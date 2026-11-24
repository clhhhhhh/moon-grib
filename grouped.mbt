///|
priv struct PackedGroup {
  first : Int32
  stop : Int32
  bit : Int64
  width : Int32
  reference : UInt64
}

///|
priv struct GroupedPacking {
  groups : Array[PackedGroup]
  missing_mode : Int32
  reference_width : Int32
}

///|
fn descriptor_size(
  bytes : Bytes,
  start : Int32,
  end : Int32,
  groups : Int32,
  width : Int32,
) -> Int32 raise GribError {
  if width > 32 {
    raise Unsupported(start, "group descriptor exceeds 32 bits")
  }
  let bits = groups.to_int64() * width.to_int64()
  let size = (bits + 7L) / 8L
  if size > (end - start).to_int64() {
    raise Invalid(start, "truncated group descriptor array")
  }
  if bits % 8L != 0L {
    let pad = 8 - (bits % 8L).to_int()
    if (byte_at(bytes, start + size.to_int() - 1) & ((1 << pad) - 1)) != 0 {
      raise Invalid(start, "nonzero group descriptor padding")
    }
  }
  size.to_int()
}

///|
fn parse_groups(
  bytes : Bytes,
  field : Field,
  packing : Packing,
  prefix : Int32,
) -> GroupedPacking raise GribError {
  let at = field.representation.offset
  if field.representation.length < 47 {
    raise Invalid(at, "truncated grouped packing definition")
  }
  if byte_at(bytes, at + 21) != 1 {
    raise Unsupported(at + 21, "only general group splitting is supported")
  }
  let missing_mode = byte_at(bytes, at + 22)
  if missing_mode > 2 {
    raise Unsupported(at + 22, "unknown missing-value mode")
  }
  let count = bounded_int(unsigned(bytes, at + 31, 4), at + 31)
  if count > 1000000 {
    raise Unsupported(at + 31, "group index exceeds resource limit")
  }
  let width_bits = byte_at(bytes, at + 36)
  let length_bits = byte_at(bytes, at + 46)
  let ref_length = unsigned(bytes, at + 37, 4)
  let length_increment = byte_at(bytes, at + 41).to_uint64()
  let payload = field.data.offset + 5
  let data = payload + prefix
  let end = field.data.offset + field.data.length
  let width_start = data +
    descriptor_size(bytes, data, end, count, packing.width)
  let length_start = width_start +
    descriptor_size(bytes, width_start, end, count, width_bits)
  let body = length_start +
    descriptor_size(bytes, length_start, end, count, length_bits)
  let available_bits = (end - body).to_int64() * 8L
  let groups : Array[PackedGroup] = []
  let mut first = 0
  let mut position = 0L
  for group in 0..<count {
    let reference = packed_integer(bytes, data, group, packing.width)
    let width = byte_at(bytes, at + 35).to_uint64() +
      packed_integer(bytes, width_start, group, width_bits)
    if width > 32UL {
      raise Unsupported(width_start, "group width exceeds 32 bits")
    }
    let length = if group + 1 == count {
      unsigned(bytes, at + 42, 4)
    } else {
      ref_length +
      length_increment * packed_integer(bytes, length_start, group, length_bits)
    }
    if length > (packing.count - first).to_uint64() {
      raise Invalid(length_start, "group lengths exceed declared value count")
    }
    let bits = length.reinterpret_as_int64() * width.reinterpret_as_int64()
    if bits > available_bits - position {
      raise Invalid(body, "group payload is truncated")
    }
    let stop = first + length.to_int()
    if stop > first {
      groups.push({
        first,
        stop,
        bit: (body - payload).to_int64() * 8L + position,
        width: width.to_int(),
        reference,
      })
    }
    position += bits
    first = stop
  }
  if first != packing.count || (position + 7L) / 8L != (end - body).to_int64() {
    raise Invalid(body, "group payload disagrees with the representation")
  }
  { groups, missing_mode, reference_width: packing.width, }
}

///|
fn is_group_missing(value : UInt64, width : Int32, mode : Int32) -> Bool {
  if width == 0 || mode == 0 {
    return false
  }
  let all_ones = (1UL << width) - 1UL
  value == all_ones || (mode == 2 && value == all_ones - 1UL)
}

///|
fn GroupedPacking::value(
  self : GroupedPacking,
  bytes : Bytes,
  payload : Int32,
  index : Int32,
) -> UInt64? {
  let mut low = 0
  let mut high = self.groups.length()
  while low < high {
    let middle = low + (high - low) / 2
    if self.groups[middle].stop <= index {
      low = middle + 1
    } else {
      high = middle
    }
  }
  let group = self.groups[low]
  if group.width == 0 {
    if is_group_missing(
        group.reference,
        self.reference_width,
        self.missing_mode,
      ) {
      return None
    }
    return Some(group.reference)
  }
  let offset = group.bit +
    (index - group.first).to_int64() * group.width.to_int64()
  let delta = bits_at(bytes, payload, offset, group.width)
  if is_group_missing(delta, group.width, self.missing_mode) {
    None
  } else {
    Some(group.reference + delta)
  }
}
