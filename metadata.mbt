///|
pub(all) struct ReferenceTime {
  year : Int32
  month : Int32
  day : Int32
  hour : Int32
  minute : Int32
  second : Int32
}

///|
pub fn ReferenceTime::iso(self : ReferenceTime) -> String {
  fn digits(value : Int32, width : Int32) -> String {
    let text = value.to_string()
    "0".repeat(if text.length() < width { width - text.length() } else { 0 }) +
    text
  }
  digits(self.year, 4) +
  "-" +
  digits(self.month, 2) +
  "-" +
  digits(self.day, 2) +
  "T" +
  digits(self.hour, 2) +
  ":" +
  digits(self.minute, 2) +
  ":" +
  digits(self.second, 2) +
  "Z"
}

///|
pub(all) struct Variable {
  discipline : Int32
  category : Int32
  parameter : Int32
}

///|
pub(all) struct Surface {
  kind : Int32
  value : Double?
}

///|
pub(all) struct Metadata {
  field_index : Int32
  origin : ReferenceTime
  centre : Int32
  subcentre : Int32
  variable : Variable
  product_template : Int32
  grid_template : Int32
  packing_template : Int32
  forecast_unit : Int32?
  forecast_offset : Int32?
  first_surface : Surface?
  second_surface : Surface?
  message : Span
}

///|
fn parse_time(bytes : Bytes, start : Int32) -> ReferenceTime raise GribError {
  let year = u16(bytes, start)
  let month = byte_at(bytes, start + 2)
  let day = byte_at(bytes, start + 3)
  let hour = byte_at(bytes, start + 4)
  let minute = byte_at(bytes, start + 5)
  let second = byte_at(bytes, start + 6)
  let max_day = days_in_month(year, month)
  if year == 0 ||
    month < 1 ||
    month > 12 ||
    day < 1 ||
    day > max_day ||
    hour > 23 ||
    minute > 59 ||
    second > 60 {
    raise Invalid(start, "invalid reference time")
  }
  { year, month, day, hour, minute, second, }
}

///|
fn read_surface(bytes : Bytes, start : Int32) -> Surface? {
  let kind = byte_at(bytes, start)
  if kind == 255 {
    return None
  }
  let value = if byte_at(bytes, start + 1) == 255 ||
    unsigned(bytes, start + 2, 4) == 4294967295UL {
    None
  } else {
    let scale = signed_magnitude(bytes, start + 1, 1)
    let magnitude = unsigned(bytes, start + 2, 4)
    Some(magnitude.to_double() * pow_int(10.0, -scale))
  }
  Some({ kind, value, })
}

///|
pub fn Archive::metadata(
  self : Archive,
  index : Int32,
) -> Metadata raise GribError {
  let field = self.field(index)
  metadata_from_headers(
    field,
    index,
    self.bytes,
    field.identification.offset,
    self.bytes,
    field.grid_definition.offset,
    self.bytes,
    field.representation.offset,
    self.bytes,
    field.product_definition.offset,
  )
}

///|
fn metadata_from_headers(
  field : Field,
  index : Int32,
  identification_bytes : Bytes,
  identification : Int32,
  grid : Bytes,
  grid_start : Int32,
  representation : Bytes,
  representation_start : Int32,
  product_bytes : Bytes,
  product : Int32,
) -> Metadata raise GribError {
  if field.product_definition.length < 11 {
    raise Invalid(product, "truncated product header")
  }
  let product_template = u16(product_bytes, product + 7)
  let common = match product_template {
    0 | 1 | 2 | 8 | 11 | 12 => true
    _ => false
  }
  if common && field.product_definition.length < 34 {
    raise Invalid(product, "truncated product metadata")
  }
  {
    field_index: index,
    origin: parse_time(identification_bytes, identification + 12),
    centre: u16(identification_bytes, identification + 5),
    subcentre: u16(identification_bytes, identification + 7),
    variable: {
      discipline: field.discipline,
      category: byte_at(product_bytes, product + 9),
      parameter: byte_at(product_bytes, product + 10),
    },
    product_template,
    grid_template: u16(grid, grid_start + 12),
    packing_template: u16(representation, representation_start + 9),
    forecast_unit: if common && byte_at(product_bytes, product + 17) != 255 {
      Some(byte_at(product_bytes, product + 17))
    } else {
      None
    },
    forecast_offset: if common &&
      unsigned(product_bytes, product + 18, 4) != 4294967295UL {
      Some(signed_magnitude(product_bytes, product + 18, 4))
    } else {
      None
    },
    first_surface: if common {
      read_surface(product_bytes, product + 22)
    } else {
      None
    },
    second_surface: if common {
      read_surface(product_bytes, product + 28)
    } else {
      None
    },
    message: field.message,
  }
}
