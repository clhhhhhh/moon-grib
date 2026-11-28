///|
pub(all) enum FieldStatus {
  Ready
  Malformed(Int32, String)
  UnsupportedField(Int32, String)
}

///|
pub(all) struct FieldDiagnostic {
  index : Int32
  result : FieldStatus
}

///|
pub fn Archive::validate(
  self : Archive,
  decode_values~ : Bool = false,
) -> Array[FieldDiagnostic] {
  let diagnostics : Array[FieldDiagnostic] = []
  for index in 0..<self.field_count() {
    let result = try {
      ignore(self.metadata(index))
      let field = self.decode(index)
      if decode_values {
        let (rows, columns) = field.dimensions()
        let cursor = field.difference.map(_ => difference_cursor())
        for row in 0..<rows {
          for column in 0..<columns {
            ignore(field.at_cursor(row, column, cursor))
          }
        }
      }
      Ready
    } catch {
      Invalid(offset, reason) => Malformed(offset, reason)
      Unsupported(offset, reason) => UnsupportedField(offset, reason)
    }
    diagnostics.push({ index, result, })
  }
  diagnostics
}

///|
pub fn FieldDiagnostic::json(self : FieldDiagnostic) -> Json {
  let fields = Map([("field", number(self.index))])
  match self.result {
    Ready => fields.set("status", Json::string("ready"))
    Malformed(at, reason) => {
      fields.set("status", Json::string("malformed"))
      fields.set("offset", number(at))
      fields.set("reason", Json::string(reason))
    }
    UnsupportedField(at, reason) => {
      fields.set("status", Json::string("unsupported"))
      fields.set("offset", number(at))
      fields.set("reason", Json::string(reason))
    }
  }
  Json::object(fields)
}
