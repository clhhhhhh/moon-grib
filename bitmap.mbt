///|
priv struct Bitmap {
  start : Int32
  ranks : Array[Int32]
}

///|
fn popcount(value : Int32) -> Int32 {
  let pair = value - ((value >> 1) & 85)
  let quad = (pair & 51) + ((pair >> 2) & 51)
  (quad + (quad >> 4)) & 15
}

///|
fn parse_bitmap(
  bytes : Bytes,
  field : Field,
  points : Int32,
  packed : Int32,
) -> Bitmap? raise GribError {
  let flag = byte_at(bytes, field.bitmap.offset + 5)
  if flag == 255 {
    if field.bitmap.length != 6 || points != packed {
      raise Invalid(
        field.bitmap.offset,
        "unmasked field count does not match grid",
      )
    }
    return None
  }
  guard field.bitmap_source is Some(span) else {
    raise Unsupported(
      field.bitmap.offset + 5,
      "predefined bitmap is unsupported",
    )
  }
  if flag == 254 && field.bitmap.length != 6 {
    raise Invalid(
      field.bitmap.offset,
      "reused bitmap contains unexpected bytes",
    )
  }
  let size = ((points.to_int64() + 7L) / 8L).to_int()
  if span.length - 6 != size {
    raise Invalid(span.offset, "bitmap length does not match grid")
  }
  let start = span.offset + 6
  let ranks : Array[Int32] = []
  let mut count = 0
  for i in 0..<size {
    if i % 64 == 0 {
      ranks.push(count)
    }
    let octet = byte_at(bytes, start + i)
    if i + 1 == size &&
      points % 8 != 0 &&
      (octet & ((1 << (8 - points % 8)) - 1)) != 0 {
      raise Invalid(start + i, "bitmap padding contains set bits")
    }
    count += popcount(octet)
  }
  if count != packed {
    raise Invalid(span.offset, "bitmap population does not match packed count")
  }
  Some({ start, ranks, })
}

///|
fn Bitmap::ordinal(self : Bitmap, bytes : Bytes, index : Int32) -> Int32? {
  let offset = index / 8
  let bit = 7 - index % 8
  let octet = byte_at(bytes, self.start + offset)
  if (octet & (1 << bit)) == 0 {
    return None
  }
  let mut rank = self.ranks[offset / 64]
  for i in (offset - offset % 64)..<offset {
    rank += popcount(byte_at(bytes, self.start + i))
  }
  Some(rank + popcount(octet >> (bit + 1)))
}
