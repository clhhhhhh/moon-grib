///|
pub(all) struct StatisticalRange {
  process : Int32
  increment_type : Int32
  range_unit : Int32
  range_length : UInt64?
  increment_unit : Int32
  increment : UInt64?
}

///|
pub(all) struct AggregationInterval {
  start : ReferenceTime?
  end : ReferenceTime
  missing_inputs : UInt64?
  ranges : Array[StatisticalRange]
}

///|
fn available_uint(bytes : Bytes, offset : Int32) -> UInt64? {
  let value = unsigned(bytes, offset, 4)
  if value == 4294967295UL {
    None
  } else {
    Some(value)
  }
}

///|
fn interval_start(metadata : Metadata) -> ReferenceTime? raise GribError {
  guard metadata.forecast_offset is Some(offset) &&
    metadata.forecast_unit is Some(unit) &&
    seconds_per_unit(unit) is Some(scale) else {
    return None
  }
  Some(from_seconds(to_seconds(metadata.origin) + offset.to_int64() * scale))
}

///|
pub fn Archive::aggregation_interval(
  self : Archive,
  index : Int32,
) -> AggregationInterval? raise GribError {
  let field = self.field(index)
  let at = field.product_definition.offset
  if u16(self.bytes, at + 7) != 8 {
    return None
  }
  if field.product_definition.length < 46 {
    raise Invalid(at, "truncated statistical product template")
  }
  let end = parse_time(self.bytes, at + 34)
  let descriptors = byte_at(self.bytes, at + 41)
  if descriptors == 0 || 46 + descriptors * 12 > field.product_definition.length {
    raise Invalid(at + 41, "invalid statistical descriptor count")
  }
  let start = interval_start(self.metadata(index))
  if start is Some(time) && to_seconds(time) > to_seconds(end) {
    raise Invalid(at + 34, "statistical interval ends before it starts")
  }
  let ranges : Array[StatisticalRange] = []
  for i in 0..<descriptors {
    let start = at + 46 + i * 12
    ranges.push({
      process: byte_at(self.bytes, start),
      increment_type: byte_at(self.bytes, start + 1),
      range_unit: byte_at(self.bytes, start + 2),
      range_length: available_uint(self.bytes, start + 3),
      increment_unit: byte_at(self.bytes, start + 7),
      increment: available_uint(self.bytes, start + 8),
    })
  }
  Some({
    start,
    end,
    missing_inputs: available_uint(self.bytes, at + 42),
    ranges,
  })
}

///|
fn optional_unsigned(value : UInt64?) -> Json {
  value.map(value => Json::number(value.to_double())).unwrap_or(Json::null())
}

///|
pub fn StatisticalRange::json(self : StatisticalRange) -> Json {
  Json::object(
    Map([
      ("process", number(self.process)),
      ("increment_type", number(self.increment_type)),
      ("range_unit", number(self.range_unit)),
      ("range_length", optional_unsigned(self.range_length)),
      ("increment_unit", number(self.increment_unit)),
      ("increment", optional_unsigned(self.increment)),
    ]),
  )
}

///|
pub fn AggregationInterval::json(self : AggregationInterval) -> Json {
  Json::object(
    Map([
      (
        "start",
        self.start.map(time => Json::string(time.iso())).unwrap_or(Json::null()),
      ),
      ("end", Json::string(self.end.iso())),
      ("missing_inputs", optional_unsigned(self.missing_inputs)),
      ("ranges", Json::array(self.ranges.map(range => range.json()))),
    ]),
  )
}
