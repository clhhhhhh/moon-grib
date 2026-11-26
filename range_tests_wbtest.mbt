///|
test "indexed range reads match normal decoding and never request the full data section" {
  let bytes = fixture(0, true)
  let spans : Array[(Int32, Int32)] = []
  let source = ByteSource::new(bytes.length(), (start, length) => {
    spans.push((start, length))
    bytes[start:start + length].to_owned()
  })
  let indexed = open_indexed(source)
  let regular = open_archive(bytes)
  assert_eq(indexed.metadata(0).json(), regular.metadata(0).json())
  let bounds : Bounds = { west: 179.5, east: -178.5, south: 1.0, north: 1.0, }
  let ranged = indexed.decode(0).window(bounds)
  assert_eq(
    samples_csv(ranged.samples),
    samples_csv(regular.decode(0).window(bounds)),
  )
  assert_eq(ranged.payload_bytes, 1L)
  assert_eq(ranged.decoded_values, 1)
  assert_true(spans.all(pair => pair.1 < bytes.length()))
  assert_eq(indexed.raw_message(0), bytes)
}

///|
test "short positioned reads return an error" {
  let source = ByteSource::new(42, (_, _) => b"x")
  let rejected = try {
    ignore(source.read_exact(0, 2))
    false
  } catch {
    Invalid(_, _) => true
    _ => false
  }
  assert_true(rejected)
}

///|
fn writer_specs() -> (RegularGridSpec, ProductSpec) {
  let grid : RegularGridSpec = {
    rows: 2,
    columns: 2,
    latitude_microdegrees: 1000000,
    longitude_microdegrees: 2000000,
    i_increment_microdegrees: 1000000,
    j_increment_microdegrees: -1000000,
  }
  let product : ProductSpec = {
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
  (grid, product)
}

///|
test "writer round trips IEEE values and simple integer codes" {
  let (grid, product) = writer_specs()
  let bounds : Bounds = { west: 2.0, east: 3.0, south: 0.0, north: 1.0, }
  let ieee = encode_ieee(grid, product, [
    Some(-2.25),
    Some(5.0),
    None,
    Some(4.0),
  ])
  let ieee_field = open_archive(ieee).decode(0)
  assert_eq(ieee_field.at(0, 0).value, Some(-2.25))
  let source = ByteSource::new(ieee.length(), (start, length) => {
    ieee[start:start + length].to_owned()
  })
  let ranged = open_indexed(source).decode(0).window(bounds)
  assert_eq(ranged.payload_bytes, 24L)
  assert_eq(samples_csv(ranged.samples), samples_csv(ieee_field.window(bounds)))
  let simple = encode_simple(
    grid,
    product,
    { binary_scale: -1, decimal_scale: 0, },
    [Some(0U), Some(5U), None, Some(3U)],
  )
  let archive = open_archive(simple)
  assert_eq(archive.decode(0).at(0, 1).value, Some(2.5))
  assert_eq(archive.decode(0).at(1, 0).value, None)
  let valid = archive.metadata(0).valid_time()
  assert_eq(valid.map(value => value.valid.iso()), Some("2024-02-29T01:00:00Z"))
}

///|
test "bilinear missing policy and raster orientation" {
  let (grid, product) = writer_specs()
  let archive = open_archive(
    encode_ieee(grid, product, [Some(0.0), Some(2.0), None, Some(4.0)]),
  )
  let field = archive.decode(0)
  let point : Position = { latitude: 0.5, longitude: 2.5, }
  assert_eq(field.estimate(point, interpolation=Bilinear).value, None)
  assert_eq(
    field.estimate(point, interpolation=Bilinear, missing=Renormalize).value,
    Some(2.0),
  )
  let bounds : Bounds = { west: 2.0, east: 3.0, south: 0.0, north: 1.0, }
  let raster = field.raster(bounds)
  assert_eq(raster.value(0, 1), Some(2.0))
  assert_true(raster.ascii_grid().contains("NODATA_value -9999"))
  assert_eq(field.compare_window(field, bounds).paired, 3)
  assert_eq(field.compare_window(field, bounds).both_missing, 1)
}

///|
test "area statistics and resampling distinguish missing points" {
  let (grid, product) = writer_specs()
  let field = open_archive(
    encode_ieee(grid, product, [Some(2.0), Some(2.0), None, Some(2.0)]),
  ).decode(0)
  let bounds : Bounds = { west: 2.0, east: 3.0, south: 0.0, north: 1.0, }
  let area = field.area_statistics(bounds)
  assert_eq(area.present, 3)
  assert_true(area.footprint_steradians > area.covered_steradians)
  assert_eq(area.weighted_mean, Some(2.0))
  let target : TargetGrid = {
    rows: 3,
    columns: 3,
    north: 1.0,
    west: 2.0,
    latitude_spacing: 0.5,
    longitude_spacing: 0.5,
  }
  let changed = field.resample(target, missing=Renormalize)
  assert_eq(changed.present, 8)
  assert_eq(changed.raster.value(1, 1), Some(2.0))
  assert_eq(changed.raster.value(2, 0), None)
}

///|
test "range planning preserves logical order across scanning modes" {
  for mode in [0, 16, 32, 48, 64, 128, 240] {
    let bytes = fixture(mode, true)
    let direct = open_archive(bytes).decode(0)
    let source = ByteSource::new(bytes.length(), (start, length) => {
      bytes[start:start + length].to_owned()
    })
    let indexed = open_indexed(source).decode(0)
    let bounds : Bounds = {
      west: -180.0,
      east: 180.0,
      south: -90.0,
      north: 90.0,
    }
    assert_eq(
      samples_csv(indexed.window(bounds).samples),
      samples_csv(direct.window(bounds)),
    )
  }
}

///|
test "a longitude miss collapses the row loop even when all latitudes match" {
  let field = open_archive(fixture(0, false)).decode(0)
  let bounds = { west: 20.0, east: 30.0, south: -90.0, north: 90.0, }
  let (rows, columns) = window_ranges(field.grid, bounds, 0)
  assert_eq(rows.start, rows.end)
  assert_true(columns.is_empty())
  assert_true(field.window(bounds, max_points=0).is_empty())
}

///|
test "opposite IEEE extrema have a finite mean even when variance overflows" {
  let (grid, product) = writer_specs()
  let bytes = encode_ieee(grid, product, [
    Some(-1.7e308),
    Some(1.7e308),
    None,
    None,
  ])
  let stats = open_archive(bytes)
    .decode(0)
    .statistics({ west: -180.0, east: 180.0, south: -90.0, north: 90.0, })
  assert_eq(stats.present, 2)
  assert_eq(stats.mean, Some(0.0))
  assert_eq(stats.population_variance, None)
}

///|
test "shared grid and bitmap references remain scoped to one message" {
  let bytes = fixture(0, true)
  let original = open_archive(bytes).field(0)
  let extra_product = bytes[original.product_definition.offset:original.bitmap.offset].to_owned()
  let reused_bitmap = b"\x00\x00\x00\x06\x06\xfe"
  let extra_data = bytes[original.data.offset:original.data.offset +
  original.data.length].to_owned()
  let prefix = bytes[:bytes.length() - 4].to_owned()
  let payload = prefix + extra_product + reused_bitmap + extra_data + b"7777"
  let assembled : Array[Byte] = []
  for octet in payload {
    assembled.push(octet)
  }
  put(assembled, 8, 8, assembled.length().to_uint64())
  let message = Bytes::from_array(assembled[:])
  let archive = open_archive(message + bytes)
  assert_eq(archive.field_count(), 3)
  assert_eq(
    archive.field(1).bitmap_source.map(span => span.offset),
    Some(original.bitmap.offset),
  )
  let source = ByteSource::new(message.length(), (start, length) => {
    message[start:start + length].to_owned()
  })
  let bounds : Bounds = {
    west: -180.0,
    east: 180.0,
    south: -90.0,
    north: 90.0,
  }
  let first = archive.decode(0).window(bounds)
  assert_eq(samples_csv(first), samples_csv(archive.decode(1).window(bounds)))
  assert_eq(
    samples_csv(first),
    samples_csv(open_indexed(source).decode(1).window(bounds).samples),
  )
}
