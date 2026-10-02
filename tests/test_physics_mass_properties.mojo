# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Independent solid formulas, geometric laws and atomic mass updates."""

from extensions.physics.body import DYNAMIC, KINEMATIC, STATIC, RigidBody
from extensions.physics.shape import CONVEX, Shape, ShapeKind, Polyhedron
from math.matrix3 import Matrix3
from math.quaternion import Quaternion
from math.vector3 import Vector3
from std.memory import bitcast
from std.math import cos, inf, isfinite, nan, sin
from std.testing import TestSuite, assert_raises, assert_true
from units.si import Angle, Length, Mass, RADIAN


def _equal[T: Equatable](actual: T, expected: T) raises:
    assert_true(actual == expected)


def _near(actual: Float32, expected: Float64, tolerance: Float64 = 2e-6) raises:
    assert_true(isfinite(actual))
    # One subnormal rounding step, plus a relative error bound. No absolute
    # unit-scale tolerance can hide a lost tiny inertia or center.
    assert_true(
        abs(Float64(actual) - expected)
        <= abs(expected) * tolerance + 1.401298464324817e-45
    )


def _integration_zero(actual: Float32, scale: Float64) raises:
    assert_true(isfinite(actual))
    # Symmetric polyhedron moments cancel to Float64 roundoff. Bound this
    # by the relevant length/inertia scale, far below a Float32 ulp.
    assert_true(
        abs(Float64(actual)) <= abs(scale) * 1e-14 + 1.401298464324817e-45
    )


def _diagonal(x: Float32, y: Float32, z: Float32) -> Matrix3:
    var out = Matrix3()
    out.elements[0] = x
    out.elements[4] = y
    out.elements[8] = z
    return out


def _body(var shape: Shape, mass: Float32 = 3) raises -> RigidBody:
    return RigidBody(
        DYNAMIC, shape^, Mass(mass), Vector3(0, 0, 0), Quaternion.identity()
    )


def _box(x: Float32, y: Float32, z: Float32) raises -> Shape:
    return Shape.box(Length(x), Length(y), Length(z))


def _check_tensor(tensor: Matrix3) raises:
    for i in range(3):
        for j in range(3):
            assert_true(isfinite(tensor.elements[3 * i + j]))
            _equal(tensor.elements[3 * i + j], tensor.elements[3 * j + i])
    # Use ordinary wide arithmetic here for these well-conditioned fixtures.
    var a = Float64(tensor.elements[0])
    var b = Float64(tensor.elements[1])
    var c = Float64(tensor.elements[2])
    var d = Float64(tensor.elements[4])
    var e = Float64(tensor.elements[5])
    var f = Float64(tensor.elements[8])
    assert_true(a > 0)
    assert_true(a * d - b * b > 0)
    assert_true(
        a * d * f + 2 * b * c * e - a * e * e - d * c * c - f * b * b > 0
    )


def _check_inverse(tensor: Matrix3, inverse: Matrix3) raises:
    _check_tensor(inverse)
    for i in range(3):
        for j in range(3):
            var value = Float64(0)
            for k in range(3):
                value += Float64(tensor.elements[3 * k + i]) * Float64(
                    inverse.elements[3 * j + k]
                )
            assert_true(abs(value - Float64(1 if i == j else 0)) < 3e-6)


def _unchanged(body: RigidBody, before: RigidBody) raises:
    _equal(body.kind, before.kind)
    _equal(body.mass, before.mass)
    _equal(body.inverse_mass, before.inverse_mass)
    _equal(body.inverse_inertia, before.inverse_inertia)
    _equal(body.center_of_mass, before.center_of_mass)
    _equal(body.shape_position, before.shape_position)
    _equal(body.shape_rotation, before.shape_rotation)
    _equal(body._has_dynamic_state, before._has_dynamic_state)
    _equal(body._dynamic_mass, before._dynamic_mass)
    _equal(body._dynamic_inverse_mass, before._dynamic_inverse_mass)
    _equal(body._dynamic_inverse_inertia, before._dynamic_inverse_inertia)
    _equal(body.linear_velocity, before.linear_velocity)
    _equal(body.angular_velocity, before.angular_velocity)
    _equal(body.force, before.force)
    _equal(body.torque, before.torque)


def test_cube_overflow_reproduction() raises:
    var cube = _box(1e8, 1e8, 1e8)
    var props = cube.mass_properties(1e-20)
    var expected = Float64(Float32(1e-20)) * Float64(Float32(1e8)) ** 2 * 2 / 3
    for i in [0, 4, 8]:
        _near(props.inertia.elements[i], expected)
    _integration_zero(props.center.x, 1e8)
    _integration_zero(props.center.y, 1e8)
    _integration_zero(props.center.z, 1e8)
    _check_tensor(props.inertia)
    var body = _body(cube^, 1e-20)
    _check_inverse(props.inertia, body.inverse_inertia)


def test_cuboids_spheres_capsules_across_scales() raises:
    var sizes = [
        Float32(1e-38),
        Float32(1e-20),
        Float32(1e-8),
        Float32(1),
        Float32(1e8),
        Float32(1e20),
        Float32(1e37),
    ]
    var masses = [
        Float32(1e38),
        Float32(1e30),
        Float32(1e8),
        Float32(12),
        Float32(1e-20),
        Float32(1e-20),
        Float32(1e-38),
    ]
    for index in range(len(sizes)):
        var size = sizes[index]
        var mass = masses[index]
        var x = Float64(size)
        var y = Float64(2 * size)
        var z = Float64(3 * size)
        var m = Float64(mass)
        var box = _box(size, 2 * size, 3 * size)
        var box_props = box.mass_properties(mass)
        _integration_zero(box_props.center.x, x)
        _integration_zero(box_props.center.y, y)
        _integration_zero(box_props.center.z, z)
        _near(box_props.inertia.elements[0], m * (y * y + z * z) / 3)
        _near(box_props.inertia.elements[4], m * (x * x + z * z) / 3)
        _near(box_props.inertia.elements[8], m * (x * x + y * y) / 3)
        for i in [1, 2, 3, 5, 6, 7]:
            _integration_zero(
                box_props.inertia.elements[i], m * (x * x + y * y + z * z)
            )
        _check_tensor(box_props.inertia)
        var box_body = _body(box^, mass)
        _check_inverse(box_props.inertia, box_body.inverse_inertia)
        var sphere = Shape.sphere(Length(size))
        var sphere_props = sphere.mass_properties(mass)
        _equal(sphere_props.center, Vector3(0, 0, 0))
        for i in [0, 4, 8]:
            _near(sphere_props.inertia.elements[i], 2 * m * x * x / 5)
        var sphere_body = _body(sphere^, mass)
        _check_inverse(sphere_props.inertia, sphere_body.inverse_inertia)
        # r=s and half-height=s: cylinder mass is 3m/5, caps are 2m/5.
        # Closed formulas: transverse 121 m r^2 / 100, axial 23 m r^2 / 50.
        var capsule = Shape.capsule(Length(size), Length(size))
        var capsule_props = capsule.mass_properties(mass)
        _equal(capsule_props.center, Vector3(0, 0, 0))
        _near(capsule_props.inertia.elements[0], 121 * m * x * x / 100)
        _near(capsule_props.inertia.elements[4], 121 * m * x * x / 100)
        _near(capsule_props.inertia.elements[8], 23 * m * x * x / 50)
        var capsule_body = _body(capsule^, mass)
        _check_inverse(capsule_props.inertia, capsule_body.inverse_inertia)
        var ball = Shape.capsule(Length(size), Length(0)).mass_properties(mass)
        for i in range(9):
            _equal(ball.inertia.elements[i], sphere_props.inertia.elements[i])


def test_capsule_extreme_aspect_ratios() raises:
    # A long thin cylinder with negligible caps, and a sphere with a tiny
    # segment. No intermediate r^2*h or r^3 is representable in Float32.
    var thin = Shape.capsule(Length(1e-10), Length(1e10)).mass_properties(1e10)
    _near(thin.inertia.elements[0], Float64(Float32(1e10)) ** 3 / 3)
    _near(
        thin.inertia.elements[8],
        Float64(Float32(1e10)) * Float64(Float32(1e-10)) ** 2 / 2,
    )
    var round = Shape.capsule(Length(1e10), Length(1e-10)).mass_properties(
        1e-10
    )
    var expected = 2 * Float64(Float32(1e-10)) * Float64(Float32(1e10)) ** 2 / 5
    _near(round.inertia.elements[0], expected)
    _near(round.inertia.elements[8], expected)
    var smallest = bitcast[DType.float32](UInt32(1))
    var recovered = Shape.sphere(Length(1e20)).mass_properties(smallest)
    _near(
        recovered.inertia.elements[0],
        0.4 * Float64(smallest) * Float64(Float32(1e20)) ** 2,
    )
    var enormous = Shape.sphere(Length(2e38)).mass_properties(1e-38)
    _near(
        enormous.inertia.elements[0],
        0.4 * Float64(Float32(1e-38)) * Float64(Float32(2e38)) ** 2,
    )


def test_cuboid_extreme_aspect_ratio() raises:
    var x = Float32(1e-30)
    var z = Float32(1e30)
    var mass = Float32(1e-30)
    var shape = _box(x, 1, z)
    var props = shape.mass_properties(mass)
    _near(props.inertia.elements[0], Float64(mass) * (1 + Float64(z) ** 2) / 3)
    _near(
        props.inertia.elements[4],
        Float64(mass) * (Float64(x) ** 2 + Float64(z) ** 2) / 3,
    )
    _near(props.inertia.elements[8], Float64(mass) * (Float64(x) ** 2 + 1) / 3)
    var body = _body(shape^, mass)
    _check_inverse(props.inertia, body.inverse_inertia)


def test_translated_convex_cuboid() raises:
    for center in [Vector3(1e8, -2e8, 3e8), Vector3(1e38, -1e38, 1e38)]:
        var half = Float32(32) if center.x < 1e20 else Float32(1e32)
        var points = List[Vector3]()
        for i in range(8):
            points.append(
                center
                + Vector3(
                    half if i & 1 else -half,
                    2 * half if i & 2 else -2 * half,
                    4 * half if i & 4 else -4 * half,
                )
            )
        # Use the represented coordinates, not an unrepresentable ideal
        # displacement at the large origin.
        var x = (Float64(points[7].x) - Float64(points[0].x)) / 2
        var y = (Float64(points[7].y) - Float64(points[0].y)) / 2
        var z = (Float64(points[7].z) - Float64(points[0].z)) / 2
        var mass = Float32(3) if center.x < 1e20 else Float32(1e-30)
        var shape = Shape.convex(points)
        var props = shape.mass_properties(mass)
        _equal(props.center, center)
        _near(props.inertia.elements[0], Float64(mass) * (y * y + z * z) / 3)
        _near(props.inertia.elements[4], Float64(mass) * (x * x + z * z) / 3)
        _near(props.inertia.elements[8], Float64(mass) * (x * x + y * y) / 3)
        _check_tensor(props.inertia)
        var body = _body(shape^, mass)
        _check_inverse(props.inertia, body.inverse_inertia)


def test_scaled_rotated_translated_tetrahedra() raises:
    # R is orthogonal, with exact rational entries; use it independently
    # for the expected R I R^T rather than the library matrix product.
    var r = [
        Float64(0.36),
        Float64(-0.48),
        Float64(0.8),
        Float64(0.8),
        Float64(0.6),
        Float64(0),
        Float64(-0.48),
        Float64(0.64),
        Float64(0.6),
    ]
    for scale in [
        Float32(1e-30),
        Float32(1e-10),
        Float32(1),
        Float32(1e10),
        Float32(1e30),
    ]:
        var mass = Float32(1 / Float64(scale))
        var s = Float64(scale)
        var shift = [8 * s, -12 * s, 16 * s]
        var points = List[Vector3]()
        for k in range(4):
            var c = [Float64(0), Float64(0), Float64(0)]
            for i in range(3):
                c[i] = shift[i]
                if k > 0:
                    c[i] += r[3 * i + k - 1] * Float64(k) * s
            points.append(Vector3(Float32(c[0]), Float32(c[1]), Float32(c[2])))
        var shape = Shape.convex(points)
        var props = shape.mass_properties(mass)
        var expected_center = [Float64(0), Float64(0), Float64(0)]
        for i in range(3):
            expected_center[i] = (
                shift[i]
                + s * (r[3 * i] + 2 * r[3 * i + 1] + 3 * r[3 * i + 2]) / 4
            )
        _near(props.center.x, expected_center[0])
        _near(props.center.y, expected_center[1])
        _near(props.center.z, expected_center[2])
        # Right tetrahedron edges s, 2s, 3s: diagonal covariance is
        # 3m a_i^2/80, off-diagonal covariance is -m a_i a_j/80.
        var factor = Float64(mass) * s * s / 80
        var original = [
            39 * factor,
            2 * factor,
            3 * factor,
            2 * factor,
            30 * factor,
            6 * factor,
            3 * factor,
            6 * factor,
            15 * factor,
        ]
        for i in range(3):
            for j in range(3):
                var expected = Float64(0)
                for k in range(3):
                    for l in range(3):
                        expected += (
                            r[3 * i + k] * original[3 * k + l] * r[3 * j + l]
                        )
                _near(props.inertia.elements[3 * j + i], expected, 2e-5)
        _check_tensor(props.inertia)
        var body = _body(shape^, mass)
        _check_inverse(props.inertia, body.inverse_inertia)


def test_shape_pose_rotation_and_mass_scaling() raises:
    var body = _body(_box(1e10, 2e10, 3e10), 1e-10)
    var angle = Float32(0.7)
    var rotation = Quaternion.from_axis_angle(
        Vector3(0, 0, 1), Angle(angle, RADIAN)
    )
    body.set_shape_pose(Vector3(7, -8, 9), rotation)
    _equal(body.center_of_mass, Vector3(7, -8, 9))
    var x = Float64(Float32(1e10))
    var m = Float64(Float32(1e-10))
    var ixx = m * 13 * x * x / 3
    var iyy = m * 10 * x * x / 3
    var izz = m * 5 * x * x / 3
    var c = cos(Float64(angle))
    var s = sin(Float64(angle))
    var expected = _diagonal(
        Float32(c * c / ixx + s * s / iyy),
        Float32(s * s / ixx + c * c / iyy),
        Float32(1 / izz),
    )
    expected.elements[1] = Float32(c * s * (1 / ixx - 1 / iyy))
    expected.elements[3] = expected.elements[1]
    for i in range(9):
        _near(body.inverse_inertia.elements[i], Float64(expected.elements[i]))
    var previous = body.inverse_inertia
    body.set_mass(Mass(2 * Float32(1e-10)))
    for i in range(9):
        _near(
            body.inverse_inertia.elements[i], Float64(previous.elements[i]) / 2
        )
    # Pose quaternions have the same normalization contract as body poses.
    body.set_shape_pose(
        Vector3(0, 0, 0),
        Quaternion(
            rotation.x * 2, rotation.y * 2, rotation.z * 2, rotation.w * 2
        ),
    )
    for i in range(9):
        _near(
            body.inverse_inertia.elements[i], Float64(previous.elements[i]) / 2
        )


def test_custom_spd_tensors_across_scales() raises:
    var body = _body(_box(1, 1, 1))
    for scale in [Float32(1e-30), Float32(1), Float32(1e30)]:
        var tensor = _diagonal(4 * scale, 5 * scale, 6 * scale)
        tensor.elements[1] = scale
        tensor.elements[3] = scale
        tensor.elements[2] = -scale
        tensor.elements[6] = -scale
        tensor.elements[5] = scale / 2
        tensor.elements[7] = scale / 2
        body.set_inertia(tensor)
        _check_inverse(tensor, body.inverse_inertia)
    var uneven = _diagonal(1e-30, 1, 1e30)
    body.set_inertia(uneven)
    _check_inverse(uneven, body.inverse_inertia)
    var retained = body.inverse_inertia
    body.set_kind(KINEMATIC)
    body.set_kind(DYNAMIC)
    _equal(body.inverse_inertia, retained)
    # The public inverse field still supports intentional locked axes.
    body.inverse_inertia.elements[0] = 0
    body.inverse_inertia.elements[4] = 0
    body.inverse_inertia.elements[8] = 0
    body.set_kind(STATIC)
    body.set_kind(DYNAMIC)
    _equal(body.inverse_inertia, _diagonal(0, 0, 0))


def test_invalid_inertia_updates_are_atomic() raises:
    var body = _body(_box(1, 2, 3))
    body.set_center_of_mass(Vector3(4, 5, 6))
    var before = body.copy()
    for bad in [
        Float32(0),
        Float32(-1),
        Float32(1e-39),
        inf[DType.float32](),
        nan[DType.float32](),
    ]:
        with assert_raises():
            body.set_inertia(_diagonal(bad, bad, bad))
        _unchanged(body, before)
    for i in range(9):
        var tensor = Matrix3()
        tensor.elements[i] = nan[DType.float32]()
        with assert_raises():
            body.set_inertia(tensor)
        _unchanged(body, before)
    for i in [1, 2, 5]:
        var tensor = Matrix3()
        tensor.elements[i] = 0.25
        with assert_raises():
            body.set_inertia(tensor)
        _unchanged(body, before)
    for tensor in [
        _diagonal(1, 0, 1),
        _diagonal(1, -1, 1),
        _diagonal(1, 1, 0),
        _diagonal(1, 1, -1),
    ]:
        with assert_raises():
            body.set_inertia(tensor)
        _unchanged(body, before)
    var indefinite = Matrix3()
    indefinite.elements[1] = 2
    indefinite.elements[3] = 2
    with assert_raises():
        body.set_inertia(indefinite)
    _unchanged(body, before)


def test_exactly_singular_tensor_is_not_rounded_positive() raises:
    var body = _body(_box(1, 2, 3))
    var before = body.copy()
    # u*u^T + v*v^T has rank two, exactly, with integer entries that fit
    # Float32. Ordinary Float64 elimination can leave a positive pivot.
    # This case can also leave an apparently positive rounded inverse.
    var u = [Float64(-134), Float64(65), Float64(198)]
    var v = [Float64(87), Float64(-95), Float64(18)]
    var singular = Matrix3()
    for i in range(3):
        for j in range(3):
            singular.elements[3 * j + i] = Float32(u[i] * u[j] + v[i] * v[j])
    with assert_raises():
        body.set_inertia(singular)
    _unchanged(body, before)
    var large = Matrix3()
    large.set(
        859325,
        -1967270,
        -2140,
        -1967270,
        5265220,
        -385448,
        -2140,
        -385448,
        200096,
    )
    with assert_raises():
        body.set_inertia(large)
    _unchanged(body, before)
    # A one-unit positive perturbation is genuinely invertible. It must
    # not be rejected by a condition-number or determinant-size cutoff.
    var positive = singular
    positive.elements[8] += 1
    body.set_inertia(positive)
    for i in range(3):
        assert_true(body.inverse_inertia.elements[4 * i] > 0)
    var negative = singular
    negative.elements[8] -= 1
    var positive_state = body.copy()
    with assert_raises():
        body.set_inertia(negative)
    _unchanged(body, positive_state)


def test_invalid_mass_updates_are_atomic() raises:
    var body = _body(_box(1e8, 2e8, 3e8), 1e-20)
    body.set_shape_pose(Vector3(1, 2, 3), Quaternion.identity())
    body.set_center_of_mass(Vector3(4, 5, 6))
    var before = body.copy()
    for bad in [
        Float32(0),
        Float32(-1),
        Float32(1e-40),
        Float32(1e38),
        inf[DType.float32](),
        nan[DType.float32](),
    ]:
        with assert_raises():
            body.set_mass(Mass(bad))
        _unchanged(body, before)
    # The tensor itself fits; its inverse would overflow.
    var tiny = Shape.sphere(Length(1e-20))
    _check_tensor(tiny.mass_properties(1).inertia)
    with assert_raises():
        _ = _body(tiny^, 1)
    # A valid original state and a zero-volume edited shape. set_mass must
    # not overwrite the configured center or inverse when geometry fails.
    for i in range(len(body.shape.polyhedron.vertices)):
        body.shape.polyhedron.vertices[i].z = 0
    before = body.copy()
    with assert_raises():
        body.set_mass(Mass(2))
    _unchanged(body, before)


def test_invalid_pose_and_center_updates_are_atomic() raises:
    var body = _body(_box(1, 2, 3))
    var before = body.copy()
    for bad in [inf[DType.float32](), nan[DType.float32]()]:
        for position in [
            Vector3(bad, 0, 0),
            Vector3(0, bad, 0),
            Vector3(0, 0, bad),
        ]:
            with assert_raises():
                body.set_shape_pose(position, Quaternion.identity())
            _unchanged(body, before)
            with assert_raises():
                body.set_center_of_mass(position)
            _unchanged(body, before)
        for rotation in [
            Quaternion(bad, 0, 0, 1),
            Quaternion(0, bad, 0, 1),
            Quaternion(0, 0, bad, 1),
            Quaternion(0, 0, 0, bad),
        ]:
            with assert_raises():
                body.set_shape_pose(Vector3(1, 2, 3), rotation)
            _unchanged(body, before)
    # A finite shape offset can still produce a nonrepresentable center.
    var points: List[Vector3] = [
        Vector3(2e38, 0, 0),
        Vector3(2e38, 1e32, 0),
        Vector3(2e38, 0, 1e32),
        Vector3(2e38 + 1e32, 0, 0),
    ]
    var far = _body(Shape.convex(points), 1e-30)
    var far_before = far.copy()
    with assert_raises():
        far.set_shape_pose(Vector3(2e38, 0, 0), Quaternion.identity())
    _unchanged(far, far_before)
    # Failure after the pose has passed validation also stays atomic.
    body.shape.radius = 0
    body.shape = Shape.sphere(Length(1e-20))
    before = body.copy()
    with assert_raises():
        body.set_shape_pose(Vector3(1, 2, 3), Quaternion.identity())
    _unchanged(body, before)


def test_invalid_mass_properties_are_rejected() raises:
    var sphere = Shape.sphere(Length(1))
    for mass in [
        Float32(0),
        Float32(-1),
        inf[DType.float32](),
        nan[DType.float32](),
    ]:
        with assert_raises():
            _ = sphere.mass_properties(mass)
    for radius in [
        Float32(0),
        Float32(-1),
        inf[DType.float32](),
        nan[DType.float32](),
    ]:
        sphere.radius = radius
        with assert_raises():
            _ = sphere.mass_properties(1)
    with assert_raises():
        _ = Shape.sphere(Length(1e-30)).mass_properties(1e-30)
    with assert_raises():
        _ = Shape.sphere(Length(1e30)).mass_properties(1e30)
    var capsule = Shape.capsule(Length(1), Length(1))
    for height in [Float32(-1), inf[DType.float32](), nan[DType.float32]()]:
        capsule.half_height = height
        with assert_raises():
            _ = capsule.mass_properties(1)
    with assert_raises():
        _ = Shape(ShapeKind(9)).mass_properties(1)
    with assert_raises():
        _ = Shape(CONVEX).mass_properties(1)
    var flat = Shape(CONVEX)
    flat.polyhedron = Polyhedron.box(Vector3(1, 1, 0))
    with assert_raises():
        _ = flat.mass_properties(1)
    var malformed = _box(1, 1, 1)
    malformed.polyhedron.normals.clear()
    with assert_raises():
        _ = malformed.mass_properties(1)
    malformed = _box(1, 1, 1)
    malformed.polyhedron.face_start.clear()
    with assert_raises():
        _ = malformed.mass_properties(1)
    for bad in [-1, 100, 2]:
        malformed = _box(1, 1, 1)
        malformed.polyhedron.face_start[1] = bad
        with assert_raises():
            _ = malformed.mass_properties(1)
    malformed = _box(1, 1, 1)
    malformed.polyhedron.face_start[0] = -1
    with assert_raises():
        _ = malformed.mass_properties(1)
    for bad in [-1, 100]:
        malformed = _box(1, 1, 1)
        malformed.polyhedron.face_corners[0] = bad
        with assert_raises():
            _ = malformed.mass_properties(1)
    malformed = _box(1, 1, 1)
    malformed.polyhedron.vertices[0].x = inf[DType.float32]()
    with assert_raises():
        _ = malformed.mass_properties(1)


def test_spd_inertia_inverse_retains_all_determinant_components() raises:
    # n*J + I is SPD, with eigenvalues 3*n+1, 1, 1. Its exact inverse
    # is I - n/(3*n+1)*J. This tests determinant magnitude, not only sign.
    var n = Float32(8000000)
    var inertia = Matrix3()
    inertia.set(n + 1, n, n, n, n + 1, n, n, n, n + 1)
    var body = _body(_box(1, 1, 1))
    body.set_inertia(inertia)
    for row in range(3):
        for column in range(3):
            var numerator = Float64(16000001) if row == column else Float64(
                -8000000
            )
            _equal(
                body.inverse_inertia.elements[3 * column + row],
                Float32(numerator / 24000001),
            )


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
