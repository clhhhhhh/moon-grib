///|
priv struct IndexRange {
  start : Int32
  end : Int32
}

///|
fn axis_edge(
  origin : Double,
  positive_step : Double,
  length : Int32,
  boundary : Double,
  upper : Bool,
) -> Int32 {
  let mut low = 0
  let mut high = length
  while low < high {
    let middle = low + (high - low) / 2
    let value = origin + middle.to_double() * positive_step
    if value < boundary || (upper && value == boundary) {
      low = middle + 1
    } else {
      high = middle
    }
  }
  low
}

///|
fn axis_range(
  origin : Double,
  step : Double,
  length : Int32,
  low : Double,
  high : Double,
) -> IndexRange {
  let ascending_origin = if step < 0.0 {
    origin + (length - 1).to_double() * step
  } else {
    origin
  }
  let left = axis_edge(
    ascending_origin,
    step.abs(),
    length,
    low - 0.000000001,
    false,
  )
  let right = axis_edge(
    ascending_origin,
    step.abs(),
    length,
    high + 0.000000001,
    true,
  )
  if step < 0.0 {
    { start: length - right, end: length - left, }
  } else {
    { start: left, end: right, }
  }
}

///|
fn longitude_ranges(grid : Grid, bounds : Bounds) -> Array[IndexRange] {
  let intervals : Array[IndexRange] = []
  let east = if bounds.east < bounds.west {
    bounds.east + 360.0
  } else {
    bounds.east
  }
  for turn in -2..<3 {
    let adjustment = turn.to_double() * 360.0
    let selected = axis_range(
      grid.first_longitude,
      grid.longitude_step,
      grid.columns,
      bounds.west + adjustment,
      east + adjustment,
    )
    if selected.start < selected.end {
      intervals.push(selected)
    }
  }
  intervals.sort_by((x, y) => x.start.compare(y.start))
  let merged : Array[IndexRange] = []
  for interval in intervals {
    let last = merged.length() - 1
    if last >= 0 && interval.start <= merged[last].end {
      let previous = merged[last]
      if interval.end > previous.end {
        merged[last] = { start: previous.start, end: interval.end, }
      }
    } else {
      merged.push(interval)
    }
  }
  merged
}
