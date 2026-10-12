# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""An independent oracle for turning box and capsule sweeps (#635).

The oracle shares no geometry with the library. It moves a body on its
exact rigid path, a constant velocity and a constant spin by Rodrigues'
rule in Float64. A box's distance to a triangle is the least distance of a
triangle point from the box, found by golden-section search over the
triangle's barycentric coordinates; a point's distance from a box is a
clamp in the box's frame. A box's overlap depth is the least overlap over
the 13 separating axes of a box and a triangle. A capsule's distance is
the least distance of its segment's points from the triangle, by
golden-section search, with Ericson's closest-point regions.

For each case the engine's first impact time t must satisfy:

- the shapes are within the tolerance at t, so the impact is not early;
- at no sampled time up to t, nor at t, do they overlap by more than the
  tolerance, so nothing passes through;
- with no impact, they never overlap by more than the tolerance in the
  step.
"""

from extensions.physics.body import DYNAMIC, STATIC, RigidBody
from extensions.physics.ccd import SPHERE_MESH_CCD
from extensions.physics.shape import PhysicsMaterial, Shape
from extensions.physics.world import PhysicsWorld, _CCDImpact
from math.matrix3 import Matrix3
from math.quaternion import Quaternion
from math.triangle import Triangle
from math.vector3 import Vector3
from std.math import cos, sin, sqrt
from std.testing import TestSuite, assert_true
from units.si import Length, Mass

comptime _V = SIMD[DType.float64, 4]
comptime _GOLDEN = 0.6180339887498949


def _dot(a: _V, b: _V) -> Float64:
    return a[0] * b[0] + a[1] * b[1] + a[2] * b[2]


def _cross(a: _V, b: _V) -> _V:
    return _V(
        a[1] * b[2] - a[2] * b[1],
        a[2] * b[0] - a[0] * b[2],
        a[0] * b[1] - a[1] * b[0],
        0,
    )


def _length(a: _V) -> Float64:
    return sqrt(_dot(a, a))


def _multiply(a: _V, b: _V) -> _V:
    # Quaternions as (x, y, z, w).
    return _V(
        a[3] * b[0] + a[0] * b[3] + a[1] * b[2] - a[2] * b[1],
        a[3] * b[1] - a[0] * b[2] + a[1] * b[3] + a[2] * b[0],
        a[3] * b[2] + a[0] * b[1] - a[1] * b[0] + a[2] * b[3],
        a[3] * b[3] - a[0] * b[0] - a[1] * b[1] - a[2] * b[2],
    )


def _turn(q: _V, v: _V) -> _V:
    var p = _multiply(
        _multiply(q, _V(v[0], v[1], v[2], 0)), _V(-q[0], -q[1], -q[2], q[3])
    )
    return _V(p[0], p[1], p[2], 0)


@fieldwise_init
struct _Motion(ImplicitlyCopyable):
    # A rigid path: mass center c + v t, rotation exp(t w) q.
    var center: _V
    var velocity: _V
    var spin: _V
    var rotation: _V

    def at(self, t: Float64) -> Tuple[_V, _V]:
        var size = _length(self.spin)
        var q = self.rotation
        if size > 0:
            var half = size * t / 2
            var axis = self.spin * (sin(half) / size)
            q = _multiply(_V(axis[0], axis[1], axis[2], cos(half)), q)
        return (self.center + self.velocity * t, q)


@fieldwise_init
struct _Flat(ImplicitlyCopyable):
    var a: _V
    var b: _V
    var c: _V


def _golden[
    F: def(Float64) capturing -> Float64
](low: Float64, high: Float64) -> Float64:
    # The least value of a convex function on [low, high].
    var a = low
    var b = high
    var x1 = b - (b - a) * _GOLDEN
    var x2 = a + (b - a) * _GOLDEN
    var f1 = F(x1)
    var f2 = F(x2)
    for _ in range(80):
        if f1 <= f2:
            b = x2
            x2 = x1
            f2 = f1
            x1 = b - (b - a) * _GOLDEN
            f1 = F(x1)
        else:
            a = x1
            x1 = x2
            f1 = f2
            x2 = a + (b - a) * _GOLDEN
            f2 = F(x2)
    return min(min(f1, f2), min(F(low), F(high)))


def _box_distance(p: _V, center: _V, q: _V, half: _V) -> Float64:
    # Turn the point into the box's frame and clamp.
    var local = _turn(_V(-q[0], -q[1], -q[2], q[3]), p - center)
    var out = _V(0)
    for k in range(3):
        out[k] = max(abs(local[k]) - half[k], 0)
    return _length(out)


def _box_triangle_distance(center: _V, q: _V, half: _V, t: _Flat) -> Float64:
    @__parameter
    def outer(u: Float64) -> Float64:
        @__parameter
        def inner(v: Float64) -> Float64:
            return _box_distance(
                t.a + (t.b - t.a) * u + (t.c - t.a) * v, center, q, half
            )

        return _golden[inner](0, 1 - u)

    return _golden[outer](0, 1)


def _box_depth(center: _V, q: _V, half: _V, t: _Flat) -> Float64:
    # The least overlap over the 13 axes; zero when one separates.
    var axes = List[_V]()
    var box = List[_V]()
    for k in range(3):
        var e = _V(0)
        e[k] = 1
        box.append(_turn(q, e))
    var face = _cross(t.b - t.a, t.c - t.a)
    for k in range(3):
        axes.append(box[k])
    axes.append(face)
    for k in range(3):
        for edge in [t.b - t.a, t.c - t.b, t.a - t.c]:
            axes.append(_cross(box[k], edge))
    var least = Float64(1e300)
    for axis in axes:
        var size = _length(axis)
        if size < 1e-12:
            continue
        var n = axis / size
        var middle = _dot(center, n)
        var reach = Float64(0)
        for k in range(3):
            reach += half[k] * abs(_dot(box[k], n))
        var low = min(_dot(t.a, n), min(_dot(t.b, n), _dot(t.c, n)))
        var high = max(_dot(t.a, n), max(_dot(t.b, n), _dot(t.c, n)))
        var overlap = min(middle + reach - low, high - (middle - reach))
        if overlap <= 0:
            return 0
        least = min(least, overlap)
    return least


def _point_triangle(p: _V, t: _Flat) -> Float64:
    # Ericson, Real-Time Collision Detection, 5.1.5.
    var ab = t.b - t.a
    var ac = t.c - t.a
    var ap = p - t.a
    var d1 = _dot(ab, ap)
    var d2 = _dot(ac, ap)
    if d1 <= 0 and d2 <= 0:
        return _length(p - t.a)
    var bp = p - t.b
    var d3 = _dot(ab, bp)
    var d4 = _dot(ac, bp)
    if d3 >= 0 and d4 <= d3:
        return _length(p - t.b)
    var vc = d1 * d4 - d3 * d2
    if vc <= 0 and d1 >= 0 and d3 <= 0:
        return _length(p - (t.a + ab * (d1 / (d1 - d3))))
    var cp = p - t.c
    var d5 = _dot(ab, cp)
    var d6 = _dot(ac, cp)
    if d6 >= 0 and d5 <= d6:
        return _length(p - t.c)
    var vb = d5 * d2 - d1 * d6
    if vb <= 0 and d2 >= 0 and d6 <= 0:
        return _length(p - (t.a + ac * (d2 / (d2 - d6))))
    var va = d3 * d6 - d5 * d4
    if va <= 0 and d4 - d3 >= 0 and d5 - d6 >= 0:
        var w = (d4 - d3) / ((d4 - d3) + (d5 - d6))
        return _length(p - (t.b + (t.c - t.b) * w))
    var denominator = 1 / (va + vb + vc)
    return _length(
        p - (t.a + ab * (vb * denominator) + ac * (vc * denominator))
    )


def _segment_triangle(start: _V, end: _V, t: _Flat) -> Float64:
    # The segment crosses the triangle when its ends lie on opposite sides
    # of the plane at a point inside; otherwise its least point distance.
    var face = _cross(t.b - t.a, t.c - t.a)
    var low = _dot(start - t.a, face)
    var high = _dot(end - t.a, face)
    if low * high <= 0 and low != high:
        var at = start + (end - start) * (low / (low - high))
        if _point_triangle(at, t) <= 1e-12:
            return 0

    @__parameter
    def along(s: Float64) -> Float64:
        return _point_triangle(start + (end - start) * s, t)

    return _golden[along](0, 1)


@fieldwise_init
struct _Shape(ImplicitlyCopyable):
    # A box of half extents `half`, or a capsule of `radius` along body z
    # with half height `half[2]`, both centered on the mass center.
    var capsule: Bool
    var half: _V
    var radius: Float64


def _distance(
    shape: _Shape, motion: _Motion, t: Float64, flat: _Flat
) -> Float64:
    var pose = motion.at(t)
    if shape.capsule:
        var axis = _turn(pose[1], _V(0, 0, shape.half[2], 0))
        return max(
            _segment_triangle(pose[0] - axis, pose[0] + axis, flat)
            - shape.radius,
            0,
        )
    return _box_triangle_distance(pose[0], pose[1], shape.half, flat)


def _depth(shape: _Shape, motion: _Motion, t: Float64, flat: _Flat) -> Float64:
    var pose = motion.at(t)
    if shape.capsule:
        var axis = _turn(pose[1], _V(0, 0, shape.half[2], 0))
        return max(
            shape.radius
            - _segment_triangle(pose[0] - axis, pose[0] + axis, flat),
            0,
        )
    return _box_depth(pose[0], pose[1], shape.half, flat)


struct _Random:
    var state: UInt64

    def __init__(out self, seed: UInt64):
        self.state = seed

    def next(mut self, low: Float64, high: Float64) -> Float64:
        # Knuth's MMIX linear congruential generator.
        self.state = self.state * 6364136223846793005 + 1442695040888963407
        var unit = Float64(self.state >> 11) / 9007199254740992.0
        return low + (high - low) * unit


def _first_impact(
    shape: _Shape,
    motion: _Motion,
    flat: _Flat,
    h: Float64,
    turning: Bool,
) raises -> Float64:
    # The engine's first impact time, or -1 for none. The new engine
    # advances the body alone; `turning` takes the original turning-capsule
    # sweep instead.
    var world = PhysicsWorld()
    world.gravity = Vector3(0, 0, 0)
    world.collision_detection = SPHERE_MESH_CCD
    # Only the first impact counts; a plastic graze may take many more.
    world.ccd_max_impacts = 1024
    world.ccd_max_substeps = 65536
    var triangle = Triangle(
        Vector3(Float32(flat.a[0]), Float32(flat.a[1]), Float32(flat.a[2])),
        Vector3(Float32(flat.b[0]), Float32(flat.b[1]), Float32(flat.b[2])),
        Vector3(Float32(flat.c[0]), Float32(flat.c[1]), Float32(flat.c[2])),
    )
    _ = world.add_body(
        RigidBody(
            STATIC,
            Shape.mesh([triangle]),
            Mass(0),
            Vector3(0, 0, 0),
            Quaternion.identity(),
        )
    )
    var form: Shape
    if shape.capsule:
        form = Shape.capsule(
            Length(Float32(shape.radius)), Length(Float32(shape.half[2]))
        )
    else:
        form = Shape.box(
            Length(Float32(shape.half[0])),
            Length(Float32(shape.half[1])),
            Length(Float32(shape.half[2])),
        )
    var q = motion.rotation
    var body = RigidBody(
        DYNAMIC,
        form^,
        Mass(1),
        Vector3(
            Float32(motion.center[0]),
            Float32(motion.center[1]),
            Float32(motion.center[2]),
        ),
        Quaternion(Float32(q[0]), Float32(q[1]), Float32(q[2]), Float32(q[3])),
    )
    var inverse = Matrix3()
    inverse.elements[0] = 6
    inverse.elements[4] = 7
    inverse.elements[8] = 8
    body.set_inverse_inertia(inverse)
    body.linear_velocity = Vector3(
        Float32(motion.velocity[0]),
        Float32(motion.velocity[1]),
        Float32(motion.velocity[2]),
    )
    body.angular_velocity = Vector3(
        Float32(motion.spin[0]),
        Float32(motion.spin[1]),
        Float32(motion.spin[2]),
    )
    # A bounce leaves the surface, so the step ends within the limits.
    body.material = PhysicsMaterial(0, 0.5)
    _ = world.add_body(body^)
    world._validate_ccd()
    var impacts = List[_CCDImpact]()
    if turning:
        _ = world._ccd_turning(1, Float32(h), impacts)
    else:
        var separation = world._ccd_separation(Float32(h))
        _ = world._ccd_advance([1], Float32(h), separation, impacts)
    if len(impacts) == 0:
        return -1
    return impacts[0].time


def _exact(shape: _Shape, motion: _Motion) -> _Motion:
    # The body's state after Float32 storage, which the engine starts from.
    var q = motion.rotation
    var stored = _V(
        Float64(Float32(q[0])),
        Float64(Float32(q[1])),
        Float64(Float32(q[2])),
        Float64(Float32(q[3])),
    )
    stored /= sqrt(_dot(stored, stored) + stored[3] * stored[3])
    var out = motion
    out.rotation = stored
    for k in range(3):
        out.center[k] = Float64(Float32(motion.center[k]))
        out.velocity[k] = Float64(Float32(motion.velocity[k]))
        out.spin[k] = Float64(Float32(motion.spin[k]))
    _ = shape
    return out


def _check(
    shape: _Shape,
    motion: _Motion,
    flat: _Flat,
    h: Float64,
    tolerance: Float64,
    turning: Bool,
) raises -> Bool:
    # Returns whether the engine reported an impact.
    var time = _first_impact(shape, motion, flat, h, turning)
    var path = _exact(shape, motion)
    # Rounding of the stored Float32 pose along the sub-steps.
    var slack = tolerance * 1e-3
    var end = h if time < 0 else time
    for k in range(65):
        var t = end * Float64(k) / 64
        assert_true(
            _depth(shape, path, t, flat) <= tolerance + slack,
            String("deep at ", t, " before impact ", time),
        )
    if time >= 0:
        assert_true(
            _distance(shape, path, time, flat) <= tolerance + slack,
            String("early impact at ", time),
        )
        return True
    return False


def _unit(mut random: _Random) -> _V:
    var q = _V(
        random.next(-1, 1),
        random.next(-1, 1),
        random.next(-1, 1),
        random.next(-1, 1),
    )
    return q / sqrt(_dot(q, q) + q[3] * q[3])


def _case(mut random: _Random, capsule: Bool) -> Tuple[_Shape, _Motion, _Flat]:
    # A tilted triangle near the origin and a body above it, falling and
    # spinning, so that most cases hit within the step. Boxes spin faster.
    var spin = 12.0 if capsule else 30.0
    var flat = _Flat(
        _V(random.next(-3, -1), random.next(-3, -1), random.next(-0.3, 0.3), 0),
        _V(random.next(1, 3), random.next(-3, -1), random.next(-0.3, 0.3), 0),
        _V(random.next(-1, 1), random.next(1, 3), random.next(-0.3, 0.3), 0),
    )
    var shape = _Shape(
        False,
        _V(
            random.next(0.2, 0.6),
            random.next(0.2, 0.6),
            random.next(0.2, 0.6),
            0,
        ),
        0,
    )
    if capsule:
        shape = _Shape(
            True, _V(0, 0, random.next(0.1, 0.6), 0), random.next(0.05, 0.3)
        )
    var motion = _Motion(
        _V(
            random.next(-0.5, 0.5),
            random.next(-0.5, 0.5),
            random.next(1.2, 1.6),
            0,
        ),
        _V(random.next(-5, 5), random.next(-5, 5), random.next(-40, -15), 0),
        _V(
            random.next(-spin, spin),
            random.next(-spin, spin),
            random.next(-spin, spin),
            0,
        ),
        _unit(random),
    )
    return (shape, motion, flat)


def test_turning_box_impacts_match_the_oracle() raises:
    var random = _Random(635)
    var hits = 0
    for _ in range(24):
        var made = _case(random, False)
        var shape = made[0]
        var bound = sqrt(_dot(shape.half, shape.half))
        if _check(made[0], made[1], made[2], 0.06, bound / 1024, False):
            hits += 1
    assert_true(hits >= 20, String(hits))


def test_turning_capsule_impacts_match_the_oracle() raises:
    # Both the new engine and the original turning-capsule sweep.
    var random = _Random(292)
    var hits = 0
    for k in range(24):
        var made = _case(random, True)
        var turning = k % 2 == 0
        if _check(
            made[0], made[1], made[2], 0.06, made[0].radius / 1024, turning
        ):
            hits += 1
    assert_true(hits >= 20, String(hits))


def test_grazing_boxes_and_capsules_match_the_oracle() raises:
    # Parallel slides and a spin about the floor normal at a gap of half
    # and twice the tolerance take no impact and never sink. A slide that
    # starts a tolerance into the face and then closes takes one.
    var flat = _Flat(_V(-10, -10, 0, 0), _V(10, -10, 0, 0), _V(0, 10, 0, 0))
    var half = _V(0.5, 0.5, 0.5, 0)
    var box = _Shape(False, half, 0)
    var tolerance = sqrt(0.75) / 1024
    for gap in [0.5 * tolerance, 2 * tolerance]:
        var slide = _Motion(
            _V(0, 0, 0.5 + gap, 0),
            _V(8, -3, 0, 0),
            _V(0, 0, 9, 0),
            _V(0, 0, 0, 1),
        )
        assert_true(not _check(box, slide, flat, 0.05, tolerance, False))
    var sinking = _Motion(
        _V(0, 0, 0.5, 0), _V(8, 0, -1, 0), _V(0, 0, 9, 0), _V(0, 0, 0, 1)
    )
    assert_true(_check(box, sinking, flat, 0.05, tolerance, False))
    # A lying capsule rolls along the floor at the same gaps.
    var lying = _Shape(True, _V(0, 0, 0.4, 0), 0.1)
    var turn = _V(sin(0.7853981633974483), 0, 0, cos(0.7853981633974483))
    for gap in [0.05 / 1024, 0.2 / 1024]:
        var roll = _Motion(
            _V(0, 0, 0.1 + gap, 0), _V(0, 3, 0, 0), _V(0, 0, 0, 0), turn
        )
        for turning in [False, True]:
            assert_true(
                not _check(lying, roll, flat, 0.05, 0.1 / 1024, turning)
            )
    # A box corner passes a triangle corner two tolerances clear.
    var corner = _Flat(_V(0, 0, 0, 0), _V(-5, -1, 0, 0), _V(-1, -5, 0, 0))
    var clear = 2 * tolerance / sqrt(2.0)
    var passing = _Motion(
        _V(0.5 + clear, 0.5 + clear, 0.25, 0),
        _V(0, 0, -10, 0),
        _V(0, 0, 0, 0),
        _V(0, 0, 0, 1),
    )
    assert_true(not _check(box, passing, corner, 0.05, tolerance, False))


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
