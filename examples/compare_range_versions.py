"""Measure identical window queries against ecCodes and an optional older CLI."""

import argparse
import csv
import io
import json
import statistics
import subprocess
import tempfile
from pathlib import Path
from time import perf_counter

import eccodes
import numpy as np

from verify_eccodes import CLI


ROWS = 181
COLUMNS = 360


def make_sample(path, packing, width, masked, column_order=False):
    gid = eccodes.codes_grib_new_from_samples("regular_ll_sfc_grib2")
    try:
        for key, value in {
            "Ni": COLUMNS, "Nj": ROWS,
            "latitudeOfFirstGridPointInDegrees": 90.0,
            "latitudeOfLastGridPointInDegrees": -90.0,
            "longitudeOfFirstGridPointInDegrees": 0.0,
            "longitudeOfLastGridPointInDegrees": 359.0,
            "iDirectionIncrementInDegrees": 1.0,
            "jDirectionIncrementInDegrees": 1.0,
            "jPointsAreConsecutive": int(column_order),
            "packingType": packing,
            "bitsPerValue": width,
            "bitmapPresent": int(masked),
            "missingValue": 9999.0,
        }.items():
            eccodes.codes_set(gid, key, value)
        values = (np.arange(ROWS * COLUMNS, dtype=float) % 512) / 4
        if masked:
            values[::7] = 9999.0
        eccodes.codes_set_values(gid, values)
        with path.open("wb") as out:
            eccodes.codes_write(gid, out)
    finally:
        eccodes.codes_release(gid)


def expected_rows(path, bounds, masked, column_order):
    with path.open("rb") as stream:
        gid = eccodes.codes_grib_new_from_file(stream)
        try:
            latitudes = eccodes.codes_get_array(gid, "latitudes")
            longitudes = eccodes.codes_get_array(gid, "longitudes")
            values = eccodes.codes_get_values(gid)
            present = eccodes.codes_get_array(gid, "bitmap") if masked else np.ones(len(values))
        finally:
            eccodes.codes_release(gid)
    west, south, east, north = bounds
    result = {}
    for i, (lat, longitude, value, valid) in enumerate(zip(latitudes, longitudes, values, present)):
        lon = (longitude + 180) % 360 - 180
        in_lon = west <= lon <= east if west <= east else lon >= west or lon <= east
        if south <= lat <= north and in_lon:
            row, column = (i % ROWS, i // ROWS) if column_order else divmod(i, COLUMNS)
            result[row, column] = (lat, lon, value if valid else None)
    return result


def run_cli(cli, path, bounds):
    start = perf_counter()
    result = subprocess.run(["node", str(cli), "range-window", str(path), "0", *map(str, bounds)],
                            check=True, capture_output=True, text=True)
    return result.stdout, json.loads(result.stderr), (perf_counter() - start) * 1000


def compare(path, name, bounds, masked, column_order, baseline, runs):
    expected = expected_rows(path, bounds, masked, column_order)
    paths = {"current": CLI}
    if baseline is not None:
        paths["baseline"] = baseline
    times = {key: [] for key in paths}
    reports = {}
    reference = None
    for iteration in range(runs):
        order = list(paths) if iteration % 2 == 0 else list(reversed(paths))
        for key in order:
            output, metrics, elapsed = run_cli(paths[key], path, bounds)
            if reference is None:
                reference = output
                rows = list(csv.DictReader(io.StringIO(output)))
                assert len(rows) == len(expected), name
                actual = {
                    (int(row["row"]), int(row["column"])): (
                        float(row["latitude"]), float(row["longitude"]),
                        float(row["value"]) if row["value"] else None,
                    )
                    for row in rows
                }
                assert actual == expected, name
            else:
                assert output == reference, (name, key)
            times[key].append(elapsed)
            reports[key] = metrics
    return {"scenario": name, "bounds": bounds, "points": len(expected),
            "missing": sum(value[2] is None for value in expected.values()),
            "file_bytes": path.stat().st_size, "reads": reports,
            "median_wall_ms": {key: round(statistics.median(value), 2)
                               for key, value in times.items()}}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--baseline", type=Path)
    parser.add_argument("--runs", type=int, default=5)
    args = parser.parse_args()
    if args.runs < 1:
        parser.error("--runs must be positive")
    cases = [
        ("small", "grid_simple", 16, False, False, [8, 39, 12, 42]),
        ("large", "grid_simple", 16, False, False, [0, -45, 120, 45]),
        ("date_line", "grid_simple", 16, False, False, [175, -5, -175, 5]),
        ("bitmap_nonbyte", "grid_simple", 11, True, False, [8, -5, 60, 10]),
        ("column_major", "grid_simple", 16, False, True, [8, -5, 60, 10]),
        ("ieee", "grid_ieee", 0, False, False, [0, -45, 120, 45]),
    ]
    with tempfile.TemporaryDirectory() as directory:
        path = Path(directory) / "global.grib2"
        results = []
        for name, packing, width, masked, column_order, bounds in cases:
            make_sample(path, packing, width, masked, column_order)
            results.append(compare(path, name, bounds, masked, column_order, args.baseline, args.runs))
        print(json.dumps(results, indent=2))


if __name__ == "__main__":
    main()
