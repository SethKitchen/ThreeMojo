# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Free-top invariants and independent coupled-Euler reference trajectories."""

from extensions.physics.body import DYNAMIC, KINEMATIC, RigidBody
from extensions.physics.shape import Shape, cross
from extensions.physics.world import PhysicsWorld
from math.matrix3 import Matrix3
from math.quaternion import Quaternion
from math.vector3 import Vector3
from std.math import cos, isfinite, sin, sqrt
from std.testing import TestSuite, assert_true
from units.si import Duration, Length, Mass, SECOND

comptime Wide = SIMD[DType.float64, 4]


def _equal[T: Equatable](actual: T, expected: T) raises:
    assert_true(actual == expected)


def _dot(a: Wide, b: Wide) -> Float64:
    return a[0] * b[0] + a[1] * b[1] + a[2] * b[2]


def _cross(a: Wide, b: Wide) -> Wide:
    return Wide(
        a[1] * b[2] - a[2] * b[1],
        a[2] * b[0] - a[0] * b[2],
        a[0] * b[1] - a[1] * b[0],
        0,
    )


def _v(v: Vector3) -> Wide:
    return Wide(Float64(v.x), Float64(v.y), Float64(v.z), 0)


def _q(q: Quaternion) -> Wide:
    var out = Wide(Float64(q.x), Float64(q.y), Float64(q.z), Float64(q.w))
    return out / sqrt(_dot(out, out) + out[3] * out[3])


def _multiply(a: Wide, b: Wide) -> Wide:
    return Wide(
        a[3] * b[0] + a[0] * b[3] + a[1] * b[2] - a[2] * b[1],
        a[3] * b[1] - a[0] * b[2] + a[1] * b[3] + a[2] * b[0],
        a[3] * b[2] + a[0] * b[1] - a[1] * b[0] + a[2] * b[3],
        a[3] * b[3] - _dot(a, b),
    )


def _rotate(q: Wide, v: Wide) -> Wide:
    var conjugate = Wide(-q[0], -q[1], -q[2], q[3])
    return _multiply(_multiply(q, v), conjugate)


def _local(body: RigidBody) -> Wide:
    var q = _q(body.rotation)
    return _rotate(Wide(-q[0], -q[1], -q[2], q[3]), _v(body.angular_velocity))


def _apply(a: Matrix3, v: Wide) -> Wide:
    var result = Wide(0)
    for row in range(3):
        for col in range(3):
            result[row] += Float64(a.elements[3 * col + row]) * v[col]
    return result


def _solve(a: Matrix3, v: Wide) -> Wide:
    # Independent Gaussian elimination with partial pivoting in Float64.
    var matrix = Array[Float64, 12](fill=0)
    for row in range(3):
        for col in range(3):
            matrix[4 * row + col] = Float64(a.elements[3 * col + row])
        matrix[4 * row + 3] = v[row]
    for col in range(3):
        var pivot = col
        for row in range(col + 1, 3):
            if abs(matrix[4 * row + col]) > abs(matrix[4 * pivot + col]):
                pivot = row
        for j in range(4):
            var temporary = matrix[4 * col + j]
            matrix[4 * col + j] = matrix[4 * pivot + j]
            matrix[4 * pivot + j] = temporary
        var scale = matrix[4 * col + col]
        for j in range(4):
            matrix[4 * col + j] /= scale
        for row in range(3):
            if row != col:
                var factor = matrix[4 * row + col]
                for j in range(4):
                    matrix[4 * row + j] -= factor * matrix[4 * col + j]
    return Wide(matrix[3], matrix[7], matrix[11], 0)


def _momentum(body: RigidBody) -> Wide:
    return _rotate(
        _q(body.rotation), _solve(body.inverse_inertia(), _local(body))
    )


def _energy(body: RigidBody) -> Float64:
    var local = _local(body)
    return _dot(local, _solve(body.inverse_inertia(), local)) / 2


def _norm(v: Wide) -> Float64:
    return sqrt(_dot(v, v))


def _pose() -> Quaternion:
    var q = Quaternion(0.2, -0.3, 0.4, 0.7)
    q.normalize()
    return q


def _tensor(full: Bool = False) -> Matrix3:
    var out = Matrix3()
    out.set(0.25, 0, 0, 0, 0.375, 0, 0, 0, 0.5)
    if full:
        out.set(0.3, 0.05, -0.025, 0.05, 0.4, 0.06, -0.025, 0.06, 0.5)
    return out


def _body(
    inverse: Matrix3, omega: Vector3 = Vector3(1, 2, 3), q: Quaternion = _pose()
) raises -> RigidBody:
    var body = RigidBody(
        DYNAMIC,
        Shape.box(Length(1), Length(2), Length(3)),
        Mass(1),
        Vector3(0, 0, 0),
        q,
    )
    body.set_inverse_inertia(inverse)
    body.angular_velocity = omega
    body.collides = False
    return body^


def _world(var body: RigidBody) raises -> PhysicsWorld:
    var world = PhysicsWorld()
    world.gravity = Vector3(0, 0, 0)
    _ = world.add_body(body^)
    return world^


def _reference(
    a: Matrix3, body: RigidBody, h: Float64, steps: Int
) -> Tuple[Wide, Wide]:
    # Classical RK4 on the coupled Euler/quaternion ODE, not the production
    # splitting method. Refining this reference is checked separately.
    var m = _solve(a, _local(body))
    var q = _q(body.rotation)
    for _ in range(steps):
        var w1 = _apply(a, m)
        var m1 = _cross(m, w1)
        var q1 = _multiply(q, w1) / 2
        var w2 = _apply(a, m + m1 * (h / 2))
        var m2 = _cross(m + m1 * (h / 2), w2)
        var q2 = _multiply(q + q1 * (h / 2), w2) / 2
        var w3 = _apply(a, m + m2 * (h / 2))
        var m3 = _cross(m + m2 * (h / 2), w3)
        var q3 = _multiply(q + q2 * (h / 2), w3) / 2
        var w4 = _apply(a, m + m3 * h)
        var m4 = _cross(m + m3 * h, w4)
        var q4 = _multiply(q + q3 * h, w4) / 2
        m += (m1 + 2 * m2 + 2 * m3 + m4) * (h / 6)
        q += (q1 + 2 * q2 + 2 * q3 + q4) * (h / 6)
    q /= sqrt(_dot(q, q) + q[3] * q[3])
    return q, _rotate(q, _apply(a, m))


def _rotation_error(actual: Wide, expected: Wide) -> Float64:
    var delta = actual - expected
    var plus = actual + expected
    return 2 * sqrt(
        min(
            _dot(delta, delta) + delta[3] * delta[3],
            _dot(plus, plus) + plus[3] * plus[3],
        )
    )


def test_asymmetric_refinement_and_long_time_bounds() raises:
    for full in [False, True]:
        var a = _tensor(full)
        var initial = _body(a)
        var reference = _reference(a, initial, 0.00025, 16000)
        var check = _reference(a, initial, 0.0005, 8000)
        assert_true(_rotation_error(reference[0], check[0]) < 2e-11)
        assert_true(_norm(reference[1] - check[1]) < 2e-11)
        var previous_pose = Float64(1)
        var previous_energy = Float64(1)
        for steps in [100, 200, 400]:
            var h = Float32(4) / Float32(steps)
            var world = _world(initial.copy())
            var l0 = _momentum(initial)
            var e0 = _energy(initial)
            var maximum_energy = Float64(0)
            var maximum_momentum = Float64(0)
            for _ in range(steps):
                world.step(Duration(h, SECOND))
                var energy = abs(_energy(world.bodies[0]) / e0 - 1)
                maximum_energy = max(maximum_energy, energy)
                maximum_momentum = max(
                    maximum_momentum,
                    _norm(_momentum(world.bodies[0]) - l0) / _norm(l0),
                )
            var error = _rotation_error(
                _q(world.bodies[0].rotation), reference[0]
            )
            print(
                "refine", full, steps, error, maximum_energy, maximum_momentum
            )
            assert_true(error < previous_pose * 0.3)
            assert_true(maximum_energy < previous_energy * 0.3)
            assert_true(maximum_momentum < 1e-5)
            previous_pose = error
            previous_energy = maximum_energy
        var world = _world(initial.copy())
        var e0 = _energy(initial)
        var l0 = _momentum(initial)
        var maximum_energy = Float64(0)
        var maximum_momentum = Float64(0)
        for _ in range(10000):
            world.step(Duration(0.01, SECOND))
            maximum_energy = max(
                maximum_energy, abs(_energy(world.bodies[0]) / e0 - 1)
            )
            maximum_momentum = max(
                maximum_momentum,
                _norm(_momentum(world.bodies[0]) - l0) / _norm(l0),
            )
        print("long", full, maximum_energy, maximum_momentum)
        assert_true(maximum_energy < 5e-4)
        assert_true(maximum_momentum < 5e-5)


def test_original_cuboid_reproduction() raises:
    var body = RigidBody(
        DYNAMIC,
        Shape.box(Length(1), Length(2), Length(3)),
        Mass(1),
        Vector3(0, 0, 0),
        Quaternion.identity(),
    )
    body.angular_velocity = Vector3(1, 2, 3)
    body.collides = False
    var initial = _momentum(body)
    var world = _world(body^)
    for _ in range(100):
        world.step(Duration(0.01, SECOND))
    var error = _norm(_momentum(world.bodies[0]) - initial)
    print("issue294", error)
    assert_true(error < 3e-5)


def _axis_rotation(axis: Wide, angle: Float64) -> Wide:
    var result = axis * sin(angle / 2)
    result[3] = cos(angle / 2)
    return result


def test_symmetric_top_analytic_full_tensor() raises:
    # A = (1/4) Id + (3/8) n n^T, n=(1,1,1)/sqrt(3).
    # Its entries are exact binary fractions; all products of inertia
    # are nonzero. The analytical solution uses two constant rotations.
    var a = Matrix3()
    a.set(0.375, 0.125, 0.125, 0.125, 0.375, 0.125, 0.125, 0.125, 0.375)
    var initial = _body(a)
    var n = Wide(1, 1, 1, 0) / sqrt(Float64(3))
    var m = _solve(a, _local(initial))
    var l = _momentum(initial)
    var time = Float64(2)
    var around_world = _axis_rotation(l / _norm(l), 0.25 * _norm(l) * time)
    var around_body = _axis_rotation(n, 0.375 * _dot(n, m) * time)
    var exact = _multiply(
        _multiply(around_world, _q(initial.rotation)), around_body
    )
    var rk = _reference(a, initial, 0.0005, 4000)
    assert_true(_rotation_error(rk[0], exact) < 1e-11)
    var previous = Float64(1)
    for steps in [100, 200, 400]:
        var world = _world(initial.copy())
        for _ in range(steps):
            world.step(Duration(Float32(time) / Float32(steps), SECOND))
        var error = _rotation_error(_q(world.bodies[0].rotation), exact)
        print("symmetric", steps, error)
        assert_true(error < previous * 0.3)
        assert_true(_norm(_momentum(world.bodies[0]) - l) / _norm(l) < 1e-5)
        previous = error


def test_torque_impulse_and_damping_balance() raises:
    var body = _body(_tensor(True))
    var l = _momentum(body)
    var impulse = Vector3(0.5, -1, 2)
    var offset = Vector3(1, -0.5, 0.3)
    var change = _v(cross(offset, impulse))
    body.apply_impulse(impulse, body.world_center_of_mass() + offset)
    assert_true(_norm(_momentum(body) - l - change) < 2e-6)
    var world = _world(body^)
    var torque = Vector3(-0.2, 0.7, 1.3)
    var expected = l + change
    for _ in range(100):
        world.bodies[0].torque = torque
        world.step(Duration(0.01, SECOND))
        expected += _v(torque) * Float64(Float32(0.01))
    assert_true(_norm(_momentum(world.bodies[0]) - expected) < 2e-5)
    world.bodies[0].angular_damping = 2
    for _ in range(50):
        world.bodies[0].torque = torque
        world.step(Duration(0.01, SECOND))
        expected = (expected + _v(torque) * Float64(Float32(0.01))) * Float64(
            Float32(1) / (Float32(1) + Float32(0.01) * Float32(2))
        )
    assert_true(_norm(_momentum(world.bodies[0]) - expected) < 2e-5)
    var before = _momentum(world.bodies[0])
    world.bodies[0].angular_damping = 0
    world.step(Duration(0.01, SECOND))
    assert_true(_norm(_momentum(world.bodies[0]) - before) < 2e-6)
    _equal(world.bodies[0].torque, Vector3(0, 0, 0))


def test_latest_velocity_and_inertia_are_authoritative() raises:
    var world = _world(_body(_tensor(True)))
    world.step(Duration(0.01, SECOND))
    world.bodies[0].angular_velocity = Vector3(-1, 4, 2)
    world.bodies[0].set_inverse_inertia(_tensor(False))
    var expected = _momentum(world.bodies[0])
    world.step(Duration(0.01, SECOND))
    assert_true(_norm(_momentum(world.bodies[0]) - expected) < 3e-6)


def _legacy_pose(q: Quaternion, w: Vector3, h: Float32) -> Quaternion:
    var spin = Quaternion(w.x, w.y, w.z, 0) * q
    var out = Quaternion(
        q.x + spin.x * 0.5 * h,
        q.y + spin.y * 0.5 * h,
        q.z + spin.z * 0.5 * h,
        q.w + spin.w * 0.5 * h,
    )
    out.normalize()
    return out


def test_isotropic_kinematic_and_custom_compatibility() raises:
    for kind in range(6):
        var a = Matrix3()
        if kind == 1:
            a.elements[0] = 0
        elif kind == 2:
            a.elements[0] = -1
        elif kind == 3:
            a.elements[1] = 0.1
        elif kind == 4:
            a.elements[0] = 0
            a.elements[4] = 0
            a.elements[8] = 0
        var body = _body(a)
        if kind == 5:
            body.set_kind(KINEMATIC)
        var omega = body.angular_velocity
        body.push_angular = Vector3(0.01, 0.02, -0.01)
        var expected = _legacy_pose(
            body.rotation, omega + body.push_angular, 0.02
        )
        var world = _world(body^)
        world.step(Duration(0.02, SECOND))
        _equal(world.bodies[0].angular_velocity, omega)
        assert_true(world.bodies[0].rotation == expected)
        _equal(world.bodies[0].push_angular, Vector3(0, 0, 0))
        assert_true(world.bodies[0].inverse_inertia() == a or kind == 5)


def test_high_spin_is_bounded_and_deterministic() raises:
    for scale in [Float32(100), Float32(1e20)]:
        var initial = _body(_tensor(True), Vector3(1, 2, 3) * scale)
        var first = _world(initial.copy())
        var second = _world(initial.copy())
        var l = _momentum(initial)
        var square = _dot(l, l)
        for _ in range(1000):
            first.step(Duration(0.02, SECOND))
            second.step(Duration(0.02, SECOND))
            _equal(
                first.bodies[0].angular_velocity,
                second.bodies[0].angular_velocity,
            )
            assert_true(first.bodies[0].rotation == second.bodies[0].rotation)
            var energy = _energy(first.bodies[0])
            # Gershgorin bounds for this A: eigenvalues are in [.225,.585].
            # This is a stability bound, not a small-step accuracy claim.
            assert_true(isfinite(energy))
            assert_true(energy > 0.1124 * square and energy < 0.2926 * square)
            assert_true(
                _norm(_momentum(first.bodies[0]) - l) / sqrt(square) < 3e-5
            )
        var q = first.bodies[0].rotation
        assert_true(
            abs(
                Float64(q.x) * Float64(q.x)
                + Float64(q.y) * Float64(q.y)
                + Float64(q.z) * Float64(q.z)
                + Float64(q.w) * Float64(q.w)
                - 1
            )
            < 3e-7
        )


def test_high_spin_refines_when_step_resolves_rotation() raises:
    var a = _tensor(True)
    var initial = _body(a, Vector3(10, 20, 30))
    var reference = _reference(a, initial, 0.000025, 8000)
    var check = _reference(a, initial, 0.00005, 4000)
    assert_true(_rotation_error(reference[0], check[0]) < 1e-11)
    var previous = Float64(1)
    for steps in [100, 200, 400]:
        var world = _world(initial.copy())
        for _ in range(steps):
            world.step(Duration(Float32(0.2) / Float32(steps), SECOND))
        var error = _rotation_error(_q(world.bodies[0].rotation), reference[0])
        print("high-spin-refine", steps, error)
        assert_true(error < previous * 0.3)
        previous = error


def test_scaled_tensors_and_extreme_principal_axes() raises:
    # Include subnormal inverse entries whose reciprocal exceeds Float32,
    # and finite entries close to its upper exponent range.
    for scale in [
        Float32(1e-40),
        Float32(1e-30),
        Float32(1),
        Float32(1e30),
        Float32(1e38),
    ]:
        var a = _tensor(True)
        for i in range(9):
            a.elements[i] *= scale
        var initial = _body(a)
        var world = _world(initial.copy())
        var l = _momentum(initial)
        for _ in range(100):
            world.step(Duration(0.01, SECOND))
        assert_true(_norm(_momentum(world.bodies[0]) - l) / _norm(l) < 3e-6)
    var a = Matrix3()
    a.set(1e-30, 0, 0, 0, 1, 0, 0, 0, 1e30)
    var initial = _body(a, Vector3(0, 0, 100), Quaternion.identity())
    var world = _world(initial.copy())
    for _ in range(100):
        world.step(Duration(0.01, SECOND))
    _equal(world.bodies[0].angular_velocity, Vector3(0, 0, 100))


def test_off_center_contact_keeps_total_angular_momentum() raises:
    var world = PhysicsWorld()
    world.gravity = Vector3(0, 0, 0)
    var box = RigidBody(
        DYNAMIC,
        Shape.box(Length(1), Length(0.7), Length(0.5)),
        Mass(2),
        Vector3(0, 0, 0),
        Quaternion.identity(),
    )
    box.material.friction = 0
    box.material.restitution = 0
    _ = world.add_body(box^)
    var ball = RigidBody(
        DYNAMIC,
        Shape.sphere(Length(0.4)),
        Mass(1),
        Vector3(1.42, 0.5, 0.25),
        Quaternion.identity(),
    )
    ball.linear_velocity = Vector3(-4, 0, 0)
    ball.material.friction = 0
    ball.material.restitution = 0
    _ = world.add_body(ball^)
    world.margin = 0.03
    var before = Wide(0)
    for i in range(2):
        before += _momentum(world.bodies[i]) + _cross(
            _v(world.bodies[i].world_center_of_mass()),
            _v(world.bodies[i].linear_velocity)
            * Float64(world.bodies[i].mass()),
        )
    world.step(Duration(0.01, SECOND))
    assert_true(world.contact_count > 0)
    assert_true(world.bodies[0].angular_velocity.length() > 0.1)
    var after = Wide(0)
    for i in range(2):
        after += _momentum(world.bodies[i]) + _cross(
            _v(world.bodies[i].world_center_of_mass()),
            _v(world.bodies[i].linear_velocity)
            * Float64(world.bodies[i].mass()),
        )
    assert_true(_norm(after - before) < 3e-6)


def test_ill_conditioned_physical_top_keeps_gyroscopic_motion() raises:
    # Principal inertias are (1/4098, 1, 1), a thin symmetric top.
    # Its inverse is rotated 45 degrees about z and has exact entries.
    var a = Matrix3()
    a.set(2049.5, 2048.5, 0, 2048.5, 2049.5, 0, 0, 0, 1)
    var initial = _body(a, Vector3(1, 0, 0), Quaternion.identity())
    var reference = _reference(a, initial, 0.000001, 10000)
    var world = _world(initial.copy())
    var l = _momentum(initial)
    for _ in range(100):
        world.step(Duration(0.0001, SECOND))
    var error = _rotation_error(_q(world.bodies[0].rotation), reference[0])
    var momentum_error = _norm(_momentum(world.bodies[0]) - l) / _norm(l)
    print(
        "conditioned", error, momentum_error, world.bodies[0].angular_velocity.z
    )
    assert_true(error < 2e-5)
    assert_true(momentum_error < 4e-4)
    # A prescribed-omega fallback would leave z at zero. Euler's equation
    # starts with a nonzero z acceleration for this fixture.
    assert_true(abs(world.bodies[0].angular_velocity.z) > 0.004)


def test_free_rotation_keeps_the_reconstructed_pose() raises:
    # A second Float32 normalization can move every quaternion component
    # after omega was reconstructed. Include a full, ill-conditioned
    # physical tensor and the sensitive pose found by the regression.
    for conditioned in [False, True]:
        var a = _tensor(True)
        if conditioned:
            a.set(2049.5, 2048.5, 0, 2048.5, 2049.5, 0, 0, 0, 1)
        for correction in [False, True]:
            var q = Quaternion(Float32(720) / 1000, -0.3, 0.4, 0.7)
            q.normalize()
            var initial = _body(a, Vector3(1, 2, 3), q)
            if correction:
                initial.push_angular = Vector3(0.01, 0.02, -0.01)
            var expected = initial.copy()
            assert_true(expected._rotate_free(0.001))
            var pose = expected.rotation
            if correction:
                pose = _legacy_pose(pose, initial.push_angular, 0.001)
            var world = _world(initial^)
            world.step(Duration(0.001, SECOND))
            assert_true(world.bodies[0].rotation == pose)
            _equal(world.bodies[0].angular_velocity, expected.angular_velocity)
            _equal(world.bodies[0].push_angular, Vector3(0, 0, 0))


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
