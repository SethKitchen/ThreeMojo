#!/usr/bin/env python3
# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
"""Generate exact Fraction enclosures for the local binary-scaling helpers.

Output needs no compiler or formatter. Use --check for an exact, read-only
replay of the saved fixture. Do not combine --check and --json.
"""
import argparse
from fractions import Fraction
from pathlib import Path
import json
import math
import random
import struct


def bits(x):
    return struct.unpack('>Q', struct.pack('>d', x))[0]


def value(raw):
    return struct.unpack('>d', struct.pack('>Q', raw))[0]


def bracket(number):
    try:
        rounded = float(number)
    except OverflowError:
        rounded = math.inf if number > 0 else -math.inf
    if math.isinf(rounded):
        return (math.nextafter(rounded, 0.0), rounded) if rounded > 0 else (rounded, math.nextafter(rounded, 0.0))
    represented = Fraction.from_float(rounded)
    low = math.nextafter(rounded, -math.inf) if represented > number else rounded
    high = math.nextafter(rounded, math.inf) if represented < number else rounded
    return low, high


def exact_normal_or_zero(number):
    lo, hi = bracket(number)
    return lo == hi and (lo == 0.0 or math.isfinite(lo) and abs(lo) > 2.0**-1022)


def main():
    parser = argparse.ArgumentParser(description=__doc__, allow_abbrev=False)
    parser.add_argument('--json', type=Path)
    parser.add_argument('--check', action='store_true', help='verify without writing')
    args = parser.parse_args()
    if args.check and args.json is not None:
        parser.error('--check is read-only; do not combine it with --json')
    root = Path(__file__).resolve().parents[1]
    rng = random.Random(302594)
    cases = []
    exponents = [0, 1, 2, 100, 500, 970, 1023, 1024, 1500, 2000, 2046]
    powers = [-1074, -1022, -700, -1, 0, 1, 400, 1000, 1023]
    for index in range(128):
        values = [value((rng.getrandbits(1) << 63) | (rng.choice(exponents) << 52) | rng.getrandbits(52)) for _ in range(2)]
        if index % 13 == 0:
            values[0] = 0.0
        lo, hi = sorted(values)
        scale = (-1.0 if rng.getrandbits(1) else 1.0) * 2.0**rng.choice(powers)
        is_power = index % 7 != 0
        if not is_power:
            scale = rng.choice([-3.0, 1.1, 1.5, 3.0])
        a, b, k = map(Fraction.from_float, (lo, hi, scale))
        product = sorted((a * k, b * k))
        quotient = sorted((a / k, b / k))
        p = (bracket(product[0])[0], bracket(product[1])[1])
        q = (bracket(quotient[0])[0], bracket(quotient[1])[1])
        cases.append(dict(bits=list(map(bits, (lo, hi, scale, *p, *q))),
                          exact_product=is_power and all(map(exact_normal_or_zero, product)),
                          exact_quotient=is_power and all(map(exact_normal_or_zero, quotient))))
    out = '''# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Controls for precise ideal bounds and origin-local scalar quadrature."""

from extensions.carla.curve_interval import (
    _Interval,
    _power_product_bound,
    _power_quotient_bound,
)
from std.memory import bitcast
from std.testing import TestSuite, assert_equal, assert_true


def test_exact_fraction_power_scaling_corpus() raises:
    var cases: List[Tuple[Array[UInt64, 7], Bool, Bool]] = [
'''
    for case in cases:
        out += '        (\n            [\n'
        out += ''.join(f'                UInt64(0x{x:016X}),\n' for x in case['bits'])
        out += (f'            ],\n            {case["exact_product"]},\n'
                f'            {case["exact_quotient"]},\n        ),\n')
    out += '''    ]
    for i in range(len(cases)):
        ref row = cases[i]
        var one = _Interval(
            bitcast[DType.float64](row[0][0]), bitcast[DType.float64](row[0][1])
        )
        var two = _Interval.point(bitcast[DType.float64](row[0][2]))
        var product = _power_product_bound(one, two)
        var quotient = _power_quotient_bound(one, two)
        var pl = bitcast[DType.float64](row[0][3])
        var ph = bitcast[DType.float64](row[0][4])
        var ql = bitcast[DType.float64](row[0][5])
        var qh = bitcast[DType.float64](row[0][6])
        assert_true(product.low <= pl)
        assert_true(product.high >= ph)
        assert_true(quotient.low <= ql)
        assert_true(quotient.high >= qh)
        if row[1]:
            assert_equal(product.low, pl)
            assert_equal(product.high, ph)
        if row[2]:
            assert_equal(quotient.low, ql)
            assert_equal(quotient.high, qh)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
'''
    target = root / 'tests/test_carla_power_fraction.mojo'
    expected = out.encode('utf-8')
    if args.check:
        try:
            matches = target.read_bytes() == expected
        except OSError as error:
            raise SystemExit(f'Cannot check {target}: {error}')
        if not matches:
            raise SystemExit(f'{target} is stale; regenerate without --check')
    else:
        target.write_bytes(expected)
    if args.json:
        args.json.write_text(json.dumps(cases, indent=2) + '\n')
    print('Verified' if args.check else 'Generated', len(cases), 'independent Fraction cases')


if __name__ == '__main__':
    main()
