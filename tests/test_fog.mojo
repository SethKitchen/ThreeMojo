# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Tests for `core.fog`.

The factors are worked out from three.js's `fog_fragment` chunk rather than
read off the implementation: a smooth step for the linear fog, and
`1 - exp(-(density * depth)^2)` for the exponential one. The mix is asked
to hold at both ends for light with no top, which is the property the
first version lost.
"""

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
    fog_factor,
    fog_mix,
    linear_fog,
    no_fog,
)
from core.scene import Scene
from render.framebuffer import Color, FloatColor
from std.math import exp, inf, nan
from std.testing import (
    TestSuite,
    assert_almost_equal,
    assert_equal,
    assert_false,
    assert_raises,
    assert_true,
)
from units.si import InverseLength, Length, METER, PER_METER

comptime TOLERANCE = Float64(1e-6)
comptime GRAY = Color(128, 128, 128)


def meters(value: Float32) -> Length:
    """Return a length in meters."""
    return Length(value, METER)


def per_meter(value: Float32) -> InverseLength:
    """Return a density per meter."""
    return InverseLength(value, PER_METER)


def not_a_number() -> Float32:
    """Return a NaN, the value no check by comparison alone catches."""
    return nan[DType.float32]()


def infinite() -> Float32:
    """Return positive infinity."""
    return inf[DType.float32]()


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
    no_fog().validate()


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


def test_a_linear_fog_refuses_an_inside_out_or_infinite_range() raises:
    # Behind the camera, nowhere, ending where it starts, ending before it
    # starts, and ending nowhere.
    with assert_raises():
        _ = linear_fog(GRAY, meters(-1), meters(5))
    with assert_raises():
        _ = linear_fog(GRAY, meters(infinite()), meters(5))
    with assert_raises():
        _ = linear_fog(GRAY, meters(not_a_number()), meters(5))
    with assert_raises():
        _ = linear_fog(GRAY, meters(5), meters(5))
    with assert_raises():
        _ = linear_fog(GRAY, meters(5), meters(2))
    with assert_raises():
        _ = linear_fog(GRAY, meters(5), meters(infinite()))
    with assert_raises():
        _ = linear_fog(GRAY, meters(5), meters(not_a_number()))
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
    # No fog at all is a legitimate density; a negative or an infinite one
    # is not, nor one that is not a number.
    _ = exp2_fog(GRAY, per_meter(0))
    with assert_raises():
        _ = exp2_fog(GRAY, per_meter(-0.1))
    with assert_raises():
        _ = exp2_fog(GRAY, per_meter(infinite()))
    with assert_raises():
        _ = exp2_fog(GRAY, per_meter(not_a_number()))


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


def test_the_mix_holds_at_both_ends_for_light_with_no_top() raises:
    # A surface a million times brighter than the fog color, fully fogged,
    # is exactly the fog color: the lerp subtracted the surface from the fog
    # and came out black. And unfogged it is exactly the surface.
    var blinding = FloatColor(1.0e6, 1.0e6, 1.0e6, 1.0)
    var fog = FloatColor(0.0144, 0.0144, 0.0144, 1.0)
    var swallowed = fog_mix(blinding, fog, 1.0)
    assert_equal(swallowed.r, fog.r)
    assert_equal(swallowed.g, fog.g)
    assert_equal(swallowed.b, fog.b)
    var clear = fog_mix(blinding, fog, 0.0)
    assert_equal(clear.r, blinding.r)
    # Half way is half the light of each, and alpha is the surface's.
    var halfway = fog_mix(FloatColor(1.0, 0.0, 0.5, 0.25), fog, 0.5)
    assert_almost_equal(halfway.r, Float32(0.5 + 0.0072), atol=TOLERANCE)
    assert_almost_equal(halfway.g, Float32(0.0072), atol=TOLERANCE)
    assert_almost_equal(halfway.b, Float32(0.25 + 0.0072), atol=TOLERANCE)
    assert_equal(halfway.a, Float32(0.25))


# --- the view -------------------------------------------------------------------


def test_a_view_of_no_fog_leaves_every_fragment_alone() raises:
    var none = FogView.none()
    assert_false(none.is_on())
    assert_equal(none.kind, NO_FOG)
    assert_equal(none.factor_at(100), Float32(0))
    none.validate()
    var through = FogView(no_fog())
    assert_false(through.is_on())
    assert_equal(through.factor_at(100), Float32(0))


def test_a_view_decodes_the_color_and_carries_the_numbers() raises:
    # The fog color is decoded from sRGB, mid-gray being about a fifth of
    # the light, with alpha one; the edges and the density come through as
    # plain floats.
    var view = FogView(linear_fog(GRAY, meters(1), meters(5)))
    assert_true(view.is_on())
    assert_equal(view.kind, LINEAR_FOG)
    assert_almost_equal(view.color.r, Float32(0.215861), atol=Float64(1e-5))
    assert_equal(view.color.a, Float32(1))
    assert_equal(view.near, Float32(1))
    assert_equal(view.far, Float32(5))
    assert_almost_equal(view.factor_at(3), Float32(0.5), atol=TOLERANCE)
    assert_equal(view.factor_at(0.5), Float32(0))
    view.validate()
    var thick = FogView(exp2_fog(GRAY, per_meter(0.5)))
    assert_equal(thick.density, Float32(0.5))
    assert_almost_equal(
        thick.factor_at(2), Float32(1) - exp(Float32(-1)), atol=TOLERANCE
    )


def test_a_view_refuses_what_the_builders_refuse() raises:
    # The fields are open, so a fog edited into nonsense after it was built
    # is caught where it is read.
    var unknown = no_fog()
    unknown.kind = FogKind(7)
    with assert_raises():
        _ = FogView(unknown)
    var behind = linear_fog(GRAY, meters(1), meters(5))
    behind.near = meters(-1)
    with assert_raises():
        _ = FogView(behind)
    var inside_out = linear_fog(GRAY, meters(1), meters(5))
    inside_out.far = meters(1)
    with assert_raises():
        _ = FogView(inside_out)
    var negative = exp2_fog(GRAY)
    negative.density = per_meter(-1)
    with assert_raises():
        _ = FogView(negative)
    # A linear fog does not read the density, nor an exponential one the
    # edges, so nonsense there is not a refusal.
    var lenient = linear_fog(GRAY, meters(1), meters(5))
    lenient.density = per_meter(-1)
    _ = FogView(lenient)
    var loose = exp2_fog(GRAY)
    loose.far = meters(-5)
    _ = FogView(loose)


def test_a_view_built_by_hand_is_checked_where_it_is_read() raises:
    # The low-level rasterizers take a view directly, and one can hold
    # anything: an unknown kind, an inside-out range, or a color that is
    # not a number, channel by channel.
    var unknown = FogView(FogKind(9), FloatColor(0.5, 0.5, 0.5, 1.0), 1, 5, 0)
    with assert_raises():
        unknown.validate()
    var inside_out = FogView(
        LINEAR_FOG, FloatColor(0.5, 0.5, 0.5, 1.0), 5, 1, 0
    )
    with assert_raises():
        inside_out.validate()
    var endless = FogView(
        EXP2_FOG, FloatColor(0.5, 0.5, 0.5, 1.0), 0, 0, infinite()
    )
    with assert_raises():
        endless.validate()
    var red = FogView(
        LINEAR_FOG, FloatColor(not_a_number(), 0.5, 0.5, 1.0), 1, 5, 0
    )
    with assert_raises():
        red.validate()
    var green = FogView(
        LINEAR_FOG, FloatColor(0.5, infinite(), 0.5, 1.0), 1, 5, 0
    )
    with assert_raises():
        green.validate()
    var blue = FogView(
        LINEAR_FOG, FloatColor(0.5, 0.5, not_a_number(), 1.0), 1, 5, 0
    )
    with assert_raises():
        blue.validate()
    var sound = FogView(LINEAR_FOG, FloatColor(0.5, 0.5, 0.5, 1.0), 1, 5, 0)
    sound.validate()


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
