# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Tests for `objects.clipping_group`, the scene's clipping groups, and the
renderer's cut by them."""

from cameras.perspective_camera import PerspectiveCamera
from core.assets import Assets
from core.buffer_attribute import BufferAttribute
from core.buffer_geometry import BufferGeometry, POSITION
from core.object3d import NodeId, Object3D
from core.scene import Scene
from geometries.plane import plane
from lights.light import ambient_light, directional_light
from materials.material import (
    BASIC,
    Material,
    line_material,
    points_material,
    sprite_material,
)
from math.bounds import Plane
from math.vector3 import Vector3
from objects.clipping_group import Clipping, ClippingGroup
from objects.group import group
from objects.line import Line, SEGMENTS
from objects.line_segments2 import LineSegments2, line_segments_geometry
from objects.mesh import Mesh
from objects.points import Points
from objects.sprite import Sprite
from render.framebuffer import Color, Framebuffer
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


def keep_right() raises -> Plane:
    """Return the plane that keeps x > 0."""
    return Plane(Vector3(1, 0, 0), 0)


def keep_up() raises -> Plane:
    """Return the plane that keeps y > 0."""
    return Plane(Vector3(0, 1, 0), 0)


def test_a_group_holds_threes_defaults() raises:
    var holder = ClippingGroup(NodeId(2))
    assert_equal(holder.node, NodeId(2))
    assert_equal(len(holder.clipping_planes), 0)
    assert_true(holder.enabled)
    assert_false(holder.clip_intersection)
    assert_false(holder.clip_shadows)
    with assert_raises(contains="scene node"):
        _ = ClippingGroup(NodeId(-1))


def test_a_context_adds_a_groups_planes_by_its_rule() raises:
    var context = Clipping()
    assert_true(context.is_empty())
    context.add_group(ClippingGroup(NodeId(0), [keep_right()]), False)
    assert_equal(len(context.union_planes), 1)
    assert_false(context.is_empty())
    context.add_group(
        ClippingGroup(NodeId(1), [keep_up()], clip_intersection=True), False
    )
    assert_equal(len(context.intersection_planes), 1)
    var only_intersection = Clipping()
    only_intersection.add_group(
        ClippingGroup(NodeId(1), [keep_up()], clip_intersection=True), False
    )
    assert_false(only_intersection.is_empty())
    # A disabled group, and a group without `clip_shadows` in a shadow
    # pass, add nothing.
    var quiet = Clipping()
    quiet.add_group(
        ClippingGroup(NodeId(0), [keep_right()], enabled=False), False
    )
    quiet.add_group(ClippingGroup(NodeId(0), [keep_right()]), True)
    assert_true(quiet.is_empty())
    quiet.add_group(
        ClippingGroup(NodeId(0), [keep_right()], clip_shadows=True), True
    )
    assert_equal(len(quiet.union_planes), 1)


def test_the_scene_gathers_the_groups_above_a_node_outer_first() raises:
    var scene = Scene()
    var outer = scene.add(group())
    var inner = scene.attach(group(), outer)
    var leaf = scene.attach(Object3D(), inner)
    var aside = scene.add(Object3D())
    assert_true(scene.clipping(leaf, False).is_empty())
    scene.add_clipping_group(ClippingGroup(outer, [keep_right()]))
    scene.add_clipping_group(
        ClippingGroup(inner, [keep_up(), keep_right()], clip_intersection=True)
    )
    var found = scene.clipping(leaf, False)
    assert_equal(len(found.union_planes), 1)
    assert_equal(len(found.intersection_planes), 2)
    assert_almost_equal(found.intersection_planes[0].normal.y, 1)
    # The group's own node is cut by it; a node beside it is not.
    assert_equal(len(scene.clipping(inner, False).intersection_planes), 2)
    assert_true(scene.clipping(aside, False).is_empty())
    # Outer first: an outer group's union planes come before an inner's.
    var deep = scene.attach(group(), leaf)
    var below = scene.attach(Object3D(), deep)
    scene.add_clipping_group(ClippingGroup(deep, [keep_up()]))
    var stacked = scene.clipping(below, False)
    assert_almost_equal(stacked.union_planes[0].normal.x, 1)
    assert_almost_equal(stacked.union_planes[1].normal.y, 1)
    with assert_raises():
        _ = scene.clipping(NodeId(99), False)


def test_the_scene_refuses_a_group_it_cannot_hold() raises:
    var scene = Scene()
    var node = scene.add(group())
    with assert_raises(contains="in the scene"):
        scene.add_clipping_group(ClippingGroup(NodeId(5)))
    scene.add_clipping_group(ClippingGroup(node))
    with assert_raises(contains="one clipping group"):
        scene.add_clipping_group(ClippingGroup(node))


def test_a_clone_carries_its_clipping_group() raises:
    var scene = Scene()
    var held = scene.add(group())
    var other = scene.add(group())
    scene.add_clipping_group(ClippingGroup(other, [keep_up()]))
    scene.add_clipping_group(ClippingGroup(held, [keep_right()]))
    var copy = scene.clone(held)
    assert_equal(len(scene.clipping_groups), 3)
    assert_equal(scene.clipping_groups[2].node, copy)
    assert_almost_equal(scene.clipping_groups[2].clipping_planes[0].normal.x, 1)


def camera() raises -> PerspectiveCamera:
    """Return a camera looking at the origin from +z."""
    var eye = PerspectiveCamera(
        Angle(45.0, DEGREE), 1.0, Length(0.1, METER), Length(100.0, METER)
    )
    eye.place(Vector3(0, 0, 3), Vector3(0, 0, 0))
    return eye^


def lit(image: Framebuffer, x: Int, y: Int) raises -> Bool:
    """Return whether a pixel is red: drawn rather than background."""
    return image.get_pixel(x, y).r > 200


def quad_under(
    mut assets: Assets, mut scene: Scene, var holder: ClippingGroup
) raises:
    """Put a red quad filling the view under a clipping group's node.

    Args:
        assets: The stores.
        scene: The scene, which holds the group's node.
        holder: The group.

    Raises:
        Error: If the scene refuses it.
    """
    var node = scene.attach(Object3D(), holder.node)
    scene.add_clipping_group(holder^)
    scene.add_light(ambient_light(Color(255, 255, 255), 1.0))
    var quad = assets.geometries.add(
        plane(Length(4.0, METER), Length(4.0, METER))
    )
    var red = assets.materials.add(Material(Color(255, 0, 0), kind=BASIC))
    scene.add_mesh(Mesh(quad, red, node))
    scene.update()


def test_a_groups_planes_cut_the_meshes_under_it() raises:
    var assets = Assets()
    var scene = Scene()
    var holder = scene.add(group())
    quad_under(assets, scene, ClippingGroup(holder, [keep_right()]))
    var renderer = Renderer(SIZE, SIZE)
    # No `local_clipping_enabled`: a group cuts without it, as three.js's.
    var half = renderer.render(scene, assets, camera())
    assert_false(lit(half, 2, 8))
    assert_true(lit(half, 13, 8))
    # With the renderer's own planes as well: both cut.
    renderer.clipping_planes = [keep_up()]
    var quarter = renderer.render(scene, assets, camera())
    assert_true(lit(quarter, 13, 2))
    assert_false(lit(quarter, 13, 13))
    # Turned off, it cuts nothing.
    scene.clipping_groups[0].enabled = False
    renderer.clipping_planes = List[Plane]()
    var whole = renderer.render(scene, assets, camera())
    assert_true(lit(whole, 2, 8))


def test_a_groups_intersection_keeps_what_is_in_front_of_any_plane() raises:
    var assets = Assets()
    var scene = Scene()
    var holder = scene.add(group())
    quad_under(
        assets,
        scene,
        ClippingGroup(
            holder, [keep_right(), keep_up()], clip_intersection=True
        ),
    )
    var image = Renderer(SIZE, SIZE).render(scene, assets, camera())
    # Cut only in the lower left, behind both planes.
    assert_false(lit(image, 2, 13))
    assert_true(lit(image, 2, 2))
    assert_true(lit(image, 13, 13))


def segment() raises -> BufferGeometry:
    """Return a horizontal segment across the view."""
    var geometry = BufferGeometry()
    geometry.set_attribute(
        POSITION, BufferAttribute([Float32(-2), 0, 0, 2, 0, 0], 3)
    )
    return geometry^


def test_lines_points_sprites_and_wide_lines_under_a_group_are_cut() raises:
    var assets = Assets()
    var scene = Scene()
    var holder = scene.add(group())
    var node = scene.attach(Object3D(), holder)
    scene.add_clipping_group(
        ClippingGroup(holder, [Plane(Vector3(-1, 0, 0), 0)])
    )
    var stick = assets.geometries.add(segment())
    var red = Color(255, 0, 0)
    var plain = assets.materials.add(Material(red, kind=BASIC))
    scene.add_line(Line(stick, plain, node, mode=SEGMENTS))
    var dots = assets.materials.add(points_material(red))
    scene.add_points(Points(stick, dots, node))
    scene.add_sprite(Sprite(assets.materials.add(sprite_material(red)), node))
    var wide = assets.geometries.add(
        line_segments_geometry([Vector3(-2, 1, 0), Vector3(2, 1, 0)])
    )
    scene.add_wide_line(
        LineSegments2(wide, assets.materials.add(line_material(red)), node)
    )
    scene.update()
    var image = Renderer(SIZE, SIZE).render(scene, assets, camera())
    # The sprite covers the middle; its right half is cut.
    assert_true(lit(image, 7, 8))
    assert_false(lit(image, 9, 8))
    # The line's right end is gone, and so is the wide line's.
    assert_false(lit(image, 14, 8))
    var left_wide = 0
    var right_wide = 0
    for y in range(SIZE // 2):
        if lit(image, 2, y):
            left_wide += 1
        if lit(image, 13, y):
            right_wide += 1
    assert_true(left_wide > 0)
    assert_equal(right_wide, 0)


def test_a_group_cuts_a_shadow_only_with_clip_shadows() raises:
    var assets = Assets()
    var scene = Scene()
    var holder = scene.add(group())
    var node = scene.attach(Object3D(), holder)
    var lamp = scene.add(Object3D())
    scene.node(lamp).set_position(0, 0, 5)
    var sun = directional_light(Color(255, 255, 255), lamp, 1.0)
    sun.cast_shadow = True
    scene.add_light(sun)
    var quad = assets.geometries.add(
        plane(Length(2.0, METER), Length(2.0, METER))
    )
    var gray = assets.materials.add(Material(Color(200, 200, 200)))
    var mesh = Mesh(quad, gray, node)
    mesh.cast_shadow = True
    scene.add_mesh(mesh)
    scene.add_clipping_group(ClippingGroup(holder, [keep_right()]))
    scene.update()
    var renderer = Renderer(SIZE, SIZE)
    var whole = renderer.shadow_maps(scene, assets)[0].depths.copy()
    scene.clipping_groups[0].clip_shadows = True
    var cut = renderer.shadow_maps(scene, assets)[0].depths.copy()
    var differ = 0
    for index in range(len(whole)):
        if whole[index] != cut[index]:
            differ += 1
    assert_true(differ > 0)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
