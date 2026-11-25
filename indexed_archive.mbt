///|
pub struct IndexedArchive {
  priv source : ByteSource
  priv fields : Array[Field]
}

///|
pub fn open_indexed(source : ByteSource) -> IndexedArchive raise GribError {
  { source, fields: scan_source(source), }
}

///|
pub fn IndexedArchive::field_count(self : IndexedArchive) -> Int32 {
  self.fields.length()
}

///|
pub fn IndexedArchive::field(
  self : IndexedArchive,
  index : Int32,
) -> Field raise GribError {
  if index < 0 || index >= self.fields.length() {
    raise Invalid(index, "field index out of bounds")
  }
  self.fields[index]
}

///|
pub fn IndexedArchive::decode(
  self : IndexedArchive,
  index : Int32,
) -> RangeField raise GribError {
  open_range_field(self.source, self.field(index))
}

///|
/// Read only the header prefix required by the public field inventory.
pub fn IndexedArchive::metadata(
  self : IndexedArchive,
  index : Int32,
) -> Metadata raise GribError {
  let field = self.field(index)
  let identification = self.source.read_exact(field.identification.offset, 21)
  let grid = self.source.read_exact(field.grid_definition.offset, 14)
  let representation = self.source.read_exact(field.representation.offset, 11)
  let product_length = if field.product_definition.length < 34 {
    field.product_definition.length
  } else {
    34
  }
  let product = self.source.read_exact(
    field.product_definition.offset,
    product_length,
  )
  metadata_from_headers(
    field, index, identification, 0, grid, 0, representation, 0, product, 0,
  )
}

///|
pub fn IndexedArchive::select(
  self : IndexedArchive,
  filter : Filter,
) -> Array[Metadata] raise GribError {
  let matches : Array[Metadata] = []
  for i in 0..<self.field_count() {
    let entry = self.metadata(i)
    if filter.matches(entry) {
      matches.push(entry)
    }
  }
  matches
}

///|
pub fn IndexedArchive::raw_message(
  self : IndexedArchive,
  index : Int32,
  max_bytes~ : Int32 = 67108864,
) -> Bytes raise GribError {
  let field = self.field(index)
  if max_bytes < 0 {
    raise Invalid(0, "message byte limit must be nonnegative")
  }
  if field.message.length > max_bytes {
    raise Unsupported(
      field.message.offset,
      "message exceeds requested byte limit",
    )
  }
  self.source.read_span(field.message)
}
