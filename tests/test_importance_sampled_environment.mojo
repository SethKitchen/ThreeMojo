# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Tests for three.js's `ImportanceSampledEnvironment` and the specular
helpers it reads: the map's half floats and distributions, the
equirectangular mapping, the three samples, and the GGX reflection sample
against `assets/ssr_denoise/reference.py`, a transcription of three.js
r186's `SpecularHelpers.js`."""

from math.matrix4 import Matrix4
from math.vector2 import Vector2
from math.vector3 import Vector3
from postprocessing.importance_sampled_environment import (
    ENV_RAY_LENGTH,
    EquirectEnvironment,
    closest_index,
    conditional_at,
    d_gtr,
    equirect_dir_pdf,
    equirect_uv,
    equirect_uv_to_dir,
    f_schlick,
    geometry_term,
    ggx_reflection_sample,
    ggx_vndf_pdf,
    half,
    mis_power_heuristic,
    sample_environment_brdf,
    sample_environment_mis,
    sample_ggx_vndf,
    sample_reflect,
    smith_g,
    specular_dominant_factor,
)
from render.framebuffer import FloatColor
from std.math import isfinite, pi
from std.testing import (
    TestSuite,
    assert_almost_equal,
    assert_equal,
    assert_raises,
    assert_true,
)


def gray(value: Float32) -> FloatColor:
    """Return an opaque gray."""
    return FloatColor(value, value, value, 1)


def test_the_numbers_are_three_js_s() raises:
    assert_equal(half(0.1), Float32(0.0999755859375))
    var values: List[Float32] = [0.1, 0.4, 0.4, 1.0]
    assert_equal(closest_index(values, 0.4, 0, 4), 1)
    assert_equal(closest_index(values, 0.05, 0, 4), 0)
    assert_equal(closest_index(values, 2, 0, 4), 3)
    assert_equal(closest_index(values, 0.5, 2, 2), 1)


def test_the_map_is_kept_in_half_floats_and_flipped() raises:
    var texels: List[FloatColor] = [gray(0.1), gray(0.2), gray(0.3), gray(0.4)]
    var env = EquirectEnvironment(2, 2, texels, flip_y=True)
    assert_equal(env.texels[0].r, half(0.3))
    assert_equal(env.texels[3].r, half(0.2))
    assert_equal(len(env.marginal), 0)
    # Across wraps: left of the first texel is the last.
    var strip: List[FloatColor] = [gray(0), gray(1)]
    var wide = EquirectEnvironment(2, 1, strip)
    assert_almost_equal(wide.sample(0, 0.5).r, 0.5, atol=1e-6)
    assert_almost_equal(wide.sample(0.25, 0.5).r, 0, atol=1e-6)
    with assert_raises(contains="positive"):
        _ = EquirectEnvironment(0, 2, texels)
    with assert_raises(contains="positive"):
        _ = EquirectEnvironment(2, 0, texels)
    with assert_raises(contains="one texel"):
        _ = EquirectEnvironment(3, 2, texels)


def test_the_distributions_are_three_js_s() raises:
    # A bright first row, a black second: every row step lands on the
    # first row, and every texel step of either row on its second texel.
    var texels: List[FloatColor] = [gray(1), gray(3), gray(0), gray(0)]
    var env = EquirectEnvironment(2, 2, texels, importance_sampling=True)
    assert_almost_equal(env.total, 4, atol=1e-5)
    assert_equal(env.marginal[0], half(0.25))
    assert_equal(env.marginal[1], half(0.25))
    assert_equal(env.conditional[0], half(0.75))
    assert_equal(env.conditional[1], half(0.75))
    assert_equal(env.conditional[2], half(0.75))
    assert_equal(env.conditional[3], half(0.75))
    assert_almost_equal(env.table(env.marginal, 2, 0.9), 0.25, atol=1e-6)
    assert_almost_equal(conditional_at(env, 0.5, 0.5), 0.75, atol=1e-6)
    # A black map has no distribution to normalize.
    var black: List[FloatColor] = [gray(0), gray(0), gray(0), gray(0)]
    var none = EquirectEnvironment(2, 2, black, importance_sampling=True)
    assert_equal(none.total, 0)


def test_the_mapping_is_three_js_s() raises:
    var uv = equirect_uv(Vector3(1, 0, 0))
    assert_almost_equal(uv.x, 0.5, atol=1e-6)
    assert_almost_equal(uv.y, 0.5, atol=1e-6)
    assert_almost_equal(equirect_uv(Vector3(0, 1, 0)).y, 1, atol=1e-6)
    var back = equirect_uv_to_dir(Vector2(0.5, 0.5))
    assert_almost_equal(back.x, 1, atol=1e-6)
    var side = equirect_uv_to_dir(Vector2(0.75, 0.5))
    assert_almost_equal(side.z, 1, atol=1e-6)
    assert_almost_equal(
        equirect_dir_pdf(Vector3(1, 0, 0)),
        Float32(1 / (2 * pi * pi)),
        atol=1e-6,
    )
    assert_equal(equirect_dir_pdf(Vector3(0, 1, 0)), 0)


def test_the_specular_helpers_are_three_js_s() raises:
    assert_almost_equal(mis_power_heuristic(1, 1), 0.5, atol=1e-6)
    assert_almost_equal(mis_power_heuristic(2, 0), 1, atol=1e-6)
    assert_almost_equal(d_gtr(1, 0.3, 2), Float32(1 / pi), atol=1e-6)
    assert_almost_equal(d_gtr(0.5, 1, 2), 1.2732395, atol=1e-5)
    assert_almost_equal(smith_g(1, 0.5), 1, atol=1e-6)
    assert_almost_equal(smith_g(0.5, 0.5), 0.8610, atol=1e-4)
    assert_almost_equal(geometry_term(1, 1, 0.3), 1, atol=1e-6)
    var f0 = Vector3(0.04, 0.04, 0.04)
    assert_almost_equal(f_schlick(f0, 1).x, 0.04, atol=1e-6)
    assert_almost_equal(f_schlick(f0, 0).y, 1, atol=1e-6)


def test_the_samples_read_the_map() raises:
    var even: List[FloatColor] = [gray(1), gray(1), gray(1), gray(1)]
    var env = EquirectEnvironment(2, 2, even, importance_sampling=True)
    env.intensity = 2
    var up = Vector3(0, 0, 1)
    var reflected = sample_reflect(env, Matrix4(), up, 0.5)
    assert_almost_equal(reflected.x, 1, atol=1e-5)
    var f0 = Vector3(0.04, 0.04, 0.04)
    var brdf = sample_environment_brdf(env, Matrix4(), up, up, up, 0.5, f0)
    assert_almost_equal(brdf.x, 0.08, atol=1e-5)
    # A mirror lobe takes the reflected ray alone, fully weighed.
    var mirror = sample_environment_mis(
        env, Matrix4(), up, up, up, 0.005, f0, 0.5, 0.5
    )
    assert_almost_equal(mirror.x, 0.08, atol=1e-4)
    # A rough lobe draws a second sample: one along the normal, and one
    # across it, which is passed over.
    var along = sample_environment_mis(
        env, Matrix4(), up, up, up, 0.5, f0, 0.5, 0.9
    )
    var across = sample_environment_mis(
        env, Matrix4(), up, up, up, 0.5, f0, 0.5, 0.5
    )
    assert_true(isfinite(along.x) and along.x > 0)
    assert_true(along.x > across.x)


def unit(x: Float32, y: Float32, z: Float32) -> Vector3:
    """Return a direction at unit length."""
    var out = Vector3(x, y, z)
    out.normalize()
    return out


def test_the_dominant_factor_is_three_js_s() raises:
    assert_equal(ENV_RAY_LENGTH, Float32(1e4))
    assert_almost_equal(
        specular_dominant_factor(0.5, 0.3), 0.9914836, atol=1e-5
    )
    # A rough surface seen straight on keeps none of the ray's length.
    assert_almost_equal(specular_dominant_factor(1, 1), 0, atol=1e-5)
    # A mirror seen edge on keeps all of it.
    assert_almost_equal(specular_dominant_factor(0, 0), 1, atol=1e-5)
    # A cosine a rounding above one reads as one.
    assert_almost_equal(
        specular_dominant_factor(1.0000001, 1),
        specular_dominant_factor(1, 1),
        atol=1e-6,
    )


def test_the_visible_normal_is_three_js_s() raises:
    var facet = sample_ggx_vndf(unit(0.3, 0.2, 0.9), 0.25, 0.25, 0.3, 0.6)
    assert_almost_equal(facet.x, -0.0627204, atol=1e-5)
    assert_almost_equal(facet.y, 0.2804075, atol=1e-5)
    assert_almost_equal(facet.z, 0.9578297, atol=1e-5)
    assert_almost_equal(facet.length(), 1, atol=1e-5)
    assert_almost_equal(ggx_vndf_pdf(0.9, 0.7, 0.25), 0.1252274, atol=1e-5)


def test_the_reflection_sample_is_three_js_s() raises:
    var normal = unit(0.1, 0.3, 0.9)
    var view = unit(-0.2, 0.4, 0.8)
    var tilted = ggx_reflection_sample(
        normal, view, 0.5, 0.7, Vector3(0.9, 0.5, 0.2), 0.3, 0.6
    )
    assert_almost_equal(tilted.reflect_dir.x, 0.3575501, atol=1e-5)
    assert_almost_equal(tilted.reflect_dir.y, -0.3524485, atol=1e-5)
    assert_almost_equal(tilted.reflect_dir.z, 0.8648341, atol=1e-5)
    assert_almost_equal(tilted.sample_weight.x, 0.6055572, atol=1e-5)
    assert_almost_equal(tilted.sample_weight.y, 0.3414651, atol=1e-5)
    assert_almost_equal(tilted.sample_weight.z, 0.1433959, atol=1e-5)
    assert_almost_equal(tilted.pdf, 0.3235509, atol=1e-5)
    assert_almost_equal(tilted.n_dot_v, 0.9378935, atol=1e-5)
    assert_almost_equal(tilted.alpha, 0.25, atol=1e-6)
    assert_almost_equal(tilted.f0.x, 0.642, atol=1e-6)
    assert_almost_equal(tilted.f0.y, 0.362, atol=1e-6)
    assert_almost_equal(tilted.f0.z, 0.152, atol=1e-6)
    # A normal along the view's z takes the second tangent.
    var facing = ggx_reflection_sample(
        Vector3(0, 0, 1), view, 0.5, 0, Vector3(1, 1, 1), 0.3, 0.6
    )
    assert_almost_equal(facing.reflect_dir.x, 0.0157584, atol=1e-5)
    assert_almost_equal(facing.reflect_dir.y, 0.1499344, atol=1e-5)
    assert_almost_equal(facing.reflect_dir.z, 0.9885704, atol=1e-5)
    assert_almost_equal(facing.sample_weight.x, 0.0383492, atol=1e-5)
    assert_almost_equal(facing.pdf, 0.2422898, atol=1e-5)
    assert_almost_equal(facing.f0.x, 0.04, atol=1e-6)
    # A mirror's alpha is a thousandth, and its weight is its reflectance.
    var mirror = ggx_reflection_sample(
        normal, view, 0, 1, Vector3(1, 1, 1), 0.8, 0.1
    )
    assert_almost_equal(mirror.alpha, 0.001, atol=1e-7)
    assert_almost_equal(mirror.reflect_dir.x, 0.4148574, atol=1e-4)
    assert_almost_equal(mirror.reflect_dir.y, 0.1540950, atol=1e-4)
    assert_almost_equal(mirror.reflect_dir.z, 0.8967430, atol=1e-4)
    assert_almost_equal(mirror.sample_weight.x, 1, atol=1e-4)
    assert_true(mirror.pdf > 6e4 and mirror.pdf < 8e4)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
