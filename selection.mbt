///|
priv struct IndexRange {
  start : Int32
  end : Int32
}

///|
fn axis_edge(
  coordinate : (Int32) -> Double,
  length : Int32,
  boundary : Double,
  upper : Bool,
) -> Int32 {
  let mut low = 0
  let mut high = length
  while low < high {
    let middle = low + (high - low) / 2
    let value = coordinate(middle)
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
    index => ascending_origin + index.to_double() * step.abs(),
    length,
    low - 0.000000001,
    false,
  )
  let right = axis_edge(
    index => ascending_origin + index.to_double() * step.abs(),
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

///|
fn latitude_range(grid : Grid, bounds : Bounds) -> IndexRange {
  let descending = grid.latitude(0) > grid.latitude(grid.rows - 1)
  let coord = index => {
    grid.latitude(if descending { grid.rows - 1 - index } else { index })
  }
  let left = axis_edge(coord, grid.rows, bounds.south - 0.000000001, false)
  let right = axis_edge(coord, grid.rows, bounds.north + 0.000000001, true)
  if descending {
    { start: grid.rows - right, end: grid.rows - left, }
  } else {
    { start: left, end: right, }
  }
}
