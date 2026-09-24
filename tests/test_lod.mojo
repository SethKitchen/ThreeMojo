# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Tests for `objects.lod` and the scene's levels of detail, three.js's
`LOD`, whose levels are any objects.

A render test draws an LOD and the same meshes on plain nodes, and asks
for the same image, pixel for pixel.
"""

from cameras.perspective_camera import PerspectiveCamera
from core.assets import Assets
from core.geometry_store import GeometryId
from core.object3d import NodeId, Object3D
from core.scene import Scene
from geometries.box import cube
from geometries.sphere import sphere
from materials.material import Material, MaterialId
from math.vector3 import Vector3
from objects.lod import Lod
from objects.mesh import Mesh
from render.framebuffer import Color, Framebuffer
from renderers.renderer import Renderer
from std.math import nan
from std.testing import (
    TestSuite,
    assert_almost_equal,
    assert_equal,
    assert_false,
    assert_raises,
    assert_true,
)
from units.si import Angle, DEGREE, Length, METER

comptime WIDTH = 24
comptime HEIGHT = 18


def a_camera(z: Float32 = 6) raises -> PerspectiveCamera:
    """Return a camera `z` meters up the z axis, looking at the origin."""
    var camera = PerspectiveCamera(
        Angle(45.0, DEGREE),
        Float32(WIDTH) / Float32(HEIGHT),
        Length(0.1, METER),
        Length(100.0, METER),
    )
    camera.place(Vector3(0, 0, z), Vector3(0, 0, 0))
    return camera^


def assert_same_image(got: Framebuffer, wanted: Framebuffer) raises:
    """Assert two images agree on every pixel and its depth."""
    for y in range(HEIGHT):
        for x in range(WIDTH):
            var one = got.get_pixel(x, y)
            var two = wanted.get_pixel(x, y)
            assert_equal(one.r, two.r)
            assert_equal(one.g, two.g)
            assert_equal(one.b, two.b)
            assert_equal(one.a, two.a)
            assert_equal(got.depth_at(x, y), wanted.depth_at(x, y))


def count_drawn(image: Framebuffer, background: Color) raises -> Int:
    """Return how many pixels are not the background."""
    var drawn = 0
    for y in range(HEIGHT):
        for x in range(WIDTH):
            var pixel = image.get_pixel(x, y)
            if pixel.r != background.r or pixel.g != background.g:
                drawn += 1
    return drawn


def level(
    mut scene: Scene, geometry: GeometryId, material: MaterialId
) raises -> NodeId:
    """Add a node carrying one mesh, and return the node."""
    var node = scene.add(Object3D())
    scene.add_mesh(Mesh(geometry, material, node))
    return node


def nodes(count: Int) raises -> Scene:
    """Return an updated scene of `count` nodes, each at the origin."""
    var scene = Scene()
    for _ in range(count):
        _ = scene.add(Object3D())
    scene.update()
    return scene^


# --- the object -------------------------------------------------------------


def test_an_lod_keeps_its_levels_in_order_of_distance() raises:
    var lod = Lod(NodeId(0))
    assert_equal(lod.count(), 0)
    assert_equal(lod.level_for(Length(3.0, METER)), -1)
    lod.add_level(NodeId(3), Length(10.0, METER))
    lod.add_level(NodeId(1))
    lod.add_level(NodeId(2), Length(5.0, METER))
    # A level at a distance another has goes after it.
    lod.add_level(NodeId(4), Length(5.0, METER))
    assert_equal(lod.count(), 4)
    assert_equal(lod.level_at(0).object, NodeId(1))
    assert_equal(lod.level_at(1).object, NodeId(2))
    assert_equal(lod.level_at(2).object, NodeId(4))
    assert_equal(lod.level_at(3).object, NodeId(3))
    assert_almost_equal(lod.level_at(3).distance.value, Float32(10))
    assert_equal(lod.level_for(Length(0.0, METER)), 0)
    assert_equal(lod.level_for(Length(4.9, METER)), 0)
    assert_equal(lod.level_for(Length(5.0, METER)), 2)
    assert_equal(lod.level_for(Length(50.0, METER)), 3)


def test_an_lod_refuses_what_cannot_be_a_level() raises:
    with assert_raises(contains="must name a scene node"):
        _ = Lod(NodeId(-1))
    var lod = Lod(NodeId(0))
    with assert_raises(contains="must name a scene node"):
        lod.add_level(NodeId(-1))
    with assert_raises(contains="its own level"):
        lod.add_level(NodeId(0))
    with assert_raises(contains="cannot be negative"):
        lod.add_level(NodeId(1), Length(-1.0, METER))
    with assert_raises(contains="from zero to one"):
        lod.add_level(NodeId(1), hysteresis=-0.1)
    with assert_raises(contains="from zero to one"):
        lod.add_level(NodeId(1), hysteresis=1.1)
    with assert_raises(contains="from zero to one"):
        lod.add_level(NodeId(1), hysteresis=nan[DType.float32]())
    with assert_raises(contains="No level"):
        _ = lod.level_at(0)
    lod.add_level(NodeId(1))
    with assert_raises(contains="one level of an LOD at most"):
        lod.add_level(NodeId(1), Length(3.0, METER))
    with assert_raises(contains="No level"):
        _ = lod.level_at(1)
    with assert_raises(contains="No level"):
        _ = lod.level_at(-1)


def test_hysteresis_keeps_a_level_until_the_camera_comes_nearer() raises:
    var lod = Lod(NodeId(0))
    lod.add_level(NodeId(1))
    lod.add_level(NodeId(2), Length(10.0, METER), 0.2)
    assert_equal(lod.current_level(), 0)
    assert_equal(lod.update(Length(9.0, METER)), 0)
    assert_equal(lod.update(Length(10.0, METER)), 1)
    assert_equal(lod.current_level(), 1)
    assert_equal(lod.level_for(Length(9.0, METER)), 0)
    assert_equal(lod.update(Length(9.0, METER)), 1)
    assert_equal(lod.update(Length(8.0, METER)), 1)
    assert_equal(lod.update(Length(7.9, METER)), 0)
    # The memory follows a level inserted before it, and an empty LOD
    # remembers nothing.
    _ = lod.update(Length(50.0, METER))
    lod.add_level(NodeId(3), Length(5.0, METER))
    assert_equal(lod.shown, 2)
    assert_equal(lod.level_at(2).object, NodeId(2))
    var empty = Lod(NodeId(0))
    assert_equal(empty.update(Length(1.0, METER)), -1)
    assert_equal(empty.shown, 0)


def test_a_level_is_removed_by_its_distance() raises:
    var lod = Lod(NodeId(0))
    assert_false(Bool(lod.remove_level(Length(0.0, METER))))
    lod.add_level(NodeId(1))
    lod.add_level(NodeId(2), Length(5.0, METER))
    lod.add_level(NodeId(3), Length(9.0, METER))
    assert_false(Bool(lod.remove_level(Length(4.0, METER))))
    # A level before the shown one: the memory follows the shown level.
    _ = lod.update(Length(20.0, METER))
    assert_equal(lod.remove_level(Length(0.0, METER)).value(), NodeId(1))
    assert_equal(lod.shown, 1)
    # The shown level itself, the last: the one before shows.
    assert_equal(lod.remove_level(Length(9.0, METER)).value(), NodeId(3))
    assert_equal(lod.shown, 0)
    # A level after the shown one changes nothing.
    lod.add_level(NodeId(4), Length(7.0, METER))
    assert_equal(lod.remove_level(Length(7.0, METER)).value(), NodeId(4))
    assert_equal(lod.shown, 0)
    # The shown level with one after it: the one after takes its place.
    lod.add_level(NodeId(5), Length(8.0, METER))
    assert_equal(lod.remove_level(Length(5.0, METER)).value(), NodeId(2))
    assert_equal(lod.shown, 0)
    assert_equal(lod.level_at(0).object, NodeId(5))


# --- the scene --------------------------------------------------------------


def test_the_scene_makes_the_levels_children_and_shows_one() raises:
    var scene = nodes(4)
    var lod = Lod(NodeId(0))
    lod.add_level(NodeId(1))
    lod.add_level(NodeId(2), Length(5.0, METER))
    scene.add_lod(lod^)
    assert_equal(scene.get(NodeId(1)).parent, NodeId(0))
    assert_equal(scene.get(NodeId(2)).parent, NodeId(0))
    assert_true(scene.get(NodeId(1)).visible)
    assert_false(scene.get(NodeId(2)).visible)
    # A level added through the scene is a child too, and hidden.
    scene.add_lod_level(0, NodeId(3), Length(9.0, METER))
    assert_equal(scene.get(NodeId(3)).parent, NodeId(0))
    assert_false(scene.get(NodeId(3)).visible)
    # A removed level is off the LOD's node, out of the scene.
    assert_true(scene.remove_lod_level(0, Length(5.0, METER)))
    assert_false(scene.remove_lod_level(0, Length(5.0, METER)))
    scene.update()
    assert_false(scene.in_scene(NodeId(2)))
    assert_equal(scene.lods[0].count(), 2)


def test_the_scene_refuses_a_level_it_cannot_hang() raises:
    var scene = nodes(3)
    with assert_raises(contains="node that is in the scene"):
        scene.add_lod(Lod(NodeId(5)))
    var outside = Lod(NodeId(0))
    outside.add_level(NodeId(7))
    with assert_raises(contains="level must name a node"):
        scene.add_lod(outside^)
    # A level above the LOD's node cannot go under it.
    scene.add(NodeId(1), parent=NodeId(2))
    var above = Lod(NodeId(1))
    above.add_level(NodeId(2))
    with assert_raises(contains="own descendant"):
        scene.add_lod(above^)
    scene.add_lod(Lod(NodeId(1)))
    with assert_raises(contains="own descendant"):
        scene.add_lod_level(0, NodeId(2))
    with assert_raises(contains="out of range"):
        scene.add_lod_level(0, NodeId(9))
    for wrong in [-1, 1]:
        with assert_raises(contains="No LOD"):
            scene.add_lod_level(wrong, NodeId(0))
        with assert_raises(contains="No LOD"):
            _ = scene.remove_lod_level(wrong, Length(0.0, METER))
        with assert_raises(contains="No LOD"):
            scene.update_lod(wrong, Vector3(0, 0, 0))


def test_updating_shows_the_level_the_camera_picks() raises:
    var scene = nodes(3)
    var lod = Lod(NodeId(0))
    lod.add_level(NodeId(1))
    lod.add_level(NodeId(2), Length(5.0, METER), 0.5)
    scene.add_lod(lod^)
    scene.update()
    scene.update_lods(Vector3(0, 0, 8))
    assert_equal(scene.lods[0].shown, 1)
    assert_false(scene.is_shown(NodeId(1)))
    assert_true(scene.is_shown(NodeId(2)))
    # The hysteresis holds the far level at four meters.
    scene.update_lods(Vector3(0, 0, 4))
    assert_equal(scene.lods[0].shown, 1)
    scene.update_lods(Vector3(0, 0, 2.4))
    assert_equal(scene.lods[0].shown, 0)
    assert_true(scene.is_shown(NodeId(1)))
    # A stale scene is refused.
    scene.node(NodeId(0)).set_position(0, 0, 1)
    with assert_raises(contains="has changed since update"):
        scene.update_lods(Vector3(0, 0, 8))


def test_every_lod_changes_level_in_one_update() raises:
    # Showing the first LOD's level leaves the scene stale. The second
    # LOD must still be measured, from the scene as it stood.
    var scene = nodes(6)
    for holder in [0, 3]:
        var lod = Lod(NodeId(holder))
        lod.add_level(NodeId(holder + 1))
        lod.add_level(NodeId(holder + 2), Length(5.0, METER))
        scene.add_lod(lod^)
    scene.update()
    scene.update_lods(Vector3(0, 0, 8))
    for index in range(2):
        assert_equal(scene.lods[index].shown, 1)
    assert_true(scene.is_shown(NodeId(2)))
    assert_true(scene.is_shown(NodeId(5)))
    assert_false(scene.is_stale())


def test_an_lod_without_auto_update_waits_to_be_told() raises:
    var scene = nodes(3)
    var lod = Lod(NodeId(0), auto_update=False)
    lod.add_level(NodeId(1))
    lod.add_level(NodeId(2), Length(5.0, METER))
    scene.add_lod(lod^)
    # One level, or none: nothing to choose.
    var single = Lod(scene.add(Object3D()))
    single.add_level(scene.add(Object3D()), Length(5.0, METER))
    scene.add_lod(single^)
    scene.add_lod(Lod(scene.add(Object3D())))
    scene.update()
    scene.update_lods(Vector3(0, 0, 8))
    assert_equal(scene.lods[0].shown, 0)
    assert_equal(scene.lods[1].shown, 0)
    scene.update_lod(0, Vector3(0, 0, 8))
    assert_equal(scene.lods[0].shown, 1)
    assert_true(scene.is_shown(NodeId(2)))
    # A scene with no LODs has nothing to update.
    var bare = nodes(1)
    bare.update_lods(Vector3(0, 0, 8))
    assert_equal(len(bare.lods), 0)


def test_a_clone_carries_its_levels() raises:
    var scene = nodes(3)
    var lod = Lod(NodeId(0))
    lod.add_level(NodeId(1))
    lod.add_level(NodeId(2), Length(5.0, METER))
    scene.add_lod(lod^)
    scene.update()
    var copy = scene.clone(NodeId(0))
    assert_equal(len(scene.lods), 2)
    ref cloned = scene.lods[1]
    assert_equal(cloned.node, copy)
    assert_equal(scene.get(cloned.levels[0].object).parent, copy)
    assert_equal(scene.get(cloned.levels[1].object).parent, copy)
    # A level that was not copied stays the original's.
    _ = scene.clone(NodeId(0), recursive=False)
    assert_equal(scene.lods[2].levels[0].object, NodeId(1))


# --- drawing ----------------------------------------------------------------


def test_the_renderer_draws_the_level_shown() raises:
    var renderer = Renderer(WIDTH, HEIGHT)
    var assets = Assets()
    var box = assets.geometries.add(cube(Length(1.0, METER)))
    var ball = assets.geometries.add(sphere(Length(0.7, METER), 12, 8))
    var paint = assets.materials.add(Material(Color(220, 120, 40)))
    var scene = nodes(1)
    var near = level(scene, box, paint)
    var far = level(scene, ball, paint)
    var lod = Lod(NodeId(0))
    lod.add_level(near)
    lod.add_level(far, Length(5.0, METER))
    scene.add_lod(lod^)
    scene.update()
    var near_box = nodes(1)
    near_box.add_mesh(Mesh(box, paint, NodeId(0)))
    var far_ball = nodes(1)
    far_ball.add_mesh(Mesh(ball, paint, NodeId(0)))
    # Never updated, level zero shows.
    assert_same_image(
        renderer.render(scene, assets, a_camera(8)),
        renderer.render(near_box, assets, a_camera(8)),
    )
    scene.update_lods(Vector3(0, 0, 8))
    assert_same_image(
        renderer.render(scene, assets, a_camera(8)),
        renderer.render(far_ball, assets, a_camera(8)),
    )
    assert_true(
        count_drawn(
            renderer.render(scene, assets, a_camera(8)), renderer.background
        )
        > 0
    )


def test_a_level_can_be_a_group() raises:
    # The far level is a group of two meshes, as three.js allows.
    var renderer = Renderer(WIDTH, HEIGHT)
    var assets = Assets()
    var box = assets.geometries.add(cube(Length(0.5, METER)))
    var paint = assets.materials.add(Material(Color(90, 190, 255)))
    var scene = nodes(1)
    var near = level(scene, box, paint)
    var group = scene.add(Object3D())
    var left = Object3D()
    left.set_position(-1, 0, 0)
    left.parent = group
    var right = Object3D()
    right.set_position(1, 0, 0)
    right.parent = group
    scene.add_mesh(Mesh(box, paint, scene.add(left^)))
    scene.add_mesh(Mesh(box, paint, scene.add(right^)))
    var lod = Lod(NodeId(0))
    lod.add_level(near)
    lod.add_level(group, Length(5.0, METER))
    scene.add_lod(lod^)
    scene.update()
    scene.update_lods(Vector3(0, 0, 6))
    var pair = nodes(1)
    for x in [Float32(-1), Float32(1)]:
        var at = Object3D()
        at.set_position(x, 0, 0)
        pair.add_mesh(Mesh(box, paint, pair.add(at^)))
    pair.update()
    assert_same_image(
        renderer.render(scene, assets, a_camera(6)),
        renderer.render(pair, assets, a_camera(6)),
    )


def test_an_lod_with_no_levels_draws_nothing() raises:
    var renderer = Renderer(WIDTH, HEIGHT)
    var assets = Assets()
    var scene = nodes(1)
    scene.add_lod(Lod(NodeId(0)))
    scene.update_lods(Vector3(0, 0, 6))
    assert_equal(len(renderer.prepare(scene, assets, a_camera())), 0)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
