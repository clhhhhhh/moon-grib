///|
fn put(
  bytes : Array[Byte],
  start : Int32,
  width : Int32,
  value : UInt64,
) -> Unit {
  for i in 0..<width {
    bytes[start + i] = ((value >> (8 * (width - i - 1))) & 255UL).to_byte()
  }
}

///|
fn fixture(mode : Int32, masked : Bool) -> Bytes {
  let identification = 16
  let grid = identification + 21
  let product = grid + 72
  let packing = product + 34
  let bitmap = packing + 21
  let data = bitmap + (if masked { 7 } else { 6 })
  let end = data + (if masked { 7 } else { 8 })
  let bytes = Array::make(end + 4, b'\x00')
  for i in 0..<4 {
    bytes[i] = b"GRIB"[i]
    bytes[end + i] = b'7'
  }
  bytes[7] = b'\x02'
  put(bytes, 8, 8, bytes.length().to_uint64())
  for
    (at, section_id, length) in [
      (identification, 1, 21),
      (grid, 3, 72),
      (product, 4, 34),
      (packing, 5, 21),
      (bitmap, 6, data - bitmap),
      (data, 7, end - data),
    ] {
    put(bytes, at, 4, length.to_uint64())
    bytes[at + 4] = section_id.to_byte()
  }
  put(bytes, identification + 12, 2, 2026UL)
  bytes[identification + 14] = b'\x0b'
  bytes[identification + 15] = b'\x17'
  put(bytes, grid + 6, 4, 6UL)
  put(bytes, grid + 30, 4, 3UL)
  put(bytes, grid + 34, 4, 2UL)
  put(bytes, grid + 46, 4, 1000000UL)
  put(bytes, grid + 50, 4, 179000000UL)
  put(bytes, grid + 63, 4, 1000000UL)
  put(bytes, grid + 67, 4, 1000000UL)
  bytes[grid + 71] = mode.to_byte()
  put(bytes, packing + 5, 4, if masked { 4UL } else { 6UL })
  bytes[packing + 19] = b'\x04'
  bytes[bitmap + 5] = if masked { b'\x00' } else { b'\xff' }
  if masked {
    bytes[bitmap + 6] = b'\xb4'
  }
  bytes[data + 5] = b'\x12'
  bytes[data + 6] = b'\x34'
  if !masked {
    bytes[data + 7] = b'\x56'
  }
  Bytes::from_array(bytes[:])
}

///|
test "decode consecutive messages, point values and wrapped longitude" {
  let one = fixture(0, false)
  let archive = open_archive(one + one)
  assert_eq(archive.field_count(), 2)
  assert_eq(archive.metadata(1).origin.iso(), "2026-11-23T00:00:00Z")
  let field = archive.decode(1)
  assert_eq(field.dimensions(), (2, 3))
  assert_eq(field.at(1, 2).value, Some(6.0))
  let result = field.window({
    west: 179.5,
    south: 0.0,
    east: -178.5,
    north: 1.0,
  })
  assert_eq(result.length(), 4)
  assert_eq(result[0].longitude, -180.0)
  assert_eq(result[3].value, Some(6.0))
}

///|
test "bitmap rank maps missing values and alternating columns" {
  let field = open_archive(fixture(48, true)).decode(0)
  assert_eq(field.at(0, 0).value, Some(1.0))
  assert_eq(field.at(1, 0).value, None)
  assert_eq(field.at(1, 1).value, Some(2.0))
  assert_eq(field.at(0, 1).value, Some(3.0))
  assert_eq(field.at(0, 2).value, None)
  assert_eq(field.at(1, 2).value, Some(4.0))
}

///|
test "malformed framing and geographic limits fail explicitly" {
  let invalid = try {
    ignore(open_archive(b"GRIB"))
    false
  } catch {
    Invalid(_, _) => true
    _ => false
  }
  assert_true(invalid)
  let field = open_archive(fixture(0, false)).decode(0)
  let limited = try {
    ignore(
      field.window(
        { west: -180.0, south: -90.0, east: 180.0, north: 90.0, },
        max_points=1,
      ),
    )
    false
  } catch {
    Unsupported(_, _) => true
    _ => false
  }
  assert_true(limited)
}
