# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0

"""Exact counterexamples from independent review of scale-safe consumers."""

from units.si import Angle, DEGREE, Length, METER
from cameras.perspective_camera import PerspectiveCamera
from core.assets import Assets
from core.buffer_attribute import BufferAttribute
from core.buffer_geometry import (
    BufferGeometry,
    NORMAL,
    POSITION,
    TANGENT,
    UV,
    _wide_normal,
)
from core.raycaster import _within_on_image
from core.scene import Scene
from geometries.mikktspace import generate_tangents
from geometries.sculptor_mesh import SculptorMesh
from loaders.amf import parse_amf
from loaders.lwo import _vertex_normals as lwo_normals
from loaders.ply import _check_convex
from loaders.svg_path import eigen_decomposition
from loaders.usd_geometry import (
    compute_vertex_normals as usd_normals,
    _project as usd_project,
)
from lights.csm import CSM
from lights.sun_light import fit_sun, sun_light_shadow
from math.matrix3 import Matrix3
from math.matrix4 import Matrix4
from math.norm import normalized_cross3
from math.scaled_products import (
    _Scaled,
    _two_sum,
    _at_exponent,
    _common_scale,
    _sum_products,
)
from math.triangle_normal import polygon_normal
from math.vector2 import Vector2
from math.vector3 import Vector3
from objects.reflector_for_ssr import fresnel_coefficient
from postprocessing.sampling import LightView
from postprocessing.shaders import god_rays_generate_pixel, _god_ray_step
from render.framebuffer import FloatColor
from render.rasterizer import mip_level, tangent_frame
from render.texture import anisotropic_footprint
from renderers.projector import apply_normal, Vec
from std.math import inf, isnan, isfinite, ldexp, log2, nan, sqrt
from std.memory import bitcast
from std.testing import (
    TestSuite,
    assert_almost_equal,
    assert_equal,
    assert_true,
)


def near3(v: Vector3, x: Float32, y: Float32, z: Float32) raises:
    assert_almost_equal(v.x, x, atol=2e-6)
    assert_almost_equal(v.y, y, atol=2e-6)
    assert_almost_equal(v.z, z, atol=2e-6)


def test_polygon_and_loader_normals_keep_original_coordinate_terms() raises:
    var h = ldexp(Float32(1), 100)
    var t = ldexp(Float32(1), -100)
    var points: List[Vector3] = [
        Vector3(h, h, 0),
        Vector3(t, 0, 0),
        Vector3(0, t, 0),
    ]
    near3(polygon_normal(points), 0, 0, -1)
    _check_convex(
        [
            Vector3(h, h, 0),
            Vector3(t, 0, 0),
            Vector3(0, 0, 0),
            Vector3(0, t, 0),
        ],
        1,
    )
    for offset in range(3):
        var p32 = List[Float32]()
        var p64 = List[Float64]()
        for i in range(3):
            var p = points[(i + offset) % 3]
            p32.extend([p.x, p.y, p.z])
            p64.extend([Float64(p.x), Float64(p.y), Float64(p.z)])
        var usd = usd_normals(p64, [0, 1, 2])
        var lwo = lwo_normals(p32, [0, 1, 2])
        for i in range(3):
            assert_equal(usd[i * 3 + 2], Float64(-1))
            assert_equal(lwo[i * 3 + 2], Float32(-1))


def test_uv_determinants_keep_original_coordinate_terms() raises:
    var h = ldexp(Float32(1), 100)
    var t = ldexp(Float32(1), -100)
    var p: List[Float32] = [0, 0, 0, 1, 0, 0, 0, 1, 0]
    var n: List[Float32] = [0, 0, 1, 0, 0, 1, 0, 0, 1]
    var uv: List[Float32] = [h, h, t, 0, 0, t]
    var g = BufferGeometry()
    g.set_attribute(String(POSITION), BufferAttribute(p.copy(), 3))
    g.set_attribute(String(NORMAL), BufferAttribute(n.copy(), 3))
    g.set_attribute(String(UV), BufferAttribute(uv.copy(), 2))
    g.compute_tangents()
    near3(
        g.attribute_view(String(TANGENT)).vector3(0),
        0.7071067811865475,
        -0.7071067811865475,
        0,
    )
    var mikk = generate_tangents(p^, n^, uv^)
    assert_almost_equal(mikk[0], Float32(0.7071067811865475), atol=1e-6)
    assert_almost_equal(mikk[1], Float32(-0.7071067811865475), atol=1e-6)


def test_normalized_matrix_products_keep_cancellation_residuals() raises:
    var h = ldexp(Float32(1), 100)
    var m3 = Matrix3()
    m3.set(1, 1, -h, 0, 1, 0, 0, 0, 0)
    var v = Vector3(h, 1, 1)
    var wide = _wide_normal(m3, v)
    assert_equal(wide[0], Float64(1))
    assert_equal(wide[1], Float64(1))
    v.apply_normal_matrix(m3)
    near3(v, 0.7071067811865475, 0.7071067811865475, 0)
    var m4 = Matrix4()
    m4.set(1, 1, -h, 0, 0, 1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1)
    v = Vector3(h, 1, 1)
    v.transform_direction(m4)
    near3(v, 0.7071067811865475, 0.7071067811865475, 0)


def test_native_double_products_keep_overflow_underflow_and_exact_residuals() raises:
    for exponent in [-600, 600]:
        var h = ldexp(Float64(1), Int32(exponent))
        var normal = apply_normal([h, 0, 0, 0, h, 0, 0, 0, 1], Vec(h, h, 0, 0))
        assert_almost_equal(
            normal[0], Float64(0.7071067811865475244), atol=1e-14
        )
        assert_equal(normal[1], normal[0])
    var h = ldexp(Float64(1), 600)
    var e = ldexp(Float64(1), -27)
    var n = normalized_cross3(
        h, h * (1 + e), Float64(0), h * (1 - e), h, Float64(0)
    )
    assert_equal(n[0], Float64(0))
    assert_equal(n[1], Float64(0))
    assert_equal(n[2], Float64(1))


def test_frame_products_preserve_mixed_exponents_and_underflowed_products() raises:
    var h = ldexp(Float32(1), 120)
    var t = ldexp(Float32(1), -40)
    var frame = tangent_frame(
        Vector3(0, 0, 1),
        Vector3(h, 0, 0),
        Vector3(0, t, 0),
        Vector2(h, 0),
        Vector2(0, t),
    )
    near3(frame.tangent, 1, 0, 0)
    near3(frame.bitangent, 0, 1, 0)
    t = ldexp(Float32(1), -120)
    for uv in [Float32(1), t]:
        frame = tangent_frame(
            Vector3(1, 0, 0),
            Vector3(h, 0, 0),
            Vector3(h, t, 0),
            Vector2(uv, 0),
            Vector2(0, 0),
        )
        near3(frame.tangent, 0, 0, -1)
        near3(frame.bitangent, 0, 0, 0)


def test_scaled_product_rounding_keeps_subnormal_boundaries() raises:
    var sum = _two_sum(
        _Scaled[DType.float32](0.5, 0), _Scaled[DType.float32](-0.75, -25)
    )
    assert_equal(_at_exponent(sum[0], 0), Float32(0.5) - ldexp(Float32(1), -25))
    var fraction = Float32(0.5) + ldexp(Float32(1), -24)
    var tiny = _at_exponent(_Scaled[DType.float32](fraction, -149), 0)
    assert_equal(tiny, bitcast[DType.float32](UInt32(1)))
    var common = _common_scale[DType.float32, 2](
        [
            _Scaled[DType.float32](1 - ldexp(Float32(1), -24), 0),
            _Scaled[DType.float32](fraction, -149),
        ]
    )
    assert_true(common[0] >= 1)
    assert_true(common[1] > 0)
    var h = ldexp(Float32(1), 120)
    var result = _sum_products[DType.float32, 3](
        [h, Float32(1), -h],
        [Float32(1), Float32(1), Float32(1)],
        [Float32(1), Float32(1), Float32(1)],
    )
    assert_equal(_at_exponent(result, 0), Float32(1))


def test_mip_level_uses_log_space_for_an_unrepresentable_norm() raises:
    var x = Vector2(3e38, 3e38)
    var got = mip_level(x, Vector2(0, 0), 1, 1)
    assert_true(isfinite(got))
    assert_equal(got, anisotropic_footprint(x, Vector2(0, 0), 1, 1, 1).level)
    assert_almost_equal(got, log2(Float32(3e38)) + Float32(0.5), atol=2e-5)


def test_god_rays_step_remains_a_direction_when_length_is_infinite() raises:
    var pixels = List[FloatColor]()
    for _ in range(8):
        for column in range(8):
            pixels.append(FloatColor(Float32(column) / 7, 0, 0, 1))
    var view = LightView(pixels, 8, 8)
    var step = Float32(1.0 / 6)
    var expected = Float32(0)
    for i in range(6):
        var at = Float32(i) * step * sqrt(Float32(0.5))
        expected += view.sample(at, at).r
    var got = god_rays_generate_pixel(
        view, 0, 0, Vector3(3e38, 3e38, 2000), step
    )
    assert_almost_equal(got.r, expected / 6, atol=1e-6)
    assert_true(got.r > 0)


def test_zero_axis_and_nonfinite_fresnel_keep_their_policies() raises:
    var v = Vector3(inf[DType.float32](), 2, 3)
    v.project_on_vector(Vector3(0, 0, 0))
    near3(v, 0, 0, 0)
    v = Vector3(inf[DType.float32](), 2, 3)
    v.project_on_plane(Vector3(0, 0, 0))
    assert_equal(v.x, inf[DType.float32]())
    assert_equal(v.y, Float32(2))
    assert_equal(v.z, Float32(3))
    assert_true(isnan(fresnel_coefficient(Vector3(nan[DType.float32](), 1, 0))))


def test_eigen_trace_and_projected_line_do_not_overflow_before_norm() raises:
    var e = eigen_decomposition(1e308, 1, 1e308)
    assert_equal(e.rt1, Float64(1e308))
    assert_equal(e.rt2, Float64(1e308))
    assert_true(
        _within_on_image(
            Vector3(-3e38, 0, -1),
            Vector3(3e38, 0, -1),
            -1,
            Matrix4(),
            Vector2(0, 0),
            1,
            1,
            0.5,
        )
    )


def test_sun_directions_can_have_an_unrepresentable_length() raises:
    var scene = Scene()
    var camera = PerspectiveCamera(
        Angle(90, DEGREE), 1, Length(1, METER), Length(3, METER)
    )
    var fit = fit_sun(scene, camera, Vector3(3e38, 3e38, 0), sun_light_shadow())
    near3(fit.direction, -0.7071067811865475, -0.7071067811865475, 0)
    var csm = CSM(
        scene, camera, cascades=1, light_direction=Vector3(3e38, 3e38, 0)
    )
    assert_equal(len(csm.lights), 1)


def test_sculptor_reconstructs_range_limited_stored_face_areas() raises:
    for exponent in [-100, 100]:
        var scale = ldexp(Float32(1), Int32(exponent))
        var mesh = SculptorMesh()
        mesh.vertices = [0, 0, 0, scale, 0, 0, 0, scale, 0]
        mesh.faces = [0, 1, 2]
        mesh.face_normals = [0, 0, scale * scale]
        mesh.normals = List[Float32](length=9, fill=0)
        mesh.render_normals = List[Float32](length=9, fill=0)
        mesh.vert_ring_face = [[0], [0], [0]]
        mesh._update_vertices_normal([0, 1, 2])
        assert_equal(mesh.render_normals[2], Float32(1))
        var area = mesh._normal_at(0)
        assert_true(isfinite(area.z) and area.z > 0)


def test_amf_positive_unit_conversion_cannot_erase_a_tiny_normal() raises:
    var source = String("<amf unit='meter'><object id='1'><mesh><vertices>")
    for vertex in range(3):
        source += (
            "<vertex><coordinates><x>"
            + String(vertex % 2)
            + "</x><y>"
            + String(vertex // 2)
            + "</y><z>0</z></coordinates><normal><nx>5e-324</nx><ny>0</ny><nz>0</nz></normal></vertex>"
        )
    source += "</vertices><volume><triangle><v1>0</v1><v2>1</v2><v3>2</v3></triangle></volume></mesh></object></amf>"
    var bytes = List[UInt8]()
    for byte in source.as_bytes():
        bytes.append(byte)
    var scene = Scene()
    var assets = Assets()
    var model = parse_amf(bytes^, scene, assets)
    var normal = (
        assets.geometries.get(model.geometries[0])
        .attribute_view(String(NORMAL))
        .vector3(0)
    )
    near3(normal, 1, 0, 0)


def test_native_usd_normals_and_basis_keep_full_float64_range() raises:
    for exponent in [-600, 600]:
        var scale = ldexp(Float64(1), Int32(exponent))
        var points: List[Float64] = [0, 0, 0, scale, 0, 0, 0, scale, 0]
        var normals = usd_normals(points, [0, 1, 2])
        assert_equal(normals[2], Float64(1))
        var basis = usd_project([0, 1, 2], points)
        assert_equal(basis[0][1], Float64(1))
        assert_equal(basis[1][0], Float64(-1))


def test_god_ray_step_cannot_overflow_or_underflow_its_numerator() raises:
    var big = _god_ray_step(0, 0, Vector3(3e38, 0, 2000), 2)
    assert_equal(big[1], Float32(2))
    var tiny = ldexp(Float32(1), -100)
    var small = _god_ray_step(0, 0, Vector3(tiny, 0, 2000), tiny)
    assert_equal(small[1], tiny)


def test_sculptor_reconstructs_partially_underflowed_area_components() raises:
    var s = ldexp(Float32(1), -75)
    var mesh = SculptorMesh()
    mesh.vertices = [0, 0, 0, 0, 0, s, 2 * s, -s, 0]
    mesh.faces = [0, 1, 2]
    mesh.face_normals = [0, bitcast[DType.float32](UInt32(1)), 0]
    mesh.normals = List[Float32](length=9, fill=0)
    mesh.render_normals = List[Float32](length=9, fill=0)
    mesh.vert_ring_face = [[0], [0], [0]]
    mesh._update_vertices_normal([0, 1, 2])
    var area = mesh._normal_at(0)
    assert_equal(area.x / area.y, Float64(0.5))
    assert_almost_equal(
        mesh.render_normals[0], Float32(1 / sqrt(Float64(5))), atol=1e-6
    )


def test_native_usd_keeps_residuals_across_polygon_edges() raises:
    var h = ldexp(Float64(1), 600)
    var d = ldexp(Float64(1), 548)
    var p: List[Float64] = [h, h, 0, h, h + d, 0, h + d, h, 0]
    var basis = usd_project([0, 1, 2], p)
    assert_equal(basis[1][0], Float64(1))
    var normals = usd_normals(p, [0, 1, 2])
    assert_equal(normals[2], Float64(-1))
    h = ldexp(Float64(1), 26)
    p = [0, 0, 0, 0, h + 0.5, h, ldexp(Float64(1), -28), h, h - 0.5]
    normals = usd_normals(p, [0, 1, 2])
    assert_almost_equal(normals[0], Float64(-0.5773502691896258), atol=1e-6)
    assert_almost_equal(normals[1], Float64(0.5773502691896258), atol=1e-6)


def test_tangent_ordinary_guards_detect_product_cancellation() raises:
    var h = ldexp(Float32(1), 40)
    var p: List[Float32] = [1, 0, 0, h, 1, 0, 2 * h, 1, 0]
    var n: List[Float32] = [0, 0, 1, 0, 0, 1, 0, 0, 1]
    var uv: List[Float32] = [0, 0, 1, 1, 1, 2]
    var g = BufferGeometry()
    g.set_attribute(String(POSITION), BufferAttribute(p.copy(), 3))
    g.set_attribute(String(NORMAL), BufferAttribute(n.copy(), 3))
    g.set_attribute(String(UV), BufferAttribute(uv.copy(), 2))
    g.compute_tangents()
    near3(
        g.attribute_view(String(TANGENT)).vector3(0),
        -0.7071067811865475,
        0.7071067811865475,
        0,
    )
    var mikk = generate_tangents(p^, n^, uv^)
    assert_almost_equal(mikk[0], Float32(-0.7071067811865475), atol=1e-6)
    assert_almost_equal(mikk[1], Float32(0.7071067811865475), atol=1e-6)


def test_sculptor_ordinary_normal_and_zero_override_fixtures() raises:
    from tests.test_sculptor import (
        test_the_bumpy_plane_welds_as_three_js_does as check_plane,
    )
    from tests.test_sculptor import (
        test_tools_leave_a_vertex_with_no_normal_in_place as check_zero,
    )
    from tests.test_sculptor import (
        test_a_hit_on_a_vertex_takes_its_normal as check_hit,
    )
    from tests.test_sculptor import test_a_zero_normal_becomes_x as check_axis

    check_plane()
    check_zero()
    check_hit()
    check_axis()


def test_mikk_keeps_a_nonzero_corner_weight_below_float32_range() raises:
    var h = ldexp(Float32(1), 120)
    var t = ldexp(Float32(1), -120)
    var p: List[Float32] = [t, 0, 0, h, t, 0, 2 * h, t, 0]
    var n: List[Float32] = [0, 0, 1, 0, 0, 1, 0, 0, 1]
    var uv: List[Float32] = [0, 0, 1, 1, 1, 2]
    var mikk = generate_tangents(p^, n^, uv^)
    assert_almost_equal(mikk[0], Float32(-0.7071067811865475), atol=1e-6)
    assert_almost_equal(mikk[1], Float32(0.7071067811865475), atol=1e-6)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
