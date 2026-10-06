#!/usr/bin/env python3
# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
"""Generate binary-Float64 point controls with independent Fraction arithmetic.

Run from any directory. Run `mojo format` on the generated Mojo test afterward.
The optional --json path retains labels and exact input bits for review.
"""
import argparse
from fractions import Fraction
import json
from pathlib import Path
import random
import struct


def bits(value):
    return struct.unpack('>Q', struct.pack('>d', value))[0]


def exact(raw):
    value = struct.unpack('>d', struct.pack('>Q', raw))[0]
    return Fraction.from_float(value)


def sign(value):
    return int(value > 0) - int(value < 0)


def upper_radius_bits(square):
    """Find the least nonnegative Float64 upper radius by exact bisection."""
    low, high = 0, 0x7FF0000000000000
    while low < high:
        middle = (low + high) // 2
        value = exact(middle)
        if value * value >= square:
            high = middle
        else:
            low = middle + 1
    return low


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--json', type=Path)
    args = parser.parse_args()
    root = Path(__file__).resolve().parents[1]
    random_source = random.Random(594302)
    rows = []

    def add(a, b, query, width, label):
        fa, fb, fq = [list(map(exact, point)) for point in (a, b, query)]
        da = sum((a - q)**2 for a, q in zip(fa, fq))
        db = sum((b - q)**2 for b, q in zip(fb, fq))
        plan = 4 * sum((a - q)**2 for a, q in zip(fa[:2], fq[:2]))
        rows.append(dict(bits=a + b + query + [width], order=sign(da - db),
                         width_sign=sign(plan - exact(width)**2), label=label,
                         upper_radius_bits=upper_radius_bits(da)))

    exponents = [0, 1, 2, 20, 500, 970, 1022, 1023, 1024, 1074, 1500, 2000, 2045, 2046]

    def random_bits():
        exponent = random_source.choice(exponents)
        return ((random_source.getrandbits(1) << 63) | (exponent << 52)
                | random_source.getrandbits(52))

    for index in range(64):
        add([random_bits() for _ in range(3)], [random_bits() for _ in range(3)],
            [random_bits() for _ in range(3)], random_bits() & ((1 << 63) - 1),
            f'broad_{index}')
    for shift in [-1000, -700, -500, -200, 0, 200, 500, 700, 1000]:
        scale = 2.0**shift
        for perturbation in [0, 1, -1]:
            query = 0 if perturbation == 0 else (1 if perturbation > 0 else (1 << 63) | 1)
            add([bits(3 * scale), bits(4 * scale), 0], [0, bits(5 * scale), 0],
                [0, query, 0], bits(10 * scale), f'equinorm_{shift}_{perturbation}')
    for index in range(9):
        x = (random_source.choice([0, 1, 1023, 2046]) << 52) | ((1 << 52) - 1)
        add([x] * 3, [x ^ (1 << 63)] * 3, [1 << 63, 0, 0], x, f'carry_tie_{index}')
    if args.json:
        args.json.write_text(json.dumps(rows, indent=2) + '\n')
    header = (root / 'tests/test_carla_curve_distance.mojo').read_text().split('from extensions')[0]
    output = header + '''from extensions.carla.curve_distance import (
    _wide_point_order, _exact_point_order, _wide_plan_contains,
    _exact_plan_width, _wide_distance_upper,
)
from std.memory import bitcast
from std.testing import TestSuite, assert_equal, assert_true


def test_fraction_bit_corpus() raises:
    var cases: List[Tuple[Array[UInt64, 10], Int, Int, UInt64]] = [
'''
    for row in rows:
        literals = ', '.join(f'UInt64(0x{raw:016X})' for raw in row['bits'])
        output += (f'        ([{literals}], {row["order"]}, {row["width_sign"]}, '
                   f'UInt64(0x{row["upper_radius_bits"]:016X})),\n')
    output += '''    ]
    for i in range(len(cases)):
        ref row = cases[i]
        var a = Array[Float64, 3](fill=0)
        var b = Array[Float64, 3](fill=0)
        var q = Array[Float64, 3](fill=0)
        for axis in range(3):
            a[axis] = bitcast[DType.float64](row[0][axis])
            b[axis] = bitcast[DType.float64](row[0][axis + 3])
            q[axis] = bitcast[DType.float64](row[0][axis + 6])
        var width = bitcast[DType.float64](row[0][9])
        assert_equal(_wide_point_order(a, b, q), row[1])
        assert_equal(_exact_point_order(a, b, q), row[1])
        assert_equal(_wide_plan_contains(a, q, width), row[2] < 0)
        assert_equal(_exact_plan_width(a, q, width), row[2])
        assert_true(_wide_distance_upper(a, q) >= bitcast[DType.float64](row[3]))


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
'''
    (root / 'tests/test_carla_lane_distance_fraction.mojo').write_text(output)
    print(f'Generated {len(rows)} independent Fraction cases')


if __name__ == '__main__':
    main()
