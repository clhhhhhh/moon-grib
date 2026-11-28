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

///|
test "level values round-trip including wholly missing fields" {
  let (grid, product) = writer_specs()
  let data = encode_level_runs(grid, product, 1, [15U, 40U], [
    Some(1),
    Some(1),
    None,
    Some(2),
  ])
  let decoded = open_archive(data).decode(0)
  assert_eq(decoded.at(0, 0).value, Some(1.5))
  assert_eq(decoded.at(0, 1).value, Some(1.5))
  assert_eq(decoded.at(1, 0).value, None)
  assert_eq(decoded.at(1, 1).value, Some(4.0))
  let missing = encode_level_runs(grid, product, 0, [1U], [
    None,
    None,
    None,
    None,
  ])
  assert_eq(open_archive(missing).decode(0).at(1, 1).value, None)
}
