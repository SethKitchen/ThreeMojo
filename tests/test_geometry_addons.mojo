# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Tests for the builders three.js keeps in its addons:
`geometries.parametric`, `geometries.convex` with `math.convex_hull`,
`geometries.decal` and `geometries.rounded_box`.

The reference numbers come from three.js 0.180 run under Node, with the
same inputs.
"""

from core.buffer_attribute import BufferAttribute
from core.buffer_geometry import BufferGeometry, NORMAL, POSITION, UV
from geometries.convex import convex
from geometries.decal import decal
from geometries.parametric import (
    EPS,
    ParametricSurface,
    SurfaceFunction,
    klein,
    mobius,
    mobius3d,
    parametric,
    parametric_plane,
)
from geometries.rounded_box import rounded_box
from math.convex_hull import ConvexHull
from math.euler import Euler, EulerOrder, XYZ
from math.matrix4 import Matrix4, rotation_x, scaling, translation
from math.vector3 import Vector3
from std.math import cos, nan, sin
from std.testing import (
    TestSuite,
    assert_almost_equal,
    assert_equal,
    assert_false,
    assert_raises,
    assert_true,
)
from units.si import Angle, Length, METER, RADIAN


def meters(value: Float32) -> Length:
    """Return a length in meters."""
    return Length(value, METER)


def assert_near(
    got: Vector3, x: Float64, y: Float64, z: Float64, tolerance: Float64
) raises:
    """Assert a vector is within `tolerance` of `(x, y, z)`."""
    assert_almost_equal(Float64(got.x), x, atol=tolerance)
    assert_almost_equal(Float64(got.y), y, atol=tolerance)
    assert_almost_equal(Float64(got.z), z, atol=tolerance)


def assert_vertex(
    geometry: BufferGeometry,
    vertex: Int,
    position: List[Float64],
    normal: List[Float64],
    uv: List[Float64],
    tolerance: Float64,
    normal_tolerance: Float64,
) raises:
    """Assert one vertex's position, normal and texture coordinate."""
    ref positions = geometry.attribute_view(String(POSITION))
    ref normals = geometry.attribute_view(String(NORMAL))
    ref uvs = geometry.attribute_view(String(UV))
    assert_near(
        positions.vector3(vertex),
        position[0],
        position[1],
        position[2],
        tolerance,
    )
    assert_near(
        normals.vector3(vertex),
        normal[0],
        normal[1],
        normal[2],
        normal_tolerance,
    )
    assert_almost_equal(
        Float64(uvs.component(vertex, 0)), uv[0], atol=tolerance
    )
    assert_almost_equal(
        Float64(uvs.component(vertex, 1)), uv[1], atol=tolerance
    )


# --- Parametric --------------------------------------------------------------


@fieldwise_init
struct Dome(ImplicitlyCopyable, ParametricSurface):
    """A half sphere of a given radius: a surface that holds a number."""

    var radius: Float32

    def point(self, u: Float32, v: Float32) -> Vector3:
        """Return the point at `(u, v)`."""
        var around = u * 6.2831855
        var up = v * 1.5707964
        return Vector3(
            self.radius * cos(up) * cos(around),
            self.radius * sin(up),
            -self.radius * cos(up) * sin(around),
        )


@fieldwise_init
struct Broken(ImplicitlyCopyable, ParametricSurface):
    """A surface that gives a number that is not finite on one axis."""

    var axis: Int

    def point(self, u: Float32, v: Float32) -> Vector3:
        """Return a point with NaN on `axis`."""
        var p = Vector3(u, v, 0)
        if self.axis == 0:
            p.x = nan[DType.float32]()
        elif self.axis == 1:
            p.y = nan[DType.float32]()
        else:
            p.z = nan[DType.float32]()
        return p


def test_a_klein_bottle_matches_three_js() raises:
    var bottle = parametric(SurfaceFunction[klein]())
    assert_equal(bottle.vertex_count(), 81)
    assert_equal(len(bottle.index), 384)
    # Positions and texture coordinates agree closely. The normals are
    # finite differences over a step of 1e-5 in Float32, so they agree to a
    # few parts in a thousand.
    assert_vertex(
        bottle,
        0,
        [4.0, 0, 0],
        [0.948686302, -0.0000298, 0.316218823],
        [0, 0],
        1e-5,
        5e-3,
    )
    assert_vertex(
        bottle,
        5,
        [2.29289317, 0.707106769, 0],
        [-0.678988516, 0.678945899, -0.279297471],
        [0.625, 0],
        1e-5,
        5e-3,
    )
    assert_vertex(
        bottle,
        13,
        [2.70710683, 0, -4.74264050],
        [-0.927738845, -0.0000289, 0.373229951],
        [0.5, 0.125],
        1e-5,
        5e-3,
    )
    assert_vertex(
        bottle,
        40,
        [0, 0, 0],
        [0.857490540, -0.0000269, -0.514499724],
        [0.5, 0.5],
        1e-5,
        5e-3,
    )
    assert_vertex(
        bottle,
        80,
        [2.0, 0, 0],
        [0.936324358, -0.0000294, 0.351136327],
        [1, 1],
        1e-5,
        5e-3,
    )


def test_a_mobius_strip_matches_three_js() raises:
    var strip = parametric(SurfaceFunction[mobius](), 4, 6)
    assert_equal(strip.vertex_count(), 35)
    assert_equal(len(strip.index), 144)
    assert_vertex(
        strip, 0, [1.5, 0, 0], [0, 0.164398983, 0.986393929], [0, 0], 1e-5, 5e-3
    )
    assert_vertex(
        strip,
        9,
        [1.21650636, 2.10705090, 0.25],
        [-0.160183802, -0.481845081, 0.861490846],
        [1, 0.166666672],
        1e-5,
        5e-3,
    )
    assert_vertex(
        strip,
        34,
        [1.5, 0, 0],
        [0, -0.164398983, -0.986393929],
        [1, 1],
        1e-5,
        5e-3,
    )


def test_a_parametric_grid_is_indexed_as_three_js_indexes_it() raises:
    var sheet = parametric(SurfaceFunction[parametric_plane](), 2, 3)
    assert_equal(sheet.vertex_count(), 12)
    # The first cell: a, b, d then b, c, d, with rows of three vertices.
    var expected = [0, 1, 3, 1, 4, 3]
    for slot in range(6):
        assert_equal(sheet.index[slot], expected[slot])
    # The plane is (u, 0, v), so u crossed with v points down y.
    ref normals = sheet.attribute_view(String(NORMAL))
    for vertex in range(sheet.vertex_count()):
        assert_near(normals.vector3(vertex), 0, -1, 0, 1e-6)
    assert_near(sheet.attribute_view(String(POSITION)).vector3(11), 1, 0, 1, 0)


def test_a_surface_can_hold_its_own_numbers() raises:
    var dome = parametric(Dome(2), 12, 4)
    ref positions = dome.attribute_view(String(POSITION))
    ref normals = dome.attribute_view(String(NORMAL))
    for vertex in range(dome.vertex_count()):
        var p = positions.vector3(vertex)
        assert_almost_equal(Float64(p.length()), 2, atol=1e-5)
    # Around this dome, u crossed with v points away from the center.
    var n = normals.vector3(13)
    var p = positions.vector3(13)
    assert_true(n.dot(p) > 0)


def test_the_thick_mobius_band_starts_on_its_center_circle() raises:
    var band = parametric(SurfaceFunction[mobius3d](), 16, 4)
    assert_near(
        band.attribute_view(String(POSITION)).vector3(0), 2.375, 0, 0, 1e-6
    )
    assert_equal(EPS, Float32(0.00001))


def test_a_parametric_surface_needs_cells_and_finite_points() raises:
    with assert_raises():
        _ = parametric(SurfaceFunction[klein](), 0, 8)
    with assert_raises():
        _ = parametric(SurfaceFunction[klein](), 8, 0)
    for axis in range(3):
        with assert_raises():
            _ = parametric(Broken(axis))


# --- Convex hull -------------------------------------------------------------


def twelve_points() -> List[Vector3]:
    """Return the twelve points the three.js reference was run on."""
    var points = List[Vector3]()
    for i in range(12):
        points.append(
            Vector3(
                Float32((i * 7) % 11 - 5) * 0.25,
                Float32((i * 5) % 13 - 6) * 0.25,
                Float32((i * 3) % 7 - 3) * 0.25,
            )
        )
    return points^


def cloud(count: Int) -> List[Vector3]:
    """Return a fixed cloud of points spread through a cube."""
    var points = List[Vector3]()
    var state = UInt32(12345)
    for _ in range(count):
        var xyz = List[Float32]()
        for _ in range(3):
            state = state * 1664525 + 1013904223
            xyz.append(Float32(state >> 8) / Float32(1 << 24) * 2 - 1)
        points.append(Vector3(xyz[0], xyz[1], xyz[2]))
    return points^


def test_a_convex_geometry_matches_three_js() raises:
    var hull = convex(twelve_points())
    var expected_positions: List[Float64] = [
        -1.25,
        -0.75,
        0.5,
        -0.5,
        1,
        0.75,
        -0.75,
        1.5,
        -0.5,
        -1.25,
        -0.75,
        0.5,
        -0.75,
        1.5,
        -0.5,
        -1.25,
        -1.5,
        -0.75,
        0,
        0.75,
        -0.75,
        1.25,
        -1,
        -0.25,
        -1.25,
        -1.5,
        -0.75,
        0,
        0.75,
        -0.75,
        -1.25,
        -1.5,
        -0.75,
        -0.75,
        1.5,
        -0.5,
        0.75,
        0,
        0.75,
        -0.5,
        1,
        0.75,
        -1.25,
        -0.75,
        0.5,
        0.75,
        0,
        0.75,
        -1.25,
        -0.75,
        0.5,
        1.25,
        -1,
        -0.25,
        0.75,
        0,
        0.75,
        1.25,
        -1,
        -0.25,
        0,
        0.75,
        -0.75,
        -1,
        -1.25,
        0,
        1.25,
        -1,
        -0.25,
        -1.25,
        -0.75,
        0.5,
        -1,
        -1.25,
        0,
        -1.25,
        -0.75,
        0.5,
        -1.25,
        -1.5,
        -0.75,
        -1,
        -1.25,
        0,
        -1.25,
        -1.5,
        -0.75,
        1.25,
        -1,
        -0.25,
        -0.25,
        1.25,
        -0.25,
        -0.75,
        1.5,
        -0.5,
        -0.5,
        1,
        0.75,
        -0.25,
        1.25,
        -0.25,
        -0.5,
        1,
        0.75,
        0.75,
        0,
        0.75,
        -0.25,
        1.25,
        -0.25,
        0.75,
        0,
        0.75,
        0,
        0.75,
        -0.75,
        -0.25,
        1.25,
        -0.25,
        0,
        0.75,
        -0.75,
        -0.75,
        1.5,
        -0.5,
    ]
    # One normal per face, in face order.
    var expected_normals: List[Float64] = [
        -0.888540387,
        0.336204469,
        0.312189877,
        -0.979705453,
        0.171878144,
        -0.103126891,
        0.217897877,
        -0.121054374,
        -0.968434989,
        -0.208123773,
        0.115624323,
        -0.971244335,
        -0.0843274072,
        -0.105409257,
        0.990846992,
        0.154996857,
        -0.658736646,
        0.736235023,
        0.824163377,
        0.549442232,
        -0.137360558,
        0.154996857,
        -0.658736646,
        0.736235023,
        -0.565685451,
        -0.707106769,
        0.424264073,
        0.136082768,
        -0.952579319,
        0.272165537,
        0.301511347,
        0.904534042,
        0.301511347,
        0.589367568,
        0.736709476,
        0.331519246,
        0.824163377,
        0.549442232,
        -0.137360558,
        0.565685451,
        0.707106769,
        -0.424264073,
    ]
    assert_equal(hull.vertex_count(), 42)
    assert_false(hull.is_indexed())
    assert_false(hull.has_attribute(String(UV)))
    ref positions = hull.attribute_view(String(POSITION))
    ref normals = hull.attribute_view(String(NORMAL))
    for vertex in range(42):
        assert_near(
            positions.vector3(vertex),
            expected_positions[vertex * 3],
            expected_positions[vertex * 3 + 1],
            expected_positions[vertex * 3 + 2],
            0,
        )
        var face = vertex // 3
        assert_near(
            normals.vector3(vertex),
            expected_normals[face * 3],
            expected_normals[face * 3 + 1],
            expected_normals[face * 3 + 2],
            1e-7,
        )


def check_hull(points: List[Vector3]) raises -> Int:
    """Check a hull is closed, convex and holds every point, and return its
    face count."""
    var hull = ConvexHull(points)
    var used = List[Bool](length=len(points), fill=False)
    for face in range(hull.face_count()):
        var normal = hull.face_normal(face)
        assert_almost_equal(Float64(normal.length()), 1, atol=1e-6)
        var a = points[hull.face_vertex(face, 0)]
        for corner in range(3):
            used[hull.face_vertex(face, corner)] = True
        # Every point is on the inner side of every face.
        for point in points:
            assert_true(normal.dot(point - a) < 1e-5)
    var on_hull = 0
    for flag in used:
        if flag:
            on_hull += 1
    # A closed surface of triangles has two faces for every vertex, less
    # four.
    assert_equal(hull.face_count(), 2 * on_hull - 4)
    for point in points:
        assert_true(hull.contains_point(point))
    assert_false(hull.contains_point(Vector3(5, 0, 0)))
    return hull.face_count()


def test_a_hull_is_closed_and_holds_every_point() raises:
    _ = check_hull(twelve_points())
    _ = check_hull(cloud(300))
    # Mirroring the set turns the first tetrahedron the other way.
    var mirrored = List[Vector3]()
    for point in twelve_points():
        mirrored.append(Vector3(point.x, point.y, -point.z))
    _ = check_hull(mirrored^)


def test_the_hull_of_a_cube_and_its_inside_is_the_cube() raises:
    var points = List[Vector3]()
    for i in range(8):
        points.append(
            Vector3(
                Float32(i & 1), Float32((i >> 1) & 1), Float32((i >> 2) & 1)
            )
        )
    points.append(Vector3(0.5, 0.5, 0.5))
    points.append(Vector3(0.25, 0.75, 0.5))
    # A point on a face and a repeated corner are not outside any face.
    points.append(Vector3(0.5, 0.5, 1))
    points.append(Vector3(1, 1, 1))
    var faces = check_hull(points)
    assert_equal(faces, 12)
    var hull = ConvexHull(points)
    assert_true(hull.contains_point(Vector3(0.5, 0.5, 0.5)))
    assert_true(hull.tolerance > 0)


def test_a_hull_refuses_what_has_no_inside() raises:
    var three = List[Vector3]()
    three.append(Vector3(0, 0, 0))
    three.append(Vector3(1, 0, 0))
    three.append(Vector3(0, 1, 0))
    with assert_raises(contains="four points"):
        _ = ConvexHull(three)
    var same = List[Vector3]()
    for _ in range(5):
        same.append(Vector3(1, 2, 3))
    with assert_raises(contains="more than one place"):
        _ = ConvexHull(same)
    var line = List[Vector3]()
    for i in range(5):
        line.append(Vector3(Float32(i), Float32(2 * i), 0))
    with assert_raises(contains="in a line"):
        _ = ConvexHull(line)
    var flat = List[Vector3]()
    for i in range(6):
        flat.append(Vector3(Float32(i % 3), Float32(i // 3), 0))
    with assert_raises(contains="in a plane"):
        _ = convex(flat)
    for axis in range(3):
        var bad = cloud(5)
        if axis == 0:
            bad[2].x = nan[DType.float32]()
        elif axis == 1:
            bad[2].y = nan[DType.float32]()
        else:
            bad[2].z = nan[DType.float32]()
        with assert_raises(contains="finite"):
            _ = ConvexHull(bad)


def test_a_hull_face_must_exist() raises:
    var hull = ConvexHull(twelve_points())
    with assert_raises():
        _ = hull.face_vertex(-1, 0)
    with assert_raises():
        _ = hull.face_vertex(hull.face_count(), 0)
    with assert_raises():
        _ = hull.face_vertex(0, -1)
    with assert_raises():
        _ = hull.face_vertex(0, 3)
    with assert_raises():
        _ = hull.face_normal(-1)
    with assert_raises():
        _ = hull.face_normal(hull.face_count())


# --- Decal -------------------------------------------------------------------


def grid(with_normals: Bool) raises -> BufferGeometry:
    """Return the indexed four by four grid the three.js reference used."""
    var positions = List[Float32]()
    var normals = List[Float32]()
    for j in range(4):
        for i in range(4):
            positions.append(Float32(i) - 1.5)
            positions.append(Float32(j) - 1.5)
            positions.append(0)
            normals.append(0)
            normals.append(0)
            normals.append(1)
    var index = List[Int]()
    for j in range(3):
        for i in range(3):
            var a = j * 4 + i
            index.append(a)
            index.append(a + 1)
            index.append(a + 5)
            index.append(a)
            index.append(a + 5)
            index.append(a + 4)
    var geometry = BufferGeometry()
    geometry.set_attribute(String(POSITION), BufferAttribute(positions^, 3))
    if with_normals:
        geometry.set_attribute(String(NORMAL), BufferAttribute(normals^, 3))
    geometry.set_index(index^)
    return geometry^


def reference_world() -> Matrix4:
    """Return the mesh's world matrix: moved, turned about x, stretched in y."""
    var world = translation(0.5, 0.25, -1)
    world.multiply(rotation_x(Angle(0.3, RADIAN)))
    world.multiply(scaling(1, 2, 1))
    return world


def reference_orientation() -> Euler:
    """Return the projector's orientation from the three.js reference."""
    return Euler(
        Angle(0.3, RADIAN), Angle(0.2, RADIAN), Angle(0.1, RADIAN), XYZ
    )


def test_a_decal_matches_three_js() raises:
    var sticker = decal(
        grid(True),
        reference_world(),
        Vector3(0.6, 0.4, -1.2),
        reference_orientation(),
        meters(1.3),
        meters(0.9),
        meters(2),
    )
    assert_equal(sticker.vertex_count(), 57)
    assert_false(sticker.is_indexed())
    var normal: List[Float64] = [0, -0.295520216, 0.955336511]
    assert_vertex(
        sticker,
        0,
        [0, 0.154689834, -1.02948284],
        normal,
        [0, 0.367034853],
        2e-6,
        1e-6,
    )
    assert_vertex(
        sticker,
        3,
        [1, 0.795590281, -0.831229150],
        normal,
        [0.801649928, 1],
        2e-6,
        1e-6,
    )
    assert_vertex(
        sticker,
        13,
        [0.298813879, -0.134400889, -1.11890912],
        normal,
        [0.200910941, 0],
        2e-6,
        1e-6,
    )
    assert_vertex(
        sticker,
        27,
        [0.0336488448, -0.159311205, -1.12661481],
        normal,
        [0, 0],
        2e-6,
        1e-6,
    )
    assert_vertex(
        sticker,
        39,
        [1.35298777, -0.0308923740, -1.08689022],
        normal,
        [1, 0.00518052513],
        2e-6,
        1e-6,
    )
    assert_vertex(
        sticker,
        44,
        [1.11394095, 0.806294143, -0.827918053],
        normal,
        [0.887980998, 1],
        2e-6,
        1e-6,
    )
    assert_vertex(
        sticker,
        55,
        [1.26178515, 0.820183039, -0.823621690],
        normal,
        [1, 1],
        2e-6,
        1e-6,
    )
    assert_vertex(
        sticker,
        56,
        [1.11394095, 0.806294143, -0.827918053],
        normal,
        [0.887980998, 1],
        2e-6,
        1e-6,
    )


def triangle(a: Vector3, b: Vector3, c: Vector3) raises -> BufferGeometry:
    """Return one triangle without an index or normals."""
    var data: List[Float32] = [a.x, a.y, a.z, b.x, b.y, b.z, c.x, c.y, c.z]
    var geometry = BufferGeometry()
    geometry.set_attribute(String(POSITION), BufferAttribute(data^, 3))
    return geometry^


def unit_decal(geometry: BufferGeometry) raises -> BufferGeometry:
    """Return a decal through a box two meters each way at the origin."""
    return decal(
        geometry,
        Matrix4(),
        Vector3(0, 0, 0),
        Euler(Angle(0, RADIAN), Angle(0, RADIAN), Angle(0, RADIAN), XYZ),
        meters(2),
        meters(2),
        meters(2),
    )


def assert_inside_the_box(geometry: BufferGeometry) raises:
    """Assert every vertex is inside the two meter box, and every texture
    coordinate is between zero and one."""
    ref positions = geometry.attribute_view(String(POSITION))
    ref uvs = geometry.attribute_view(String(UV))
    for vertex in range(geometry.vertex_count()):
        var p = positions.vector3(vertex)
        assert_true(
            abs(p.x) <= 1.000001
            and abs(p.y) <= 1.000001
            and abs(p.z) <= 1.000001
        )
        assert_true(
            uvs.component(vertex, 0) >= -1e-6
            and uvs.component(vertex, 0) <= 1.000001
        )
        assert_true(
            uvs.component(vertex, 1) >= -1e-6
            and uvs.component(vertex, 1) <= 1.000001
        )


def test_a_triangle_with_one_corner_out_becomes_two() raises:
    var out = Vector3(3, 0, 0)
    var p = Vector3(0, 0.5, 0)
    var q = Vector3(-0.5, -0.5, 0)
    # Each corner in turn is the one outside.
    for first in range(3):
        var corners = [out, p, q]
        var rotated = triangle(
            corners[first], corners[(first + 1) % 3], corners[(first + 2) % 3]
        )
        var cut = unit_decal(rotated)
        assert_equal(cut.vertex_count(), 6)
        assert_false(cut.has_attribute(String(NORMAL)))
        assert_inside_the_box(cut)


def test_a_triangle_with_two_corners_out_becomes_one() raises:
    var inside = Vector3(0, 0, 0)
    var p = Vector3(3, 0.5, 0)
    var q = Vector3(3, -0.5, 0)
    for first in range(3):
        var corners = [inside, p, q]
        var rotated = triangle(
            corners[first], corners[(first + 1) % 3], corners[(first + 2) % 3]
        )
        var cut = unit_decal(rotated)
        assert_equal(cut.vertex_count(), 3)
        assert_inside_the_box(cut)
        # The cut corners lie on the face of the box at x = 1.
        var on_face = 0
        ref positions = cut.attribute_view(String(POSITION))
        for vertex in range(3):
            if abs(positions.vector3(vertex).x - 1) < 1e-6:
                on_face += 1
        assert_equal(on_face, 2)


def test_a_decal_outside_the_mesh_is_empty() raises:
    var far = triangle(Vector3(5, 5, 5), Vector3(6, 5, 5), Vector3(5, 6, 5))
    var cut = unit_decal(far)
    assert_equal(cut.vertex_count(), 0)
    var none = decal(
        grid(True),
        Matrix4(),
        Vector3(10, 0, 0),
        reference_orientation(),
        meters(1),
        meters(1),
        meters(1),
    )
    # three.js adds normals only when there are some to add.
    assert_equal(none.vertex_count(), 0)
    assert_false(none.has_attribute(String(NORMAL)))
    var empty = BufferGeometry()
    empty.set_attribute(String(POSITION), BufferAttribute(List[Float32](), 3))
    assert_equal(unit_decal(empty).vertex_count(), 0)


def test_a_decal_without_normals_has_none() raises:
    var cut = decal(
        grid(False),
        reference_world(),
        Vector3(0.6, 0.4, -1.2),
        reference_orientation(),
        meters(1.3),
        meters(0.9),
        meters(2),
    )
    assert_equal(cut.vertex_count(), 57)
    assert_false(cut.has_attribute(String(NORMAL)))


def test_a_decal_needs_a_box_and_a_mesh_it_can_read() raises:
    var still = Euler(Angle(0, RADIAN), Angle(0, RADIAN), Angle(0, RADIAN), XYZ)
    var one = meters(1)
    var zero = meters(0)
    with assert_raises(contains="positive"):
        _ = decal(
            grid(True), Matrix4(), Vector3(0, 0, 0), still, zero, one, one
        )
    with assert_raises(contains="positive"):
        _ = decal(
            grid(True), Matrix4(), Vector3(0, 0, 0), still, one, zero, one
        )
    with assert_raises(contains="positive"):
        _ = decal(
            grid(True), Matrix4(), Vector3(0, 0, 0), still, one, one, zero
        )
    # A world matrix that flattens the mesh has no normal matrix.
    with assert_raises():
        _ = decal(
            grid(True), scaling(1, 0, 1), Vector3(0, 0, 0), still, one, one, one
        )
    # Without normals it is not needed.
    _ = decal(
        grid(False), scaling(1, 0, 1), Vector3(0, 0, 0), still, one, one, one
    )
    var twisted = Euler(
        Angle(0, RADIAN),
        Angle(0, RADIAN),
        Angle(0, RADIAN),
        EulerOrder(0, 0, 0),
    )
    with assert_raises():
        _ = decal(
            grid(True), Matrix4(), Vector3(0, 0, 0), twisted, one, one, one
        )
    with assert_raises():
        _ = unit_decal(BufferGeometry())


# --- Rounded box -------------------------------------------------------------


def test_a_rounded_box_matches_three_js() raises:
    var soft = rounded_box(meters(2), meters(1.5), meters(1), 2, meters(0.25))
    assert_equal(soft.vertex_count(), 900)
    assert_false(soft.is_indexed())
    assert_equal(len(soft.groups), 6)
    for side in range(6):
        assert_equal(soft.groups[side].start, side * 150)
        assert_equal(soft.groups[side].count, 150)
        assert_equal(soft.groups[side].material_index.value, side)
    var t = 1e-6
    assert_vertex(
        soft,
        0,
        [0.894337595, 0.644337595, 0.394337565],
        [0.577350259, 0.577350259, 0.577350259],
        [0, 1],
        t,
        t,
    )
    assert_vertex(
        soft,
        7,
        [0.954124153, 0.602062106, 0.352062076],
        [0.816496551, 0.408248305, 0.408248305],
        [0.0901060998, 0.942243338],
        t,
        t,
    )
    assert_vertex(
        soft,
        150,
        [-0.894337595, 0.644337595, -0.394337565],
        [-0.577350259, 0.577350259, -0.577350259],
        [0, 1],
        t,
        t,
    )
    assert_vertex(
        soft,
        151,
        [-0.916666687, 0.583333313, -0.416666657],
        [-0.666666687, 0.333333343, -0.666666687],
        [0, 0.942243338],
        t,
        t,
    )
    assert_vertex(
        soft,
        333,
        [-0.926776707, 0.676776707, -0.25],
        [-0.707106769, 0.707106769, 0],
        [0, 0.780049562],
        t,
        t,
    )
    assert_vertex(
        soft,
        512,
        [-0.861803412, -0.723606825, 0.25],
        [-0.447213620, -0.894427180, 0],
        [0.0424989015, 0.780049562],
        t,
        t,
    )
    assert_vertex(
        soft,
        640,
        [-0.75, 0.5, 0.5],
        [0, 0, 1],
        [0.103740498, 0.859015107],
        t,
        t,
    )
    assert_vertex(
        soft,
        777,
        [-0.852062106, 0.602062106, -0.454124153],
        [-0.408248305, 0.408248305, -0.816496551],
        [0.957501113, 0.942243338],
        t,
        t,
    )
    assert_vertex(
        soft,
        899,
        [-0.916666687, -0.583333313, -0.416666657],
        [-0.666666687, -0.333333343, -0.666666687],
        [1, 0.0577566512],
        t,
        t,
    )


def test_a_rounded_box_radius_stops_at_half_the_shortest_side() raises:
    var ball = rounded_box(meters(1), meters(1), meters(1), 1, meters(5))
    assert_equal(ball.vertex_count(), 324)
    var t = 1e-6
    assert_vertex(
        ball,
        0,
        [0.288675129, 0.288675129, 0.288675129],
        [0.577350259, 0.577350259, 0.577350259],
        [0, 1],
        t,
        t,
    )
    assert_vertex(ball, 20, [0.5, 0, 0], [1, 0, 0], [0.5, 0.5], t, t)
    assert_vertex(
        ball,
        53,
        [0.353553385, 0, -0.353553385],
        [0.707106769, 0, -0.707106769],
        [1, 0.5],
        t,
        t,
    )


def test_a_rounded_box_of_no_radius_is_a_box() raises:
    var square = rounded_box(meters(2), meters(1), meters(1), 1, meters(0))
    var bounds = square.bounding_box()
    assert_near(bounds.min, -1, -0.5, -0.5, 1e-6)
    assert_near(bounds.max, 1, 0.5, 0.5, 1e-6)


def test_a_rounded_box_needs_extents_segments_and_a_radius() raises:
    var one = meters(1)
    with assert_raises():
        _ = rounded_box(meters(0), one, one)
    with assert_raises():
        _ = rounded_box(one, meters(0), one)
    with assert_raises():
        _ = rounded_box(one, one, meters(0))
    with assert_raises():
        _ = rounded_box(one, one, one, 0)
    with assert_raises():
        _ = rounded_box(one, one, one, 2, meters(-0.1))


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
