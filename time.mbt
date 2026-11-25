///|
pub(all) struct ForecastTime {
  reference : ReferenceTime
  valid : ReferenceTime
  offset_seconds : Int64
}

///|
fn leap_year(year : Int32) -> Bool {
  year % 4 == 0 && (year % 100 != 0 || year % 400 == 0)
}

///|
fn days_in_month(year : Int32, month : Int32) -> Int32 {
  match month {
    2 => if leap_year(year) { 29 } else { 28 }
    4 | 6 | 9 | 11 => 30
    _ => 31
  }
}

///|
fn before_year(year : Int32) -> Int64 {
  let n = (year - 1).to_int64()
  365L * n + n / 4L - n / 100L + n / 400L
}

///|
fn day_number(time : ReferenceTime) -> Int64 {
  let mut result = before_year(time.year)
  for month in 1..<time.month {
    result += days_in_month(time.year, month).to_int64()
  }
  result + (time.day - 1).to_int64()
}

///|
fn to_seconds(time : ReferenceTime) -> Int64 raise GribError {
  if time.year < 1 ||
    time.year > 65535 ||
    time.month < 1 ||
    time.month > 12 ||
    time.day < 1 ||
    time.day > days_in_month(time.year, time.month) ||
    time.hour < 0 ||
    time.hour > 23 ||
    time.minute < 0 ||
    time.minute > 59 ||
    time.second < 0 ||
    time.second > 59 {
    raise Invalid(0, "time must be a Gregorian timestamp without leap seconds")
  }
  day_number(time) * 86400L +
  time.hour.to_int64() * 3600L +
  time.minute.to_int64() * 60L +
  time.second.to_int64()
}

///|
fn from_seconds(seconds : Int64) -> ReferenceTime raise GribError {
  if seconds < 0L || seconds >= before_year(65536) * 86400L {
    raise Unsupported(0, "valid time is outside years 1 through 65535")
  }
  let day = seconds / 86400L
  let remainder = (seconds % 86400L).to_int()
  let mut low = 1
  let mut high = 65536
  while low + 1 < high {
    let mid = low + (high - low) / 2
    if before_year(mid) <= day {
      low = mid
    } else {
      high = mid
    }
  }
  let year = low
  let mut ordinal = (day - before_year(year)).to_int()
  let mut month = 1
  while ordinal >= days_in_month(year, month) {
    ordinal -= days_in_month(year, month)
    month += 1
  }
  {
    year,
    month,
    day: ordinal + 1,
    hour: remainder / 3600,
    minute: remainder / 60 % 60,
    second: remainder % 60,
  }
}

///|
fn seconds_per_unit(code : Int32) -> Int64? {
  match code {
    0 => Some(60L)
    1 => Some(3600L)
    2 => Some(86400L)
    10 => Some(10800L)
    11 => Some(21600L)
    12 => Some(43200L)
    13 => Some(1L)
    _ => None
  }
}

///|
pub fn Metadata::valid_time(self : Metadata) -> ForecastTime? raise GribError {
  if self.product_template != 0 &&
    self.product_template != 1 &&
    self.product_template != 2 {
    return None
  }
  guard self.forecast_unit is Some(unit) && self.forecast_offset is Some(offset) else {
    return None
  }
  guard seconds_per_unit(unit) is Some(seconds) else { return None }
  let offset_seconds = offset.to_int64() * seconds
  let valid = from_seconds(to_seconds(self.origin) + offset_seconds)
  Some({ reference: self.origin, valid, offset_seconds, })
}

///|
pub fn Archive::select_valid_time(
  self : Archive,
  filter : Filter,
  start : ReferenceTime,
  end : ReferenceTime,
) -> Array[Metadata] raise GribError {
  let lower = to_seconds(start)
  let upper = to_seconds(end)
  if lower > upper {
    raise Invalid(0, "time interval is reversed")
  }
  let matches : Array[Metadata] = []
  for field in self.select(filter) {
    if field.valid_time() is Some(time) {
      let target = to_seconds(time.valid)
      if target >= lower && target <= upper {
        matches.push(field)
      }
    }
  }
  matches
}
