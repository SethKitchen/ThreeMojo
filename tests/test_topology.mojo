# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Tests for `extensions.topology`: the welder, the arrangement, the cell
complex and the storey stack.

The references are areas and volumes of rectangles and boxes, and the
closedness check of every cell.
"""

from std.math import inf, nan
from std.testing import (
    TestSuite,
    assert_almost_equal,
    assert_equal,
    assert_false,
    assert_raises,
    assert_true,
)
from extensions.topology.arrangement import (
    Point2,
    Region,
    arrange,
    contains,
    polygon_area,
)
from extensions.topology.complex import (
    CellComplex,
    FaceKind,
    HORIZONTAL,
    VERTICAL,
)
from extensions.topology.ids import (
    CellId,
    EdgeId,
    FaceId,
    NO_REGION,
    RegionId,
    VertexId,
)
from extensions.topology.loops import split_bridged, vector_area
from extensions.topology.storeys import build_storeys
from extensions.topology.weld import Welder
from generators.utils import Vec3d
from units.si import Length64, METER


def _tol() -> Length64:
    return Length64(1e-6, METER)


def _rect(
    layer: Int, id: Int, x0: Float64, y0: Float64, x1: Float64, y1: Float64
) -> Region:
    var points: List[Point2] = [
        Point2(x0, y0),
        Point2(x1, y0),
        Point2(x1, y1),
        Point2(x0, y1),
    ]
    return Region(layer, RegionId(id), points^)


def _levels(var heights: List[Float64]) -> List[Length64]:
    var out = List[Length64]()
    for i in range(len(heights)):
        out.append(Length64(heights[i], METER))
    return out^


# --- ids ---------------------------------------------------------------------


def test_ids_are_valid_from_zero() raises:
    assert_true(VertexId(0).is_valid())
    assert_false(VertexId(-1).is_valid())
    assert_true(EdgeId(3).is_valid())
    assert_false(EdgeId(-2).is_valid())
    assert_true(FaceId(1).is_valid())
    assert_false(FaceId(-1).is_valid())
    assert_true(CellId(0).is_valid())
    assert_false(CellId(-1).is_valid())
    assert_true(RegionId(7).is_valid())
    assert_false(NO_REGION.is_valid())
    assert_true(VERTICAL.is_valid())
    assert_true(HORIZONTAL.is_valid())
    assert_false(FaceKind(2).is_valid())
    assert_false(FaceKind(-1).is_valid())


# --- welder ------------------------------------------------------------------


def test_welder_merges_close_points() raises:
    var w = Welder(1.0)
    assert_equal(w.weld(Vec3d(0.5, 0, 0)), 0)
    assert_equal(w.weld(Vec3d(0.9, 0.2, 0)), 0)
    # In the next grid cell but farther than the tolerance.
    assert_equal(w.weld(Vec3d(1.8, 0, 0)), 1)
    assert_equal(w.find(Vec3d(50, 50, 50)), -1)
    assert_equal(len(w.points), 2)
    # A second point in the same cell.
    var v = Welder(10.0)
    _ = v.weld(Vec3d(1, 1, 1))
    assert_equal(v.weld(Vec3d(9, 9, 9)), 1)


def test_welder_refuses() raises:
    with assert_raises(contains="tolerance"):
        _ = Welder(0)
    with assert_raises(contains="tolerance"):
        _ = Welder(inf[DType.float64]())
    var w = Welder(1.0)
    with assert_raises(contains="finite"):
        _ = w.weld(Vec3d(nan[DType.float64](), 0, 0))
    with assert_raises(contains="finite"):
        _ = w.weld(Vec3d(0, inf[DType.float64](), 0))
    with assert_raises(contains="finite"):
        _ = w.weld(Vec3d(0, 0, nan[DType.float64]()))


# --- arrangement -------------------------------------------------------------


def test_polygon_helpers() raises:
    var square: List[Point2] = [
        Point2(0, 0),
        Point2(2, 0),
        Point2(2, 2),
        Point2(0, 2),
    ]
    assert_equal(polygon_area(square), 4)
    assert_true(contains(square, Point2(1, 1)))
    assert_false(contains(square, Point2(3, 1)))
    assert_false(contains(square, Point2(1, 3)))
    assert_equal(polygon_area(List[Point2]()), 0)
    assert_false(contains(List[Point2](), Point2(0, 0)))


def test_two_rooms_share_one_edge() raises:
    var regions = List[Region]()
    regions.append(_rect(0, 0, 0, 0, 4, 3))
    regions.append(_rect(0, 1, 4, 0, 8, 3))
    var a = arrange(regions, 1, _tol())
    assert_equal(len(a.faces), 2)
    assert_equal(len(a.points), 6)
    assert_equal(len(a.edges), 7)
    var total = Float64(0)
    for f in range(len(a.faces)):
        total += a.face_area(f)
    assert_almost_equal(total, 24, atol=1e-12)
    # The shared edge has a bounded face on each side.
    var shared = 0
    for e in range(len(a.edges)):
        if a.edges[e].left >= 0 and a.edges[e].right >= 0:
            shared += 1
            var left = a.faces[a.edges[e].left].labels[0].value
            var right = a.faces[a.edges[e].right].labels[0].value
            assert_true(left != right)
    assert_equal(shared, 1)


def test_a_t_junction_splits_the_long_edge() raises:
    var regions = List[Region]()
    regions.append(_rect(0, 0, 0, 0, 2, 1))
    regions.append(_rect(0, 1, 0, 1, 1, 2))
    regions.append(_rect(0, 2, 1, 1, 2, 2))
    var a = arrange(regions, 1, _tol())
    assert_equal(len(a.faces), 3)
    # (1, 1) is a vertex, so the bottom room's top edge is split.
    var found = False
    for i in range(len(a.points)):
        if a.points[i].x == 1 and a.points[i].y == 1:
            found = True
    assert_true(found)
    assert_equal(len(a.edges), 10)


def test_an_overlay_labels_each_face_per_layer() raises:
    var regions = List[Region]()
    regions.append(_rect(0, 5, 0, 0, 2, 2))
    regions.append(_rect(1, 9, 1, 1, 3, 3))
    var a = arrange(regions, 2, _tol())
    assert_equal(len(a.faces), 3)
    var both = 0
    var lower = 0
    var upper = 0
    for f in range(len(a.faces)):
        var l0 = a.faces[f].labels[0]
        var l1 = a.faces[f].labels[1]
        if l0.is_valid() and l1.is_valid():
            both += 1
            assert_almost_equal(a.face_area(f), 1, atol=1e-12)
        elif l0.is_valid():
            lower += 1
            assert_equal(l0.value, 5)
            assert_almost_equal(a.face_area(f), 3, atol=1e-12)
        else:
            upper += 1
            assert_equal(l1.value, 9)
    assert_equal(both, 1)
    assert_equal(lower, 1)
    assert_equal(upper, 1)


def test_an_enclosed_region_is_bridged() raises:
    var regions = List[Region]()
    regions.append(_rect(0, 0, 0, 0, 10, 10))
    regions.append(_rect(1, 1, 4, 4, 6, 6))
    var a = arrange(regions, 2, _tol())
    assert_equal(len(a.faces), 2)
    var areas = List[Float64]()
    for f in range(len(a.faces)):
        areas.append(a.face_area(f))
    assert_almost_equal(areas[0] + areas[1], 100, atol=1e-9)
    var ring = 0 if areas[0] > areas[1] else 1
    assert_almost_equal(areas[ring], 96, atol=1e-9)
    assert_false(a.faces[ring].labels[1].is_valid())
    assert_equal(a.faces[1 - ring].labels[1].value, 1)
    # Four edges per square and one bridge.
    assert_equal(len(a.edges), 9)


def test_a_ring_of_rooms_around_an_empty_court() raises:
    # Four rooms around an uncovered court, with an island room in it.
    var regions = List[Region]()
    regions.append(_rect(0, 0, 0, 0, 9, 3))
    regions.append(_rect(0, 1, 0, 6, 9, 9))
    regions.append(_rect(0, 2, 0, 3, 3, 6))
    regions.append(_rect(0, 3, 6, 3, 9, 6))
    regions.append(_rect(0, 4, 4, 4, 5, 5))
    var a = arrange(regions, 1, _tol())
    var uncovered = 0
    for f in range(len(a.faces)):
        if not a.faces[f].labels[0].is_valid():
            uncovered += 1
            assert_almost_equal(a.face_area(f), 8, atol=1e-9)
    assert_equal(uncovered, 1)


def test_arrange_refuses() raises:
    var regions = List[Region]()
    regions.append(_rect(0, 0, 0, 0, 2, 2))
    with assert_raises(contains="one layer or more"):
        _ = arrange(regions, 0, _tol())
    with assert_raises(contains="tolerance"):
        _ = arrange(regions, 1, Length64(0, METER))
    var bad_layer = List[Region]()
    bad_layer.append(_rect(1, 0, 0, 0, 2, 2))
    with assert_raises(contains="layer"):
        _ = arrange(bad_layer, 1, _tol())
    var negative_layer = List[Region]()
    negative_layer.append(_rect(-1, 0, 0, 0, 2, 2))
    with assert_raises(contains="layer"):
        _ = arrange(negative_layer, 1, _tol())
    var bad_id = List[Region]()
    bad_id.append(_rect(0, -1, 0, 0, 2, 2))
    with assert_raises(contains="id"):
        _ = arrange(bad_id, 1, _tol())
    var overlap = List[Region]()
    overlap.append(_rect(0, 0, 0, 0, 2, 2))
    overlap.append(_rect(0, 1, 1, 1, 3, 3))
    with assert_raises(contains="overlap"):
        _ = arrange(overlap, 1, _tol())


def _one(var points: List[Point2]) -> List[Region]:
    var out = List[Region]()
    out.append(Region(0, RegionId(0), points^))
    return out^


def test_arrange_refuses_bad_polygons() raises:
    var two: List[Point2] = [Point2(0, 0), Point2(1, 0)]
    with assert_raises(contains="three corners"):
        _ = arrange(_one(two^), 1, _tol())
    var nan_x: List[Point2] = [
        Point2(nan[DType.float64](), 0),
        Point2(1, 0),
        Point2(0, 1),
    ]
    with assert_raises(contains="finite"):
        _ = arrange(_one(nan_x^), 1, _tol())
    var inf_y: List[Point2] = [
        Point2(0, inf[DType.float64]()),
        Point2(1, 0),
        Point2(0, 1),
    ]
    with assert_raises(contains="finite"):
        _ = arrange(_one(inf_y^), 1, _tol())
    var short: List[Point2] = [
        Point2(0, 0),
        Point2(0, 0),
        Point2(1, 0),
        Point2(0, 1),
    ]
    with assert_raises(contains="longer than"):
        _ = arrange(_one(short^), 1, _tol())
    var flat: List[Point2] = [Point2(0, 0), Point2(1, 0), Point2(2, 0)]
    with assert_raises(contains="area"):
        _ = arrange(_one(flat^), 1, _tol())
    var bowtie: List[Point2] = [
        Point2(0, 0),
        Point2(4, 4),
        Point2(4, 0),
        Point2(0, 2),
    ]
    with assert_raises(contains="cross itself"):
        _ = arrange(_one(bowtie^), 1, _tol())
    # A corner that touches the middle of another edge.
    var touching: List[Point2] = [
        Point2(0, 0),
        Point2(4, 0),
        Point2(4, 4),
        Point2(2, 0),
        Point2(0, 4),
    ]
    with assert_raises(contains="touch itself"):
        _ = arrange(_one(touching^), 1, _tol())
    # Another edge's corner on the first edge, seen from the other side.
    var touching_back: List[Point2] = [
        Point2(2, 0),
        Point2(4, 4),
        Point2(0, 4),
        Point2(0, 0),
        Point2(4, 0),
    ]
    with assert_raises(contains="itself"):
        _ = arrange(_one(touching_back^), 1, _tol())


def test_a_clockwise_l_shape_arranges() raises:
    # Clockwise input, and a concave corner the ear search must skip.
    var l_shape: List[Point2] = [
        Point2(0, 0),
        Point2(0, 4),
        Point2(1, 4),
        Point2(1, 1),
        Point2(4, 1),
        Point2(4, 0),
    ]
    var a = arrange(_one(l_shape^), 1, _tol())
    assert_equal(len(a.faces), 1)
    assert_almost_equal(a.face_area(0), 7, atol=1e-12)
    assert_equal(a.faces[0].labels[0].value, 0)


def test_crossing_edges_meet_at_a_new_vertex() raises:
    var regions = List[Region]()
    regions.append(_rect(0, 0, 0, 0, 4, 2))
    var diamond: List[Point2] = [
        Point2(2, -1),
        Point2(3, 1),
        Point2(2, 3),
        Point2(1, 1),
    ]
    regions.append(Region(1, RegionId(0), diamond^))
    var a = arrange(regions, 2, _tol())
    var area = Float64(0)
    for f in range(len(a.faces)):
        area += a.face_area(f)
    # The union: the rectangle plus two tips of half a square meter.
    assert_almost_equal(area, 8 + 0.5 + 0.5, atol=1e-9)


# --- cell complex ------------------------------------------------------------


def test_complex_queries_on_a_box() raises:
    var c = CellComplex(1e-6)
    var cell = c.add_cell()
    var p = List[VertexId]()
    for i in range(8):
        var x = Float64(i & 1)
        var y = Float64((i >> 1) & 1)
        var z = Float64(i >> 2)
        p.append(c.add_vertex(Vec3d(x * 2, y * 3, z * 4)))
    # Outward normals; the cell is behind each face.
    var quads: List[List[Int]] = [
        [0, 2, 3, 1],
        [4, 5, 7, 6],
        [0, 1, 5, 4],
        [2, 6, 7, 3],
        [0, 4, 6, 2],
        [1, 3, 7, 5],
    ]
    for q in range(6):
        var loop = List[VertexId]()
        for k in range(4):
            loop.append(p[quads[q][k]])
        var kind = HORIZONTAL if q < 2 else VERTICAL
        _ = c.add_face(loop^, None, cell, kind)
    c.validate()
    assert_equal(c.cell_count(), 1)
    assert_equal(c.vertex_count(), 8)
    assert_equal(len(c.edges), 12)
    assert_almost_equal(c.cell_volume(cell), 24, atol=1e-12)
    assert_almost_equal(c.face_area(FaceId(0)), 6, atol=1e-12)
    var n = c.face_normal(FaceId(0))
    assert_almost_equal(n.z, -1, atol=1e-12)
    var out = c.outward_normal(FaceId(1), cell)
    assert_almost_equal(out.z, 1, atol=1e-12)
    var mid = c.face_centroid(FaceId(1))
    assert_almost_equal(mid.z, 4, atol=1e-12)
    assert_equal(len(c.exterior_faces(cell)), 6)
    assert_equal(len(c.neighbors(cell)), 0)
    assert_equal(c.vertex(p[7]).y, 3)


def test_complex_refuses() raises:
    var c = CellComplex(1e-6)
    var cell = c.add_cell()
    var a = c.add_vertex(Vec3d(0, 0, 0))
    var b = c.add_vertex(Vec3d(1, 0, 0))
    var d = c.add_vertex(Vec3d(0, 1, 0))
    var two: List[VertexId] = [a, b]
    with assert_raises(contains="three corners"):
        _ = c.add_face(two^, cell, None, HORIZONTAL)
    var repeated: List[VertexId] = [a, b, b]
    with assert_raises(contains="repeat"):
        _ = c.add_face(repeated^, cell, None, HORIZONTAL)
    var outside: List[VertexId] = [a, b, VertexId(9)]
    with assert_raises(contains="vertex id"):
        _ = c.add_face(outside^, cell, None, HORIZONTAL)
    var negative: List[VertexId] = [a, b, VertexId(-1)]
    with assert_raises(contains="vertex id"):
        _ = c.add_face(negative^, cell, None, HORIZONTAL)
    var tri: List[VertexId] = [a, b, d]
    with assert_raises(contains="cell id"):
        _ = c.add_face(tri.copy(), CellId(4), None, HORIZONTAL)
    with assert_raises(contains="cell id"):
        _ = c.add_face(tri.copy(), None, CellId(-1), HORIZONTAL)
    with assert_raises(contains="both sides"):
        _ = c.add_face(tri.copy(), cell, cell, HORIZONTAL)
    with assert_raises(contains="kind"):
        _ = c.add_face(tri.copy(), cell, None, FaceKind(5))
    var f = c.add_face(tri.copy(), cell, None, HORIZONTAL)
    var other = c.add_cell()
    with assert_raises(contains="either side"):
        _ = c.other_side(f, other)
    with assert_raises(contains="either side"):
        _ = c.outward_normal(f, other)
    with assert_raises(contains="face id"):
        _ = c.face_points(FaceId(3))
    with assert_raises(contains="face id"):
        _ = c.face_points(FaceId(-1))
    with assert_raises(contains="cell id"):
        _ = c.faces_of(CellId(9))
    with assert_raises(contains="cell id"):
        _ = c.shared_faces(cell, CellId(9))
    with assert_raises(contains="vertex id"):
        _ = c.vertex(VertexId(9))
    with assert_raises(contains="tolerance"):
        _ = CellComplex(0)
    # One triangle is not a closed cell.
    with assert_raises(contains="not closed"):
        c.validate()


def test_validate_refuses_a_face_used_twice() raises:
    var c = CellComplex(1e-6)
    var cell = c.add_cell()
    var a = c.add_vertex(Vec3d(0, 0, 0))
    var b = c.add_vertex(Vec3d(1, 0, 0))
    var d = c.add_vertex(Vec3d(0, 1, 0))
    var tri: List[VertexId] = [a, b, d]
    _ = c.add_face(tri.copy(), cell, None, HORIZONTAL)
    _ = c.add_face(tri.copy(), cell, None, HORIZONTAL)
    with assert_raises(contains="twice"):
        c.validate()


# --- storeys -----------------------------------------------------------------


def test_one_storey_with_two_rooms() raises:
    var plan = List[Region]()
    plan.append(_rect(0, 0, 0, 0, 4, 3))
    plan.append(_rect(0, 1, 4, 0, 8, 3))
    var plans = List[List[Region]]()
    plans.append(plan^)
    var s = build_storeys(_levels([0.0, 3.0]), plans, _tol())
    s.complex.validate()
    var a = s.cell_of(0, RegionId(0)).value()
    var b = s.cell_of(0, RegionId(1)).value()
    assert_false(s.cell_of(0, RegionId(7)))
    assert_false(s.cell_of(1, RegionId(0)))
    assert_almost_equal(s.complex.cell_volume(a), 36, atol=1e-9)
    assert_almost_equal(s.complex.cell_volume(b), 36, atol=1e-9)
    var shared = s.complex.shared_faces(a, b)
    assert_equal(len(shared), 1)
    assert_almost_equal(s.complex.face_area(shared[0]), 9, atol=1e-9)
    assert_true(s.complex.faces[shared[0].value].kind == VERTICAL)
    var n = s.complex.neighbors(a)
    assert_equal(len(n), 1)
    assert_true(n[0] == b)
    # Three outside walls, the ground and the roof.
    assert_equal(len(s.complex.exterior_faces(a)), 5)
    assert_equal(len(s.face_level), len(s.complex.faces))


def test_a_stack_with_different_plans_is_watertight() raises:
    var plans = List[List[Region]]()
    var ground = List[Region]()
    ground.append(_rect(0, 0, 0, 0, 4, 4))
    ground.append(_rect(0, 1, 4, 0, 8, 4))
    plans.append(ground^)
    var first = List[Region]()
    first.append(_rect(0, 0, 0, 0, 8, 4))
    plans.append(first^)
    var crown = List[Region]()
    crown.append(_rect(0, 3, 2, 1, 6, 3))
    plans.append(crown^)
    var s = build_storeys(_levels([0.0, 3.0, 6.0, 9.0]), plans, _tol())
    s.complex.validate()
    var hall = s.cell_of(1, RegionId(0)).value()
    var neighbors = s.complex.neighbors(hall)
    assert_equal(len(neighbors), 3)
    assert_almost_equal(s.complex.cell_volume(hall), 96, atol=1e-9)
    var top = s.cell_of(2, RegionId(3)).value()
    assert_almost_equal(s.complex.cell_volume(top), 24, atol=1e-9)
    # The hall's south wall bottom edge carries the vertex at x = 4.
    var a = s.cell_of(0, RegionId(0)).value()
    var floor = s.complex.shared_faces(a, hall)
    assert_equal(len(floor), 1)
    assert_true(s.complex.faces[floor[0].value].kind == HORIZONTAL)
    assert_equal(s.face_level[floor[0].value], 1)
    # The roof around the crown is exterior.
    var roof_area = Float64(0)
    var faces = s.complex.exterior_faces(hall)
    for i in range(len(faces)):
        if s.complex.faces[faces[i].value].kind == HORIZONTAL:
            roof_area += s.complex.face_area(faces[i])
    assert_almost_equal(roof_area, 32 - 8, atol=1e-9)


def test_an_empty_court_has_no_walls_of_its_own() raises:
    var plan = List[Region]()
    plan.append(_rect(0, 0, 0, 0, 9, 3))
    plan.append(_rect(0, 1, 0, 6, 9, 9))
    plan.append(_rect(0, 2, 0, 3, 3, 6))
    plan.append(_rect(0, 3, 6, 3, 9, 6))
    plan.append(_rect(0, 4, 4, 4, 5, 5))
    var plans = List[List[Region]]()
    plans.append(plan^)
    var s = build_storeys(_levels([0.0, 3.0]), plans, _tol())
    s.complex.validate()
    var island = s.cell_of(0, RegionId(4)).value()
    assert_equal(len(s.complex.exterior_faces(island)), 6)
    assert_almost_equal(s.complex.cell_volume(island), 3, atol=1e-9)


def test_build_storeys_refuses() raises:
    var plans = List[List[Region]]()
    var plan = List[Region]()
    plan.append(_rect(0, 0, 0, 0, 1, 1))
    plans.append(plan.copy())
    with assert_raises(contains="one more level"):
        _ = build_storeys(_levels([0.0]), plans, _tol())
    with assert_raises(contains="increase"):
        _ = build_storeys(_levels([1.0, 1.0]), plans, _tol())
    with assert_raises(contains="finite"):
        _ = build_storeys(_levels([0.0, inf[DType.float64]()]), plans, _tol())
    var layered = List[List[Region]]()
    var high = List[Region]()
    high.append(_rect(1, 0, 0, 0, 1, 1))
    layered.append(high^)
    with assert_raises(contains="layer zero"):
        _ = build_storeys(_levels([0.0, 1.0]), layered, _tol())
    var repeated = List[List[Region]]()
    var twice = List[Region]()
    twice.append(_rect(0, 0, 0, 0, 1, 1))
    twice.append(_rect(0, 0, 1, 0, 2, 1))
    repeated.append(twice^)
    with assert_raises(contains="repeat"):
        _ = build_storeys(_levels([0.0, 1.0]), repeated, _tol())
    var empty = List[List[Region]]()
    var nothing = build_storeys(_levels([0.0]), empty, _tol())
    assert_equal(nothing.complex.cell_count(), 0)
    assert_false(nothing.cell_of(0, RegionId(0)))


# --- edge cases --------------------------------------------------------------


def test_an_empty_arrangement() raises:
    var a = arrange(List[Region](), 1, _tol())
    assert_equal(len(a.faces), 0)
    assert_equal(len(a.points), 0)


def test_corners_within_the_tolerance_weld() raises:
    # The second room starts half a tolerance inside the first.
    var regions = List[Region]()
    regions.append(_rect(0, 0, 0, 0, 4, 3))
    regions.append(_rect(0, 1, 4 - 5e-7, 0, 8, 3))
    var a = arrange(regions, 1, _tol())
    assert_equal(len(a.faces), 2)
    assert_equal(len(a.points), 6)


def test_a_notched_room_finds_an_inside_point() raises:
    # Three corners of the notch lie inside the lowest-left corner's
    # triangle.
    var notch: List[Point2] = [
        Point2(0, 0),
        Point2(10, 0),
        Point2(10, 10),
        Point2(7, 1),
        Point2(5, 3),
        Point2(3, 2),
        Point2(0, 10),
    ]
    var regions = List[Region]()
    regions.append(Region(0, RegionId(4), notch^))
    var a = arrange(regions, 1, _tol())
    assert_equal(len(a.faces), 1)
    assert_equal(a.faces[0].labels[0].value, 4)


def test_complex_queries_on_cells_without_faces() raises:
    var c = CellComplex(1e-6)
    c.validate()
    var empty = c.add_cell()
    assert_equal(len(c.neighbors(empty)), 0)
    assert_equal(len(c.exterior_faces(empty)), 0)
    assert_equal(len(c.shared_faces(empty, empty)), 0)
    assert_equal(c.cell_volume(empty), 0)
    c.validate()


def test_complex_sides_from_the_positive_cell() raises:
    var c = CellComplex(1e-6)
    var below = c.add_cell()
    var above = c.add_cell()
    var third = c.add_cell()
    var a = c.add_vertex(Vec3d(0, 0, 0))
    var b = c.add_vertex(Vec3d(1, 0, 0))
    var d = c.add_vertex(Vec3d(0, 1, 0))
    var tri: List[VertexId] = [a, b, d]
    var f = c.add_face(tri^, above, below, HORIZONTAL)
    assert_true(c.other_side(f, above).value() == below)
    assert_true(c.other_side(f, below).value() == above)
    assert_almost_equal(c.outward_normal(f, above).z, -1, atol=1e-12)
    assert_almost_equal(c.outward_normal(f, below).z, 1, atol=1e-12)
    with assert_raises(contains="either side"):
        _ = c.other_side(f, third)


def test_rooms_that_share_two_walls_are_one_neighbor() raises:
    var plan = List[Region]()
    plan.append(_rect(0, 0, 0, 0, 2, 2))
    var wrap: List[Point2] = [
        Point2(2, 0),
        Point2(4, 0),
        Point2(4, 4),
        Point2(0, 4),
        Point2(0, 2),
        Point2(2, 2),
    ]
    plan.append(Region(0, RegionId(1), wrap^))
    var plans = List[List[Region]]()
    plans.append(plan^)
    var s = build_storeys(_levels([0.0, 3.0]), plans, _tol())
    s.complex.validate()
    var a = s.cell_of(0, RegionId(0)).value()
    var b = s.cell_of(0, RegionId(1)).value()
    assert_equal(len(s.complex.shared_faces(a, b)), 2)
    assert_equal(len(s.complex.neighbors(a)), 1)


def test_partitions_above_split_the_wall_tops_below() raises:
    var plans = List[List[Region]]()
    var hall = List[Region]()
    hall.append(_rect(0, 0, 0, 0, 8, 4))
    plans.append(hall^)
    var rooms = List[Region]()
    rooms.append(_rect(0, 0, 0, 0, 3, 4))
    rooms.append(_rect(0, 1, 3, 0, 5, 4))
    rooms.append(_rect(0, 2, 5, 0, 8, 4))
    plans.append(rooms.copy())
    var empty = List[Region]()
    plans.append(empty^)
    plans.append(rooms^)
    var hall_top = List[Region]()
    hall_top.append(_rect(0, 0, 0, 0, 8, 4))
    plans.append(hall_top^)
    var s = build_storeys(
        _levels([0.0, 3.0, 6.0, 9.0, 12.0, 15.0]), plans, _tol()
    )
    s.complex.validate()
    assert_false(s.cell_of(2, RegionId(0)))
    var middle = s.cell_of(3, RegionId(1)).value()
    assert_almost_equal(s.complex.cell_volume(middle), 24, atol=1e-9)
    var top = s.cell_of(4, RegionId(0)).value()
    # Three floor faces under the top hall.
    var floors = 0
    var faces = s.complex.faces_of(top)
    for i in range(len(faces)):
        if s.complex.faces[faces[i].value].kind == HORIZONTAL:
            if s.face_level[faces[i].value] == 4:
                floors += 1
    assert_equal(floors, 3)


def test_split_bridged_loops() raises:
    # A square with a square hole, joined by a bridge from (0, 0) to (1, 1).
    var loop: List[Vec3d] = [
        Vec3d(0, 0, 0),
        Vec3d(1, 1, 0),
        Vec3d(1, 2, 0),
        Vec3d(2, 2, 0),
        Vec3d(2, 1, 0),
        Vec3d(1, 1, 0),
        Vec3d(0, 0, 0),
        Vec3d(3, 0, 0),
        Vec3d(3, 3, 0),
        Vec3d(0, 3, 0),
    ]
    var parts = split_bridged(loop)
    assert_equal(len(parts.outer), 4)
    assert_equal(len(parts.holes), 1)
    assert_almost_equal(vector_area(parts.outer).z, 9, atol=1e-12)
    assert_almost_equal(vector_area(parts.holes[0]).z, -1, atol=1e-12)
    # Without a bridge, the loop is its own outer ring.
    var square: List[Vec3d] = [
        Vec3d(0, 0, 0),
        Vec3d(1, 0, 0),
        Vec3d(1, 1, 0),
        Vec3d(0, 1, 0),
    ]
    assert_equal(len(split_bridged(square).outer), 4)
    # Two islands winding the same way: the second becomes a hole entry.
    var islands: List[Vec3d] = [
        Vec3d(0, 0, 0),
        Vec3d(1, 0, 0),
        Vec3d(1, 1, 0),
        Vec3d(0, 1, 0),
        Vec3d(0, 0, 0),
        Vec3d(5, 0, 0),
        Vec3d(6, 0, 0),
        Vec3d(6, 1, 0),
        Vec3d(5, 1, 0),
        Vec3d(5, 0, 0),
    ]
    var both = split_bridged(islands)
    assert_equal(len(both.holes), 1)
    with assert_raises(contains="three corners"):
        _ = split_bridged([Vec3d(0, 0, 0), Vec3d(1, 0, 0)])
    assert_equal(vector_area(List[Vec3d]()).z, 0)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
