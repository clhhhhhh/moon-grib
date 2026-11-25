///|
pub struct Raster {
  rows : Int32
  columns : Int32
  north : Double
  west : Double
  latitude_spacing : Double
  longitude_spacing : Double
  priv values : Array[Double?]
}

///|
pub fn Raster::value(
  self : Raster,
  row : Int32,
  column : Int32,
) -> Double? raise GribError {
  if row < 0 || row >= self.rows || column < 0 || column >= self.columns {
    raise Invalid(0, "raster coordinates are out of bounds")
  }
  self.values[row * self.columns + column]
}

///|
pub fn Raster::latitude(self : Raster, row : Int32) -> Double {
  self.north - row.to_double() * self.latitude_spacing
}

///|
pub fn Raster::longitude(self : Raster, column : Int32) -> Double {
  self.west + column.to_double() * self.longitude_spacing
}

///|
pub fn DecodedField::raster(
  self : DecodedField,
  bounds : Bounds,
  max_points~ : Int32 = 1000000,
) -> Raster raise GribError {
  if self.grid.latitudes is Some(_) {
    raise Unsupported(0, "raster export requires uniformly spaced latitudes")
  }
  let (row_span, column_spans) = window_ranges(self.grid, bounds, max_points)
  if row_span.start == row_span.end || column_spans.length() == 0 {
    raise Invalid(0, "selected raster contains no points")
  }
  if column_spans.length() != 1 {
    raise Unsupported(
      0, "raster export requires a contiguous longitude interval",
    )
  }
  let columns = column_spans[0]
  let count = columns.end - columns.start
  let height = row_span.end - row_span.start
  let reverse_rows = self.grid.latitude_step > 0.0
  let reverse_columns = self.grid.longitude_step < 0.0
  let first_row = if reverse_rows { row_span.end - 1 } else { row_span.start }
  let first_column = if reverse_columns {
    columns.end - 1
  } else {
    columns.start
  }
  let west = self.grid.longitude(first_column)
  let width = (count - 1).to_double() * self.grid.longitude_step.abs()
  if west + width > 180.0 + 0.000000001 {
    raise Unsupported(
      0, "raster export cannot represent a wrapped longitude axis",
    )
  }
  let values : Array[Double?] = []
  for y in 0..<height {
    let row = if reverse_rows { first_row - y } else { first_row + y }
    for x in 0..<count {
      let column = if reverse_columns {
        first_column - x
      } else {
        first_column + x
      }
      values.push(self.at(row, column).value)
    }
  }
  {
    rows: height,
    columns: count,
    north: self.grid.latitude(first_row),
    west,
    latitude_spacing: self.grid.latitude_step.abs(),
    longitude_spacing: self.grid.longitude_step.abs(),
    values,
  }
}

///|
fn raster_line(out : StringBuilder, label : String, value : String) -> Unit {
  out.write_string(label)
  out.write_char(' ')
  out.write_string(value)
  out.write_char('\n')
}

///|
pub fn Raster::ascii_grid(
  self : Raster,
  missing_value~ : Double = -9999.0,
) -> String raise GribError {
  let cell = self.latitude_spacing
  if cell == 0.0 || (cell - self.longitude_spacing).abs() > 0.000000001 {
    raise Unsupported(0, "ASCII grid export requires square cells")
  }
  if missing_value.is_nan() || missing_value.is_inf() {
    raise Invalid(0, "missing-data sentinel must be finite")
  }
  if self.values.any(value => value == Some(missing_value)) {
    raise Invalid(0, "missing-data sentinel collides with a valid datum")
  }
  let out = StringBuilder()
  raster_line(out, "ncols", self.columns.to_string())
  raster_line(out, "nrows", self.rows.to_string())
  raster_line(out, "xllcenter", self.west.to_string())
  raster_line(out, "yllcenter", self.latitude(self.rows - 1).to_string())
  raster_line(out, "cellsize", cell.to_string())
  raster_line(out, "NODATA_value", missing_value.to_string())
  for row in 0..<self.rows {
    for col in 0..<self.columns {
      if col > 0 {
        out.write_char(' ')
      }
      out.write_string(
        self.values[row * self.columns + col]
        .unwrap_or(missing_value)
        .to_string(),
      )
    }
    out.write_char('\n')
  }
  out.to_string()
}

///|
pub fn Raster::pgm(self : Raster) -> String {
  let mut lower : Double? = None
  let mut upper : Double? = None
  for candidate in self.values {
    if candidate is Some(value) {
      if lower is None || value < lower.unwrap_or(value) {
        lower = Some(value)
      }
      if upper is None || value > upper.unwrap_or(value) {
        upper = Some(value)
      }
    }
  }
  let minimum = lower.unwrap_or(0.0)
  let maximum = upper.unwrap_or(0.0)
  let scale = if maximum.abs() > minimum.abs() {
    maximum.abs()
  } else {
    minimum.abs()
  }
  let out = StringBuilder()
  out.write_string("P2\n")
  out.write_string(
    self.columns.to_string() + " " + self.rows.to_string() + "\n255\n",
  )
  for row in 0..<self.rows {
    for col in 0..<self.columns {
      if col > 0 {
        out.write_char(' ')
      }
      let shade = match self.values[row * self.columns + col] {
        None => 0
        Some(_) if minimum == maximum => 128
        Some(value) => {
          let fraction = (value / scale - minimum / scale) /
            (maximum / scale - minimum / scale)
          1 + (fraction * 254.0).round().to_int()
        }
      }
      out.write_string(shade.to_string())
    }
    out.write_char('\n')
  }
  out.to_string()
}
