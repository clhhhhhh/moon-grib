///|
extern "js" fn open_descriptor(path : String) -> Int32? =
  #| path => {
  #|   try { return require("node:fs").openSync(path, "r"); }
  #|   catch (_) { return undefined; }
  #| }

///|
extern "js" fn source_size(handle : Int32) -> Int32? =
  #| handle => {
  #|   try {
  #|     const stat = require("node:fs").fstatSync(handle);
  #|     return stat.isFile() && stat.size <= 2147483647 ? stat.size : undefined;
  #|   } catch (_) { return undefined; }
  #| }

///|
extern "js" fn descriptor_read(
  handle : Int32,
  offset : Int32,
  length : Int32,
) -> Bytes? =
  #| (handle, offset, length) => {
  #|   try {
  #|     const fs = require("node:fs");
  #|     const bytes = Buffer.alloc(length);
  #|     let count = 0;
  #|     while (count < length) {
  #|       const read = fs.readSync(handle, bytes, count, length - count, offset + count);
  #|       if (read === 0) return undefined;
  #|       count += read;
  #|     }
  #|     return bytes;
  #|   } catch (_) { return undefined; }
  #| }

///|
extern "js" fn close_descriptor(handle : Int32) -> Unit =
  #| handle => { require("node:fs").closeSync(handle); }

///|
extern "js" fn write_stdout(value : String) -> Unit =
  #| value => { process.stdout.write(value); }

///|
extern "js" fn write_stderr(value : String) -> Unit =
  #| value => { process.stderr.write(value + "\n"); }

///|
fn range_window(
  path : String,
  index : Int32,
  bounds : @grib.Bounds,
) -> Unit raise @grib.GribError {
  guard open_descriptor(path) is Some(handle) else {
    raise @grib.Invalid(0, "could not open input")
  }
  defer close_descriptor(handle)
  let (window, reads, bytes) = read_range_window(handle, index, bounds)
  write_stdout(@grib.samples_csv(window.samples))
  let metrics = Json::object(
    Map([
      ("window", window.metrics_json()),
      ("source_reads", Json::number(reads.to_double())),
      ("source_bytes", Json::number(bytes.to_double())),
    ]),
  )
  write_stderr(metrics.stringify())
}

///|
fn read_range_window(
  handle : Int32,
  index : Int32,
  bounds : @grib.Bounds,
) -> (@grib.ReadWindow, Int32, Int64) raise @grib.GribError {
  let file = file_source(handle)
  let reads = Ref(0)
  let bytes = Ref(0L)
  let source = @grib.ByteSource::new(file.length, (offset, count) => {
    let data = file.read_exact(offset, count)
    reads.val += 1
    bytes.val += count.to_int64()
    data
  })
  let window = @grib.open_indexed(source).decode(index).window(bounds)
  (window, reads.val, bytes.val)
}
