"""Run an inventory-to-raster workflow on an independently verifiable fixture."""

import argparse
import csv
import io
import json
import subprocess
from pathlib import Path

from verify_eccodes import CLI
from verify_encoded import ENCODER


def run(*args):
    result = subprocess.run(["node", str(CLI), *map(str, args)],
                            check=True, capture_output=True)
    return result.stdout


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("output", type=Path, help="new directory for the demo files")
    args = parser.parse_args()
    args.output.mkdir(parents=True, exist_ok=False)
    fixture = args.output / "forecast.grib2"
    fixture.write_bytes(subprocess.check_output(["node", str(ENCODER)]))
    inventory = run("range-inventory", fixture)
    records = [json.loads(line) for line in inventory.splitlines()]
    assert len(records) == 2 and records[0]["parameter"] == 0
    (args.output / "inventory.jsonl").write_bytes(inventory)

    bounds = (100, 39, 102, 40)
    window = run("range-window", fixture, 0, *bounds)
    points = list(csv.DictReader(io.StringIO(window.decode("utf-8"))))
    assert len(points) == 6 and sum(row["value"] == "" for row in points) == 1
    (args.output / "temperature.csv").write_bytes(window)

    preview = run("raster", fixture, 0, *bounds, "pgm")
    assert preview.splitlines()[:3] == [b"P2", b"3 2", b"255"]
    (args.output / "temperature.pgm").write_bytes(preview)
    print(f"{len(records)} fields, {len(points)} points, 1 missing point")


if __name__ == "__main__":
    main()
