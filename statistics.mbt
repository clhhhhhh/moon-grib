///|
pub(all) struct Statistics {
  points : Int32
  present : Int32
  missing : Int32
  minimum : Double?
  maximum : Double?
  mean : Double?
  population_variance : Double?
}

///|
priv struct Moment {
  mut points : Int32
  mut present : Int32
  mut minimum : Double
  mut maximum : Double
  mut mean : Double
  mut squared : Double
}

///|
fn Moment::add(self : Moment, sample : Sample) -> Unit {
  self.points += 1
  if sample.value is Some(value) {
    if self.present == 0 {
      self.minimum = value
      self.maximum = value
      self.mean = value
    } else {
      if value < self.minimum {
        self.minimum = value
      }
      if value > self.maximum {
        self.maximum = value
      }
      let delta = value - self.mean
      let count = (self.present + 1).to_double()
      self.mean = if delta.is_inf() {
        // Opposite-sign finite extrema can overflow the subtraction.
        self.mean * (self.present.to_double() / count) + value / count
      } else {
        self.mean + delta / count
      }
      self.squared += delta * (value - self.mean)
    }
    self.present += 1
  }
}

///|
fn Moment::finish(self : Moment) -> Statistics {
  let any = self.present > 0
  let variance = self.squared / self.present.to_double()
  {
    points: self.points,
    present: self.present,
    missing: self.points - self.present,
    minimum: if any {
      Some(self.minimum)
    } else {
      None
    },
    maximum: if any {
      Some(self.maximum)
    } else {
      None
    },
    mean: if any && !self.mean.is_inf() && !self.mean.is_nan() {
      Some(self.mean)
    } else {
      None
    },
    population_variance: if any && !variance.is_inf() && !variance.is_nan() {
      Some(if variance < 0.0 { 0.0 } else { variance })
    } else {
      None
    },
  }
}

///|
pub fn DecodedField::statistics(
  self : DecodedField,
  bounds : Bounds,
  max_points~ : Int32 = 1000000,
) -> Statistics raise GribError {
  let moments : Moment = {
    points: 0,
    present: 0,
    minimum: 0.0,
    maximum: 0.0,
    mean: 0.0,
    squared: 0.0,
  }
  self.visit_window(bounds, sample => moments.add(sample), max_points~)
  moments.finish()
}

///|
fn optional_real(value : Double?) -> Json {
  value.map(value => Json::number(value)).unwrap_or(Json::null())
}

///|
pub fn Statistics::json(self : Statistics) -> Json {
  Json::object(
    Map([
      ("points", number(self.points)),
      ("present", number(self.present)),
      ("missing", number(self.missing)),
      ("minimum", optional_real(self.minimum)),
      ("maximum", optional_real(self.maximum)),
      ("mean", optional_real(self.mean)),
      ("population_variance", optional_real(self.population_variance)),
    ]),
  )
}
