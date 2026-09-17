# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Tests for `core.fog`.

The factors are worked out from three.js's `fog_fragment` chunk rather than
read off the implementation: a smooth step for the linear fog, and
`1 - exp(-(density * depth)^2)` for the exponential one. The depth is the
camera-space depth, so a camera that has moved or turned is tested as well
as one at the origin.
"""

from cameras.perspective_camera import PerspectiveCamera
from core.fog import (
    DEFAULT_FOG_DENSITY,
    DEFAULT_FOG_FAR,
    DEFAULT_FOG_NEAR,
    EXP2_FOG,
    LINEAR_FOG,
    NO_FOG,
    Fog,
    FogKind,
    FogView,
    exp2_fog,
    fog_depth,
    fog_factor,
    linear_fog,
    no_fog,
)
from core.scene import Scene
from math.matrix4 import Matrix4
from math.vector3 import Vector3
from render.framebuffer import Color
from std.math import exp
from std.testing import (
    TestSuite,
    assert_almost_equal,
    assert_equal,
    assert_false,
    assert_raises,
    assert_true,
)
from units.si import Angle, DEGREE, InverseLength, Length, METER, PER_METER

comptime TOLERANCE = Float64(1e-6)
comptime GRAY = Color(128, 128, 128)


def meters(value: Float32) -> Length:
    """Return a length in meters."""
    return Length(value, METER)


def per_meter(value: Float32) -> InverseLength:
    """Return a density per meter."""
    return InverseLength(value, PER_METER)


# --- kinds and builders -------------------------------------------------------


def test_the_three_kinds_are_valid_and_a_fourth_is_not() raises:
    assert_true(NO_FOG.is_valid())
    assert_true(LINEAR_FOG.is_valid())
    assert_true(EXP2_FOG.is_valid())
    assert_false(FogKind(7).is_valid())


def test_a_scene_starts_with_no_fog() raises:
    var scene = Scene()
    assert_equal(scene.fog.kind, NO_FOG)
    assert_false(scene.fog.is_on())
    assert_false(no_fog().is_on())


def test_a_linear_fog_carries_its_edges_at_three_js_defaults() raises:
    var fog = linear_fog(GRAY)
    assert_equal(fog.kind, LINEAR_FOG)
    assert_true(fog.is_on())
    assert_equal(fog.color.r, UInt8(128))
    assert_almost_equal(fog.near.to(METER), Float32(1), atol=TOLERANCE)
    assert_almost_equal(fog.far.to(METER), Float32(1000), atol=TOLERANCE)
    assert_true(fog.near == DEFAULT_FOG_NEAR)
    assert_true(fog.far == DEFAULT_FOG_FAR)
    var close = linear_fog(GRAY, meters(2), meters(5))
    assert_almost_equal(close.near.to(METER), Float32(2), atol=TOLERANCE)
    assert_almost_equal(close.far.to(METER), Float32(5), atol=TOLERANCE)


def test_a_linear_fog_refuses_an_inside_out_range() raises:
    # Behind the camera, ending where it starts, and ending before it starts.
    with assert_raises():
        _ = linear_fog(GRAY, meters(-1), meters(5))
    with assert_raises():
        _ = linear_fog(GRAY, meters(5), meters(5))
    with assert_raises():
        _ = linear_fog(GRAY, meters(5), meters(2))
    # Starting at the camera itself is allowed.
    _ = linear_fog(GRAY, meters(0), meters(2))


def test_an_exponential_fog_carries_its_density_at_three_js_default() raises:
    var fog = exp2_fog(GRAY)
    assert_equal(fog.kind, EXP2_FOG)
    assert_true(fog.is_on())
    assert_almost_equal(
        fog.density.to(PER_METER), Float32(0.00025), atol=Float64(1e-9)
    )
    assert_true(fog.density == DEFAULT_FOG_DENSITY)
    var thick = exp2_fog(GRAY, per_meter(0.5))
    assert_almost_equal(
        thick.density.to(PER_METER), Float32(0.5), atol=TOLERANCE
    )
    # No fog at all is a legitimate density; a negative one is not.
    _ = exp2_fog(GRAY, per_meter(0))
    with assert_raises():
        _ = exp2_fog(GRAY, per_meter(-0.1))


# --- the arithmetic ------------------------------------------------------------


def test_a_linear_fog_rises_smoothly_between_its_edges() raises:
    # Nothing before near, everything past far, and a smooth step between:
    # at the midpoint a half, at a quarter of the way three thirty-seconds.
    assert_equal(fog_factor(LINEAR_FOG, 0.5, 1, 5, 0), Float32(0))
    assert_equal(fog_factor(LINEAR_FOG, 1, 1, 5, 0), Float32(0))
    assert_almost_equal(
        fog_factor(LINEAR_FOG, 3, 1, 5, 0), Float32(0.5), atol=TOLERANCE
    )
    assert_almost_equal(
        fog_factor(LINEAR_FOG, 2, 1, 5, 0), Float32(0.15625), atol=TOLERANCE
    )
    assert_equal(fog_factor(LINEAR_FOG, 5, 1, 5, 0), Float32(1))
    assert_equal(fog_factor(LINEAR_FOG, 50, 1, 5, 0), Float32(1))


def test_an_exponential_fog_thickens_with_the_square_of_the_depth() raises:
    # `1 - exp(-(density * depth)^2)`: nothing at the camera, and at a
    # density of a half two meters out, one minus e to the minus one.
    assert_equal(fog_factor(EXP2_FOG, 0, 0, 0, 0.5), Float32(0))
    assert_almost_equal(
        fog_factor(EXP2_FOG, 2, 0, 0, 0.5),
        Float32(1) - exp(Float32(-1)),
        atol=TOLERANCE,
    )
    assert_almost_equal(
        fog_factor(EXP2_FOG, 4, 0, 0, 0.5),
        Float32(1) - exp(Float32(-4)),
        atol=TOLERANCE,
    )
    # Never quite everything, but as good as, far enough out.
    assert_almost_equal(
        fog_factor(EXP2_FOG, 100, 0, 0, 0.5), Float32(1), atol=TOLERANCE
    )
    # A zero density is no fog at any depth.
    assert_equal(fog_factor(EXP2_FOG, 100, 0, 0, 0), Float32(0))


def test_no_fog_and_an_unknown_kind_veil_nothing() raises:
    assert_equal(fog_factor(NO_FOG, 100, 1, 5, 0.5), Float32(0))
    assert_equal(fog_factor(FogKind(7), 100, 1, 5, 0.5), Float32(0))


def test_fog_depth_is_the_negated_depth_row() raises:
    # The identity view: depth is minus the world z, the camera looking down
    # -z from the origin. A translation in the row moves the camera.
    assert_equal(fog_depth(0, 0, 1, 0, 1, 2, -3), Float32(3))
    assert_equal(fog_depth(0, 0, 1, -5, 1, 2, -3), Float32(8))
    assert_equal(fog_depth(1, 0, 0, 0, -4, 2, -3), Float32(4))


# --- the view -------------------------------------------------------------------


def test_a_view_of_no_fog_leaves_every_fragment_alone() raises:
    var none = FogView.none()
    assert_false(none.is_on())
    assert_equal(none.kind, NO_FOG)
    assert_equal(none.factor_at(Vector3(0, 0, -100)), Float32(0))
    var through = FogView(no_fog(), Matrix4())
    assert_false(through.is_on())
    assert_equal(through.factor_at(Vector3(0, 0, -100)), Float32(0))


def test_a_view_decodes_the_color_and_takes_the_depth_row() raises:
    # Through the identity view: the depth row is (0, 0, 1, 0), and the
    # fog color is decoded from sRGB, mid-gray being about a fifth of the
    # light, with alpha one.
    var view = FogView(linear_fog(GRAY, meters(1), meters(5)), Matrix4())
    assert_true(view.is_on())
    assert_equal(view.kind, LINEAR_FOG)
    assert_almost_equal(view.color.r, Float32(0.215861), atol=Float64(1e-5))
    assert_equal(view.color.a, Float32(1))
    assert_equal(view.near, Float32(1))
    assert_equal(view.far, Float32(5))
    assert_equal(view.zx, Float32(0))
    assert_equal(view.zy, Float32(0))
    assert_equal(view.zz, Float32(1))
    assert_equal(view.zw, Float32(0))
    assert_equal(view.depth_of(Vector3(7, 7, -3)), Float32(3))
    assert_almost_equal(
        view.factor_at(Vector3(0, 0, -3)), Float32(0.5), atol=TOLERANCE
    )
    var thick = FogView(exp2_fog(GRAY, per_meter(0.5)), Matrix4())
    assert_equal(thick.density, Float32(0.5))
    assert_almost_equal(
        thick.factor_at(Vector3(0, 0, -2)),
        Float32(1) - exp(Float32(-1)),
        atol=TOLERANCE,
    )


def test_the_depth_is_measured_along_the_camera_the_view_came_from() raises:
    # A camera five meters out on +x looking at the origin: the origin is
    # five deep, a point two meters nearer on x is three deep, and a point
    # off to the side at the same x is as deep as the origin, since fog
    # measures depth and not distance.
    var camera = PerspectiveCamera(
        Angle(60.0, DEGREE), 1.0, Length(0.1, METER), Length(100.0, METER)
    )
    camera.place(Vector3(5, 0, 0), Vector3(0, 0, 0))
    var view = FogView(
        linear_fog(GRAY, meters(1), meters(5)), camera.view_matrix()
    )
    assert_almost_equal(
        view.depth_of(Vector3(0, 0, 0)), Float32(5), atol=Float64(1e-5)
    )
    assert_almost_equal(
        view.depth_of(Vector3(2, 0, 0)), Float32(3), atol=Float64(1e-5)
    )
    assert_almost_equal(
        view.depth_of(Vector3(0, 0, 4)), Float32(5), atol=Float64(1e-5)
    )
    assert_almost_equal(
        view.factor_at(Vector3(2, 0, 0)), Float32(0.5), atol=Float64(1e-5)
    )
    assert_almost_equal(
        view.factor_at(Vector3(0, 0, 0)), Float32(1), atol=Float64(1e-5)
    )


def test_a_view_refuses_what_the_builders_refuse() raises:
    # The fields are open, so a fog edited into nonsense after it was built
    # is caught where it is read.
    var unknown = no_fog()
    unknown.kind = FogKind(7)
    with assert_raises():
        _ = FogView(unknown, Matrix4())
    var behind = linear_fog(GRAY, meters(1), meters(5))
    behind.near = meters(-1)
    with assert_raises():
        _ = FogView(behind, Matrix4())
    var inside_out = linear_fog(GRAY, meters(1), meters(5))
    inside_out.far = meters(1)
    with assert_raises():
        _ = FogView(inside_out, Matrix4())
    var negative = exp2_fog(GRAY)
    negative.density = per_meter(-1)
    with assert_raises():
        _ = FogView(negative, Matrix4())
    # A linear fog does not read the density, nor an exponential one the
    # edges, so nonsense there is not a refusal.
    var lenient = linear_fog(GRAY, meters(1), meters(5))
    lenient.density = per_meter(-1)
    _ = FogView(lenient, Matrix4())
    var loose = exp2_fog(GRAY)
    loose.far = meters(-5)
    _ = FogView(loose, Matrix4())


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
