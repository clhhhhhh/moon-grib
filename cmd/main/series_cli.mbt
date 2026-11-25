///|
fn timestamp_number(
  chars : Array[Char],
  start : Int32,
  length : Int32,
) -> Int32 raise @grib.GribError {
  let mut value = 0
  for i in start..<(start + length) {
    let char = chars[i]
    if char < '0' || char > '9' {
      raise @grib.Invalid(i, "timestamp field is not numeric")
    }
    value = value * 10 + char.to_int() - '0'.to_int()
  }
  value
}

///|
fn parse_timestamp(text : String) -> @grib.ReferenceTime raise @grib.GribError {
  let chars = text.to_array()
  if chars.length() != 20 ||
    chars[4] != '-' ||
    chars[7] != '-' ||
    chars[10] != 'T' ||
    chars[13] != ':' ||
    chars[16] != ':' ||
    chars[19] != 'Z' {
    raise @grib.Invalid(0, "timestamp must use YYYY-MM-DDTHH:MM:SSZ")
  }
  {
    year: timestamp_number(chars, 0, 4),
    month: timestamp_number(chars, 5, 2),
    day: timestamp_number(chars, 8, 2),
    hour: timestamp_number(chars, 11, 2),
    minute: timestamp_number(chars, 14, 2),
    second: timestamp_number(chars, 17, 2),
  }
}

///|
fn series_filter(
  discipline : String,
  category : String,
  parameter : String,
) -> @grib.Filter raise @grib.GribError {
  {
    ..@grib.Filter::empty(),
    discipline: optional_code(discipline),
    category: optional_code(category),
    parameter: optional_code(parameter),
  }
}

///|
fn point_series(
  path : String,
  discipline : String,
  category : String,
  parameter : String,
  latitude : String,
  longitude : String,
  start : String,
  end : String,
  mode : String,
) -> Unit raise @grib.GribError {
  let filter = series_filter(discipline, category, parameter)
  let position : @grib.Position = {
    latitude: parse_numeric(latitude),
    longitude: parse_numeric(longitude),
  }
  let options : @grib.SeriesOptions = {
    ..@grib.SeriesOptions::standard(),
    interpolation: interpolation_kind(mode),
  }
  let samples = load(path).point_series(
    filter,
    position,
    parse_timestamp(start),
    parse_timestamp(end),
    options~,
  )
  for sample in samples {
    println(sample.json().stringify())
  }
}

///|
fn regional_series(
  path : String,
  discipline : String,
  category : String,
  parameter : String,
  bounds : @grib.Bounds,
  start : String,
  end : String,
) -> Unit raise @grib.GribError {
  let filter = series_filter(discipline, category, parameter)
  let samples = load(path).regional_series(
    filter,
    bounds,
    parse_timestamp(start),
    parse_timestamp(end),
  )
  for sample in samples {
    println(sample.json().stringify())
  }
}

///|
fn print_interval(path : String, index : String) -> Unit raise @grib.GribError {
  let field = parse_index(index)
  let result = load(path).aggregation_interval(field)
  println(result.map(value => value.json()).unwrap_or(Json::null()).stringify())
}

///|
fn print_raster(
  path : String,
  index : String,
  bounds : @grib.Bounds,
  format : String,
) -> Unit raise @grib.GribError {
  let raster = load(path).decode(parse_index(index)).raster(bounds)
  let output = match format {
    "asc" => raster.ascii_grid()
    "pgm" => raster.pgm()
    _ => raise @grib.Invalid(0, "raster format must be asc or pgm")
  }
  write_stdout(output)
}
