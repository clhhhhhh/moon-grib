///|
fn resample_raster(
  path : String,
  index : String,
  rows : String,
  columns : String,
  north : String,
  west : String,
  dy : String,
  dx : String,
  mode : String,
  format : String,
) -> Unit raise @grib.GribError {
  let grid : @grib.TargetGrid = {
    rows: parse_index(rows),
    columns: parse_index(columns),
    north: parse_numeric(north),
    west: parse_numeric(west),
    latitude_spacing: parse_numeric(dy),
    longitude_spacing: parse_numeric(dx),
  }
  let decoded = load(path).decode(parse_index(index))
  let output = decoded.resample(grid, interpolation=interpolation_kind(mode))
  let encoded = match format {
    "asc" => output.raster.ascii_grid()
    "pgm" => output.raster.pgm()
    _ => raise @grib.Invalid(0, "raster format must be asc or pgm")
  }
  write_stdout(encoded)
  write_stderr(output.metrics_json().stringify())
}
