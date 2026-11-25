"""Compare full decoding, in-memory window decoding, and positioned reads."""
import csv
import io
import json
import statistics
import subprocess
import tempfile
from pathlib import Path
from time import perf_counter

from verify_eccodes import CLI, source


def run(command, path, bounds):
    start = perf_counter()
    result = subprocess.run(
        ["node", str(CLI), command, str(path), "7", *map(str, bounds)],
        check=True, capture_output=True, text=True,
    )
    return result.stdout, result.stderr, (perf_counter() - start) * 1000


def compare(path, bounds, runs=5):
    times = {method: [] for method in ("scan-window", "window", "range-window")}
    first = None
    metrics = None
    for _ in range(runs):
        for method in times:
            output, diagnostic, elapsed = run(method, path, bounds)
            if first is None:
                first = output
            else:
                assert output == first, method
            times[method].append(elapsed)
            if method == "range-window":
                metrics = json.loads(diagnostic)
    count = len(list(csv.DictReader(io.StringIO(first))))
    assert count == metrics["window"]["samples"]
    return {
        "bounds": bounds,
        "selected_points": count,
        "file_bytes": path.stat().st_size,
        "full_scan_points": 600 * 600,
        "range_window": metrics,
        "median_cli_wall_ms": {name: round(statistics.median(values), 2)
                               for name, values in times.items()},
    }


if __name__ == "__main__":
    with tempfile.TemporaryDirectory() as directory:
        sample = Path(directory) / "one.grib2"
        archive = Path(directory) / "run.grib2"
        source(sample, 600, False, "grid_simple")
        archive.write_bytes(sample.read_bytes() * 16)
        print(json.dumps([
            compare(archive, [101, 38, 102, 39]),
            compare(archive, [103, 16, 123, 36]),
        ], indent=2))
