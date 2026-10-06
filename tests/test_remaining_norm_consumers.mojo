# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0

"""Independent direction and length oracles for the remaining norm consumers."""

from geometries.edges import _face_normal as edge_normal
from geometries.torus import torus_knot
from geometries.utils import to_creased_normals
from loaders.fbx import _triangulate as fbx_triangulate
from loaders.ply import _check_convex as ply_convex
from loaders.lwo import _vertex_normals as lwo_normals
from loaders.usd_geometry import compute_vertex_normals as usd_normals
from loaders.svg_path import eigen_decomposition
from math.triangle_normal import normal_or_zero, polygon_normal
from postprocessing.effects import _hypot
from renderers.renderer import face_normal
from units.si import Length, METER
from controls.arcball_controls import _angle_to
from controls.transform_controls import _angle_between
from core.buffer_attribute import BufferAttribute
from core.buffer_geometry import BufferGeometry, NORMAL, POSITION, TANGENT, UV
from core.gaussian_splat_utils import write_covariance
from core.object3d import Object3D
from geometries.mikktspace import generate_tangents, _normalize as mikk_unit, _v
from geometries.sculptor_tools import _unit_or_x
from geometries.sculptor_utils import Point3
from lights.lighting import light_vector, toward_eye_at, PERSPECTIVE_VIEW
from loaders.gltf import _apply_matrix
from loaders.ldraw import _face_normal, Vec as LDrawVec
from loaders.model_nodes import decompose_onto
from loaders.object_loader import decompose as object_decompose
from loaders.svg import _svg_angle
from loaders.svg_path import (
    SvgVector,
    svg_scale,
    transform_scale_x,
    transform_scale_y,
)
from loaders.svg_shapes import (
    _normalize as svg_unit,
    _normal as svg_normal,
    _length as svg_length,
)
from loaders.vrml_geometry import _Vector, normal_attribute
from math.matrix3 import Matrix3
from math.matrix4 import Matrix4, scaling
from math.norm import (
    normalized_cross3,
    normalized_difference2,
    normalized_difference3,
    reciprocal_normalized3,
)
from math.vector2 import Vector2
from math.vector3 import Vector3
from objects.line import _unit as line_unit
from objects.reflector_for_ssr import fresnel_coefficient
from render.cube_texture import equirect_uv
from render.rasterizer import mip_level, tangent_frame
from render.texture import (
    anisotropic_footprint,
    _principal_axes,
    _major_direction,
)
from renderers.projector import apply_normal, Vec
from std.math import inf, isfinite, isnan, nan, pi, sqrt
from std.memory import bitcast
from std.testing import (
    TestSuite,
    assert_almost_equal,
    assert_equal,
    assert_true,
    assert_raises,
)


def near3(v: Vector3, x: Float32, y: Float32, z: Float32) raises:
    assert_almost_equal(v.x, x, atol=2e-6)
    assert_almost_equal(v.y, y, atol=2e-6)
    assert_almost_equal(v.z, z, atol=2e-6)


def test_scalar_consumers_cover_float32_binary_exponents() raises:
    var scales: List[Float32] = [
        bitcast[DType.float32](UInt32(1)),
        bitcast[DType.float32](UInt32(0x7F7FFFFF)),
    ]
    for exponent in range(1, 255):
        scales.append(bitcast[DType.float32](UInt32(exponent) << 23))
    for scale in scales:
        var m = mikk_unit(_v(scale, -scale, scale))
        assert_almost_equal(m[0], Float32(0.5773502691896258), atol=1e-6)
        assert_equal(m[1], -m[0])
        var l = line_unit(SIMD[DType.float32, 2](scale, -scale))
        assert_almost_equal(l[0], Float32(0.7071067811865475), atol=1e-6)
        assert_equal(l[1], -l[0])
        assert_almost_equal(
            _angle_to(Vector3(scale, 0, 0), Vector3(scale, 0, 0)),
            Float32(0),
            atol=1e-6,
        )
        assert_almost_equal(
            _angle_between(Vector3(scale, 0, 0), Vector3(-scale, 0, 0)),
            Float32(pi),
            atol=1e-6,
        )
        assert_almost_equal(
            _angle_to(Vector3(scale, 0, 0), Vector3(0, scale, 0)),
            Float32(pi / 2),
            atol=1e-6,
        )
        assert_almost_equal(
            fresnel_coefficient(Vector3(scale, scale, 0)),
            Float32(0.5),
            atol=1e-6,
        )
        var uv = equirect_uv(Vector3(scale, scale, 0))
        assert_almost_equal(uv.x, Float32(0.5), atol=1e-6)
        assert_almost_equal(uv.y, Float32(0.75), atol=1e-6)


def test_double_consumers_keep_tiny_nonzero_and_unrepresentable_norms() raises:
    for scale in [
        bitcast[DType.float64](UInt64(1)),
        Float64(1e-200),
        Float64(1),
        Float64(1e200),
        Float64(1.7e308),
    ]:
        var v = svg_unit(SvgVector(scale, -scale))
        assert_almost_equal(v[0], Float64(0.7071067811865475244), atol=1e-14)
        assert_equal(v[1], -v[0])
        var axis = _Vector(scale, 0, 0)
        assert_equal(axis.normalized().x, Float64(1))
        assert_almost_equal(
            axis.angle_to(_Vector(0, scale, 0)), Float64(pi / 2), atol=1e-14
        )
        assert_almost_equal(
            axis.angle_to(_Vector(-scale, 0, 0)), Float64(pi), atol=1e-14
        )
        assert_equal(_svg_angle(scale, 0, scale, 0), Float64(0))
        assert_almost_equal(
            _svg_angle(scale, 0, 0, -scale), Float64(-pi / 2), atol=1e-14
        )
        var normal = _unit_or_x(Point3(scale, 0, 0))
        assert_equal(normal.x, Float64(1))
    for scale in [Float64(1e-200), Float64(1e200)]:
        assert_almost_equal(
            svg_length(SvgVector(3 * scale, 4 * scale)) / scale,
            Float64(5),
            atol=1e-14,
        )
        var matrix = svg_scale(3 * scale, 4 * scale)
        assert_equal(transform_scale_x(matrix), 3 * scale)
        assert_equal(transform_scale_y(matrix), 4 * scale)


def test_zero_and_nonfinite_policies_are_separate() raises:
    var zero = svg_unit(SvgVector(-0.0, 0.0))
    assert_equal(bitcast[DType.uint64](zero[0]), UInt64(0x8000000000000000))
    assert_equal(
        _Vector(0, 0, 0).angle_to(_Vector(1e300, 0, 0)), Float64(pi / 2)
    )
    assert_equal(_unit_or_x(Point3(0, 0, 0)).x, Float64(1))
    var line = line_unit(SIMD[DType.float32, 2](0))
    assert_true(isnan(line[0]) and isnan(line[1]))
    var invalid = reciprocal_normalized3(
        nan[DType.float64](), Float64(1), Float64(2)
    )
    assert_true(isnan(invalid[0]) and isnan(invalid[1]) and isnan(invalid[2]))
    var infinite = reciprocal_normalized3(
        inf[DType.float64](), Float64(1), Float64(2)
    )
    assert_true(isnan(infinite[0]))
    assert_equal(infinite[1], Float64(0))
    var ray = light_vector(Vector3(0, 0, 0), Vector3(0, 0, 0))
    assert_equal(ray[1], Float32(0))
    near3(ray[0], 0, 0, 0)


def test_finite_endpoint_differences_keep_directions() raises:
    var n2 = normalized_difference2(
        Float64(-1.7e308), Float64(0), Float64(1.7e308), Float64(0)
    )
    assert_equal(n2[0], Float64(1))
    var n3 = normalized_difference3(
        Float32(-3e38),
        Float32(0),
        Float32(0),
        Float32(3e38),
        Float32(0),
        Float32(0),
    )
    assert_equal(n3[0], Float32(1))
    var normal = svg_normal(SvgVector(-1.7e308, 0), SvgVector(1.7e308, 0))
    assert_equal(normal[0], Float64(0))
    assert_equal(normal[1], Float64(1))
    var ray = light_vector(Vector3(3e38, 0, 0), Vector3(-3e38, 0, 0))
    assert_equal(ray[1], inf[DType.float32]())
    near3(ray[0], 1, 0, 0)
    assert_equal(ray[2], Float32(1))
    near3(
        toward_eye_at(
            Vector3(3e38, 0, 0), PERSPECTIVE_VIEW, Vector3(-3e38, 0, 0)
        ),
        1,
        0,
        0,
    )


def test_cross_products_scale_before_multiplication() raises:
    for scale in [
        bitcast[DType.float64](UInt64(1)),
        Float64(1e-200),
        Float64(1),
        Float64(1e200),
        Float64(1e308),
    ]:
        var n = normalized_cross3(
            scale, Float64(0), Float64(0), Float64(0), scale, Float64(0)
        )
        assert_equal(n[0], Float64(0))
        assert_equal(n[1], Float64(0))
        assert_equal(n[2], Float64(1))
        n = normalized_cross3(
            scale, Float64(0), Float64(0), -scale, Float64(0), Float64(0)
        )
        assert_equal(n[2], Float64(0))
    # Scaling each whole vector would erase both tiny coordinates. Separate
    # product exponents retain the two equal, representable cross components.
    var mixed = normalized_cross3(
        Float64(1e308),
        Float64(1e-300),
        Float64(0),
        Float64(1e308),
        Float64(0),
        Float64(1e-300),
    )
    assert_almost_equal(mixed[1], Float64(-0.7071067811865475), atol=1e-14)
    assert_almost_equal(mixed[2], Float64(-0.7071067811865475), atol=1e-14)
    for scale in [Float64(1e-200), Float64(1e200)]:
        var normals = normal_attribute(
            [0, 1, 2], [0, 0, 0, scale, 0, 0, 0, scale, 0], 0
        )
        assert_equal(normals[2], Float64(1))
        var n = _face_normal(
            [LDrawVec(0), LDrawVec(scale, 0, 0, 0), LDrawVec(0, scale, 0, 0)]
        )
        assert_equal(n[2], Float64(1))


def triangle(scale: Float32, uv_scale: Float32 = 1) raises -> BufferGeometry:
    var g = BufferGeometry()
    g.set_attribute(
        String(POSITION),
        BufferAttribute([0, 0, 0, scale, 0, 0, 0, scale, 0], 3),
    )
    g.set_attribute(
        String(NORMAL), BufferAttribute([0, 0, 1, 0, 0, 1, 0, 0, 1], 3)
    )
    g.set_attribute(
        String(UV), BufferAttribute([0, 0, uv_scale, 0, 0, uv_scale], 2)
    )
    return g^


def test_geometry_normals_and_tangents_widen_before_products() raises:
    for scale in [
        bitcast[DType.float32](UInt32(1)),
        Float32(1e-30),
        Float32(1),
        Float32(1e30),
        Float32(3e38),
    ]:
        for uv_scale in [Float32(1e-30), Float32(1), Float32(1e30)]:
            var g = triangle(scale, uv_scale)
            g.compute_vertex_normals()
            near3(g.attribute_view(String(NORMAL)).vector3(0), 0, 0, 1)
            g.compute_tangents()
            near3(g.attribute_view(String(TANGENT)).vector3(0), 1, 0, 0)
            assert_equal(
                g.attribute_view(String(TANGENT)).component(0, 3), Float32(1)
            )
            var tangents = generate_tangents(
                g.attribute_view(String(POSITION)).packed(),
                g.attribute_view(String(NORMAL)).packed(),
                g.attribute_view(String(UV)).packed(),
            )
            assert_almost_equal(tangents[0], Float32(1), atol=1e-6)
            assert_almost_equal(tangents[1], Float32(0), atol=1e-6)
            assert_equal(tangents[3], Float32(1))


def test_projection_and_transformed_directions_widen_before_products() raises:
    for scale in [Float32(1e-30), Float32(1e30), Float32(3e38)]:
        var v = Vector3(1, 2, 3)
        v.project_on_vector(Vector3(scale, 0, 0))
        near3(v, 1, 0, 0)
        v = Vector3(scale, scale, 0)
        v.transform_direction(scaling(scale, scale, scale))
        near3(v, 0.7071067811865475, 0.7071067811865475, 0)
        var matrix = Matrix3()
        matrix.elements[0] = scale
        matrix.elements[4] = scale
        matrix.elements[8] = scale
        v = Vector3(scale, 0, 0)
        v.apply_normal_matrix(matrix)
        near3(v, 1, 0, 0)


def test_loader_decompositions_keep_tiny_and_mirrored_scales() raises:
    for scale in [Float32(1e-30), Float32(1e30)]:
        var matrix = scaling(-scale, scale, scale)
        var node = Object3D()
        decompose_onto(node, matrix, "test")
        assert_equal(node.scale.x, -scale)
        assert_equal(node.scale.y, scale)
        assert_equal(node.scale.z, scale)
        assert_almost_equal(abs(node.quaternion.w), Float32(1), atol=1e-6)
        var elements = List[Float32]()
        for element in matrix.elements:
            elements.append(element)
        _apply_matrix(node, elements)
        assert_equal(node.scale.x, -scale)
        object_decompose(node, elements)
        assert_equal(node.scale.x, -scale)


def test_light_and_frame_scales_are_separate_from_unit_directions() raises:
    for scale in [Float32(1e-30), Float32(1e30), Float32(3e38)]:
        var ray = light_vector(Vector3(scale, scale, 0), Vector3(0, 0, 0))
        assert_almost_equal(
            ray[0].x / ray[2], Float32(0.7071067811865475), atol=1e-6
        )
        for uv_scale in [Float32(1e-30), Float32(1), Float32(1e30)]:
            var frame = tangent_frame(
                Vector3(0, 0, 1),
                Vector3(scale, 0, 0),
                Vector3(0, scale, 0),
                Vector2(uv_scale, 0),
                Vector2(0, uv_scale),
            )
            near3(frame.tangent, 1, 0, 0)
            near3(frame.bitangent, 0, 1, 0)


def test_footprints_and_mip_levels_do_not_square_away_finite_derivatives() raises:
    for scale in [Float32(1e-30), Float32(1e15), Float32(1e30), Float32(3e38)]:
        var iso = anisotropic_footprint(
            Vector2(scale, 0), Vector2(0, scale), 8, 8, 1
        )
        assert_true(isfinite(iso.level))
        assert_true(
            isfinite(mip_level(Vector2(scale, 0), Vector2(0, scale), 8, 8))
        )
        var aniso = anisotropic_footprint(
            Vector2(scale, 0), Vector2(0, scale / 8), 8, 8, 16
        )
        aniso.validate()
        var axes = _principal_axes(Vector2(scale, 0), Vector2(0, scale / 8))
        assert_almost_equal(axes.x / scale, Float32(1), atol=2e-6)
        var direction = _major_direction(
            Vector2(scale, 0), Vector2(0, scale / 8), axes.x
        )
        assert_equal(direction.x, Float32(1))
    var ordinary = anisotropic_footprint(Vector2(4, 0), Vector2(0, 1), 1, 1, 8)
    assert_equal(ordinary.taps, 4)
    assert_equal(ordinary.level, Float32(0))


def test_covariance_and_projector_use_finite_unit_directions() raises:
    var identity: List[Float64] = [1, 0, 0, 0, 1, 0, 0, 0, 1]
    for scale in [Float64(1e-200), Float64(1e200), Float64(1.7e308)]:
        var normal = apply_normal(identity, Vec(scale, -scale, scale, 0))
        assert_almost_equal(normal[0], Float64(0.5773502691896258), atol=1e-14)
        var got: List[Float32] = [0, 0, 0, 0, 0, 0]
        write_covariance(got, 0, 1, 2, 3, 0, 0, scale, scale)
        assert_almost_equal(got[0], Float32(4), atol=1e-6)
        assert_almost_equal(got[3], Float32(1), atol=1e-6)
        assert_almost_equal(got[5], Float32(9), atol=1e-6)


def test_stored_coordinate_normals_keep_extreme_component_ratios() raises:
    var tiny = bitcast[DType.float32](UInt32(0x0D800000))
    var huge = bitcast[DType.float32](UInt32(0x71800000))
    var a = Vector3(tiny, 0, 3)
    var b = Vector3(huge, huge, 3)
    var c = Vector3(0, tiny, 3)
    near3(normal_or_zero(a, b, c), 0, 0, 1)
    near3(edge_normal(a, b, c), 0, 0, 1)
    near3(face_normal(a, b, c), 0, 0, 1)
    var g = triangle(1)
    g.set_attribute(
        String(POSITION),
        BufferAttribute([a.x, a.y, a.z, b.x, b.y, b.z, c.x, c.y, c.z], 3),
    )
    g.compute_vertex_normals()
    near3(g.attribute_view(String(NORMAL)).vector3(0), 0, 0, 1)


def test_loader_and_polygon_normal_builders_keep_small_faces() raises:
    for scale in [Float32(1e-30), Float32(1), Float32(1e30)]:
        var positions: List[Float32] = [0, 0, 0, scale, 0, 0, 0, scale, 0]
        var wide = List[Float64]()
        for x in positions:
            wide.append(Float64(x))
        var usd = usd_normals(wide, [0, 1, 2])
        assert_almost_equal(usd[2], Float64(1), atol=1e-6)
        var lwo = lwo_normals(positions, [0, 1, 2])
        assert_almost_equal(lwo[2], Float32(1), atol=1e-6)
        var points: List[Vector3] = [
            Vector3(0, 0, 0),
            Vector3(scale, 0, 0),
            Vector3(scale, scale, 0),
            Vector3(0, scale, 0),
        ]
        near3(polygon_normal(points), 0, 0, 1)
        ply_convex(points, 1)
        var cut = fbx_triangulate(points)
        assert_equal(len(cut), 6)
        var knot = torus_knot(
            Length(scale, METER), Length(scale / 8, METER), 4, 3
        )
        near3(
            Vector3(
                knot.attribute_view(String(NORMAL)).vector3(0).length(), 0, 0
            ),
            1,
            0,
            0,
        )
        assert_almost_equal(
            _hypot(3 * scale, 4 * scale) / scale, Float32(5), atol=1e-6
        )


def test_svg_eigen_norm_and_transformed_morph_normal_scale() raises:
    for scale in [Float64(1e-200), Float64(1e200)]:
        var eig = eigen_decomposition(3 * scale, scale, 3 * scale)
        assert_almost_equal(eig.rt1 / scale, Float64(4), atol=1e-14)
        assert_almost_equal(eig.rt2 / scale, Float64(2), atol=1e-14)
        assert_almost_equal(
            eig.cs * eig.cs + eig.sn * eig.sn, Float64(1), atol=1e-14
        )
    var g = triangle(1)
    g.set_attribute(
        String(NORMAL), BufferAttribute([1e30, 0, 0, 1e30, 0, 0, 1e30, 0, 0], 3)
    )
    g.morph_normals.append(
        BufferAttribute([5e29, 0, 0, 5e29, 0, 0, 5e29, 0, 0], 3)
    )
    g.apply_matrix4(scaling(1e-20, 1e-20, 1e-20))
    near3(g.attribute_view(String(NORMAL)).vector3(0), 1, 0, 0)
    near3(g.morph_normals[0].vector3(0), 0.5, 0, 0)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
