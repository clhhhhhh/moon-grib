///|
pub(all) struct TargetGrid {
  rows : Int32
  columns : Int32
  north : Double
  west : Double
  latitude_spacing : Double
  longitude_spacing : Double
}

///|
pub(all) struct ResamplingResult {
  raster : Raster
  present : Int32
  missing : Int32
  outside_or_unsampled : Int32
}

///|
fn validate_target(
  target : TargetGrid,
  maximum : Int32,
) -> Unit raise GribError {
  if target.rows <= 0 || target.columns <= 0 || maximum < 0 {
    raise Invalid(0, "output raster dimensions and sample limit are invalid")
  }
  if target.rows.to_int64() * target.columns.to_int64() > maximum.to_int64() {
    raise Unsupported(0, "output raster exceeds the sample limit")
  }
  if !(target.latitude_spacing > 0.0 &&
    target.latitude_spacing <= 180.0 &&
    target.longitude_spacing > 0.0 &&
    target.longitude_spacing <= 360.0) {
    raise Invalid(0, "target increments must be finite and positive")
  }
  let east = target.west +
    (target.columns - 1).to_double() * target.longitude_spacing
  let south = target.north -
    (target.rows - 1).to_double() * target.latitude_spacing
  if !(target.north <= 90.0 &&
    south >= -90.0 &&
    target.west >= -180.0 &&
    east <= 180.0) {
    raise Invalid(
      0, "target raster falls outside an unwrapped geographic window",
    )
  }
}

///|
pub fn DecodedField::resample(
  self : DecodedField,
  target : TargetGrid,
  interpolation~ : InterpolationMethod = Bilinear,
  missing~ : MissingPolicy = RequireAll,
  max_points~ : Int32 = 1000000,
) -> ResamplingResult raise GribError {
  validate_target(target, max_points)
  let values : Array[Double?] = []
  let mut present = 0
  let mut outside_or_unsampled = 0
  for row in 0..<target.rows {
    let latitude = target.north - row.to_double() * target.latitude_spacing
    for column in 0..<target.columns {
      let longitude = target.west +
        column.to_double() * target.longitude_spacing
      let sample = self.estimate(
        { latitude, longitude, },
        interpolation~,
        missing~,
      )
      if sample.value is Some(_) {
        present += 1
      }
      if sample.contributing_points == 0 {
        outside_or_unsampled += 1
      }
      values.push(sample.value)
    }
  }
  let raster : Raster = {
    rows: target.rows,
    columns: target.columns,
    north: target.north,
    west: target.west,
    latitude_spacing: target.latitude_spacing,
    longitude_spacing: target.longitude_spacing,
    values,
  }
  { raster, present, missing: values.length() - present, outside_or_unsampled, }
}

///|
pub fn ResamplingResult::metrics_json(self : ResamplingResult) -> Json {
  Json::object(
    Map([
      ("rows", number(self.raster.rows)),
      ("columns", number(self.raster.columns)),
      ("present", number(self.present)),
      ("missing", number(self.missing)),
      ("outside_or_unsampled", number(self.outside_or_unsampled)),
    ]),
  )
}
