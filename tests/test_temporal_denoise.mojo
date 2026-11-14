# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Tests for three.js's `TemporalReprojectNode` and `RecurrentDenoiseNode`:
their helpers against three.js's, a still frame whose history is kept, a
history that cannot be trusted, and the loop the SSGI example runs. Then
the specular mode that the SSR denoise example runs, against a reference
transcription of the two nodes."""

from cameras.perspective_camera import PerspectiveCamera
from math.matrix4 import Matrix4
from math.vector2 import Vector2
from math.vector3 import Vector3
from postprocessing.screen_space import DepthView
from postprocessing.temporal_denoise import (
    AO_ALPHA,
    _in_unit,
    AlphaSource,
    DIFFUSE_DENOISE,
    DenoiseInputs,
    DenoiseMode,
    NO_ALPHA,
    RAY_LENGTH_ALPHA,
    ReprojectCamera,
    ReprojectInputs,
    SPECULAR_DENOISE,
    TemporalDenoiseSettings,
    analytic_noise,
    check_temporal_denoise,
    clip_to_aabb,
    from_ycocg,
    hit_dist_factor,
    inverse_view_normal,
    karis_blend,
    lobe_normal_falloff,
    normal_curvature,
    project_world_to_uv,
    ray_length_stats,
    recurrent_denoise_pixel,
    reproject_hit_point,
    sample_history,
    sample_history_confidence,
    screen_position,
    specular_dominant_direction,
    specular_history,
    stretch_confidence,
    temporal_denoise,
    temporal_reproject_pixel,
    to_ycocg,
    view_position,
    vogel_disk,
)
from render.framebuffer import FloatColor
from std.math import nan, pi, sqrt, tan
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


def test_a_depth_past_an_integer_reads_the_edge() raises:
    var depth = List[Float32]()
    for index in range(SIDE * SIDE):
        depth.append(Float32(index))
    var inputs = DenoiseInputs(
        SIDE,
        SIDE,
        plane_of(FloatColor(0, 0, 0, 1)),
        plane_of(FloatColor(0, 0, 0, 1)),
        depth^,
        plane_of(Vector3(0, 0, 1)),
        Matrix4(),
        Matrix4(),
    )
    assert_equal(inputs.depth_at(0.1, 0.1), 0)
    assert_equal(inputs.depth_at(1, 0.1), 3)
    assert_equal(inputs.depth_at(Float32(1e20), 0.1), 3)
    assert_equal(inputs.depth_at(Float32(-1e20), 0.1), 0)
    assert_equal(inputs.depth_at(nan[DType.float32](), 0.1), 0)


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


def test_a_denoise_frame_must_fit() raises:
    with assert_raises(contains="at least one pixel"):
        _ = ReprojectInputs(
            0,
            1,
            List[FloatColor](),
            List[FloatColor](),
            List[Float32](),
            List[Float32](),
            List[Vector3](),
            List[Vector3](),
            List[Vector2](),
        )
    with assert_raises(contains="at least one pixel"):
        _ = DenoiseInputs(
            1,
            0,
            List[FloatColor](),
            List[FloatColor](),
            List[Float32](),
            List[Vector3](),
            Matrix4(),
            Matrix4(),
        )
    with assert_raises(contains="larger than this port"):
        _ = ReprojectInputs(
            1 << 32,
            1 << 32,
            List[FloatColor](),
            List[FloatColor](),
            List[Float32](),
            List[Float32](),
            List[Vector3](),
            List[Vector3](),
            List[Vector2](),
        )
    with assert_raises(contains="larger than this port"):
        _ = DenoiseInputs(
            1 << 32,
            1 << 32,
            List[FloatColor](),
            List[FloatColor](),
            List[Float32](),
            List[Vector3](),
            Matrix4(),
            Matrix4(),
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
    # A history of another height is seeded again, even at the same width.
    settings.history_height = SIDE + 1
    var third = temporal_denoise(raw, view, normals, still, Matrix4(), settings)
    assert_equal(settings.history_height, SIDE)
    assert_equal(len(third), SIDE * SIDE)
    settings.alpha_source = AlphaSource(9)
    with assert_raises(contains="alpha source"):
        _ = temporal_denoise(raw, view, normals, still, Matrix4(), settings)


# --- the specular mode --------------------------------------------------------
#
# The expected numbers of the grid tests come from
# `assets/ssr_denoise/reference.py`: a Python transcription of three.js
# r186's `TemporalReprojectNode.js` and `RecurrentDenoiseNode.js`, in
# doubles, on the same 6 by 6 frame. Its diffuse results agree with the
# port's diffuse mode, which the tests above pin by hand.

comptime GRID = 6


def grid_projection() raises -> Matrix4:
    """Return the grid's camera projection."""
    return PerspectiveCamera(
        Angle(50.0, DEGREE), 1, Length(0.1, METER), Length(20.0, METER)
    ).projection_matrix()


def grid_depth() raises -> List[Float32]:
    """Return the window depth of a plane that tilts about the view's y."""
    var projection = grid_projection()
    var slope = tan(Float64(25) * Float64(pi) / 180)
    var out = List[Float32]()
    for _ in range(GRID):
        for x in range(GRID):
            var u = (Float64(x) + 0.5) / Float64(GRID)
            var z = -3 / (1 + 0.2 * (2 * u - 1) * slope)
            var ndc = (
                Float64(projection.elements[10]) * z
                + Float64(projection.elements[14])
            ) / (-z)
            out.append(Float32(ndc * 0.5 + 0.5))
    return out^


def grid_normals() -> List[Vector3]:
    """Return normals that turn a little from column to column."""
    var out = List[Vector3]()
    for _ in range(GRID):
        for x in range(GRID):
            var nx = -0.2 - 0.002 * Float64(x)
            var size = sqrt(nx * nx + 1)
            out.append(Vector3(Float32(nx / size), 0, Float32(1 / size)))
    return out^


def grid_signal(env_slot: Int = 15) -> List[FloatColor]:
    """Return a raw signal whose alpha is a ray length, with one ray that
    reached the environment."""
    var out = List[FloatColor]()
    for i in range(GRID * GRID):
        var ray = Float32(0.5 + 0.25 * Float64((i * 7) % 4))
        if i == env_slot:
            ray = 1e4
        out.append(
            FloatColor(
                Float32(0.2 + 0.05 * Float64((i * 3) % 7)),
                Float32(0.1 + 0.04 * Float64((i * 5) % 6)),
                Float32(0.3 + 0.03 * Float64((i * 2) % 5)),
                ray,
            )
        )
    return out^


def grid_history() -> List[FloatColor]:
    """Return a history whose alpha is one over a frame count."""
    var out = List[FloatColor]()
    for i in range(GRID * GRID):
        out.append(
            FloatColor(
                Float32(0.25 + 0.04 * Float64((i * 5) % 7)),
                Float32(0.15 + 0.03 * Float64((i * 3) % 6)),
                Float32(0.28 + 0.02 * Float64((i * 4) % 5)),
                Float32(0.1 + 0.05 * Float64((i * 3) % 4)),
            )
        )
    return out^


def grid_velocities() -> List[Vector2]:
    """Return velocities that stretch the reprojection a little."""
    var out = List[Vector2]()
    for y in range(GRID):
        for x in range(GRID):
            out.append(
                Vector2(
                    Float32(0.01 + 0.004 * Float64(x)),
                    Float32(-0.02 + 0.003 * Float64(y)),
                )
            )
    return out^


def grid_surfaces() -> List[Vector2]:
    """Return metal whose roughness changes from column to column."""
    var out = List[Vector2]()
    for _ in range(GRID):
        for x in range(GRID):
            out.append(Vector2(1, Float32(0.3 + 0.05 * Float64(x % 3))))
    return out^


def grid_settings(mode: DenoiseMode) raises -> TemporalDenoiseSettings:
    """Return settings whose last camera stood a little to the side."""
    var settings = TemporalDenoiseSettings()
    settings.mode = mode
    settings.alpha_source = RAY_LENGTH_ALPHA
    settings.projection = grid_projection()
    settings.projection_inverse = settings.projection
    settings.projection_inverse.invert()
    settings.previous_projection = settings.projection
    settings.previous_projection_inverse = settings.projection_inverse
    settings.previous_world.elements[12] = 0.05
    settings.previous_view.elements[12] = -0.05
    return settings^


def grid_reproject(
    signal: List[FloatColor],
) raises -> ReprojectInputs:
    """Return the grid's reprojection inputs around a raw signal."""
    return ReprojectInputs(
        GRID,
        GRID,
        signal.copy(),
        grid_history(),
        grid_depth(),
        grid_depth(),
        grid_normals(),
        grid_normals(),
        grid_velocities(),
    )


def assert_color(
    seen: FloatColor, r: Float32, g: Float32, b: Float32, a: Float32
) raises:
    """Assert a color against the reference, to four places."""
    assert_almost_equal(seen.r, r, atol=1e-4)
    assert_almost_equal(seen.g, g, atol=1e-4)
    assert_almost_equal(seen.b, b, atol=1e-4)
    assert_almost_equal(seen.a, a, atol=1e-4)


def test_the_mode_is_checked() raises:
    assert_true(DIFFUSE_DENOISE.is_valid())
    assert_true(SPECULAR_DENOISE.is_valid())
    assert_false(DenoiseMode(2).is_valid())
    assert_false(DenoiseMode(-1).is_valid())
    assert_true(TemporalDenoiseSettings().mode == DIFFUSE_DENOISE)
    var bad = TemporalDenoiseSettings()
    bad.mode = DenoiseMode(2)
    with assert_raises(contains="diffuse or specular"):
        check_temporal_denoise(bad)
    bad = TemporalDenoiseSettings()
    bad.roughness_phi = Float32.MAX * 2
    with assert_raises(contains="finite"):
        check_temporal_denoise(bad)


def test_the_ray_lengths_are_gathered() raises:
    var inputs = grid_reproject(grid_signal())
    # Eight rays hit and one reached the environment.
    var mixed = ray_length_stats(inputs, 2, 3)
    assert_almost_equal(mixed[0], 0.96875, atol=1e-5)
    assert_almost_equal(mixed[1], 1.0 / 9.0, atol=1e-6)
    assert_almost_equal(mixed[2], 0.2633172, atol=1e-5)
    # A corner reads its edge texels again, and none reached the
    # environment.
    var corner = ray_length_stats(inputs, 0, 5)
    assert_almost_equal(corner[0], 0.8611111, atol=1e-5)
    assert_equal(corner[1], 0)
    assert_almost_equal(corner[2], 0.2389535, atol=1e-5)
    # Where every ray reached the environment, the length is the
    # environment's and the deviation is its floor.
    var sky = ReprojectInputs(
        SIDE,
        SIDE,
        plane_of(FloatColor(1, 1, 1, 1e4)),
        plane_of(FloatColor(1, 1, 1, 1)),
        plane_of(Float32(0.5)),
        plane_of(Float32(0.5)),
        plane_of(Vector3(0, 0, 1)),
        plane_of(Vector3(0, 0, 1)),
        plane_of(Vector2(0, 0)),
    )
    var lost = ray_length_stats(sky, 1, 1)
    assert_equal(lost[0], Float32(1e4))
    assert_equal(lost[1], 1)
    assert_almost_equal(lost[2], 1e-3, atol=1e-7)


def test_a_point_is_projected_onto_the_last_frame() raises:
    # Through identity matrices the point's x and y are its place.
    var at = project_world_to_uv(Vector3(0.5, 0.5, 0), Matrix4(), Matrix4())
    assert_almost_equal(at.x, 0.75, atol=1e-6)
    assert_almost_equal(at.y, 0.25, atol=1e-6)
    # A clip w of zero has no place.
    var flat = Matrix4()
    flat.elements[15] = 0
    var lost = project_world_to_uv(Vector3(0.5, 0.5, 0), Matrix4(), flat)
    assert_equal(lost.x, -1)
    assert_equal(lost.y, -1)
    # A place that is not finite is no place.
    var huge = Matrix4()
    huge.elements[0] = Float32.MAX
    var far = project_world_to_uv(Vector3(10, 0.5, 0), Matrix4(), huge)
    assert_equal(far.x, -1)
    assert_equal(far.y, -1)
    # The hit point lies along the camera's ray, past the surface.
    var hit = reproject_hit_point(
        Vector3(0.3, 0, -0.4), 0.5, Vector3(0, 0, 0), Matrix4(), Matrix4()
    )
    assert_almost_equal(hit.x, 0.8, atol=1e-6)
    assert_almost_equal(hit.y, 0.5, atol=1e-6)
    # The last camera stood aside, so the point was elsewhere.
    var aside = Matrix4()
    aside.elements[12] = -0.2
    var moved = reproject_hit_point(
        Vector3(0.3, 0, -0.4), 0.5, Vector3(0, 0, 0), aside, Matrix4()
    )
    assert_almost_equal(moved.x, 0.7, atol=1e-6)


def test_the_normal_s_curve_is_measured() raises:
    var inputs = grid_reproject(grid_signal())
    assert_almost_equal(
        normal_curvature(inputs, Matrix4(), 2, 3), 0.0959674, atol=1e-4
    )
    assert_almost_equal(
        normal_curvature(inputs, Matrix4(), 4, 1), 0.0958143, atol=1e-4
    )
    # A flat surface does not curve, and a crease is held at one.
    var flat = reproject_inputs(
        FloatColor(0.5, 0.5, 0.5, 1), FloatColor(0.5, 0.5, 0.5, 0.5)
    )
    assert_equal(normal_curvature(flat, Matrix4(), 1, 2), 0)
    var normals = plane_of(Vector3(0, 0, 1))
    for slot in range(SIDE * SIDE):
        if slot % 2 == 1:
            normals[slot] = Vector3(1, 0, 0)
    var creased = ReprojectInputs(
        SIDE,
        SIDE,
        plane_of(FloatColor(0.5, 0.5, 0.5, 1)),
        plane_of(FloatColor(0.5, 0.5, 0.5, 0.5)),
        plane_of(Float32(0.9)),
        plane_of(Float32(0.9)),
        normals^,
        plane_of(Vector3(0, 0, 1)),
        plane_of(Vector2(0, 0)),
    )
    assert_equal(normal_curvature(creased, Matrix4(), 1, 2), 1)


def test_the_reprojection_is_three_js_s() raises:
    var signal = grid_signal()
    var inputs = grid_reproject(signal)
    # The diffuse mode on this frame, to tie the reference to the port.
    var diffuse = grid_settings(DIFFUSE_DENOISE)
    var camera = ReprojectCamera(diffuse)
    assert_almost_equal(camera.world_position.x, 0, atol=1e-7)
    assert_color(
        temporal_reproject_pixel(inputs, camera, 2, 3, diffuse),
        0.3097275,
        0.1700345,
        0.2817334,
        0.1960328,
    )
    assert_color(
        temporal_reproject_pixel(inputs, camera, 0, 5, diffuse),
        0.3726319,
        0.1491538,
        0.2875588,
        0.2068595,
    )
    # The specular mode mixes in the history where the hit point was.
    var specular = grid_settings(SPECULAR_DENOISE)
    assert_color(
        temporal_reproject_pixel(inputs, camera, 2, 3, specular),
        0.3183373,
        0.1675138,
        0.2820567,
        0.1907335,
    )
    assert_color(
        temporal_reproject_pixel(inputs, camera, 3, 2, specular),
        0.4258844,
        0.2321361,
        0.2899344,
        0.2010348,
    )
    assert_color(
        temporal_reproject_pixel(inputs, camera, 4, 1, specular),
        0.3050828,
        0.1589892,
        0.2855891,
        0.2124656,
    )
    assert_color(
        temporal_reproject_pixel(inputs, camera, 0, 5, specular),
        0.3722587,
        0.1493885,
        0.2854826,
        0.2377670,
    )
    # Without the hit point, the color is the surface history's, and the
    # confidence is the surface tap's.
    specular.hit_point_reprojection = False
    assert_color(
        temporal_reproject_pixel(inputs, camera, 2, 3, specular),
        0.3097275,
        0.1700345,
        0.2817334,
        0.2255587,
    )
    assert_color(
        temporal_reproject_pixel(inputs, camera, 4, 1, specular),
        0.3097180,
        0.1586277,
        0.2867479,
        0.2162631,
    )


def test_a_history_off_the_image_is_not_trusted() raises:
    assert_true(_in_unit(Vector2(0, 1)))
    assert_false(_in_unit(Vector2(-0.5, 0.5)))
    assert_false(_in_unit(Vector2(0.5, 1.5)))
    var settings = TemporalDenoiseSettings()
    settings.mode = SPECULAR_DENOISE
    var camera = ReprojectCamera(settings)
    var signal = FloatColor(0.5, 0.5, 0.5, 1)
    # The surface was off the image, so only the hit point's history
    # counts, and it is trusted.
    var gone = reproject_inputs(
        signal, FloatColor(0.2, 0.2, 0.2, 0.5), velocity=Vector2(4, 0)
    )
    var world = Vector3(-0.25, -0.25, 0.8)
    var normal = Vector3(0, 0, 1)
    var surface = sample_history_confidence(
        gone, camera, -1.625, 0.625, world, normal, signal
    )
    var from_hit = specular_history(
        gone,
        camera,
        1,
        2,
        Vector2(-1.625, 0.625),
        surface,
        world,
        normal,
        signal,
        0,
        settings,
    )
    assert_almost_equal(from_hit[0].r, 0.2, atol=1e-5)
    assert_almost_equal(from_hit[1], 1, atol=1e-5)
    assert_almost_equal(from_hit[2], 1, atol=1e-5)
    # A ray that reached the environment has its hit point off the
    # image, so only the surface's history counts.
    var far = reproject_inputs(
        FloatColor(0.5, 0.5, 0.5, 1e4), FloatColor(0.2, 0.2, 0.2, 0.5)
    )
    surface = sample_history_confidence(
        far, camera, 0.375, 0.625, world, normal, signal
    )
    var from_surface = specular_history(
        far,
        camera,
        1,
        2,
        Vector2(0.375, 0.625),
        surface,
        world,
        normal,
        signal,
        0,
        settings,
    )
    assert_almost_equal(from_surface[0].r, 0.2, atol=1e-5)
    assert_almost_equal(from_surface[0].a, 0.5, atol=1e-5)
    assert_equal(from_surface[2], 0)
    # A black history is no history: the raw signal stands in, new.
    var dark = reproject_inputs(signal, FloatColor(0, 0, 0, 0.5))
    surface = sample_history_confidence(
        dark, camera, 0.375, 0.625, world, normal, signal
    )
    var fresh = specular_history(
        dark,
        camera,
        1,
        2,
        Vector2(0.375, 0.625),
        surface,
        world,
        normal,
        signal,
        0,
        settings,
    )
    assert_equal(fresh[0].r, 0.5)
    assert_equal(fresh[0].a, 1)


def test_a_pixel_with_no_reflection_holds_one_frame_less() raises:
    var diffuse = TemporalDenoiseSettings()
    var specular = TemporalDenoiseSettings()
    specular.mode = SPECULAR_DENOISE
    var camera = ReprojectCamera(diffuse)
    var inputs = reproject_inputs(
        FloatColor(0, 0, 0, 0), FloatColor(0.001, 0.001, 0.001, 0.5)
    )
    var kept = temporal_reproject_pixel(inputs, camera, 1, 2, diffuse)
    var missed = temporal_reproject_pixel(inputs, camera, 1, 2, specular)
    # Two frames held. The clip toward the black neighbors costs a little
    # confidence: less in the specular mode, which trusts its hit point.
    assert_almost_equal(1 / kept.a, 2.948713, atol=1e-3)
    assert_almost_equal(1 / missed.a, 1.974190, atol=1e-3)
    # The count does not go below one frame.
    var new_inputs = reproject_inputs(
        FloatColor(0, 0, 0, 0), FloatColor(10, 10, 10, 0.5)
    )
    var newest = temporal_reproject_pixel(new_inputs, camera, 1, 2, specular)
    assert_equal(newest.a, 1)


def test_a_smaller_raw_signal_is_read_by_texel() raises:
    var small = List[FloatColor]()
    for i in range(9):
        small.append(FloatColor(Float32(i), 0, 0, 1))
    var inputs = ReprojectInputs(
        GRID,
        GRID,
        small.copy(),
        grid_history(),
        grid_depth(),
        grid_depth(),
        grid_normals(),
        grid_normals(),
        grid_velocities(),
        3,
        3,
    )
    assert_equal(inputs.signal_width, 3)
    var first = inputs.signal_texel(0, 0)
    assert_equal(first[0], 0)
    assert_equal(first[1], 0)
    var last = inputs.signal_texel(5, 2)
    assert_equal(last[0], 2)
    assert_equal(last[1], 1)
    var same = grid_reproject(grid_signal()).signal_texel(5, 2)
    assert_equal(same[0], 5)
    assert_equal(same[1], 2)
    # A frame pixel takes the statistics of the raw texel under it.
    var stats = ray_length_stats(inputs, 5, 2)
    assert_almost_equal(stats[0], 1, atol=1e-6)
    # One side of the size alone is no size.
    with assert_raises(contains="at least one pixel"):
        _ = ReprojectInputs(
            GRID,
            GRID,
            small.copy(),
            grid_history(),
            grid_depth(),
            grid_depth(),
            grid_normals(),
            grid_normals(),
            grid_velocities(),
            3,
            0,
        )
    with assert_raises(contains="at least one pixel"):
        _ = ReprojectInputs(
            GRID,
            GRID,
            small.copy(),
            grid_history(),
            grid_depth(),
            grid_depth(),
            grid_normals(),
            grid_normals(),
            grid_velocities(),
            0,
            3,
        )
    # The raw signal must fill its own size.
    with assert_raises(contains="one of each input"):
        _ = ReprojectInputs(
            GRID,
            GRID,
            small.copy(),
            grid_history(),
            grid_depth(),
            grid_depth(),
            grid_normals(),
            grid_normals(),
            grid_velocities(),
            2,
            2,
        )


def grid_denoise(
    history: List[FloatColor],
) raises -> DenoiseInputs:
    """Return the grid's denoise inputs around a history."""
    return DenoiseInputs(
        GRID,
        GRID,
        history.copy(),
        grid_signal(),
        grid_depth(),
        grid_normals(),
        Matrix4(),
        grid_projection(),
        grid_surfaces(),
    )


def test_the_denoise_is_three_js_s() raises:
    var toward = specular_dominant_direction(
        Vector3(0.10482848, 0.31448545, 0.94345635),
        Vector3(-0.21821789, 0.43643578, 0.87287156),
        0.25,
    )
    assert_almost_equal(toward.x, 0.3413458, atol=1e-5)
    assert_almost_equal(toward.y, 0.1960214, atol=1e-5)
    assert_almost_equal(toward.z, 0.9192707, atol=1e-5)
    var inputs = grid_denoise(grid_history())
    var surface = inputs.metal_rough(0.5, 0.5)
    assert_almost_equal(surface.x, 1, atol=1e-6)
    assert_almost_equal(surface.y, 0.35, atol=1e-5)
    var diffuse = grid_settings(DIFFUSE_DENOISE)
    diffuse.radius = 12
    assert_color(
        recurrent_denoise_pixel(inputs, 2, 3, diffuse),
        0.3293408,
        0.1593540,
        0.2837939,
        0.1026310,
    )
    assert_color(
        recurrent_denoise_pixel(inputs, 3, 2, diffuse),
        0.4328491,
        0.2366405,
        0.2837906,
        0.1504276,
    )
    # The specular mode lays its disk across the reflected lobe, and
    # weighs each tap by its roughness.
    var specular = grid_settings(SPECULAR_DENOISE)
    specular.radius = 12
    assert_color(
        recurrent_denoise_pixel(inputs, 2, 3, specular),
        0.3360066,
        0.1593618,
        0.2826941,
        0.1007526,
    )
    assert_color(
        recurrent_denoise_pixel(inputs, 3, 2, specular),
        0.4307894,
        0.2365343,
        0.2845118,
        0.1508964,
    )
    assert_color(
        recurrent_denoise_pixel(inputs, 4, 1, specular),
        0.2951957,
        0.1559329,
        0.2859182,
        0.2000018,
    )
    specular.adaptive_trust = 0.5
    specular.frame_id = 3
    assert_color(
        recurrent_denoise_pixel(inputs, 2, 3, specular),
        0.3348530,
        0.1592636,
        0.2824957,
        0.1009738,
    )
    assert_color(
        recurrent_denoise_pixel(inputs, 4, 1, specular),
        0.2990578,
        0.1555688,
        0.2849869,
        0.2000000,
    )


def test_the_denoise_s_surfaces_and_raw_size_are_checked() raises:
    # Without the input, every surface is a rough non-metal.
    var plain = denoise_inputs(
        FloatColor(0.2, 0.2, 0.2, 0.25), FloatColor(0.8, 0.8, 0.8, 1)
    )
    assert_equal(plain.metal_rough(0.5, 0.5).x, 0)
    assert_equal(plain.metal_rough(0.5, 0.5).y, 1)
    assert_equal(plain.raw_width, SIDE)
    with assert_raises(contains="one of each input"):
        _ = DenoiseInputs(
            SIDE,
            SIDE,
            plane_of(FloatColor(0, 0, 0, 1)),
            plane_of(FloatColor(0, 0, 0, 1)),
            plane_of(Float32(0.25)),
            plane_of(Vector3(0, 0, 1)),
            Matrix4(),
            Matrix4(),
            List[Vector2](length=3, fill=Vector2(0, 1)),
        )
    # A raw signal of a quarter of the pixels is read bilinear.
    var raw = List[FloatColor](length=4, fill=FloatColor(0.8, 0.8, 0.8, 1))
    raw[0] = FloatColor(0.4, 0.4, 0.4, 1)
    var scaled = DenoiseInputs(
        SIDE,
        SIDE,
        plane_of(FloatColor(0.2, 0.2, 0.2, 0.25)),
        raw.copy(),
        plane_of(Float32(0.25)),
        plane_of(Vector3(0, 0, 1)),
        Matrix4(),
        Matrix4(),
        plane_of(Vector2(1, 0.5)),
        2,
        2,
    )
    assert_equal(scaled.raw_height, 2)
    assert_almost_equal(scaled.raw_at(0.25, 0.25).r, 0.4, atol=1e-6)
    assert_almost_equal(scaled.raw_at(0.5, 0.25).r, 0.6, atol=1e-6)
    assert_almost_equal(scaled.raw_at(0.75, 0.75).r, 0.8, atol=1e-6)
    with assert_raises(contains="at least one pixel"):
        _ = DenoiseInputs(
            SIDE,
            SIDE,
            plane_of(FloatColor(0, 0, 0, 1)),
            raw.copy(),
            plane_of(Float32(0.25)),
            plane_of(Vector3(0, 0, 1)),
            Matrix4(),
            Matrix4(),
            List[Vector2](),
            2,
            0,
        )
    with assert_raises(contains="at least one pixel"):
        _ = DenoiseInputs(
            SIDE,
            SIDE,
            plane_of(FloatColor(0, 0, 0, 1)),
            raw.copy(),
            plane_of(Float32(0.25)),
            plane_of(Vector3(0, 0, 1)),
            Matrix4(),
            Matrix4(),
            List[Vector2](),
            0,
            2,
        )
    with assert_raises(contains="one of each input"):
        _ = DenoiseInputs(
            SIDE,
            SIDE,
            plane_of(FloatColor(0, 0, 0, 1)),
            raw.copy(),
            plane_of(Float32(0.25)),
            plane_of(Vector3(0, 0, 1)),
            Matrix4(),
            Matrix4(),
            List[Vector2](),
            3,
            3,
        )


def test_the_specular_loop_keeps_its_history() raises:
    var projection = grid_projection()
    var ndc = List[Float32]()
    var window = grid_depth()
    for slot in range(GRID * GRID):
        ndc.append(window[slot] * 2 - 1)
    var view = DepthView(
        ndc,
        GRID,
        GRID,
        projection,
        Length(0.1, METER),
        Length(20.0, METER),
    )
    # The reflections are a quarter of the frame's pixels.
    var raw = List[FloatColor]()
    for i in range(9):
        raw.append(FloatColor(0.3 + 0.05 * Float32(i), 0.2, 0.1, 0.75))
    var settings = TemporalDenoiseSettings()
    settings.mode = SPECULAR_DENOISE
    settings.alpha_source = RAY_LENGTH_ALPHA
    var first = temporal_denoise(
        raw,
        view,
        grid_normals(),
        grid_velocities(),
        Matrix4(),
        settings,
        grid_surfaces(),
        3,
        3,
    )
    assert_equal(len(first), GRID * GRID)
    assert_equal(settings.history_width, GRID)
    assert_equal(len(settings.history), GRID * GRID)
    assert_equal(
        settings.previous_projection.elements[5], projection.elements[5]
    )
    var second = temporal_denoise(
        raw,
        view,
        grid_normals(),
        grid_velocities(),
        Matrix4(),
        settings,
        grid_surfaces(),
        3,
        3,
    )
    assert_equal(settings.frame_id, 2)
    assert_true(second[14].r > 0.25 and second[14].r < 0.75)
    assert_true(second[14].a > 0 and second[14].a <= 1)
    # A raw signal that does not fill its size is refused before the
    # history moves on.
    with assert_raises(contains="one of each input"):
        _ = temporal_denoise(
            raw,
            view,
            grid_normals(),
            grid_velocities(),
            Matrix4(),
            settings,
            grid_surfaces(),
            2,
            2,
        )
    assert_equal(settings.frame_id, 2)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
