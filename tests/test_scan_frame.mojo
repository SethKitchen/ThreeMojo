# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Tests for `extensions.scan.frame`: the axes, the scale sources, the map
from scan to building coordinates and the heading estimate.

The expected points are worked by hand from the module docstring's four
steps. The heading is checked on rooms from `tests/_scan_room.mojo` that
are turned by a known angle.
"""

from core.gaussian_splat_utils import (
    GaussianSplatGeometry,
    create_gaussian_splat_geometry,
)
from extensions.scan.frame import (
    SCALE_ASSUMED,
    SCALE_DECLARED,
    SCALE_MEASURED,
    SCAN_NEGATIVE_X,
    SCAN_NEGATIVE_Y,
    SCAN_NEGATIVE_Z,
    SCAN_POSITIVE_X,
    SCAN_POSITIVE_Y,
    SCAN_POSITIVE_Z,
    ScaleSource,
    ScanAxis,
    ScanFrame,
    _x_axis,
    axis_vector,
    building_covariance,
    estimate_heading,
    scale_source,
    scan_axis,
    supersplat_frame,
)
from generators.utils import Vec3d
from std.math import cos, nan, pi, sin
from std.testing import (
    TestSuite,
    assert_almost_equal,
    assert_equal,
    assert_false,
    assert_raises,
    assert_true,
)
from tests._scan_room import default_room, room_scan
from units.si import Angle64, DEGREE64, Length64, METER, RADIAN


def _frame(up: ScanAxis, north: ScanAxis) -> ScanFrame:
    """Return a frame with the given axes and nothing else."""
    return ScanFrame(
        up,
        north,
        Length64(1, METER),
        SCALE_DECLARED,
        Angle64(0, RADIAN),
        Vec3d(0, 0, 0),
    )


def _close(found: Vec3d, x: Float64, y: Float64, z: Float64) raises:
    """Assert a point is where it should be, to rounding."""
    assert_almost_equal(found.x, x, atol=1e-12)
    assert_almost_equal(found.y, y, atol=1e-12)
    assert_almost_equal(found.z, z, atol=1e-12)


def test_the_axes_have_names_coordinates_and_signs() raises:
    """Each of the six axes reads its coordinate in its direction."""
    var names: List[String] = ["+x", "-x", "+y", "-y", "+z", "-z"]
    for value in range(6):
        var axis = ScanAxis(value)
        assert_true(axis.is_valid())
        assert_equal(axis.name(), names[value])
        assert_equal(axis.index(), value // 2)
        assert_true(scan_axis(names[value]) == axis)
    assert_equal(SCAN_POSITIVE_Z.sign(), 1)
    assert_equal(SCAN_NEGATIVE_Z.sign(), -1)
    assert_false(ScanAxis(6).is_valid())
    assert_equal(ScanAxis(-1).name(), "unknown")
    with assert_raises(contains="'y' is not an axis"):
        _ = scan_axis("y")


def test_the_scale_sources_have_names() raises:
    """A scale source reads back from its name."""
    assert_equal(SCALE_DECLARED.name(), "declared")
    assert_equal(SCALE_MEASURED.name(), "measured")
    assert_equal(SCALE_ASSUMED.name(), "assumed")
    assert_equal(ScaleSource(3).name(), "unknown")
    assert_true(scale_source("measured") == SCALE_MEASURED)
    with assert_raises(contains="'guessed' is not a scale source"):
        _ = scale_source("guessed")


def test_an_axis_is_a_unit_vector() raises:
    """Each axis points along its coordinate, and no other axis exists."""
    _close(axis_vector(SCAN_NEGATIVE_X), -1, 0, 0)
    _close(axis_vector(SCAN_POSITIVE_Y), 0, 1, 0)
    _close(axis_vector(SCAN_POSITIVE_Z), 0, 0, 1)
    with assert_raises(contains="an axis is 0 to 5"):
        _ = axis_vector(ScanAxis(9))


def test_a_frame_is_refused_when_it_cannot_map_a_scan() raises:
    """Every field is checked."""
    var good = supersplat_frame()
    good.check()
    var frame = good
    frame.up = ScanAxis(7)
    with assert_raises(contains="an axis is 0 to 5"):
        frame.check()
    frame = good
    frame.north = ScanAxis(-2)
    with assert_raises(contains="an axis is 0 to 5"):
        frame.check()
    frame = good
    frame.north = SCAN_POSITIVE_Y
    with assert_raises(contains="up and north must be different axes"):
        frame.check()
    frame = good
    frame.scale = ScaleSource(5)
    with assert_raises(contains="a scale source is 0 to 2"):
        frame.check()
    frame = good
    frame.unit = Length64(0, METER)
    with assert_raises(contains="the unit must be positive"):
        frame.check()
    frame = good
    frame.heading = Angle64(nan[DType.float64](), RADIAN)
    with assert_raises(contains="the heading must be finite"):
        frame.check()
    for axis in range(3):
        frame = good
        var values: List[Float64] = [0, 0, 0]
        values[axis] = nan[DType.float64]()
        frame.origin = Vec3d(values[0], values[1], values[2])
        with assert_raises(contains="the origin must be finite"):
            frame.check()


def test_supersplat_up_is_minus_y() raises:
    """Scan (-1, -2, -3) is building (1, 3, 2): x is -X, y is -Z, z is -Y."""
    var frame = supersplat_frame()
    _close(frame.to_building(Vec3d(-1, -2, -3)), 1, 3, 2)
    assert_true(frame.scale == SCALE_DECLARED)


def test_a_frame_takes_the_origin_scales_and_turns() raises:
    """With z up, a unit of 2 m and a quarter-turn heading, scan (3, 1, 5)
    from origin (1, 1, 1) is (2, 0, 4) units: (4, 0, 8) m, turned to
    (0, 4, 8)."""
    var frame = ScanFrame(
        SCAN_POSITIVE_Z,
        SCAN_POSITIVE_Y,
        Length64(2, METER),
        SCALE_MEASURED,
        Angle64(90, DEGREE64),
        Vec3d(1, 1, 1),
    )
    _close(frame.to_building(Vec3d(3, 1, 5)), 0, 4, 8)


def test_the_x_axis_is_north_cross_up() raises:
    """The axes stay right-handed for every pair."""
    assert_true(_x_axis(supersplat_frame()) == SCAN_NEGATIVE_X)
    assert_true(
        _x_axis(_frame(SCAN_POSITIVE_Z, SCAN_POSITIVE_Y)) == SCAN_POSITIVE_X
    )
    assert_true(
        _x_axis(_frame(SCAN_POSITIVE_X, SCAN_POSITIVE_Z)) == SCAN_POSITIVE_Y
    )
    assert_true(
        _x_axis(_frame(SCAN_POSITIVE_Y, SCAN_POSITIVE_X)) == SCAN_POSITIVE_Z
    )
    assert_true(
        _x_axis(_frame(SCAN_NEGATIVE_X, SCAN_POSITIVE_Z)) == SCAN_NEGATIVE_Y
    )


def test_a_covariance_is_read_on_the_building_axes() raises:
    """A floor splat of the room is thin along building z, at any unit."""
    var room = room_scan(default_room())
    var frame = supersplat_frame()
    var c = building_covariance(room, 0, frame)
    assert_almost_equal(c[5], 0.004 * 0.004, atol=1e-9)
    assert_almost_equal(c[0], 0.12 * 0.12, atol=1e-7)
    assert_almost_equal(c[1], 0, atol=1e-12)
    frame.unit = Length64(2, METER)
    var scaled = building_covariance(room, 0, frame)
    assert_almost_equal(scaled[0], c[0] * 4, atol=1e-7)


def _heading(turn: Float64) raises -> Float64:
    """Return the estimated heading of a room turned by `turn` degrees."""
    var plan = default_room()
    plan.turn = turn
    return estimate_heading(room_scan(plan), supersplat_frame()).to(DEGREE64)


def test_the_heading_turns_the_walls_back() raises:
    """A room turned 10 degrees needs -10; one turned 80 needs +10, the
    nearer quarter turn; near 0 and 90 the bins wrap."""
    assert_almost_equal(_heading(10), -10, atol=0.05)
    assert_almost_equal(_heading(80), 10, atol=0.05)
    assert_almost_equal(_heading(0), 0, atol=0.05)
    assert_almost_equal(_heading(1), -1, atol=0.05)
    assert_almost_equal(_heading(89), 1, atol=0.05)
    assert_almost_equal(_heading(-30), 30, atol=0.05)


def _wall(angle: Float64) -> List[Float32]:
    """Return a wall splat's scan covariance: 1 m long in plan at `angle`
    degrees, 1 m tall and 1 cm thick, in SuperSplat's frame."""
    var t = angle * pi / 180
    var c = cos(t)
    var s = sin(t)
    var long = Float64(1)
    var thin = Float64(1e-4)
    var xx = c * c * long + s * s * thin
    var xy = c * s * (long - thin)
    var yy = s * s * long + c * c * thin
    # Scan X is -x, Y is -z and Z is -y.
    return [Float32(xx), 0, Float32(xy), Float32(long), 0, Float32(yy)]


def test_the_heading_window_wraps_past_a_quarter_turn() raises:
    """Heavy splats at 87.5 and 89.5 degrees and a light one at 0.5 make
    the window around 88 the heaviest; its last two bins are past 90."""
    var centers = List[Float32](length=9, fill=0)
    var covariances = _wall(87.5)
    covariances.extend(_wall(89.5))
    covariances.extend(_wall(0.5))
    var colors: List[UInt8] = [0, 0, 0, 255, 0, 0, 0, 255, 0, 0, 0, 50]
    var splats = create_gaussian_splat_geometry(centers^, covariances^, colors^)
    var heavy = Float64(1) - 1e-4
    var light = Float64(50) / 255 * heavy
    var mean = (87.5 * heavy + 89.5 * heavy + 90.5 * light) / (
        2 * heavy + light
    )
    assert_almost_equal(
        estimate_heading(splats, supersplat_frame()).to(DEGREE64),
        90 - mean,
        atol=1e-3,
    )


def test_the_heading_needs_wall_splats() raises:
    """Floor splats, round splats and empty ones say nothing of walls."""
    var centers: List[Float32] = [0, 0, 0, 1, 0, 0, 2, 0, 0, 3, 0, 0]
    # A floor splat, long in plan, thin up (scan Y); a round splat; a
    # splat with no plan extent; and one long and thin in plan only.
    var covariances: List[Float32] = [
        1,
        0,
        0,
        0.0001,
        0,
        0.5,
        1,
        0,
        0,
        1,
        0,
        1,
        0,
        0,
        0,
        1,
        0,
        0,
        1,
        0,
        0,
        0.001,
        0,
        0.01,
    ]
    var colors = List[UInt8](length=16, fill=255)
    var splats = create_gaussian_splat_geometry(centers^, covariances^, colors^)
    with assert_raises(contains="no splat is a wall splat"):
        _ = estimate_heading(splats, supersplat_frame())
    with assert_raises(contains="no splat is a wall splat"):
        _ = estimate_heading(GaussianSplatGeometry(), supersplat_frame())
    var bad = supersplat_frame()
    bad.unit = Length64(-1, METER)
    with assert_raises(contains="the unit must be positive"):
        _ = estimate_heading(splats, bad)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
