# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.
"""Compare two PPM frames, as run.sh check does for the GPU and the CPU.

    compare_ppm.py A.ppm B.ppm MEAN OUTLIER FRACTION

The frames pass if their mean difference is at most MEAN (of 255), and at most
FRACTION of the values differ by more than OUTLIER. Exit status 0 is a pass.
"""

import sys


def read_ppm(path):
    """Return (width, height, bytes) of a binary PPM with 255 as its maximum."""
    with open(path, "rb") as file:
        data = file.read()
    magic, size, maximum, pixels = data.split(b"\n", 3)
    if magic != b"P6" or maximum != b"255":
        raise SystemExit(f"{path} is not a P6 PPM with 255 levels")
    width, height = (int(side) for side in size.split())
    if len(pixels) != width * height * 3:
        raise SystemExit(f"{path} has {len(pixels)} bytes, not {width * height * 3}")
    return width, height, pixels


def main(arguments):
    if len(arguments) != 5:
        raise SystemExit(__doc__)
    first, second = arguments[0], arguments[1]
    mean_limit, outlier, fraction = float(arguments[2]), int(arguments[3]), float(arguments[4])
    width, height, a = read_ppm(first)
    other_width, other_height, b = read_ppm(second)
    if (width, height) != (other_width, other_height):
        raise SystemExit(f"sizes differ: {width}x{height} and {other_width}x{other_height}")
    gaps = [abs(x - y) for x, y in zip(a, b)]
    mean = sum(gaps) / len(gaps)
    worst = max(gaps)
    outliers = sum(1 for gap in gaps if gap > outlier) / len(gaps)
    print(f"{width}x{height}: mean {mean:.4f}, worst {worst}, {outliers * 100:.3f}% over {outlier}")
    return 0 if mean <= mean_limit and outliers <= fraction else 1


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
