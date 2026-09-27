# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Tests for three.js's `SSRNode`: the metalness attachment it reads, its
settings, and a metal floor that reflects a red box."""

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
from postprocessing.screen_space import DepthView
from postprocessing.sampling import LightView
from postprocessing.ssr_node import (
    SsrNodeFrame,
    SsrNodeSettings,
    check_ssr_node,
    ssr_node_light,
    ssr_node_pixel,
)
from render.framebuffer import Color, FloatColor
from render.rect import Rect
from render.target import (
    FLOAT_TARGET,
    OUTPUT_COLOR,
    OUTPUT_METAL_ROUGH,
    OUTPUT_NORMAL,
    UNSIGNED_BYTE_TARGET,
    RenderTarget,
    TargetOutput,
)
from renderers.renderer import Renderer
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


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
