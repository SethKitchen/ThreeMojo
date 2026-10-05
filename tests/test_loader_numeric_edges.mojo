# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0

"""Independent edge-case oracles for loader direction and matrix boundaries."""

from loaders.amf import _scaled_normal
from core.assets import Assets
from core.object3d import Object3D
from core.scene import Scene
from loaders.ldraw import _face_normal, Vec
from loaders.lwo import _vertex_normals
from loaders.object_loader import decompose
from loaders.svg import _svg_angle
from loaders.svg_path import eigen_decomposition, SvgVector
from loaders.svg_shapes import _normalize, _normal
from loaders.usd_geometry import _project
from loaders.vrml import parse_vrml
from loaders.vrml_geometry import _Vector, normal_attribute
from std.math import inf, isnan, nan, pi, sin, cos
from std.testing import (
    TestSuite,
    assert_almost_equal,
    assert_equal,
    assert_raises,
    assert_true,
)


def test_each_flattened_matrix_axis_is_refused() raises:
    for axis in range(3):
        var elements = List[Float32](length=16, fill=0)
        for diagonal in range(4):
            elements[diagonal * 5] = 1
        elements[axis * 5] = 0
        var node = Object3D()
        with assert_raises(contains="flattens an axis"):
            decompose(node, elements)


def test_empty_lwo_normals_have_no_vertices() raises:
    assert_equal(len(_vertex_normals([], [])), 0)


def test_ldraw_opposite_finite_corners_on_each_axis() raises:
    # Each cyclic permutation has the positive remaining-axis normal.
    # Either edge can overflow independently before the safe half scaling.
    for axis in range(3):
        for edge in range(2):
            var a = Vec(0)
            var b = Vec(0)
            var c = Vec(0)
            if edge == 0:
                a[axis] = -1.7e308
                b[axis] = 1.7e308
                c[axis] = 1.7e308
                c[(axis + 1) % 3] = 1
            else:
                a[(axis + 1) % 3] = -1
                a[axis] = -1.7e308
                b[axis] = -1.7e308
                c[axis] = 1.7e308
            var got = _face_normal([a, b, c])
            for lane in range(3):
                var expected = Float64(0)
                if lane == (axis + 2) % 3:
                    expected = 1 if edge == 0 else -1
                assert_equal(got[lane], expected)


def test_vrml_opposite_finite_corners_on_each_axis() raises:
    for axis in range(3):
        for edge in range(2):
            var points = List[Float64](length=9, fill=0)
            points[3 + axis] = -1.7e308
            if edge == 0:
                points[axis] = -1.7e308
                points[(axis + 1) % 3] = 1
                points[6 + axis] = 1.7e308
            else:
                points[axis] = 1.7e308
                points[6 + axis] = -1.7e308
                points[6 + (axis + 1) % 3] = 1
            var got = normal_attribute([0, 1, 2], points, 0)
            var sign = Float64(1) if edge == 0 else Float64(-1)
            for lane in range(3):
                var expected = sign if lane == (axis + 2) % 3 else Float64(0)
                assert_equal(got[lane], expected)


def test_vrml_angle_zero_components_and_product_range() raises:
    var zero = _Vector(0, 0, 0)
    for axis in [
        _Vector(1e-200, 0, 0),
        _Vector(0, 1e-200, 0),
        _Vector(0, 0, 1e-200),
    ]:
        assert_equal(axis.angle_to(zero), Float64(pi / 2))
        assert_equal(zero.angle_to(axis), Float64(pi / 2))
        assert_almost_equal(axis.angle_to(axis), Float64(0), atol=1e-14)
    # Both squared norms are ordinary, but their product over/underflows.
    for magnitude in [Float64(1e-100), Float64(1e100)]:
        assert_almost_equal(
            _Vector(magnitude, 0, 0).angle_to(_Vector(0, magnitude, 0)),
            Float64(pi / 2),
            atol=1e-14,
        )


def test_vrml_rotation_normalizes_an_extreme_axis() raises:
    for magnitude in [String("1e-200"), String("1e200")]:
        var scene = Scene()
        var assets = Assets()
        var model = parse_vrml(
            "#VRML V2.0 utf8\nTransform { rotation 0 " + magnitude + " 0 1 }",
            scene,
            assets,
        )
        var nodes = scene.traverse(model.root)
        assert_equal(len(nodes), 2)
        var rotation = scene.get(nodes[1]).quaternion
        assert_equal(rotation.x, Float32(0))
        assert_almost_equal(rotation.y, Float32(sin(Float64(0.5))), atol=1e-7)
        assert_equal(rotation.z, Float32(0))
        assert_almost_equal(rotation.w, Float32(cos(Float64(0.5))), atol=1e-7)


def test_svg_angle_keeps_degenerate_and_axis_aligned_policies() raises:
    # The pinned scalar min/max clamp selects one for a NaN cosine,
    # so a zero argument retains this implementation's zero-angle result.
    for values in [SvgVector(1e-200, 0), SvgVector(0, 1e-200), SvgVector(0, 0)]:
        assert_equal(_svg_angle(0, 0, values[0], values[1]), Float64(0))
        assert_equal(_svg_angle(values[0], values[1], 0, 0), Float64(0))
    assert_almost_equal(_svg_angle(1, 0, 0, 1e200), Float64(pi / 2), atol=1e-14)
    assert_almost_equal(
        _svg_angle(1e-200, 0, 0, 1e-200), Float64(pi / 2), atol=1e-14
    )
    assert_almost_equal(
        _svg_angle(0, 1e-200, 1e-200, 0), Float64(-pi / 2), atol=1e-14
    )


def test_svg_normal_keeps_nan_and_vertical_overflow_policies() raises:
    var invalid = _normalize(SvgVector(nan[DType.float64](), 1))
    assert_true(isnan(invalid[0]))
    assert_true(isnan(invalid[1]))
    var vertical = _normal(SvgVector(0, -1.7e308), SvgVector(0, 1.7e308))
    assert_equal(vertical[0], Float64(-1))
    assert_equal(vertical[1], Float64(0))


def test_svg_eigen_zero_repeated_and_unequal_diagonals() raises:
    var zero = eigen_decomposition(0, 0, 0)
    assert_equal(zero.rt1, Float64(0))
    assert_equal(zero.rt2, Float64(0))
    var repeated = eigen_decomposition(2, 0, 2)
    assert_equal(repeated.rt1, Float64(2))
    assert_equal(repeated.rt2, Float64(2))
    var tiny_repeated = eigen_decomposition(5e-324, 0, 5e-324)
    assert_equal(tiny_repeated.rt1, Float64(5e-324))
    assert_equal(tiny_repeated.rt2, Float64(5e-324))
    var distinct = eigen_decomposition(1e200, 0, 2e200)
    assert_equal(distinct.rt1, Float64(2e200))
    assert_equal(distinct.rt2, Float64(1e200))


def test_usd_basis_retains_each_exact_orientation_component() raises:
    # Coordinates are quarter-integers. Relative to the first point the
    # edges are (3.5, -2.5) and (-1, 0.75), whose determinant is +0.125.
    # The directly summed Newell terms cancel to a negative result. Cyclic
    # permutations make every component independently decide recovery.
    var h = Float64(1125899906842624)
    for axis in range(3):
        var points = List[Float64](length=9, fill=0)
        points[axis] = h - 2.75
        points[(axis + 1) % 3] = h - 1.5
        points[3 + axis] = h + 0.75
        points[3 + (axis + 1) % 3] = h - 4
        points[6 + axis] = h - 3.75
        points[6 + (axis + 1) % 3] = h - 0.75
        var basis = _project([0, 1, 2], points)
        var tangent = basis[0].copy()
        var bitangent = basis[1].copy()
        for lane in range(3):
            var j = (lane + 1) % 3
            var k = (lane + 2) % 3
            var normal = tangent[j] * bitangent[k] - tangent[k] * bitangent[j]
            var expected = Float64(1) if lane == (axis + 2) % 3 else Float64(0)
            assert_equal(normal, expected)


def test_amf_scaled_normal_retains_each_nonfinite_lane_policy() raises:
    for axis in range(3):
        var components: List[Float64] = [1, 2, 3]
        components[axis] = inf[DType.float64]()
        var got = _scaled_normal(
            components[0], components[1], components[2], 1000
        )
        var result: List[Float64] = [got[0], got[1], got[2]]
        for lane in range(3):
            if lane == axis:
                assert_true(isnan(result[lane]))
            else:
                assert_equal(result[lane], Float64(0))
    var tiny = _scaled_normal(5e-324, 0, 0, 1000)
    assert_equal(tiny[0], Float64(1))
    assert_equal(tiny[1], Float64(0))
    assert_equal(tiny[2], Float64(0))
    var ordinary = _scaled_normal(3, 4, 0, 1)
    assert_almost_equal(ordinary[0], Float64(0.6), atol=1e-14)
    assert_almost_equal(ordinary[1], Float64(0.8), atol=1e-14)
    assert_equal(ordinary[2], Float64(0))


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
