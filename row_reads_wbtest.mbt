///|
test "row-range reader splits at read limit and preserves wrapped windows" {
  let (grid, product) = writer_specs()
  let wrapped : RegularGridSpec = {
    ..grid,
    columns: 8,
    longitude_microdegrees: 176000000,
  }
  let values : Array[Double?] = []
  for i in 0..<16 {
    values.push(Some(i.to_double() - 2.0))
  }
  let bytes = encode_ieee(wrapped, product, values)
  let reads : Array[Int32] = []
  let source = ByteSource::new(bytes.length(), (offset, length) => {
    reads.push(length)
    bytes[offset:offset + length].to_owned()
  })
  let field = open_indexed(source).decode(0)
  reads.clear()
  let bounds : Bounds = { west: 178.0, east: -178.0, south: 0.0, north: 1.0, }
  let small = field.window(bounds, options={
    max_points: 20,
    merge_gap: 0,
    max_read: 16,
  })
  let expected = open_archive(bytes).decode(0).window(bounds)
  assert_eq(samples_csv(small.samples), samples_csv(expected))
  assert_eq(small.decoded_values, 10)
  assert_eq(small.payload_bytes, 80L)
  assert_eq(small.payload_reads, 6)
  assert_true(reads.all(length => length <= 16))
}
