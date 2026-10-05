#!/usr/bin/env python3
# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
"""Verify exact-input footprint singular values with independent Decimal math.

    python3 tools/reference_texture_axes.py docs/fixtures/glsl614/footprint_axes.json

The fixture stores Float32 inputs, not platform-dependent trigonometric calls.
No ThreeMojo or Mojo code is imported. Expectations are never rewritten.
"""

import argparse
from decimal import Decimal, localcontext
import json
from pathlib import Path
import struct


def float32(value):
    """Round a finite host value to the input/output precision."""
    return struct.unpack("<f", struct.pack("<f", value))[0]


def singular_values(inputs):
    """Solve the 2-by-2 Gram characteristic polynomial at 100 digits."""
    with localcontext() as context:
        context.prec = 100
        a, b, c, d = (Decimal.from_float(float32(x)) for x in inputs)
        trace = a * a + b * b + c * c + d * d
        determinant = a * d - b * c
        discriminant = max(Decimal(0), trace * trace - 4 * determinant * determinant)
        major = ((trace + discriminant.sqrt()) / 2).sqrt()
        minor = abs(determinant) / major if major else Decimal(0)
        return major, minor


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("fixture", type=Path)
    args = parser.parse_args()
    fixture = json.loads(args.fixture.read_text(encoding="utf-8"))
    for case in fixture["cases"]:
        major, minor = singular_values(case["inputs"])
        if major != Decimal(case["major"]) or minor != Decimal(case["minor"]):
            raise AssertionError(f"Independent expectation differs: {case['name']}")
        print(f"PASS {case['name']}: {float32(float(major))}, {float32(float(minor))}")
    print(f"Verified {len(fixture['cases'])} exact-input singular-value fixtures")


if __name__ == "__main__":
    main()
