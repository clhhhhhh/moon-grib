///|
test "finite scaling survives overflow before decimal adjustment" {
  let (grid, product) = writer_specs()
  let bytes = encode_simple(
    grid,
    product,
    { binary_scale: 1023, decimal_scale: 308, },
    [Some(4U), Some(1U), Some(0U), None],
  )
  let value = open_archive(bytes).decode(0).at(0, 0).value.unwrap()
  assert_true((value - 3.595386269724632).abs() < 0.000000000001)
}

///|
test "truly overflowing values still fail" {
  let (grid, product) = writer_specs()
  let bytes = encode_simple(
    grid,
    product,
    { binary_scale: 1023, decimal_scale: 0, },
    [Some(4U), Some(1U), Some(0U), None],
  )
  let field = open_archive(bytes).decode(0)
  let rejected = try {
    ignore(field.at(0, 0))
    false
  } catch {
    Unsupported(_, _) => true
    _ => false
  }
  assert_true(rejected)
}
