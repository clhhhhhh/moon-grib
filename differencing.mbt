///|
priv struct Difference {
  seeds : Array[Int64]
  minimum : Int64
}

///|
priv struct DifferenceState {
  initialized : Int32
  previous : Int64
  before_previous : Int64
}

///|
priv struct DifferenceIndex {
  spec : Difference
  checkpoints : Array[DifferenceState]
}

///|
fn parse_difference(
  bytes : Bytes,
  field : Field,
) -> (Difference, Int32) raise GribError {
  let at = field.representation.offset
  if field.representation.length < 49 {
    raise Invalid(at, "truncated differencing template")
  }
  let order = byte_at(bytes, at + 47)
  let width = byte_at(bytes, at + 48)
  if (order != 1 && order != 2) || width < 1 || width > 4 {
    raise Unsupported(
      at + 47,
      "unsupported differencing order or descriptor width",
    )
  }
  let size = (order + 1) * width
  let payload = field.data.offset + 5
  if field.data.length - 5 < size {
    raise Invalid(payload, "truncated differencing descriptors")
  }
  let seeds : Array[Int64] = []
  for i in 0..<order {
    seeds.push(
      unsigned(bytes, payload + i * width, width).reinterpret_as_int64(),
    )
  }
  let minimum = signed_magnitude(bytes, payload + order * width, width).to_int64()
  ({ seeds, minimum, }, size)
}

///|
fn Difference::advance(
  self : Difference,
  previous : DifferenceState,
  code : UInt64,
  at : Int32,
) -> DifferenceState raise GribError {
  let value = if previous.initialized < self.seeds.length() {
    self.seeds[previous.initialized]
  } else {
    let delta = self.minimum + code.reinterpret_as_int64()
    if self.seeds.length() == 1 {
      previous.previous + delta
    } else {
      previous.previous * 2L - previous.before_previous + delta
    }
  }
  if value < 0L || value > 9007199254740991L {
    raise Invalid(at, "reconstructed packed value is out of range")
  }
  {
    initialized: if previous.initialized < self.seeds.length() {
      previous.initialized + 1
    } else {
      previous.initialized
    },
    previous: value,
    before_previous: previous.previous,
  }
}

///|
fn build_difference_index(
  spec : Difference,
  grouped : GroupedPacking,
  bytes : Bytes,
  payload : Int32,
  count : Int32,
) -> DifferenceIndex raise GribError {
  if count > 20000000 {
    raise Unsupported(payload, "differencing prepass exceeds resource limit")
  }
  let checkpoints : Array[DifferenceState] = []
  let mut state : DifferenceState = {
    initialized: 0,
    previous: 0L,
    before_previous: 0L,
  }
  for i in 0..<count {
    if i % 256 == 0 {
      checkpoints.push(state)
    }
    if grouped.value(bytes, payload, i) is Some(code) {
      state = spec.advance(state, code, payload)
    }
  }
  { spec, checkpoints, }
}

///|
fn DifferenceIndex::value(
  self : DifferenceIndex,
  grouped : GroupedPacking,
  bytes : Bytes,
  payload : Int32,
  index : Int32,
) -> UInt64? raise GribError {
  let block = index / 256
  let mut state = self.checkpoints[block]
  for i in (block * 256)..<(index + 1) {
    match grouped.value(bytes, payload, i) {
      Some(code) => {
        state = self.spec.advance(state, code, payload)
        if i == index {
          return Some(state.previous.reinterpret_as_uint64())
        }
      }
      None => if i == index { return None }
    }
  }
  None
}
