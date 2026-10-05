# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Assert finite-range fallbacks and per-coordinate nonfinite boundaries."""

from cameras.perspective_camera import PerspectiveCamera
from core.scene import Scene
from lights.csm import CSM
from lights.lighting import light_vector
from lights.sun_light import fit_sun, sun_light_shadow
from math.vector2 import Vector2
from math.vector3 import Vector3
from objects.reflector_for_ssr import fresnel_coefficient
from postprocessing.shaders import _god_ray_step
from render.cube_texture import equirect_uv
from render.framebuffer import FloatColor
from render.rasterizer import mip_level, tangent_frame
from render.texture import (
    Texture,
    Footprint,
    CLAMP,
    NEAREST,
    LINEAR,
    _major_direction,
    anisotropic_footprint,
)
from renderers.projector import apply_normal, Vec
from std.math import inf, isnan, isinf, ldexp, log2, nan, sqrt
from std.memory import bitcast
from std.testing import (
    TestSuite,
    assert_equal,
    assert_true,
    assert_raises,
    assert_almost_equal,
)
from units.si import Angle, DEGREE, Length, METER


def _color(a: FloatColor, b: FloatColor) raises:
    """Compare the complete exact straight color."""
    assert_equal(a.r, b.r)
    assert_equal(a.g, b.g)
    assert_equal(a.b, b.b)
    assert_equal(a.a, b.a)


def test_light_offsets_check_each_input_component_and_overflow_axis() raises:
    var zero = Vector3(0, 0, 0)
    var coincident = light_vector(zero, zero)
    assert_true(coincident[0] == zero)
    assert_equal(coincident[1], 0)
    assert_equal(coincident[2], 1)
    for input in range(2):
        for axis in range(3):
            var bad = zero
            bad.set_component(axis, nan[DType.float32]())
            var got = light_vector(bad, zero) if input == 0 else light_vector(
                zero, bad
            )
            assert_true(isnan(got[0].get_component(axis)))
            assert_true(isnan(got[1]))
            assert_true(isnan(got[2]))
    for axis in range(3):
        var at = zero
        at.set_component(axis, Float32(3e38))
        var got = light_vector(at, -at)
        var expected = zero
        expected.set_component(axis, 1)
        assert_true(got[0] == expected)
        assert_true(isinf(got[1]))
        assert_equal(got[2], 1)


def test_nonfinite_panorama_and_fresnel_inputs_preserve_ieee_results() raises:
    assert_true(equirect_uv(Vector3(1, 0, 0)) == Vector2(0.5, 0.5))
    assert_equal(fresnel_coefficient(Vector3(1, 0, 0)), 1)
    for axis in range(3):
        var eye = Vector3(1, 1, 1)
        eye.set_component(axis, nan[DType.float32]())
        # A NaN squared magnitude makes every divided direction component
        # NaN; longitude and the Fresnel quotient must retain that result.
        assert_true(isnan(equirect_uv(eye).x))
        assert_true(isnan(fresnel_coefficient(eye)))


def test_sun_and_cascade_refusals_check_each_direction_component() raises:
    var camera = PerspectiveCamera(
        Angle(60, DEGREE), 1, Length(1, METER), Length(10, METER)
    )
    for axis in range(3):
        var bad = Vector3(0, 0, 1)
        bad.set_component(axis, nan[DType.float32]())
        var scene = Scene()
        with assert_raises(contains="no direction"):
            _ = fit_sun(scene, camera, bad, sun_light_shadow())
        with assert_raises(contains="finite and not zero"):
            _ = CSM(scene, camera, cascades=1, light_direction=bad)
        assert_equal(scene.count(), 0)
    var scene = Scene()
    var fit = fit_sun(scene, camera, Vector3(0, 0, 1), sun_light_shadow())
    assert_true(len(fit.cascades) > 0)
    var csm = CSM(scene, camera, cascades=1, light_direction=Vector3(0, 0, 1))
    assert_equal(len(csm.lights), 1)


def test_normal_matrix_cancellation_uses_the_wide_sum() raises:
    # The exact transformed direction is (8 - 7, 1, 0). Its product
    # bound is 15, larger than four times its largest resulting component.
    var got = apply_normal([8, 0, 0, -7, 1, 0, 0, 0, 0], Vec(1, 1, 0, 0))
    assert_almost_equal(got[0], Float64(1) / sqrt(Float64(2)), atol=1e-14)
    assert_almost_equal(got[1], Float64(1) / sqrt(Float64(2)), atol=1e-14)
    assert_equal(got[2], Float64(0))
    assert_equal(got[3], Float64(0))


def test_nonfinite_tangent_frame_retains_its_ieee_fallback() raises:
    var frame = tangent_frame(
        Vector3(nan[DType.float32](), 0, 1),
        Vector3(1, 0, 0),
        Vector3(0, 1, 0),
        Vector2(1, 0),
        Vector2(0, 1),
    )
    assert_true(isnan(frame.tangent.x))
    assert_true(isnan(frame.bitangent.y))


def test_each_derivative_axis_can_require_a_log_space_mip_level() raises:
    var huge = ldexp(Float32(1), 127)
    for axis in range(4):
        var dx = Vector2(0, 0)
        var dy = Vector2(0, 0)
        if axis == 0:
            dx.x = huge
        elif axis == 1:
            dx.y = huge
        elif axis == 2:
            dy.x = huge
        else:
            dy.y = huge
        assert_equal(mip_level(dx, dy, 2, 2), Float32(128))
    var level = mip_level(Vector2(0, 0), Vector2(3e38, 3e38), 1, 1)
    assert_almost_equal(level, log2(Float32(3e38)) + Float32(0.5), atol=2e-5)


def test_god_ray_step_keeps_a_subnormal_vertical_component_bounded() raises:
    var tiny = bitcast[DType.float32](UInt32(1))
    var got = _god_ray_step(0, 0, Vector3(1, tiny, 0), 0.5)
    assert_equal(got[0], 1)
    assert_equal(got[1], 0.5)
    assert_equal(got[2], 0)


def test_runtime_gradient_and_footprint_fail_closed_per_component() raises:
    var image = Texture(
        1, 1, [UInt8(255), 0, 0, 255], CLAMP, NEAREST, LINEAR, False
    )
    var zero = Vector2(0, 0)
    var black = FloatColor(0, 0, 0, 0)
    _color(image._sample_grad(0.5, 0.5, zero, zero), FloatColor(1, 0, 0, 1))
    for bad in [nan[DType.float32](), inf[DType.float32]()]:
        _color(image._sample_grad(bad, 0.5, zero, zero), black)
        _color(image._sample_grad(0.5, bad, zero, zero), black)
        for footprint in [
            Footprint(bad, 1, zero),
            Footprint(0, 1, Vector2(bad, 0)),
            Footprint(0, 1, Vector2(0, bad)),
        ]:
            _color(
                image._sample_footprint(0.5, 0.5, footprint, explicit=True),
                black,
            )
    # Finite inputs can still overflow at one end of a multiple-tap read.
    _color(
        image._sample_footprint(
            3e38, 0, Footprint(0, 3, Vector2(3e38, 0)), explicit=True
        ),
        black,
    )
    _color(
        image._sample_footprint(
            0, 3e38, Footprint(0, 3, Vector2(0, 3e38)), explicit=True
        ),
        black,
    )
    assert_true(_major_direction(zero, zero, 0) == Vector2(1, 0))
    for along_y in [zero, Vector2(0, inf[DType.float32]())]:
        var invalid = anisotropic_footprint(
            Vector2(inf[DType.float32](), 0), along_y, 1, 1, 2
        )
        assert_equal(invalid.taps, 1)
        assert_true(invalid.step == zero)
        with assert_raises(contains="finite"):
            invalid.validate()


def test_overflowed_texel_product_keeps_a_finite_anisotropic_footprint() raises:
    # The derivative is 2^127 texels per UV unit. A two-texel image has
    # an exact 2^128 major footprint, which needs log-space arithmetic.
    # Two taps give mip level 127 and 2^126 UV spacing.
    var derivative = bitcast[DType.float32](UInt32(0x7F000000))
    var spacing = bitcast[DType.float32](UInt32(0x7E800000))
    var footprint = anisotropic_footprint(
        Vector2(derivative, 0), Vector2(0, 0), 2, 2, 2
    )
    footprint.validate()
    assert_equal(footprint.level, Float32(127))
    assert_equal(footprint.taps, 2)
    assert_true(footprint.step == Vector2(spacing, 0))


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
