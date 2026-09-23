# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Tests for clipping planes: the renderer's, and each material's own."""

from cameras.perspective_camera import PerspectiveCamera
from core.assets import Assets
from core.buffer_attribute import BufferAttribute
from core.buffer_geometry import BufferGeometry, POSITION
from core.object3d import Object3D
from core.scene import Scene
from geometries.plane import plane
from lights.light import ambient_light, directional_light
from materials.material import (
    BASIC,
    MAX_CLIPPING_PLANES,
    Material,
    points_material,
    sprite_material,
)
from math.bounds import Plane
from math.vector3 import Vector3
from objects.line import Line, SEGMENTS
from objects.mesh import Mesh
from objects.points import Points
from objects.sprite import Sprite
from render.framebuffer import Color, FloatColor, Framebuffer
from renderers.clip import (
    ClipVertex,
    clip_depth,
    clip_segment,
    flipped,
    within_any,
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


def _corner(x: Float32, y: Float32) -> ClipVertex:
    """Return a bare corner at z = -1 in camera space."""
    return ClipVertex(
        Vector3(x, y, -1),
        FloatColor(1.0, 1.0, 1.0),
        Vector3(0, 0, 1),
        0,
        0,
        Vector3(x, y, -1),
    )


def _area(triangles: List[ClipVertex]) -> Float32:
    """Return the total area of triangles in the xy plane."""
    var total = Float32(0)
    for index in range(len(triangles) // 3):
        var a = triangles[index * 3].position
        var b = triangles[index * 3 + 1].position
        var c = triangles[index * 3 + 2].position
        total += abs((b.x - a.x) * (c.y - a.y) - (c.x - a.x) * (b.y - a.y)) / 2
    return total


def test_a_point_is_kept_in_front_of_any_plane() raises:
    var right = Plane(Vector3(1, 0, 0), 0)
    var up = Plane(Vector3(0, 1, 0), 0)
    assert_true(within_any(Vector3(-1, -1, 0), List[Plane]()))
    assert_true(within_any(Vector3(-1, 1, 0), [right, up]))
    assert_false(within_any(Vector3(-1, -1, 0), [right, up]))
    assert_almost_equal(flipped(right).normal.x, Float32(-1))


def test_a_triangle_cut_by_the_union_of_two_half_planes() raises:
    # A square from -1 to 1, as two triangles, kept where x > 0 or y > 0:
    # three quarters of it.
    var right = Plane(Vector3(1, 0, 0), 0)
    var up = Plane(Vector3(0, 1, 0), 0)
    var total = Float32(0)
    total += _area(
        clip_depth(
            _corner(-1, -1),
            _corner(1, -1),
            _corner(1, 1),
            0.1,
            10,
            List[Plane](),
            [right, up],
        )
    )
    total += _area(
        clip_depth(
            _corner(-1, -1),
            _corner(1, 1),
            _corner(-1, 1),
            0.1,
            10,
            List[Plane](),
            [right, up],
        )
    )
    assert_almost_equal(total, Float32(3), atol=1e-5)


def test_a_segment_cut_by_the_union_of_two_half_planes() raises:
    # From x = -3 to 3, kept where x > 1 or x < -1: two pieces.
    var beyond = Plane(Vector3(1, 0, 0), -1)
    var before = Plane(Vector3(-1, 0, 0), -1)
    var kept = clip_segment(
        _corner(-3, 0), _corner(3, 0), 0.1, 10, List[Plane](), [beyond, before]
    )
    assert_equal(len(kept), 4)
    assert_almost_equal(kept[0].position.x, Float32(1), atol=1e-5)
    assert_almost_equal(kept[3].position.x, Float32(-1), atol=1e-5)
    # Wholly behind both.
    var none = clip_segment(
        _corner(-0.5, 0),
        _corner(0.5, 0),
        0.1,
        10,
        List[Plane](),
        [beyond, before],
    )
    assert_equal(len(none), 0)
    # A cut against a side, then nothing more.
    var one = clip_segment(
        _corner(-3, 0), _corner(3, 0), 0.1, 10, [beyond], List[Plane]()
    )
    assert_equal(len(one), 2)


def test_a_material_holds_at_most_eight_planes() raises:
    var material = Material(Color(255, 0, 0))
    var planes = List[Plane]()
    for index in range(MAX_CLIPPING_PLANES + 1):
        planes.append(Plane(Vector3(1, 0, 0), Float32(index)))
    with assert_raises(contains="at most"):
        material.set_clipping_planes(planes)
    _ = planes.pop()
    material.set_clipping_planes(planes, intersection=True, shadows=True)
    assert_equal(material.clip_plane_count, MAX_CLIPPING_PLANES)
    assert_true(material.clip_intersection)
    assert_true(material.clip_shadows)
    var back = material.clipping_planes()
    assert_almost_equal(back[3].constant, Float32(3))
    material.set_clipping_planes(List[Plane]())
    assert_equal(len(material.clipping_planes()), 0)


def _camera() raises -> PerspectiveCamera:
    """Return a camera looking at the origin from +z.

    Returns:
        The camera.

    Raises:
        Error: If its parameters are invalid.
    """
    var camera = PerspectiveCamera(
        Angle(45.0, DEGREE), 1.0, Length(0.1, METER), Length(100.0, METER)
    )
    camera.place(Vector3(0, 0, 3), Vector3(0, 0, 0))
    return camera^


def _lit(image: Framebuffer, x: Int, y: Int) raises -> Bool:
    """Return whether a pixel is red: drawn rather than background."""
    return image.get_pixel(x, y).r > 200


def _quad_scene(
    mut assets: Assets, mut scene: Scene, material: Material
) raises:
    """Put a red quad filling the view at the origin.

    Args:
        assets: The stores.
        scene: The scene.
        material: The quad's material.

    Raises:
        Error: If the scene refuses it.
    """
    var node = scene.add(Object3D())
    scene.add_light(ambient_light(Color(255, 255, 255), 1.0))
    var quad = assets.geometries.add(
        plane(Length(4.0, METER), Length(4.0, METER))
    )
    scene.add_mesh(Mesh(quad, assets.materials.add(material), node))
    scene.update()


def test_the_renderers_planes_cut_every_mesh() raises:
    var assets = Assets()
    var scene = Scene()
    _quad_scene(assets, scene, Material(Color(255, 0, 0), kind=BASIC))
    var renderer = Renderer(SIZE, SIZE)
    var whole = renderer.render(scene, assets, _camera())
    assert_true(_lit(whole, 2, 8))
    assert_true(_lit(whole, 13, 8))
    # Keep x > 0: the right half.
    renderer.clipping_planes = [Plane(Vector3(1, 0, 0), 0)]
    var half = renderer.render(scene, assets, _camera())
    assert_false(_lit(half, 2, 8))
    assert_true(_lit(half, 13, 8))


def test_a_materials_planes_need_local_clipping() raises:
    var assets = Assets()
    var scene = Scene()
    var material = Material(Color(255, 0, 0), kind=BASIC)
    material.set_clipping_planes(
        [Plane(Vector3(1, 0, 0), 0), Plane(Vector3(0, 1, 0), 0)]
    )
    _quad_scene(assets, scene, material)
    var renderer = Renderer(SIZE, SIZE)
    # Off by default, as in three.js: the planes are ignored.
    assert_true(_lit(renderer.render(scene, assets, _camera()), 2, 2))
    renderer.local_clipping_enabled = True
    # The union: kept only where x > 0 and y > 0, the upper right.
    var union = renderer.render(scene, assets, _camera())
    assert_true(_lit(union, 13, 2))
    assert_false(_lit(union, 2, 2))
    assert_false(_lit(union, 13, 13))


def test_clip_intersection_keeps_what_is_in_front_of_any_plane() raises:
    var assets = Assets()
    var scene = Scene()
    var material = Material(Color(255, 0, 0), kind=BASIC)
    material.set_clipping_planes(
        [Plane(Vector3(1, 0, 0), 0), Plane(Vector3(0, 1, 0), 0)],
        intersection=True,
    )
    _quad_scene(assets, scene, material)
    var renderer = Renderer(SIZE, SIZE)
    renderer.local_clipping_enabled = True
    var image = renderer.render(scene, assets, _camera())
    # Cut only in the lower left, behind both planes.
    assert_false(_lit(image, 2, 13))
    assert_true(_lit(image, 2, 2))
    assert_true(_lit(image, 13, 13))
    assert_true(_lit(image, 13, 2))


def _segment() raises -> BufferGeometry:
    """Return a horizontal segment across the view.

    Returns:
        The geometry.

    Raises:
        Error: If the attribute is refused.
    """
    var geometry = BufferGeometry()
    geometry.set_attribute(
        POSITION, BufferAttribute([Float32(-2), 0, 0, 2, 0, 0], 3)
    )
    return geometry^


def test_lines_points_and_sprites_are_cut_too() raises:
    var assets = Assets()
    var scene = Scene()
    var node = scene.add(Object3D())
    scene.add_light(ambient_light(Color(255, 255, 255), 1.0))
    var segment = assets.geometries.add(_segment())
    var keep_left: List[Plane] = [Plane(Vector3(-1, 0, 0), 0)]
    var line_material = Material(Color(255, 0, 0), kind=BASIC)
    line_material.set_clipping_planes(keep_left)
    scene.add_line(
        Line(
            segment,
            assets.materials.add(line_material),
            node,
            mode=SEGMENTS,
        )
    )
    var dots = points_material(Color(255, 0, 0))
    dots.set_clipping_planes(keep_left, intersection=True)
    scene.add_points(Points(segment, assets.materials.add(dots), node))
    var card = sprite_material(Color(255, 0, 0))
    card.set_clipping_planes(keep_left)
    scene.add_sprite(Sprite(assets.materials.add(card), node))
    scene.update()
    var renderer = Renderer(SIZE, SIZE)
    renderer.local_clipping_enabled = True
    var image = renderer.render(scene, assets, _camera())
    # The sprite covers the middle; its right half is cut.
    assert_true(_lit(image, 7, 8))
    assert_false(_lit(image, 9, 8))
    # The line's right end is gone as well.
    assert_false(_lit(image, 14, 8))


def test_a_point_in_view_behind_every_plane_is_cut() raises:
    # Two points half a meter either side of the middle, both in view:
    # under `clip_intersection` with one plane, only the left is kept.
    var assets = Assets()
    var scene = Scene()
    var node = scene.add(Object3D())
    var geometry = BufferGeometry()
    geometry.set_attribute(
        POSITION, BufferAttribute([Float32(-0.5), 0, 0, 0.5, 0, 0], 3)
    )
    var pair = assets.geometries.add(geometry^)
    var dots = points_material(Color(255, 0, 0))
    dots.set_clipping_planes([Plane(Vector3(-1, 0, 0), 0)], intersection=True)
    scene.add_points(Points(pair, assets.materials.add(dots), node))
    scene.update()
    var renderer = Renderer(SIZE, SIZE)
    renderer.local_clipping_enabled = True
    var image = renderer.render(scene, assets, _camera())
    var left = 0
    var right = 0
    for y in range(SIZE):
        for x in range(SIZE):
            if _lit(image, x, y):
                if x < SIZE // 2:
                    left += 1
                else:
                    right += 1
    assert_true(left > 0)
    assert_equal(right, 0)


def test_a_materials_planes_cut_its_shadow_only_when_asked() raises:
    var assets = Assets()
    var scene = Scene()
    var node = scene.add(Object3D())
    var lamp = scene.add(Object3D())
    scene.node(lamp).set_position(0, 0, 5)
    var sun = directional_light(Color(255, 255, 255), lamp, 1.0)
    sun.cast_shadow = True
    scene.add_light(sun)
    var quad = assets.geometries.add(
        plane(Length(2.0, METER), Length(2.0, METER))
    )
    var material = Material(Color(200, 200, 200))
    material.set_clipping_planes([Plane(Vector3(1, 0, 0), 0)])
    var id = assets.materials.add(material)
    var mesh = Mesh(quad, id, node)
    mesh.cast_shadow = True
    scene.add_mesh(mesh)
    scene.update()
    var renderer = Renderer(SIZE, SIZE)
    renderer.local_clipping_enabled = True
    # Renderer planes never cut a shadow.
    renderer.clipping_planes = [Plane(Vector3(0, 1, 0), 0)]
    var whole = renderer.shadow_maps(scene, assets)[0].depths.copy()
    var shadows = material
    shadows.set_clipping_planes([Plane(Vector3(1, 0, 0), 0)], shadows=True)
    scene.meshes[0].material = assets.materials.add(shadows)
    var cut = renderer.shadow_maps(scene, assets)[0].depths.copy()
    var differ = 0
    for index in range(len(whole)):
        if whole[index] != cut[index]:
            differ += 1
    assert_true(differ > 0)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
