///|
pub struct ByteSource {
  length : Int32
  priv read : (Int32, Int32) -> Bytes raise GribError
}

///|
pub fn ByteSource::new(
  length : Int32,
  read : (Int32, Int32) -> Bytes raise GribError,
) -> ByteSource raise GribError {
  if length < 0 {
    raise Invalid(0, "source length must be nonnegative")
  }
  { length, read, }
}

///|
pub fn ByteSource::read_exact(
  self : ByteSource,
  start : Int32,
  length : Int32,
) -> Bytes raise GribError {
  if start < 0 ||
    start > self.length ||
    length < 0 ||
    length > self.length - start {
    raise Invalid(start, "read exceeds source bounds")
  }
  if length == 0 {
    return b""
  }
  let result = (self.read)(start, length)
  if result.length() != length {
    raise Invalid(start, "source returned an incomplete read")
  }
  result
}

///|
pub fn ByteSource::read_span(
  self : ByteSource,
  span : Span,
) -> Bytes raise GribError {
  self.read_exact(span.offset, span.length)
}

///|
pub fn scan_source(source : ByteSource) -> Array[Field] raise GribError {
  let fields : Array[Field] = []
  let mut offset = 0
  while offset < source.length {
    offset += read_message(source, offset, fields)
  }
  if fields.length() == 0 {
    raise Invalid(0, "archive is empty")
  }
  fields
}
