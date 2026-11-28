"""Check GRIB2 5.200 runs and malformed payload handling against ecCodes."""
from pathlib import Path
import csv
import io
import subprocess
import tempfile

import eccodes

from verify_eccodes import CLI, invoke, source


def section(number, payload):
    return (len(payload) + 5).to_bytes(4, "big") + bytes([number]) + payload


def replace_packing(original, payload):
    prefix = original[:16]
    at = 16
    content = b""
    while at < len(original) - 4:
        size = int.from_bytes(original[at:at + 4], "big")
        kind = original[at + 4]
        if kind == 5:
            content += section(5, bytes.fromhex("0000024000c8080002000201000f0028"))
        elif kind == 7:
            content += section(7, payload)
        else:
            content += original[at:at + size]
        at += size
    return prefix[:8] + (20 + len(content)).to_bytes(8, "big") + content + b"7777"


def main():
    # MV=2, radix=253. Runs are 300 × 1.5, 2 missing, and 274 × 4.0.
    payload = bytes([1, 49, 4, 0, 4, 2, 23, 4])
    with tempfile.TemporaryDirectory() as directory:
        path = Path(directory) / "levels.grib2"
        source(path, 24, False, "grid_simple")
        base = path.read_bytes()
        path.write_bytes(replace_packing(base, payload))
        gid = eccodes.codes_new_from_message(path.read_bytes())
        try:
            assert eccodes.codes_get(gid, "dataRepresentationTemplateNumber") == 200
            reference = eccodes.codes_get_values(gid).tolist()
            missing = eccodes.codes_get(gid, "missingValue")
        finally:
            eccodes.codes_release(gid)
        expected = [1.5] * 300 + [missing] * 2 + [4.0] * 274
        assert reference == expected
        args = ("window", path, 0, 100, 37.7, 102.3, 40)
        rows = list(csv.DictReader(io.StringIO(invoke(*args))))
        assert [float(row["value"]) if row["value"] else missing for row in rows] == expected
        assert [i for i, row in enumerate(rows) if not row["value"]] == [300, 301]

        for invalid in (payload[:-1], bytes([255]) + payload[1:], payload + b"\0"):
            path.write_bytes(replace_packing(base, invalid))
            result = subprocess.run(["node", str(CLI), *map(str, args)], capture_output=True, text=True)
            assert result.returncode != 0
            assert "level" in result.stderr
    print("GRIB2 5.200: 576 points, 2 missing, 3 malformed payloads rejected")


if __name__ == "__main__":
    main()
