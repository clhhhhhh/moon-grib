///|
priv struct Packing {
  reference : Double
  binary_scale : Double
  binary_exponent : Int32
  decimal_scale : Double
  width : Int32
  count : Int32
}

///|
fn pow_int(base : Double, exponent : Int32) -> Double {
  let mut power = if exponent < 0 { -exponent } else { exponent }
  let mut factor = if exponent < 0 { 1.0 / base } else { base }
  let mut result = 1.0
  while power > 0 {
    if (power & 1) != 0 {
      result *= factor
    }
    power = power >> 1
    if power > 0 {
      factor *= factor
    }
  }
  result
}

///|
fn ieee_single(bits : UInt64, at : Int32) -> Double raise GribError {
  let exponent = ((bits >> 23) & 255UL).to_int()
  if exponent == 255 {
    raise Invalid(at, "non-finite packing reference")
  }
  let fraction = (bits & 8388607UL).to_double()
  let sign = if bits >> 31 == 0UL { 1.0 } else { -1.0 }
  if exponent == 0 {
    sign * fraction * pow_int(2.0, -149)
  } else {
    sign * (8388608.0 + fraction) * pow_int(2.0, exponent - 150)
  }
}

///|
fn parse_packing(bytes : Bytes, field : Field) -> Packing raise GribError {
  parse_packing_definition(bytes, field.representation, field.data.length)
}

///|
fn parse_packing_definition(
  bytes : Bytes,
  representation : Span,
  data_length : Int32,
) -> Packing raise GribError {
  let at = representation.offset
  let template = u16(bytes, at + 9)
  if template != 0 && template != 2 && template != 3 {
    raise Unsupported(
      at + 9,
      "unsupported packing template 5." + template.to_string(),
    )
  }
  if representation.length < 21 {
    raise Invalid(at, "truncated simple packing definition")
  }
  let count = bounded_int(unsigned(bytes, at + 5, 4), at + 5)
  let width = byte_at(bytes, at + 19)
  if width > 32 {
    raise Unsupported(at + 19, "packed width exceeds 32 bits")
  }
  let bit_count = count.to_int64() * width.to_int64()
  if template == 0 && (bit_count + 7L) / 8L != (data_length - 5).to_int64() {
    raise Invalid(at, "section 7 length disagrees with packed count and width")
  }
  let binary = signed_magnitude(bytes, at + 15, 2)
  let decimal = signed_magnitude(bytes, at + 17, 2)
  if binary < -1074 || binary > 1023 || decimal < -308 || decimal > 308 {
    raise Unsupported(at + 15, "packing scales exceed Double range")
  }
  {
    reference: ieee_single(unsigned(bytes, at + 11, 4), at + 11),
    binary_scale: pow_int(2.0, binary),
    binary_exponent: binary,
    decimal_scale: pow_int(10.0, -decimal),
    width,
    count,
  }
}

///|
fn packed_integer(
  bytes : Bytes,
  start : Int32,
  ordinal : Int32,
  width : Int32,
) -> UInt64 {
  if width == 0 {
    return 0UL
  }
  bits_at(bytes, start, ordinal.to_int64() * width.to_int64(), width)
}

///|
fn bits_at(bytes : Bytes, start : Int32, bit : Int64, width : Int32) -> UInt64 {
  let shift = (bit % 8L).to_int()
  let bytes_needed = (shift + width + 7) / 8
  let raw = unsigned(bytes, start + (bit / 8L).to_int(), bytes_needed)
  (raw >> (bytes_needed * 8 - shift - width)) & ((1UL << width) - 1UL)
}

///|
fn decode_value(
  start : Int32,
  packing : Packing,
  integer : UInt64,
) -> Double raise GribError {
  let scaled_integer = integer.to_double() * packing.binary_scale
  let unscaled = packing.reference + scaled_integer
  let value = if unscaled.is_inf() && integer != 0UL {
    let decimal = packing.decimal_scale
    let bits = decimal.reinterpret_as_uint64()
    let encoded_exponent = ((bits >> 52) & 2047UL).to_int()
    let exponent = if encoded_exponent == 0 {
      -1022
    } else {
      encoded_exponent - 1023
    }
    let mantissa = @math.scalbn(decimal, -exponent)
    @math.scalbn(
      integer.to_double() * mantissa,
      packing.binary_exponent + exponent,
    ) +
    packing.reference * decimal
  } else {
    unscaled * packing.decimal_scale
  }
  if value.is_nan() || value.is_inf() {
    raise Unsupported(start, "decoded value exceeds Double range")
  }
  value
}
