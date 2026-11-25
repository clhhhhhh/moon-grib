///|
pub(all) struct WindowDifference {
  evaluated : Int32
  paired : Int32
  both_missing : Int32
  left_only : Int32
  right_only : Int32
  above_tolerance : Int32
  mean_delta : Double?
  mean_absolute_error : Double?
  maximum_absolute_error : Double?
}

///|
priv struct DifferenceMoments {
  mut evaluated : Int32
  mut paired : Int32
  mut both_missing : Int32
  mut left_only : Int32
  mut right_only : Int32
  mut above_tolerance : Int32
  mut mean_delta : Double
  mut mean_abs : Double
  mut maximum : Double
}

///|
fn DifferenceMoments::add(
  self : DifferenceMoments,
  left : Double?,
  right : Double?,
  tolerance : Double,
  at : Int32,
) -> Unit raise GribError {
  self.evaluated += 1
  match (left, right) {
    (Some(a), Some(b)) => {
      let delta = b - a
      if delta.is_inf() {
        raise Unsupported(at, "comparison overflows Double")
      }
      let magnitude = delta.abs()
      self.paired += 1
      if magnitude > tolerance {
        self.above_tolerance += 1
      }
      if magnitude > self.maximum {
        self.maximum = magnitude
      }
      let weight = 1.0 / self.paired.to_double()
      self.mean_delta = self.mean_delta * (1.0 - weight) + delta * weight
      self.mean_abs += (magnitude - self.mean_abs) * weight
    }
    (Some(_), None) => self.left_only += 1
    (None, Some(_)) => self.right_only += 1
    (None, None) => self.both_missing += 1
  }
}

///|
fn DifferenceMoments::finish(self : DifferenceMoments) -> WindowDifference {
  {
    evaluated: self.evaluated,
    paired: self.paired,
    both_missing: self.both_missing,
    left_only: self.left_only,
    right_only: self.right_only,
    above_tolerance: self.above_tolerance,
    mean_delta: if self.paired > 0 {
      Some(self.mean_delta)
    } else {
      None
    },
    mean_absolute_error: if self.paired > 0 {
      Some(self.mean_abs)
    } else {
      None
    },
    maximum_absolute_error: if self.paired > 0 {
      Some(self.maximum)
    } else {
      None
    },
  }
}

///|
fn assert_matching_grid(left : Grid, right : Grid) -> Unit raise GribError {
  if left.rows != right.rows || left.columns != right.columns {
    raise Invalid(0, "comparison requires equal grid dimensions")
  }
  for row in 0..<left.rows {
    if (left.latitude(row) - right.latitude(row)).abs() > 0.000000001 {
      raise Invalid(0, "comparison requires identical latitude axes")
    }
  }
  for column in 0..<left.columns {
    if normalize_longitude(left.longitude(column) - right.longitude(column)).abs() >
      0.000000001 {
      raise Invalid(0, "comparison requires identical longitude axes")
    }
  }
}

///|
pub fn DecodedField::compare_window(
  self : DecodedField,
  other : DecodedField,
  bounds : Bounds,
  tolerance~ : Double = 0.0,
  max_points~ : Int32 = 1000000,
) -> WindowDifference raise GribError {
  if !(tolerance >= 0.0) || tolerance.is_inf() {
    raise Invalid(0, "comparison tolerance must be finite and nonnegative")
  }
  assert_matching_grid(self.grid, other.grid)
  let (rows, columns) = window_ranges(self.grid, bounds, max_points)
  let moments : DifferenceMoments = {
    evaluated: 0,
    paired: 0,
    both_missing: 0,
    left_only: 0,
    right_only: 0,
    above_tolerance: 0,
    mean_delta: 0.0,
    mean_abs: 0.0,
    maximum: 0.0,
  }
  for row in rows.start..<rows.end {
    for interval in columns {
      for column in interval.start..<interval.end {
        let lhs = self.at(row, column)
        let rhs = other.at(row, column)
        moments.add(lhs.value, rhs.value, tolerance, self.payload)
      }
    }
  }
  moments.finish()
}

///|
pub fn WindowDifference::json(self : WindowDifference) -> Json {
  Json::object(
    Map([
      ("evaluated", number(self.evaluated)),
      ("paired", number(self.paired)),
      ("both_missing", number(self.both_missing)),
      ("left_only", number(self.left_only)),
      ("right_only", number(self.right_only)),
      ("above_tolerance", number(self.above_tolerance)),
      ("mean_delta", optional_real(self.mean_delta)),
      ("mean_absolute_error", optional_real(self.mean_absolute_error)),
      ("maximum_absolute_error", optional_real(self.maximum_absolute_error)),
    ]),
  )
}
