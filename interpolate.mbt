///|
pub(all) struct Position {
  latitude : Double
  longitude : Double
}

///|
pub(all) enum MissingPolicy {
  RequireAll
  Renormalize
}

///|
pub(all) enum InterpolationMethod {
  Nearest
  Bilinear
}

///|
pub(all) struct EstimatedValue {
  position : Position
  value : Double?
  contributing_points : Int32
}

///|
priv struct Bracket {
  lower : Int32
  upper : Int32
  weight : Double
}

///|
fn assert_position(position : Position) -> Unit raise GribError {
  if !(position.latitude >= -90.0 &&
    position.latitude <= 90.0 &&
    position.longitude >= -180.0 &&
    position.longitude <= 180.0) {
    raise Invalid(0, "invalid sampling coordinate")
  }
}

///|
fn axis_bracket(
  value : Double,
  length : Int32,
  coordinate : (Int32) -> Double,
) -> Bracket? {
  let reversed = coordinate(length - 1) < coordinate(0)
  let at = index => {
    coordinate(if reversed { length - 1 - index } else { index })
  }
  let index = i => if reversed { length - 1 - i } else { i }
  if value < at(0) - 0.000000001 || value > at(length - 1) + 0.000000001 {
    return None
  }
  let upper = axis_edge(at, length, value, false)
  if upper == 0 {
    return Some({ lower: index(0), upper: index(0), weight: 0.0, })
  }
  let previous = upper - 1
  if upper == length {
    return Some({ lower: index(previous), upper: index(previous), weight: 0.0, })
  }
  let a = at(previous)
  let b = at(upper)
  if (b - value).abs() < 0.000000001 {
    return Some({ lower: index(upper), upper: index(upper), weight: 0.0, })
  }
  Some({
    lower: index(previous),
    upper: index(upper),
    weight: (value - a) / (b - a),
  })
}

///|
fn Grid::longitude_bracket(self : Grid, longitude : Double) -> Bracket? {
  let coord : (Int32) -> Double = index => {
    self.first_longitude + self.longitude_step * index.to_double()
  }
  for shift in -2..<3 {
    let unwrapped = longitude + shift.to_double() * 360.0
    if axis_bracket(unwrapped, self.columns, coord) is Some(bracket) {
      return Some(bracket)
    }
  }
  let step = self.longitude_step.abs()
  if self.columns == 1 ||
    (step * self.columns.to_double() - 360.0).abs() > 0.000001 {
    return None
  }
  let origin = coord(0)
  let direction = if self.longitude_step < 0.0 { -1.0 } else { 1.0 }
  let distance = (longitude - origin) * direction
  let wrapped = distance - (distance / 360.0).floor() * 360.0
  let last = coord(self.columns - 1)
  let at = (last - origin) * direction
  if wrapped > at {
    Some({ lower: self.columns - 1, upper: 0, weight: (wrapped - at) / step, })
  } else {
    None
  }
}

///|
pub fn DecodedField::estimate(
  self : DecodedField,
  position : Position,
  interpolation~ : InterpolationMethod = Nearest,
  missing~ : MissingPolicy = RequireAll,
) -> EstimatedValue raise GribError {
  assert_position(position)
  guard axis_bracket(position.latitude, self.grid.rows, row => {
      self.grid.latitude(row)
    })
    is Some(y) &&
    self.grid.longitude_bracket(position.longitude) is Some(x) else {
    return { position, value: None, contributing_points: 0, }
  }
  match interpolation {
    Nearest => {
      let row = if y.weight <= 0.5 { y.lower } else { y.upper }
      let column = if x.weight <= 0.5 { x.lower } else { x.upper }
      let value = self.at(row, column).value
      {
        position,
        value,
        contributing_points: if value is Some(_) {
          1
        } else {
          0
        },
      }
    }
    Bilinear => self.interpolate(position, x, y, missing)
  }
}

///|
fn DecodedField::interpolate(
  self : DecodedField,
  position : Position,
  x : Bracket,
  y : Bracket,
  policy : MissingPolicy,
) -> EstimatedValue raise GribError {
  let mut weight_sum = 0.0
  let mut value_sum = 0.0
  let mut contributors = 0
  let mut missing = false
  for (row, y_weight) in [(y.lower, 1.0 - y.weight), (y.upper, y.weight)] {
    for (column, x_weight) in [(x.lower, 1.0 - x.weight), (x.upper, x.weight)] {
      let weight = x_weight * y_weight
      if weight <= 0.0 {
        continue
      }
      match self.at(row, column).value {
        Some(value) => {
          value_sum += value * weight
          weight_sum += weight
          contributors += 1
        }
        None => missing = true
      }
    }
  }
  let estimate = if weight_sum == 0.0 || (missing && policy is RequireAll) {
    None
  } else {
    let result = value_sum / weight_sum
    if result.is_nan() || result.is_inf() {
      None
    } else {
      Some(result)
    }
  }
  { position, value: estimate, contributing_points: contributors, }
}

///|
pub fn DecodedField::profile(
  self : DecodedField,
  from : Position,
  to : Position,
  points : Int32,
  interpolation~ : InterpolationMethod = Nearest,
  missing~ : MissingPolicy = RequireAll,
) -> Array[EstimatedValue] raise GribError {
  assert_position(from)
  assert_position(to)
  if points < 2 || points > 100000 {
    raise Invalid(0, "profile requires 2 through 100000 points")
  }
  let dlat = to.latitude - from.latitude
  let dlon = normalize_longitude(to.longitude - from.longitude)
  let result : Array[EstimatedValue] = []
  for i in 0..<points {
    let ratio = i.to_double() / (points - 1).to_double()
    let position = if i + 1 == points {
      to
    } else {
      {
        latitude: from.latitude + ratio * dlat,
        longitude: normalize_longitude(from.longitude + ratio * dlon),
      }
    }
    result.push(self.estimate(position, interpolation~, missing~))
  }
  result
}

///|
pub fn EstimatedValue::json(self : EstimatedValue) -> Json {
  Json::object(
    Map([
      ("latitude", Json::number(self.position.latitude)),
      ("longitude", Json::number(self.position.longitude)),
      ("value", optional_real(self.value)),
      ("contributing_points", number(self.contributing_points)),
    ]),
  )
}
