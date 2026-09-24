# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Tests for managing a `BatchedMesh` as three.js's does: deleting,
hiding, geometry ranges, resizing, culling and a custom sort."""

from cameras.perspective_camera import PerspectiveCamera
from core.assets import Assets
from core.buffer_attribute import BufferAttribute
from core.buffer_geometry import POSITION, BufferGeometry
from core.geometry_store import GeometryId
from core.object_bounds import box_from_object
from core.object3d import NodeId, Object3D
from core.raycaster import Raycaster
from core.scene import Scene
from geometries.box import cube
from materials.material import Color, Material, MaterialId
from math.matrix4 import Matrix4, translation
from math.vector3 import Vector3
from objects.instanced_mesh import (
    BatchedDrawItem,
    BatchedMesh,
    NO_LIMIT,
)
from renderers.renderer import Renderer
from std.testing import (
    TestSuite,
    assert_equal,
    assert_false,
    assert_raises,
    assert_true,
)
from units.si import Angle, DEGREE, Length, METER

comptime WIDTH = 24
comptime HEIGHT = 18


def a_camera() raises -> PerspectiveCamera:
    """Return a camera six meters up z, looking at the origin."""
    var camera = PerspectiveCamera(
        Angle(45.0, DEGREE),
        Float32(WIDTH) / Float32(HEIGHT),
        Length(0.1, METER),
        Length(100.0, METER),
    )
    camera.place(Vector3(0, 0, 6), Vector3(0, 0, 0))
    return camera^


def triangle() raises -> BufferGeometry:
    """Return one triangle, not indexed."""
    var geometry = BufferGeometry()
    geometry.set_attribute(
        String(POSITION), BufferAttribute([0, 0, 0, 1, 0, 0, 0, 1, 0], 3)
    )
    return geometry^


def batch() raises -> BatchedMesh:
    """Return an empty batch with no limits."""
    return BatchedMesh(MaterialId(0), NodeId(0))


# --- instances --------------------------------------------------------------


def test_a_deleted_index_is_reused_lowest_first() raises:
    var group = batch()
    for _ in range(4):
        _ = group.add_instance(GeometryId(0))
    group.delete_instance(1)
    group.delete_instance(2)
    assert_equal(group.count(), 4)
    assert_equal(group.instance_count(), 2)
    assert_false(group.is_drawn(1))
    assert_equal(group.add_instance(GeometryId(3)), 1)
    assert_equal(group.add_instance(GeometryId(3)), 2)
    assert_equal(group.add_instance(GeometryId(3)), 4)
    assert_equal(group.instance_count(), 5)


def test_a_deleted_instance_is_refused() raises:
    var group = batch()
    _ = group.add_instance(GeometryId(0))
    group.delete_instance(0)
    with assert_raises(contains="deleted"):
        group.delete_instance(0)
    with assert_raises(contains="deleted"):
        _ = group.matrix_at(0)
    with assert_raises(contains="deleted"):
        group.set_visible_at(0, False)
    with assert_raises(contains="No instance"):
        _ = group.visible_at(1)
    assert_false(group.is_drawn(-1))
    assert_false(group.is_drawn(5))


def test_a_batch_holds_no_more_than_its_count() raises:
    var group = BatchedMesh(MaterialId(0), NodeId(0), max_instance_count=2)
    _ = group.add_instance(GeometryId(0))
    _ = group.add_instance(GeometryId(0))
    with assert_raises(contains="no more instances"):
        _ = group.add_instance(GeometryId(0))
    group.delete_instance(0)
    assert_equal(group.add_instance(GeometryId(0)), 0)


def test_a_batch_refuses_a_negative_size() raises:
    with assert_raises(contains="negative count"):
        _ = BatchedMesh(MaterialId(0), NodeId(0), max_instance_count=-1)
    with assert_raises(contains="negative count"):
        _ = BatchedMesh(MaterialId(0), NodeId(0), max_vertex_count=-1)
    with assert_raises(contains="negative count"):
        _ = BatchedMesh(MaterialId(0), NodeId(0), max_index_count=-1)
    assert_equal(batch().max_instance_count, NO_LIMIT)


def test_an_instance_is_shown_and_hidden() raises:
    var group = batch()
    _ = group.add_instance(GeometryId(0))
    assert_true(group.visible_at(0))
    group.set_visible_at(0, False)
    assert_false(group.visible_at(0))
    assert_false(group.is_drawn(0))


def test_the_instance_count_can_change() raises:
    var group = BatchedMesh(MaterialId(0), NodeId(0), max_instance_count=4)
    for _ in range(4):
        _ = group.add_instance(GeometryId(0))
    group.delete_instance(3)
    group.delete_instance(1)
    # The deleted instance at the end is dropped; the one in the middle
    # is still counted.
    group.set_instance_count(3)
    assert_equal(group.count(), 3)
    assert_equal(group.max_instance_count, 3)
    with assert_raises(contains="cannot shrink"):
        group.set_instance_count(2)
    group.set_instance_count(10)
    assert_equal(group.max_instance_count, 10)


# --- geometry ranges --------------------------------------------------------


def test_geometries_take_ranges_one_after_another() raises:
    var group = BatchedMesh(
        MaterialId(0), NodeId(0), max_vertex_count=100, max_index_count=100
    )
    var box = cube(Length(1, METER))
    _ = group.add_geometry(GeometryId(0), box)
    _ = group.add_geometry(GeometryId(1), box, 30, 40)
    var first = group.get_geometry_range_at(GeometryId(0))
    assert_equal(first.vertex_start, 0)
    assert_equal(first.vertex_count, 24)
    assert_equal(first.reserved_vertex_count, 24)
    assert_equal(first.index_start, 0)
    assert_equal(first.index_count, 36)
    assert_equal(first.start(), 0)
    assert_equal(first.count(), 36)
    var second = group.get_geometry_range_at(GeometryId(1))
    assert_equal(second.vertex_start, 24)
    assert_equal(second.reserved_vertex_count, 30)
    assert_equal(second.index_start, 36)
    assert_equal(second.start(), 36)
    assert_equal(group.unused_vertex_count(), 46)
    assert_equal(group.unused_index_count(), 24)


def test_a_range_without_an_index() raises:
    var group = batch()
    _ = group.add_geometry(GeometryId(0), triangle())
    var only = group.get_geometry_range_at(GeometryId(0))
    assert_equal(only.index_start, -1)
    assert_equal(only.reserved_index_count, -1)
    assert_equal(only.start(), 0)
    assert_equal(only.count(), 3)
    assert_equal(group.next_index_start, 0)


def test_a_range_that_does_not_fit_is_refused() raises:
    var group = BatchedMesh(
        MaterialId(0), NodeId(0), max_vertex_count=30, max_index_count=40
    )
    var box = cube(Length(1, METER))
    with assert_raises(contains="must name a geometry"):
        _ = group.add_geometry(GeometryId(-1), box)
    with assert_raises(contains="smaller than its geometry"):
        _ = group.add_geometry(GeometryId(0), box, 10)
    with assert_raises(contains="smaller than its geometry"):
        _ = group.add_geometry(GeometryId(0), box, -1, 10)
    with assert_raises(contains="does not fit"):
        _ = group.add_geometry(GeometryId(0), box, 31)
    with assert_raises(contains="does not fit"):
        _ = group.add_geometry(GeometryId(0), box, -1, 41)
    _ = group.add_geometry(GeometryId(0), box)
    with assert_raises(contains="has a range already"):
        _ = group.add_geometry(GeometryId(0), box)
    with assert_raises(contains="an index, or none"):
        _ = group.add_geometry(GeometryId(1), triangle())
    var loose = batch()
    _ = loose.add_geometry(GeometryId(0), triangle())
    with assert_raises(contains="an index, or none"):
        _ = loose.add_geometry(GeometryId(1), box)
    with assert_raises(contains="no range"):
        _ = loose.get_geometry_range_at(GeometryId(5))


def test_deleting_a_geometry_deletes_its_instances() raises:
    var group = batch()
    _ = group.add_geometry(GeometryId(0), triangle())
    _ = group.add_geometry(GeometryId(1), triangle())
    _ = group.add_instance(GeometryId(0))
    _ = group.add_instance(GeometryId(1))
    _ = group.add_instance(GeometryId(0))
    # An instance of a geometry with no range goes too.
    _ = group.add_instance(GeometryId(7))
    group.delete_geometry(GeometryId(0))
    assert_equal(group.instance_count(), 2)
    assert_false(group.is_drawn(0))
    assert_true(group.is_drawn(1))
    with assert_raises(contains="no range"):
        _ = group.get_geometry_range_at(GeometryId(0))
    group.delete_geometry(GeometryId(7))
    assert_equal(group.instance_count(), 1)
    with assert_raises(contains="must name a geometry"):
        group.delete_geometry(GeometryId(-1))
    # The freed slot is reused.
    _ = group.add_geometry(GeometryId(2), triangle())
    assert_equal(group.geometries[0].geometry, GeometryId(2))
    assert_equal(group.get_geometry_range_at(GeometryId(2)).vertex_start, 6)


def test_optimize_closes_the_gaps() raises:
    var group = batch()
    var box = cube(Length(1, METER))
    _ = group.add_geometry(GeometryId(0), box)
    _ = group.add_geometry(GeometryId(1), box)
    _ = group.add_geometry(GeometryId(2), box)
    group.delete_geometry(GeometryId(0))
    # Slot zero is reused for a range that lies after the others.
    _ = group.add_geometry(GeometryId(3), box)
    group.delete_geometry(GeometryId(2))
    group.optimize()
    assert_equal(group.get_geometry_range_at(GeometryId(1)).vertex_start, 0)
    assert_equal(group.get_geometry_range_at(GeometryId(1)).index_start, 0)
    assert_equal(group.get_geometry_range_at(GeometryId(3)).vertex_start, 24)
    assert_equal(group.get_geometry_range_at(GeometryId(3)).index_start, 36)
    assert_equal(group.next_vertex_start, 48)
    assert_equal(group.next_index_start, 72)
    # Ranges without an index move their vertices only.
    var loose = batch()
    _ = loose.add_geometry(GeometryId(0), triangle())
    _ = loose.add_geometry(GeometryId(1), triangle())
    loose.delete_geometry(GeometryId(0))
    loose.optimize()
    assert_equal(loose.get_geometry_range_at(GeometryId(1)).vertex_start, 0)
    assert_equal(loose.get_geometry_range_at(GeometryId(1)).index_start, -1)
    # Nothing to move.
    var empty = batch()
    empty.optimize()
    assert_equal(empty.next_vertex_start, 0)


def test_the_geometry_size_can_change() raises:
    var group = batch()
    var box = cube(Length(1, METER))
    _ = group.add_geometry(GeometryId(0), box)
    _ = group.add_geometry(GeometryId(1), box)
    group.delete_geometry(GeometryId(1))
    group.set_geometry_size(24, 36)
    assert_equal(group.max_vertex_count, 24)
    assert_equal(group.unused_vertex_count(), 0 - 24)
    with assert_raises(contains="vertices it uses"):
        group.set_geometry_size(23, 36)
    with assert_raises(contains="indices it uses"):
        group.set_geometry_size(24, 35)
    var loose = batch()
    _ = loose.add_geometry(GeometryId(0), triangle())
    loose.set_geometry_size(3, 0)
    assert_equal(loose.max_index_count, 0)
    # A batch with no ranges shrinks to nothing.
    var empty = batch()
    empty.set_geometry_size(0, 0)
    assert_equal(empty.max_vertex_count, 0)


# --- drawing ----------------------------------------------------------------


def a_scene_with(var group: BatchedMesh) raises -> Scene:
    """Return an updated scene with one node at the origin holding a
    batch."""
    var scene = Scene()
    _ = scene.add(Object3D())
    scene.update()
    scene.add_batched_mesh(group^)
    return scene^


def two_boxes(mut assets: Assets) raises -> BatchedMesh:
    """Return a batch of two boxes, one to the left and near, one to the
    right and far."""
    var box = assets.geometries.add(cube(Length(1, METER)))
    var paint = assets.materials.add(Material(Color(200, 100, 50)))
    var group = BatchedMesh(paint, NodeId(0))
    _ = group.add_instance(box, translation(-1.5, 0, 0))
    _ = group.add_instance(box, translation(1.5, 0, -2))
    return group^


def test_hidden_and_deleted_instances_are_not_drawn() raises:
    var renderer = Renderer(WIDTH, HEIGHT)
    var assets = Assets()
    var group = two_boxes(assets)
    var both = len(
        renderer.prepare(a_scene_with(group.copy()), assets, a_camera())
    )
    group.set_visible_at(0, False)
    var one = len(
        renderer.prepare(a_scene_with(group.copy()), assets, a_camera())
    )
    assert_true(one > 0 and one < both)
    group.set_visible_at(0, True)
    group.delete_instance(1)
    var other = len(
        renderer.prepare(a_scene_with(group.copy()), assets, a_camera())
    )
    assert_true(other > 0 and other < both)
    # Nor picked.
    var scene = a_scene_with(group^)
    var ray = Raycaster(Vector3(1.5, 0, 5), Vector3(0, 0, -1))
    assert_equal(len(ray.intersect_batched_mesh(scene, assets, 0)), 0)
    var hit = Raycaster(Vector3(-1.5, 0, 5), Vector3(0, 0, -1))
    assert_true(len(hit.intersect_batched_mesh(scene, assets, 0)) > 0)
    # A deleted instance adds no box; a hidden one still does.
    var bounded = box_from_object(scene, assets, NodeId(0))
    assert_equal(bounded.max.x, -1)
    scene.batched_meshes[0].set_visible_at(0, False)
    assert_equal(box_from_object(scene, assets, NodeId(0)).max.x, -1)


def test_culling_per_instance_or_for_the_whole_batch() raises:
    var renderer = Renderer(WIDTH, HEIGHT)
    var assets = Assets()
    var group = two_boxes(assets)
    # One instance behind the camera: culled on its own, or kept with the
    # batch, or never tested. The clipper removes it either way.
    group.set_matrix_at(1, translation(0, 0, 20))
    var counts = List[Int]()
    for mode in range(3):
        var copy = group.copy()
        copy.frustum_culled = mode != 2
        copy.per_object_frustum_culled = mode == 0
        counts.append(
            len(renderer.prepare(a_scene_with(copy^), assets, a_camera()))
        )
    assert_true(counts[0] > 0)
    assert_equal(counts[0], counts[1])
    assert_equal(counts[0], counts[2])
    # Every instance out of view: the whole batch is left out.
    group.set_matrix_at(0, translation(0, 0, 30))
    group.per_object_frustum_culled = False
    assert_equal(
        len(renderer.prepare(a_scene_with(group^), assets, a_camera())), 0
    )


def far_first(mut items: List[BatchedDrawItem]):
    """Put the furthest instance first."""
    for position in range(1, len(items)):
        var item = items[position]
        var at = position
        while at > 0 and items[at - 1].z < item.z:
            items[at] = items[at - 1]
            at -= 1
        items[at] = item


def a_stray(mut items: List[BatchedDrawItem]):
    """Add an instance that is not drawn."""
    items.append(BatchedDrawItem(9, 0))


def test_a_custom_sort_orders_the_batch() raises:
    var renderer = Renderer(WIDTH, HEIGHT)
    var assets = Assets()
    var group = two_boxes(assets)
    # Opaque draws go nearest first on their own: the left box.
    var own = renderer.prepare(a_scene_with(group.copy()), assets, a_camera())
    assert_true(own[0].world.x < 0)
    group.set_custom_sort(far_first)
    assert_true(group.custom_sorted)
    var sorted = renderer.prepare(
        a_scene_with(group.copy()), assets, a_camera()
    )
    assert_true(sorted[0].world.x > 0)
    group.clear_custom_sort()
    assert_false(group.custom_sorted)
    var again = renderer.prepare(a_scene_with(group.copy()), assets, a_camera())
    assert_true(again[0].world.x < 0)
    group.set_custom_sort(a_stray)
    with assert_raises(contains="not drawn"):
        _ = renderer.prepare(a_scene_with(group^), assets, a_camera())


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
