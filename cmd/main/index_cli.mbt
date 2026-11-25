///|
extern "js" fn write_bytes_stdout(value : Bytes) -> Unit =
  #| value => { process.stdout.write(value); }

///|
fn file_source(handle : Int32) -> @grib.ByteSource raise @grib.GribError {
  guard source_size(handle) is Some(length) else {
    raise @grib.Invalid(0, "input must be a regular file of at most 2 GiB")
  }
  @grib.ByteSource::new(length, (offset, count) => {
    guard descriptor_read(handle, offset, count) is Some(data) else {
      raise @grib.Invalid(offset, "positioned read failed")
    }
    data
  })
}

///|
fn range_inventory(path : String) -> Unit raise @grib.GribError {
  guard open_descriptor(path) is Some(handle) else {
    raise @grib.Invalid(0, "could not open input")
  }
  defer close_descriptor(handle)
  let archive = @grib.open_indexed(file_source(handle))
  for i in 0..<archive.field_count() {
    println(archive.metadata(i).json().stringify())
  }
}

///|
/// The extracted span is the containing GRIB message. A message with multiple
/// fields is preserved byte-for-byte so shared sections stay valid.
fn extract_message(path : String, index : Int32) -> Unit raise @grib.GribError {
  guard open_descriptor(path) is Some(handle) else {
    raise @grib.Invalid(0, "could not open input")
  }
  defer close_descriptor(handle)
  let archive = @grib.open_indexed(file_source(handle))
  write_bytes_stdout(archive.raw_message(index))
}

///|
fn print_field_span(path : String, index : Int32) -> Unit raise @grib.GribError {
  guard open_descriptor(path) is Some(handle) else {
    raise @grib.Invalid(0, "could not open input")
  }
  defer close_descriptor(handle)
  let entry = @grib.open_indexed(file_source(handle)).field(index)
  println(
    Json::object(
      Map([
        ("message_offset", Json::number(entry.message.offset.to_double())),
        ("message_bytes", Json::number(entry.message.length.to_double())),
        ("payload_offset", Json::number((entry.data.offset + 5).to_double())),
        ("payload_bytes", Json::number((entry.data.length - 5).to_double())),
      ]),
    ).stringify(),
  )
}
