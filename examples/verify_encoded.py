"""Check MoonGRIB-generated messages with the independent ecCodes decoder."""

import subprocess
from pathlib import Path

import eccodes
import numpy as np


ENCODER = Path("_build/js/debug/build/examples/encode/encode.js")


def main():
    encoded = subprocess.check_output(["node", str(ENCODER)])
    start = 0
    results = []
    for template in (0, 4):
        length = int.from_bytes(encoded[start + 8:start + 16], "big")
        message = encoded[start:start + length]
        assert message.startswith(b"GRIB") and message.endswith(b"7777")
        gid = eccodes.codes_new_from_message(message)
        try:
            expected = {
                "dataRepresentationTemplateNumber": template, "Ni": 3, "Nj": 2,
                "paramId": 167, "forecastTime": 2, "validityDate": 20240229,
                "validityTime": 100,
            }
            for key, value in expected.items():
                actual = eccodes.codes_get(gid, key)
                assert actual == value, (key, actual, value)
            mask = eccodes.codes_get_array(gid, "bitmap")
            np.testing.assert_array_equal(mask, [1, 0, 1, 1, 1, 1])
            np.testing.assert_array_equal(eccodes.codes_get_values(gid)[mask != 0],
                                          [275, 276, 277, 278, 279])
            np.testing.assert_array_equal(eccodes.codes_get_array(gid, "latitudes"),
                                          [40, 40, 40, 39, 39, 39])
            np.testing.assert_array_equal(eccodes.codes_get_array(gid, "longitudes"),
                                          [100, 101, 102, 100, 101, 102])
            results.append(f"5.{template}: 6 coordinates, 5 values and 1 missing point")
        finally:
            eccodes.codes_release(gid)
        start += length
    assert start == len(encoded)
    print("\n".join(results))


if __name__ == "__main__":
    main()
