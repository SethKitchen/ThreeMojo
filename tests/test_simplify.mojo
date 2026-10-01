# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Tests for welding, decimating and budgeting humanoid meshes."""

from core.assets import Assets
from core.buffer_attribute import BufferAttribute
from core.buffer_geometry import BufferGeometry, NORMAL, POSITION, UV
from core.geometry_store import GeometryId
from core.object3d import NodeId, Object3D
from core.scene import Scene
from extensions.humanoid.skeleton.simplify import (
    MIN_PART_TRIANGLES,
    WeldedMesh,
    _Collapser,
    _Entry,
    _Heap,
    fit_triangle_budget,
    share_budget,
    simplify,
    simplify_welded,
    weld,
)
from geometries.plane import plane
from geometries.sphere import sphere
from materials.material import MaterialId
from math.vector3 import Vector3
from objects.mesh import Mesh
from std.math import pi
from std.testing import (
    TestSuite,
    assert_almost_equal,
    assert_equal,
    assert_false,
    assert_raises,
    assert_true,
)
from units.si import Length, METER


def _ball(segments: Int = 48) raises -> BufferGeometry:
    """Return a unit sphere of `segments` around and half as many up."""
    return sphere(Length(1.0, METER), segments, segments // 2)


def _loose(var positions: List[Float32]) raises -> BufferGeometry:
    """Return an unindexed geometry of `positions` only."""
    var geometry = BufferGeometry()
    geometry.set_attribute(String(POSITION), BufferAttribute(positions^, 3))
    return geometry^


def _area(geometry: BufferGeometry) raises -> Float64:
    """Return the surface area of an indexed geometry."""
    ref points = geometry.attribute_view(String(POSITION))
    var total = Float64(0)
    var slot = 0
    while slot < len(geometry.index):
        var a = points.vector3(geometry.index[slot])
        var edge = points.vector3(geometry.index[slot + 1]) - a
        edge.cross(points.vector3(geometry.index[slot + 2]) - a)
        total += Float64(edge.length()) * 0.5
        slot += 3
    return total


def test_a_simplified_ball_keeps_its_shape() raises:
    var ball = _ball()
    var fewer = simplify(ball, 400)
    assert_true(fewer.triangle_count() <= 400)
    assert_true(fewer.triangle_count() > 300)
    # The area of a unit sphere, to within a few percent.
    assert_almost_equal(_area(fewer), 4 * Float64(pi), rtol=0.05)
    ref normals = fewer.attribute_view(String(NORMAL))
    ref points = fewer.attribute_view(String(POSITION))
    for vertex in range(points.count()):  # pragma: no branch
        var normal = normals.vector3(vertex)
        assert_almost_equal(normal.length(), Float32(1), atol=1e-4)
        # Outward: along the vertex's own position on a sphere.
        assert_true(normal.dot(points.vector3(vertex)) > 0.8)
    assert_true(fewer.has_attribute(String(UV)))


def test_a_target_above_the_count_only_welds() raises:
    var ball = _ball(16)
    var kept = simplify(ball, 100000)
    assert_equal(kept.triangle_count(), ball.triangle_count())
    # The seam and the poles are joined.
    assert_true(
        kept.attribute_view(String(POSITION)).count()
        < ball.attribute_view(String(POSITION)).count()
    )


def test_weld_joins_corners_and_drops_faces_with_no_area() raises:
    # Two triangles that share an edge, each with its own corners, and a
    # third whose two corners meet.
    var corners: List[Float32] = [
        0,
        0,
        0,
        1,
        0,
        0,
        0,
        1,
        0,
        1,
        0,
        0,
        1,
        1,
        0,
        0,
        1,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        1,
        1,
        0,
    ]
    var geometry = _loose(corners^)
    var joined = simplify(geometry, 10)
    assert_equal(joined.triangle_count(), 2)
    assert_equal(joined.attribute_view(String(POSITION)).count(), 4)
    assert_false(joined.has_attribute(String(UV)))


def test_weld_takes_an_empty_mesh() raises:
    var empty = weld(WeldedMesh(List[Vector3](), List[Float32](), List[Int]()))
    assert_equal(empty.triangle_count(), 0)
    assert_equal(len(empty.positions), 0)


def test_an_open_mesh_keeps_its_border() raises:
    # A flat sheet: every collapse costs nothing inside, and its border
    # holds its edges where they are.
    var sheet = plane(Length(2.0, METER), Length(2.0, METER), 16, 16)
    var fewer = simplify(sheet, 20)
    assert_true(fewer.triangle_count() <= 20)
    ref points = fewer.attribute_view(String(POSITION))
    var low = Float32(0)
    var high = Float32(0)
    for vertex in range(points.count()):  # pragma: no branch
        low = min(low, points.vector3(vertex).x)
        high = max(high, points.vector3(vertex).x)
    assert_almost_equal(low, Float32(-1), atol=1e-4)
    assert_almost_equal(high, Float32(1), atol=1e-4)
    assert_almost_equal(_area(fewer), 4.0, rtol=1e-3)


def test_an_edge_of_three_faces_is_never_collapsed() raises:
    # Three fins on one spine: the spine is not a surface edge.
    var positions: List[Vector3] = [
        Vector3(0, 0, 0),
        Vector3(0, 1, 0),
        Vector3(1, 0.5, 0),
        Vector3(-1, 0.5, 0),
        Vector3(0, 0.5, 1),
    ]
    var faces: List[Int] = [0, 1, 2, 1, 0, 3, 0, 1, 4]
    var fins = WeldedMesh(positions^, List[Float32](), faces^)
    var kept = simplify_welded(fins, 1)
    # The fins' own edges are open, and they may merge; the spine stays.
    assert_true(kept.triangle_count() >= 1)
    var collapser = _Collapser(fins)
    assert_false(collapser.collapse(_Entry(0, 0, 1, 0, 0, 0, 0.5, 0)))


def test_a_stale_or_gone_candidate_is_refused() raises:
    var positions: List[Vector3] = [
        Vector3(0, 0, 0),
        Vector3(1, 0, 0),
        Vector3(0, 1, 0),
        Vector3(1, 1, 0),
    ]
    var faces: List[Int] = [0, 1, 2, 1, 3, 2]
    var square = WeldedMesh(positions^, List[Float32](), faces^)
    var collapser = _Collapser(square)
    # A version that has moved on.
    assert_false(collapser.collapse(_Entry(0, 1, 2, 5, 0, 0, 0, 0)))
    assert_false(collapser.collapse(_Entry(0, 1, 2, 0, 5, 0, 0, 0)))
    # Two vertices no face joins.
    assert_false(collapser.collapse(_Entry(0, 0, 3, 0, 0, 0, 0, 0)))
    # A vertex that is gone.
    collapser.vertex_alive[3] = False
    assert_false(collapser.collapse(_Entry(0, 3, 1, 0, 0, 0, 0, 0)))
    assert_false(collapser.collapse(_Entry(0, 1, 3, 0, 0, 0, 0, 0)))


def test_a_collapse_that_would_pinch_is_refused() raises:
    # A tetrahedron's edge has two faces, and its ends share the two far
    # corners and nothing else, so the link holds; a pyramid of four
    # sides over a square gives two apexes' neighbors a third in common.
    var positions: List[Vector3] = [
        Vector3(0, 0, 0),
        Vector3(1, 0, 0),
        Vector3(1, 1, 0),
        Vector3(0, 1, 0),
        Vector3(0.5, 0.5, 1),
        Vector3(0.5, 0.5, -1),
    ]
    # An octahedron: every edge's ends share exactly two neighbors, so
    # merging two opposite vertices through a false edge is refused.
    var faces: List[Int] = [
        0,
        1,
        4,
        1,
        2,
        4,
        2,
        3,
        4,
        3,
        0,
        4,
        1,
        0,
        5,
        2,
        1,
        5,
        3,
        2,
        5,
        0,
        3,
        5,
    ]
    var gem = WeldedMesh(positions^, List[Float32](), faces^)
    var collapser = _Collapser(gem)
    # The two apexes share no face.
    assert_false(collapser.collapse(_Entry(0, 4, 5, 0, 0, 0.5, 0.5, 0)))
    # Merging one edge of the gem closes it to a flat double sheet,
    # whose faces turn over: refused.
    assert_false(collapser.collapse(_Entry(0, 0, 2, 0, 0, 0.5, 0.5, 0)))
    # An honest edge can go once.
    assert_true(collapser.collapse(_Entry(0, 0, 1, 0, 0, 0.5, 0, 0)))


def test_the_heap_pops_cheapest_first() raises:
    var heap = _Heap()
    var costs: List[Float64] = [5, 1, 4, 2, 3, 0]
    for index in range(len(costs)):  # pragma: no branch
        heap.push(_Entry(costs[index], index, 0, 0, 0, 0, 0, 0))
    var last = Float64(-1)
    while len(heap.entries) > 0:
        var entry = heap.pop()
        assert_true(entry.cost >= last)
        last = entry.cost
    assert_equal(last, 5)


def test_the_budget_is_shared_by_area() raises:
    var areas: List[Float64] = [1, 1, 2]
    var counts: List[Int] = [1000, 10, 1000]
    var shares = share_budget(areas, counts, 410)
    # The small mesh cannot use its quarter, and gives it back.
    assert_equal(shares[1], 10)
    assert_equal(shares[0], 133)
    assert_equal(shares[2], 266)
    # Every mesh keeps its least, however small the budget.
    var tiny = share_budget(areas, counts, 1)
    assert_equal(tiny[0], MIN_PART_TRIANGLES)
    assert_equal(tiny[1], 10)
    # A mesh with no area still keeps its least.
    var flat: List[Float64] = [0, 0]
    var two: List[Int] = [100, 100]
    var none = share_budget(flat, two, 1000)
    assert_equal(none[0], MIN_PART_TRIANGLES)
    assert_equal(len(share_budget(List[Float64](), List[Int](), 5)), 0)


def _scene_of_balls(
    mut assets: Assets, mut scene: Scene
) raises -> List[GeometryId]:
    """Put two balls in `scene`, one drawn twice, and return their ids."""
    var node = scene.add(Object3D())
    var small = assets.geometries.add(_ball(24))
    var large = assets.geometries.add(_ball(64))
    scene.add_mesh(Mesh(small, MaterialId(0), node))
    scene.add_mesh(Mesh(large, MaterialId(0), node))
    scene.add_mesh(Mesh(small, MaterialId(0), node))
    return [small, large]


def test_fit_triangle_budget_decimates_the_scene() raises:
    for workers in [1, 3]:  # pragma: no branch
        var assets = Assets()
        var scene = Scene()
        var ids = _scene_of_balls(assets, scene)
        fit_triangle_budget(scene, assets, 0, 1200, workers)
        var small = assets.geometries.get(ids[0]).triangle_count()
        var large = assets.geometries.get(ids[1]).triangle_count()
        assert_true(small + large <= 1200)
        # The same area, so the same share.
        assert_true(small > 500 and large > 500)


def test_fit_triangle_budget_starts_at_the_first_mesh() raises:
    var assets = Assets()
    var scene = Scene()
    var ids = _scene_of_balls(assets, scene)
    var before = assets.geometries.get(ids[0]).triangle_count()
    fit_triangle_budget(scene, assets, 3, 10)
    assert_equal(assets.geometries.get(ids[0]).triangle_count(), before)


def test_fit_triangle_budget_refuses_bad_arguments() raises:
    var assets = Assets()
    var scene = Scene()
    _ = _scene_of_balls(assets, scene)
    with assert_raises():
        fit_triangle_budget(scene, assets, 0, 0)
    with assert_raises():
        fit_triangle_budget(scene, assets, 0, 100, 0)
    with assert_raises():
        fit_triangle_budget(scene, assets, -1, 100)
    with assert_raises():
        fit_triangle_budget(scene, assets, 4, 100)


def test_simplify_refuses_bad_meshes() raises:
    with assert_raises():
        _ = simplify(_ball(8), 0)
    var partial: List[Float32] = [0, 0, 0, 1, 0, 0]
    with assert_raises():
        _ = simplify(_loose(partial^), 10)
    var corners: List[Float32] = [0, 0, 0, 1, 0, 0, 0, 1, 0]
    var pointed = _loose(corners^)
    pointed.set_index([0, 1, 2])
    pointed.index[2] = 5
    with assert_raises():
        _ = simplify(pointed, 10)
    var bent = _loose(List[Float32]())
    bent.set_index(List[Int]())
    bent.index = [-1, 0, 0]
    with assert_raises():
        _ = simplify(bent, 10)


def test_the_store_replaces_a_geometry_in_place() raises:
    var assets = Assets()
    var id = assets.geometries.add(_ball(8))
    assets.geometries.replace(id, _ball(16))
    assert_equal(
        assets.geometries.get(id).triangle_count(),
        _ball(16).triangle_count(),
    )
    with assert_raises():
        assets.geometries.replace(GeometryId(4), _ball(8))
    with assert_raises():
        assets.geometries.replace(GeometryId(-1), _ball(8))


def test_weld_drops_a_face_whichever_corners_meet() raises:
    # Each face below loses a different pair of corners to the weld.
    var corners: List[Float32] = [
        0,
        0,
        0,
        1,
        0,
        0,
        1,
        0,
        0,
        0,
        0,
        0,
        1,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        1,
        0,
        0,
        0,
        1,
        0,
    ]
    var joined = simplify(_loose(corners^), 10)
    assert_equal(joined.triangle_count(), 1)


def test_a_vertex_no_face_uses_points_up() raises:
    var positions: List[Vector3] = [
        Vector3(0, 0, 0),
        Vector3(1, 0, 0),
        Vector3(0, 1, 0),
        Vector3(5, 5, 5),
    ]
    var faces: List[Int] = [0, 1, 2]
    var mesh = WeldedMesh(positions^, List[Float32](), faces^)
    var geometry = mesh.to_geometry()
    var up = geometry.attribute_view(String(NORMAL)).vector3(3)
    assert_equal(up.y, Float32(1))


def test_a_collapse_that_pinches_the_surface_is_refused() raises:
    # The edge 0-1 has two faces, but its ends also share 4 and 5
    # through two other faces: merging them would pinch.
    var positions: List[Vector3] = [
        Vector3(0, 0, 0),
        Vector3(1, 0, 0),
        Vector3(0.5, 1, 0),
        Vector3(0.5, -1, 0),
        Vector3(0.5, 0, 1),
        Vector3(0.5, 0.5, 2),
    ]
    var faces: List[Int] = [0, 1, 2, 1, 0, 3, 0, 4, 5, 4, 1, 5]
    var mesh = WeldedMesh(positions^, List[Float32](), faces^)
    var collapser = _Collapser(mesh)
    assert_false(collapser.collapse(_Entry(0, 0, 1, 0, 0, 0.5, 0, 0)))


def test_faces_with_no_area_hold_nothing_and_refuse_to_move() raises:
    # A strip of two faces and a sliver whose corners lie on one line.
    var positions: List[Vector3] = [
        Vector3(0, 0, 0),
        Vector3(1, 0, 0),
        Vector3(0, 1, 0),
        Vector3(1, 1, 0),
        Vector3(2, 0, 0),
    ]
    var faces: List[Int] = [0, 1, 2, 1, 3, 2, 0, 4, 1]
    var mesh = WeldedMesh(positions^, List[Float32](), faces^)
    var collapser = _Collapser(mesh)
    # Vertex 1 is on the sliver, which has no normal to keep: refused.
    assert_false(collapser.collapse(_Entry(0, 2, 1, 0, 0, 1, 0, 0)))
    # Moving 2 onto the line through 0 and 1 leaves its face no area.
    var square = WeldedMesh(
        [
            Vector3(0, 0, 0),
            Vector3(1, 0, 0),
            Vector3(0, 1, 0),
            Vector3(1, 1, 0),
        ],
        List[Float32](),
        [0, 1, 2, 1, 3, 2],
    )
    var flat = _Collapser(square)
    assert_false(flat.collapse(_Entry(0, 3, 2, 0, 0, 0.5, 0, 0)))


def test_an_empty_mesh_has_no_area_and_no_faces() raises:
    var empty = WeldedMesh(List[Vector3](), List[Float32](), List[Int]())
    assert_equal(empty.area(), 0)
    assert_equal(empty.to_geometry().triangle_count(), 0)
    var bare = _loose(List[Float32]())
    bare.set_attribute(String(UV), BufferAttribute(List[Float32](), 2))
    assert_equal(simplify(bare, 10).triangle_count(), 0)


def test_collapsing_a_quad_leaves_no_face() raises:
    var positions: List[Vector3] = [
        Vector3(0, 0, 0),
        Vector3(1, 0, 0),
        Vector3(0, 1, 0),
        Vector3(1, 1, 0),
    ]
    var faces: List[Int] = [0, 1, 2, 1, 3, 2]
    var quad = WeldedMesh(positions^, List[Float32](), faces^)
    var collapser = _Collapser(quad)
    assert_true(collapser.collapse(_Entry(0, 1, 2, 0, 0, 0.5, 0.5, 0)))
    assert_equal(collapser.alive, 0)


def test_a_tetrahedron_stops_when_no_edge_can_go() raises:
    var positions: List[Vector3] = [
        Vector3(0, 0, 0),
        Vector3(1, 0, 0),
        Vector3(0, 1, 0),
        Vector3(0, 0, 1),
    ]
    var faces: List[Int] = [0, 2, 1, 0, 1, 3, 0, 3, 2, 1, 2, 3]
    var tetra = WeldedMesh(positions^, List[Float32](), faces^)
    var kept = simplify_welded(tetra, 1)
    assert_true(kept.triangle_count() >= 2)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
