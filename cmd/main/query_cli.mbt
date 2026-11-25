///|
fn coordinates(
  west : String,
  south : String,
  east : String,
  north : String,
) -> @grib.Bounds raise @grib.GribError {
  {
    west: parse_numeric(west),
    south: parse_numeric(south),
    east: parse_numeric(east),
    north: parse_numeric(north),
  }
}

///|
fn interpolation_kind(
  text : String,
) -> @grib.InterpolationMethod raise @grib.GribError {
  match text {
    "nearest" => Nearest
    "bilinear" => Bilinear
    _ => raise @grib.Invalid(0, "interpolation must be nearest or bilinear")
  }
}

///|
fn estimate_at(
  path : String,
  index : String,
  latitude : String,
  longitude : String,
  mode : String,
) -> Unit raise @grib.GribError {
  let position : @grib.Position = {
    latitude: parse_numeric(latitude),
    longitude: parse_numeric(longitude),
  }
  let result = load(path)
    .decode(parse_index(index))
    .estimate(position, interpolation=interpolation_kind(mode))
  println(result.json().stringify())
}

///|
fn profile_at(
  path : String,
  index : String,
  start_lat : String,
  start_lon : String,
  end_lat : String,
  end_lon : String,
  size : String,
  mode : String,
) -> Unit raise @grib.GribError {
  let from : @grib.Position = {
    latitude: parse_numeric(start_lat),
    longitude: parse_numeric(start_lon),
  }
  let to : @grib.Position = {
    latitude: parse_numeric(end_lat),
    longitude: parse_numeric(end_lon),
  }
  let results = load(path)
    .decode(parse_index(index))
    .profile(
      from,
      to,
      parse_index(size),
      interpolation=interpolation_kind(mode),
    )
  for result in results {
    println(result.json().stringify())
  }
}

///|
fn report_comparison(
  left : String,
  left_index : String,
  right : String,
  right_index : String,
  bounds : @grib.Bounds,
  tolerance : String,
) -> Unit raise @grib.GribError {
  let base = load(left).decode(parse_index(left_index))
  let comparison = load(right).decode(parse_index(right_index))
  let result = base.compare_window(
    comparison,
    bounds,
    tolerance=parse_numeric(tolerance),
  )
  println(result.json().stringify())
}

///|
fn optional_code(value : String) -> Int32? raise @grib.GribError {
  if value == "-" {
    None
  } else {
    Some(parse_index(value))
  }
}

///|
fn search_inventory(
  path : String,
  discipline : String,
  category : String,
  parameter : String,
  level : String,
) -> Unit raise @grib.GribError {
  let defaults = @grib.Filter::empty()
  let query : @grib.Filter = {
    ..defaults,
    discipline: optional_code(discipline),
    category: optional_code(category),
    parameter: optional_code(parameter),
    surface_kind: optional_code(level),
  }
  for field in load(path).select(query) {
    println(field.json().stringify())
  }
}
