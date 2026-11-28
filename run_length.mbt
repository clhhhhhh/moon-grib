///|
priv struct LevelRun {
  stop : Int32
  value : Double?
}

///|
fn parse_level_runs(
  bytes : Bytes,
  field : Field,
  count : Int32,
) -> Array[LevelRun] raise GribError {
  let at = field.representation.offset
  let start = field.data.offset + 5
  let available = (field.data.length - 5).to_int64() * 8L
  if field.representation.length < 17 {
    raise Invalid(at, "truncated level packing definition")
  }
  let width = byte_at(bytes, at + 11)
  let maximum = u16(bytes, at + 12)
  let levels = u16(bytes, at + 14)
  if maximum > levels || field.representation.length != 17 + 2 * levels {
    raise Invalid(at, "invalid representative level table")
  }
  if maximum == 0 && available == 0L {
    return if count == 0 { [] } else { [{ stop: count, value: None, }] }
  }
  if width == 0 || width > 32 {
    raise Unsupported(at + 11, "level packing width must be 1 through 32 bits")
  }
  let radix = (1L << width) - 1L - maximum.to_int64()
  if radix <= 0L {
    raise Invalid(at + 12, "maximum level leaves no repetition codes")
  }
  let scale = pow_int(10.0, -signed_magnitude(bytes, at + 16, 1))
  let runs : Array[LevelRun] = []
  let mut bit = 0L
  let mut end = 0
  let step = width.to_int64()
  while end < count {
    if available - bit < step {
      raise Invalid(start, "level runs do not reach declared point count")
    }
    let level = bits_at(bytes, start, bit, width).to_int()
    if level < 0 || level > maximum {
      raise Invalid(start, "level run must start with a level code")
    }
    bit += step
    let mut length = 1L
    let remaining = (count - end).to_int64()
    let mut factor = 1L
    while available - bit >= step {
      let code = bits_at(bytes, start, bit, width).reinterpret_as_int64()
      if code <= maximum.to_int64() {
        break
      }
      let digit = code - maximum.to_int64() - 1L
      if digit > (remaining - length) / factor {
        raise Invalid(start, "level run exceeds declared point count")
      }
      length += digit * factor
      factor = if factor > remaining / radix {
        remaining + 1L
      } else {
        factor * radix
      }
      bit += step
    }
    end += length.to_int()
    if runs.length() == 1000000 {
      raise Unsupported(start, "level run index exceeds resource limit")
    }
    let value = if level == 0 {
      None
    } else {
      Some(u16(bytes, at + 17 + 2 * (level - 1)).to_double() * scale)
    }
    runs.push({ stop: end, value, })
  }
  let padding = available - bit
  if padding > 7L ||
    (padding > 0L && bits_at(bytes, start, bit, padding.to_int()) != 0UL) {
    raise Invalid(start, "unexpected data after final level run")
  }
  runs
}

///|
fn level_run_value(runs : Array[LevelRun], index : Int32) -> Double? {
  let mut low = 0
  let mut high = runs.length()
  while low < high {
    let middle = low + (high - low) / 2
    if runs[middle].stop <= index {
      low = middle + 1
    } else {
      high = middle
    }
  }
  runs[low].value
}
