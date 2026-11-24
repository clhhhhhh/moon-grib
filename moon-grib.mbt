///|
pub(all) suberror GribError {
  Invalid(Int32, String)
  Unsupported(Int32, String)
}

///|
fn byte_at(bytes : Bytes, at : Int32) -> Int32 {
  bytes[at].to_int()
}

///|
fn unsigned(bytes : Bytes, at : Int32, count : Int32) -> UInt64 {
  let mut result = 0UL
  for i in at..<(at + count) {
    result = (result << 8) | bytes[i].to_uint64()
  }
  result
}

///|
fn u16(bytes : Bytes, at : Int32) -> Int32 {
  unsigned(bytes, at, 2).to_int()
}

///|
fn signed_magnitude(bytes : Bytes, at : Int32, count : Int32) -> Int32 {
  let magnitude = (unsigned(bytes, at, count) & ((1UL << (count * 8 - 1)) - 1UL)).to_int()
  if byte_at(bytes, at) >= 128 {
    -magnitude
  } else {
    magnitude
  }
}

///|
fn bounded_int(value : UInt64, at : Int32) -> Int32 raise GribError {
  if value > 2147483647UL {
    raise Unsupported(at, "value exceeds local indexing range")
  }
  value.to_int()
}

///|
pub(all) struct Span {
  offset : Int32
  length : Int32
}

///|
pub(all) struct Field {
  discipline : Int32
  message : Span
  identification : Span
  grid_definition : Span
  product_definition : Span
  representation : Span
  bitmap : Span
  data : Span
  bitmap_source : Span?
}

///|
pub struct Archive {
  bytes : Bytes
  fields : Array[Field]
}

///|
pub fn Archive::field_count(self : Archive) -> Int32 {
  self.fields.length()
}

///|
pub fn Archive::field(self : Archive, index : Int32) -> Field raise GribError {
  if index < 0 || index >= self.fields.length() {
    raise Invalid(index, "field index is out of bounds")
  }
  self.fields[index]
}

///|
fn is_marker(bytes : Bytes, at : Int32, values : Bytes) -> Bool {
  for i in 0..<values.length() {
    if bytes[at + i] != values[i] {
      return false
    }
  }
  true
}

///|
pub fn open_archive(bytes : Bytes) -> Archive raise GribError {
  let fields : Array[Field] = []
  let mut offset = 0
  while offset < bytes.length() {
    offset += read_message(bytes, offset, fields)
  }
  if fields.length() == 0 {
    raise Invalid(0, "archive is empty")
  }
  { bytes, fields, }
}

///|
fn read_message(
  bytes : Bytes,
  offset : Int32,
  fields : Array[Field],
) -> Int32 raise GribError {
  if bytes.length() - offset < 20 || !is_marker(bytes, offset, b"GRIB") {
    raise Invalid(offset, "missing GRIB message indicator")
  }
  if byte_at(bytes, offset + 7) != 2 {
    raise Unsupported(offset + 7, "only GRIB edition 2 is supported")
  }
  let length = bounded_int(unsigned(bytes, offset + 8, 8), offset + 8)
  if length < 20 || length > bytes.length() - offset {
    raise Invalid(offset + 8, "message length exceeds the input")
  }
  let end = offset + length - 4
  if !is_marker(bytes, end, b"7777") {
    raise Invalid(end, "missing end section")
  }
  let message : Span = { offset, length, }
  let discipline = byte_at(bytes, offset + 6)
  let (identification, _) = read_section(bytes, offset + 16, end, 1, 21)
  let mut cursor = identification.offset + identification.length
  let mut grid : Span? = None
  let mut reusable_bitmap : Span? = None
  let initial_count = fields.length()
  while cursor < end {
    if end - cursor >= 5 && byte_at(bytes, cursor + 4) == 2 {
      let (local_section, _) = read_section(bytes, cursor, end, 2, 5)
      cursor += local_section.length
    }
    if end - cursor >= 5 && byte_at(bytes, cursor + 4) == 3 {
      let (section, _) = read_section(bytes, cursor, end, 3, 14)
      grid = Some(section)
      cursor += section.length
    }
    guard grid is Some(grid_definition) else {
      raise Invalid(cursor, "field has no grid definition")
    }
    let (product_definition, after_product) = read_section(
      bytes, cursor, end, 4, 9,
    )
    let (representation, after_representation) = read_section(
      bytes, after_product, end, 5, 11,
    )
    let (bitmap, after_bitmap) = read_section(
      bytes, after_representation, end, 6, 6,
    )
    let (data, after_data) = read_section(bytes, after_bitmap, end, 7, 5)
    let flag = byte_at(bytes, bitmap.offset + 5)
    let bitmap_source = match flag {
      0 => {
        reusable_bitmap = Some(bitmap)
        Some(bitmap)
      }
      254 =>
        match reusable_bitmap {
          Some(previous) => Some(previous)
          None => raise Invalid(bitmap.offset, "no earlier bitmap to reuse")
        }
      _ => None
    }
    fields.push({
      discipline,
      message,
      identification,
      grid_definition,
      product_definition,
      representation,
      bitmap,
      data,
      bitmap_source,
    })
    cursor = after_data
  }
  if fields.length() == initial_count {
    raise Invalid(offset, "message has no fields")
  }
  length
}

///|
fn read_section(
  bytes : Bytes,
  cursor : Int32,
  end : Int32,
  expected : Int32,
  minimum : Int32,
) -> (Span, Int32) raise GribError {
  if end - cursor < 5 {
    raise Invalid(cursor, "truncated section header")
  }
  let length = bounded_int(unsigned(bytes, cursor, 4), cursor)
  if length < minimum || length > end - cursor {
    raise Invalid(cursor, "invalid section length")
  }
  if byte_at(bytes, cursor + 4) != expected {
    raise Invalid(cursor + 4, "expected section " + expected.to_string())
  }
  ({ offset: cursor, length, }, cursor + length)
}
