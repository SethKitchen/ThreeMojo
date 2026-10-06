# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0

"""Numerical fallback and mutable-cache regression checks for geometry."""

from core.buffer_attribute import BufferAttribute
from core.buffer_geometry import (
    BufferGeometry,
    GeometryGroup,
    NORMAL,
    POSITION,
    UV,
    TANGENT,
    _wide_tangents,
)
from core.gaussian_splat_utils import write_covariance
from geometries.convex import convex
from geometries.simplify import _unit4
from geometries.sculptor_mesh import SculptorMesh
from geometries.sculptor_tools import area_normal
from geometries.mikktspace import (
    generate_tangents,
    _grid_cell,
    _projected_edge,
    _corner_angle,
    _v,
)
from geometries.torus import torus_knot
from core.buffer_geometry import MaterialIndex
from math.matrix4 import Matrix4
from math.vector3 import Vector3
from std.math import inf, nan, isnan, isfinite, ldexp, sqrt
from std.testing import (
    TestSuite,
    assert_equal,
    assert_true,
    assert_raises,
    assert_almost_equal,
)
from units.si import Length, METER


def triangle() raises -> BufferGeometry:
    var geometry = BufferGeometry()
    geometry.set_attribute(
        POSITION, BufferAttribute([0, 0, 0, 1, 0, 0, 0, 1, 0], 3)
    )
    geometry.set_attribute(
        NORMAL, BufferAttribute([0, 0, 1, 0, 0, 1, 0, 0, 1], 3)
    )
    geometry.set_attribute(UV, BufferAttribute([0, 0, 1, 0, 0, 1], 2))
    return geometry^


def test_covariance_rotations_survive_each_subnormal_axis() raises:
    for axis in range(4):
        var q = [Float64(0), Float64(0), Float64(0), Float64(0)]
        q[axis] = 1e-300
        var data = List[Float32](length=6, fill=0)
        write_covariance(data, 0, 1, 2, 3, q[0], q[1], q[2], q[3])
        assert_equal(data[0], Float32(1))
        assert_equal(data[1], Float32(0))
        assert_equal(data[2], Float32(0))
        assert_equal(data[3], Float32(4))
        assert_equal(data[4], Float32(0))
        assert_equal(data[5], Float32(9))


def test_convex_refuses_every_nonfinite_or_unstorable_component() raises:
    comptime P = SIMD[DType.float64, 4]
    with assert_raises():
        _ = convex(List[P]())
    for axis in range(3):
        for bad in [inf[DType.float64](), nan[DType.float64](), Float64(1e300)]:
            var p = P(0)
            p[axis] = bad
            var points: List[P] = [
                p,
                P(1, 0, 0, 0),
                P(0, 1, 0, 0),
                P(0, 0, 1, 0),
            ]
            with assert_raises():
                _ = convex(points)


def test_four_component_simplification_preserves_extreme_directions() raises:
    for scale in [Float64(1e-300), Float64(1e300)]:
        var unit = _unit4(SIMD[DType.float64, 4](scale, -scale, scale, -scale))
        for lane in range(4):
            assert_equal(
                unit[lane], Float64(0.5) if lane % 2 == 0 else Float64(-0.5)
            )
    var zero = _unit4(SIMD[DType.float64, 4](0))
    for lane in range(4):
        assert_equal(zero[lane], Float64(0))


def test_tangents_recover_a_zero_or_conditioned_projected_direction() raises:
    for y in [Float32(0), Float32(1e-5)]:
        var geometry = triangle()
        geometry.set_attribute(
            NORMAL, BufferAttribute([1, y, 0, 1, y, 0, 1, y, 0], 3)
        )
        geometry.compute_tangents()
        ref tangent = geometry.attribute_view(TANGENT)
        assert_equal(tangent.component(0, 0), Float32(0))
        assert_equal(
            tangent.component(0, 1), Float32(0) if y == 0 else Float32(-1)
        )
        assert_equal(tangent.component(0, 2), Float32(0))
    var geometry = triangle()
    geometry.set_attribute(
        UV, BufferAttribute([0, 0, 1, 1, 1, 1 + ldexp(Float32(1), -20)], 2)
    )
    geometry.compute_tangents()
    ref tangent = geometry.attribute_view(TANGENT)
    assert_true(tangent.component(0, 0) > 0)
    assert_true(tangent.component(0, 1) < 0)
    assert_almost_equal(tangent.vector3(0).length(), Float32(1), atol=1e-6)


def test_wide_tangents_validate_runs_and_empty_or_nonfinite_uvs() raises:
    for start in [-1, 0]:
        var geometry = triangle()
        geometry.groups = [
            GeometryGroup(start, -1 if start == 0 else 3, MaterialIndex(0))
        ]
        with assert_raises():
            _ = _wide_tangents(geometry)
    var empty_run = triangle()
    empty_run.add_group(3, 0)
    var empty = _wide_tangents(empty_run)
    for value in empty:
        assert_equal(value, Float32(0))
    var bad_uv = triangle()
    bad_uv.set_attribute(
        UV, BufferAttribute([0, 0, nan[DType.float32](), 0, 0, 1], 2)
    )
    var skipped = _wide_tangents(bad_uv)
    for vertex in range(3):
        assert_equal(skipped[vertex * 4], Float32(0))
        assert_equal(skipped[vertex * 4 + 1], Float32(0))
        assert_equal(skipped[vertex * 4 + 2], Float32(0))


def test_nonordinary_morph_delta_uses_its_base_normals_scale() raises:
    var geometry = triangle()
    geometry.morph_normals.append(
        BufferAttribute([1e-30, 0, 0, 1e-30, 0, 0, 1e-30, 0, 0], 3)
    )
    geometry.apply_matrix4(Matrix4())
    assert_equal(geometry.morph_normals[0].component(0, 0), Float32(1e-30))
    assert_equal(geometry.morph_normals[0].component(0, 1), Float32(0))


def test_sculptor_manual_face_and_vertex_normal_overrides_are_preserved() raises:
    var tiny = ldexp(Float32(1), -100)
    var mesh = SculptorMesh()
    mesh.vertices = [0, 0, 0, tiny, 0, 0, 0, tiny, 0]
    mesh.faces = [0, 1, 2]
    mesh.vert_ring_face = [[0], []]
    mesh.normals = List[Float32](length=6, fill=0)
    for axis in range(3):
        mesh.face_normals = [0, 0, 0]
        mesh.face_normals[axis] = tiny
        var area = mesh._face_area(0)
        assert_equal([area.x, area.y, area.z][axis], Float64(tiny))
        mesh.face_normals = [0, 0, 0]
        mesh.normals = List[Float32](length=6, fill=0)
        mesh.normals[axis] = tiny
        var normal = mesh._normal_at(0)
        assert_equal([normal.x, normal.y, normal.z][axis], Float64(tiny))
    var none = mesh._vertex_area(1)
    assert_equal(none.x, Float64(0))
    assert_equal(none.y, Float64(0))
    assert_equal(none.z, Float64(0))
    mesh.normals = [0, 1, 0, 0, 0, 0]
    var mean = area_normal(mesh, [0]).value()
    assert_equal(mean.x, Float64(0))
    assert_equal(mean.y, Float64(1))
    assert_equal(mean.z, Float64(0))


def test_sculptor_nonfinite_stored_vertices_keep_ieee_face_area() raises:
    var mesh = SculptorMesh()
    mesh.vertices = [0, 0, 0, inf[DType.float32](), 0, 0, 0, 1, 0]
    mesh.faces = [0, 1, 2]
    mesh.face_normals = List[Float32](length=3, fill=0)
    mesh.face_boxes = List[Float32](length=6, fill=0)
    mesh.face_centers = List[Float32](length=3, fill=0)
    mesh._update_faces_aabb_and_normal([0])
    var area = mesh._face_area(0)
    assert_true(isnan(area.y))


def test_mikk_nonfinite_fallbacks_preserve_ieee_results() raises:
    assert_equal(_grid_cell(0, nan[DType.float32](), 0), 0)
    assert_equal(_grid_cell(0, 1, nan[DType.float32]()), 0)
    for coordinate in range(9):
        var a = _v(1, 0, 0)
        var b = _v(0, 0, 0)
        var n = _v(0, 0, 1)
        if coordinate < 3:
            a[coordinate] = nan[DType.float32]()
        elif coordinate < 6:
            b[coordinate - 3] = nan[DType.float32]()
        else:
            n[coordinate - 6] = nan[DType.float32]()
        var projected = _projected_edge(a, b, n)
        assert_true(isnan(projected[0]))
        assert_true(isnan(projected[1]))
        assert_true(isnan(projected[2]))
    for coordinate in range(4):
        var a = _v(1, 0, 0)
        var n = _v(0, 0, 1)
        if coordinate == 0:
            a[1] = nan[DType.float32]()
        else:
            n[coordinate - 1] = nan[DType.float32]()
        assert_equal(
            _corner_angle(a, _v(0, 0, 0), _v(1, 1, 0), n, 1), Float64(0)
        )


def test_torus_normal_fallback_when_binormal_is_still_ordinary() raises:
    var geometry = torus_knot(Length(1e9, METER), Length(1, METER), 3, 3)
    ref normals = geometry.attribute_view(NORMAL)
    for vertex in range(normals.count()):
        assert_almost_equal(
            normals.vector3(vertex).length(), Float32(1), atol=2e-6
        )


def test_tangent_second_derivative_guards_are_independent() raises:
    var h = ldexp(Float32(1), 40)
    var geometry = triangle()
    geometry.set_attribute(
        POSITION, BufferAttribute([1, 0, 0, h, 1, 0, 2 * h, 1, 0], 3)
    )
    geometry.set_attribute(UV, BufferAttribute([0, 0, 1, 1, 2, 1], 2))
    geometry.compute_tangents()
    assert_true(geometry.attribute_view(TANGENT).vector3(0) == Vector3(1, 0, 0))
    geometry = triangle()
    geometry.set_attribute(
        POSITION, BufferAttribute([0, 0, 0, 1, 0, 0, 0, 1e-30, 0], 3)
    )
    geometry.compute_tangents()
    assert_true(geometry.attribute_view(TANGENT).vector3(0) == Vector3(1, 0, 0))


def test_mikk_nonfinite_uv_and_position_fallbacks_keep_default_frame() raises:
    for axis in range(3):
        var positions: List[Float32] = [0, 0, 0, 1, 0, 0, 0, 1, 0]
        positions[3 + axis] = nan[DType.float32]()
        var result = generate_tangents(
            positions^, [0, 0, 1, 0, 0, 1, 0, 0, 1], [0, 0, 1, 0, 0, 1]
        )
        for vertex in range(3):
            assert_equal(result[vertex * 4], Float32(1))
            assert_equal(result[vertex * 4 + 1], Float32(0))
            assert_equal(result[vertex * 4 + 2], Float32(0))
    var result = generate_tangents(
        [0, 0, 0, 1, 0, 0, 0, 1, 0],
        [0, 0, 1, 0, 0, 1, 0, 0, 1],
        [0, 0, nan[DType.float32](), 0, 0, 1],
    )
    for vertex in range(3):
        assert_equal(result[vertex * 4], Float32(1))
        assert_equal(result[vertex * 4 + 1], Float32(0))
        assert_equal(result[vertex * 4 + 2], Float32(0))


def test_mikk_ordinary_derivatives_can_have_underflowed_magnitudes() raises:
    from geometries.mikktspace import (
        _Context,
        _TriInfo,
        _init_tri_info,
        GROUP_WITH_ANY,
    )

    var context = _Context(
        [0, 0, 0, 2e-38, 0, 0, 0, 2e-38, 0],
        [0, 0, 1, 0, 0, 1, 0, 0, 1],
        [0, 0, 1e19, 0, 0, 1e19],
    )
    var infos = List[_TriInfo]()
    infos.append(
        _TriInfo(
            SIMD[DType.int64, 4](-1),
            SIMD[DType.int64, 4](-1),
            _v(0, 0, 0),
            _v(0, 0, 0),
            0,
            0,
            0,
            0,
            0,
        )
    )
    _init_tri_info(context, infos, [0, 1, 2], 1)
    assert_equal(infos[0].mag_s, Float32(0))
    assert_equal(infos[0].mag_t, Float32(0))
    assert_true((infos[0].flag & GROUP_WITH_ANY) != 0)
    assert_equal(infos[0].os[0], Float32(1))
    assert_equal(infos[0].ot[1], Float32(1))


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
