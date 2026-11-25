///|
pub(all) struct RegularGridSpec {
  columns : Int32
  rows : Int32
  latitude_microdegrees : Int32
  longitude_microdegrees : Int32
  i_increment_microdegrees : Int32
  j_increment_microdegrees : Int32
}

///|
pub(all) struct ProductSpec {
  variable : Variable
  reference : ReferenceTime
  centre : Int32
  subcentre : Int32
  forecast_unit : Int32
  forecast_offset : Int32
  level_kind : Int32
  level_value : Int32?
}

///|
pub(all) struct IntegerPackingSpec {
  binary_scale : Int32
  decimal_scale : Int32
}

///|
priv struct BinaryWriter {
  bytes : Array[Byte]
}

///|
fn BinaryWriter::octet(self : BinaryWriter, value : Int32) -> Unit {
  self.bytes.push(value.to_byte())
}

///|
fn BinaryWriter::integer(
  self : BinaryWriter,
  value : UInt64,
  width : Int32,
) -> Unit {
  for position in 0..<width {
    let shift = (width - position - 1) * 8
    self.octet(((value >> shift) & 255UL).to_int())
  }
}

///|
fn BinaryWriter::zeros(self : BinaryWriter, count : Int32) -> Unit {
  for _ in 0..<count {
    self.octet(0)
  }
}

///|
fn BinaryWriter::literal(self : BinaryWriter, data : Bytes) -> Unit {
  for value in data {
    self.bytes.push(value)
  }
}

///|
fn BinaryWriter::section(
  self : BinaryWriter,
  identifier : Int32,
  length : Int32,
) -> Unit {
  self.integer(length.to_uint64(), 4)
  self.octet(identifier)
}

///|
fn signed_code(value : Int32, width : Int32) -> UInt64 {
  if value < 0 {
    (-value).to_uint64() | (1UL << (width * 8 - 1))
  } else {
    value.to_uint64()
  }
}

///|
fn require_unsigned(
  value : Int32,
  maximum : Int32,
  label : String,
) -> Unit raise GribError {
  if value < 0 || value > maximum {
    raise Invalid(0, label + " is outside the supported range")
  }
}

///|
fn validate_product(spec : ProductSpec) -> Unit raise GribError {
  ignore(to_seconds(spec.reference))
  require_unsigned(spec.variable.discipline, 254, "discipline")
  require_unsigned(spec.variable.category, 254, "category")
  require_unsigned(spec.variable.parameter, 254, "parameter")
  require_unsigned(spec.centre, 65534, "centre")
  require_unsigned(spec.subcentre, 65534, "subcentre")
  require_unsigned(spec.forecast_unit, 254, "forecast unit")
  require_unsigned(spec.level_kind, 255, "level kind")
  if spec.forecast_offset == -2147483648 || spec.forecast_offset == -2147483647 {
    raise Invalid(0, "forecast offset is out of range")
  }
  if spec.level_value is Some(value) && (spec.level_kind == 255 || value < 0) {
    raise Invalid(0, "level conflicts with missing-value markers")
  }
}

///|
fn validate_grid_spec(
  spec : RegularGridSpec,
  count : Int32,
) -> Unit raise GribError {
  if spec.rows <= 0 ||
    spec.columns <= 0 ||
    spec.rows.to_int64() * spec.columns.to_int64() != count.to_int64() {
    raise Invalid(0, "grid dimensions differ from the supplied sample count")
  }
  if count > 10000000 {
    raise Unsupported(0, "encoder is limited to ten million grid points")
  }
  if spec.latitude_microdegrees < -90000000 ||
    spec.latitude_microdegrees > 90000000 ||
    spec.longitude_microdegrees < -180000000 ||
    spec.longitude_microdegrees >= 360000000 {
    raise Invalid(0, "first grid coordinates are outside supported bounds")
  }
  if spec.i_increment_microdegrees <= 0 ||
    spec.i_increment_microdegrees > 360000000 ||
    spec.j_increment_microdegrees == 0 ||
    spec.j_increment_microdegrees < -180000000 ||
    spec.j_increment_microdegrees > 180000000 {
    raise Invalid(0, "grid increments are out of range")
  }
  let last_latitude = spec.latitude_microdegrees.to_int64() +
    spec.j_increment_microdegrees.to_int64() * (spec.rows - 1).to_int64()
  let longitude_span = spec.i_increment_microdegrees.to_int64() *
    (spec.columns - 1).to_int64()
  if last_latitude < -90000000L ||
    last_latitude > 90000000L ||
    longitude_span > 360000000L {
    raise Invalid(0, "last grid coordinates are outside supported bounds")
  }
}

///|
fn encoded_longitude(value : Int64) -> UInt64 {
  let normalized = (value % 360000000L + 360000000L) % 360000000L
  normalized.reinterpret_as_uint64()
}

///|
fn BinaryWriter::identification(
  self : BinaryWriter,
  spec : ProductSpec,
) -> Unit {
  self.section(1, 21)
  self.integer(spec.centre.to_uint64(), 2)
  self.integer(spec.subcentre.to_uint64(), 2)
  self.octet(2)
  self.octet(0)
  self.octet(1)
  let time = spec.reference
  self.integer(time.year.to_uint64(), 2)
  self.octet(time.month)
  self.octet(time.day)
  self.octet(time.hour)
  self.octet(time.minute)
  self.octet(time.second)
  self.octet(0)
  self.octet(1)
}

///|
fn BinaryWriter::grid(
  self : BinaryWriter,
  spec : RegularGridSpec,
  points : Int32,
) -> Unit {
  self.section(3, 72)
  self.octet(0)
  self.integer(points.to_uint64(), 4)
  self.zeros(4)
  self.octet(6)
  for _ in 0..<15 {
    self.octet(255)
  }
  self.integer(spec.columns.to_uint64(), 4)
  self.integer(spec.rows.to_uint64(), 4)
  self.integer(0UL, 4)
  self.integer(4294967295UL, 4)
  self.integer(signed_code(spec.latitude_microdegrees, 4), 4)
  self.integer(encoded_longitude(spec.longitude_microdegrees.to_int64()), 4)
  self.octet(48)
  let final_lat = spec.latitude_microdegrees +
    spec.j_increment_microdegrees * (spec.rows - 1)
  let final_lon = spec.longitude_microdegrees.to_int64() +
    spec.i_increment_microdegrees.to_int64() * (spec.columns - 1).to_int64()
  self.integer(signed_code(final_lat, 4), 4)
  self.integer(encoded_longitude(final_lon), 4)
  self.integer(spec.i_increment_microdegrees.to_uint64(), 4)
  self.integer(spec.j_increment_microdegrees.abs().to_uint64(), 4)
  self.octet(if spec.j_increment_microdegrees > 0 { 64 } else { 0 })
}

///|
fn BinaryWriter::product(self : BinaryWriter, spec : ProductSpec) -> Unit {
  self.section(4, 34)
  self.zeros(4)
  self.octet(spec.variable.category)
  self.octet(spec.variable.parameter)
  self.octet(2)
  self.octet(0)
  self.octet(0)
  self.zeros(3)
  self.octet(spec.forecast_unit)
  self.integer(signed_code(spec.forecast_offset, 4), 4)
  self.octet(spec.level_kind)
  match spec.level_value {
    Some(value) => {
      self.octet(0)
      self.integer(value.to_uint64(), 4)
    }
    None => {
      self.octet(255)
      self.integer(4294967295UL, 4)
    }
  }
  for _ in 0..<6 {
    self.octet(255)
  }
}

///|
priv struct Presence {
  points : Int32
  present : Int32
  mask : Array[Byte]
}

///|
fn[T] build_presence(values : Array[T?]) -> Presence {
  let mask = Array::make((values.length() + 7) / 8, b'\x00')
  let mut present = 0
  for i, candidate in values {
    if candidate is Some(_) {
      present += 1
      let byte = i / 8
      mask[byte] = (mask[byte].to_int() | (1 << (7 - i % 8))).to_byte()
    }
  }
  { points: values.length(), present, mask, }
}

///|
fn Presence::section_size(self : Presence) -> Int32 {
  if self.present == self.points {
    6
  } else {
    6 + self.mask.length()
  }
}

///|
fn BinaryWriter::presence(self : BinaryWriter, bitmap : Presence) -> Unit {
  let masked = bitmap.present != bitmap.points
  self.section(6, bitmap.section_size())
  self.octet(if masked { 0 } else { 255 })
  if masked {
    self.literal(Bytes::from_array(bitmap.mask[:]))
  }
}

///|
fn message_writer(
  grid : RegularGridSpec,
  product : ProductSpec,
  bitmap : Presence,
  representation_length : Int32,
  data_length : Int32,
) -> BinaryWriter {
  let writer : BinaryWriter = { bytes: [], }
  let length = 16 +
    21 +
    72 +
    34 +
    representation_length +
    bitmap.section_size() +
    data_length +
    4
  writer.literal(b"GRIB")
  writer.zeros(2)
  writer.octet(product.variable.discipline)
  writer.octet(2)
  writer.integer(length.to_uint64(), 8)
  writer.identification(product)
  writer.grid(grid, bitmap.points)
  writer.product(product)
  writer
}

///|
fn bit_width(value : UInt64) -> Int32 {
  let mut remaining = value
  let mut width = 0
  while remaining != 0UL {
    width += 1
    remaining = remaining >> 1
  }
  width
}

///|
priv struct BitWriter {
  target : BinaryWriter
  mut pending : UInt64
  mut bits : Int32
}

///|
fn BitWriter::append(self : BitWriter, value : UInt64, width : Int32) -> Unit {
  self.pending = (self.pending << width) | value
  self.bits += width
  while self.bits >= 8 {
    self.bits -= 8
    self.target.octet(((self.pending >> self.bits) & 255UL).to_int())
  }
  self.pending = self.pending & ((1UL << self.bits) - 1UL)
}

///|
fn BitWriter::finish(self : BitWriter) -> Unit {
  if self.bits > 0 {
    self.target.octet((self.pending << (8 - self.bits)).to_int())
  }
}

///|
pub fn encode_simple(
  grid : RegularGridSpec,
  product : ProductSpec,
  scales : IntegerPackingSpec,
  values : Array[UInt32?],
) -> Bytes raise GribError {
  validate_grid_spec(grid, values.length())
  validate_product(product)
  if scales.binary_scale < -1074 ||
    scales.binary_scale > 1023 ||
    scales.decimal_scale < -308 ||
    scales.decimal_scale > 308 {
    raise Invalid(0, "scales are out of range")
  }
  let bitmap = build_presence(values)
  let mut largest = 0UL
  for candidate in values {
    if candidate is Some(value) && value.to_uint64() > largest {
      largest = value.to_uint64()
    }
  }
  let width = bit_width(largest)
  let data_length = 5 +
    ((bitmap.present.to_int64() * width.to_int64() + 7L) / 8L).to_int()
  let writer = message_writer(grid, product, bitmap, 21, data_length)
  writer.section(5, 21)
  writer.integer(bitmap.present.to_uint64(), 4)
  writer.zeros(6)
  writer.integer(signed_code(scales.binary_scale, 2), 2)
  writer.integer(signed_code(scales.decimal_scale, 2), 2)
  writer.octet(width)
  writer.octet(0)
  writer.presence(bitmap)
  writer.section(7, data_length)
  let bits : BitWriter = { target: writer, pending: 0UL, bits: 0, }
  for candidate in values {
    if candidate is Some(value) {
      bits.append(value.to_uint64(), width)
    }
  }
  bits.finish()
  writer.literal(b"7777")
  Bytes::from_array(writer.bytes[:])
}

///|
pub fn encode_ieee(
  grid : RegularGridSpec,
  product : ProductSpec,
  values : Array[Double?],
) -> Bytes raise GribError {
  validate_grid_spec(grid, values.length())
  validate_product(product)
  let bitmap = build_presence(values)
  let data_length = 5 + bitmap.present * 8
  let writer = message_writer(grid, product, bitmap, 12, data_length)
  writer.section(5, 12)
  writer.integer(bitmap.present.to_uint64(), 4)
  writer.integer(4UL, 2)
  writer.octet(2)
  writer.presence(bitmap)
  writer.section(7, data_length)
  for i, candidate in values {
    if candidate is Some(value) {
      if value.is_nan() || value.is_inf() {
        raise Invalid(i, "cannot encode a nonfinite value")
      }
      writer.integer(value.reinterpret_as_uint64(), 8)
    }
  }
  writer.literal(b"7777")
  Bytes::from_array(writer.bytes[:])
}
