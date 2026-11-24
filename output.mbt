///|
fn number(value : Int32) -> Json {
  Json::number(value.to_double())
}

///|
fn optional_number(value : Int32?) -> Json {
  value.map(number).unwrap_or(Json::null())
}

///|
fn surface_json(surface : Surface?) -> Json {
  match surface {
    None => Json::null()
    Some(value) =>
      Json::object(
        Map([
          ("kind", number(value.kind)),
          (
            "value",
            value.value
            .map(number => Json::number(number))
            .unwrap_or(Json::null()),
          ),
        ]),
      )
  }
}

///|
pub fn Metadata::json(self : Metadata) -> Json {
  Json::object(
    Map([
      ("field", number(self.field_index)),
      ("offset", number(self.message.offset)),
      ("length", number(self.message.length)),
      ("reference_time", Json::string(self.origin.iso())),
      ("centre", number(self.centre)),
      ("subcentre", number(self.subcentre)),
      ("discipline", number(self.variable.discipline)),
      ("category", number(self.variable.category)),
      ("parameter", number(self.variable.parameter)),
      ("grid_template", number(self.grid_template)),
      ("product_template", number(self.product_template)),
      ("packing_template", number(self.packing_template)),
      ("forecast_unit", optional_number(self.forecast_unit)),
      ("forecast_offset", optional_number(self.forecast_offset)),
      ("first_surface", surface_json(self.first_surface)),
      ("second_surface", surface_json(self.second_surface)),
    ]),
  )
}

///|
pub fn Sample::json(self : Sample) -> Json {
  Json::object(
    Map([
      ("row", number(self.row)),
      ("column", number(self.column)),
      ("latitude", Json::number(self.latitude)),
      ("longitude", Json::number(self.longitude)),
      (
        "value",
        self.value.map(value => Json::number(value)).unwrap_or(Json::null()),
      ),
    ]),
  )
}

///|
pub fn samples_csv(samples : Array[Sample]) -> String {
  let out = StringBuilder()
  out.write_string("row,column,latitude,longitude,value\n")
  for sample in samples {
    out.write_string(sample.row.to_string())
    out.write_char(',')
    out.write_string(sample.column.to_string())
    out.write_char(',')
    out.write_string(sample.latitude.to_string())
    out.write_char(',')
    out.write_string(sample.longitude.to_string())
    out.write_char(',')
    if sample.value is Some(value) {
      out.write_string(value.to_string())
    }
    out.write_char('\n')
  }
  out.to_string()
}
