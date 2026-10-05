# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Independent 100-digit SVD controls for the shared Float32 footprint axes.

Expected values use exact Float32 input components and decimal arithmetic.
The existing rotated-footprint regression keeps its original tolerance.
"""

from math.vector2 import Vector2
from render.texture import _principal_axes, anisotropic_footprint
from std.testing import TestSuite, assert_almost_equal, assert_equal


def check_axes(u: Vector2, v: Vector2, major: Float32, minor: Float32) raises:
    var axes = _principal_axes(u, v)
    assert_almost_equal(axes.x, major, atol=0, rtol=0.000003)
    assert_almost_equal(axes.y, minor, atol=0, rtol=0.000003)


def test_principal_axes_match_independent_singular_values() raises:
    # zero
    check_axes(Vector2(0.0, 0.0), Vector2(0.0, 0.0), 0.0, 0.0)
    # axis16_1
    check_axes(Vector2(16.0, 0.0), Vector2(0.0, 1.0), 16.0, 1.0)
    # rotated_0_scale1
    check_axes(Vector2(16.0, 0.0), Vector2(-0.0, 1.0), 16.0, 1.0)
    # axis_swap_0_scale1
    check_axes(Vector2(0.0, 16.0), Vector2(1.0, -0.0), 16.0, 1.0)
    # rotated_0_scale1e-30
    check_axes(
        Vector2(1.600000005073723e-29, 0.0),
        Vector2(-0.0, 1.0000000031710769e-30),
        1.600000005073723e-29,
        1.0000000031710769e-30,
    )
    # axis_swap_0_scale1e-30
    check_axes(
        Vector2(0.0, 1.600000005073723e-29),
        Vector2(1.0000000031710769e-30, -0.0),
        1.600000005073723e-29,
        1.0000000031710769e-30,
    )
    # rotated_0_scale1e+30
    check_axes(
        Vector2(1.600000024075946e31, 0.0),
        Vector2(-0.0, 1.0000000150474662e30),
        1.600000024075946e31,
        1.0000000150474662e30,
    )
    # axis_swap_0_scale1e+30
    check_axes(
        Vector2(0.0, 1.600000024075946e31),
        Vector2(1.0000000150474662e30, -0.0),
        1.600000024075946e31,
        1.0000000150474662e30,
    )
    # rotated_15_scale1
    check_axes(
        Vector2(15.454813003540039, 0.258819043636322),
        Vector2(-4.141104698181152, 0.9659258127212524),
        16.0,
        1.0,
    )
    # axis_swap_15_scale1
    check_axes(
        Vector2(0.258819043636322, 15.454813003540039),
        Vector2(0.9659258127212524, -4.141104698181152),
        16.0,
        1.0,
    )
    # rotated_15_scale1e-30
    check_axes(
        Vector2(1.5454812917831506e-29, 2.5881905312026536e-31),
        Vector2(-4.141104849924246e-30, 9.659258073644691e-31),
        1.600000005073723e-29,
        1.0000000031710769e-30,
    )
    # axis_swap_15_scale1e-30
    check_axes(
        Vector2(2.5881905312026536e-31, 1.5454812917831506e-29),
        Vector2(9.659258073644691e-31, -4.141104849924246e-30),
        1.600000005073723e-29,
        1.0000000031710769e-30,
    )
    # rotated_15_scale1e+30
    check_axes(
        Vector2(1.545481338173949e31, 2.5881904205809155e29),
        Vector2(-4.141104672929465e30, 9.659258363587181e29),
        1.600000024075946e31,
        1.0000000150474662e30,
    )
    # axis_swap_15_scale1e+30
    check_axes(
        Vector2(2.5881904205809155e29, 1.545481338173949e31),
        Vector2(9.659258363587181e29, -4.141104672929465e30),
        1.600000024075946e31,
        1.0000000150474662e30,
    )
    # rotated_30_scale1
    check_axes(
        Vector2(13.856406211853027, 0.5),
        Vector2(-8.0, 0.8660253882408142),
        16.0,
        1.0,
    )
    # axis_swap_30_scale1
    check_axes(
        Vector2(0.5, 13.856406211853027),
        Vector2(0.8660253882408142, -8.0),
        16.0,
        1.0,
    )
    # rotated_30_scale1e-30
    check_axes(
        Vector2(1.3856406920713317e-29, 5.000000015855384e-31),
        Vector2(-8.000000025368615e-30, 8.660254325445823e-31),
        1.600000005073723e-29,
        1.0000000031710769e-30,
    )
    # axis_swap_30_scale1e-30
    check_axes(
        Vector2(5.000000015855384e-31, 1.3856406920713317e-29),
        Vector2(8.660254325445823e-31, -8.000000025368615e-30),
        1.600000005073723e-29,
        1.0000000031710769e-30,
    )
    # rotated_30_scale1e+30
    check_axes(
        Vector2(1.3856406721893796e31, 5.000000075237331e29),
        Vector2(-8.00000012037973e30, 8.660254201183622e29),
        1.600000024075946e31,
        1.0000000150474662e30,
    )
    # axis_swap_30_scale1e+30
    check_axes(
        Vector2(5.000000075237331e29, 1.3856406721893796e31),
        Vector2(8.660254201183622e29, -8.00000012037973e30),
        1.600000024075946e31,
        1.0000000150474662e30,
    )
    # rotated_45_scale1
    check_axes(
        Vector2(11.313708305358887, 0.7071067690849304),
        Vector2(-11.313708305358887, 0.7071067690849304),
        16.0,
        1.0,
    )
    # axis_swap_45_scale1
    check_axes(
        Vector2(0.7071067690849304, 11.313708305358887),
        Vector2(0.7071067690849304, -11.313708305358887),
        16.0,
        1.0,
    )
    # rotated_45_scale1e-30
    check_axes(
        Vector2(1.1313708444065452e-29, 7.071067777540908e-31),
        Vector2(-1.1313708444065452e-29, 7.071067777540908e-31),
        1.600000005073723e-29,
        1.0000000031710769e-30,
    )
    # axis_swap_45_scale1e-30
    check_axes(
        Vector2(7.071067777540908e-31, 1.1313708444065452e-29),
        Vector2(7.071067777540908e-31, -1.1313708444065452e-29),
        1.600000005073723e-29,
        1.0000000031710769e-30,
    )
    # rotated_45_scale1e+30
    check_axes(
        Vector2(1.1313708104347115e31, 7.071067565216947e29),
        Vector2(-1.1313708104347115e31, 7.071067565216947e29),
        1.599999903183364e31,
        9.999999394896025e29,
    )
    # axis_swap_45_scale1e+30
    check_axes(
        Vector2(7.071067565216947e29, 1.1313708104347115e31),
        Vector2(7.071067565216947e29, -1.1313708104347115e31),
        1.599999903183364e31,
        9.999999394896025e29,
    )
    # rotated_65_scale1
    check_axes(
        Vector2(6.761892318725586, 0.9063078165054321),
        Vector2(-14.500925064086914, 0.4226182699203491),
        16.0,
        1.0,
    )
    # axis_swap_65_scale1
    check_axes(
        Vector2(0.9063078165054321, 6.761892318725586),
        Vector2(0.4226182699203491, -14.500925064086914),
        16.0,
        1.0,
    )
    # rotated_65_scale1e-30
    check_axes(
        Vector2(6.761891886494975e-30, 9.063077431563008e-31),
        Vector2(-1.4500923890500813e-29, 4.22618242905936e-31),
        1.599999854610446e-29,
        9.999999091315288e-31,
    )
    # axis_swap_65_scale1e-30
    check_axes(
        Vector2(9.063077431563008e-31, 6.761891886494975e-30),
        Vector2(4.22618242905936e-31, -1.4500923890500813e-29),
        1.599999854610446e-29,
        9.999999091315288e-31,
    )
    # rotated_65_scale1e+30
    check_axes(
        Vector2(6.761892040405423e30, 9.063078106801501e29),
        Vector2(-1.4500924970882402e31, 4.2261825252533894e29),
        1.600000024075946e31,
        1.0000000150474662e30,
    )
    # axis_swap_65_scale1e+30
    check_axes(
        Vector2(9.063078106801501e29, 6.761892040405423e30),
        Vector2(4.2261825252533894e29, -1.4500924970882402e31),
        1.600000024075946e31,
        1.0000000150474662e30,
    )
    # rotated_80_scale1
    check_axes(
        Vector2(2.7783708572387695, 0.9848077297210693),
        Vector2(-15.75692367553711, 0.1736481785774231),
        16.0,
        1.0,
    )
    # axis_swap_80_scale1
    check_axes(
        Vector2(0.9848077297210693, 2.7783708572387695),
        Vector2(0.1736481785774231, -15.75692367553711),
        16.0,
        1.0,
    )
    # rotated_80_scale1e-30
    check_axes(
        Vector2(2.7783707999764274e-30, 9.848077261019535e-31),
        Vector2(-1.5756923617631256e-29, 1.7364817499852671e-31),
        1.600000005073723e-29,
        1.0000000031710769e-30,
    )
    # axis_swap_80_scale1e-30
    check_axes(
        Vector2(9.848077261019535e-31, 2.7783707999764274e-30),
        Vector2(1.7364817499852671e-31, -1.5756923617631256e-29),
        1.600000005073723e-29,
        1.0000000031710769e-30,
    )
    # rotated_80_scale1e+30
    check_axes(
        Vector2(2.778370848062725e30, 9.848077465038241e29),
        Vector2(-1.5756923944061185e31, 1.7364817800392032e29),
        1.600000024075946e31,
        1.0000000150474662e30,
    )
    # axis_swap_80_scale1e+30
    check_axes(
        Vector2(9.848077465038241e29, 2.778370848062725e30),
        Vector2(1.7364817800392032e29, -1.5756923944061185e31),
        1.600000024075946e31,
        1.0000000150474662e30,
    )
    # rotated_90_scale1
    check_axes(
        Vector2(9.797174820681343e-16, 1.0),
        Vector2(-16.0, 6.123234262925839e-17),
        16.0,
        1.0,
    )
    # axis_swap_90_scale1
    check_axes(
        Vector2(1.0, 9.797174820681343e-16),
        Vector2(6.123234262925839e-17, -16.0),
        16.0,
        1.0,
    )
    # rotated_90_scale1e-30
    check_axes(
        Vector2(1.401298464324817e-45, 1.0000000031710769e-30),
        Vector2(-1.600000005073723e-29, 0.0),
        1.600000005073723e-29,
        1.0000000031710769e-30,
    )
    # axis_swap_90_scale1e-30
    check_axes(
        Vector2(1.0000000031710769e-30, 1.401298464324817e-45),
        Vector2(0.0, -1.600000005073723e-29),
        1.600000005073723e-29,
        1.0000000031710769e-30,
    )
    # rotated_90_scale1e+30
    check_axes(
        Vector2(979717406588928.0, 1.0000000150474662e30),
        Vector2(-1.600000024075946e31, 61232337911808.0),
        1.600000024075946e31,
        1.0000000150474662e30,
    )
    # axis_swap_90_scale1e+30
    check_axes(
        Vector2(1.0000000150474662e30, 979717406588928.0),
        Vector2(61232337911808.0, -1.600000024075946e31),
        1.600000024075946e31,
        1.0000000150474662e30,
    )
    # nearparallel_scale1
    check_axes(
        Vector2(1.0, 1.0),
        Vector2(1.0, 1.0000009536743164),
        2.000000476837158,
        4.768370445162873e-07,
    )
    # parallel_scale1
    check_axes(Vector2(1.0, 1.0), Vector2(1.0, 1.0), 2.0, 0.0)
    # general_scale1
    check_axes(
        Vector2(3.0, 4.0),
        Vector2(5.0, 6.0),
        9.271108627319336,
        0.215723916888237,
    )
    # nearparallel_scale1e-30
    check_axes(
        Vector2(1.0000000031710769e-30, 1.0000000031710769e-30),
        Vector2(1.0000000031710769e-30, 1.0000009435665575e-30),
        2.000000570579442e-30,
        4.701976506458133e-37,
    )
    # parallel_scale1e-30
    check_axes(
        Vector2(1.0000000031710769e-30, 1.0000000031710769e-30),
        Vector2(1.0000000031710769e-30, 1.0000000031710769e-30),
        2.0000000063421537e-30,
        0.0,
    )
    # general_scale1e-30
    check_axes(
        Vector2(3.0000000095132306e-30, 4.0000000126843074e-30),
        Vector2(5.000000015855384e-30, 6.000000019026461e-30),
        9.271109274765883e-30,
        2.1572392558635125e-31,
    )
    # nearparallel_scale1e+30
    check_axes(
        Vector2(1.0000000150474662e30, 1.0000000150474662e30),
        Vector2(1.0000000150474662e30, 1.000000921741831e30),
        2.0000004834421148e30,
        4.533470742690949e23,
    )
    # parallel_scale1e+30
    check_axes(
        Vector2(1.0000000150474662e30, 1.0000000150474662e30),
        Vector2(1.0000000150474662e30, 1.0000000150474662e30),
        2.0000000300949324e30,
        0.0,
    )
    # general_scale1e+30
    check_axes(
        Vector2(2.999999894026671e30, 4.000000060189865e30),
        Vector2(4.9999999241216036e30, 5.999999788053342e30),
        9.271108852914967e30,
        2.157240666875043e29,
    )
    # rank1
    check_axes(Vector2(-5.0, 2.5), Vector2(2.0, -1.0), 6.020797252655029, 0.0)
    # full_swap
    check_axes(
        Vector2(5.0, 6.0),
        Vector2(3.0, 4.0),
        9.271108627319336,
        0.215723916888237,
    )


def test_round_footprints_keep_one_tap_without_ratio_rounding() raises:
    for scale in [Float32(1), Float32(1e-30), Float32(1e30)]:
        var u = Vector2(scale, 6 * scale)
        var v = Vector2(-6 * scale, scale)
        var axes = _principal_axes(u, v)
        assert_equal(axes.x, axes.y)
        var footprint = anisotropic_footprint(u, v, 1, 1, 16)
        assert_equal(footprint.taps, 1)
        var swapped = anisotropic_footprint(v, u, 1, 1, 16)
        assert_equal(swapped.taps, 1)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
