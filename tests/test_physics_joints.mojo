# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Ball and hinge joints: what they hold, what they refuse, and the
solver's measured limits."""

from extensions.physics.body import (
    BodyId,
    DYNAMIC,
    KINEMATIC,
    RigidBody,
    STATIC,
)
from extensions.physics.ccd import SPHERE_MESH_CCD
from extensions.physics.joint import (
    BALL,
    CARRY_FULL,
    CARRY_NONE,
    HINGE,
    JointId,
    JointKind,
    _curve,
    _resolved,
    require_hinge_limits,
)
from extensions.physics.shape import Shape
from extensions.physics.world import PhysicsWorld
from math.matrix3 import Matrix3
from math.quaternion import Quaternion
from math.triangle import Triangle
from math.vector3 import Vector3
from std.math import cos, inf, nan, pi, sin, tan
from std.testing import (
    TestSuite,
    assert_almost_equal,
    assert_equal,
    assert_false,
    assert_raises,
    assert_true,
)
from units.si import Angle, DEGREE, Duration, Length, Mass, RADIAN, SECOND


def _fixed(at: Vector3) raises -> RigidBody:
    return RigidBody(
        STATIC, Shape.sphere(Length(0.01)), Mass(1), at, Quaternion.identity()
    )


def _ball(mass: Float32, at: Vector3) raises -> RigidBody:
    return RigidBody(
        DYNAMIC,
        Shape.sphere(Length(0.05)),
        Mass(mass),
        at,
        Quaternion.identity(),
    )


def _door() raises -> RigidBody:
    # One meter wide, hinged at the origin along z, with its center at
    # x = 0.5 m.
    return RigidBody(
        DYNAMIC,
        Shape.box(Length(0.5), Length(0.02), Length(1.0)),
        Mass(10),
        Vector3(0.5, 0, 0),
        Quaternion.identity(),
    )


def _pendulum(mut world: PhysicsWorld) raises -> JointId:
    var base = world.add_body(_fixed(Vector3(0, 0, 0)))
    var bob = world.add_body(_ball(2, Vector3(1, 0, 0)))
    return world.add_ball_joint(base, bob, Vector3(0, 0, 0))


def _hinged(mut world: PhysicsWorld) raises -> JointId:
    world.gravity = Vector3(0, 0, 0)
    var frame = world.add_body(_fixed(Vector3(0, 0, 0)))
    var door = world.add_body(_door())
    return world.add_hinge_joint(
        frame, door, Vector3(0, 0, 0), Vector3(0, 0, 2)
    )


def _energy(world: PhysicsWorld, id: Int) -> Float64:
    # Kinetic energy and height energy of one body, in joules.
    ref body = world.bodies[id]
    return Float64(body.kinetic_energy()) + Float64(
        body.mass()
    ) * 9.8 * Float64(body.world_center_of_mass().z)


def _swing_error(steps_a_second: Int) raises -> Float64:
    # The widest energy error of a pendulum released level, in two seconds.
    var world = PhysicsWorld()
    _ = _pendulum(world)
    var before = _energy(world, 1)
    var widest = Float64(0)
    for _ in range(2 * steps_a_second):
        world.step(Duration(1.0 / Float32(steps_a_second), SECOND))
        widest = max(widest, abs(_energy(world, 1) - before))
    return widest


def test_ids_and_kinds_are_typed() raises:
    assert_true(JointId(0).is_valid())
    assert_false(JointId(-1).is_valid())
    assert_true(BALL.is_valid())
    assert_true(HINGE.is_valid())
    assert_false(JointKind(2).is_valid())
    assert_false(JointKind(-1).is_valid())


def test_a_ball_joint_holds_a_pendulum() raises:
    var world = PhysicsWorld()
    var joint = _pendulum(world)
    assert_equal(world.joint_count(), 1)
    var lowest = Float32(0)
    var stretch = Float32(0)
    var apart = Float32(0)
    var aside = Float32(0)
    for _ in range(480):
        world.step(Duration(1.0 / 240.0, SECOND))
        ref bob = world.bodies[1]
        stretch = max(stretch, abs(bob.position.length() - 1))
        apart = max(
            apart, world.joints[joint.value].separation(world.bodies).length()
        )
        aside = max(aside, abs(bob.position.y))
        lowest = min(lowest, bob.position.z)
    # The bob stays one meter from the pivot, within a micrometer.
    assert_true(stretch < 1e-6)
    assert_true(apart < 1e-6)
    # It swings in the plane it was released in, and passes under the pivot.
    assert_true(aside < 1e-6)
    assert_almost_equal(lowest, -1, atol=1e-4)
    var at = world.joints[joint.value].anchor(world.bodies)
    assert_equal(at.x, 0)
    assert_equal(at.z, 0)


def test_a_hanging_body_is_held_by_its_weight() raises:
    var world = PhysicsWorld()
    var base = world.add_body(_fixed(Vector3(0, 0, 0)))
    var bob = world.add_body(_ball(2, Vector3(0, 0, -1)))
    var joint = world.add_ball_joint(base, bob, Vector3(0, 0, 0))
    var h = Float32(0.01)
    for _ in range(50):
        world.step(Duration(h, SECOND))
    ref body = world.bodies[bob.value]
    assert_almost_equal(body.position.z, -1, atol=1e-6)
    assert_almost_equal(body.linear_velocity.length(), 0, atol=1e-6)
    # The joint gives the body its weight for one step: m g h, upward.
    var held = world.joints[joint.value].impulse
    assert_almost_equal(held.z, 2 * 9.8 * h, atol=1e-5)
    assert_almost_equal(held.x, 0, atol=1e-6)
    assert_almost_equal(held.y, 0, atol=1e-6)
    # A joint that stops acting reports no impulse.
    world.joints[joint.value].enabled = False
    world.step(Duration(h, SECOND))
    assert_equal(world.joints[joint.value].impulse.z, 0)
    assert_true(world.bodies[bob.value].linear_velocity.z < 0)


def test_a_swing_keeps_its_energy_within_the_step_error() raises:
    # Gravity changes the velocity once a step, so the energy swings about
    # its true value by an amount in proportion to the step. It does not
    # drift away: half the step gives half the error.
    var coarse = _swing_error(240)
    var fine = _swing_error(480)
    assert_almost_equal(coarse / fine, 2, atol=0.1)
    # Released level, the bob has 19.6 J to trade. At 240 steps a second
    # the error stays under 1 % of that.
    assert_true(coarse < 0.01 * 19.6)


def test_a_hinge_keeps_only_the_turn_about_its_axis() raises:
    var world = PhysicsWorld()
    var hinge = _hinged(world)
    world.bodies[1].angular_velocity = Vector3(0.3, 0.2, 2.0)
    var h = Float32(1.0 / 240.0)
    world.step(Duration(h, SECOND))
    ref door = world.bodies[1]
    # The spin about the door's center becomes a turn about the hinge
    # with the same angular momentum about the hinge line:
    # I w0 = (I + m d^2) w1, with I = m (a^2 + b^2) / 3 for the half
    # widths a = 0.5 m and b = 0.02 m, and d = 0.5 m.
    var about_center = 10.0 * (0.25 + 0.0004) / 3.0
    var rate = 2.0 * about_center / (about_center + 10.0 * 0.25)
    assert_almost_equal(Float64(door.angular_velocity.z), rate, atol=1e-4)
    assert_almost_equal(door.angular_velocity.x, 0, atol=1e-5)
    assert_almost_equal(door.angular_velocity.y, 0, atol=1e-5)
    # The center moves on its circle about the hinge.
    assert_almost_equal(Float64(door.linear_velocity.y), 0.5 * rate, atol=1e-4)
    for _ in range(239):
        world.step(Duration(h, SECOND))
    # After one second the door has turned by that rate, within the
    # solver's loss.
    var turned = Float64(world.hinge_angle(hinge).value)
    assert_almost_equal(turned, rate, atol=2e-3)
    assert_true(
        world.joints[hinge.value].separation(world.bodies).length() < 1e-4
    )
    # The door's own axis still lies along the hinge.
    var up = world.bodies[1].rotation.rotate(Vector3(0, 0, 1))
    assert_almost_equal(up.z, 1, atol=1e-6)


def test_hinge_limits_stop_the_turn() raises:
    var world = PhysicsWorld()
    var hinge = _hinged(world)
    world.set_hinge_limits(hinge, Angle(-20, DEGREE), Angle(30, DEGREE))
    world.bodies[1].angular_velocity = Vector3(0, 0, 3.0)
    world.bodies[1].linear_velocity = Vector3(0, 1.5, 0)
    var top = Float32(0)
    for _ in range(120):
        world.step(Duration(1.0 / 240.0, SECOND))
        top = max(top, world.hinge_angle(hinge).value)
    var limit = Float32(30.0 * pi / 180.0)
    # The door stops at the upper limit and stays there.
    assert_true(top <= limit + 1e-5)
    assert_almost_equal(world.hinge_angle(hinge).value, limit, atol=1e-5)
    assert_almost_equal(world.bodies[1].angular_velocity.z, 0, atol=1e-5)
    # The other way, it stops at the lower limit.
    world.bodies[1].angular_velocity = Vector3(0, 0, -3.0)
    world.bodies[1].linear_velocity = world.bodies[1].velocity_at(
        world.bodies[1].world_center_of_mass()
    )
    var bottom = Float32(0)
    for _ in range(360):
        world.step(Duration(1.0 / 240.0, SECOND))
        bottom = min(bottom, world.hinge_angle(hinge).value)
    limit = Float32(-20.0 * pi / 180.0)
    assert_true(bottom >= limit - 1e-5)
    assert_almost_equal(world.hinge_angle(hinge).value, limit, atol=1e-5)
    assert_almost_equal(world.bodies[1].angular_velocity.z, 0, atol=1e-5)


def test_a_limit_lets_the_gap_close_and_no_more() raises:
    var world = PhysicsWorld()
    var hinge = _hinged(world)
    world.set_hinge_limits(hinge, Angle(-0.01, RADIAN), Angle(0.01, RADIAN))
    # In one step of 0.01 s this turn would pass the limit by 0.02 rad.
    var about_center = 10.0 * (0.25 + 0.0004) / 3.0
    var spin = Float32(3.0 * (about_center + 2.5) / about_center)
    world.bodies[1].angular_velocity = Vector3(0, 0, spin)
    world.step(Duration(0.01, SECOND))
    assert_almost_equal(world.hinge_angle(hinge).value, 0.01, atol=1e-5)
    world.step(Duration(0.01, SECOND))
    assert_almost_equal(world.hinge_angle(hinge).value, 0.01, atol=1e-5)
    assert_almost_equal(world.bodies[1].angular_velocity.z, 0, atol=1e-4)


def test_a_turn_past_a_limit_is_pushed_back() raises:
    var world = PhysicsWorld()
    var hinge = _hinged(world)
    world.joint_push_factor = 0.25
    # The door is at zero. Limits that leave zero outside put it past one.
    world.set_hinge_limits(hinge, Angle(0.1, RADIAN), Angle(0.5, RADIAN))
    world.step(Duration(0.01, SECOND))
    # One step removes the push factor's part of the error, and leaves
    # the stored velocity alone.
    assert_almost_equal(world.hinge_angle(hinge).value, 0.025, atol=1e-5)
    assert_equal(world.bodies[1].angular_velocity.z, 0)
    # The whole of a large error goes in one step, within the error of a
    # straight-line correction of a turn.
    world.joint_push_factor = 1
    world.step(Duration(0.01, SECOND))
    assert_almost_equal(world.hinge_angle(hinge).value, 0.1, atol=1e-4)
    # Past the upper limit, the push is the other way.
    world.set_hinge_limits(hinge, Angle(-0.5, RADIAN), Angle(-0.1, RADIAN))
    world.joint_push_factor = 0.25
    world.step(Duration(0.01, SECOND))
    assert_almost_equal(world.hinge_angle(hinge).value, 0.05, atol=1e-4)
    assert_equal(world.bodies[1].angular_velocity.z, 0)
    # The pose update turns by twice the arc tangent of half the angle
    # asked for. So a correction of 0.15 rad lands 0.0003 rad short, and
    # the next step removes the rest.
    world.joint_push_factor = 1
    world.step(Duration(0.01, SECOND))
    assert_almost_equal(world.hinge_angle(hinge).value, -0.1, atol=5e-4)
    world.step(Duration(0.01, SECOND))
    assert_almost_equal(world.hinge_angle(hinge).value, -0.1, atol=1e-5)


def test_position_errors_shrink_without_adding_speed() raises:
    var world = PhysicsWorld()
    world.gravity = Vector3(0, 0, 0)
    var base = world.add_body(_fixed(Vector3(0, 0, 0)))
    var bob = world.add_body(_ball(2, Vector3(0, 0, 0)))
    var joint = world.add_ball_joint(base, bob, Vector3(0, 0, 0))
    # Move the body off its anchor by hand.
    world.bodies[bob.value].position = Vector3(0.1, 0, 0)
    world.joint_push_factor = 0.25
    world.step(Duration(0.01, SECOND))
    assert_almost_equal(
        world.joints[joint.value].separation(world.bodies).x, 0.075, atol=1e-6
    )
    assert_equal(world.bodies[bob.value].linear_velocity.x, 0)
    # The default removes the whole error in one step.
    world.joint_push_factor = 1
    world.step(Duration(0.01, SECOND))
    assert_almost_equal(
        world.joints[joint.value].separation(world.bodies).x, 0, atol=1e-6
    )
    assert_equal(world.bodies[bob.value].linear_velocity.x, 0)
    # A hinge that leans off its axis is turned back the same way.
    var leaning = PhysicsWorld()
    var hinge = _hinged(leaning)
    leaning.bodies[1].rotation = Quaternion.from_axis_angle(
        Vector3(1, 0, 0), Angle(0.1, RADIAN)
    )
    for _ in range(5):
        leaning.step(Duration(0.01, SECOND))
    var up = leaning.bodies[1].rotation.rotate(Vector3(0, 0, 1))
    assert_almost_equal(up.z, 1, atol=1e-6)
    assert_equal(leaning.bodies[1].angular_velocity.length(), 0)
    assert_true(
        leaning.joints[hinge.value].separation(leaning.bodies).length() < 1e-5
    )


def test_a_wrong_push_factor_is_refused() raises:
    var world = PhysicsWorld()
    _ = _pendulum(world)
    world.joint_push_factor = -0.5
    with assert_raises(contains="push factor"):
        world.step(Duration(0.01, SECOND))
    world.joint_push_factor = nan[DType.float32]()
    with assert_raises(contains="push factor"):
        world.step(Duration(0.01, SECOND))
    assert_equal(world.bodies[1].linear_velocity.z, 0)
    # Zero leaves the position error alone.
    world.joint_push_factor = 0
    world.bodies[1].position = Vector3(1.5, 0, 0)
    world.gravity = Vector3(0, 0, 0)
    world.step(Duration(0.01, SECOND))
    assert_equal(world.bodies[1].position.x, 1.5)


def _about_origin(world: PhysicsWorld) -> Vector3:
    # The angular momentum of the first two bodies about the origin.
    var out = Vector3(0, 0, 0)
    for i in range(2):
        ref body = world.bodies[i]
        var arm = body.world_center_of_mass()
        var p = body.momentum()
        out = (
            out
            + body.angular_momentum()
            + Vector3(
                arm.y * p.z - arm.z * p.y,
                arm.z * p.x - arm.x * p.z,
                arm.x * p.y - arm.y * p.x,
            )
        )
    return out


def test_a_free_pair_keeps_its_momentum_and_energy() raises:
    var world = PhysicsWorld()
    world.gravity = Vector3(0, 0, 0)
    var a = world.add_body(_ball(2, Vector3(-0.5, 0, 0)))
    var b = world.add_body(_ball(3, Vector3(0.5, 0, 0)))
    _ = world.add_ball_joint(a, b, Vector3(0, 0, 0))
    world.bodies[a.value].linear_velocity = Vector3(0, 1, 0.5)
    world.bodies[b.value].linear_velocity = Vector3(0.2, -1, 0)
    world.bodies[b.value].angular_velocity = Vector3(0.5, 0, 1)
    # The first step makes the two velocities agree at the anchor. That
    # is a plastic impact, and it loses energy. Measure from after it.
    world.step(Duration(1.0 / 240.0, SECOND))
    var linear = world.bodies[0].momentum() + world.bodies[1].momentum()
    var angular = _about_origin(world)
    var energy = (
        world.bodies[0].kinetic_energy() + world.bodies[1].kinetic_energy()
    )
    var apart = Float32(0)
    for _ in range(480):
        world.step(Duration(1.0 / 240.0, SECOND))
        apart = max(apart, world.joints[0].separation(world.bodies).length())
    var after = world.bodies[0].momentum() + world.bodies[1].momentum()
    assert_almost_equal(after.x, linear.x, atol=1e-5)
    assert_almost_equal(after.y, linear.y, atol=1e-5)
    assert_almost_equal(after.z, linear.z, atol=1e-5)
    var turned = _about_origin(world)
    assert_almost_equal(turned.x, angular.x, atol=1e-4)
    assert_almost_equal(turned.y, angular.y, atol=1e-4)
    assert_almost_equal(turned.z, angular.z, atol=1e-4)
    assert_almost_equal(
        world.bodies[0].kinetic_energy() + world.bodies[1].kinetic_energy(),
        energy,
        rtol=1e-4,
    )
    assert_true(apart < 1e-6)


def test_a_tumbling_hinge_stays_on_its_axis() raises:
    var world = PhysicsWorld()
    world.gravity = Vector3(0, 0, 0)
    var a = world.add_body(
        RigidBody(
            DYNAMIC,
            Shape.box(Length(0.5), Length(0.1), Length(0.2)),
            Mass(2),
            Vector3(-0.5, 0, 0),
            Quaternion.identity(),
        )
    )
    var b = world.add_body(
        RigidBody(
            DYNAMIC,
            Shape.box(Length(0.5), Length(0.2), Length(0.1)),
            Mass(3),
            Vector3(0.5, 0, 0),
            Quaternion.identity(),
        )
    )
    _ = world.add_hinge_joint(a, b, Vector3(0, 0, 0), Vector3(0, 0, 1))
    world.bodies[a.value].linear_velocity = Vector3(0, 1, 0.5)
    world.bodies[a.value].angular_velocity = Vector3(1.5, 2, -1)
    world.bodies[b.value].linear_velocity = Vector3(0.2, -1, 0)
    world.bodies[b.value].angular_velocity = Vector3(1.5, 2, 1)
    world.step(Duration(1.0 / 240.0, SECOND))
    var energy = (
        world.bodies[0].kinetic_energy() + world.bodies[1].kinetic_energy()
    )
    var apart = Float32(0)
    var lean = Float32(0)
    for _ in range(480):
        world.step(Duration(1.0 / 240.0, SECOND))
        apart = max(apart, world.joints[0].separation(world.bodies).length())
        lean = max(
            lean,
            1
            - world.bodies[0]
            .rotation.rotate(Vector3(0, 0, 1))
            .dot(world.bodies[1].rotation.rotate(Vector3(0, 0, 1))),
        )
    # The two axes stay on one line and the anchors stay together.
    assert_true(lean < 1e-6)
    assert_true(apart < 1e-4)
    # These boxes precess inside a step, which the joint does not
    # predict. The pose correction of that part loses a little energy:
    # under 0.5 % in two seconds here.
    var after = (
        world.bodies[0].kinetic_energy() + world.bodies[1].kinetic_energy()
    )
    assert_true(after <= energy)
    assert_almost_equal(after, energy, rtol=5e-3)


def test_the_end_of_a_turning_arm_leaves_its_straight_path() raises:
    var arm = SIMD[DType.float64, 4](1, 0, 0, 0)
    var still = _curve(arm, SIMD[DType.float64, 4](0, 0, 0, 0), 0.01)
    assert_equal(still[0], 0)
    assert_equal(still[1], 0)
    assert_equal(still[2], 0)
    # A spin about z that the pose update turns by 0.2 rad in the step:
    # w h / 2 = tan(0.1). The arm's end goes from (1, 0) to (cos, sin).
    # Its straight path ends at (1, w h).
    var h = 0.01
    var rate = 2 * tan(0.1) / h
    var bent = _curve(arm, SIMD[DType.float64, 4](0, 0, rate, 0), h)
    assert_almost_equal(bent[0], cos(0.2) - 1, atol=1e-12)
    assert_almost_equal(bent[1], sin(0.2) - rate * h, atol=1e-12)
    assert_equal(bent[2], 0)
    # An arm along the spin does not move.
    var along = _curve(
        SIMD[DType.float64, 4](0, 0, 1, 0),
        SIMD[DType.float64, 4](0, 0, rate, 0),
        h,
    )
    assert_almost_equal(along[0], 0, atol=1e-15)
    assert_almost_equal(along[1], 0, atol=1e-15)
    assert_almost_equal(along[2], 0, atol=1e-15)


def test_the_centripetal_pass_fades_for_a_coarse_turn() raises:
    var none = SIMD[DType.float64, 4](0, 0, 0, 0)
    var h = 0.01
    # At rest and at the full limit the pass acts in full.
    assert_equal(_resolved(none, none, h), 1)
    var full = SIMD[DType.float64, 4](0, CARRY_FULL / h, 0, 0)
    assert_almost_equal(_resolved(full, none, h), 1, atol=1e-12)
    # Half way between the limits it acts by half, whichever body turns.
    var half = SIMD[DType.float64, 4](
        0, 0, 0.5 * (CARRY_FULL + CARRY_NONE) / h, 0
    )
    assert_almost_equal(_resolved(half, none, h), 0.5, atol=1e-12)
    assert_almost_equal(_resolved(none, half, h), 0.5, atol=1e-12)
    assert_almost_equal(_resolved(full, half, h), 0.5, atol=1e-12)
    # From the upper limit it does not act.
    var fast = SIMD[DType.float64, 4](2 * CARRY_NONE / h, 0, 0, 0)
    assert_equal(_resolved(fast, none, h), 0)
    assert_equal(_resolved(none, fast, h), 0)


def test_a_coarse_turn_stays_stable() raises:
    # A light arm that turns more than a radian in a step. The joint
    # cannot follow such a turn closely, but it must not add energy.
    var world = PhysicsWorld()
    world.gravity = Vector3(0, 0, 0)
    var base = world.add_body(_fixed(Vector3(0, 0, 0)))
    var bob = world.add_body(_ball(0.001, Vector3(0.01, 0, 0)))
    _ = world.add_ball_joint(base, bob, Vector3(0, 0, 0))
    world.bodies[bob.value].angular_velocity = Vector3(0, 0, 400)
    world.bodies[bob.value].linear_velocity = Vector3(0, 4, 0)
    var before = world.bodies[bob.value].kinetic_energy()
    var highest = before
    for _ in range(240):
        world.step(Duration(1.0 / 240.0, SECOND))
        highest = max(highest, world.bodies[bob.value].kinetic_energy())
    assert_true(highest <= before * 1.000001)
    assert_true(world.bodies[bob.value].position.length() < 0.02)


def test_a_chain_hangs_together() raises:
    var world = PhysicsWorld()
    var previous = world.add_body(_fixed(Vector3(0, 0, 0)))
    for link in range(5):
        var next = world.add_body(
            _ball(1, Vector3(0.2 * Float32(link + 1), 0, 0))
        )
        _ = world.add_ball_joint(
            previous, next, Vector3(0.2 * Float32(link), 0, 0)
        )
        previous = next
    var apart = Float32(0)
    var lowest = Float32(0)
    for _ in range(480):
        world.step(Duration(1.0 / 240.0, SECOND))
        for joint in world.joints:
            apart = max(apart, joint.separation(world.bodies).length())
        lowest = min(lowest, world.bodies[5].position.z)
    # Five joints share each pass, so each holds within a millimeter.
    assert_true(apart < 1e-3)
    # The chain swung down from level. Its end went most of the way to
    # the full length, one meter, under the pivot.
    assert_true(lowest < -0.8)
    assert_true(lowest > -1.001)


def test_joined_bodies_do_not_touch_by_default() raises:
    var world = PhysicsWorld()
    world.gravity = Vector3(0, 0, 0)
    var a = world.add_body(_ball(1, Vector3(0, 0, 0)))
    var b = world.add_body(_ball(1, Vector3(0.06, 0, 0)))
    var c = world.add_body(_ball(1, Vector3(5, 0, 0)))
    # The two spheres overlap by 4 cm.
    var joint = world.add_ball_joint(a, b, Vector3(0.03, 0, 0))
    _ = world.add_ball_joint(b, c, Vector3(2, 0, 0))
    world.step(Duration(0.01, SECOND))
    assert_equal(world.contact_count, 0)
    world.joints[joint.value].collide_connected = True
    world.step(Duration(0.01, SECOND))
    assert_equal(world.contact_count, 1)
    world.joints[joint.value].collide_connected = False
    world.step(Duration(0.01, SECOND))
    assert_equal(world.contact_count, 0)
    # A joint that is not enabled does not keep them apart either.
    world.joints[joint.value].enabled = False
    world.step(Duration(0.01, SECOND))
    assert_equal(world.contact_count, 1)


def test_a_body_joined_to_a_mesh_does_not_touch_it() raises:
    var world = PhysicsWorld()
    world.gravity = Vector3(0, 0, 0)
    var floor = world.add_body(
        RigidBody(
            STATIC,
            Shape.mesh(
                [
                    Triangle(
                        Vector3(-5, -5, 0), Vector3(5, -5, 0), Vector3(0, 5, 0)
                    )
                ]
            ),
            Mass(1),
            Vector3(0, 0, 0),
            Quaternion.identity(),
        )
    )
    var resting = world.add_body(_ball(1, Vector3(0, 0, 0.04)))
    var loose = world.add_body(_ball(1, Vector3(1, 0, 0.04)))
    var joint = world.add_ball_joint(floor, resting, Vector3(0, 0, 0))
    world.step(Duration(0.01, SECOND))
    # The loose sphere touches the floor. The joined one does not.
    assert_equal(world.contact_count, 1)
    assert_true(loose.is_valid())
    world.joints[joint.value].collide_connected = True
    world.step(Duration(0.01, SECOND))
    assert_equal(world.contact_count, 2)


def test_a_joint_between_fixed_bodies_is_idle() raises:
    var world = PhysicsWorld()
    var a = world.add_body(_fixed(Vector3(0, 0, 0)))
    var b = world.add_body(_fixed(Vector3(1, 0, 0)))
    var mover = RigidBody(
        KINEMATIC,
        Shape.sphere(Length(0.05)),
        Mass(1),
        Vector3(2, 0, 0),
        Quaternion.identity(),
    )
    mover.linear_velocity = Vector3(1, 0, 0)
    var c = world.add_body(mover^)
    var first = world.add_ball_joint(a, b, Vector3(0.5, 0, 0))
    var second = world.add_ball_joint(b, c, Vector3(1.5, 0, 0))
    world.step(Duration(0.1, SECOND))
    # Neither joint has a dynamic body, so neither acts.
    assert_equal(world.joints[first.value].impulse.length(), 0)
    assert_equal(world.joints[second.value].impulse.length(), 0)
    assert_almost_equal(world.bodies[c.value].position.x, 2.1, atol=1e-6)
    # A dynamic body on either side makes a joint act.
    var d = world.add_body(_ball(1, Vector3(0, 0, -1)))
    var e = world.add_body(_ball(1, Vector3(1, 0, -1)))
    var held = world.add_ball_joint(d, a, Vector3(0, 0, 0))
    var held_too = world.add_ball_joint(b, e, Vector3(1, 0, 0))
    world.step(Duration(0.1, SECOND))
    assert_almost_equal(world.joints[held.value].impulse.z, -0.98, atol=1e-5)
    assert_almost_equal(world.joints[held_too.value].impulse.z, 0.98, atol=1e-5)


def test_bodies_that_cannot_turn_take_no_twist() raises:
    var world = PhysicsWorld()
    world.gravity = Vector3(0, 0, 0)
    var a = world.add_body(_ball(1, Vector3(0, 0, 0)))
    var b = world.add_body(_ball(1, Vector3(1, 0, 0)))
    var locked = Matrix3()
    for i in range(9):
        locked.elements[i] = 0
    world.bodies[a.value].set_inverse_inertia(locked)
    world.bodies[b.value].set_inverse_inertia(locked)
    var hinge = world.add_hinge_joint(
        a, b, Vector3(0.5, 0, 0), Vector3(0, 0, 1)
    )
    world.set_hinge_limits(hinge, Angle(-1, RADIAN), Angle(1, RADIAN))
    world.bodies[b.value].angular_velocity = Vector3(1, 2, 3)
    world.bodies[b.value].linear_velocity = Vector3(1, 0, 0)
    world.step(Duration(0.01, SECOND))
    # No impulse can turn either body, so the spin stays. The point
    # still shares the linear momentum, and keeps its total.
    assert_equal(world.bodies[b.value].angular_velocity.x, 1)
    assert_equal(world.bodies[b.value].angular_velocity.y, 2)
    assert_equal(world.bodies[b.value].angular_velocity.z, 3)
    var total = (
        world.bodies[a.value].linear_velocity
        + world.bodies[b.value].linear_velocity
    )
    assert_almost_equal(total.x, 1, atol=1e-6)
    assert_almost_equal(total.y, 0, atol=1e-6)
    assert_almost_equal(total.z, 0, atol=1e-6)
    assert_true(world.bodies[a.value].linear_velocity.x > 0.4)


def test_the_angle_follows_the_right_hand_rule() raises:
    var world = PhysicsWorld()
    var hinge = _hinged(world)
    assert_equal(world.hinge_angle(hinge).value, 0)
    world.bodies[1].rotation = Quaternion.from_axis_angle(
        Vector3(0, 0, 1), Angle(30, DEGREE)
    )
    assert_almost_equal(
        world.hinge_angle(hinge).value, Float32(30.0 * pi / 180.0), atol=1e-6
    )
    world.bodies[1].rotation = Quaternion.from_axis_angle(
        Vector3(0, 0, 1), Angle(-45, DEGREE)
    )
    assert_almost_equal(
        world.hinge_angle(hinge).value, Float32(-45.0 * pi / 180.0), atol=1e-6
    )
    # A ball joint keeps an axis to measure about.
    var other = PhysicsWorld()
    var ball = _pendulum(other)
    assert_equal(other.hinge_angle(ball).value, 0)


def test_wrong_bodies_and_directions_are_refused() raises:
    var world = PhysicsWorld()
    var a = world.add_body(_fixed(Vector3(0, 0, 0)))
    var b = world.add_body(_ball(1, Vector3(1, 0, 0)))
    var at = Vector3(0, 0, 0)
    with assert_raises(contains="names no body"):
        _ = world.add_ball_joint(BodyId(-1), b, at)
    with assert_raises(contains="names no body"):
        _ = world.add_ball_joint(a, BodyId(-1), at)
    with assert_raises(contains="names no body"):
        _ = world.add_ball_joint(BodyId(2), b, at)
    with assert_raises(contains="names no body"):
        _ = world.add_ball_joint(a, BodyId(2), at)
    with assert_raises(contains="two different bodies"):
        _ = world.add_ball_joint(b, b, at)
    with assert_raises(contains="must be finite"):
        _ = world.add_ball_joint(a, b, Vector3(nan[DType.float32](), 0, 0))
    with assert_raises(contains="must be finite"):
        _ = world.add_hinge_joint(a, b, at, Vector3(0, inf[DType.float32](), 0))
    with assert_raises(contains="must have a length"):
        _ = world.add_hinge_joint(a, b, at, Vector3(0, 0, 0))
    assert_equal(world.joint_count(), 0)


def test_wrong_ids_and_limits_are_refused() raises:
    var world = PhysicsWorld()
    var ball = _pendulum(world)
    var hinge = world.add_hinge_joint(
        BodyId(0), BodyId(1), Vector3(0, 0, 0), Vector3(0, 1, 0)
    )
    with assert_raises(contains="names no joint"):
        world.check_joint(JointId(-1))
    with assert_raises(contains="names no joint"):
        world.check_joint(JointId(2))
    with assert_raises(contains="names no joint"):
        _ = world.hinge_angle(JointId(2))
    with assert_raises(contains="names no joint"):
        world.set_hinge_limits(JointId(2), Angle(0, RADIAN), Angle(1, RADIAN))
    with assert_raises(contains="Only a hinge"):
        world.set_hinge_limits(ball, Angle(0, RADIAN), Angle(1, RADIAN))
    with assert_raises(contains="must be finite"):
        world.set_hinge_limits(
            hinge, Angle(nan[DType.float32](), RADIAN), Angle(1, RADIAN)
        )
    with assert_raises(contains="must be finite"):
        world.set_hinge_limits(
            hinge, Angle(0, RADIAN), Angle(inf[DType.float32](), RADIAN)
        )
    with assert_raises(contains="in order"):
        world.set_hinge_limits(hinge, Angle(1, RADIAN), Angle(0.5, RADIAN))
    with assert_raises(contains="in order"):
        world.set_hinge_limits(hinge, Angle(-4, RADIAN), Angle(0.5, RADIAN))
    with assert_raises(contains="in order"):
        world.set_hinge_limits(hinge, Angle(0, RADIAN), Angle(4, RADIAN))
    assert_false(world.joints[hinge.value].limited)
    # Equal limits lock the hinge, and the full range is allowed.
    require_hinge_limits(Angle(0.25, RADIAN), Angle(0.25, RADIAN))
    world.set_hinge_limits(hinge, Angle(-180, DEGREE), Angle(180, DEGREE))
    assert_true(world.joints[hinge.value].limited)


def test_a_step_refuses_a_joint_edited_into_a_wrong_state() raises:
    var world = PhysicsWorld()
    var hinge = _hinged(world)
    world.set_hinge_limits(hinge, Angle(-1, RADIAN), Angle(1, RADIAN))
    var good = world.joints[hinge.value]
    world.bodies[1].add_force(Vector3(0, 5, 0), Vector3(0.5, 0, 0))
    var dt = Duration(0.01, SECOND)
    world.joints[0].kind = JointKind(7)
    with assert_raises(contains="kind is not valid"):
        world.step(dt)
    with assert_raises(contains="kind is not valid"):
        _ = world.hinge_angle(hinge)
    world.joints[0] = good
    world.joints[0].a = BodyId(-1)
    with assert_raises(contains="names no body"):
        world.step(dt)
    world.joints[0] = good
    world.joints[0].b = BodyId(-1)
    with assert_raises(contains="names no body"):
        world.step(dt)
    world.joints[0] = good
    world.joints[0].a = BodyId(2)
    with assert_raises(contains="names no body"):
        world.step(dt)
    world.joints[0] = good
    world.joints[0].b = BodyId(2)
    with assert_raises(contains="names no body"):
        world.step(dt)
    world.joints[0] = good
    world.joints[0].b = BodyId(0)
    with assert_raises(contains="two different bodies"):
        world.step(dt)
    var bad = Vector3(nan[DType.float32](), 0, 0)
    world.joints[0] = good
    world.joints[0].anchor_a = bad
    with assert_raises(contains="must be finite"):
        world.step(dt)
    world.joints[0] = good
    world.joints[0].anchor_b = bad
    with assert_raises(contains="must be finite"):
        world.step(dt)
    world.joints[0] = good
    world.joints[0].axis_a = bad
    with assert_raises(contains="must be finite"):
        world.step(dt)
    world.joints[0] = good
    world.joints[0].axis_b = bad
    with assert_raises(contains="must be finite"):
        world.step(dt)
    world.joints[0] = good
    world.joints[0].reference_a = bad
    with assert_raises(contains="must be finite"):
        world.step(dt)
    world.joints[0] = good
    world.joints[0].reference_b = bad
    with assert_raises(contains="must be finite"):
        world.step(dt)
    world.joints[0] = good
    world.joints[0].axis_b = Vector3(0, 0, 2)
    with assert_raises(contains="unit vectors"):
        world.step(dt)
    world.joints[0] = good
    world.joints[0].lower = Angle(2, RADIAN)
    with assert_raises(contains="in order"):
        world.step(dt)
    # A ball joint needs no unit directions and has no limits to check.
    world.joints[0].kind = BALL
    world.step(dt)
    # No refused step moved the door or used its force: the one step that
    # ran is the first to turn it.
    world.joints[0] = good
    var before = world.bodies[1].angular_velocity.z
    assert_true(before > 0)
    world.joints[0].limited = False
    world.joints[0].lower = Angle(2, RADIAN)
    world.step(dt)
    assert_almost_equal(world.bodies[1].angular_velocity.z, before, atol=1e-6)


def _refused_tensor(x: Float32, y: Float32, z: Float32, along: Vector3) raises:
    # Two unit spheres joined one meter along a direction from the first.
    # The first has the given diagonal inverse inertia.
    var world = PhysicsWorld()
    world.gravity = Vector3(0, 0, 0)
    var a = world.add_body(_ball(1, Vector3(0, 0, 0)))
    var b = world.add_body(_ball(1, along))
    var custom = Matrix3()
    custom.elements[0] = x
    custom.elements[4] = y
    custom.elements[8] = z
    world.bodies[a.value].set_inverse_inertia(custom)
    _ = world.add_ball_joint(a, b, along)
    world.bodies[b.value].linear_velocity = Vector3(1, 1, 1)
    with assert_raises(contains="no positive effective mass"):
        world.step(Duration(0.01, SECOND))
    # The refused step moved nothing.
    assert_equal(world.bodies[b.value].position.x, along.x)
    assert_equal(world.bodies[b.value].position.y, along.y)


def test_a_tensor_with_no_positive_mass_is_refused() raises:
    # With the anchor one meter along z, the effective mass has the
    # diagonal 2 + y, 2 + x, 2. With it along x, it has 2, 2 + z, 2 + y.
    # Each case makes one leading minor fail and keeps the ones before it.
    _refused_tensor(0, -100, 0, Vector3(0, 0, 1))
    _refused_tensor(-100, 0, 0, Vector3(0, 0, 1))
    _refused_tensor(0, -100, 0, Vector3(1, 0, 0))


def test_continuous_collision_refuses_joints() raises:
    var world = PhysicsWorld()
    var joint = _pendulum(world)
    world.collision_detection = SPHERE_MESH_CCD
    with assert_raises(contains="does not support joints"):
        world.step(Duration(0.01, SECOND))
    # The refused step changed nothing.
    assert_equal(world.bodies[1].position.x, 1)
    assert_equal(world.bodies[1].linear_velocity.z, 0)
    # A joint that is not enabled does not act, so the mode accepts it.
    world.joints[joint.value].enabled = False
    world.bodies[0].collides = False
    world.step(Duration(0.01, SECOND))
    assert_true(world.bodies[1].linear_velocity.z < 0)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
