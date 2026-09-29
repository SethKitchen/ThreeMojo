# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0

"""Regressions for shared surfaces, mutable probes, and splat passes."""

from core.assets import Assets
from core.object3d import Object3D
from core.scene import Scene
from geometries.box import box
from geometries.plane import plane
from lights.lighting import Lighting
from materials.material import Material, DOUBLE_SIDE, PHYSICAL
from math.vector2 import Vector2
from math.vector3 import Vector3
from objects.mesh import Mesh
from postprocessing.oit import oit_draw_count, oit_render
from render.framebuffer import Color, FloatColor
from render.rasterizer import (
    Corner,
    Surface,
    RasterVertex,
    Draw,
    DRAW_TRIANGLES,
    rasterize_frame,
    rasterize_shaded,
    corner_of,
    surface_of,
    joined,
)
from render.target import RenderTarget, FLOAT_TARGET
from render.texture_store import TextureId
from renderers.renderer import Renderer, _Slim, _turned_around, _opaque_draws
from std.testing import (
    TestSuite,
    assert_equal,
    assert_almost_equal,
    assert_true,
    assert_raises,
)
from test_audit_followup import camera
from test_gaussian_splat import one_red_splat
from test_rasterizer import phong_corner, lit_along_z_from
from units.si import Length, METER


def test_surface_cache_keeps_both_facings_and_reuses_each() raises:
    var front = RasterVertex(0, 0, 0.5, 1, FloatColor(1, 1, 1))
    front.normal_scale = Vector2(2, 3)
    front.bump_scale = 4
    front.layers.anisotropy = Vector2(0.4, 0.6)
    front.layers.clearcoat_normal_map = TextureId(0)
    front.layers.clearcoat_normal_scale = Vector2(5, 6)
    var back = _turned_around(front)
    for reverse in range(2):
        var slim = _Slim()
        slim.new_surface()
        for triangle in range(4):
            slim.turned = (triangle + reverse) % 2 != 0
            for _ in range(3):
                slim.append(back if slim.turned else front)
        assert_equal(len(slim.surfaces), 2)
        var whole = slim.whole()
        for triangle in range(4):
            var expected = back if (triangle + reverse) % 2 != 0 else front
            for corner in range(3):
                ref actual = whole[triangle * 3 + corner]
                assert_equal(actual.normal_scale.x, expected.normal_scale.x)
                assert_equal(actual.normal_scale.y, expected.normal_scale.y)
                assert_equal(actual.bump_scale, expected.bump_scale)
                assert_equal(
                    actual.layers.anisotropy.x, expected.layers.anisotropy.x
                )
                assert_equal(
                    actual.layers.clearcoat_normal_scale.y,
                    expected.layers.clearcoat_normal_scale.y,
                )
                assert_equal(
                    actual.frames.object_normal, expected.frames.object_normal
                )
        slim.new_surface()
        for _ in range(3):
            slim.append(front)
        assert_equal(len(slim.surfaces), 3)


def test_renderer_selects_surface_for_each_face_in_one_draw() raises:
    var scene = Scene()
    var assets = Assets()
    var node = scene.add(Object3D())
    var geometry = assets.geometries.add(
        box(Length(2, METER), Length(2, METER), Length(2, METER))
    )
    # The constructor ties each scale to its map, and refuses both maps at
    # once; the corners only carry the scales, so set them afterward.
    var surface = Material(
        Color(255, 255, 255), kind=PHYSICAL, side=DOUBLE_SIDE
    )
    surface.normal_scale = Vector2(2, 3)
    surface.bump_scale = 4
    var material = assets.materials.add(surface^)
    scene.add_mesh(Mesh(geometry, material, node))
    scene.update()
    var frame = Renderer(16, 16).prepare_frame(scene, assets, camera())
    var whole = frame.whole_corners()
    var fronts = 0
    var backs = 0
    for triangle in range(len(whole) // 3):
        var away = whole[triangle * 3].seen_from_behind
        if away:
            backs += 1
        else:
            fronts += 1
        for corner in range(3):
            ref vertex = whole[triangle * 3 + corner]
            assert_equal(vertex.normal_scale.x, Float32(-2 if away else 2))
            assert_equal(vertex.bump_scale, Float32(-4 if away else 4))
    assert_true(fronts > 0 and backs > 0)
    assert_equal(len(frame.surfaces), 2)


def test_slim_draw_ranges_raise_before_reading_corners() raises:
    var bad: List[Draw] = [
        Draw(DRAW_TRIANGLES, 0, 1),
        Draw(DRAW_TRIANGLES, -1, 1),
        Draw(DRAW_TRIANGLES, 0, -1),
        Draw(DRAW_TRIANGLES, 9223372036854775807, 1),
        Draw(DRAW_TRIANGLES, 1, 9223372036854775807),
    ]
    for workers in range(1, 3):
        for index in range(len(bad)):
            var draws: List[Draw] = [bad[index]]
            var target = RenderTarget(2, 2, Color(0, 0, 0))
            with assert_raises():
                rasterize_frame(
                    List[Corner](),
                    List[Surface](),
                    List[RasterVertex](),
                    draws,
                    target,
                    workers=workers,
                )


def test_frame_preserves_specular_interpolation() raises:
    var a = phong_corner(0, 0, FloatColor(0, 0, 0), 2, FloatColor(0, 0, 0))
    var b = phong_corner(8, 0, FloatColor(1, 1, 1), 2, FloatColor(0, 0, 0))
    var c = phong_corner(
        0, 8, FloatColor(0.5, 0.2, 0.7), 2, FloatColor(0, 0, 0)
    )
    var vertices: List[RasterVertex] = [a, b, c]
    var corners = List[Corner]()
    var surfaces: List[Surface] = [surface_of(a)]
    for index in range(3):
        corners.append(corner_of(vertices[index], 0))
        var restored = joined(corners[index], surfaces[0])
        assert_equal(restored.specular.r, vertices[index].specular.r)
        assert_equal(restored.specular.g, vertices[index].specular.g)
        assert_equal(restored.specular.b, vertices[index].specular.b)
    var lighting = lit_along_z_from(5)
    var direct = RenderTarget(8, 8, Color(0, 0, 0))
    rasterize_shaded(a, b, c, direct, lighting=lighting)
    assert_true(direct.colors[18].r > 0.1)
    var draws: List[Draw] = [Draw(DRAW_TRIANGLES, 0, 1)]
    for workers in range(1, 3):
        var whole = RenderTarget(8, 8, Color(0, 0, 0))
        var slim = RenderTarget(8, 8, Color(0, 0, 0))
        rasterize_frame(
            vertices,
            List[RasterVertex](),
            draws,
            whole,
            lighting=lighting,
            workers=workers,
        )
        rasterize_frame(
            corners,
            surfaces,
            List[RasterVertex](),
            draws,
            slim,
            lighting=lighting,
            workers=workers,
        )
        for pixel in range(64):
            assert_almost_equal(whole.colors[pixel].r, direct.colors[pixel].r)
            assert_almost_equal(slim.colors[pixel].r, direct.colors[pixel].r)
            assert_almost_equal(slim.colors[pixel].g, direct.colors[pixel].g)
            assert_almost_equal(slim.colors[pixel].b, direct.colors[pixel].b)


def test_public_probe_edits_affect_ambient_immediately() raises:
    var lighting = Lighting.uniform()
    var normal = Vector3(0, 1, 0)
    var position = Vector3(0, 0, 0)
    for value in range(2):
        lighting.probe.lanes[0] = Float32(1 - value)
        var expected = lighting.probe.get_irradiance_at(normal)
        var actual = lighting.ambient_at(normal, position)
        assert_almost_equal(actual.r, lighting.ambient.r + expected.x)


def test_splats_survive_transmission_and_oit_passes() raises:
    var scene = Scene()
    var node = scene.add(Object3D())
    scene.update()
    scene.add_gaussian_splat(one_red_splat(scene, node))
    var assets = Assets()
    var renderer = Renderer(16, 16)
    var eye = camera()
    var frame = renderer.prepare_frame(scene, assets, eye)
    assert_equal(len(_opaque_draws(frame)), 0)
    assert_equal(oit_draw_count(renderer, scene, assets, eye), 0)
    var target = RenderTarget(16, 16, Color(0, 0, 0), FLOAT_TARGET)
    oit_render(target, renderer, scene, assets, eye)
    assert_true(target.colors[8 * 16 + 8].r > 0)
    var geometry = assets.geometries.add(
        plane(Length(4, METER), Length(4, METER))
    )
    var material = assets.materials.add(
        Material(Color(255, 255, 255), kind=PHYSICAL, transmission=0.5)
    )
    var front = Object3D()
    front.set_position(0, 0, 1)
    var near = scene.add(front^)
    scene.add_mesh(Mesh(geometry, material, near))
    scene.update()
    renderer.render_into(target, scene, assets, eye)
    assert_true(target.colors[8 * 16 + 8].r > 0)
    oit_render(target, renderer, scene, assets, eye)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
