///|
fn ieee_precision(
  bytes : Bytes,
  representation : Span,
  data_length : Int32,
) -> (Int32, Int32) raise GribError {
  let at = representation.offset
  if representation.length < 12 {
    raise Invalid(at, "truncated IEEE packing definition")
  }
  let width = match byte_at(bytes, at + 11) {
    1 => 4
    2 => 8
    _ => raise Unsupported(at + 11, "unsupported IEEE precision")
  }
  let count = bounded_int(unsigned(bytes, at + 5, 4), at + 5)
  if count.to_int64() * width.to_int64() != (data_length - 5).to_int64() {
    raise Invalid(at, "IEEE payload length differs from the value count")
  }
  (width, count)
}

///|
fn ieee_value(
  bytes : Bytes,
  at : Int32,
  width : Int32,
) -> Double raise GribError {
  let bits = unsigned(bytes, at, width)
  let value = if width == 4 {
    ieee_single(bits, at)
  } else {
    bits.reinterpret_as_double()
  }
  if value.is_nan() || value.is_inf() {
    raise Unsupported(at, "nonfinite IEEE datum")
  }
  value
}

///|
fn ieee_packing(width : Int32, count : Int32) -> Packing {
  {
    reference: 0.0,
    binary_scale: 1.0,
    binary_exponent: 0,
    decimal_scale: 1.0,
    width: width * 8,
    count,
  }
}
