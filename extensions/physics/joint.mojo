# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Joints that hold two rigid bodies together.

A ball joint keeps one point of each body at the same place. The bodies
turn any way about that point, as a hip or a shoulder does. A hinge joint
also keeps one axis of each body on the same line. The bodies turn only
about that axis, as a knee or a door does. A hinge can have a lower and
an upper limit.

`PhysicsWorld` solves the joints with its contacts, by sequential
impulses (Erin Catto, "Iterative Dynamics with Temporal Coherence",
2005). Each velocity pass does this for one joint:

1. The point takes one impulse that stops the relative velocity of the
   two anchors. The three directions are solved together: the impulse is
   the inverse of the 3 by 3 effective mass times the velocity.
2. A hinge takes two angular impulses, one along each direction at right
   angles to its axis. They stop the relative spin in those directions.
3. A limited hinge takes one impulse about its axis for each limit. It
   lets the bodies close the gap to the limit and no more, as a contact
   with a gap does.

An angular impulse alone would move the anchors apart again. So each one
comes with the point impulse that keeps them together, and its effective
mass is the Schur complement of the point's block. A door on a fixed
frame then stops at its limit in one pass.

Split impulses then remove the position error, as they do for an
overlapping contact. They change pose and not the stored velocities.

The joint math uses `Float64` for the effective mass and its inverse.
The body state stays `Float32`.
"""

from core.ordinal import ordinal_valid, require_valid
from extensions.physics.body import BodyId, RigidBody
from extensions.physics.shape import any_perpendicular, cross
from math.cross import wide_cross, wide_dot, widen_vector
from math.finite import require_finite_group
from math.matrix3 import Matrix3
from math.vector3 import Vector3, vector3_from_float64
from std.math import atan, atan2, cos, isfinite, pi, sin, sqrt
from units.si import Angle, RADIAN


@fieldwise_init
struct JointId(Equatable, ImplicitlyCopyable, Writable):
    """The index of a joint in its `PhysicsWorld`."""

    var value: Int

    def is_valid(self) -> Bool:
        """Return True if this can name a joint.

        Returns:
            Whether the index is zero or more.
        """
        return self.value >= 0


@fieldwise_init
struct JointKind(Equatable, ImplicitlyCopyable, Writable):
    """Which degrees of freedom a joint removes."""

    var value: Int

    def is_valid(self) -> Bool:
        """Return True if this names one of the two kinds.

        Returns:
            Whether the value is 0 or 1.
        """
        return ordinal_valid(self.value, 1)


# One shared point: three degrees of freedom removed.
comptime BALL = JointKind(0)
# One shared point and one shared axis: five degrees of freedom removed.
comptime HINGE = JointKind(1)

# A hinge direction is a unit vector within this, in squared length.
comptime UNIT_TOLERANCE = 1e-3
# The centripetal pass acts in full while each body turns at most
# CARRY_FULL radians in a step, and not at all from CARRY_NONE. A faster
# turn is too coarse for it, and the plain solve is stable at any speed.
comptime CARRY_FULL = 0.25
comptime CARRY_NONE = 0.5


def _require_unit(v: Vector3, message: String) raises:
    var size = Float64(v.length_sq())
    if not abs(size - 1.0) <= UNIT_TOLERANCE:
        raise Error(message)


@fieldwise_init
struct Joint(ImplicitlyCopyable):
    """One joint between two bodies of a world.

    Make a joint with `PhysicsWorld.add_ball_joint` or
    `PhysicsWorld.add_hinge_joint`. Those take the anchor and the axis in
    the world frame and store them in each body's frame.
    """

    var kind: JointKind
    # The two bodies. A hinge angle is how far `b` has turned from `a`.
    var a: BodyId
    var b: BodyId
    # The shared point, in each body's frame, in meters.
    var anchor_a: Vector3
    var anchor_b: Vector3
    # A hinge's axis, in each body's frame. Unit vectors.
    var axis_a: Vector3
    var axis_b: Vector3
    # A direction at right angles to the axis, in each body's frame. The
    # hinge angle is zero when the two point the same way.
    var reference_a: Vector3
    var reference_b: Vector3
    # Whether a hinge stops at `lower` and `upper`.
    var limited: Bool
    var lower: Angle
    var upper: Angle
    # Whether the two bodies still make contacts with each other.
    var collide_connected: Bool
    # A joint that is not enabled does nothing. Its id stays valid.
    var enabled: Bool
    # The impulse the joint gave body `b` at the anchor in the last
    # step, in N s. Body `a` took the opposite.
    var impulse: Vector3

    def validate(self, count: Int) raises:
        """Refuse a joint that the solver cannot use.

        Args:
            count: How many bodies the world has.

        Raises:
            Error: If the kind is not valid, a body id is not valid or
                names no body, the two bodies are the same, a vector is
                not finite, a hinge direction is not a unit vector, or
                the limits of a limited hinge are not in order inside
                minus pi to pi.
        """
        require_valid(self.kind.is_valid(), "Joint kind is not valid")
        if (
            not self.a.is_valid()
            or not self.b.is_valid()
            or self.a.value >= count
            or self.b.value >= count
        ):
            raise Error("A joint's body id names no body")
        if self.a == self.b:
            raise Error("A joint needs two different bodies")
        require_finite_group(
            self.anchor_a.is_finite()
            and self.anchor_b.is_finite()
            and self.axis_a.is_finite()
            and self.axis_b.is_finite()
            and self.reference_a.is_finite()
            and self.reference_b.is_finite(),
            "A joint's anchors and directions must be finite",
        )
        if self.kind != HINGE:
            return
        var message = "A hinge's axis and reference must be unit vectors"
        _require_unit(self.axis_a, message)
        _require_unit(self.axis_b, message)
        _require_unit(self.reference_a, message)
        _require_unit(self.reference_b, message)
        if self.limited:
            require_hinge_limits(self.lower, self.upper)

    def anchor(self, bodies: List[RigidBody]) -> Vector3:
        """Return where body `a` holds the joint, in the world frame.

        Body `b` holds the same point when the joint has no error.

        Args:
            bodies: The bodies of the joint's world.

        Returns:
            The point, in meters.
        """
        ref body = bodies[self.a.value]
        return body.position + body.rotation.rotate(self.anchor_a)

    def separation(self, bodies: List[RigidBody]) -> Vector3:
        """Return how far apart the two bodies hold the joint.

        Args:
            bodies: The bodies of the joint's world.

        Returns:
            From body `a`'s anchor to body `b`'s, in meters, in the world
            frame. Zero when the joint has no position error.
        """
        ref body = bodies[self.b.value]
        return (
            body.position
            + body.rotation.rotate(self.anchor_b)
            - self.anchor(bodies)
        )

    def angle(self, bodies: List[RigidBody]) -> Angle:
        """Return how far body `b` has turned from body `a` about the axis.

        The angle is zero in the pose the joint was made in. A positive
        angle turns `b` about the axis by the right-hand rule. A ball
        joint has the same directions, so it also has an angle about its
        stored axis.

        Args:
            bodies: The bodies of the joint's world.

        Returns:
            The angle, between minus pi and pi.
        """
        ref ba = bodies[self.a.value]
        ref bb = bodies[self.b.value]
        var axis = widen_vector(ba.rotation.rotate(self.axis_a))
        var from_a = widen_vector(ba.rotation.rotate(self.reference_a))
        var from_b = widen_vector(bb.rotation.rotate(self.reference_b))
        return Angle(
            Float32(
                atan2(
                    wide_dot(axis, wide_cross(from_a, from_b)),
                    wide_dot(from_a, from_b),
                )
            ),
            RADIAN,
        )


def require_hinge_limits(lower: Angle, upper: Angle) raises:
    """Refuse hinge limits that are not in order inside minus pi to pi.

    Nothing. The call returns when the limits are usable.

    Args:
        lower: The least angle.
        upper: The greatest angle.

    Raises:
        Error: If a limit is not finite, the lower limit is above the
            upper limit, or a limit is outside minus pi to pi.
    """
    var low = lower.value
    var high = upper.value
    if not (isfinite(low) and isfinite(high)):
        raise Error("A hinge limit must be finite")
    # The Float32 nearest to pi, which 180 degrees converts to.
    var half_turn = Float32(pi)
    if low > high or low < -half_turn or high > half_turn:
        raise Error("Hinge limits must be in order inside minus pi to pi")


def _require_pair(bodies: List[RigidBody], a: BodyId, b: BodyId) raises:
    if (
        not a.is_valid()
        or not b.is_valid()
        or a.value >= len(bodies)
        or b.value >= len(bodies)
    ):
        raise Error("A joint's body id names no body")
    if a == b:
        raise Error("A joint needs two different bodies")


def ball_joint(
    bodies: List[RigidBody], a: BodyId, b: BodyId, anchor: Vector3
) raises -> Joint:
    """Return a ball joint that holds two bodies at a world point.

    The bodies keep their present relative place at the anchor. They can
    turn any way about it.

    Args:
        bodies: The bodies of the world the joint is for.
        a: The first body.
        b: The second body.
        anchor: The shared point, in the world frame, in meters.

    Returns:
        The joint, enabled, with connected collisions off.

    Raises:
        Error: If an id names no body, the two bodies are the same, or
            the anchor is not finite.
    """
    return _joint(bodies, BALL, a, b, anchor, Vector3(0, 0, 1))


def hinge_joint(
    bodies: List[RigidBody],
    a: BodyId,
    b: BodyId,
    anchor: Vector3,
    axis: Vector3,
) raises -> Joint:
    """Return a hinge joint that holds two bodies on a world axis.

    The bodies keep their present relative place at the anchor. They can
    turn only about the axis. The hinge angle is zero in the present
    pose.

    Args:
        bodies: The bodies of the world the joint is for.
        a: The first body.
        b: The second body. The hinge angle is its turn from `a`.
        anchor: A point on the axis, in the world frame, in meters.
        axis: The direction of the axis, in the world frame. Any length
            but zero.

    Returns:
        The joint, enabled, with no limits and connected collisions off.

    Raises:
        Error: If an id names no body, the two bodies are the same, the
            anchor or the axis is not finite, or the axis has no length.
    """
    return _joint(bodies, HINGE, a, b, anchor, axis)


def _joint(
    bodies: List[RigidBody],
    kind: JointKind,
    a: BodyId,
    b: BodyId,
    anchor: Vector3,
    axis: Vector3,
) raises -> Joint:
    _require_pair(bodies, a, b)
    require_finite_group(
        anchor.is_finite() and axis.is_finite(),
        "A joint's anchors and directions must be finite",
    )
    var size = axis.length()
    if not size > 0:
        raise Error("A hinge axis must have a length")
    var along = axis / size
    var side = any_perpendicular(along)
    ref ba = bodies[a.value]
    ref bb = bodies[b.value]
    var to_a = ba.rotation.conjugate()
    var to_b = bb.rotation.conjugate()
    return Joint(
        kind,
        a,
        b,
        to_a.rotate(anchor - ba.position),
        to_b.rotate(anchor - bb.position),
        to_a.rotate(along),
        to_b.rotate(along),
        to_a.rotate(side),
        to_b.rotate(side),
        False,
        Angle(0, RADIAN),
        Angle(0, RADIAN),
        False,
        True,
        Vector3(0, 0, 0),
    )


@fieldwise_init
struct _PointMass(ImplicitlyCopyable):
    """The inverse of the 3 by 3 effective mass at a joint's anchor."""

    var k0: SIMD[DType.float64, 4]
    var k1: SIMD[DType.float64, 4]
    var k2: SIMD[DType.float64, 4]

    def solve(self, v: SIMD[DType.float64, 4]) -> SIMD[DType.float64, 4]:
        """Return the inverse effective mass times a vector.

        Args:
            v: A velocity at the anchor, in m/s.

        Returns:
            The impulse that makes that velocity change, in N s.
        """
        return SIMD[DType.float64, 4](
            wide_dot(self.k0, v), wide_dot(self.k1, v), wide_dot(self.k2, v), 0
        )


@fieldwise_init
struct _Turn(ImplicitlyCopyable):
    """One angular row of a hinge.

    An angular impulse alone moves the two anchors apart. So each unit of
    it comes with the point impulse `carry`, which keeps the anchors at
    the same velocity. `mass` is the effective mass of the two together:
    the Schur complement of the point's block.
    """

    var along: Vector3
    var mass: Float32
    var carry: Vector3


@fieldwise_init
struct _JointRows(Copyable, Movable):
    """One joint's solver state for one step."""

    # The joint's index and its two bodies' indices.
    var joint: Int
    var a: Int
    var b: Int
    # From each body's center of mass to its anchor, in the world frame.
    var ra: Vector3
    var rb: Vector3
    # Each body's world inverse inertia at the start of the step.
    var inertia_a: Matrix3
    var inertia_b: Matrix3
    var point: _PointMass
    # From body a's anchor to body b's: the point's position error.
    var error: Vector3
    # The impulse given to body b at the anchor so far.
    var impulse: Vector3
    var hinge: Bool
    # Two directions at right angles to the hinge axis, and the axis.
    var p: _Turn
    var q: _Turn
    var axis: _Turn
    # Body b's hinge axis, in the world frame.
    var other_axis: Vector3
    # How far body b's axis leans from body a's, along p and q.
    var error_p: Float32
    var error_q: Float32
    # Whether the joint is a hinge with limits.
    var limited: Bool
    # The angle left before each limit. Negative past the limit.
    var lower_gap: Float32
    var upper_gap: Float32
    var lower_impulse: Float32
    var upper_impulse: Float32
    var lower_push: Float32
    var upper_push: Float32


def _times(m: Matrix3, v: SIMD[DType.float64, 4]) -> SIMD[DType.float64, 4]:
    ref e = m.elements
    return SIMD[DType.float64, 4](
        Float64(e[0]) * v[0] + Float64(e[3]) * v[1] + Float64(e[6]) * v[2],
        Float64(e[1]) * v[0] + Float64(e[4]) * v[1] + Float64(e[7]) * v[2],
        Float64(e[2]) * v[0] + Float64(e[5]) * v[1] + Float64(e[8]) * v[2],
        0,
    )


def _column(
    mass: Float64,
    inertia_a: Matrix3,
    ra: SIMD[DType.float64, 4],
    inertia_b: Matrix3,
    rb: SIMD[DType.float64, 4],
    unit: SIMD[DType.float64, 4],
) -> SIMD[DType.float64, 4]:
    # The anchor velocity a unit impulse makes: m^-1 e + (W (r x e)) x r,
    # summed over the two bodies.
    return (
        unit * mass
        + wide_cross(_times(inertia_a, wide_cross(ra, unit)), ra)
        + wide_cross(_times(inertia_b, wide_cross(rb, unit)), rb)
    )


def _point_mass(
    mass: Float64,
    inertia_a: Matrix3,
    ra: SIMD[DType.float64, 4],
    inertia_b: Matrix3,
    rb: SIMD[DType.float64, 4],
) raises -> _PointMass:
    var c0 = _column(
        mass, inertia_a, ra, inertia_b, rb, SIMD[DType.float64, 4](1, 0, 0, 0)
    )
    var c1 = _column(
        mass, inertia_a, ra, inertia_b, rb, SIMD[DType.float64, 4](0, 1, 0, 0)
    )
    var c2 = _column(
        mass, inertia_a, ra, inertia_b, rb, SIMD[DType.float64, 4](0, 0, 1, 0)
    )
    var det = wide_dot(c0, wide_cross(c1, c2))
    # The three leading minors. A custom inverse tensor can be negative.
    # Then no impulse at the point stops it.
    if not (c0[0] > 0 and c0[0] * c1[1] - c1[0] * c0[1] > 0 and det > 0):
        raise Error("A joint's bodies give no positive effective mass")
    return _PointMass(
        wide_cross(c1, c2) / det,
        wide_cross(c2, c0) / det,
        wide_cross(c0, c1) / det,
    )


def _turn(
    point: _PointMass,
    inertia_a: Matrix3,
    ra: SIMD[DType.float64, 4],
    inertia_b: Matrix3,
    rb: SIMD[DType.float64, 4],
    along: Vector3,
) -> _Turn:
    var n = widen_vector(along)
    var spin_a = _times(inertia_a, n)
    var spin_b = _times(inertia_b, n)
    # How fast a unit angular impulse parts the anchors, and the point
    # impulse that stops that.
    var part = wide_cross(spin_b, rb) + wide_cross(spin_a, ra)
    var hold = point.solve(part)
    var k = wide_dot(n, spin_a) + wide_dot(n, spin_b) - wide_dot(part, hold)
    # Zero when neither body can turn about the direction: the row then
    # gives no impulse.
    var mass = Float32(0)
    if k > 0:
        mass = Float32(1 / k)
    return _Turn(
        along, mass, vector3_from_float64(-hold[0], -hold[1], -hold[2])
    )


def _rows(
    bodies: List[RigidBody], joint: Joint, index: Int
) raises -> _JointRows:
    ref ba = bodies[joint.a.value]
    ref bb = bodies[joint.b.value]
    var ra = joint.anchor(bodies) - ba.world_center_of_mass()
    var rb = (
        bb.position
        + bb.rotation.rotate(joint.anchor_b)
        - bb.world_center_of_mass()
    )
    var inertia_a = ba.world_inverse_inertia()
    var inertia_b = bb.world_inverse_inertia()
    var wide_a = widen_vector(ra)
    var wide_b = widen_vector(rb)
    var point = _point_mass(
        Float64(ba.inverse_mass()) + Float64(bb.inverse_mass()),
        inertia_a,
        wide_a,
        inertia_b,
        wide_b,
    )
    var axis = ba.rotation.rotate(joint.axis_a)
    var p = any_perpendicular(axis)
    var q = cross(axis, p)
    var other_axis = bb.rotation.rotate(joint.axis_b)
    var lean = cross(axis, other_axis)
    var angle = joint.angle(bodies).value
    return _JointRows(
        index,
        joint.a.value,
        joint.b.value,
        ra,
        rb,
        inertia_a,
        inertia_b,
        point,
        joint.separation(bodies),
        Vector3(0, 0, 0),
        joint.kind == HINGE,
        _turn(point, inertia_a, wide_a, inertia_b, wide_b, p),
        _turn(point, inertia_a, wide_a, inertia_b, wide_b, q),
        _turn(point, inertia_a, wide_a, inertia_b, wide_b, axis),
        other_axis,
        lean.dot(p),
        lean.dot(q),
        joint.kind == HINGE and joint.limited,
        angle - joint.lower.value,
        joint.upper.value - angle,
        0,
        0,
        0,
        0,
    )


def _prepare_joints(
    bodies: List[RigidBody], joints: List[Joint]
) raises -> List[_JointRows]:
    """Return the solver state of each joint that acts in this step.

    Every joint is checked. A joint that is not enabled, or that joins
    two bodies that are not dynamic, has no state and does nothing.

    Args:
        bodies: The world's bodies, before the step changes them.
        joints: The world's joints.

    Returns:
        One state for each acting joint, in joint order.

    Raises:
        Error: If a joint is not valid, or the bodies of an acting joint
            give no positive effective mass.
    """
    var out = List[_JointRows]()
    for i in range(len(joints)):
        var joint = joints[i]
        joint.validate(len(bodies))
        if not joint.enabled:
            continue
        if not (
            bodies[joint.a.value].is_dynamic()
            or bodies[joint.b.value].is_dynamic()
        ):
            continue
        out.append(_rows(bodies, joint, i))
    return out^


def _narrow(v: SIMD[DType.float64, 4]) -> Vector3:
    return vector3_from_float64(v[0], v[1], v[2])


def _thrust(mut bodies: List[RigidBody], mut r: _JointRows, j: Vector3):
    # Give body b the impulse j at its anchor and body a its opposite.
    r.impulse = r.impulse + j
    ref ba = bodies[r.a]
    ba.linear_velocity = ba.linear_velocity - j * ba.inverse_mass()
    ba.angular_velocity = ba.angular_velocity - r.inertia_a.transform(
        cross(r.ra, j)
    )
    ref bb = bodies[r.b]
    bb.linear_velocity = bb.linear_velocity + j * bb.inverse_mass()
    bb.angular_velocity = bb.angular_velocity + r.inertia_b.transform(
        cross(r.rb, j)
    )


def _twist(
    mut bodies: List[RigidBody], mut r: _JointRows, turn: _Turn, size: Float32
):
    # Give body b an angular impulse along the row and body a its
    # opposite, with the point impulse that keeps the anchors together.
    var j = turn.along * size
    ref ba = bodies[r.a]
    ba.angular_velocity = ba.angular_velocity - r.inertia_a.transform(j)
    ref bb = bodies[r.b]
    bb.angular_velocity = bb.angular_velocity + r.inertia_b.transform(j)
    _thrust(bodies, r, turn.carry * size)


def _spin(bodies: List[RigidBody], r: _JointRows, turn: _Turn) -> Float32:
    return (bodies[r.b].angular_velocity - bodies[r.a].angular_velocity).dot(
        turn.along
    )


def _solve_joint(mut bodies: List[RigidBody], mut r: _JointRows, h: Float32):
    """Solve one joint's velocity rows once.

    The point goes first. Each angular row then keeps it closed.

    Args:
        bodies: The world's bodies. Their velocities change.
        r: The joint's state. Its impulses grow.
        h: The step, in seconds.
    """
    var slip = (
        bodies[r.b].linear_velocity
        + cross(bodies[r.b].angular_velocity, r.rb)
        - bodies[r.a].linear_velocity
        - cross(bodies[r.a].angular_velocity, r.ra)
    )
    _thrust(bodies, r, -_narrow(r.point.solve(widen_vector(slip))))
    # Copies: a row of `r` cannot be read while `r` changes.
    var p = r.p
    var q = r.q
    var axis = r.axis
    if r.hinge:
        _twist(bodies, r, p, -p.mass * _spin(bodies, r, p))
        _twist(bodies, r, q, -q.mass * _spin(bodies, r, q))
    if r.limited:
        # Each limit lets the angle close its gap and no more.
        var lower = max(
            r.lower_impulse
            + axis.mass * (min(-r.lower_gap, 0) / h - _spin(bodies, r, axis)),
            0,
        )
        _twist(bodies, r, axis, lower - r.lower_impulse)
        r.lower_impulse = lower
        var upper = max(
            r.upper_impulse
            + axis.mass * (min(-r.upper_gap, 0) / h + _spin(bodies, r, axis)),
            0,
        )
        _twist(bodies, r, axis, r.upper_impulse - upper)
        r.upper_impulse = upper


def _curve(
    arm: SIMD[DType.float64, 4], spin: SIMD[DType.float64, 4], h: Float64
) -> SIMD[DType.float64, 4]:
    # How far a direction fixed in a body leaves its straight path in one
    # step: R r - r - h w x r. The integrator's normalized quaternion
    # update turns the body about its spin by twice the arc tangent of
    # half the spin times the step.
    var size = sqrt(wide_dot(spin, spin))
    if size == 0:
        return SIMD[DType.float64, 4](0, 0, 0, 0)
    var n = spin / size
    var angle = 2 * atan(0.5 * size * h)
    var across = wide_cross(n, arm)
    return across * (sin(angle) - size * h) + (n * wide_dot(n, arm) - arm) * (
        1 - cos(angle)
    )


def _resolved(
    spin_a: SIMD[DType.float64, 4], spin_b: SIMD[DType.float64, 4], h: Float64
) -> Float64:
    # One when both bodies turn at most CARRY_FULL in the step, zero when
    # one turns CARRY_NONE or more, and a straight line between.
    var turn = sqrt(max(wide_dot(spin_a, spin_a), wide_dot(spin_b, spin_b))) * h
    return min(max((CARRY_NONE - turn) / (CARRY_NONE - CARRY_FULL), 0), 1)


def _carry_joint(mut bodies: List[RigidBody], mut r: _JointRows, h: Float32):
    """Solve one joint's velocity once more, for the end of the step.

    A velocity that keeps the anchors together now does not keep them
    together after the step: each arm turns, and its end leaves its
    straight path. This pass adds the impulse that cancels that part. It
    is the centripetal impulse of the turn.

    Args:
        bodies: The world's bodies. Their velocities change.
        r: The joint's state. Its impulse grows.
        h: The step, in seconds.
    """
    var step = Float64(h)
    var spin_a = widen_vector(bodies[r.a].angular_velocity)
    var spin_b = widen_vector(bodies[r.b].angular_velocity)
    var weight = _resolved(spin_a, spin_b, step)
    var slip = widen_vector(
        bodies[r.b].linear_velocity
        + cross(bodies[r.b].angular_velocity, r.rb)
        - bodies[r.a].linear_velocity
        - cross(bodies[r.a].angular_velocity, r.ra)
    )
    var bend = (
        _curve(widen_vector(r.rb), spin_b, step)
        - _curve(widen_vector(r.ra), spin_a, step)
    ) * (weight / step)
    _thrust(bodies, r, -_narrow(r.point.solve(slip + bend)))
    if not r.hinge:
        return
    # The same for the lean of body b's axis from body a's.
    var p = r.p
    var q = r.q
    spin_a = widen_vector(bodies[r.a].angular_velocity)
    spin_b = widen_vector(bodies[r.b].angular_velocity)
    var axis_a = widen_vector(r.axis.along)
    var axis_b = widen_vector(r.other_axis)
    var line_a = wide_cross(spin_a, axis_a) * step
    var line_b = wide_cross(spin_b, axis_b) * step
    var lean = (
        wide_cross(
            axis_a + line_a + _curve(axis_a, spin_a, step),
            axis_b + line_b + _curve(axis_b, spin_b, step),
        )
        - wide_cross(axis_a, axis_b)
        - wide_cross(line_a, axis_b)
        - wide_cross(axis_a, line_b)
    ) * (weight / step)
    _twist(
        bodies,
        r,
        p,
        -p.mass
        * (
            _spin(bodies, r, p) + Float32(wide_dot(lean, widen_vector(p.along)))
        ),
    )
    _twist(
        bodies,
        r,
        q,
        -q.mass
        * (
            _spin(bodies, r, q) + Float32(wide_dot(lean, widen_vector(q.along)))
        ),
    )


def _push_thrust(mut bodies: List[RigidBody], r: _JointRows, j: Vector3):
    ref ba = bodies[r.a]
    ba.push_velocity = ba.push_velocity - j * ba.inverse_mass()
    ba.push_angular = ba.push_angular - r.inertia_a.transform(cross(r.ra, j))
    ref bb = bodies[r.b]
    bb.push_velocity = bb.push_velocity + j * bb.inverse_mass()
    bb.push_angular = bb.push_angular + r.inertia_b.transform(cross(r.rb, j))


def _push_twist(
    mut bodies: List[RigidBody], r: _JointRows, turn: _Turn, size: Float32
):
    var j = turn.along * size
    ref ba = bodies[r.a]
    ba.push_angular = ba.push_angular - r.inertia_a.transform(j)
    ref bb = bodies[r.b]
    bb.push_angular = bb.push_angular + r.inertia_b.transform(j)
    _push_thrust(bodies, r, turn.carry * size)


def _push_spin(bodies: List[RigidBody], r: _JointRows, turn: _Turn) -> Float32:
    return (bodies[r.b].push_angular - bodies[r.a].push_angular).dot(turn.along)


def _push_joint(
    mut bodies: List[RigidBody], mut r: _JointRows, h: Float32, factor: Float32
):
    """Solve one joint's position rows once, with split impulses.

    Args:
        bodies: The world's bodies. Their push velocities change.
        r: The joint's state. Its limit pushes grow.
        h: The step, in seconds.
        factor: How much of the position error one step removes.
    """
    var slip = (
        bodies[r.b].push_velocity
        + cross(bodies[r.b].push_angular, r.rb)
        - bodies[r.a].push_velocity
        - cross(bodies[r.a].push_angular, r.ra)
    )
    _push_thrust(
        bodies,
        r,
        _narrow(r.point.solve(widen_vector(r.error * (-factor / h) - slip))),
    )
    if r.hinge:
        _push_twist(
            bodies,
            r,
            r.p,
            r.p.mass * (-factor * r.error_p / h - _push_spin(bodies, r, r.p)),
        )
        _push_twist(
            bodies,
            r,
            r.q,
            r.q.mass * (-factor * r.error_q / h - _push_spin(bodies, r, r.q)),
        )
    if r.limited and r.lower_gap < 0:
        var lower = max(
            r.lower_push
            + r.axis.mass
            * (-factor * r.lower_gap / h - _push_spin(bodies, r, r.axis)),
            0,
        )
        _push_twist(bodies, r, r.axis, lower - r.lower_push)
        r.lower_push = lower
    if r.limited and r.upper_gap < 0:
        var upper = max(
            r.upper_push
            + r.axis.mass
            * (-factor * r.upper_gap / h + _push_spin(bodies, r, r.axis)),
            0,
        )
        _push_twist(bodies, r, r.axis, r.upper_push - upper)
        r.upper_push = upper
