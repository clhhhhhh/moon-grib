///|
const PI : Double = 3.14159265358979323846

///|
fn legendre(order : Int32, x : Double) -> (Double, Double) {
  let mut previous = 1.0
  let mut current = x
  for index in 2..<(order + 1) {
    let n = index.to_double()
    let next = ((2.0 * n - 1.0) * x * current - (n - 1.0) * previous) / n
    previous = current
    current = next
  }
  (previous, current)
}

///|
fn gaussian_latitudes(
  parallels : Int32,
  offset : Int32,
) -> Array[Double] raise GribError {
  if parallels <= 0 || parallels > 2048 {
    raise Unsupported(
      offset, "Gaussian grids require 1 through 2048 parallels per hemisphere",
    )
  }
  let order = parallels * 2
  let result = Array::make(order, 0.0)
  for index in 0..<parallels {
    let theta = PI * (index.to_double() + 0.75) / (order.to_double() + 0.5)
    let mut x = @math.cos(theta)
    let mut converged = false
    for _ in 0..<20 {
      let (previous, current) = legendre(order, x)
      let derivative = order.to_double() *
        (previous - x * current) /
        (1.0 - x * x)
      let delta = current / derivative
      x -= delta
      if delta.abs() <= 0.000000000000002 {
        converged = true
        break
      }
    }
    if !converged || x.is_nan() || x <= 0.0 || x >= 1.0 {
      raise Invalid(offset, "failed to compute Gaussian parallels")
    }
    let latitude = @math.asin(x) * 180.0 / PI
    result[index] = latitude
    result[order - 1 - index] = -latitude
  }
  result
}

///|
fn select_gaussian_rows(
  parallels : Int32,
  rows : Int32,
  first : Double,
  last : Double,
  ascending : Bool,
  endpoint_row : Int32,
  tolerance : Double,
  offset : Int32,
) -> Array[Double] raise GribError {
  let axis = gaussian_latitudes(parallels, offset)
  let mut start = -1
  for index, value in axis {
    if (value - first).abs() <= tolerance {
      start = index
      break
    }
  }
  let direction = if ascending { -1 } else { 1 }
  let stop = start.to_int64() + (rows - 1).to_int64() * direction.to_int64()
  if start < 0 || stop < 0L || stop >= axis.length().to_int64() {
    raise Invalid(offset, "Gaussian subset falls outside its latitude axis")
  }
  if (axis[start + endpoint_row * direction] - last).abs() > tolerance {
    raise Invalid(offset, "Gaussian last latitude disagrees with the scan")
  }
  let selected : Array[Double] = []
  for row in 0..<rows {
    selected.push(axis[start + row * direction])
  }
  selected
}
