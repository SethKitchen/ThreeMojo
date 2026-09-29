# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Tests for three.js's `OITPassNode`: its weight and composite, the draw
filter the renderer draws its two passes with, and a scene of panes whose
order does not matter."""

from cameras.perspective_camera import PerspectiveCamera
from core.assets import Assets
from core.object3d import Object3D
from core.scene import Scene
from geometries.box import box
from geometries.plane import plane
from materials.material import ADDITIVE, BASIC, Material
from math.vector3 import Vector3
from objects.mesh import Mesh
from postprocessing.composer import (
    OIT,
    EffectComposer,
    oit_pass,
    reads_frame_as_light,
    render_pass,
)
from postprocessing.oit import (
    OitAccumulation,
    oit_composite,
    oit_draw_count,
    oit_render,
    oit_weight,
)
from core.background import texture_background
from render.framebuffer import Color, FloatColor
from render.rasterizer import RasterVertex
from render.texture import data_texture
from render.target import FLOAT_TARGET, RenderTarget
from renderers.draw_filter import (
    ALL_DRAWS,
    DrawFilter,
    NO_OIT_DRAWS,
    ONE_OIT_DRAW,
    check_draw_filter,
    kept_draws,
    oit_capable,
    snap_to_pixels,
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


comptime SIZE = 16


def test_the_weight_is_three_js_s() raises:
    # Near the camera the weight is held at 3000; at 200 m it is 0.03 over
    # one; far past that it is held at a hundredth.
    assert_almost_equal(oit_weight(1, 0), 3000, atol=1e-2)
    assert_almost_equal(oit_weight(0.5, 200), 0.5 * 0.03 / 1.00001, atol=1e-7)
    assert_almost_equal(oit_weight(1, 2000), 0.01, atol=1e-7)


def test_one_layer_is_normal_blending() raises:
    var sums = OitAccumulation(1)
    assert_equal(sums.revealage[0], 1)
    sums.add(0, FloatColor(0.8 * 0.5, 0, 0, 0.5), 3)
    var out = oit_composite(
        FloatColor(0, 0, 1, 1), sums.accum[0], sums.revealage[0]
    )
    assert_almost_equal(out.r, 0.4, atol=1e-5)
    assert_almost_equal(out.b, 0.5, atol=1e-5)
    assert_almost_equal(out.a, 1, atol=1e-6)
    # Nothing accumulated leaves the frame as it was.
    var none = OitAccumulation(1)
    var kept = oit_composite(FloatColor(0.3, 0.2, 0.1, 1), none.accum[0], 1)
    assert_almost_equal(kept.r, 0.3, atol=1e-6)


def test_the_order_does_not_matter() raises:
    var red = FloatColor(0.5, 0, 0, 0.5)
    var blue = FloatColor(0, 0, 0.25, 0.25)
    var first = OitAccumulation(1)
    first.add(0, red, 2)
    first.add(0, blue, 5)
    var second = OitAccumulation(1)
    second.add(0, blue, 5)
    second.add(0, red, 2)
    var a = oit_composite(
        FloatColor(0, 1, 0, 1), first.accum[0], first.revealage[0]
    )
    var b = oit_composite(
        FloatColor(0, 1, 0, 1), second.accum[0], second.revealage[0]
    )
    assert_almost_equal(a.r, b.r, atol=1e-6)
    assert_almost_equal(a.g, b.g, atol=1e-6)
    assert_almost_equal(a.b, b.b, atol=1e-6)
    assert_almost_equal(a.g, 0.5 * 0.75, atol=1e-6)


def test_the_draw_filter_keeps_the_right_draws() raises:
    var capable: List[Bool] = [False, True, False, True]
    var all = kept_draws(capable, ALL_DRAWS, 0)
    assert_true(all[0] and all[1] and all[2] and all[3])
    var opaque = kept_draws(capable, NO_OIT_DRAWS, 0)
    assert_true(opaque[0] and not opaque[1] and opaque[2] and not opaque[3])
    var second = kept_draws(capable, ONE_OIT_DRAW, 1)
    assert_true(not second[0] and not second[1] and not second[2] and second[3])
    assert_equal(len(kept_draws(List[Bool](), NO_OIT_DRAWS, 0)), 0)
    check_draw_filter(ALL_DRAWS, 0)
    assert_false(DrawFilter(3).is_valid())
    assert_false(DrawFilter(-1).is_valid())
    with assert_raises(contains="one of the three"):
        check_draw_filter(DrawFilter(3), 0)
    with assert_raises(contains="negative"):
        check_draw_filter(ONE_OIT_DRAW, -1)


def test_a_capable_material_is_transparent_normal_and_clear() raises:
    var glass = Material(
        Color(255, 0, 0), kind=BASIC, transparent=True, opacity=0.5
    )
    assert_true(oit_capable(glass))
    assert_false(oit_capable(Material(Color(255, 0, 0), kind=BASIC)))
    var added = Material(
        Color(255, 0, 0), kind=BASIC, transparent=True, blending=ADDITIVE
    )
    assert_false(oit_capable(added))
    var thick = glass
    thick.transmission = 0.5
    assert_false(oit_capable(thick))


def a_camera() raises -> PerspectiveCamera:
    """Return a camera four meters back from the origin."""
    var camera = PerspectiveCamera(
        Angle(50.0, DEGREE), 1, Length(0.1, METER), Length(50.0, METER)
    )
    camera.place(Vector3(0, 0, 4), Vector3(0, 0, 0))
    return camera^


def pane(
    mut assets: Assets, mut scene: Scene, color: Color, x: Float32, z: Float32
) raises:
    """Add a transparent square at half opacity."""
    var node = Object3D()
    node.set_position(x, 0, z)
    scene.add_mesh(
        Mesh(
            assets.geometries.add(
                plane(Length(1.2, METER), Length(1.2, METER))
            ),
            assets.materials.add(
                Material(color, kind=BASIC, transparent=True, opacity=0.5)
            ),
            scene.add(node^),
        )
    )


def a_scene(mut assets: Assets) raises -> Scene:
    """Return a gray box, a red pane in front of it, a blue pane in front of
    that, overlapping, and a green pane hidden behind the box."""
    var scene = Scene()
    var back = Object3D()
    back.set_position(0.6, 0, -1)
    scene.add_mesh(
        Mesh(
            assets.geometries.add(
                box(Length(1.0, METER), Length(1.0, METER), Length(0.2, METER))
            ),
            assets.materials.add(Material(Color(128, 128, 128), kind=BASIC)),
            scene.add(back^),
        )
    )
    pane(assets, scene, Color(255, 0, 0), -0.3, 0)
    pane(assets, scene, Color(0, 0, 255), 0.3, 0.5)
    pane(assets, scene, Color(0, 255, 0), 0.6, -2)
    scene.update()
    return scene^


def test_the_pass_weighs_the_panes() raises:
    var assets = Assets()
    var scene = a_scene(assets)
    var camera = a_camera()
    var renderer = Renderer(SIZE, SIZE)
    renderer.set_background(Color(0, 0, 0))
    assert_equal(oit_draw_count(renderer, scene, assets, camera), 3)
    var frame = RenderTarget(SIZE, SIZE, Color(0, 0, 0), FLOAT_TARGET)
    oit_render(frame, renderer, scene, assets, camera)
    # Where the red and blue panes overlap, both show.
    var both = frame.color_at(SIZE // 2, SIZE // 2)
    assert_true(both.r > 0.05 and both.b > 0.05)
    # The green pane is behind the box, so the box shows no green over it.
    var covered = frame.color_at(SIZE * 3 // 4, SIZE // 2)
    assert_true(covered.g < covered.r + 0.2)
    # Nothing transparent in a corner: the background.
    assert_almost_equal(frame.color_at(0, 0).r, 0, atol=1e-5)
    # A texture background is painted under the first draw alone.
    var backed = a_scene(assets)
    backed.background = texture_background(
        assets.textures.add(data_texture(1, 1, [0.0, 1.0, 0.0, 1.0]))
    )
    var painted = RenderTarget(SIZE, SIZE, Color(0, 0, 0), FLOAT_TARGET)
    oit_render(painted, renderer, backed, assets, camera)
    assert_true(painted.color_at(0, 0).g > 0.9)
    # An empty scene weighs nothing.
    var empty = RenderTarget(SIZE, SIZE, Color(0, 0, 0), FLOAT_TARGET)
    oit_render(empty, renderer, Scene(), Assets(), camera)
    assert_almost_equal(empty.color_at(4, 4).g, 0, atol=1e-6)


def test_the_composer_runs_the_pass() raises:
    var assets = Assets()
    var scene = a_scene(assets)
    var composer = EffectComposer()
    composer.add_pass(oit_pass())
    assert_true(composer.passes[0].kind == OIT)
    assert_false(reads_frame_as_light(OIT))
    var image = composer.render(Renderer(SIZE, SIZE), scene, assets, a_camera())
    assert_equal(image.width, SIZE)


def test_a_renderer_refuses_a_bad_filter() raises:
    var assets = Assets()
    var scene = a_scene(assets)
    var renderer = Renderer(4, 4)
    renderer.draw_filter = DrawFilter(5)
    var target = RenderTarget(4, 4, Color(0, 0, 0))
    with assert_raises(contains="draw filter"):
        renderer.render_into(target, scene, assets, a_camera())
    renderer.draw_filter = ONE_OIT_DRAW
    renderer.oit_draw = -2
    with assert_raises(contains="negative"):
        renderer.render_into(target, scene, assets, a_camera())


def test_the_snap_rounds_to_whole_pixels_from_the_center() raises:
    var assets = Assets()
    var scene = a_scene(assets)
    var renderer = Renderer(10, 6)
    var frame = renderer.prepare_frame(scene, assets, a_camera())
    # The frame's own slim corners, and the same corners whole.
    var corners = frame.corners.copy()
    snap_to_pixels(corners, 10, 6)
    var whole = frame.whole_corners()
    snap_to_pixels(whole, 10, 6)
    for at in range(len(corners)):
        var x = corners[at].x - 5
        var y = corners[at].y - 3
        assert_equal(x, Float32(Int(x)))
        assert_equal(y, Float32(Int(y)))
        assert_true(abs(corners[at].x - frame.corners[at].x) <= 0.5)
        assert_equal(whole[at].x, corners[at].x)
        assert_equal(whole[at].y, corners[at].y)
    var none = List[RasterVertex]()
    snap_to_pixels(none, 10, 6)
    assert_equal(len(none), 0)
    # A renderer that snaps draws the same scene.
    renderer.snap_vertices = True
    var target = RenderTarget(10, 6, Color(0, 0, 0))
    renderer.render_into(target, scene, assets, a_camera())


def test_a_resized_renderer_keeps_the_settings() raises:
    var renderer = Renderer(8, 8)
    renderer.set_background(Color(1, 2, 3))
    var small = renderer.resized(4, 2)
    assert_equal(small.width, 4)
    assert_equal(small.height, 2)
    assert_equal(small.background.b, 3)
    assert_true(small.draw_filter == ALL_DRAWS)
    assert_false(small.snap_vertices)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
