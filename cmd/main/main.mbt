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
      ["inventory", path] => {
        let archive = load(path)
        for i in 0..<archive.field_count() {
          println(archive.metadata(i).json().stringify())
        }
      }
      ["window" | "stats" as command, path, index, west, south, east, north] => {
        let archive = load(path)
        let field = archive.decode(parse_index(index))
        let bounds : @grib.Bounds = {
          west: parse_numeric(west),
          south: parse_numeric(south),
          east: parse_numeric(east),
          north: parse_numeric(north),
        }
        if command == "stats" {
          println(field.statistics(bounds).json().stringify())
        } else {
          println(@grib.samples_csv(field.window(bounds)))
        }
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
          0, "Usage: inventory FILE | verify FILE | point FILE FIELD ROW COLUMN | window|stats FILE FIELD WEST SOUTH EAST NORTH",
        )
    }
  } catch {
    @grib.Invalid(offset, reason) =>
      report_error("invalid at " + offset.to_string() + " " + reason)
    @grib.Unsupported(offset, reason) =>
      report_error("unsupported at " + offset.to_string() + " " + reason)
  }
}
