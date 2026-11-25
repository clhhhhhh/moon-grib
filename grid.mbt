///|
pub struct Grid {
  columns : Int32
  rows : Int32
  points : Int32
  first_latitude : Double
  first_longitude : Double
  latitude_step : Double
  priv latitudes : Array[Double]?
  longitude_step : Double
  column_major : Bool
  alternating : Bool
}

///|
pub fn Archive::grid(self : Archive, index : Int32) -> Grid raise GribError {
  parse_grid(self.bytes, self.field(index).grid_definition)
}

///|
fn parse_grid(bytes : Bytes, span : Span) -> Grid raise GribError {
  let at = span.offset
  let template = u16(bytes, at + 12)
  if template != 0 && template != 40 {
    raise Unsupported(
      at + 12,
      "unsupported grid template 3." + template.to_string(),
    )
  }
  if span.length < 72 {
    raise Invalid(at, "truncated regular latitude/longitude grid")
  }
  if byte_at(bytes, at + 5) != 0 || byte_at(bytes, at + 10) != 0 {
    raise Unsupported(
      at + 5,
      "externally specified or reduced grids are unsupported",
    )
  }
  let nx = bounded_int(unsigned(bytes, at + 30, 4), at + 30)
  let ny = bounded_int(unsigned(bytes, at + 34, 4), at + 34)
  let points = bounded_int(unsigned(bytes, at + 6, 4), at + 6)
  if nx == 0 || ny == 0 || nx.to_int64() * ny.to_int64() != points.to_int64() {
    raise Invalid(at + 6, "grid dimensions disagree with point count")
  }
  let basic = unsigned(bytes, at + 38, 4)
  let divisions = unsigned(bytes, at + 42, 4)
  let unit = if basic == 0UL {
    0.000001
  } else {
    if basic == 4294967295UL || divisions == 0UL || divisions == 4294967295UL {
      raise Invalid(at + 38, "invalid angular unit")
    }
    basic.to_double() / divisions.to_double()
  }
  let scan = byte_at(bytes, at + 71)
  if (scan & 15) != 0 {
    raise Unsupported(at + 71, "staggered scan modes are unsupported")
  }
  let i_sign = if (scan & 128) != 0 { -1.0 } else { 1.0 }
  let j_sign = if (scan & 64) != 0 { 1.0 } else { -1.0 }
  let first_latitude = signed_magnitude(bytes, at + 46, 4).to_double() * unit
  let first_longitude = signed_magnitude(bytes, at + 50, 4).to_double() * unit
  let latitude_step = if template == 0 {
    increment(bytes, at + 67, ny, unit) * j_sign
  } else {
    0.0
  }
  let latitudes = if template == 40 {
    let parallels = bounded_int(unsigned(bytes, at + 67, 4), at + 67)
    let last_latitude = signed_magnitude(bytes, at + 55, 4).to_double() * unit
    let endpoint_row = if (scan & 32) != 0 && (scan & 16) != 0 && nx % 2 == 0 {
      0
    } else {
      ny - 1
    }
    Some(
      select_gaussian_rows(
        parallels,
        ny,
        first_latitude,
        last_latitude,
        j_sign > 0.0,
        endpoint_row,
        unit + 0.0000000001,
        at + 67,
      ),
    )
  } else {
    None
  }
  let declared_increment = increment(bytes, at + 63, nx, unit)
  let last_column_is_first = (scan & 32) == 0 && (scan & 16) != 0 && ny % 2 == 0
  let longitude_step = if template == 40 && nx > 1 && !last_column_is_first {
    let last = signed_magnitude(bytes, at + 59, 4).to_double() * unit
    let extent = (last - first_longitude) * i_sign
    let span = if extent < 0.0 { extent + 360.0 } else { extent }
    if span > 0.0 {
      span / (nx - 1).to_double() * i_sign
    } else {
      declared_increment * i_sign
    }
  } else {
    declared_increment * i_sign
  }
  let final_latitude = first_latitude + (ny - 1).to_double() * latitude_step
  if first_latitude.abs() > 90.000001 ||
    final_latitude.abs() > 90.000001 ||
    first_longitude.abs() > 360.000001 ||
    (nx - 1).to_double() * longitude_step.abs() > 360.000001 {
    raise Invalid(at + 46, "grid coordinates are outside geographic bounds")
  }
  {
    columns: nx,
    rows: ny,
    points,
    first_latitude,
    first_longitude,
    latitude_step,
    latitudes,
    longitude_step,
    column_major: (scan & 32) != 0,
    alternating: (scan & 16) != 0,
  }
}

///|
fn increment(
  bytes : Bytes,
  at : Int32,
  dimension : Int32,
  unit : Double,
) -> Double raise GribError {
  if dimension == 1 {
    return 0.0
  }
  let raw = unsigned(bytes, at, 4)
  if raw == 0UL || raw == 4294967295UL {
    raise Unsupported(at, "grid requires explicit positive increments")
  }
  raw.to_double() * unit
}

///|
fn normalize_longitude(value : Double) -> Double {
  value - ((value + 180.0) / 360.0).floor() * 360.0
}

///|
pub fn Grid::longitude(self : Grid, column : Int32) -> Double {
  normalize_longitude(
    self.first_longitude + column.to_double() * self.longitude_step,
  )
}

///|
pub fn Grid::latitude(self : Grid, row : Int32) -> Double {
  match self.latitudes {
    Some(axis) => axis[row]
    None => self.first_latitude + row.to_double() * self.latitude_step
  }
}

///|
fn Grid::scan_index(self : Grid, row : Int32, column : Int32) -> Int32 {
  if self.column_major {
    let within = if self.alternating && column % 2 != 0 {
      self.rows - 1 - row
    } else {
      row
    }
    column * self.rows + within
  } else {
    let within = if self.alternating && row % 2 != 0 {
      self.columns - 1 - column
    } else {
      column
    }
    row * self.columns + within
  }
}
