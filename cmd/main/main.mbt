///|
extern "js" fn read_bytes(path : String) -> Bytes? =
  #| path => {
  #|   try {
  #|     const fs = require("node:fs");
  #|     const stat = fs.statSync(path);
  #|     if (!stat.isFile() || stat.size > 536870912) return undefined;
  #|     return fs.readFileSync(path);
  #|   } catch (_) { return undefined; }
  #| }

///|
extern "js" fn report_error(message : String) -> Unit =
  #| message => { console.error(message); process.exitCode = 2; }

///|
fn load(path : String) -> @grib.Archive raise @grib.GribError {
  match read_bytes(path) {
    Some(bytes) => @grib.open_archive(bytes)
    None =>
      raise @grib.Invalid(0, "could not read a regular file up to 512 MiB")
  }
}

///|
fn parse_index(text : String) -> Int32 raise @grib.GribError {
  @string.parse_int(text[:]) catch {
    _ => raise @grib.Invalid(0, "field index must be an integer")
  }
}

///|
fn parse_numeric(text : String) -> Double raise @grib.GribError {
  @string.parse_double(text[:]) catch {
    _ => raise @grib.Invalid(0, "coordinate must be a decimal number")
  }
}

///|
fn main {
  let args = @env.args()
  try {
    match args[2:] {
      ["range-inventory", path] => range_inventory(path)
      ["extract-message", path, index] =>
        extract_message(path, parse_index(index))
      ["field-span", path, index] => print_field_span(path, parse_index(index))
      ["inventory", path] => {
        let archive = load(path)
        for i in 0..<archive.field_count() {
          println(archive.metadata(i).json().stringify())
        }
      }
      [
        "window"
        | "stats"
        | "range-window"
        | "scan-window" as command,
        path,
        index,
        west,
        south,
        east,
        north,
      ] => {
        let bounds = coordinates(west, south, east, north)
        let field_index = parse_index(index)
        if command == "range-window" {
          range_window(path, field_index, bounds)
        } else {
          let field = load(path).decode(field_index)
          if command == "stats" {
            println(field.statistics(bounds).json().stringify())
          } else {
            let samples = if command == "scan-window" {
              field.scan_window(bounds)
            } else {
              field.window(bounds)
            }
            write_stdout(@grib.samples_csv(samples))
          }
        }
      }
      ["estimate", path, index, lat, lon, mode] =>
        estimate_at(path, index, lat, lon, mode)
      ["profile", path, index, lat1, lon1, lat2, lon2, size, mode] =>
        profile_at(path, index, lat1, lon1, lat2, lon2, size, mode)
      ["compare", left, li, right, ri, west, south, east, north, tolerance] =>
        report_comparison(
          left,
          li,
          right,
          ri,
          coordinates(west, south, east, north),
          tolerance,
        )
      ["select", path, discipline, category, parameter, level] =>
        search_inventory(path, discipline, category, parameter, level)
      ["point-series", path, d, c, p, lat, lon, start, end, mode] =>
        point_series(path, d, c, p, lat, lon, start, end, mode)
      ["regional-series", path, d, c, p, west, south, east, north, start, end] =>
        regional_series(
          path,
          d,
          c,
          p,
          coordinates(west, south, east, north),
          start,
          end,
        )
      ["interval", path, index] => print_interval(path, index)
      ["raster", path, index, west, south, east, north, format] =>
        print_raster(path, index, coordinates(west, south, east, north), format)
      [
        "resample",
        path,
        index,
        rows,
        columns,
        north,
        west,
        dy,
        dx,
        mode,
        format,
      ] =>
        resample_raster(
          path, index, rows, columns, north, west, dy, dx, mode, format,
        )
      ["area-stats", path, index, west, south, east, north] => {
        let field = load(path).decode(parse_index(index))
        println(
          field
          .area_statistics(coordinates(west, south, east, north))
          .json()
          .stringify(),
        )
      }
      ["verify", path] =>
        for diagnostic in load(path).validate() {
          println(diagnostic.json().stringify())
          if !(diagnostic.result is @grib.Ready) {
            report_error("field verification failed")
          }
        }
      ["point", path, index, row, column] =>
        println(
          load(path)
          .decode(parse_index(index))
          .at(parse_index(row), parse_index(column))
          .json()
          .stringify(),
        )
      _ =>
        raise @grib.Invalid(
          0, "Usage: resample FILE FIELD ROWS COLUMNS NORTH WEST DY DX MODE FORMAT | area-stats FILE FIELD WEST SOUTH EAST NORTH | point-series FILE DISC CAT PARAM LAT LON START END MODE | regional-series FILE DISC CAT PARAM WEST SOUTH EAST NORTH START END | interval FILE FIELD | raster FILE FIELD WEST SOUTH EAST NORTH FORMAT | inventory FILE | range-inventory FILE | extract-message FILE FIELD | field-span FILE FIELD | select FILE DISCIPLINE CATEGORY PARAMETER LEVEL | estimate FILE FIELD LAT LON MODE | profile FILE FIELD LAT1 LON1 LAT2 LON2 POINTS MODE | compare LEFT LFIELD RIGHT RFIELD WEST SOUTH EAST NORTH TOLERANCE | verify FILE | point FILE FIELD ROW COLUMN | window|stats|range-window|scan-window FILE FIELD WEST SOUTH EAST NORTH",
        )
    }
  } catch {
    @grib.Invalid(offset, reason) =>
      report_error("invalid at " + offset.to_string() + " " + reason)
    @grib.Unsupported(offset, reason) =>
      report_error("unsupported at " + offset.to_string() + " " + reason)
  }
}
