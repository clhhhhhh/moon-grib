///|
priv struct RowSlice {
  row : Int32
  column : Int32
  count : Int32
  start : Int32
  end : Int32
}

///|
fn row_slices(
  grid : Grid,
  rows : IndexRange,
  columns : Array[IndexRange],
  stride : Int32,
  max_read : Int32,
) -> Array[RowSlice] {
  let slices : Array[RowSlice] = []
  let capacity = max_read / stride
  for row in rows.start..<rows.end {
    for interval in columns {
      let mut column = interval.start
      while column < interval.end {
        let available = interval.end - column
        let count = if available < capacity { available } else { capacity }
        let start = (row * grid.columns + column) * stride
        slices.push({ row, column, count, start, end: start + count * stride, })
        column += count
      }
    }
  }
  slices
}

///|
fn RangeField::read_rows(
  self : RangeField,
  rows : IndexRange,
  columns : Array[IndexRange],
  options : RangeOptions,
) -> ReadWindow raise GribError {
  let stride = self.packing.width / 8
  let slices = row_slices(self.grid, rows, columns, stride, options.max_read)
  let samples : Array[Sample] = []
  let mut reads = 0
  let mut payload_bytes = 0L
  let mut first = 0
  while first < slices.length() {
    let start = slices[first].start
    let mut end = slices[first].end
    let mut stop = first + 1
    while stop < slices.length() {
      let next = slices[stop]
      if next.start - end > options.merge_gap ||
        next.end - start > options.max_read {
        break
      }
      end = next.end
      stop += 1
    }
    let content = self.source.read_exact(self.payload + start, end - start)
    reads += 1
    payload_bytes += (end - start).to_int64()
    for i in first..<stop {
      let slice = slices[i]
      let latitude = self.grid.latitude(slice.row)
      for step in 0..<slice.count {
        let at = slice.start - start + step * stride
        let column = slice.column + step
        let value = if self.ieee_width > 0 {
          ieee_value(content, at, stride)
        } else {
          decode_value(
            self.payload,
            self.packing,
            unsigned(content, at, stride),
          )
        }
        samples.push({
          row: slice.row,
          column,
          latitude,
          longitude: self.grid.longitude(column),
          value: Some(value),
        })
      }
    }
    first = stop
  }
  {
    samples,
    payload_reads: reads,
    payload_bytes,
    decoded_values: samples.length(),
  }
}
