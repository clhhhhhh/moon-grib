///|
pub(all) struct AreaStatistics {
  points : Int32
  present : Int32
  missing : Int32
  footprint_steradians : Double
  covered_steradians : Double
  weighted_mean : Double?
}

///|
fn latitude_edge(grid : Grid, row : Int32, before : Bool) -> Double {
  let point = grid.latitude(row)
  let other = if before { row - 1 } else { row + 1 }
  if other >= 0 && other < grid.rows {
    return (point + grid.latitude(other)) * 0.5
  }
  if grid.rows == 1 {
    return point
  }
  let inside = if before { row + 1 } else { row - 1 }
  let extrapolated = point + (point - grid.latitude(inside)) * 0.5
  if extrapolated > 90.0 {
    90.0
  } else if extrapolated < -90.0 {
    -90.0
  } else {
    extrapolated
  }
}

///|
fn Grid::row_area(self : Grid, row : Int32) -> Double {
  let radians = PI / 180.0
  let first = latitude_edge(self, row, true) * radians
  let last = latitude_edge(self, row, false) * radians
  (@math.sin(first) - @math.sin(last)).abs() *
  self.longitude_step.abs() *
  radians
}

///|
pub fn DecodedField::area_statistics(
  self : DecodedField,
  bounds : Bounds,
  max_points~ : Int32 = 1000000,
) -> AreaStatistics raise GribError {
  if self.grid.columns < 2 || self.grid.rows < 2 {
    raise Unsupported(0, "area weighting requires at least two points per axis")
  }
  let (rows, columns) = window_ranges(self.grid, bounds, max_points)
  let mut points = 0
  let mut present = 0
  let mut footprint = 0.0
  let mut covered = 0.0
  let mut mean = 0.0
  for row in rows.start..<rows.end {
    let weight = self.grid.row_area(row)
    for span in columns {
      for column in span.start..<span.end {
        points += 1
        footprint += weight
        if self.at(row, column).value is Some(value) {
          present += 1
          covered += weight
          if covered > 0.0 {
            let fraction = weight / covered
            mean = mean * (1.0 - fraction) + value * fraction
          }
        }
      }
    }
  }
  {
    points,
    present,
    missing: points - present,
    footprint_steradians: footprint,
    covered_steradians: covered,
    weighted_mean: if covered > 0.0 && !mean.is_nan() && !mean.is_inf() {
      Some(mean)
    } else {
      None
    },
  }
}

///|
pub fn AreaStatistics::json(self : AreaStatistics) -> Json {
  Json::object(
    Map([
      ("points", number(self.points)),
      ("present", number(self.present)),
      ("missing", number(self.missing)),
      ("footprint_steradians", Json::number(self.footprint_steradians)),
      ("covered_steradians", Json::number(self.covered_steradians)),
      ("weighted_mean", optional_real(self.weighted_mean)),
    ]),
  )
}
