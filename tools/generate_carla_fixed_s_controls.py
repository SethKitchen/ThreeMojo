#!/usr/bin/env python3
# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
"""Generate independent fixed-s lane answers from captured geometry seed bits.

Build and run tools/capture_carla_fixed_s_controls.mojo with the pinned compiler.
Pass its output to this script. Geometry evaluation is unchanged by issue #604.
Only the reference point and ordinary sin/cos seeds come from that capture.
Python independently performs each Float64 lane-center operation; Fraction
compares exact stored points. No nearest_lane result is read by this oracle.
"""
import argparse
from fractions import Fraction
import json
from pathlib import Path
import struct


def bits(value):
    return struct.unpack('>Q', struct.pack('>d', value))[0]


def scalar(value):
    return struct.unpack('>d', struct.pack('>Q', value))[0]


def f32(value):
    return struct.unpack('>f', struct.pack('>f', value))[0]


def square(point, query):
    return sum((Fraction.from_float(a) - Fraction.from_float(b)) ** 2
               for a, b in zip(point, query))


def upper_radius_bits(value):
    low, high = 0, 0x7FEFFFFFFFFFFFFF
    while low < high:
        middle = (low + high) // 2
        if Fraction.from_float(scalar(middle)) ** 2 >= value:
            high = middle
        else:
            low = middle + 1
    return low


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('capture', type=Path)
    parser.add_argument('--json', type=Path)
    args = parser.parse_args()
    rows = []
    for line in args.capture.read_text().splitlines():
        kind, origin_bits, heading_bits, *seeds = map(int, line.split())
        x, y, sn, cs = map(scalar, seeds)
        zero_x, zero_y = x - 0.375 * sn, y + 0.375 * cs
        centers = []
        for side in [-1, 1]:
            cx, cy = zero_x, zero_y
            widths = [2.0, 3.0] if side < 0 else [2.0, 4.0]
            for index, width in enumerate(widths):
                half = -side * width * 0.5
                cx, cy = cx + half * sn, cy - half * cs
                centers.append((side * (index + 1), (cx, cy, 1.25)))
                cx, cy = cx + half * sn, cy - half * cs
        for dx, dy, dz in [(-5.0, -1.0, 0.75), (0.0, 0.0, 0.0), (4.0, -5.0, -1.25)]:
            query = tuple(map(f32, (x + dx, y + dy, dz)))
            best, gap = None, None
            for lane, center in centers:
                candidate = square(center, query)
                if best is None or candidate <= gap:
                    best, gap = lane, candidate
            rows.append(dict(kind=kind, origin_bits=origin_bits, heading_bits=heading_bits,
                             query_bits=list(map(bits, query)), winner=best,
                             radius_bits=upper_radius_bits(gap),
                             center_bits=[(lane, list(map(bits, center))) for lane, center in centers]))
    assert len(rows) == 135
    root = Path(__file__).resolve().parents[1]
    if args.json:
        args.json.write_text(json.dumps(rows, indent=2) + '\n')
    header = (root / 'tests/carla_fixed_s_fixture.mojo').read_text().split('"""')[0]
    output = header + '''"""Generated stored-input Fraction controls for all five geometry kinds."""

from extensions.carla.polynomial import CubicPolynomial
from extensions.carla.road_info import RoadInfoGeometry, RoadInfoLaneOffset
from math.vector3 import Vector3
from std.memory import bitcast
from std.testing import TestSuite, assert_equal, assert_true
from tests.carla_fixed_s_fixture import _fixed_geometry
from tests.test_carla_road_fixed_s import _lane, _road


def test_all_geometry_kinds_against_fraction_centers() raises:
    # kind, origin/heading/query bits, expected lane, upper exact norm.
    var cases: List[Tuple[Int, Array[UInt64, 5], Int, UInt64]] = [
'''
    for row in rows:
        literals = ', '.join(f'UInt64(0x{b:016X})' for b in [row['origin_bits'], row['heading_bits']] + row['query_bits'])
        output += f'        ({row["kind"]}, [{literals}], {row["winner"]}, UInt64(0x{row["radius_bits"]:016X})),\n'
    output += '''    ]
    for i in range(len(cases)):
        ref row = cases[i]
        var origin = bitcast[DType.float64](row[1][0])
        var heading = bitcast[DType.float64](row[1][1])
        var road = _road(z=1.25)
        road.info.geometries[0] = RoadInfoGeometry(
            0.0, _fixed_geometry(row[0], origin, heading)
        )
        road.info.lane_offsets.append(
            RoadInfoLaneOffset(0.0, CubicPolynomial.constant(0.375))
        )
        _lane(road, 0, -2, 3.0)
        _lane(road, 0, 2, 4.0)
        var query = Vector3(
            Float32(bitcast[DType.float64](row[1][2])),
            Float32(bitcast[DType.float64](row[1][3])),
            Float32(bitcast[DType.float64](row[1][4])),
        )
        var result = road.nearest_lane(3.25, query)
        assert_equal(result[0].value().lane_id.value, row[2])
        assert_true(result[1] >= bitcast[DType.float64](row[3] - UInt64(5)))
        assert_true(result[1] <= bitcast[DType.float64](row[3] + UInt64(4)))


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
'''
    (root / 'tests/test_carla_fixed_s_fraction.mojo').write_text(output)
    print(f'Generated {len(rows)} independent fixed-s Fraction cases')


if __name__ == '__main__':
    main()
