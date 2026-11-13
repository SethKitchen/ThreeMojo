# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Tests for three.js's `SSRNode`: the metalness attachment it reads, its
settings, and a metal floor that reflects a red box. Then its stochastic
mode, its environment, its history and its refinement, on a row of pixels
whose geometry is known."""

from cameras.perspective_camera import PerspectiveCamera
from core.assets import Assets
from core.object3d import Object3D
from core.scene import Scene
from geometries.box import box
from geometries.plane import plane
from materials.material import BASIC, PHYSICAL, Material
from math.matrix4 import Matrix4
from math.vector2 import Vector2
from math.vector3 import Vector3
from objects.mesh import Mesh
from postprocessing.composer import (
    SSR_NODE,
    EffectComposer,
    Pass,
    frame_outputs,
    render_pass,
    ssr_node_pass,
)
from postprocessing.importance_sampled_environment import (
    ENV_RAY_LENGTH,
    EquirectEnvironment,
)
from postprocessing.rnoise import analytic_noise4
from postprocessing.screen_space import DepthView
from postprocessing.sampling import LightView
from postprocessing.ssr_node import (
    SsrNodeFrame,
    SsrNodeSettings,
    check_ssr_node,
    next_noise_index,
    screen_border_factor,
    ssr_node_add,
    ssr_node_light,
    ssr_node_pixel,
    ssr_node_blur,
    ssr_node_signal,
)
from postprocessing.temporal_denoise import RAY_LENGTH_ALPHA, SPECULAR_DENOISE
from render.framebuffer import Color, FloatColor
from render.rect import Rect
from render.target import (
    FLOAT_TARGET,
    OUTPUT_COLOR,
    OUTPUT_METAL_ROUGH,
    OUTPUT_NORMAL,
    OUTPUT_VELOCITY,
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


comptime SIZE = 32


def surfaces() -> List[TargetOutput]:
    """Return the outputs of a target with a metalness attachment."""
    return [OUTPUT_COLOR, OUTPUT_METAL_ROUGH]


def test_the_attachment_keeps_what_a_write_gives() raises:
    var target = RenderTarget(2, 2, Color(0, 0, 0), FLOAT_TARGET, surfaces())
    assert_true(target.has_metal_roughs())
    target.write(0, 0, FloatColor(1, 0, 0, 1), metal_rough=Vector2(1, 0.5))
    assert_equal(target.metal_rough_at(0, 0).y, 0.5)
    assert_equal(target.metal_rough_in(0).x, 1)
    target.blend(0, 0, FloatColor(0, 0, 1, 0.5))
    assert_equal(target.metal_rough_at(0, 0).x, 1)
    target.clear_inside(Rect(0, 1, 1, 1), Color(0, 0, 0))
    assert_equal(target.metal_rough_at(0, 0).x, 0)
    var raw = target.attachment(1)
    assert_equal(raw.get_pixel(0, 0)[3], 1)
    var plain = RenderTarget(1, 1, Color(0, 0, 0))
    assert_false(plain.has_metal_roughs())
    assert_equal(plain.metal_rough_in(0).x, 0)
    with assert_raises(contains="no metalness attachment"):
        _ = plain.metal_rough_at(0, 0)
    # A resolve averages the block.
    var sampled = RenderTarget(
        1, 1, Color(0, 0, 0), FLOAT_TARGET, surfaces(), samples=4
    )
    var buffer = sampled.multisample_buffer()
    buffer.write(0, 0, FloatColor(1, 1, 1, 1), metal_rough=Vector2(4, 0))
    sampled.resolve_samples(buffer, Rect.whole(1, 1))
    assert_equal(sampled.metal_rough_at(0, 0).x, 1)
    with assert_raises(contains="the target's outputs"):
        sampled.resolve_samples(
            RenderTarget(2, 2, Color(0, 0, 0), FLOAT_TARGET), Rect.whole(1, 1)
        )


def test_the_settings_are_checked() raises:
    check_ssr_node(SsrNodeSettings())
    var bad = SsrNodeSettings()
    bad.quality = Float32.MAX * 2
    with assert_raises(contains="finite"):
        check_ssr_node(bad)
    bad = SsrNodeSettings()
    bad.max_distance = Length(0, METER)
    with assert_raises(contains="positive"):
        check_ssr_node(bad)
    bad = SsrNodeSettings()
    bad.resolution_scale = 0
    with assert_raises(contains="positive"):
        check_ssr_node(bad)
    bad = SsrNodeSettings()
    bad.thickness = Length(-1, METER)
    with assert_raises(contains="negative"):
        check_ssr_node(bad)
    bad = SsrNodeSettings()
    bad.blur_quality = -1
    with assert_raises(contains="negative"):
        check_ssr_node(bad)
    bad = SsrNodeSettings()
    bad.blur_quality = 2048
    with assert_raises(contains="larger than this port"):
        check_ssr_node(bad)
    bad.blur_quality = Int.MAX
    with assert_raises(contains="larger than this port"):
        check_ssr_node(bad)
    with assert_raises(contains="positive"):
        _ = ssr_node_pass(max_distance=Length(-1, METER))
    assert_true(ssr_node_pass().kind == SSR_NODE)
    var steps: List[Pass] = [render_pass(), ssr_node_pass()]
    var outputs = frame_outputs(steps)
    assert_equal(len(outputs), 3)
    assert_true(outputs[1] == OUTPUT_NORMAL)
    assert_true(outputs[2] == OUTPUT_METAL_ROUGH)


def a_camera() raises -> PerspectiveCamera:
    """Return a camera above and in front of the floor."""
    var camera = PerspectiveCamera(
        Angle(50.0, DEGREE), 1, Length(0.1, METER), Length(20.0, METER)
    )
    camera.place(Vector3(0, 1.0, 2.5), Vector3(0, 0.2, 0))
    return camera^


def a_scene(mut assets: Assets, roughness: Float32 = 0) raises -> Scene:
    """Return a metal floor and a red box standing on it."""
    var scene = Scene()
    var floor = Object3D()
    floor.set_euler(
        Angle(-90.0, DEGREE), Angle(0.0, DEGREE), Angle(0.0, DEGREE)
    )
    scene.add_mesh(
        Mesh(
            assets.geometries.add(plane(Length(4, METER), Length(4, METER))),
            assets.materials.add(
                Material(
                    Color(255, 255, 255),
                    kind=PHYSICAL,
                    metalness=1,
                    roughness=roughness,
                )
            ),
            scene.add(floor^),
        )
    )
    var stand = Object3D()
    stand.set_position(0, 0.3, 0)
    scene.add_mesh(
        Mesh(
            assets.geometries.add(
                box(Length(0.6, METER), Length(0.6, METER), Length(0.6, METER))
            ),
            assets.materials.add(Material(Color(255, 0, 0), kind=BASIC)),
            scene.add(stand^),
        )
    )
    scene.update()
    return scene^


def red_on_floor(image: RenderTarget) raises -> Float32:
    """Return the red in the bottom quarter of the image, the floor in
    front of the box."""
    var total = Float32(0)
    for y in range(SIZE * 3 // 4, SIZE):
        for x in range(SIZE):
            total += image.color_at(x, y).r
    return total


def drawn(scene: Scene, assets: Assets) raises -> RenderTarget:
    """Return the scene drawn with its normals and metalness."""
    var renderer = Renderer(SIZE, SIZE)
    renderer.set_background(Color(0, 0, 0))
    var outputs: List[TargetOutput] = [
        OUTPUT_COLOR,
        OUTPUT_NORMAL,
        OUTPUT_METAL_ROUGH,
    ]
    var target = RenderTarget(SIZE, SIZE, Color(0, 0, 0), FLOAT_TARGET, outputs)
    renderer.render_into(target, scene, assets, a_camera())
    return target^


def view_of(target: RenderTarget) raises -> DepthView:
    """Return the target's depth seen through the camera."""
    var camera = a_camera()
    return DepthView(
        target.depth,
        SIZE,
        SIZE,
        camera.projection_matrix(),
        Length(0.1, METER),
        Length(20.0, METER),
        target.depth_mode,
        target.normals,
    )


def world_of() raises -> Matrix4:
    """Return the camera's world matrix."""
    var world = a_camera().view_matrix()
    world.invert()
    return world^


def test_the_renderer_keeps_the_floor_s_metalness() raises:
    var assets = Assets()
    var scene = a_scene(assets, 0.5)
    var target = drawn(scene, assets)
    var floor = target.metal_rough_at(SIZE // 2, SIZE - 2)
    assert_almost_equal(floor.x, 1)
    assert_almost_equal(floor.y, 0.5, atol=0.05)
    # The box is basic: neither.
    var box_here = target.metal_rough_at(SIZE // 2, SIZE // 2)
    assert_equal(box_here.x, 0)


def test_the_metal_floor_reflects_the_box() raises:
    var assets = Assets()
    var scene = a_scene(assets)
    var target = drawn(scene, assets)
    var before = red_on_floor(target)
    var settings = SsrNodeSettings()
    settings.max_distance = Length(3, METER)
    settings.quality = 1
    ssr_node_light(target, view_of(target), world_of(), settings)
    assert_true(red_on_floor(target) > before + 0.5)
    # Unblurred, the same.
    target = drawn(scene, assets)
    settings.use_roughness = False
    ssr_node_light(target, view_of(target), world_of(), settings)
    assert_true(red_on_floor(target) > before + 0.5)
    # A rough floor reads the blurred levels.
    assets = Assets()
    scene = a_scene(assets, 0.8)
    target = drawn(scene, assets)
    settings.use_roughness = True
    ssr_node_light(target, view_of(target), world_of(), settings)
    assert_true(red_on_floor(target) > 0)
    # A frame without the attachments is refused.
    var plain = RenderTarget(SIZE, SIZE, Color(0, 0, 0), FLOAT_TARGET)
    with assert_raises(contains="normal and metalness attachments"):
        ssr_node_light(plain, view_of(plain), world_of(), settings)


def test_non_metals_reflect_when_asked() raises:
    var assets = Assets()
    var scene = a_scene(assets)
    var target = drawn(scene, assets)
    # Every pixel's metalness to zero: nothing reflects, unless asked.
    for slot in range(SIZE * SIZE):
        target.metal_roughs[slot] = Vector2(0, 0)
    var before = red_on_floor(target)
    var settings = SsrNodeSettings()
    settings.max_distance = Length(3, METER)
    settings.quality = 1
    ssr_node_light(target, view_of(target), world_of(), settings)
    assert_almost_equal(red_on_floor(target), before, atol=1e-4)
    settings.reflect_non_metals = True
    ssr_node_light(target, view_of(target), world_of(), settings)
    assert_almost_equal(red_on_floor(target), before, atol=1e-4)


def test_a_surface_seen_edge_on_reflects_nothing() raises:
    # Through an identity projection, every normal across the view: the
    # ray is endless, its end has no place, and nothing is reflected.
    var colors = List[FloatColor](length=4, fill=FloatColor(1, 1, 1, 1))
    var across = List[FloatColor](length=4, fill=FloatColor(1, 0, 0, 0))
    var metal = List[FloatColor](length=4, fill=FloatColor(1, 0, 0, 0))
    var depth = List[Float32](length=4, fill=0)
    var view = DepthView(
        depth, 2, 2, Matrix4(), Length(0.1, METER), Length(10, METER)
    )
    var frame = SsrNodeFrame(
        LightView(colors, 2, 2),
        LightView(across, 2, 2),
        LightView(metal, 2, 2),
        2,
        2,
        Matrix4(),
        Matrix4(),
        0.1,
        10,
    )
    var seen = ssr_node_pixel(frame, view, 0, 0, SsrNodeSettings())
    _ = colors^
    _ = across^
    _ = metal^
    assert_equal(seen.r, 0)
    assert_equal(seen.a, 0)


def reflected_red(
    mut target: RenderTarget, settings: SsrNodeSettings
) raises -> Float32:
    """Return how much red the settings' reflections add to the floor."""
    var before = red_on_floor(target)
    ssr_node_light(target, view_of(target), world_of(), settings)
    return red_on_floor(target) - before


def test_what_the_march_passes_over() raises:
    var assets = Assets()
    var scene = a_scene(assets)
    var settings = SsrNodeSettings()
    settings.max_distance = Length(3, METER)
    settings.quality = 1
    # No normal anywhere: the reflection runs straight back, and finds
    # nothing to face it.
    var target = drawn(scene, assets)
    for slot in range(SIZE * SIZE):
        target.normals[slot] = Vector3(0, 0, 0)
    _ = reflected_red(target, settings)
    # The box's faces turned along every ray: each is passed over.
    target = drawn(scene, assets)
    for slot in range(SIZE * SIZE):
        if target.metal_roughs[slot].x == 0:
            target.normals[slot] = Vector3(0, 1, 0)
    assert_almost_equal(reflected_red(target, settings), 0, atol=1e-4)
    # A march of one step takes none.
    target = drawn(scene, assets)
    settings.quality = 0.001
    assert_almost_equal(reflected_red(target, settings), 0, atol=1e-4)
    # A short ray with a deep thickness hits the box farther from the floor
    # than the ray reaches, and stops.
    target = drawn(scene, assets)
    settings.quality = 1
    settings.max_distance = Length(0.05, METER)
    settings.thickness = Length(100, METER)
    assert_almost_equal(reflected_red(target, settings), 0, atol=1e-4)
    # The box pulled up to the near plane: where a ray passes behind it,
    # the point there is far above the floor, past the ray's reach, and
    # the march stops.
    target = drawn(scene, assets)
    for slot in range(SIZE * SIZE):
        if target.metal_roughs[slot].x == 0 and target.depth[slot] < 1:
            target.depth[slot] = -0.999
    settings.max_distance = Length(0.5, METER)
    _ = reflected_red(target, settings)


def test_an_orthographic_camera_reflects_too() raises:
    from cameras.orthographic_camera import centered

    var assets = Assets()
    var scene = a_scene(assets)
    var camera = centered(
        Length(3.0, METER), 1.0, Length(0.1, METER), Length(20.0, METER)
    )
    camera.place(Vector3(0, 1.0, 2.5), Vector3(0, 0.2, 0))
    var renderer = Renderer(SIZE, SIZE)
    renderer.set_background(Color(0, 0, 0))
    var outputs: List[TargetOutput] = [
        OUTPUT_COLOR,
        OUTPUT_NORMAL,
        OUTPUT_METAL_ROUGH,
    ]
    var target = RenderTarget(SIZE, SIZE, Color(0, 0, 0), FLOAT_TARGET, outputs)
    renderer.render_into(target, scene, assets, camera)
    var view = DepthView(
        target.depth,
        SIZE,
        SIZE,
        camera.projection_matrix(),
        Length(0.1, METER),
        Length(20.0, METER),
        target.depth_mode,
        target.normals,
    )
    var world = camera.view_matrix()
    world.invert()
    var before = red_on_floor(target)
    var settings = SsrNodeSettings()
    settings.max_distance = Length(3, METER)
    settings.quality = 1
    ssr_node_light(target, view, world, settings)
    assert_true(red_on_floor(target) > before)


def test_the_composer_runs_an_ssr_node_pass() raises:
    var assets = Assets()
    var scene = a_scene(assets)
    var composer = EffectComposer()
    composer.add_pass(render_pass())
    composer.add_pass(ssr_node_pass(max_distance=Length(3, METER), quality=1))
    var renderer = Renderer(SIZE, SIZE)
    renderer.set_background(Color(0, 0, 0))
    var image = composer.render(renderer, scene, assets, a_camera())
    assert_equal(image.width, SIZE)


def test_each_ssr_number_must_be_finite() raises:
    for field in range(6):
        var bad = SsrNodeSettings()
        var infinity = Float32.MAX * 2
        if field == 0:
            bad.max_distance = Length(infinity, METER)
        elif field == 1:
            bad.thickness = Length(infinity, METER)
        elif field == 2:
            bad.intensity = infinity
        elif field == 3:
            bad.max_luminance = infinity
        elif field == 4:
            bad.quality = infinity
        else:
            bad.resolution_scale = infinity
        with assert_raises(contains="finite"):
            check_ssr_node(bad)


def test_normals_without_metalness_are_refused() raises:
    var outputs: List[TargetOutput] = [OUTPUT_COLOR, OUTPUT_NORMAL]
    var frame = RenderTarget(SIZE, SIZE, Color(0, 0, 0), FLOAT_TARGET, outputs)
    with assert_raises(contains="attachments"):
        ssr_node_light(frame, view_of(frame), world_of(), SsrNodeSettings())


def test_an_ssr_blur_must_fit() raises:
    var colors = List[FloatColor](length=1, fill=FloatColor(0, 0, 0, 0))
    var source = LightView(colors, 1, 1)
    with assert_raises(contains="at least one pixel"):
        _ = ssr_node_blur(source, 0, 1, 1, 1)
    with assert_raises(contains="at least one pixel"):
        _ = ssr_node_blur(source, 1, 0, 1, 1)
    with assert_raises(contains="larger than this port"):
        _ = ssr_node_blur(source, 1 << 32, 1 << 32, 1, 1)
    with assert_raises(contains="larger than this port"):
        _ = ssr_node_blur(source, 1, 1, 2048, 1)
    with assert_raises(contains="larger than this port"):
        _ = ssr_node_blur(source, 1, 1, Int.MAX, 1)
    _ = colors^


def test_a_ray_with_only_vertical_projection_overflow_reflects_nothing() raises:
    from std.memory import bitcast

    var colors = List[FloatColor](length=4, fill=FloatColor(1, 1, 1, 1))
    var normals = List[FloatColor](
        length=4, fill=FloatColor(0, 0.70710677, 0.70710677, 0)
    )
    var metal = List[FloatColor](length=4, fill=FloatColor(1, 0, 0, 0))
    var depth = List[Float32](length=4, fill=0)
    var view = DepthView(
        depth, 2, 2, Matrix4(), Length(0.1, METER), Length(10, METER)
    )
    var projection = Matrix4()
    projection.elements[5] = bitcast[DType.float32](UInt32(0x7F7FFFFF))
    var frame = SsrNodeFrame(
        LightView(colors, 2, 2),
        LightView(normals, 2, 2),
        LightView(metal, 2, 2),
        2,
        2,
        Matrix4(),
        projection,
        0.1,
        10,
    )
    var seen = ssr_node_pixel(frame, view, 0, 0, SsrNodeSettings())
    _ = colors^
    _ = normals^
    _ = metal^
    assert_equal(seen.a, Float32(0))


# --- the stochastic mode, the environment, the history and the refinement ---


def test_the_stochastic_settings_are_checked() raises:
    for field in range(8):
        var bad = SsrNodeSettings()
        var infinity = Float32.MAX * 2
        var message = String("mirror bias")
        if field == 0:
            bad.mirror_bias = -0.1
        elif field == 1:
            bad.mirror_bias = 1.5
        elif field == 2:
            bad.step_exponent = 0
            message = "step exponent"
        elif field == 3:
            bad.step_exponent = infinity
            message = "step exponent"
        elif field == 4:
            bad.screen_edge_fade = -1
            message = "border fade"
        elif field == 5:
            bad.screen_edge_fade = infinity
            message = "border fade"
        elif field == 6:
            bad.environment_intensity = -1
            message = "environment intensity"
        else:
            bad.environment_intensity = infinity
            message = "environment intensity"
        with assert_raises(contains=message):
            check_ssr_node(bad)
    var bad = SsrNodeSettings()
    bad.noise_index = -1
    with assert_raises(contains="noise index"):
        check_ssr_node(bad)
    # Only stochastic reflections are denoised.
    bad = SsrNodeSettings()
    bad.denoise = True
    with assert_raises(contains="stochastic reflections only"):
        check_ssr_node(bad)
    bad.stochastic = True
    check_ssr_node(bad)
    with assert_raises(contains="stochastic reflections only"):
        _ = ssr_node_pass(denoise=True)
    # The noise moves on a frame at a time, and starts again.
    assert_equal(next_noise_index(0), 1)
    assert_equal(next_noise_index(2147483646), 0)
    # A pass that denoises asks for the frame's velocities too.
    var steps: List[Pass] = [
        render_pass(),
        ssr_node_pass(stochastic=True, denoise=True),
    ]
    var outputs = frame_outputs(steps)
    assert_equal(len(outputs), 4)
    assert_true(outputs[2] == OUTPUT_VELOCITY)
    assert_true(steps[1].temporal_denoise.mode == SPECULAR_DENOISE)
    assert_true(steps[1].temporal_denoise.alpha_source == RAY_LENGTH_ALPHA)
    steps[1].enabled = False
    assert_equal(len(frame_outputs(steps)), 1)
    var plain: List[Pass] = [render_pass(), ssr_node_pass(stochastic=True)]
    assert_equal(len(frame_outputs(plain)), 3)


def test_the_border_factor_is_three_js_s() raises:
    # Against `assets/ssr_denoise/reference.py`, a transcription of
    # `computeScreenBorderFactor`.
    assert_almost_equal(screen_border_factor(0.5, 0.5, 0.2), 1, atol=1e-6)
    assert_almost_equal(
        screen_border_factor(0.05, 0.5, 0.2), 0.7114159, atol=1e-5
    )
    assert_almost_equal(
        screen_border_factor(0.5, 0.98, 0.2), 0.4681734, atol=1e-5
    )
    assert_almost_equal(screen_border_factor(0.3, 0.3, 0), 1, atol=1e-6)
    assert_equal(screen_border_factor(0, 0.3, 0.2), 0)


comptime ROW = 8
# The view z of a row test's far background, of a surface a ray along x
# hits, and of a blocker just in front of the camera.
comptime ROW_FAR = Float32(-15)
comptime ROW_WALL = Float32(-9.5)
comptime ROW_NEAR = Float32(-2)


def row_depths(wall_from: Int = ROW, blocker: Int = -1) -> List[Float32]:
    """Return the view z of each column of a row test: a mirror at column
    one, a far background, a wall from a column on, and a blocker."""
    var out = List[Float32](length=ROW, fill=ROW_FAR)
    out[1] = -10
    for column in range(wall_from, ROW):
        out[column] = ROW_WALL
    if blocker >= 0:
        out[blocker] = ROW_NEAR
    return out^


def row_reflection(
    depths: List[Float32],
    normal: Vector3,
    settings: SsrNodeSettings,
    environment: Optional[EquirectEnvironment] = None,
    roughness: Float32 = 0,
    tint: Bool = False,
) raises -> FloatColor:
    """Return the reflection of the pixel at column one of an 8 by 8
    orthographic frame whose every row is alike. A pixel is a meter wide,
    and the pixel's surface is ten meters away with the given normal.
    """
    from cameras.orthographic_camera import centered

    var projection = centered(
        Length(8.0, METER), 1.0, Length(0.1, METER), Length(20.0, METER)
    ).projection_matrix()
    var depth = List[Float32]()
    var colors = List[FloatColor]()
    var normals = List[FloatColor]()
    var surfaces = List[FloatColor]()
    var tints = List[FloatColor]()
    for _ in range(ROW):
        for x in range(ROW):
            depth.append(projection.transform_point(Vector3(0, 0, depths[x])).z)
            colors.append(FloatColor(0.5, 0.25, 0.125, 1))
            if x == 1:
                normals.append(FloatColor(normal.x, normal.y, normal.z, 0))
            else:
                normals.append(FloatColor(-1, 0, 0, 0))
            surfaces.append(FloatColor(1, roughness, 0, 0))
            tints.append(FloatColor(1, 0.5, 0, 1))
    var view = DepthView(
        depth, ROW, ROW, projection, Length(0.1, METER), Length(20.0, METER)
    )
    var frame = SsrNodeFrame(
        LightView(colors, ROW, ROW),
        LightView(normals, ROW, ROW),
        LightView(surfaces, ROW, ROW),
        ROW,
        ROW,
        Matrix4(),
        projection,
        0.1,
        20,
    )
    if tint:
        frame = frame.with_diffuse(LightView(tints, ROW, ROW))
    var seen = ssr_node_pixel(frame, view, 1, 3, settings, environment)
    _ = colors^
    _ = normals^
    _ = surfaces^
    _ = tints^
    return seen


def toward(x: Float32, y: Float32) -> Vector3:
    """Return a normal that sends a ray along the view straight across
    the image: half a turn between the view's z and a direction across."""
    var out = Vector3(x, y, 1)
    out.normalize()
    return out


def row_settings(stochastic: Bool) -> SsrNodeSettings:
    """Return settings whose ray is long enough to reach the row's wall."""
    var settings = SsrNodeSettings()
    settings.max_distance = Length(4, METER)
    settings.quality = 1
    settings.stochastic = stochastic
    return settings


def test_a_refined_mirror_hit_past_the_reach_reflects_nothing() raises:
    # The ray runs along the row. It passes behind a blocker that is too
    # far in front of it to count, and then hits the wall.
    var depths = row_depths(wall_from=5, blocker=4)
    var settings = row_settings(False)
    var coarse = row_reflection(depths, toward(1, 0), settings)
    assert_true(coarse.r > 0)
    assert_true(coarse.a > 3 and coarse.a < 5)
    # The refinement bisects back to where the ray first passed behind the
    # depth: the blocker, eight meters off the ray and past its reach.
    settings.binary_refine = True
    var refined = row_reflection(depths, toward(1, 0), settings)
    assert_equal(refined.r, 0)
    assert_equal(refined.a, 0)
    # With no blocker, the refined hit is the wall's near edge.
    var clear = row_reflection(row_depths(wall_from=5), toward(1, 0), settings)
    assert_true(clear.r > 0)
    assert_true(clear.a < coarse.a)


def test_a_stochastic_ray_marches_a_fixed_count_of_steps() raises:
    var settings = row_settings(True)
    # A mirror's lobe is a thousandth wide, so the ray runs along the row
    # and hits the wall. The alpha is the distance times the lobe's
    # dominant factor, which is one for a mirror seen at 45 degrees.
    var hit = row_reflection(row_depths(wall_from=5), toward(1, 0), settings)
    assert_true(hit.a > 2 and hit.a < 5)
    assert_almost_equal(hit.r / hit.g, 2, atol=1e-3)
    # The base color tints a metal's reflection.
    var tinted = row_reflection(
        row_depths(wall_from=5), toward(1, 0), settings, tint=True
    )
    assert_almost_equal(tinted.r, hit.r, atol=1e-3)
    assert_almost_equal(tinted.g / tinted.r, 0.25, atol=1e-2)
    assert_true(tinted.b < 1e-3)
    # The blocker is too far in front of the ray, and is passed over.
    var passed = row_reflection(
        row_depths(wall_from=5, blocker=4), toward(1, 0), settings
    )
    assert_true(passed.a > 2 and passed.a < 5)
    # A ray that ends over the background hits nothing, and reads as the
    # environment's ray. There is no environment, so it is black.
    settings.max_distance = Length(1, METER)
    var short = row_reflection(row_depths(), toward(1, 0), settings)
    assert_equal(short.a, ENV_RAY_LENGTH)
    assert_equal(short.r, 0)
    # A march of one step takes none.
    settings.max_distance = Length(4, METER)
    settings.quality = 0.001
    var none = row_reflection(row_depths(wall_from=5), toward(1, 0), settings)
    assert_equal(none.a, ENV_RAY_LENGTH)
    # A pixel with no surface reflects nothing at all.
    var sky = row_depths()
    sky[1] = -25
    settings.quality = 1
    var empty = row_reflection(sky, toward(1, 0), settings)
    assert_equal(empty.a, 0)


def test_a_stochastic_ray_stops_at_each_edge_of_the_image() raises:
    var settings = row_settings(True)
    settings.max_distance = Length(8, METER)
    # Right, left, up and down: each ray leaves the image over the
    # background.
    var right = row_reflection(row_depths(), toward(1, 0), settings)
    assert_equal(right.a, ENV_RAY_LENGTH)
    var left = row_reflection(row_depths(), toward(-1, 0), settings)
    assert_equal(left.a, ENV_RAY_LENGTH)
    var up = row_reflection(row_depths(), toward(0, 1), settings)
    assert_equal(up.a, ENV_RAY_LENGTH)
    var down = row_reflection(row_depths(), toward(0, -1), settings)
    assert_equal(down.a, ENV_RAY_LENGTH)


def test_a_stochastic_hit_is_refined() raises:
    # The wall starts at the next column, so the first step hits. The step
    # before it is the ray's start, whatever the noise.
    var depths = row_depths(wall_from=2)
    var below = 0
    var above = 0
    for index in range(16):
        var settings = row_settings(True)
        settings.binary_refine = True
        settings.noise_index = index
        var jitter = analytic_noise4(1, 3, index, 47).z
        if jitter < 0.5:
            below += 1
        else:
            above += 1
        var refined = row_reflection(depths, toward(1, 0), settings)
        assert_true(refined.a > 0 and refined.a < 2)
        assert_true(refined.r > 0)
    assert_true(below > 0 and above > 0)
    # A refined march that hits nothing is not refined.
    var settings = row_settings(True)
    settings.binary_refine = True
    settings.max_distance = Length(1, METER)
    var none = row_reflection(row_depths(), toward(1, 0), settings)
    assert_equal(none.a, ENV_RAY_LENGTH)


def gray_environment(
    value: Float32, importance_sampling: Bool
) raises -> EquirectEnvironment:
    """Return an environment of one gray."""
    return EquirectEnvironment(
        8,
        4,
        List[FloatColor](length=32, fill=FloatColor(value, value, value, 1)),
        False,
        importance_sampling,
    )


def test_a_ray_that_hits_nothing_takes_the_environment() raises:
    var settings = row_settings(True)
    settings.max_distance = Length(1, METER)
    var env = Optional[EquirectEnvironment](gray_environment(0.5, False))
    var lit = row_reflection(row_depths(), toward(1, 0), settings, env)
    assert_equal(lit.a, ENV_RAY_LENGTH)
    # A mirror's weight is its reflectance, so the light is the map's,
    # times three.js's pi.
    assert_almost_equal(lit.r, 0.5 * Float32(pi), atol=1e-2)
    assert_almost_equal(lit.g, lit.r, atol=1e-6)
    settings.environment_intensity = 1
    var plain = row_reflection(row_depths(), toward(1, 0), settings, env)
    assert_almost_equal(plain.r, 0.5, atol=1e-2)
    # The intensity scales the light, and the luminance cap holds it.
    settings.intensity = 0.5
    var dim = row_reflection(row_depths(), toward(1, 0), settings, env)
    assert_almost_equal(dim.r, plain.r * 0.5, atol=1e-6)
    settings.intensity = 1
    settings.max_luminance = 0.25
    var capped = row_reflection(row_depths(), toward(1, 0), settings, env)
    assert_almost_equal(capped.r, 0.25, atol=1e-3)
    settings.max_luminance = 10
    # A map with distributions is sampled by the power heuristic.
    var sampled = Optional[EquirectEnvironment](gray_environment(0.5, True))
    var mis = row_reflection(
        row_depths(), toward(1, 0), settings, sampled, roughness=0.5
    )
    assert_equal(mis.a, ENV_RAY_LENGTH)
    assert_true(mis.r > 0 and mis.r < 2)
    # A fade to black darkens the light of a pixel near the border.
    settings.screen_edge_fade_black = True
    settings.screen_edge_fade = 0.5
    var faded = row_reflection(row_depths(), toward(1, 0), settings, env)
    assert_true(faded.r > 0 and faded.r < plain.r)
    assert_almost_equal(
        faded.r / plain.r,
        screen_border_factor(1.5 / 8, 3.5 / 8, 0.5),
        atol=1e-3,
    )


def test_a_stochastic_hit_fades_at_the_border() raises:
    var depths = row_depths(wall_from=5)
    var env = Optional[EquirectEnvironment](gray_environment(4, False))
    var settings = row_settings(True)
    settings.environment_intensity = 1
    # No fade: the hit's color as it is.
    settings.screen_edge_fade = 0
    var whole = row_reflection(depths, toward(1, 0), settings, env)
    assert_almost_equal(whole.r, 0.5, atol=1e-2)
    # A wide fade mixes the hit toward the environment's light.
    settings.screen_edge_fade = 1
    var toward_env = row_reflection(depths, toward(1, 0), settings, env)
    assert_true(toward_env.r > whole.r + 0.1)
    # Without an environment it mixes toward black.
    var toward_black = row_reflection(depths, toward(1, 0), settings)
    assert_true(toward_black.r < whole.r - 0.05)
    assert_true(toward_black.r > 0)
    # A fade to black scales the hit by the border factor at the hit.
    settings.screen_edge_fade_black = True
    var black = row_reflection(depths, toward(1, 0), settings, env)
    assert_true(black.r < whole.r - 0.05)
    assert_true(black.r > 0)


def with_velocities(scene: Scene, assets: Assets) raises -> RenderTarget:
    """Return the scene drawn with its normals, velocities and metalness."""
    var renderer = Renderer(SIZE, SIZE)
    renderer.set_background(Color(0, 0, 0))
    var outputs: List[TargetOutput] = [
        OUTPUT_COLOR,
        OUTPUT_NORMAL,
        OUTPUT_VELOCITY,
        OUTPUT_METAL_ROUGH,
    ]
    var target = RenderTarget(SIZE, SIZE, Color(0, 0, 0), FLOAT_TARGET, outputs)
    renderer.render_into(target, scene, assets, a_camera())
    return target^


def red_of(signal: List[FloatColor]) -> Float32:
    """Return the red a signal holds."""
    var total = Float32(0)
    for slot in range(len(signal)):
        total += signal[slot].r
    return total


def test_the_last_result_adds_a_second_bounce() raises:
    var assets = Assets()
    var scene = a_scene(assets)
    var target = with_velocities(scene, assets)
    var view = view_of(target)
    for stochastic in range(2):
        var settings = SsrNodeSettings()
        settings.max_distance = Length(3, METER)
        settings.quality = 1
        settings.stochastic = stochastic == 1
        var once = red_of(ssr_node_signal(target, view, world_of(), settings))
        assert_true(once > 0)
        # A history that holds many frames adds its light to each hit.
        var bright = List[FloatColor](
            length=SIZE * SIZE, fill=FloatColor(1, 1, 1, 0)
        )
        var twice = red_of(
            ssr_node_signal(target, view, world_of(), settings, None, bright)
        )
        assert_true(twice > once * 1.5)
        # A history of one frame adds nothing.
        var new = List[FloatColor](
            length=SIZE * SIZE, fill=FloatColor(1, 1, 1, 1)
        )
        var same = red_of(
            ssr_node_signal(target, view, world_of(), settings, None, new)
        )
        assert_almost_equal(same, once, atol=1e-3)
    # A history of another size, and a frame with no velocities, are
    # refused.
    var settings = SsrNodeSettings()
    var short = List[FloatColor](length=4, fill=FloatColor(1, 1, 1, 0))
    with assert_raises(contains="history"):
        _ = ssr_node_signal(target, view, world_of(), settings, None, short)
    var still = drawn(scene, assets)
    var whole = List[FloatColor](
        length=SIZE * SIZE, fill=FloatColor(1, 1, 1, 0)
    )
    with assert_raises(contains="history"):
        _ = ssr_node_signal(
            still, view_of(still), world_of(), settings, None, whole
        )


def test_a_stochastic_floor_reflects_the_box() raises:
    var assets = Assets()
    var scene = a_scene(assets)
    var target = drawn(scene, assets)
    var before = red_on_floor(target)
    var settings = SsrNodeSettings()
    settings.max_distance = Length(3, METER)
    settings.quality = 1
    settings.stochastic = True
    var signal = ssr_node_signal(target, view_of(target), world_of(), settings)
    var hits = 0
    var misses = 0
    var empty = 0
    for slot in range(SIZE * SIZE):
        if signal[slot].a == 0:
            empty += 1
        elif signal[slot].a == ENV_RAY_LENGTH:
            misses += 1
        else:
            hits += 1
    assert_true(hits > 0 and misses > 0 and empty > 0)
    # Added as they are, with no blur chain.
    ssr_node_light(target, view_of(target), world_of(), settings)
    assert_true(red_on_floor(target) > before + 0.5)
    # A rough floor scatters its rays, and some are drawn again. The
    # refinement and a half-size target change nothing about that.
    assets = Assets()
    scene = a_scene(assets, 1)
    target = drawn(scene, assets)
    settings.binary_refine = True
    settings.resolution_scale = 0.5
    var env = Optional[EquirectEnvironment](gray_environment(0.5, False))
    var rough = ssr_node_signal(
        target, view_of(target), world_of(), settings, env
    )
    assert_equal(len(rough), SIZE * SIZE // 4)
    var lit = 0
    for slot in range(len(rough)):
        assert_true(rough[slot].r >= 0 and rough[slot].a >= 0)
        if rough[slot].r > 0:
            lit += 1
    assert_true(lit > 0)
    ssr_node_light(target, view_of(target), world_of(), settings, env)


def test_a_stochastic_orthographic_camera_reflects_too() raises:
    from cameras.orthographic_camera import centered

    var assets = Assets()
    var scene = a_scene(assets)
    var camera = centered(
        Length(3.0, METER), 1.0, Length(0.1, METER), Length(20.0, METER)
    )
    camera.place(Vector3(0, 1.0, 2.5), Vector3(0, 0.2, 0))
    var renderer = Renderer(SIZE, SIZE)
    renderer.set_background(Color(0, 0, 0))
    var outputs: List[TargetOutput] = [
        OUTPUT_COLOR,
        OUTPUT_NORMAL,
        OUTPUT_METAL_ROUGH,
    ]
    var target = RenderTarget(SIZE, SIZE, Color(0, 0, 0), FLOAT_TARGET, outputs)
    renderer.render_into(target, scene, assets, camera)
    var view = DepthView(
        target.depth,
        SIZE,
        SIZE,
        camera.projection_matrix(),
        Length(0.1, METER),
        Length(20.0, METER),
        target.depth_mode,
        target.normals,
    )
    var world = camera.view_matrix()
    world.invert()
    for stochastic in range(2):
        var settings = SsrNodeSettings()
        settings.max_distance = Length(3, METER)
        settings.quality = 1
        settings.binary_refine = True
        settings.stochastic = stochastic == 1
        assert_true(red_of(ssr_node_signal(target, view, world, settings)) > 0)


def test_a_stochastic_ray_with_no_place_takes_the_environment() raises:
    from std.memory import bitcast

    var env = Optional[EquirectEnvironment](gray_environment(0.5, False))
    var settings = SsrNodeSettings()
    settings.stochastic = True
    var colors = List[FloatColor](length=4, fill=FloatColor(1, 1, 1, 1))
    var metal = List[FloatColor](length=4, fill=FloatColor(1, 0, 0, 0))
    var depth = List[Float32](length=4, fill=0)
    var view = DepthView(
        depth, 2, 2, Matrix4(), Length(0.1, METER), Length(10, METER)
    )
    # A surface seen edge on: the ray is endless.
    var across = List[FloatColor](length=4, fill=FloatColor(1, 0, 0, 0))
    var edge_on = SsrNodeFrame(
        LightView(colors, 2, 2),
        LightView(across, 2, 2),
        LightView(metal, 2, 2),
        2,
        2,
        Matrix4(),
        Matrix4(),
        0.1,
        10,
    )
    var seen = ssr_node_pixel(edge_on, view, 0, 0, settings, env)
    assert_equal(seen.a, ENV_RAY_LENGTH)
    # A projection that overflows down the image only.
    var normals = List[FloatColor](
        length=4, fill=FloatColor(0, 0.70710677, 0.70710677, 0)
    )
    var projection = Matrix4()
    projection.elements[5] = bitcast[DType.float32](UInt32(0x7F7FFFFF))
    var tall = SsrNodeFrame(
        LightView(colors, 2, 2),
        LightView(normals, 2, 2),
        LightView(metal, 2, 2),
        2,
        2,
        Matrix4(),
        projection,
        0.1,
        10,
    )
    var lost = ssr_node_pixel(tall, view, 0, 0, settings, env)
    _ = colors^
    _ = across^
    _ = normals^
    _ = metal^
    assert_equal(lost.a, ENV_RAY_LENGTH)
    assert_true(lost.r > 0)


def test_an_image_is_added_to_the_frame() raises:
    var frame = RenderTarget(2, 2, Color(0, 0, 0), FLOAT_TARGET)
    var light = List[FloatColor](length=1, fill=FloatColor(0.25, 0.5, 1, 9))
    ssr_node_add(frame, light, 1, 1)
    assert_almost_equal(frame.color_at(1, 1).r, 0.25, atol=1e-6)
    assert_almost_equal(frame.color_at(0, 1).b, 1, atol=1e-6)
    with assert_raises(contains="one entry a pixel"):
        ssr_node_add(frame, light, 0, 1)
    with assert_raises(contains="one entry a pixel"):
        ssr_node_add(frame, light, 1, 0)
    with assert_raises(contains="one entry a pixel"):
        ssr_node_add(frame, light, 2, 2)


def test_the_composer_denoises_stochastic_reflections() raises:
    var assets = Assets()
    var scene = a_scene(assets, 0.3)
    var composer = EffectComposer()
    composer.add_pass(render_pass())
    composer.add_pass(
        ssr_node_pass(
            max_distance=Length(3, METER),
            quality=0.25,
            stochastic=True,
            denoise=True,
            environment=Optional[EquirectEnvironment](
                gray_environment(0.5, False)
            ),
        )
    )
    var renderer = Renderer(SIZE, SIZE)
    renderer.set_background(Color(0, 0, 0))
    var plain = EffectComposer()
    plain.add_pass(render_pass())
    var bare = plain.render(renderer, scene, assets, a_camera())
    var first = composer.render(renderer, scene, assets, a_camera())
    assert_equal(first.width, SIZE)
    assert_equal(composer.passes[1].ssr_node.noise_index, 1)
    assert_equal(composer.passes[1].temporal_denoise.history_width, SIZE)
    assert_equal(composer.passes[1].temporal_denoise.frame_id, 1)
    # The floor takes the environment's light and the box's reflection.
    var floor_now = first.get_pixel(SIZE // 2, SIZE - 2)
    var floor_was = bare.get_pixel(SIZE // 2, SIZE - 2)
    assert_true(Int(floor_now.r) > Int(floor_was.r))
    # The second frame reads the first's result as its history.
    _ = composer.render(renderer, scene, assets, a_camera())
    assert_equal(composer.passes[1].ssr_node.noise_index, 2)
    assert_equal(composer.passes[1].temporal_denoise.frame_id, 2)
    # A history of another height is not read, and is seeded again.
    composer.passes[1].temporal_denoise.history_height = SIZE + 1
    _ = composer.render(renderer, scene, assets, a_camera())
    assert_equal(composer.passes[1].temporal_denoise.history_height, SIZE)
    # Half-size reflections are denoised at the frame's size.
    composer.passes[1].ssr_node.resolution_scale = 0.5
    _ = composer.render(renderer, scene, assets, a_camera())
    assert_equal(len(composer.passes[1].temporal_denoise.history), SIZE * SIZE)
    # A stochastic pass that does not denoise adds the raw reflections.
    var raw = EffectComposer()
    raw.add_pass(render_pass())
    raw.add_pass(
        ssr_node_pass(max_distance=Length(3, METER), quality=1, stochastic=True)
    )
    var noisy = raw.render(renderer, scene, assets, a_camera())
    assert_equal(noisy.width, SIZE)
    assert_equal(raw.passes[1].ssr_node.noise_index, 1)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
