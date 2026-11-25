///|
pub(all) struct RangeOptions {
  max_points : Int32
  merge_gap : Int32
  max_read : Int32
}

///|
pub fn RangeOptions::standard() -> RangeOptions {
  { max_points: 1000000, merge_gap: 64, max_read: 1048576, }
}

///|
pub(all) struct ReadWindow {
  samples : Array[Sample]
  payload_reads : Int32
  payload_bytes : Int64
  decoded_values : Int32
}

///|
priv struct RequestedSample {
  row : Int32
  column : Int32
  ordinal : Int32?
}

///|
priv struct PackedRequest {
  position : Int32
  ordinal : Int32
  start : Int32
  end : Int32
}

///|
priv struct ReadBatch {
  start : Int32
  end : Int32
  first : Int32
  stop : Int32
}

///|
pub struct RangeField {
  priv source : ByteSource
  grid : Grid
  priv packing : Packing
  priv ieee_width : Int32
  priv bitmap : Bitmap?
  priv bitmap_bytes : Bytes
  priv payload : Int32
}

///|
pub fn open_range_field(
  source : ByteSource,
  field : Field,
) -> RangeField raise GribError {
  let grid_bytes = source.read_exact(
    field.grid_definition.offset,
    if field.grid_definition.length < 72 {
      field.grid_definition.length
    } else {
      72
    },
  )
  if grid_bytes.length() < 14 {
    raise Invalid(field.grid_definition.offset, "truncated grid definition")
  }
  let grid = parse_grid(grid_bytes, { offset: 0, length: grid_bytes.length(), })
  let representation = source.read_exact(
    field.representation.offset,
    if field.representation.length < 21 {
      field.representation.length
    } else {
      21
    },
  )
  if representation.length() < 11 {
    raise Invalid(field.representation.offset, "truncated representation")
  }
  let template = u16(representation, 9)
  let span = { offset: 0, length: representation.length(), }
  let (packing, ieee_width) = match template {
    0 => (parse_packing_definition(representation, span, field.data.length), 0)
    4 => {
      let (width, count) = ieee_precision(
        representation,
        span,
        field.data.length,
      )
      (ieee_packing(width, count), width)
    }
    _ =>
      raise Unsupported(
        field.representation.offset + 9,
        "range reads support simple and IEEE packing",
      )
  }
  let flag = byte_at(source.read_exact(field.bitmap.offset + 5, 1), 0)
  let (bitmap, bitmap_bytes) = if flag == 255 {
    if field.bitmap.length != 6 || grid.points != packing.count {
      raise Invalid(
        field.bitmap.offset,
        "unmasked field count does not match grid",
      )
    }
    (None, b"")
  } else {
    guard field.bitmap_source is Some(span) && (flag == 0 || flag == 254) else {
      raise Unsupported(field.bitmap.offset, "predefined bitmap is unsupported")
    }
    if span.length < 6 || (flag == 254 && field.bitmap.length != 6) {
      raise Invalid(field.bitmap.offset, "invalid bitmap section length")
    }
    let expected = ((grid.points.to_int64() + 7L) / 8L).to_int()
    if span.length - 6 != expected {
      raise Invalid(span.offset, "invalid bitmap payload size")
    }
    let bytes = source.read_exact(span.offset + 6, expected)
    (
      Some(index_bitmap(bytes, 0, bytes.length(), grid.points, packing.count)),
      bytes,
    )
  }
  {
    source,
    grid,
    packing,
    ieee_width,
    bitmap,
    bitmap_bytes,
    payload: field.data.offset + 5,
  }
}

///|
fn range_samples(
  field : RangeField,
  bounds : Bounds,
  max_points : Int32,
) -> Array[RequestedSample] raise GribError {
  let (rows, columns) = window_ranges(field.grid, bounds, max_points)
  let output : Array[RequestedSample] = []
  for row in rows.start..<rows.end {
    for interval in columns {
      for column in interval.start..<interval.end {
        let scan = field.grid.scan_index(row, column)
        let ordinal = match field.bitmap {
          None => Some(scan)
          Some(bitmap) => bitmap.ordinal(field.bitmap_bytes, scan)
        }
        output.push({ row, column, ordinal, })
      }
    }
  }
  output
}

///|
fn packed_requests(
  samples : Array[RequestedSample],
  width : Int32,
) -> Array[PackedRequest] {
  let requests : Array[PackedRequest] = []
  if width == 0 {
    return requests
  }
  let mut ordered = true
  let mut previous = -1
  for position, sample in samples {
    if sample.ordinal is Some(ordinal) {
      ordered = ordered && ordinal >= previous
      previous = ordinal
      let bit = ordinal.to_int64() * width.to_int64()
      requests.push({
        position,
        ordinal,
        start: (bit / 8L).to_int(),
        end: ((bit + width.to_int64() + 7L) / 8L).to_int(),
      })
    }
  }
  if !ordered {
    requests.sort_by((a, b) => a.ordinal.compare(b.ordinal))
  }
  requests
}

///|
fn plan_reads(
  requests : Array[PackedRequest],
  options : RangeOptions,
) -> Array[ReadBatch] {
  let batches : Array[ReadBatch] = []
  if requests.length() == 0 {
    return batches
  }
  let mut first = 0
  let mut start = requests[0].start
  let mut end = requests[0].end
  for i in 1..<requests.length() {
    let request = requests[i]
    if request.start - end <= options.merge_gap &&
      request.end - start <= options.max_read {
      if request.end > end {
        end = request.end
      }
    } else {
      batches.push({ start, end, first, stop: i, })
      start = request.start
      end = request.end
      first = i
    }
  }
  batches.push({ start, end, first, stop: requests.length(), })
  batches
}

///|
pub fn RangeField::window(
  self : RangeField,
  bounds : Bounds,
  options~ : RangeOptions = RangeOptions::standard(),
) -> ReadWindow raise GribError {
  if options.merge_gap < 0 || options.max_read < 8 {
    raise Invalid(self.payload, "invalid range read limits")
  }
  let selected = range_samples(self, bounds, options.max_points)
  let requests = packed_requests(selected, self.packing.width)
  let batches = plan_reads(requests, options)
  let values : Array[Double?] = Array::make(selected.length(), None)
  let mut payload_bytes = 0L
  let mut decoded_values = 0
  if self.packing.width == 0 {
    let value = decode_value(self.payload, self.packing, 0UL)
    for i, sample in selected {
      if sample.ordinal is Some(_) {
        values[i] = Some(value)
        decoded_values += 1
      }
    }
  }
  for batch in batches {
    let size = batch.end - batch.start
    let content = self.source.read_exact(self.payload + batch.start, size)
    payload_bytes += size.to_int64()
    for i in batch.first..<batch.stop {
      let request = requests[i]
      let bit = request.ordinal.to_int64() * self.packing.width.to_int64() -
        batch.start.to_int64() * 8L
      let value = if self.ieee_width > 0 {
        ieee_value(content, (bit / 8L).to_int(), self.ieee_width)
      } else {
        decode_value(
          self.payload,
          self.packing,
          bits_at(content, 0, bit, self.packing.width),
        )
      }
      values[request.position] = Some(value)
      decoded_values += 1
    }
  }
  let samples : Array[Sample] = []
  for i, sample in selected {
    samples.push({
      row: sample.row,
      column: sample.column,
      latitude: self.grid.latitude(sample.row),
      longitude: self.grid.longitude(sample.column),
      value: values[i],
    })
  }
  { samples, payload_reads: batches.length(), payload_bytes, decoded_values, }
}

///|
pub fn ReadWindow::metrics_json(self : ReadWindow) -> Json {
  Json::object(
    Map([
      ("samples", number(self.samples.length())),
      ("payload_reads", number(self.payload_reads)),
      ("payload_bytes", Json::number(self.payload_bytes.to_double())),
      ("decoded_values", number(self.decoded_values)),
      ("missing_points", number(self.samples.length() - self.decoded_values)),
    ]),
  )
}
