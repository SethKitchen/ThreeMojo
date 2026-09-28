# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Tests for three.js's `TemporalReprojectNode` and `RecurrentDenoiseNode`:
their helpers against three.js's, a still frame whose history is kept, a
history that cannot be trusted, and the loop the SSGI example runs."""

from cameras.perspective_camera import PerspectiveCamera
from math.matrix4 import Matrix4
from math.vector2 import Vector2
from math.vector3 import Vector3
from postprocessing.screen_space import DepthView
from postprocessing.temporal_denoise import (
    AO_ALPHA,
    AlphaSource,
    DenoiseInputs,
    NO_ALPHA,
    RAY_LENGTH_ALPHA,
    ReprojectCamera,
    ReprojectInputs,
    TemporalDenoiseSettings,
    analytic_noise,
    check_temporal_denoise,
    clip_to_aabb,
    from_ycocg,
    hit_dist_factor,
    inverse_view_normal,
    karis_blend,
    lobe_normal_falloff,
    recurrent_denoise_pixel,
    sample_history,
    screen_position,
    stretch_confidence,
    temporal_denoise,
    temporal_reproject_pixel,
    to_ycocg,
    view_position,
    vogel_disk,
)
from render.framebuffer import FloatColor
from std.testing import (
    TestSuite,
    assert_almost_equal,
    assert_equal,
    assert_false,
    assert_raises,
    assert_true,
)
from units.si import Angle, DEGREE, Length, METER


comptime SIDE = 4


def test_the_settings_are_checked() raises:
    check_temporal_denoise(TemporalDenoiseSettings())
    assert_false(AlphaSource(3).is_valid())
    var bad = TemporalDenoiseSettings()
    bad.alpha_source = AlphaSource(-1)
    with assert_raises(contains="alpha source"):
        check_temporal_denoise(bad)
    bad = TemporalDenoiseSettings()
    bad.luma_phi = Float32.MAX * 2
    with assert_raises(contains="finite"):
        check_temporal_denoise(bad)
    bad = TemporalDenoiseSettings()
    bad.max_velocity_length = 0
    with assert_raises(contains="frame limit"):
        check_temporal_denoise(bad)
    bad = TemporalDenoiseSettings()
    bad.max_frames = 0.5
    with assert_raises(contains="frame limit"):
        check_temporal_denoise(bad)
    bad = TemporalDenoiseSettings()
    bad.max_velocity_length = Float32.MAX * 2
    with assert_raises(contains="frame limit"):
        check_temporal_denoise(bad)
    bad = TemporalDenoiseSettings()
    bad.max_frames = Float32.MAX * 2
    with assert_raises(contains="frame limit"):
        check_temporal_denoise(bad)
    bad = TemporalDenoiseSettings()
    bad.frame_id = -1
    with assert_raises(contains="frame count"):
        check_temporal_denoise(bad)


def test_the_helpers_are_three_js_s() raises:
    var c = to_ycocg(0.2, 0.5, 0.9)
    var back = from_ycocg(c)
    assert_almost_equal(back.x, 0.2, atol=1e-6)
    assert_almost_equal(back.y, 0.5, atol=1e-6)
    assert_almost_equal(back.z, 0.9, atol=1e-6)
    # Inside the box a point is kept; outside it is pulled to the box.
    var inside = clip_to_aabb(
        Vector3(0.5, 0.5, 0.5), Vector3(0, 0, 0), Vector3(1, 1, 1)
    )
    assert_equal(inside.x, 0.5)
    var outside = clip_to_aabb(
        Vector3(3, 0.5, 0.5), Vector3(0, 0, 0), Vector3(1, 1, 1)
    )
    assert_almost_equal(outside.x, 1, atol=1e-5)
    assert_almost_equal(outside.y, 0.5, atol=1e-5)
    # The normal is turned by the view's transpose and made unit length.
    var turned = inverse_view_normal(Vector3(0, 0, 2), Matrix4())
    assert_almost_equal(turned.z, 1, atol=1e-6)
    var point = view_position(0.5, 0.5, 0.5, Matrix4())
    assert_almost_equal(point.x, 0, atol=1e-6)
    assert_almost_equal(point.z, 0, atol=1e-6)
    var screen = screen_position(Vector3(1, 1, 0), Matrix4())
    assert_almost_equal(screen.x, 1, atol=1e-6)
    assert_almost_equal(screen.y, 0, atol=1e-6)
    assert_almost_equal(analytic_noise(0, 0, 0), 0.2261276, atol=1e-4)
    assert_almost_equal(analytic_noise(5, 7, 3), 0.4986420, atol=1e-4)
    assert_almost_equal(analytic_noise(40, 3, 1), 0.9476471, atol=1e-4)
    var tap = vogel_disk(3, 1)
    assert_almost_equal(tap.x, -0.3431363, atol=1e-5)
    assert_almost_equal(tap.y, 0.5654711, atol=1e-5)
    assert_almost_equal(lobe_normal_falloff(1, 0, -4), 3.6989954, atol=1e-3)
    assert_almost_equal(lobe_normal_falloff(1, 1, -4), 77.2776, atol=1e-2)
    assert_almost_equal(hit_dist_factor(1, 2, 0.5), 0.5, atol=1e-6)
    assert_almost_equal(hit_dist_factor(9, 2, 0.5), 1, atol=1e-6)
    var blended = karis_blend(
        Vector3(0.2, 0.2, 0.2), Vector3(0.8, 0.8, 0.8), 0.25, 1, 0, 0, 0
    )
    assert_almost_equal(blended.x, 0.26, atol=1e-5)


def plane_of[T: Copyable](value: T) -> List[T]:
    """Return a 4 by 4 image of one value."""
    return List[T](length=SIDE * SIDE, fill=value)


def reproject_inputs(
    signal: FloatColor,
    history: FloatColor,
    depth: Float32 = 0.9,
    previous_normal: Vector3 = Vector3(0, 0, 1),
    velocity: Vector2 = Vector2(0, 0),
) raises -> ReprojectInputs:
    """Return a still 4 by 4 frame of one signal, one history, one depth
    and normals facing the camera."""
    return ReprojectInputs(
        SIDE,
        SIDE,
        plane_of(signal),
        plane_of(history),
        plane_of(depth),
        plane_of(Float32(0.9)),
        plane_of(Vector3(0, 0, 1)),
        plane_of(previous_normal),
        plane_of(velocity),
    )


def test_a_still_history_is_kept() raises:
    var settings = TemporalDenoiseSettings()
    var camera = ReprojectCamera(settings)
    var inputs = reproject_inputs(
        FloatColor(0.5, 0.5, 0.5, 1), FloatColor(0.5, 0.5, 0.5, 0.5)
    )
    assert_almost_equal(stretch_confidence(inputs, 1, 2), 1, atol=1e-5)
    var kept = temporal_reproject_pixel(inputs, camera, 1, 2, settings)
    assert_almost_equal(kept.r, 0.5, atol=1e-5)
    # Two frames held, one more with full confidence: one over three.
    assert_almost_equal(kept.a, 1.0 / 3.0, atol=1e-5)
    # The sky has no surface.
    var sky = reproject_inputs(
        FloatColor(0.5, 0.5, 0.5, 1), FloatColor(0.5, 0.5, 0.5, 0.5), depth=1
    )
    var cleared = temporal_reproject_pixel(sky, camera, 1, 2, settings)
    assert_equal(cleared.r, 0)
    assert_equal(cleared.a, 1)


def test_a_history_that_does_not_match_is_dropped() raises:
    var settings = TemporalDenoiseSettings()
    var camera = ReprojectCamera(settings)
    # The last frame's normals face away: no texel matches, and the raw
    # signal stands in with an alpha of one.
    var turned = reproject_inputs(
        FloatColor(0.5, 0.5, 0.5, 1),
        FloatColor(0.1, 0.1, 0.1, 0.5),
        previous_normal=Vector3(1, 0, 0),
    )
    var fallback = sample_history(
        turned,
        camera,
        0.4,
        0.4,
        Vector3(0, 0, 0),
        Vector3(0, 0, 1),
        FloatColor(0.5, 0.5, 0.5, 1),
    )
    assert_equal(fallback.a, 1)
    assert_almost_equal(fallback.r, 0.5, atol=1e-6)
    # A history far outside the neighbors' box loses all confidence, and
    # the raw signal takes its place.
    var far = reproject_inputs(
        FloatColor(0, 0, 0, 1), FloatColor(10, 10, 10, 0.5)
    )
    var fresh = temporal_reproject_pixel(far, camera, 2, 1, settings)
    assert_almost_equal(fresh.r, 0, atol=1e-5)
    # A fast velocity weighs the new frame up.
    var fast = reproject_inputs(
        FloatColor(0.5, 0.5, 0.5, 1),
        FloatColor(0.5, 0.5, 0.5, 0.5),
        velocity=Vector2(0.5, 0.5),
    )
    var moved = temporal_reproject_pixel(fast, camera, 2, 1, settings)
    assert_true(moved.a > 0 and moved.a <= 1)
    with assert_raises(contains="one of each input"):
        _ = ReprojectInputs(
            SIDE,
            SIDE,
            plane_of(FloatColor(0, 0, 0, 1)),
            List[FloatColor](),
            plane_of(Float32(0.5)),
            plane_of(Float32(0.5)),
            plane_of(Vector3(0, 0, 1)),
            plane_of(Vector3(0, 0, 1)),
            plane_of(Vector2(0, 0)),
        )


def denoise_inputs(
    history: FloatColor, raw: FloatColor, depth: Float32 = 0.25
) raises -> DenoiseInputs:
    """Return an even 4 by 4 frame facing the camera, through identity
    matrices."""
    return DenoiseInputs(
        SIDE,
        SIDE,
        plane_of(history),
        plane_of(raw),
        plane_of(depth),
        plane_of(Vector3(0, 0, 1)),
        Matrix4(),
        Matrix4(),
    )


def test_an_even_frame_denoises_to_karis_s_blend() raises:
    # Every tap is alike, so the denoise leaves the history and the raw
    # signal as they are and mixes them by Karis's weights.
    var inputs = denoise_inputs(
        FloatColor(0.2, 0.2, 0.2, 0.25), FloatColor(0.8, 0.8, 0.8, 1)
    )
    var sources = List[AlphaSource]()
    sources.append(AO_ALPHA)
    sources.append(RAY_LENGTH_ALPHA)
    sources.append(NO_ALPHA)
    for at in range(3):
        var settings = TemporalDenoiseSettings()
        settings.alpha_source = sources[at]
        var out = recurrent_denoise_pixel(inputs, 1, 1, settings)
        assert_almost_equal(out.r, 0.26, atol=1e-4)
        assert_almost_equal(out.a, 0.25, atol=1e-5)
    # With adaptive trust, the flicker suppression halves.
    var trusting = TemporalDenoiseSettings()
    trusting.adaptive_trust = 0.5
    var trusted = recurrent_denoise_pixel(inputs, 2, 2, trusting)
    assert_almost_equal(trusted.r, 0.270588, atol=1e-4)
    # A ray that reached the environment reads as a quarter meter.
    var env = denoise_inputs(
        FloatColor(0.2, 0.2, 0.2, 0.25), FloatColor(0.8, 0.8, 0.8, 2000)
    )
    var rays = TemporalDenoiseSettings()
    rays.alpha_source = RAY_LENGTH_ALPHA
    assert_almost_equal(
        recurrent_denoise_pixel(env, 1, 2, rays).r, 0.26, atol=1e-4
    )
    # A black raw signal is left out of its own mean.
    var dark = denoise_inputs(
        FloatColor(0.2, 0.2, 0.2, 0.25), FloatColor(0, 0, 0, 1)
    )
    assert_almost_equal(
        recurrent_denoise_pixel(dark, 1, 1, TemporalDenoiseSettings()).r,
        0.1,
        atol=1e-4,
    )
    # The sky has no surface.
    var sky = denoise_inputs(
        FloatColor(0.2, 0.2, 0.2, 0.25), FloatColor(0.8, 0.8, 0.8, 1), 1
    )
    assert_equal(
        recurrent_denoise_pixel(sky, 1, 1, TemporalDenoiseSettings()).a, 1
    )


def test_a_tilted_surface_and_a_far_environment_denoise() raises:
    # A normal off the view axis takes the first tangent.
    var tilted = DenoiseInputs(
        SIDE,
        SIDE,
        plane_of(FloatColor(0.2, 0.2, 0.2, 0.25)),
        plane_of(FloatColor(0.8, 0.8, 0.8, 1)),
        plane_of(Float32(0.25)),
        plane_of(Vector3(0, 0.6, 0.8)),
        Matrix4(),
        Matrix4(),
    )
    var out = recurrent_denoise_pixel(tilted, 1, 1, TemporalDenoiseSettings())
    assert_true(out.r > 0 and out.r < 1)
    # A wide disk reaches a column whose rays reached the environment,
    # though the pixel's own neighbors' did not.
    var raw = plane_of(FloatColor(0.8, 0.8, 0.8, 1))
    for y in range(SIDE):
        raw[y * SIDE + 3] = FloatColor(0.8, 0.8, 0.8, 2000)
    var wide = DenoiseInputs(
        SIDE,
        SIDE,
        plane_of(FloatColor(0.2, 0.2, 0.2, 0.25)),
        raw^,
        plane_of(Float32(0.25)),
        plane_of(Vector3(0, 0, 1)),
        Matrix4(),
        Matrix4(),
    )
    var settings = TemporalDenoiseSettings()
    settings.alpha_source = RAY_LENGTH_ALPHA
    settings.radius = 200
    var far = recurrent_denoise_pixel(wide, 0, 1, settings)
    assert_true(far.r > 0 and far.r < 1)


def test_a_newer_neighbor_smooths_the_frame_count() raises:
    var history = plane_of(FloatColor(0.2, 0.2, 0.2, 0.25))
    for slot in range(SIDE * SIDE):
        if slot % 2 == 0:
            history[slot] = FloatColor(0.2, 0.2, 0.2, 0.5)
    var inputs = DenoiseInputs(
        SIDE,
        SIDE,
        history^,
        plane_of(FloatColor(0.8, 0.8, 0.8, 1)),
        plane_of(Float32(0.25)),
        plane_of(Vector3(0, 0, 1)),
        Matrix4(),
        Matrix4(),
    )
    var settings = TemporalDenoiseSettings()
    var smoothed = recurrent_denoise_pixel(inputs, 1, 1, settings)
    settings.smooth_disocclusions = False
    var plain = recurrent_denoise_pixel(inputs, 1, 1, settings)
    assert_true(smoothed.a >= plain.a - 1e-6)
    with assert_raises(contains="one of each input"):
        _ = DenoiseInputs(
            SIDE,
            SIDE,
            List[FloatColor](),
            plane_of(FloatColor(0, 0, 0, 1)),
            plane_of(Float32(0.25)),
            plane_of(Vector3(0, 0, 1)),
            Matrix4(),
            Matrix4(),
        )
    var flat = Matrix4()
    flat.elements[0] = 0
    with assert_raises(contains="invertible"):
        _ = DenoiseInputs(
            SIDE,
            SIDE,
            plane_of(FloatColor(0, 0, 0, 1)),
            plane_of(FloatColor(0, 0, 0, 1)),
            plane_of(Float32(0.25)),
            plane_of(Vector3(0, 0, 1)),
            Matrix4(),
            flat,
        )


def test_the_loop_keeps_its_history() raises:
    var camera = PerspectiveCamera(
        Angle(50.0, DEGREE), 1, Length(0.1, METER), Length(20.0, METER)
    )
    var projection = camera.projection_matrix()
    var ndc = projection.transform_point(Vector3(0, 0, -3)).z
    var view = DepthView(
        plane_of(ndc),
        SIDE,
        SIDE,
        projection,
        Length(0.1, METER),
        Length(20.0, METER),
    )
    var raw = plane_of(FloatColor(0.4, 0.3, 0.2, 0.8))
    var normals = plane_of(Vector3(0, 0, 1))
    var still = plane_of(Vector2(0, 0))
    var settings = TemporalDenoiseSettings()
    var first = temporal_denoise(raw, view, normals, still, Matrix4(), settings)
    assert_equal(len(first), SIDE * SIDE)
    assert_equal(settings.frame_id, 1)
    assert_equal(settings.history_width, SIDE)
    var second = temporal_denoise(
        raw, view, normals, still, Matrix4(), settings
    )
    assert_equal(settings.frame_id, 2)
    # An even signal stays even and bounded.
    assert_true(second[5].r > 0.3 and second[5].r < 0.5)
    assert_true(second[5].a > 0 and second[5].a <= 1)
    settings.alpha_source = AlphaSource(9)
    with assert_raises(contains="alpha source"):
        _ = temporal_denoise(raw, view, normals, still, Matrix4(), settings)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
