///|
pub(all) struct Filter {
  discipline : Int32?
  category : Int32?
  parameter : Int32?
  centre : Int32?
  surface_kind : Int32?
  forecast_unit : Int32?
  forecast_offset : Int32?
  reference_time : String?
}

///|
pub fn Filter::empty() -> Filter {
  {
    discipline: None,
    category: None,
    parameter: None,
    centre: None,
    surface_kind: None,
    forecast_unit: None,
    forecast_offset: None,
    reference_time: None,
  }
}

///|
fn int_matches(wanted : Int32?, actual : Int32?) -> Bool {
  wanted is None || wanted == actual
}

///|
pub fn Filter::matches(self : Filter, value : Metadata) -> Bool {
  int_matches(self.discipline, Some(value.variable.discipline)) &&
  int_matches(self.category, Some(value.variable.category)) &&
  int_matches(self.parameter, Some(value.variable.parameter)) &&
  int_matches(self.centre, Some(value.centre)) &&
  int_matches(
    self.surface_kind,
    value.first_surface.map(surface => surface.kind),
  ) &&
  int_matches(self.forecast_unit, value.forecast_unit) &&
  int_matches(self.forecast_offset, value.forecast_offset) &&
  (
    self.reference_time is None ||
    self.reference_time == Some(value.origin.iso())
  )
}

///|
pub fn Archive::select(
  self : Archive,
  filter : Filter,
) -> Array[Metadata] raise GribError {
  let matches : Array[Metadata] = []
  for i in 0..<self.field_count() {
    let value = self.metadata(i)
    if filter.matches(value) {
      matches.push(value)
    }
  }
  matches
}
