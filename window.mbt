///|
pub(all) struct Bounds {
  west : Double
  south : Double
  east : Double
  north : Double
}

///|
pub(all) struct Sample {
  row : Int32
  column : Int32
  latitude : Double
  longitude : Double
  value : Double?
}

///|
pub struct DecodedField {
  bytes : Bytes
  grid : Grid
  priv bitmap : Bitmap?
  priv packing : Packing
  priv grouped : GroupedPacking?
  priv difference : DifferenceIndex?
  priv ieee_width : Int32
  payload : Int32
}

///|
pub fn Archive::decode(
  self : Archive,
  index : Int32,
) -> DecodedField raise GribError {
  let field = self.field(index)
  let grid = parse_grid(self.bytes, field.grid_definition)
  let template = u16(self.bytes, field.representation.offset + 9)
  let (packing, ieee_width) = if template == 4 {
    let (width, count) = ieee_precision(
      self.bytes,
      field.representation,
      field.data.length,
    )
    (ieee_packing(width, count), width)
  } else {
    (parse_packing(self.bytes, field), 0)
  }
  let payload = field.data.offset + 5
  let bitmap = parse_bitmap(self.bytes, field, grid.points, packing.count)
  let (grouped, difference) = match template {
    2 => (Some(parse_groups(self.bytes, field, packing, 0)), None)
    3 => {
      let (spec, prefix) = parse_difference(self.bytes, field)
      let groups = parse_groups(self.bytes, field, packing, prefix)
      (
        Some(groups),
        Some(
          build_difference_index(
            spec,
            groups,
            self.bytes,
            payload,
            packing.count,
          ),
        ),
      )
    }
    _ => (None, None)
  }
  {
    bytes: self.bytes,
    grid,
    bitmap,
    packing,
    grouped,
    difference,
    ieee_width,
    payload,
  }
}

///|
pub fn DecodedField::dimensions(self : DecodedField) -> (Int32, Int32) {
  (self.grid.rows, self.grid.columns)
}

///|
pub fn DecodedField::at(
  self : DecodedField,
  row : Int32,
  column : Int32,
) -> Sample raise GribError {
  if row < 0 ||
    row >= self.grid.rows ||
    column < 0 ||
    column >= self.grid.columns {
    raise Invalid(self.payload, "grid index out of bounds")
  }
  self.at_cursor(row, column, None)
}

///|
fn DecodedField::at_cursor(
  self : DecodedField,
  row : Int32,
  column : Int32,
  cursor : DifferenceCursor?,
) -> Sample raise GribError {
  let scan = self.grid.scan_index(row, column)
  let ordinal = match self.bitmap {
    Some(bitmap) => bitmap.ordinal(self.bytes, scan)
    None => Some(scan)
  }
  let value = match ordinal {
    Some(index) if self.ieee_width > 0 =>
      Some(
        ieee_value(
          self.bytes,
          self.payload + index * self.ieee_width,
          self.ieee_width,
        ),
      )
    Some(index) => {
      let integer = match self.grouped {
        None =>
          Some(
            packed_integer(self.bytes, self.payload, index, self.packing.width),
          )
        Some(groups) =>
          match self.difference {
            Some(index_data) =>
              index_data.value(
                groups,
                self.bytes,
                self.payload,
                index,
                match cursor {
                  Some(state) => state
                  None => difference_cursor()
                },
              )
            None => groups.value(self.bytes, self.payload, index)
          }
      }
      match integer {
        Some(value) => Some(decode_value(self.payload, self.packing, value))
        None => None
      }
    }
    None => None
  }
  {
    row,
    column,
    latitude: self.grid.latitude(row),
    longitude: self.grid.longitude(column),
    value,
  }
}

///|
fn validate_bounds(bounds : Bounds) -> Unit raise GribError {
  if !(bounds.south >= -90.0 &&
    bounds.south <= bounds.north &&
    bounds.north <= 90.0 &&
    bounds.west >= -180.0 &&
    bounds.west <= 180.0 &&
    bounds.east >= -180.0 &&
    bounds.east <= 180.0) {
    raise Invalid(0, "invalid geographic window")
  }
}

///|
pub fn DecodedField::window(
  self : DecodedField,
  bounds : Bounds,
  max_points~ : Int32 = 1000000,
) -> Array[Sample] raise GribError {
  let result : Array[Sample] = []
  self.visit_window(bounds, sample => result.push(sample), max_points~)
  result
}

///|
pub fn DecodedField::visit_window(
  self : DecodedField,
  bounds : Bounds,
  emit : (Sample) -> Unit,
  max_points~ : Int32 = 1000000,
) -> Unit raise GribError {
  let (rows, columns) = window_ranges(self.grid, bounds, max_points)
  let cursor = self.difference.map(_ => difference_cursor())
  for row in rows.start..<rows.end {
    for interval in columns {
      for column in interval.start..<interval.end {
        emit(self.at_cursor(row, column, cursor))
      }
    }
  }
}

///|
fn window_ranges(
  grid : Grid,
  bounds : Bounds,
  max_points : Int32,
) -> (IndexRange, Array[IndexRange]) raise GribError {
  validate_bounds(bounds)
  if max_points < 0 {
    raise Invalid(0, "point limit must be nonnegative")
  }
  let columns = longitude_ranges(grid, bounds)
  let rows = latitude_range(grid, bounds)
  if columns.is_empty() {
    return ({ start: rows.start, end: rows.start, }, columns)
  }
  let mut width = 0
  for interval in columns {
    width += interval.end - interval.start
  }
  let count = width.to_int64() * (rows.end - rows.start).to_int64()
  if count > max_points.to_int64() {
    raise Unsupported(0, "window exceeds point limit")
  }
  (rows, columns)
}
