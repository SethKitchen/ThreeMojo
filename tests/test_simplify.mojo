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
    BEST_EFFORT,
    MINIMUM_SHARES,
    MIN_PART_TRIANGLES,
    SAFE_COLLAPSE_LIMIT,
    SMALL_WELDED_SOURCES,
    STRICT,
    TriangleBudgetMode,
    TriangleBudgetReason,
    WeldedMesh,
    _Collapser,
    _Entry,
    _Heap,
    _read_mesh,
    _replace_budget_meshes,
    fit_triangle_budget,
    fit_triangle_budget_result,
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
from std.math import cos, pi, sin
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


def test_budget_floors_do_not_exceed_a_feasible_budget() raises:
    var areas: List[Float64] = [1, 100]
    var counts: List[Int] = [100, 100]
    var shares = share_budget(areas, counts, 64)
    assert_equal(shares[0], 32)
    assert_equal(shares[1], 32)
    # A capped large-area mesh must not consume another mesh's minimum.
    var capped: List[Int] = [100, 50]
    var tight = share_budget(areas, capped, 64)
    assert_equal(tight[0], 32)
    assert_equal(tight[1], 32)
    # With room to spare, return unused triangles from the capped mesh.
    var roomy = share_budget(areas, capped, 100)
    assert_equal(roomy[0], 50)
    assert_equal(roomy[1], 50)


def _fan(triangles: Int) raises -> BufferGeometry:
    """Return a flat disk with one center and `triangles` border vertices."""
    var positions: List[Vector3] = [Vector3(0, 0, 0)]
    var faces = List[Int]()
    for index in range(triangles):  # pragma: no branch
        var angle = Float32(2 * pi) * Float32(index) / Float32(triangles)
        positions.append(Vector3(cos(angle), sin(angle), 0))
        faces.append(0)
        faces.append(index + 1)
        faces.append((index + 1) % triangles + 1)
    return WeldedMesh(positions^, List[Float32](), faces^).to_geometry()


def test_budget_does_not_collapse_below_the_part_minimum() raises:
    for workers in [1, 3]:  # pragma: no branch
        var assets = Assets()
        var scene = Scene()
        var node = scene.add(Object3D())
        var id = assets.geometries.add(_fan(33))
        scene.add_mesh(Mesh(id, MaterialId(0), node))
        fit_triangle_budget(scene, assets, 0, 32, workers)
        assert_equal(assets.geometries.get(id).triangle_count(), 32)


def test_budget_bounds_hold_for_small_and_zero_area_meshes() raises:
    # Cover lower and upper bounds in both orders, including zero areas.
    for first_area in [Float64(0), 1, 100]:  # pragma: no branch
        for second_area in [Float64(0), 1, 100]:  # pragma: no branch
            for first_count in [0, 10, 32, 33, 100]:  # pragma: no branch
                for second_count in [10, 50, 100]:  # pragma: no branch
                    for budget in [1, 64, 100, 500]:  # pragma: no branch
                        var areas: List[Float64] = [first_area, second_area]
                        var counts: List[Int] = [first_count, second_count]
                        var shares = share_budget(areas, counts, budget)
                        var least = min(32, first_count) + min(32, second_count)
                        assert_true(shares[0] >= min(32, first_count))
                        assert_true(shares[1] >= min(32, second_count))
                        assert_true(shares[0] <= first_count)
                        assert_true(shares[1] <= second_count)
                        assert_true(shares[0] + shares[1] <= max(budget, least))
                        var reversed_areas: List[Float64] = [
                            second_area,
                            first_area,
                        ]
                        var reversed_counts: List[Int] = [
                            second_count,
                            first_count,
                        ]
                        var reversed = share_budget(
                            reversed_areas, reversed_counts, budget
                        )
                        assert_equal(shares[0], reversed[1])
                        assert_equal(shares[1], reversed[0])


def test_budget_minima_take_priority_when_the_budget_is_too_small() raises:
    for workers in [1, 3]:  # pragma: no branch
        var assets = Assets()
        var scene = Scene()
        var node = scene.add(Object3D())
        var first = assets.geometries.add(_fan(33))
        var second = assets.geometries.add(_fan(33))
        scene.add_mesh(Mesh(first, MaterialId(0), node))
        scene.add_mesh(Mesh(second, MaterialId(0), node))
        fit_triangle_budget(scene, assets, 0, 1, workers)
        assert_equal(assets.geometries.get(first).triangle_count(), 32)
        assert_equal(assets.geometries.get(second).triangle_count(), 32)


def test_budget_minimum_uses_the_count_after_welding() raises:
    var assets = Assets()
    var scene = Scene()
    var node = scene.add(Object3D())
    var geometry = _fan(3)
    for _ in range(30):  # pragma: no branch
        geometry.index.append(0)
        geometry.index.append(0)
        geometry.index.append(1)
    assert_equal(geometry.triangle_count(), 33)
    var id = assets.geometries.add(geometry^)
    scene.add_mesh(Mesh(id, MaterialId(0), node))
    fit_triangle_budget(scene, assets, 0, 1)
    assert_equal(assets.geometries.get(id).triangle_count(), 3)


def test_budget_keeps_protected_topology_above_the_target() raises:
    var assets = Assets()
    var scene = Scene()
    var node = scene.add(Object3D())
    var geometry = _loose([0, 0, 0, 1, 0, 0, 0, 1, 0])
    var faces = List[Int]()
    # Every edge belongs to more than two faces. No collapse is safe.
    for _ in range(33):  # pragma: no branch
        faces.append(0)
        faces.append(1)
        faces.append(2)
    geometry.set_index(faces^)
    var id = assets.geometries.add(geometry^)
    scene.add_mesh(Mesh(id, MaterialId(0), node))
    fit_triangle_budget(scene, assets, 0, 32)
    assert_equal(assets.geometries.get(id).triangle_count(), 33)


def _protected_faces(triangles: Int) raises -> BufferGeometry:
    """Return overlapping faces with no safely collapsible edge."""
    var geometry = _loose([0, 0, 0, 1, 0, 0, 0, 1, 0])
    var faces = List[Int]()
    for _ in range(triangles):  # pragma: no branch
        faces.append(0)
        faces.append(1)
        faces.append(2)
    geometry.set_index(faces^)
    return geometry^


def test_budget_result_reports_exact_feasible_and_shared_counts() raises:
    for workers in [1, 3]:  # pragma: no branch
        var assets = Assets()
        var scene = Scene()
        var node = scene.add(Object3D())
        var first = assets.geometries.add(_fan(33))
        var second = assets.geometries.add(_fan(33))
        scene.add_mesh(Mesh(first, MaterialId(0), node))
        scene.add_mesh(Mesh(second, MaterialId(0), node))
        scene.add_mesh(Mesh(first, MaterialId(0), node))
        var result = fit_triangle_budget_result(scene, assets, 0, 64, workers)
        # Independent counts, rather than a comparison to the allocator.
        assert_equal(assets.geometries.get(first).triangle_count(), 32)
        assert_equal(assets.geometries.get(second).triangle_count(), 32)
        assert_equal(result.requested_triangles, 64)
        assert_equal(result.retained_triangles, 64)
        assert_equal(result.minimum_triangles, 64)
        assert_equal(result.small_source_triangles, 0)
        assert_equal(result.protected_triangles, 0)
        assert_true(result.target_met())
        for reason in [
            MINIMUM_SHARES,
            SMALL_WELDED_SOURCES,
            SAFE_COLLAPSE_LIMIT,
        ]:
            assert_false(result.has_reason(reason))


def test_budget_result_reports_infeasible_minima() raises:
    var assets = Assets()
    var scene = Scene()
    var node = scene.add(Object3D())
    var first = assets.geometries.add(_fan(33))
    var second = assets.geometries.add(_fan(33))
    scene.add_mesh(Mesh(first, MaterialId(0), node))
    scene.add_mesh(Mesh(second, MaterialId(0), node))
    var result = fit_triangle_budget_result(scene, assets, 0, 63)
    assert_equal(result.requested_triangles, 63)
    assert_equal(result.retained_triangles, 64)
    assert_equal(result.minimum_triangles, 64)
    assert_false(result.target_met())
    assert_true(result.has_reason(MINIMUM_SHARES))
    assert_false(result.has_reason(SMALL_WELDED_SOURCES))
    assert_false(result.has_reason(SAFE_COLLAPSE_LIMIT))


def test_budget_result_reports_protected_topology_and_overlapping_reasons() raises:
    for budget in [31, 32, 33]:  # pragma: no branch
        var assets = Assets()
        var scene = Scene()
        var node = scene.add(Object3D())
        var id = assets.geometries.add(_protected_faces(33))
        scene.add_mesh(Mesh(id, MaterialId(0), node))
        var result = fit_triangle_budget_result(scene, assets, 0, budget)
        assert_equal(assets.geometries.get(id).triangle_count(), 33)
        assert_equal(result.requested_triangles, budget)
        assert_equal(result.retained_triangles, 33)
        assert_equal(result.minimum_triangles, 32)
        assert_equal(result.target_met(), budget == 33)
        assert_equal(result.has_reason(MINIMUM_SHARES), budget == 31)
        assert_false(result.has_reason(SMALL_WELDED_SOURCES))
        assert_equal(result.has_reason(SAFE_COLLAPSE_LIMIT), budget < 33)


def test_budget_result_uses_small_welded_sources_and_preserves_them() raises:
    for budget in [1, 3]:  # pragma: no branch
        var assets = Assets()
        var scene = Scene()
        var node = scene.add(Object3D())
        var geometry = _fan(3)
        # Thirty degenerate faces disappear in welding, leaving three.
        for _ in range(30):  # pragma: no branch
            geometry.index.append(0)
            geometry.index.append(0)
            geometry.index.append(1)
        assert_equal(geometry.triangle_count(), 33)
        var id = assets.geometries.add(geometry^)
        scene.add_mesh(Mesh(id, MaterialId(0), node))
        scene.add_mesh(Mesh(id, MaterialId(0), node))
        if budget == 1:
            var before = assets.geometries.get(id).clone()
            with assert_raises(contains="small welded sources 3"):
                _ = fit_triangle_budget_result(
                    scene, assets, 0, budget, mode=STRICT
                )
            _assert_same_geometry(assets.geometries.get(id), before)
        var result = fit_triangle_budget_result(scene, assets, 0, budget)
        assert_equal(assets.geometries.get(id).triangle_count(), 3)
        assert_equal(result.requested_triangles, budget)
        assert_equal(result.retained_triangles, 3)
        assert_equal(result.minimum_triangles, 3)
        assert_equal(result.small_source_triangles, 3)
        assert_equal(result.protected_triangles, 0)
        assert_equal(result.target_met(), budget == 3)
        assert_equal(result.has_reason(MINIMUM_SHARES), budget == 1)
        assert_equal(result.has_reason(SMALL_WELDED_SOURCES), budget == 1)
        assert_false(result.has_reason(SAFE_COLLAPSE_LIMIT))


def test_strict_budget_commits_only_a_met_target() raises:
    for workers in [1, 3]:  # pragma: no branch
        var assets = Assets()
        var scene = Scene()
        var node = scene.add(Object3D())
        var id = assets.geometries.add(_fan(33))
        scene.add_mesh(Mesh(id, MaterialId(0), node))
        var result = fit_triangle_budget_result(
            scene, assets, 0, 32, workers, STRICT
        )
        assert_true(result.target_met())
        assert_equal(result.retained_triangles, 32)
        assert_equal(assets.geometries.get(id).triangle_count(), 32)


def _assert_same_geometry(
    actual: BufferGeometry, expected: BufferGeometry
) raises:
    """Check indices and position, normal and texture-coordinate data."""
    assert_equal(actual.index, expected.index)
    for name in [String(POSITION), String(NORMAL), String(UV)]:
        assert_equal(actual.has_attribute(name), expected.has_attribute(name))
        if expected.has_attribute(name):
            assert_equal(
                actual.attribute_view(name).data,
                expected.attribute_view(name).data,
            )


def test_strict_failure_keeps_all_original_shared_assets() raises:
    for workers in [1, 3]:  # pragma: no branch
        for budget in [1, 64]:  # pragma: no branch
            var assets = Assets()
            var scene = Scene()
            var node = scene.add(Object3D())
            var first = assets.geometries.add(_fan(33))
            var second = assets.geometries.add(_protected_faces(33))
            var before_first = assets.geometries.get(first).clone()
            var before_second = assets.geometries.get(second).clone()
            scene.add_mesh(Mesh(first, MaterialId(0), node))
            scene.add_mesh(Mesh(second, MaterialId(0), node))
            scene.add_mesh(Mesh(first, MaterialId(0), node))
            with assert_raises(contains="retained 65"):
                _ = fit_triangle_budget_result(
                    scene, assets, 0, budget, workers, STRICT
                )
            _assert_same_geometry(assets.geometries.get(first), before_first)
            _assert_same_geometry(assets.geometries.get(second), before_second)
            assert_equal(scene.meshes[0].geometry, scene.meshes[2].geometry)


def test_conversion_failure_keeps_all_original_shared_assets() raises:
    var assets = Assets()
    var scene = Scene()
    var node = scene.add(Object3D())
    var first = assets.geometries.add(_fan(33))
    var second = assets.geometries.add(_fan(34))
    var before_first = assets.geometries.get(first).clone()
    var before_second = assets.geometries.get(second).clone()
    scene.add_mesh(Mesh(first, MaterialId(0), node))
    scene.add_mesh(Mesh(second, MaterialId(0), node))
    scene.add_mesh(Mesh(first, MaterialId(0), node))
    var meshes = List[WeldedMesh]()
    meshes.append(_read_mesh(_fan(32)))
    # A partial trailing face reaches set_index, which refuses conversion.
    # Inject it at the internal conversion boundary: valid public inputs
    # cannot produce a partial face after welding or edge collapse.
    meshes.append(WeldedMesh([Vector3(0, 0, 0)], List[Float32](), [0]))
    with assert_raises(contains="whole triangles"):
        _replace_budget_meshes(assets, [first, second], meshes)
    _assert_same_geometry(assets.geometries.get(first), before_first)
    _assert_same_geometry(assets.geometries.get(second), before_second)
    assert_equal(scene.meshes[0].geometry, scene.meshes[2].geometry)


def test_budget_result_empty_range_and_invalid_typed_values() raises:
    var assets = Assets()
    var scene = Scene()
    assert_true(BEST_EFFORT.is_valid())
    assert_true(STRICT.is_valid())
    assert_false(TriangleBudgetMode(-1).is_valid())
    assert_false(TriangleBudgetMode(2).is_valid())
    for mode in [BEST_EFFORT, STRICT]:  # pragma: no branch
        var result = fit_triangle_budget_result(scene, assets, 0, 1, 3, mode)
        assert_equal(result.requested_triangles, 1)
        assert_equal(result.retained_triangles, 0)
        assert_equal(result.minimum_triangles, 0)
        assert_equal(result.small_source_triangles, 0)
        assert_equal(result.protected_triangles, 0)
        assert_true(result.target_met())
        for reason in [
            MINIMUM_SHARES,
            SMALL_WELDED_SOURCES,
            SAFE_COLLAPSE_LIMIT,
        ]:
            assert_true(reason.is_valid())
            assert_false(result.has_reason(reason))
        for value in [-1, 3]:  # pragma: no branch
            assert_false(TriangleBudgetReason(value).is_valid())
            with assert_raises(contains="reason must be a named value"):
                _ = result.has_reason(TriangleBudgetReason(value))
    for value in [-1, 2]:  # pragma: no branch
        with assert_raises(contains="mode must be best effort or strict"):
            _ = fit_triangle_budget_result(
                scene, assets, 0, 1, mode=TriangleBudgetMode(value)
            )


def test_budget_result_does_not_recreate_faces_removed_by_welding() raises:
    var assets = Assets()
    var scene = Scene()
    var node = scene.add(Object3D())
    # Six distinct vertices, but every indexed face repeats a vertex.
    var geometry = _loose(
        [
            0,
            0,
            0,
            1,
            0,
            0,
            2,
            0,
            0,
            3,
            0,
            0,
            4,
            0,
            0,
            5,
            0,
            0,
        ]
    )
    geometry.set_attribute(
        String(UV), BufferAttribute(List[Float32](length=12, fill=0), 2)
    )
    geometry.set_attribute(
        String("color"), BufferAttribute(List[Float32](length=18, fill=1), 3)
    )
    geometry.add_group(0, 9)
    geometry.set_index([0, 0, 1, 2, 2, 3, 4, 4, 5])
    var id = assets.geometries.add(geometry^)
    scene.add_mesh(Mesh(id, MaterialId(0), node))
    var result = fit_triangle_budget_result(scene, assets, 0, 1, mode=STRICT)
    assert_equal(result.retained_triangles, 0)
    assert_equal(result.minimum_triangles, 0)
    assert_true(result.target_met())
    assert_equal(assets.geometries.get(id).triangle_count(), 0)
    assert_equal(assets.geometries.get(id).vertex_count(), 0)
    assert_equal(
        assets.geometries.get(id).attribute_view(String(NORMAL)).count(), 0
    )
    assert_false(assets.geometries.get(id).has_attribute(String("color")))
    assert_equal(len(assets.geometries.get(id).groups), 0)
    assert_equal(
        assets.geometries.get(id).attribute_view(String(UV)).count(), 0
    )


def test_budget_result_counts_only_selected_unique_geometries() raises:
    var assets = Assets()
    var scene = Scene()
    var node = scene.add(Object3D())
    var ignored = assets.geometries.add(_fan(34))
    var shared = assets.geometries.add(_fan(33))
    var later = assets.geometries.add(_fan(33))
    scene.add_mesh(Mesh(ignored, MaterialId(0), node))
    scene.add_mesh(Mesh(shared, MaterialId(0), node))
    scene.add_mesh(Mesh(later, MaterialId(0), node))
    scene.add_mesh(Mesh(shared, MaterialId(0), node))
    var result = fit_triangle_budget_result(scene, assets, 2, 64)
    assert_equal(result.retained_triangles, 64)
    assert_equal(result.minimum_triangles, 64)
    assert_equal(assets.geometries.get(ignored).triangle_count(), 34)
    assert_equal(assets.geometries.get(shared).triangle_count(), 32)
    assert_equal(assets.geometries.get(later).triangle_count(), 32)


def test_budget_result_can_meet_total_despite_a_protected_share() raises:
    var assets = Assets()
    var scene = Scene()
    var node = scene.add(Object3D())
    var geometry = _protected_faces(33)
    geometry.set_attribute(
        String(POSITION),
        BufferAttribute(
            [
                0,
                0,
                0,
                0.01,
                0,
                0,
                0,
                0.01,
                0,
            ],
            3,
        ),
    )
    var protected = assets.geometries.add(geometry^)
    var ball = assets.geometries.add(_ball(8))
    scene.add_mesh(Mesh(protected, MaterialId(0), node))
    scene.add_mesh(Mesh(ball, MaterialId(0), node))
    var result = fit_triangle_budget_result(scene, assets, 0, 65, mode=STRICT)
    assert_equal(assets.geometries.get(protected).triangle_count(), 33)
    assert_equal(assets.geometries.get(ball).triangle_count(), 32)
    assert_equal(result.retained_triangles, 65)
    assert_equal(result.protected_triangles, 1)
    assert_true(result.target_met())
    assert_false(result.has_reason(SAFE_COLLAPSE_LIMIT))


def test_budget_input_failure_does_not_replace_an_earlier_geometry() raises:
    var assets = Assets()
    var scene = Scene()
    var node = scene.add(Object3D())
    var first = assets.geometries.add(_fan(33))
    var invalid = assets.geometries.add(BufferGeometry())
    var before = assets.geometries.get(first).clone()
    scene.add_mesh(Mesh(first, MaterialId(0), node))
    scene.add_mesh(Mesh(invalid, MaterialId(0), node))
    with assert_raises():
        _ = fit_triangle_budget_result(scene, assets, 0, 32, mode=STRICT)
    _assert_same_geometry(assets.geometries.get(first), before)
    assert_false(assets.geometries.get(invalid).has_attribute(String(POSITION)))


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
