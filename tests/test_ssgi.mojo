# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Tests for three.js's `SSGINode` and `SSSNode`: their helpers against
three.js's, a crease that is darkened and lit by its walls, and a wall
that shadows the floor beside it."""

from animation.keyframe_track import LightIndex
from cameras.orthographic_camera import centered
from cameras.perspective_camera import PerspectiveCamera
from core.assets import Assets
from core.object3d import Object3D
from core.scene import NO_PARENT, Scene
from geometries.box import box
from geometries.plane import plane
from lights.light import directional_light
from materials.material import BASIC, Material
from math.vector3 import Vector3
from objects.mesh import Mesh
from postprocessing.composer import (
    SSGI,
    SSS,
    EffectComposer,
    Pass,
    frame_outputs,
    render_pass,
    ssgi_pass,
    sss_pass,
)
from postprocessing.screen_space import DepthView
from postprocessing.ssgi import (
    ScreenInputs,
    SsgiSettings,
    SssSettings,
    check_ssgi,
    check_sss,
    glsl_sign,
    gtao_fast_acos,
    occluded_sectors,
    ssgi_composite,
    ssgi_pixel,
    ssgi_signal,
    ssgi_temporal,
    sss_light,
    sss_light_direction,
    sss_pixel,
)
from render.framebuffer import Color, FloatColor
from render.target import (
    FLOAT_TARGET,
    OUTPUT_COLOR,
    OUTPUT_NORMAL,
    RenderTarget,
    TargetOutput,
)
from renderers.renderer import Renderer
from std.math import pi
from std.testing import (
    TestSuite,
    assert_almost_equal,
    assert_equal,
    assert_false,
    assert_raises,
    assert_true,
)
from units.si import Angle, DEGREE, Length, METER


comptime SIZE = 24


def test_the_helpers_are_three_js_s() raises:
    assert_almost_equal(gtao_fast_acos(1), 0, atol=1e-6)
    assert_almost_equal(gtao_fast_acos(0), Float32(pi / 2), atol=1e-6)
    assert_almost_equal(gtao_fast_acos(-1), Float32(pi), atol=1e-6)
    assert_almost_equal(gtao_fast_acos(0.5), 1.0553, atol=1e-3)
    assert_equal(glsl_sign(2), 1)
    assert_equal(glsl_sign(-2), -1)
    assert_equal(glsl_sign(0), 0)
    assert_equal(occluded_sectors(0, 1), UInt32(0xFFFFFFFF))
    assert_equal(occluded_sectors(0.5, 0.25), UInt32(0xFF) << 16)
    assert_equal(occluded_sectors(0.3, 0), UInt32(0))
    assert_equal(occluded_sectors(0.3, -0.1), UInt32(0))
    var still = SsgiSettings()
    still.use_temporal_filtering = False
    var fixed = ssgi_temporal(still)
    assert_equal(fixed[0], 1)
    assert_equal(fixed[1], 1)
    var moving = SsgiSettings()
    moving.frame_id = 7
    var turned = ssgi_temporal(moving)
    assert_almost_equal(turned[0], 300.0 / 360.0, atol=1e-6)
    assert_almost_equal(turned[1], 0.75, atol=1e-6)


def test_the_settings_are_checked() raises:
    check_ssgi(SsgiSettings())
    var bad = SsgiSettings()
    bad.slice_count = 0
    with assert_raises(contains="a slice and a step"):
        check_ssgi(bad)
    bad = SsgiSettings()
    bad.step_count = 0
    with assert_raises(contains="a slice and a step"):
        check_ssgi(bad)
    bad = SsgiSettings()
    bad.gi_intensity = Float32.MAX * 2
    with assert_raises(contains="finite"):
        check_ssgi(bad)
    bad = SsgiSettings()
    bad.radius = 0
    with assert_raises(contains="positive"):
        check_ssgi(bad)
    bad = SsgiSettings()
    bad.exp_factor = -1
    with assert_raises(contains="positive"):
        check_ssgi(bad)
    bad = SsgiSettings()
    bad.frame_id = -1
    with assert_raises(contains="frame count"):
        check_ssgi(bad)
    check_sss(SssSettings())
    var off = SssSettings()
    off.light = LightIndex(-1)
    with assert_raises(contains="light"):
        check_sss(off)
    off = SssSettings()
    off.quality = Float32.MAX * 2
    with assert_raises(contains="finite"):
        check_sss(off)
    off = SssSettings()
    off.frame_id = -1
    with assert_raises(contains="frame count"):
        check_sss(off)
    with assert_raises(contains="a slice and a step"):
        _ = ssgi_pass(slice_count=0)
    assert_true(ssgi_pass().kind == SSGI)
    assert_true(sss_pass().kind == SSS)
    # The frame carries normals for an SSGI, and velocities too when it
    # denoises.
    var passes = List[Pass]()
    passes.append(ssgi_pass())
    assert_equal(len(frame_outputs(passes)), 2)
    passes.append(ssgi_pass(denoise=True))
    assert_equal(len(frame_outputs(passes)), 3)


def a_camera() raises -> PerspectiveCamera:
    """Return a camera above and in front of the crease."""
    var camera = PerspectiveCamera(
        Angle(50.0, DEGREE), 1, Length(0.1, METER), Length(20.0, METER)
    )
    camera.place(Vector3(0, 1.2, 2.2), Vector3(0, 0.3, 0))
    return camera^


def a_scene(mut assets: Assets, light_target: Bool = False) raises -> Scene:
    """Return a gray floor, a white wall standing on it, and a sun from the
    right and above."""
    var scene = Scene()
    var floor = Object3D()
    floor.set_euler(
        Angle(-90.0, DEGREE), Angle(0.0, DEGREE), Angle(0.0, DEGREE)
    )
    scene.add_mesh(
        Mesh(
            assets.geometries.add(plane(Length(4, METER), Length(4, METER))),
            assets.materials.add(Material(Color(120, 120, 120), kind=BASIC)),
            scene.add(floor^),
        )
    )
    var wall = Object3D()
    wall.set_position(0.3, 0.4, -0.3)
    scene.add_mesh(
        Mesh(
            assets.geometries.add(
                box(Length(0.3, METER), Length(0.8, METER), Length(1.0, METER))
            ),
            assets.materials.add(Material(Color(255, 255, 255), kind=BASIC)),
            scene.add(wall^),
        )
    )
    var lamp = Object3D()
    lamp.set_position(3, 2, 0)
    var node = scene.add(lamp^)
    var target = NO_PARENT
    if light_target:
        var aim = Object3D()
        aim.set_position(0, 0, 0)
        target = scene.add(aim^)
    scene.add_light(directional_light(Color(255, 255, 255), node, 1, target))
    scene.update()
    return scene^


def drawn(scene: Scene, assets: Assets) raises -> RenderTarget:
    """Return the scene drawn with its normals."""
    var renderer = Renderer(SIZE, SIZE)
    renderer.set_background(Color(0, 0, 0))
    var outputs: List[TargetOutput] = [OUTPUT_COLOR, OUTPUT_NORMAL]
    var frame = RenderTarget(SIZE, SIZE, Color(0, 0, 0), FLOAT_TARGET, outputs)
    renderer.render_into(frame, scene, assets, a_camera())
    return frame^


def view_of(frame: RenderTarget) raises -> DepthView:
    """Return a frame's depth through the test camera."""
    var camera = a_camera()
    return DepthView(
        frame.depth,
        SIZE,
        SIZE,
        camera.projection_matrix(),
        Length(0.1, METER),
        Length(20.0, METER),
        frame.depth_mode,
        frame.normals,
    )


def test_the_crease_is_darkened_and_lit() raises:
    var assets = Assets()
    var scene = a_scene(assets)
    var frame = drawn(scene, assets)
    var inputs = ScreenInputs(frame, view_of(frame))
    var settings = SsgiSettings()
    var signal = ssgi_signal(inputs, settings)
    var occluded = 0
    var lit = 0
    for slot in range(SIZE * SIZE):
        var s = signal[slot]
        assert_true(s.a >= 0 and s.a <= 1)
        if s.a < 1:
            occluded += 1
        if s.r > 0.01 and s.a < 1:
            lit += 1
    assert_true(occluded > 10)
    assert_true(lit > 0)
    # The sky has no surface: white, with no light.
    assert_equal(ssgi_pixel(inputs, 0, 0, settings).a, 1)
    # Every variant three.js has runs, and keeps the AO a share.
    var variants = List[SsgiSettings]()
    var world = SsgiSettings()
    world.use_screen_space_sampling = False
    variants.append(world)
    var linear = SsgiSettings()
    linear.use_linear_thickness = True
    linear.slice_count = 2
    variants.append(linear)
    var backs = SsgiSettings()
    backs.backface_lighting = 0.5
    backs.use_temporal_filtering = False
    variants.append(backs)
    for at in range(len(variants)):
        var other = ssgi_signal(inputs, variants[at])
        for slot in range(SIZE * SIZE):
            assert_true(other[slot].a >= 0 and other[slot].a <= 1)
    # A bright bounce is held at a luminance of seven.
    var strong = SsgiSettings()
    strong.gi_intensity = 1000
    var held = ssgi_signal(inputs, strong)
    var capped = 0
    for slot in range(SIZE * SIZE):
        var light = held[slot]
        var luma = (
            0.2126729 * light.r + 0.7151522 * light.g + 0.0721750 * light.b
        )
        assert_true(luma <= 7.001)
        if luma > 6.99:
            capped += 1
    assert_true(capped > 0)
    # The composite: the frame times the AO, plus the frame times the light.
    var before = frame.colors[12 * SIZE + 12]
    ssgi_composite(frame, signal)
    var s = signal[12 * SIZE + 12]
    assert_almost_equal(
        frame.colors[12 * SIZE + 12].r,
        before.r * s.a + before.r * s.r,
        atol=1e-5,
    )


def test_a_frame_without_normals_takes_them_from_the_depth() raises:
    var assets = Assets()
    var scene = a_scene(assets)
    var frame = drawn(scene, assets)
    var plain = RenderTarget(SIZE, SIZE, Color(0, 0, 0), FLOAT_TARGET)
    plain.depth = frame.depth.copy()
    plain.colors = frame.colors.copy()
    var inputs = ScreenInputs(plain, view_of(frame))
    assert_true(inputs.normal(0.5, 0.8).length() > 0.9)
    with assert_raises(contains="the frame's size"):
        _ = ScreenInputs(RenderTarget(4, 4, Color(0, 0, 0)), view_of(frame))
    with assert_raises(contains="the frame's size"):
        _ = ScreenInputs(RenderTarget(SIZE, 4, Color(0, 0, 0)), view_of(frame))
    with assert_raises(contains="the frame's size"):
        _ = ScreenInputs(RenderTarget(4, SIZE, Color(0, 0, 0)), view_of(frame))


def test_the_light_direction_is_in_the_camera_s_space() raises:
    var assets = Assets()
    var scene = a_scene(assets)
    var view = a_camera().view_matrix_in(scene)
    var toward = sss_light_direction(scene, LightIndex(0), view)
    assert_almost_equal(toward.length(), 1, atol=1e-5)
    var aimed = a_scene(assets, True)
    var same = sss_light_direction(aimed, LightIndex(0), view)
    assert_almost_equal(same.x, toward.x, atol=1e-5)
    with assert_raises(contains="one of the scene's"):
        _ = sss_light_direction(scene, LightIndex(3), view)


def test_the_wall_shadows_the_floor_beside_it() raises:
    var assets = Assets()
    var scene = a_scene(assets)
    var frame = drawn(scene, assets)
    var inputs = ScreenInputs(frame, view_of(frame))
    var view = a_camera().view_matrix_in(scene)
    # A light from the left: the floor right of the wall is in its lee.
    var toward = Vector3(-1, 0.3, 0)
    toward.normalize()
    var settings = SssSettings()
    settings.max_distance = Length(1.0, METER)
    settings.thickness = Length(1.0, METER)
    settings.quality = 1
    var shadowed = 0
    for y in range(SIZE):
        for x in range(SIZE):
            if sss_pixel(inputs, x, y, toward, settings) < 1:
                shadowed += 1
    assert_true(shadowed > 0)
    # The sky has no surface: lit.
    assert_equal(sss_pixel(inputs, 0, 0, toward, settings), 1)
    # The temporal offsets change the walk, and keep it a shadow or not.
    settings.use_temporal_filtering = True
    settings.frame_id = 3
    var moved = sss_pixel(inputs, 12, 20, toward, settings)
    assert_true(moved == 0 or moved == 1)
    # Over a frame.
    var before = frame.colors[0]
    sss_light(frame, inputs, toward, settings)
    assert_equal(frame.colors[0].r, before.r)
    _ = view


def test_an_orthographic_depth_reads_its_own_view_z() raises:
    var camera = centered(
        Length(4.0, METER), 1.0, Length(0.1, METER), Length(10.0, METER)
    )
    camera.place(Vector3(0, 0, 5), Vector3(0, 0, 0))
    var projection = camera.projection_matrix()
    var depth = List[Float32]()
    for y in range(8):
        for x in range(8):
            # Farther to the left, and a near strip on the right.
            var z = Float32(-3)
            if x < 5:
                z = Float32(-5) - Float32(0.1) * Float32(5 - x)
            depth.append(projection.transform_point(Vector3(0, 0, z)).z)
    var frame = RenderTarget(8, 8, Color(0, 0, 0), FLOAT_TARGET)
    frame.depth = depth.copy()
    var view = DepthView(
        depth, 8, 8, projection, Length(0.1, METER), Length(10.0, METER)
    )
    var inputs = ScreenInputs(frame, view^)
    var settings = SssSettings()
    settings.max_distance = Length(2.0, METER)
    settings.thickness = Length(3.0, METER)
    settings.quality = 1
    # The rays rise toward the camera. To the right, the near strip is in
    # the way; to the left, every surface is behind the ray.
    var right = Vector3(1, 0, 0.5)
    right.normalize()
    var left = Vector3(-1, 0, 0.5)
    left.normalize()
    assert_equal(sss_pixel(inputs, 2, 4, right, settings), 0)
    assert_equal(sss_pixel(inputs, 2, 4, left, settings), 1)
    # A strip nearer than the thickness is passed over.
    var thin = settings
    thin.thickness = Length(0.1, METER)
    assert_equal(sss_pixel(inputs, 2, 4, right, thin), 1)
    # No quality takes no step.
    var none = settings
    none.quality = 0
    assert_equal(sss_pixel(inputs, 2, 4, right, none), 1)
    # Long rays leave the image by each edge and shadow nothing.
    var long = settings
    long.max_distance = Length(10.0, METER)
    var up = Vector3(0, 1, 0.5)
    up.normalize()
    var down = Vector3(0, -1, 0.5)
    down.normalize()
    assert_equal(sss_pixel(inputs, 1, 4, left, long), 1)
    assert_equal(sss_pixel(inputs, 1, 4, up, long), 1)
    assert_equal(sss_pixel(inputs, 1, 4, down, long), 1)
    var far_right = Vector3(1, 0, 3)
    far_right.normalize()
    assert_equal(sss_pixel(inputs, 5, 4, far_right, long), 1)


def test_the_composer_runs_both_passes() raises:
    var assets = Assets()
    var scene = a_scene(assets)
    var composer = EffectComposer()
    composer.add_pass(render_pass())
    composer.add_pass(ssgi_pass(denoise=True))
    composer.add_pass(sss_pass(max_distance=Length(0.5, METER)))
    var renderer = Renderer(SIZE, SIZE)
    _ = composer.render(renderer, scene, assets, a_camera())
    var image = composer.render(renderer, scene, assets, a_camera())
    assert_equal(image.width, SIZE)
    assert_equal(composer.passes[1].ssgi.frame_id, 2)
    assert_equal(composer.passes[1].temporal_denoise.frame_id, 2)
    assert_equal(composer.passes[2].sss.frame_id, 2)
    # Without the denoiser the frame keeps no velocity.
    var plain = EffectComposer()
    plain.add_pass(render_pass())
    plain.add_pass(ssgi_pass())
    _ = plain.render(renderer, scene, assets, a_camera())
    assert_equal(plain.passes[1].temporal_denoise.frame_id, 0)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
