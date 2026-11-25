///|
extern "js" fn write_stdout(bytes : Bytes) -> Unit =
  #| bytes => process.stdout.write(bytes)

///|
fn main raise {
  let grid : @grib.RegularGridSpec = {
    rows: 2,
    columns: 3,
    latitude_microdegrees: 40000000,
    longitude_microdegrees: 100000000,
    i_increment_microdegrees: 1000000,
    j_increment_microdegrees: -1000000,
  }
  let product : @grib.ProductSpec = {
    variable: { discipline: 0, category: 0, parameter: 0, },
    reference: {
      year: 2024,
      month: 2,
      day: 28,
      hour: 23,
      minute: 0,
      second: 0,
    },
    centre: 98,
    subcentre: 0,
    forecast_unit: 1,
    forecast_offset: 2,
    level_kind: 103,
    level_value: Some(2),
  }
  let simple = @grib.encode_simple(
    grid,
    product,
    { binary_scale: -1, decimal_scale: 0, },
    [Some(550U), None, Some(552U), Some(554U), Some(556U), Some(558U)],
  )
  let ieee = @grib.encode_ieee(grid, product, [
    Some(275.0),
    None,
    Some(276.0),
    Some(277.0),
    Some(278.0),
    Some(279.0),
  ])
  write_stdout(simple + ieee)
}
