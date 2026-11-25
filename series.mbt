///|
pub(all) struct SeriesPoint {
  field_index : Int32
  time : ForecastTime
  location : EstimatedValue
}

///|
pub(all) struct SeriesOptions {
  interpolation : InterpolationMethod
  missing : MissingPolicy
  max_fields : Int32
}

///|
pub fn SeriesOptions::standard() -> SeriesOptions {
  { interpolation: Nearest, missing: RequireAll, max_fields: 10000, }
}

///|
priv struct SeriesField {
  metadata : Metadata
  time : ForecastTime
  order : Int64
}

///|
fn ordered_series_fields(
  archive : Archive,
  filter : Filter,
  start : ReferenceTime,
  end : ReferenceTime,
  limit : Int32,
) -> Array[SeriesField] raise GribError {
  let matches = archive.select_valid_time(filter, start, end)
  if matches.length() > limit {
    raise Unsupported(0, "series exceeds field limit")
  }
  let candidates : Array[SeriesField] = []
  for metadata in matches {
    if metadata.valid_time() is Some(time) {
      candidates.push({ metadata, time, order: to_seconds(time.valid), })
    }
  }
  candidates.sort_by((a, b) => {
    if a.order == b.order {
      a.metadata.field_index.compare(b.metadata.field_index)
    } else {
      a.order.compare(b.order)
    }
  })
  candidates
}

///|
pub fn Archive::point_series(
  self : Archive,
  filter : Filter,
  pos : Position,
  start : ReferenceTime,
  end : ReferenceTime,
  options~ : SeriesOptions = SeriesOptions::standard(),
) -> Array[SeriesPoint] raise GribError {
  assert_position(pos)
  if options.max_fields < 0 {
    raise Invalid(0, "field limit must be nonnegative")
  }
  let fields = ordered_series_fields(
    self,
    filter,
    start,
    end,
    options.max_fields,
  )
  let result : Array[SeriesPoint] = []
  for candidate in fields {
    let field_index = candidate.metadata.field_index
    let location = self
      .decode(field_index)
      .estimate(
        pos,
        interpolation=options.interpolation,
        missing=options.missing,
      )
    result.push({ field_index, time: candidate.time, location, })
  }
  result
}

///|
pub fn SeriesPoint::json(self : SeriesPoint) -> Json {
  Json::object(
    Map([
      ("field", number(self.field_index)),
      ("reference_time", Json::string(self.time.reference.iso())),
      ("valid_time", Json::string(self.time.valid.iso())),
      ("sample", self.location.json()),
    ]),
  )
}

///|
pub(all) struct RegionalSeriesPoint {
  field_index : Int32
  time : ForecastTime
  statistics : Statistics
}

///|
pub fn Archive::regional_series(
  self : Archive,
  filter : Filter,
  bounds : Bounds,
  start : ReferenceTime,
  end : ReferenceTime,
  max_fields~ : Int32 = 10000,
  max_points~ : Int32 = 1000000,
) -> Array[RegionalSeriesPoint] raise GribError {
  validate_bounds(bounds)
  if max_fields < 0 || max_points < 0 {
    raise Invalid(0, "series limits must be nonnegative")
  }
  let fields = ordered_series_fields(self, filter, start, end, max_fields)
  let result : Array[RegionalSeriesPoint] = []
  let mut remaining = max_points
  for candidate in fields {
    let field_index = candidate.metadata.field_index
    let statistics = self
      .decode(field_index)
      .statistics(bounds, max_points=remaining)
    remaining -= statistics.points
    result.push({ field_index, time: candidate.time, statistics, })
  }
  result
}

///|
pub fn RegionalSeriesPoint::json(self : RegionalSeriesPoint) -> Json {
  Json::object(
    Map([
      ("field", number(self.field_index)),
      ("reference_time", Json::string(self.time.reference.iso())),
      ("valid_time", Json::string(self.time.valid.iso())),
      ("statistics", self.statistics.json()),
    ]),
  )
}
