"""Generate regular-grid fixtures with ecCodes and compare MoonGRIB results."""
import csv
import io
import json
from pathlib import Path
import subprocess
import sys
import tempfile
from time import perf_counter

import eccodes
import numpy as np


CLI = Path("_build/js/debug/build/cmd/main/main.js").resolve()
PACKING_TEMPLATES = {
    "grid_simple": 0, "grid_complex": 2,
    "grid_complex_spatial_differencing": 3, "grid_ieee": 4,
}


def invoke(*args):
    return subprocess.run(["node", str(CLI), *map(str, args)], capture_output=True,
                          text=True, check=True).stdout


def source(path, size, bitmap, packing):
    gid = eccodes.codes_grib_new_from_samples("regular_ll_sfc_grib2")
    try:
        increment = 0.1
        inputs = {
            "Ni": size, "Nj": size,
            "latitudeOfFirstGridPointInDegrees": 40.0,
            "latitudeOfLastGridPointInDegrees": 40.0 - (size - 1) * increment,
            "longitudeOfFirstGridPointInDegrees": 100.0,
            "longitudeOfLastGridPointInDegrees": 100.0 + (size - 1) * increment,
            "iDirectionIncrementInDegrees": increment,
            "jDirectionIncrementInDegrees": increment,
            "packingType": packing,
            "paramId": 167,
            "bitsPerValue": 16,
            "bitmapPresent": int(bitmap),
            "missingValue": 9999.0,
        }
        for key, value in inputs.items():
            eccodes.codes_set(gid, key, value)
        values = (np.arange(size * size, dtype=float) % 1024) / 16
        if bitmap:
            values[::7] = 9999.0
        eccodes.codes_set_values(gid, values)
        with path.open("wb") as stream:
            eccodes.codes_write(gid, stream)
    finally:
        eccodes.codes_release(gid)


def check_case(path, size, bitmap, packing, gaussian=False, bounds=None):
    if gaussian:
        sample = eccodes.codes_grib_new_from_samples("regular_gg_sfc_grib2")
        try:
            columns = eccodes.codes_get(sample, "Ni")
            rows = eccodes.codes_get(sample, "Nj")
            eccodes.codes_set_values(sample, np.arange(rows * columns, dtype=float))
            with path.open("wb") as out:
                eccodes.codes_write(sample, out)
        finally:
            eccodes.codes_release(sample)
    else:
        rows = columns = size
        source(path, size, bitmap, packing)
    with path.open("rb") as stream:
        gid = eccodes.codes_grib_new_from_file(stream)
    try:
        if bounds is None:
            bounds = (0.0, 35.0, 12.0, 44.0) if gaussian else (101.0, 38.0, 102.0, 39.0)
        west, south, east, north = bounds
        expected = {}
        latitudes = eccodes.codes_get_array(gid, "latitudes")
        longitudes = eccodes.codes_get_array(gid, "longitudes")
        values = eccodes.codes_get_values(gid)
        mask = eccodes.codes_get_array(gid, "bitmap") if bitmap else np.ones(len(values))
        for i, (lat, lon, value, valid) in enumerate(zip(latitudes, longitudes, values, mask)):
            if west - 1e-9 <= lon <= east + 1e-9 and south - 1e-9 <= lat <= north + 1e-9:
                expected[divmod(i, columns)] = (lat, lon, value if valid else None)
        start = perf_counter()
        output = invoke("window", path, 0, west, south, east, north)
        elapsed = perf_counter() - start
        rows = list(csv.DictReader(io.StringIO(output)))
        assert expected, "empty oracle window"
        assert len(rows) == len(expected)
        assert len({(row["row"], row["column"]) for row in rows}) == len(rows)
        for row in rows:
            key = (int(row["row"]), int(row["column"]))
            lat, lon, value = expected.pop(key)
            assert abs(float(row["latitude"]) - lat) < 1e-8
            assert abs(float(row["longitude"]) - lon) < 1e-8
            if value is None:
                assert row["value"] == ""
            else:
                assert abs(float(row["value"]) - value) < 1e-8
        assert not expected
        inventory = json.loads(invoke("inventory", path))
        assert inventory["length"] == path.stat().st_size
        assert inventory["grid_template"] == (40 if gaussian else 0)
        assert inventory["packing_template"] == PACKING_TEMPLATES[packing]
        if packing in ("grid_simple", "grid_ieee"):
            assert invoke("range-window", path, 0, west, south, east, north) == output
        return {"grid": [eccodes.codes_get(gid, "Ni"), eccodes.codes_get(gid, "Nj")],
                "grid_template": inventory["grid_template"], "bitmap": bitmap, "packing": packing, "verified_points": len(rows),
                "missing_points": sum(row["value"] == "" for row in rows),
                "cli_wall_seconds": round(elapsed, 4)}, output
    finally:
        eccodes.codes_release(gid)


def check_same_field(directory):
    # The 24 × 24 temperature field is encoded from the same source array
    # each time, including the same missing positions and exactly representable values.
    results = []
    baseline = None
    for packing in PACKING_TEMPLATES:
        path = directory / f"{packing}.grib2"
        report, output = check_case(path, 24, True, packing, bounds=(100, 37.7, 102.3, 40))
        assert report["verified_points"] == 576
        assert report["missing_points"] == 83
        if baseline is None:
            baseline = output
        assert output == baseline, f"{packing} changed the decoded temperature field"
        results.append(report)
    return results


if __name__ == "__main__":
    with tempfile.TemporaryDirectory() as directory:
        path = Path(directory) / "sample.grib2"
        if sys.argv[1:] == ["--same-field"]:
            print(json.dumps(check_same_field(path.parent), indent=2))
        elif not sys.argv[1:]:
            cases = [check_case(path, 24, False, "grid_simple"),
                          check_case(path, 200, True, "grid_simple"),
                          check_case(path, 200, False, "grid_complex"),
                          check_case(path, 200, False, "grid_complex_spatial_differencing"),
                          check_case(path, 24, True, "grid_ieee"),
                          check_case(path, None, False, "grid_simple", gaussian=True)]
            print(json.dumps([report for report, _ in cases], indent=2))
        else:
            raise SystemExit("usage: verify_eccodes.py [--same-field]")
