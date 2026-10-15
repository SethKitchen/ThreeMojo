# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""The float helpers of the converters give CPython 3.12's answers, and the
packing helpers give `struct`'s bytes.

Every expected value here is what CPython 3.12.14 printed for the same
expression.
"""

from std.testing import TestSuite, assert_equal, assert_raises

from tools._python_float import python_repr
from tools._python_math import (
    degrees,
    dist,
    floor_divide,
    product,
    radians,
    round_half_even,
)
from tools._struct import (
    pack_f32,
    pack_i16,
    pack_u8,
    pack_u16,
    pack_u32,
    pad4,
    unpack_f32,
    unpack_u32,
)


def test_a_product_is_never_fused_into_a_sum() raises:
    # A fused multiply-add gives -2.1102230235724448e-16 here.
    var values: List[Float64] = [1e-8, 1.0, -1.0]
    var a = values[1] + values[0]
    var b = values[1] - values[0]
    assert_equal(
        python_repr(product(a, b) + values[2]), "-2.220446049250313e-16"
    )


def test_distances_follow_math_dist() raises:
    var cases: List[List[Float64]] = [
        [
            0.4626176917049918,
            -0.6199171520953191,
            2.85753063355752,
            -2.7205039162934623,
            2.1508107542920776,
            -1.2623442820099424,
        ],
        [
            2.0398066830752484,
            2.668086570647624,
            -0.15540997548213298,
            0.9849132328480468,
            -2.6359834344166817,
            1.2089521278265432,
        ],
        [
            -0.784478562631648,
            0.3980473422383515,
            2.718587553150572,
            1.1429619428158677,
            0.09294859842467051,
            0.7055564964547658,
        ],
        [
            0.9178682570460541,
            1.7978624690979608,
            -2.491329081297719,
            0.9635139012293648,
            2.4586628253103378,
            1.6938173045885403,
        ],
    ]
    # The plain square root of the sum of squares differs from each.
    var expected = [
        "5.8976745944874365",
        "5.577404661569751",
        "2.8036415927750635",
        "4.237238594521217",
    ]
    for i in range(len(cases)):
        var c = cases[i].copy()
        assert_equal(
            python_repr(dist([c[0], c[1], c[2]], [c[3], c[4], c[5]])),
            expected[i],
        )
    # Subnormal coordinates are scaled up first.
    assert_equal(
        python_repr(dist([1e-310, 0.0, 0.0], [0.0, 3e-310, 0.0])),
        "3.1622776601684e-310",
    )
    assert_equal(python_repr(dist([0.0, 0.0, 0.0], [0.0, 0.0, 0.0])), "0.0")
    assert_equal(python_repr(dist([1.5], [0.0])), "1.5")
    assert_equal(python_repr(dist([0.0, 0.0], [3.0, 4.0])), "5.0")
    var inf = Float64.MAX_FINITE * 2
    assert_equal(python_repr(dist([inf, 0.0], [0.0, 1.0])), "inf")
    assert_equal(python_repr(dist([inf - inf, 0.0], [0.0, 1.0])), "nan")
    with assert_raises(contains="same number"):
        _ = dist([0.0], [0.0, 1.0])


def test_angles_round_their_factor_first() raises:
    assert_equal(python_repr(degrees(1.0)), "57.29577951308232")
    assert_equal(python_repr(degrees(-2.5)), "-143.2394487827058")
    assert_equal(python_repr(radians(100.0)), "1.7453292519943295")


def test_floor_division_follows_python() raises:
    var cases: List[Tuple[Float64, Float64, String]] = [
        (7.5, 2.0, "3.0"),
        (-7.5, 2.0, "-4.0"),
        (7.5, -2.0, "-4.0"),
        (-0.0, 0.015, "-0.0"),
        (0.0, -0.015, "-0.0"),
        (-1e-300, 0.015, "-1.0"),
        (0.0299999, 0.015, "1.0"),
        (-0.0151, 0.015, "-2.0"),
        (1.0, 0.1, "9.0"),
    ]
    for item in cases:
        assert_equal(python_repr(floor_divide(item[0], item[1])), item[2])
    with assert_raises(contains="division by zero"):
        _ = floor_divide(1.0, 0.0)


def test_rounding_takes_halves_to_even() raises:
    var cases: List[Tuple[Float64, String]] = [
        (0.5, "0.0"),
        (1.5, "2.0"),
        (2.5, "2.0"),
        (-0.5, "-0.0"),
        (-1.5, "-2.0"),
        (-2.5, "-2.0"),
        (2.4999999999999996, "2.0"),
        (-3.7, "-4.0"),
    ]
    for item in cases:
        assert_equal(python_repr(round_half_even(item[0])), item[1])


def test_packing_follows_struct() raises:
    var out = List[UInt8]()
    pack_u8(out, 7)
    pad4(out)
    pack_u16(out, 0xBEEF)
    pack_i16(out, -2)
    pack_u32(out, 0x01020304)
    pack_f32(out, 1.0)
    var expected: List[UInt8] = [
        7,
        0,
        0,
        0,
        0xEF,
        0xBE,
        0xFE,
        0xFF,
        4,
        3,
        2,
        1,
        0,
        0,
        0x80,
        0x3F,
    ]
    assert_equal(len(out), len(expected))
    for i in range(len(out)):
        assert_equal(out[i], expected[i])
    assert_equal(unpack_u32(Span(out), 8), 0x01020304)
    assert_equal(unpack_f32(Span(out), 12), 1.0)
    # A double rounds to the nearest float, and 0.1 is not exact.
    var tenth = List[UInt8]()
    pack_f32(tenth, 0.1)
    assert_equal(python_repr(unpack_f32(Span(tenth), 0)), "0.10000000149011612")
    with assert_raises(contains="ubyte"):
        pack_u8(out, 256)
    with assert_raises(contains="'H' format"):
        pack_u16(out, -1)
    with assert_raises(contains="'h' format"):
        pack_i16(out, 32768)
    with assert_raises(contains="'I' format"):
        pack_u32(out, 1 << 32)
    with assert_raises(contains="too large"):
        pack_f32(out, 1e39)
    with assert_raises(contains="at least 4 bytes"):
        _ = unpack_u32(Span(out), len(out) - 2)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
