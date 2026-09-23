# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Tests for `Object3D.visible`, `name`, `render_order` and
`matrix_auto_update`, and the scene's walks over its nodes."""

from cameras.perspective_camera import PerspectiveCamera
from core.assets import Assets
from core.buffer_attribute import BufferAttribute
from core.buffer_geometry import BufferGeometry, POSITION
from core.layers import Layers
from core.object3d import NO_PARENT, NodeId, Object3D
from core.raycaster import Raycaster
from core.scene import Scene
from geometries.plane import plane
from lights.light import ambient_light, directional_light
from materials.material import (
    BASIC,
    Material,
    points_material,
    sprite_material,
)
from math.matrix4 import translation
from math.vector3 import Vector3
from objects.line import Line, SEGMENTS
from objects.mesh import Mesh
from objects.points import Points
from objects.sprite import Sprite
from render.framebuffer import Color, Framebuffer
from renderers.renderer import Renderer
from std.testing import (
    TestSuite,
    assert_equal,
    assert_false,
    assert_raises,
    assert_true,
)
from units.si import Angle, DEGREE, Length, METER

comptime SIZE = 16


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
    camera.place(Vector3(0, 0, 4), Vector3(0, 0, 0))
    return camera^


def _center(image: Framebuffer) raises -> Color:
    """Return the pixel at the middle of an image.

    Args:
        image: The image.

    Returns:
        Its middle pixel.

    Raises:
        Error: Never for an image of this size.
    """
    return image.get_pixel(SIZE // 2, SIZE // 2)


def _segment() raises -> BufferGeometry:
    """Return one horizontal segment through the origin.

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


def test_a_node_is_visible_unnamed_and_first_by_default() raises:
    var node = Object3D()
    assert_true(node.visible)
    assert_equal(node.name, "")
    assert_equal(node.render_order, 0)
    assert_true(node.matrix_auto_update)
    var copy = Object3D(copy=node)
    assert_true(copy.visible)


def test_a_hidden_parent_hides_its_children() raises:
    var scene = Scene()
    var parent = scene.add(Object3D())
    var child = scene.attach(Object3D(), parent)
    var other = scene.add(Object3D())
    scene.node(parent).visible = False
    scene.update()
    assert_false(scene.is_shown(parent))
    assert_false(scene.is_shown(child))
    assert_true(scene.is_shown(other))
    assert_false(scene.shows(child, Layers()))
    assert_true(scene.shows(other, Layers()))
    # On a layer the camera does not see.
    var none = Layers()
    none.disable_all()
    assert_false(scene.shows(other, none))
    with assert_raises(contains="out of range"):
        _ = scene.is_shown(NodeId(9))
    scene.node(other).visible = False
    with assert_raises(contains="update"):
        _ = scene.is_shown(other)


def test_a_node_is_found_by_name() raises:
    var scene = Scene()
    var first = Object3D()
    first.name = "lamp"
    _ = scene.add(first^)
    var second = Object3D()
    second.name = "lamp"
    _ = scene.add(second^)
    assert_equal(scene.find("lamp").value().value, 0)
    assert_false(Bool(scene.find("table")))


def test_children_and_descendants() raises:
    var scene = Scene()
    var root = scene.add(Object3D())
    var a = scene.attach(Object3D(), root)
    var other = scene.add(Object3D())
    var b = scene.attach(Object3D(), a)
    var c = scene.attach(Object3D(), root)
    var kids = scene.children(root)
    assert_equal(len(kids), 2)
    assert_equal(kids[0].value, a.value)
    assert_equal(kids[1].value, c.value)
    var all = scene.descendants(root)
    assert_equal(len(all), 4)
    assert_equal(all[2].value, b.value)
    assert_equal(len(scene.descendants(other)), 1)
    assert_equal(len(scene.children(b)), 0)
    with assert_raises(contains="out of range"):
        _ = scene.children(NodeId(20))
    with assert_raises(contains="out of range"):
        _ = scene.descendants(NodeId(-3))


def test_a_node_can_keep_the_matrix_it_was_given() raises:
    var scene = Scene()
    var node = Object3D()
    node.set_position(5, 0, 0)
    node.matrix_auto_update = False
    node.matrix = translation(0, 3, 0)
    var id = scene.add(node^)
    scene.update()
    var at = scene.world_position(id)
    assert_equal(at.x, 0)
    assert_equal(at.y, 3)
    # With the automatic update on, the position wins again.
    scene.node(id).matrix_auto_update = True
    scene.update()
    assert_equal(scene.world_position(id).x, 5)
    assert_equal(scene.get(id).matrix.transform_point(Vector3(0, 0, 0)).x, 5)


def test_render_order_reads_without_a_copy() raises:
    var scene = Scene()
    var node = Object3D()
    node.render_order = 3
    var id = scene.add(node^)
    assert_equal(scene.render_order(id), 3)
    with assert_raises(contains="out of range"):
        _ = scene.render_order(NodeId(4))
    with assert_raises(contains="out of range"):
        _ = scene.render_order(NodeId(-1))
    # The last node has nothing after it to be its child.
    assert_equal(len(scene.children(id)), 0)
    assert_equal(len(scene.descendants(id)), 1)
    assert_false(Bool(Scene().find("anything")))


def _flat_scene(mut assets: Assets, mut scene: Scene) raises -> NodeId:
    """Add a node lit by a white ambient light, and return it.

    Args:
        assets: Unused; kept for symmetry with the callers.
        scene: The scene.

    Returns:
        The node.

    Raises:
        Error: If the scene refuses it.
    """
    var node = scene.add(Object3D())
    scene.add_light(ambient_light(Color(255, 255, 255), 1.0))
    return node


def test_a_hidden_mesh_line_point_and_sprite_draw_nothing() raises:
    var assets = Assets()
    var scene = Scene()
    var node = _flat_scene(assets, scene)
    var quad = assets.geometries.add(
        plane(Length(2.0, METER), Length(2.0, METER))
    )
    var red = assets.materials.add(Material(Color(255, 0, 0), kind=BASIC))
    scene.add_mesh(Mesh(quad, red, node))
    var segment = assets.geometries.add(_segment())
    var green = assets.materials.add(Material(Color(0, 255, 0), kind=BASIC))
    scene.add_line(Line(segment, green, node, mode=SEGMENTS))
    var dots = assets.materials.add(points_material(Color(0, 0, 255)))
    scene.add_points(Points(segment, dots, node))
    scene.add_sprite(Sprite(assets.materials.add(sprite_material()), node))
    var renderer = Renderer(SIZE, SIZE)
    scene.update()
    var shown = renderer.render(scene, assets, _camera())
    assert_true(_center(shown).r > 0 or _center(shown).g > 0)
    scene.node(node).visible = False
    scene.update()
    var hidden = renderer.render(scene, assets, _camera())
    for y in range(SIZE):
        for x in range(SIZE):
            var pixel = hidden.get_pixel(x, y)
            assert_equal(pixel.r, renderer.background.r)
            assert_equal(pixel.g, renderer.background.g)
            assert_equal(pixel.b, renderer.background.b)


def test_a_hidden_light_does_not_shine() raises:
    var assets = Assets()
    var scene = Scene()
    var node = scene.add(Object3D())
    var lamp_node = scene.add(Object3D())
    scene.node(lamp_node).set_position(0, 0, 5)
    var sun = directional_light(Color(255, 255, 255), lamp_node, 1.0)
    sun.cast_shadow = True
    scene.add_light(sun)
    var quad = assets.geometries.add(
        plane(Length(2.0, METER), Length(2.0, METER))
    )
    var gray = assets.materials.add(Material(Color(200, 200, 200)))
    var mesh = Mesh(quad, gray, node)
    mesh.cast_shadow = True
    scene.add_mesh(mesh)
    var renderer = Renderer(SIZE, SIZE)
    scene.update()
    assert_true(_center(renderer.render(scene, assets, _camera())).r > 0)
    assert_equal(len(renderer.shadow_maps(scene, assets)), 1)
    scene.node(lamp_node).visible = False
    scene.update()
    assert_equal(Int(_center(renderer.render(scene, assets, _camera())).r), 0)
    assert_equal(len(renderer.shadow_maps(scene, assets)), 0)
    # A light on no node always shines.
    assert_true(scene.light_shown(ambient_light(Color(1, 1, 1), 1.0)))


def test_render_order_decides_which_translucent_surface_is_on_top() raises:
    var assets = Assets()
    var scene = Scene()
    var near = scene.add(Object3D())
    scene.node(near).set_position(0, 0, 1)
    var far = scene.add(Object3D())
    scene.add_light(ambient_light(Color(255, 255, 255), 1.0))
    var quad = assets.geometries.add(
        plane(Length(2.0, METER), Length(2.0, METER))
    )
    var red = assets.materials.add(
        Material(Color(255, 0, 0), kind=BASIC, opacity=0.5, transparent=True)
    )
    var blue = assets.materials.add(
        Material(Color(0, 0, 255), kind=BASIC, opacity=0.5, transparent=True)
    )
    scene.add_mesh(Mesh(quad, red, near))
    scene.add_mesh(Mesh(quad, blue, far))
    var renderer = Renderer(SIZE, SIZE)
    scene.update()
    # By depth alone the far blue goes first and the near red over it.
    var by_depth = _center(renderer.render(scene, assets, _camera()))
    assert_true(by_depth.r > by_depth.b)
    # Drawn last, the far blue lands on top.
    scene.node(far).render_order = 1
    scene.update()
    var by_order = _center(renderer.render(scene, assets, _camera()))
    assert_true(by_order.b > by_order.r)


def test_render_order_sorts_lines_and_points_too() raises:
    var assets = Assets()
    var scene = Scene()
    var first = scene.add(Object3D())
    var second = scene.add(Object3D())
    scene.node(first).render_order = 2
    scene.add_light(ambient_light(Color(255, 255, 255), 1.0))
    var segment = assets.geometries.add(_segment())
    var solid = assets.materials.add(Material(Color(0, 255, 0), kind=BASIC))
    var glass = assets.materials.add(
        Material(Color(0, 0, 255), kind=BASIC, opacity=0.5, transparent=True)
    )
    scene.add_line(Line(segment, solid, first, mode=SEGMENTS))
    scene.add_line(Line(segment, solid, second, mode=SEGMENTS))
    scene.add_line(Line(segment, glass, first, mode=SEGMENTS))
    scene.add_line(Line(segment, glass, second, mode=SEGMENTS))
    var dots = assets.materials.add(points_material(Color(255, 0, 0)))
    var faint = assets.materials.add(
        points_material(Color(255, 0, 0), opacity=0.5, transparent=True)
    )
    scene.add_points(Points(segment, dots, first))
    scene.add_points(Points(segment, dots, second))
    scene.add_points(Points(segment, faint, first))
    scene.add_points(Points(segment, faint, second))
    var renderer = Renderer(SIZE, SIZE)
    scene.update()
    var image = renderer.render(scene, assets, _camera())
    assert_true(Int(_center(image).r) + Int(_center(image).g) > 0)


def test_a_hidden_mesh_is_not_picked() raises:
    var assets = Assets()
    var scene = Scene()
    var node = scene.add(Object3D())
    var quad = assets.geometries.add(
        plane(Length(2.0, METER), Length(2.0, METER))
    )
    var red = assets.materials.add(Material(Color(255, 0, 0)))
    scene.add_mesh(Mesh(quad, red, node))
    scene.update()
    # Off the diagonal the two triangles share.
    var ray = Raycaster(Vector3(0.3, 0.6, 5), Vector3(0, 0, -1))
    assert_equal(len(ray.intersect_mesh(scene, assets, 0)), 1)
    scene.node(node).visible = False
    scene.update()
    assert_equal(len(ray.intersect_mesh(scene, assets, 0)), 0)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
