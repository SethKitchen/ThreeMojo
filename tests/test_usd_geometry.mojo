# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Tests for `loaders.usd_geometry`: faces cut into triangles, and a
mesh's attributes laid out as three.js r186's `USDComposer` lays them out,
with its groups for subsets. `tests/test_usd.mojo` compares whole meshes
with three.js."""

from core.buffer_geometry import NORMAL, POSITION, UV, UV1, BufferGeometry
from loaders.usd_geometry import (
    MAX_CORNERS,
    HoleMap,
    UsdArray,
    UsdMeshArrays,
    apply_pattern,
    build_hole_map,
    build_usd_geometry,
    build_usd_geometry_with_subsets,
    compute_vertex_normals,
    expand_attribute,
    triangulate_ngon,
    triangulate_ngon_with_holes,
    triangulate_with_pattern,
    value_at,
)
from std.math import isnan
from std.testing import (
    TestSuite,
    assert_almost_equal,
    assert_equal,
    assert_false,
    assert_raises,
    assert_true,
)

comptime _NAN = Float64(0) / Float64(0)


def _same(got: List[Float64], want: List[Float64], what: String = "") raises:
    """Assert two lists of numbers are equal, NaN equal to NaN."""
    assert_equal(len(got), len(want), what + " length")
    for k in range(len(got)):
        if isnan(want[k]):
            assert_true(isnan(got[k]), what + " NaN at " + String(k))
        else:
            assert_almost_equal(got[k], want[k], atol=1e-6, msg=what)


def _attribute(geometry: BufferGeometry, name: String) raises -> List[Float64]:
    """Return an attribute's numbers."""
    var out = List[Float64]()
    for value in geometry.attribute_view(name).data:
        out.append(Float64(value))
    return out^


def _slice(values: List[Float64], start: Int, end: Int) -> List[Float64]:
    """Return part of a list."""
    var out = List[Float64]()
    for k in range(start, end):
        out.append(values[k])
    return out^


def _plus(a: List[Float64], b: List[Float64]) -> List[Float64]:
    """Return one list after another."""
    var out = a.copy()
    out.extend(b.copy())
    return out^


def _square() -> List[Float64]:
    """Return four points of a unit square in the xy plane."""
    return [0, 0, 0, 1, 0, 0, 1, 1, 0, 0, 1, 0]


def test_value_at() raises:
    var values: List[Float64] = [1, 2]
    assert_equal(value_at(values, 1), 2)
    assert_true(isnan(value_at(values, -1)))
    assert_true(isnan(value_at(values, 2)))
    assert_true(isnan(value_at(values, 0.5)))
    assert_true(isnan(value_at(values, _NAN)))


def test_hole_maps() raises:
    assert_equal(len(build_hole_map(UsdArray()).hole_faces), 0)
    assert_equal(len(build_hole_map(UsdArray(List[Float64]())).hole_faces), 0)
    # Two holes of one face, a hole of a NaN parent twice, and a last hole
    # with no parent, which is NaN too.
    var map = build_hole_map(UsdArray([1, 0, 2, 0, 3, _NAN, 4, 7, 5, _NAN, 6]))
    assert_equal(len(map.parents), 3)
    assert_true(map.is_hole(1))
    assert_false(map.is_hole(0))
    assert_equal(len(map.holes_of(0)), 2)
    assert_equal(len(map.holes_of(9)), 0)
    assert_equal(len(map.holes[1]), 3)
    assert_false(HoleMap().is_hole(0))


def test_triangles_and_quads() raises:
    var cut = triangulate_with_pattern(
        [0, 1, 2, 0, 1, 2, 3, 9], [3, 4, 1, 0], _square(), HoleMap()
    )
    _same(cut.indices, [0, 1, 2, 0, 1, 2, 0, 2, 3])
    _same(cut.pattern, [0, 1, 2, 3, 4, 5, 3, 5, 6])
    var empty = triangulate_with_pattern(
        List[Float64](), List[Float64](), List[Float64](), HoleMap()
    )
    assert_equal(len(empty.indices), 0)
    # A corner past the list is NaN.
    var short = triangulate_with_pattern([0, 1], [3], _square(), HoleMap())
    assert_true(isnan(short.indices[2]))


def test_ngons() raises:
    var pentagon: List[Float64] = [0, 0, 0, 2, 0, 0, 2, 2, 0, 1, 3, 0, 0, 2, 0]
    var cut = triangulate_with_pattern(
        [0, 1, 2, 3, 4], [5], pentagon, HoleMap()
    )
    assert_equal(len(cut.indices), 9)
    for k in range(9):
        assert_equal(cut.pattern[k], cut.indices[k])
    # A face in the xz plane projects on x and z.
    var flat: List[Float64] = [0, 0, 0, 0, 0, 2, 2, 0, 2, 3, 0, 1, 2, 0, 0]
    assert_equal(len(triangulate_ngon([0, 1, 2, 3, 4], flat)), 9)
    # With no points, a fan; a repeated corner is found where it is first.
    var fan = triangulate_with_pattern(
        [0, 1, 2, 3, 4], [5.5], List[Float64](), HoleMap()
    )
    _same(fan.indices, [0, 1, 2, 0, 2, 3, 0, 3, 4, 0, 4, _NAN])
    var repeated = triangulate_with_pattern(
        [0, 1, 2, 0, 3], [5], pentagon, HoleMap()
    )
    for k in range(len(repeated.indices)):
        if repeated.indices[k] == 0:
            assert_equal(repeated.pattern[k], 0)
    # A corner that is NaN is never found, as `indexOf` does not find it.
    var lost = triangulate_with_pattern([0, 1, 2, 3], [5], pentagon, HoleMap())
    var found_nan = False
    for k in range(len(lost.indices)):
        if isnan(lost.indices[k]):
            assert_equal(lost.pattern[k], -1)
            found_nan = True
    assert_true(found_nan)
    # Points all in one place have no normal to project on.
    var same: List[Float64] = [1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1]
    _ = triangulate_ngon([0, 1, 2, 3, 4], same)
    with assert_raises(contains="2^24"):
        _ = triangulate_with_pattern(
            [0], [Float64(MAX_CORNERS) + 1], _square(), HoleMap()
        )


def test_faces_with_holes() raises:
    var points: List[Float64] = [
        0, 0, 0, 4, 0, 0, 4, 4, 0, 0, 4, 0,
        1, 1, 0, 1, 3, 0, 3, 3, 0, 3, 1, 0,
    ]
    var holes = build_hole_map(UsdArray([1, 0]))
    var cut = triangulate_with_pattern(
        [0, 1, 2, 3, 4, 5, 6, 7], [4, 4], points, holes
    )
    assert_equal(len(cut.indices), 24)
    for k in range(24):
        assert_equal(cut.pattern[k], cut.indices[k])
    # With no points the holes are not cut out.
    var fan = triangulate_with_pattern(
        [0, 1, 2, 3, 4, 5, 6, 7], [4, 4], List[Float64](), holes
    )
    assert_equal(len(fan.indices), 6)
    # A face of no corners has no triangles.
    var none = triangulate_with_pattern(
        [0, 1, 2, 3], [0, 4], points, build_hole_map(UsdArray([1, 0]))
    )
    assert_equal(len(none.indices), 0)
    # Corners past the list are NaN, and a Map finds NaN by NaN.
    var lost = triangulate_with_pattern(
        [0, 1, 2], [4, 3], points, build_hole_map(UsdArray([1, 0]))
    )
    assert_equal(len(lost.indices) % 3, 0)
    # A corner after a NaN one is found past it; earcut's answer for NaN
    # points does not matter here.
    try:
        _ = triangulate_with_pattern(
            [0, 1, 2, _NAN, 4, 5, 6], [4, 3], points, build_hole_map(UsdArray([1, 0]))
        )
    except:
        pass
    # A hole that is no face is an empty contour, which earcut refuses as
    # three.js's does.
    with assert_raises():
        _ = triangulate_with_pattern(
            [0, 1, 2, 3], [4], points, build_hole_map(UsdArray([9, 0]))
        )
    var direct = triangulate_ngon_with_holes([0, 1, 2, 3], [[4, 5, 6, 7]], points)
    assert_equal(len(direct), 24)
    # A face whose corners lie on a line has no triangles.
    var line: List[Float64] = [0, 0, 0, 1, 0, 0, 2, 0, 0, 3, 0, 0, 0.5, 0, 0, 1.5, 0, 0]
    var flat = triangulate_with_pattern(
        [0, 1, 2, 3, 4, 5], [4, 2], line, build_hole_map(UsdArray([1, 0]))
    )
    assert_equal(len(flat.indices), 0)


def test_patterns_and_expansion() raises:
    _same(apply_pattern([5, 6], [1, 0, 3]), [6, 5, _NAN])
    assert_equal(len(apply_pattern([5], List[Float64]())), 0)
    _same(expand_attribute([1, 2, 3, 4], [1, _NAN], 2), [3, 4, _NAN, _NAN])
    assert_equal(len(expand_attribute([1], List[Float64](), 2)), 0)


def test_vertex_normals() raises:
    var normals = compute_vertex_normals(_square(), [0, 1, 2, 0, 2, 3])
    _same(normals, [0, 0, 1, 0, 0, 1, 0, 0, 1, 0, 0, 1])
    # A point no triangle touches keeps a zero normal; a corner that names
    # no point adds to nothing, and a partial triangle reads NaN.
    var odd = compute_vertex_normals(_square(), [0, 1, 2, -1, 0.5, 9, 0])
    assert_equal(odd[9], 0)
    assert_true(isnan(odd[0]))
    assert_equal(len(compute_vertex_normals(List[Float64](), List[Float64]())), 0)
    with assert_raises(contains="whole vertices"):
        _ = compute_vertex_normals([0, 1], List[Float64]())


def _quad() -> UsdMeshArrays:
    """Return a quad of one face."""
    var mesh = UsdMeshArrays()
    mesh.points = UsdArray(_square())
    mesh.indices = UsdArray([0, 1, 2, 3])
    mesh.counts = UsdArray([4])
    return mesh^


def test_geometry() raises:
    assert_equal(build_usd_geometry(UsdMeshArrays()).attribute_count(), 0)
    var mesh = _quad()
    mesh.normals = UsdArray([0, 0, 1])
    mesh.normal_indices = UsdArray([0, 0, 0, 0])
    mesh.uvs = UsdArray([0, 0, 1, 0, 1, 1, 0, 1])
    mesh.uv_indices = UsdArray([3, 2, 1, 0])
    mesh.uvs2 = UsdArray([0, 0, 1, 0, 1, 1, 0, 1])
    var geometry = build_usd_geometry(mesh)
    assert_equal(len(_attribute(geometry, String(POSITION))), 18)
    _same(_slice(_attribute(geometry, String(NORMAL)), 0, 3), [0, 0, 1])
    _same(_slice(_attribute(geometry, String(UV)), 0, 2), [0, 1])
    _same(_slice(_attribute(geometry, String(UV1)), 0, 2), [0, 0])


def test_geometry_normals() raises:
    # Normals for each point.
    var mesh = _quad()
    mesh.normals = UsdArray(_square())
    var geometry = build_usd_geometry(mesh)
    _same(_slice(_attribute(geometry, String(NORMAL)), 3, 6), [1, 0, 0])
    # For each face corner, with no indices of their own.
    mesh = _quad()
    mesh.normals = UsdArray([0, 0, 1, 0, 0, 2, 0, 0, 3, 0, 0, 4])
    mesh.points = UsdArray(_plus(_square(), [5, 5, 5]))
    geometry = build_usd_geometry(mesh)
    _same(_slice(_attribute(geometry, String(NORMAL)), 15, 18), [0, 0, 4])
    # Normal indices with no faces, and normals of no layout, as given.
    mesh = UsdMeshArrays()
    mesh.points = UsdArray(_square())
    mesh.normals = UsdArray([0, 0, 1])
    mesh.normal_indices = UsdArray([0])
    geometry = build_usd_geometry(mesh)
    assert_equal(len(_attribute(geometry, String(NORMAL))), 3)
    assert_equal(len(_attribute(geometry, String(POSITION))), 12)
    # Normals for each point with no corners stay as they are.
    mesh = UsdMeshArrays()
    mesh.points = UsdArray(_square())
    mesh.normals = UsdArray(_square())
    mesh.indices = UsdArray(List[Float64]())
    geometry = build_usd_geometry(mesh)
    assert_equal(len(_attribute(geometry, String(NORMAL))), 12)


def test_geometry_computes_normals() raises:
    var geometry = build_usd_geometry(_quad())
    _same(_slice(_attribute(geometry, String(NORMAL)), 0, 3), [0, 0, 1])
    # Corners with no faces are used as they are.
    var mesh = UsdMeshArrays()
    mesh.points = UsdArray(_square())
    mesh.indices = UsdArray([0, 1, 2])
    mesh.counts = UsdArray(List[Float64]())
    geometry = build_usd_geometry(mesh)
    assert_equal(len(_attribute(geometry, String(POSITION))), 9)
    with assert_raises(contains="no normals and no corners"):
        var bare = UsdMeshArrays()
        bare.points = UsdArray(_square())
        _ = build_usd_geometry(bare)
    with assert_raises(contains="no corner indices"):
        var faces = UsdMeshArrays()
        faces.points = UsdArray(_square())
        faces.counts = UsdArray([4])
        _ = build_usd_geometry(faces)


def test_geometry_coordinates() raises:
    # For each point, for each face corner, and as they are.
    var mesh = _quad()
    mesh.uvs = UsdArray([0, 0, 1, 0, 1, 1, 0, 1])
    var geometry = build_usd_geometry(mesh)
    _same(_slice(_attribute(geometry, String(UV)), 4, 6), [1, 1])
    mesh = _quad()
    mesh.points = UsdArray(_plus(_square(), [5, 5, 5]))
    mesh.uvs = UsdArray([0, 0, 1, 0, 1, 1, 0, 0.5])
    geometry = build_usd_geometry(mesh)
    _same(_slice(_attribute(geometry, String(UV)), 10, 12), [0, 0.5])
    mesh = _quad()
    mesh.uvs = UsdArray([0, 0])
    geometry = build_usd_geometry(mesh)
    assert_equal(len(_attribute(geometry, String(UV))), 2)
    # Coordinate indices with no faces, and no corners at all.
    mesh = UsdMeshArrays()
    mesh.points = UsdArray(_square())
    mesh.normals = UsdArray([0, 0, 1])
    mesh.uvs = UsdArray([0, 0])
    mesh.uv_indices = UsdArray([0])
    geometry = build_usd_geometry(mesh)
    assert_equal(len(_attribute(geometry, String(UV))), 2)


def _split() -> UsdMeshArrays:
    """Return two triangles and a quad, with normals and coordinates for
    each point."""
    var mesh = UsdMeshArrays()
    mesh.points = UsdArray(_plus(_square(), [1, 1, 1]))
    mesh.indices = UsdArray([0, 1, 2, 0, 2, 3, 0, 1, 4, 3])
    mesh.counts = UsdArray([3, 3, 4])
    return mesh^


def test_subsets() raises:
    var mesh = _split()
    mesh.normals = UsdArray(_plus(_square(), [0, 1, 0]))
    mesh.uvs = UsdArray([0, 0, 1, 0, 1, 1, 0, 1, 1, 1])
    # The quad in the first subset and the first triangle in the second;
    # a face past the list and a subset of no faces are skipped.
    var geometry = build_usd_geometry_with_subsets(
        mesh, [[2, 9], [0], List[Float64]()]
    )
    assert_equal(len(geometry.groups), 2)
    assert_equal(geometry.groups[0].start, 3)
    assert_equal(geometry.groups[0].count, 6)
    assert_equal(geometry.groups[0].material_index.value, 0)
    assert_equal(geometry.groups[1].start, 9)
    assert_equal(geometry.groups[1].material_index.value, 1)
    # The sorted triangles: the second face, the quad's two, the first.
    var positions = _attribute(geometry, String(POSITION))
    _same(_slice(positions, 0, 9), [0, 0, 0, 1, 1, 0, 0, 1, 0])
    _same(_slice(_attribute(geometry, String(UV)), 0, 2), [0, 0])
    _same(_slice(_attribute(geometry, String(NORMAL)), 3, 6), [1, 1, 0])
    assert_false(geometry.has_attribute(String(UV1)))
    assert_equal(
        build_usd_geometry_with_subsets(UsdMeshArrays(), [[0]]).attribute_count(), 0
    )
    var no_faces = UsdMeshArrays()
    no_faces.points = UsdArray(_square())
    assert_equal(build_usd_geometry_with_subsets(no_faces, [[0]]).attribute_count(), 0)


def test_subset_groups() raises:
    # Every triangle in a subset; no triangle in any; and none at all.
    var mesh = _split()
    mesh.normals = UsdArray(_plus(_square(), [0, 1, 0]))
    var all = build_usd_geometry_with_subsets(mesh, [[0, 1, 2]])
    assert_equal(len(all.groups), 1)
    assert_equal(all.groups[0].count, 12)
    var none = build_usd_geometry_with_subsets(mesh, List[List[Float64]]())
    assert_equal(len(none.groups), 0)
    var tiny = UsdMeshArrays()
    tiny.points = UsdArray(_square())
    tiny.indices = UsdArray([0, 1])
    tiny.counts = UsdArray([2])
    tiny.normals = UsdArray(List[Float64]())
    var empty = build_usd_geometry_with_subsets(tiny, [[0]])
    assert_equal(len(empty.groups), 0)
    assert_equal(len(_attribute(empty, String(POSITION))), 0)


def test_subset_holes() raises:
    var mesh = UsdMeshArrays()
    mesh.points = UsdArray(
        [0, 0, 0, 4, 0, 0, 4, 4, 0, 0, 4, 0, 1, 1, 0, 1, 3, 0, 3, 3, 0, 3, 1, 0]
    )
    mesh.indices = UsdArray([0, 1, 2, 3, 4, 5, 6, 7])
    mesh.counts = UsdArray([4, 4])
    mesh.holes = UsdArray([1, 0])
    # The hole face's own triangles run past the last, and are dropped.
    var geometry = build_usd_geometry_with_subsets(mesh, [[0], [1]])
    assert_equal(len(_attribute(geometry, String(POSITION))), 6 * 9)
    assert_equal(len(geometry.groups), 1)
    with assert_raises(contains="not whole"):
        var negative = UsdMeshArrays()
        negative.points = UsdArray(_square())
        negative.indices = UsdArray([0])
        negative.counts = UsdArray([0, 1])
        negative.holes = UsdArray([1, 0])
        _ = build_usd_geometry_with_subsets(negative, [[0]])
    with assert_raises(contains="not whole"):
        var half = UsdMeshArrays()
        half.points = UsdArray(_square())
        half.indices = UsdArray([0, 1, 2, 3])
        half.counts = UsdArray([3.5])
        _ = build_usd_geometry_with_subsets(half, [[0]])
    # A NaN count of triangles is none, as `new Int32Array( NaN )` is
    # empty; the hole of no corners is then refused, as three.js throws.
    with assert_raises():
        var nan_holes = UsdMeshArrays()
        nan_holes.points = UsdArray(_square())
        nan_holes.indices = UsdArray([0, 1, 2, 3])
        nan_holes.counts = UsdArray([4, _NAN])
        nan_holes.holes = UsdArray([1, 0])
        _ = build_usd_geometry_with_subsets(nan_holes, [[0]])
    # Subset faces that are not whole numbers from zero have no triangles.
    var nan_mesh = UsdMeshArrays()
    nan_mesh.points = UsdArray(_square())
    nan_mesh.indices = UsdArray([0, 1, 2])
    nan_mesh.counts = UsdArray([_NAN, 3])
    nan_mesh.normals = UsdArray(_square())
    var unassigned = build_usd_geometry_with_subsets(nan_mesh, [[_NAN, -1, 0.5]])
    assert_equal(len(_attribute(unassigned, String(POSITION))), 9)
    assert_equal(len(unassigned.groups), 0)


def test_subset_layouts() raises:
    # Coordinates by their indices and by face corner, normals by their
    # indices and by face corner, and normals computed.
    var mesh = _split()
    mesh.uvs = UsdArray([0, 0, 1, 1])
    mesh.uv_indices = UsdArray([0, 1, 0, 1, 0, 1, 0, 1, 0, 1])
    var corners = List[Float64]()
    for k in range(20):
        corners.append(Float64(k))
    mesh.uvs2 = UsdArray(corners^)
    mesh.normals = UsdArray([0, 0, 1, 0, 1, 0])
    mesh.normal_indices = UsdArray([1, 1, 1, 0, 0, 0, 0, 0, 0, 0])
    var geometry = build_usd_geometry_with_subsets(mesh, [[0]])
    _same(_slice(_attribute(geometry, String(UV)), 0, 2), [1, 1])
    _same(_slice(_attribute(geometry, String(UV1)), 0, 2), [6, 7])
    _same(_slice(_attribute(geometry, String(NORMAL)), 0, 3), [0, 0, 1])
    mesh = _split()
    var normals = List[Float64]()
    for k in range(30):
        normals.append(Float64(k))
    mesh.normals = UsdArray(normals^)
    mesh.uvs2 = UsdArray([0, 0, 1, 1])
    geometry = build_usd_geometry_with_subsets(mesh, [[0]])
    _same(_slice(_attribute(geometry, String(NORMAL)), 0, 3), [9, 10, 11])
    _same(_slice(_attribute(geometry, String(UV1)), 0, 2), [0, 0])
    mesh = _split()
    mesh.normals = UsdArray([0, 0, 1])
    mesh.normal_indices = UsdArray(List[Float64]())
    geometry = build_usd_geometry_with_subsets(mesh, [[0]])
    _same(_slice(_attribute(geometry, String(NORMAL)), 0, 3), [0, 0, 0])
    mesh = _split()
    mesh.points = UsdArray(_plus(_square(), [1, 1, 0]))
    geometry = build_usd_geometry_with_subsets(mesh, [[0]])
    _same(_slice(_attribute(geometry, String(NORMAL)), 0, 3), [0, 0, 1])
    with assert_raises(contains="no corner indices"):
        var faces = _split()
        faces.indices = UsdArray()
        _ = build_usd_geometry_with_subsets(faces, [[0]])
    with assert_raises(contains="no normals and no corners"):
        var flat = UsdMeshArrays()
        flat.points = UsdArray(_square())
        flat.indices = UsdArray(List[Float64]())
        flat.counts = UsdArray([0])
        flat.uvs = UsdArray(List[Float64]())
        _ = build_usd_geometry_with_subsets(flat, [[0]])


def test_subset_face_varying_coordinates() raises:
    var mesh = _split()
    var corners = List[Float64]()
    for k in range(20):
        corners.append(Float64(k))
    mesh.uvs = UsdArray(corners^)
    mesh.uvs2 = UsdArray([0, 0])
    mesh.uv2_indices = UsdArray([0, 0, 0, 0, 0, 0, 0, 0, 0, 0])
    var geometry = build_usd_geometry_with_subsets(mesh, [[0]])
    _same(_slice(_attribute(geometry, String(UV)), 0, 2), [6, 7])
    _same(_slice(_attribute(geometry, String(UV1)), 0, 2), [0, 0])


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
