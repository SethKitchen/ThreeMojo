# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""A wheeled vehicle on ray-cast suspension, driven as CARLA drives one.

The chassis is one dynamic body: a box from the wheel centers to the top
of the vehicle's bounding box. `update` runs before each world step. It
applies CARLA's vehicle control, as CARLA's wheeled vehicle in its
simulator plugin, `Carla/Vehicle/CarlaWheeledVehicle.cpp`, hands it on.
The vehicle model is this port's own. In this order:

1. The Ackermann controller, when it is active, turns its target into a
   `VehicleControl` (`AckermannController.run_loop`).
2. The control goes to the gearbox as CARLA's default movement
   component, `Carla/Vehicle/MovementComponents/
   DefaultMovementComponent.cpp`, sends it: a change of `reverse` selects gear -1 or 1
   at once and turns the automatic gearbox off in reverse; otherwise
   `manual_gear_shift` selects `gear` at once and turns it off.
3. Each wheel casts a ray down its suspension axis, from the top of its
   travel to the bottom of the tire. The spring pushes with the spring
   rate times the compression from full drop, plus the preload, plus a
   damper at `suspension_damping_ratio` of the critical damping of the
   wheel's share of the mass. The chassis feels it along the ground's
   normal, as the suspension arms carry the part across the spring. An anti-roll bar pushes each wheel of an
   axle by `rollbar_scaling` times the spring rate times the difference
   of the two compressions.
4. The engine is locked to the driven wheels through the gear and the
   final ratio while a gear is engaged, and never turns slower than idle.
   Its torque is the throttle times the torque curve, limited to
   `max_torque`, and cut at `max_rpm`. With the throttle released the engine
   brakes. Out of gear, it spins up against `rev_up_moi` or slows at
   `rev_down_rate`. The automatic gearbox shifts up at `change_up_rpm`
   and down at `change_down_rpm`, and the clutch is out for
   `gear_change_time`.
5. Each tire in contact makes a force along the ground and across it.
   The drive torque over the radius pushes; the brake holds the wheel
   like static friction up to its torque over the radius; the side force
   stops the sliding across the wheel, up to the cornering stiffness
   times the slip angle. All of it stays inside the friction circle of
   the tire's grip times its load. The tires are solved together, with
   projected Gauss-Seidel on the relative contact velocity the step will
   have. Both bodies respond to each impulse. Wheels on the same support
   share its predicted motion, so they do not each stop the same slide. A wheel whose brake holds
   more than its grip locks and slides, unless `abs_enabled`. A driven
   wheel whose torque passes its grip spins, unless
   `traction_control_enabled`.
6. Air drag and downforce act at the center of mass. They use world
   velocity in still air, separate from the support-relative tire speed.

A tire's grip is `friction_force_multiplier` times the ground's
friction. Its load is the spring force, blended with an equal share of
the weight by `wheel_load_ratio`.

The rollover behavior is CARLA's, from `CarlaWheeledVehicle.cpp`:
past 130 degrees of roll, four steps take 35 percent of the angular
velocity each, and five seconds later the vehicle reports `ROLLOVER`.

Differences from the earlier port:
    The af6c253 tire model used chassis world velocity and chassis-only
    effective mass. A braked car and its support moving together at 10 m/s
    produced -20000 N without relative motion. Tire motion now includes
    both bodies, including prescribed support rotation and pending forces.
    Moving-support scenario replay therefore changes. This is the port's
    own model, not a claim of identical CARLA trajectories.
"""

from extensions.carla.physics.body import (
    BodyId,
    DYNAMIC,
    RigidBody,
    rotation_matrix,
)
from extensions.carla.physics.quantities import KILOMETER_PER_HOUR
from extensions.carla.physics.shape import Shape, cross, unit_or
from extensions.carla.physics.vehicle_control import (
    AckermannController,
    Gear,
    NO_FAILURE,
    ROLLOVER,
    VehicleAckermannControl,
    VehicleControl,
    VehicleFailureState,
    VehicleTelemetryData,
    WheelTelemetryData,
)
from extensions.carla.physics.vehicle_physics import (
    ALL_WHEEL_DRIVE,
    FRONT_AXLE,
    FRONT_WHEEL_DRIVE,
    REAR_AXLE,
    REAR_WHEEL_DRIVE,
    VehiclePhysicsControl,
    evaluate_curve,
)
from extensions.carla.physics.world import PhysicsWorld
from extensions.carla.transform import CarlaTransform
from math.matrix3 import Matrix3
from math.quaternion import Quaternion
from math.vector3 import Vector3
from std.math import atan2, inf, sqrt
from units.si import (
    Angle,
    AngularVelocity,
    DEGREE,
    Duration,
    KILOGRAM,
    Length,
    METER,
    Mass,
    RADIAN,
    Velocity,
)

# The density of air at sea level and 15 degrees Celsius, in kg/m^3.
comptime AIR_DENSITY = Float32(1.225)
# How many passes the tire solver makes.
comptime _TIRE_ITERATIONS = 8
# CARLA's `RolloverBehaviorForce` and `RolloverFlagTime`.
comptime ROLLOVER_FORCE = Float32(0.35)
comptime ROLLOVER_FLAG_TIME = Float32(5.0)


@fieldwise_init
struct WheelState(ImplicitlyCopyable):
    """What one wheel is doing."""

    var in_contact: Bool
    # How far the spring is compressed from full drop, in meters.
    var compression: Float32
    var last_compression: Float32
    # The spring, damper and anti-roll force, in newtons.
    var suspension_force: Float32
    var contact_point: Vector3
    var contact_normal: Vector3
    var ground: BodyId
    # The ground's friction.
    var ground_friction: Float32
    # The wheel's spin, in rad/s, and how much of it is wheelspin.
    var omega: Float32
    var spin: Float32
    # The steer angle, in radians.
    var steer: Float32
    # In N m.
    var drive_torque: Float32
    var brake_torque: Float32
    # The slip angle, in radians, and the slip ratio.
    var lat_slip: Float32
    var long_slip: Float32
    # The mass the spring holds at rest, in kilograms.
    var sprung_mass: Float32
    var locked: Bool
    var slipping: Bool
    var skidding: Bool
    # The wheel's center and its velocity, in the world.
    var location: Vector3
    var velocity: Vector3

    @staticmethod
    def at_rest() -> WheelState:
        """Return a wheel off the ground and still.

        Returns:
            The state.
        """
        return WheelState(
            False,
            0,
            0,
            0,
            Vector3(0, 0, 0),
            Vector3(0, 0, 1),
            BodyId(-1),
            0,
            0,
            0,
            0,
            0,
            0,
            0,
            0,
            0,
            False,
            False,
            False,
            Vector3(0, 0, 0),
            Vector3(0, 0, 0),
        )


@fieldwise_init
struct _TireBody(ImplicitlyCopyable):
    # One shared prediction per body, before the world's contact solve.
    var id: BodyId
    var center: Vector3
    var inverse_mass: Float32
    var inverse_inertia: Matrix3
    var v: Vector3
    var w: Vector3
    var responds: Bool

    def velocity_at(self, r: Vector3) -> Vector3:
        return self.v + cross(self.w, r)

    def apply(mut self, impulse: Vector3, r: Vector3):
        self.v = self.v + impulse * self.inverse_mass
        self.w = self.w + self.inverse_inertia.transform(cross(r, impulse))

    def inverse_mass_along(self, r: Vector3, d: Vector3) -> Float32:
        if not self.responds:
            return 0
        var c = cross(r, d)
        return self.inverse_mass + c.dot(self.inverse_inertia.transform(c))


@fieldwise_init
struct _Tire(ImplicitlyCopyable):
    var wheel: Int
    var point: Vector3
    var r: Vector3
    var support: Int
    var support_r: Vector3
    var forward: Vector3
    var lateral: Vector3
    var mass_forward: Float32
    var mass_lateral: Float32
    var drive: Float32
    var brake: Float32
    var limit: Float32
    var lateral_cap: Float32
    var along: Float32
    var across: Float32
    var drive_saturated: Bool


struct WheeledVehicle(Copyable, Movable):
    """A CARLA vehicle: a chassis body, its wheels, engine and gearbox."""

    var body: BodyId
    var physics: VehiclePhysicsControl
    # The control applied by the user, and the one last flushed.
    var control: VehicleControl
    var applied: VehicleControl
    var ackermann: AckermannController
    var ackermann_active: Bool
    var last_ackermann: VehicleAckermannControl
    var wheels: List[WheelState]
    # The engine's speed, in rad/s.
    var engine_omega: Float32
    var gear: Int
    var target_gear: Int
    # The time left in a gear change, in seconds.
    var shift_timer: Float32
    var automatic: Bool
    var failure_state: VehicleFailureState
    var rollover_tracker: Int
    # The time left before the rollover flag, or less than zero.
    var rollover_timer: Float32
    # The chassis box, in the vehicle's frame.
    var box_center: Vector3
    var box_extent: Vector3

    def __init__(
        out self,
        mut world: PhysicsWorld,
        transform: CarlaTransform,
        bounding_box_center: Vector3,
        bounding_box_extent: Vector3,
        var physics: VehiclePhysicsControl,
    ) raises:
        """Spawn a vehicle: add its chassis body to the world.

        Args:
            world: The world the chassis joins.
            transform: Where the vehicle's origin is, and how it is turned.
            bounding_box_center: The middle of the vehicle's bounding box,
                in its frame, in meters.
            bounding_box_extent: Half the bounding box's size.
            physics: The setup.

        Raises:
            Error: If the setup is refused, or the box ends below the
                lowest wheel center.
        """
        physics.check()
        var low = bounding_box_center.z - bounding_box_extent.z
        # `physics.check` refuses a vehicle with no wheel.
        for w in physics.wheels:  # pragma: no branch
            low = max(low, w.offset.z)
        var high = bounding_box_center.z + bounding_box_extent.z
        if not (high > low):
            raise Error("The bounding box must reach above the wheel centers")
        self.box_center = Vector3(
            bounding_box_center.x, bounding_box_center.y, (low + high) * 0.5
        )
        self.box_extent = Vector3(
            bounding_box_extent.x, bounding_box_extent.y, (high - low) * 0.5
        )
        var body = RigidBody(
            DYNAMIC,
            Shape.box(
                Length(self.box_extent.x, METER),
                Length(self.box_extent.y, METER),
                Length(self.box_extent.z, METER),
            ),
            physics.mass,
            transform.location,
            Quaternion.from_matrix(transform.matrix()),
        )
        body.set_shape_pose(self.box_center, Quaternion.identity())
        # The drag is modeled on its own below.
        body.linear_damping = 0
        self.body = world.add_body(body^)
        self.physics = physics^
        self.control = VehicleControl()
        self.applied = VehicleControl()
        self.ackermann = AckermannController()
        self.ackermann_active = False
        self.last_ackermann = VehicleAckermannControl()
        self.wheels = List[WheelState]()
        for _ in range(len(self.physics.wheels)):  # pragma: no branch
            self.wheels.append(WheelState.at_rest())
        self.engine_omega = 0
        self.gear = 0
        self.target_gear = 0
        self.shift_timer = 0
        self.automatic = True
        self.failure_state = NO_FAILURE
        self.rollover_tracker = 0
        self.rollover_timer = -1
        self._apply_mass(world)

    def _apply_mass(mut self, mut world: PhysicsWorld) raises:
        ref body = world.bodies[self.body.value]
        body.set_mass(self.physics.mass)
        var scale = self.physics.inertia_tensor_scale
        var props = body.shape.mass_properties(self.physics.mass.value)
        var inertia = props.inertia
        inertia.elements[0] *= scale.x
        inertia.elements[4] *= scale.y
        inertia.elements[8] *= scale.z
        body.set_inertia(inertia)
        body.set_center_of_mass(self.box_center + self.physics.center_of_mass)
        self.engine_omega = self.physics.idle_rpm.value
        self._sprung_masses()
        self.ackermann.update_vehicle_physics(self.maximum_steer_angle())

    def _sprung_masses(mut self):
        """Share the weight among the wheels: the least-squares shares that
        balance the mass about the center of mass."""
        var n = len(self.wheels)
        var mass = self.physics.mass.value
        var com = self.box_center + self.physics.center_of_mass
        var sums = Matrix3()
        var sx = Float32(0)
        var sy = Float32(0)
        var sxx = Float32(0)
        var sxy = Float32(0)
        var syy = Float32(0)
        # A vehicle has one wheel at least.
        for w in self.physics.wheels:  # pragma: no branch
            var x = w.offset.x - com.x
            var y = w.offset.y - com.y
            sx += x
            sy += y
            sxx += x * x
            sxy += x * y
            syy += y * y
        sums.set(Float32(n), sx, sy, sx, sxx, sxy, sy, sxy, syy)
        sums.invert()
        var share = mass / Float32(n)
        var rhs = Vector3(0, -share * sx, -share * sy)
        var lam = sums.transform(rhs)
        for i in range(n):  # pragma: no branch
            ref w = self.physics.wheels[i]
            var x = w.offset.x - com.x
            var y = w.offset.y - com.y
            self.wheels[i].sprung_mass = max(
                share + lam.x + lam.y * x + lam.z * y, 0
            )

    # --- controls ------------------------------------------------------

    def apply_control(mut self, control: VehicleControl) raises:
        """Take a control, `ApplyVehicleControl`. It turns the Ackermann
        controller off.

        Args:
            control: The control.

        Raises:
            Error: If the control is refused.
        """
        control.check()
        if self.ackermann_active:
            self.ackermann.reset()
        self.ackermann_active = False
        self.control = control

    def apply_ackermann_control(mut self, target: VehicleAckermannControl):
        """Hand the pedals to the Ackermann controller,
        `ApplyVehicleAckermannControl`.

        Args:
            target: The target steer, speed and acceleration.
        """
        self.ackermann_active = True
        self.last_ackermann = target
        self.ackermann.set_target_point(target)

    def apply_physics_control(
        mut self, mut world: PhysicsWorld, var physics: VehiclePhysicsControl
    ) raises:
        """Replace the setup, `ApplyVehiclePhysicsControl`.

        Args:
            world: The world that holds the chassis.
            physics: The new setup. It must have as many wheels as the old.

        Raises:
            Error: If the setup is refused, or its wheel count differs.
        """
        physics.check()
        if len(physics.wheels) != len(self.wheels):
            raise Error("A new setup must keep the number of wheels")
        self.physics = physics^
        self._apply_mass(world)

    def maximum_steer_angle(self) -> Angle:
        """Return the first wheel's steer limit, `GetMaximumSteerAngle`.

        Returns:
            The angle.
        """
        return self.physics.wheels[0].max_steer_angle

    def forward_speed(self, world: PhysicsWorld) -> Velocity:
        """Return the speed along the vehicle's forward axis.

        Args:
            world: The world that holds the chassis.

        Returns:
            The speed. Minus is backward.
        """
        ref body = world.bodies[self.body.value]
        return Velocity(
            body.linear_velocity.dot(body.rotation.rotate(Vector3(1, 0, 0)))
        )

    def telemetry(self, world: PhysicsWorld) -> VehicleTelemetryData:
        """Return what the vehicle reports, `GetVehicleTelemetryData`.

        Args:
            world: The world that holds the chassis.

        Returns:
            The speed, the last control applied, the engine speed, the
            gear and each wheel's slip and spin.
        """
        var wheels = List[WheelTelemetryData]()
        # A vehicle has one wheel at least.
        for w in self.wheels:  # pragma: no branch
            wheels.append(
                WheelTelemetryData(
                    Angle(w.lat_slip, RADIAN),
                    w.long_slip,
                    AngularVelocity(w.omega),
                )
            )
        return VehicleTelemetryData(
            self.forward_speed(world),
            self.applied.steer,
            self.applied.throttle,
            self.applied.brake,
            AngularVelocity(self.engine_omega),
            Gear(self.gear),
            wheels^,
        )

    # --- the step ------------------------------------------------------

    def update(mut self, mut world: PhysicsWorld, dt: Duration) raises:
        """Drive the vehicle for one step: call this before `world.step`.

        Args:
            world: The world that holds the chassis.
            dt: The step. It must be more than zero.

        Raises:
            Error: If the step is not more than zero, or a ray cast fails.
        """
        var h = dt.value
        if not (h > 0):
            raise Error("A vehicle step must be more than zero")
        self._flush_control(world, dt)
        self._steer(world)
        self._suspension(world, h)
        _ = self._couple()
        self._transmission(h)
        self._engine(h)
        self._tires(world, h)
        self._aerodynamics(world)
        self._rollover(world, h)

    def _flush_control(mut self, world: PhysicsWorld, dt: Duration):
        if self.ackermann_active:
            self.ackermann.update_vehicle_state(
                self.forward_speed(world), self.applied.steer, dt
            )
            self.ackermann.run_loop(self.control)
        if self.applied.reverse != self.control.reverse:
            self.automatic = not self.control.reverse
            self._set_gear(-1 if self.control.reverse else 1, True)
        else:
            self.automatic = not self.control.manual_gear_shift
            if self.control.manual_gear_shift:
                self._set_gear(self.control.gear.value, True)
        self.control.gear = Gear(self.gear)
        self.control.reverse = self.gear < 0
        self.applied = self.control

    def _set_gear(mut self, gear: Int, immediate: Bool):
        var g = max(
            -len(self.physics.reverse_gear_ratios),
            min(gear, len(self.physics.forward_gear_ratios)),
        )
        self.target_gear = g
        if immediate or self.physics.gear_change_time.value <= 0:
            self.gear = g
            self.shift_timer = 0
        else:
            self.shift_timer = self.physics.gear_change_time.value

    def _ratio(self) -> Float32:
        if self.gear > 0:
            return (
                self.physics.forward_gear_ratios[self.gear - 1]
                * self.physics.final_ratio
            )
        if self.gear < 0:
            return (
                -self.physics.reverse_gear_ratios[-self.gear - 1]
                * self.physics.final_ratio
            )
        return 0

    def _steer(mut self, world: PhysicsWorld):
        var kmh = abs(self.forward_speed(world).to(KILOMETER_PER_HOUR))
        var factor = evaluate_curve(self.physics.steering_curve, kmh)
        # A vehicle has one wheel at least.
        for i in range(len(self.wheels)):  # pragma: no branch
            ref setup = self.physics.wheels[i]
            if setup.affected_by_steering:
                self.wheels[i].steer = (
                    self.applied.steer * factor * setup.max_steer_angle.value
                )
            else:
                self.wheels[i].steer = 0

    def _suspension(mut self, mut world: PhysicsWorld, h: Float32) raises:
        var body = world.bodies[self.body.value].copy()
        for i in range(len(self.wheels)):  # pragma: no branch
            ref setup = self.physics.wheels[i]
            ref state = self.wheels[i]
            var down = unit_or(
                body.rotation.rotate(setup.suspension_axis), Vector3(0, 0, -1)
            )
            var raise_ = setup.suspension_max_raise.value
            var drop = setup.suspension_max_drop.value
            var radius = setup.wheel_radius.value
            var mount = body.position + body.rotation.rotate(setup.offset)
            var start = mount - down * raise_
            var hit = world.raycast(
                start,
                down,
                Length(raise_ + drop + radius, METER),
                self.body,
            )
            state.last_compression = state.compression
            if not Bool(hit):
                state.in_contact = False
                state.compression = 0
                state.last_compression = 0
                state.suspension_force = 0
                state.location = mount + down * drop
                state.velocity = body.velocity_at(state.location)
                continue
            var found = hit.value()
            state.in_contact = True
            state.compression = max(
                raise_ + drop - (found.distance - radius), 0
            )
            state.contact_point = found.point
            state.contact_normal = found.normal
            state.ground = found.body
            state.ground_friction = found.material.friction
            state.location = start + down * (found.distance - radius)
            state.velocity = body.velocity_at(state.location)
            var k = setup.spring_rate.value
            var c = (
                setup.suspension_damping_ratio * 2 * sqrt(k * state.sprung_mass)
            )
            state.suspension_force = (
                k * state.compression
                + setup.spring_preload.value
                + c * (state.compression - state.last_compression) / h
            )
        # The anti-roll bars join wheels 0 and 1, 2 and 3, and so on.
        for i in range(0, len(self.wheels) - 1, 2):
            var a = self.wheels[i]
            var b = self.wheels[i + 1]
            if not (a.in_contact and b.in_contact):
                continue
            var bar = (
                self.physics.wheels[i].rollbar_scaling
                * self.physics.wheels[i].spring_rate.value
                * (a.compression - b.compression)
            )
            self.wheels[i].suspension_force += bar
            self.wheels[i + 1].suspension_force -= bar
        for i in range(len(self.wheels)):  # pragma: no branch
            ref state = self.wheels[i]
            if not state.in_contact:
                continue
            state.suspension_force = max(state.suspension_force, 0)
            var at = state.contact_point + body.rotation.rotate(
                self.physics.wheels[i].suspension_force_offset
            )
            # The ground pushes along its normal. The suspension arms carry
            # whatever of that is not along the spring, so the chassis
            # feels the whole of it, and a pitched chassis is not pushed
            # along the road by its own springs.
            var force = state.contact_normal * state.suspension_force
            world.bodies[self.body.value].add_force(force, at)
            _push_ground(world, state.ground, -force, at)

    def _transmission(mut self, h: Float32):
        if self.shift_timer > 0:
            self.shift_timer -= h
            if self.shift_timer <= 0:
                self.shift_timer = 0
                self.gear = self.target_gear
            return
        if not self.automatic:
            return
        if self.gear == 0:
            if self.applied.throttle > 0:
                self._set_gear(1, True)
            return
        if self.gear < 0:
            return
        if (
            self.engine_omega >= self.physics.change_up_rpm.value
            and self.gear < len(self.physics.forward_gear_ratios)
        ):
            self._set_gear(self.gear + 1, False)
        elif (
            self.engine_omega <= self.physics.change_down_rpm.value
            and self.gear > 1
        ):
            self._set_gear(self.gear - 1, False)

    def _shares(self) -> List[Float32]:
        """Return the fraction of the engine's torque each wheel gets."""
        var n = len(self.wheels)
        var out = List[Float32](length=n, fill=0)
        var kind = self.physics.differential_type
        var split = self.physics.front_rear_split
        var front = 0
        var rear = 0
        # A vehicle has one wheel at least.
        for w in self.physics.wheels:  # pragma: no branch
            if w.axle_type == FRONT_AXLE:
                front += 1
            elif w.axle_type == REAR_AXLE:
                rear += 1
        for i in range(n):  # pragma: no branch
            ref w = self.physics.wheels[i]
            if kind == ALL_WHEEL_DRIVE:
                if w.axle_type == FRONT_AXLE:
                    out[i] = (1 - split) / Float32(front)
                elif w.axle_type == REAR_AXLE:
                    out[i] = split / Float32(rear)
            elif kind == FRONT_WHEEL_DRIVE:
                if w.axle_type == FRONT_AXLE:
                    out[i] = 1 / Float32(front)
            elif kind == REAR_WHEEL_DRIVE:
                if w.axle_type == REAR_AXLE:
                    out[i] = 1 / Float32(rear)
            elif w.affected_by_engine:
                out[i] = 1
        var total = Float32(0)
        for s in out:  # pragma: no branch
            total += s
        if total > 0:
            for i in range(n):  # pragma: no branch
                out[i] /= total
        return out^

    def _couple(mut self) -> Float32:
        """Lock the engine to the driven wheels while a gear is engaged.

        Returns:
            The engine's speed as the wheels turn it, with its sign.
        """
        var shares = self._shares()
        var ratio = self._ratio()
        var wheel = Float32(0)
        # A vehicle has one wheel at least.
        for i in range(len(self.wheels)):  # pragma: no branch
            wheel += shares[i] * self.wheels[i].omega
        var turned = wheel * ratio
        if ratio != 0 and self.shift_timer <= 0:
            self.engine_omega = min(
                max(abs(turned), self.physics.idle_rpm.value),
                self.physics.max_rpm.value,
            )
        return turned

    def _engine(mut self, h: Float32):
        var turned = self._couple()
        ref p = self.physics
        var shares = self._shares()
        var ratio = self._ratio()
        var engaged = ratio != 0 and self.shift_timer <= 0
        var idle = p.idle_rpm.value
        var top = p.max_rpm.value
        var throttle = self.applied.throttle
        var torque = Float32(0)
        if throttle > 0:
            if self.engine_omega < top:
                torque = throttle * min(
                    evaluate_curve(p.torque_curve, self.engine_omega * _TO_RPM),
                    p.max_torque.value,
                )
        elif engaged:
            torque = -p.brake_effect.value * turned / top
        if not engaged:
            if throttle > 0:
                self.engine_omega += torque / p.rev_up_moi.value * h
            else:
                self.engine_omega -= p.rev_down_rate.value * h
            self.engine_omega = min(max(self.engine_omega, idle), top)
            torque = 0
        var brake = self.applied.brake
        for i in range(len(self.wheels)):  # pragma: no branch
            ref setup = p.wheels[i]
            ref state = self.wheels[i]
            state.drive_torque = (
                torque * ratio * p.transmission_efficiency * shares[i]
            )
            var hold = Float32(0)
            if setup.affected_by_brake:
                hold += brake * setup.max_brake_torque.value
            if setup.affected_by_handbrake and self.applied.hand_brake:
                hold += setup.max_hand_brake_torque.value
            state.brake_torque = hold

    def _tires(mut self, mut world: PhysicsWorld, h: Float32) raises:
        ref body = world.bodies[self.body.value]
        var chassis = _predict_tire_body(body, self.body, world.gravity, h)
        var supports = List[_TireBody]()
        var tires = List[_Tire]()
        for i in range(len(self.wheels)):  # pragma: no branch
            ref setup = self.physics.wheels[i]
            ref state = self.wheels[i]
            var radius = setup.wheel_radius.value
            var inertia = 0.5 * setup.wheel_mass.value * radius * radius
            if not state.in_contact:
                state.omega += state.drive_torque / inertia * h
                var stop = state.brake_torque / inertia * h
                state.omega -= max(min(state.omega, stop), -stop)
                state.lat_slip = 0
                state.long_slip = 0
                state.locked = False
                state.slipping = False
                state.skidding = False
                continue
            var n = state.contact_normal
            var turn = Quaternion.from_axis_angle(
                body.rotation.rotate(Vector3(0, 0, 1)),
                Angle(state.steer, RADIAN),
            )
            var heading = (turn * body.rotation).rotate(Vector3(1, 0, 0))
            var forward = unit_or(heading - n * heading.dot(n), heading)
            var lateral = cross(n, forward)
            var support = -1
            for j in range(len(supports)):
                if supports[j].id == state.ground:
                    support = j
                    break
            if support < 0:
                support = len(supports)
                supports.append(
                    _predict_tire_body(
                        world.bodies[state.ground.value],
                        state.ground,
                        world.gravity,
                        h,
                    )
                )
            var r = state.contact_point - chassis.center
            var support_r = state.contact_point - supports[support].center
            var at = chassis.velocity_at(r) - supports[support].velocity_at(
                support_r
            )
            var along = at.dot(forward)
            var across = at.dot(lateral)
            state.lat_slip = atan2(across, abs(along))
            var load = (1 - setup.wheel_load_ratio) * state.sprung_mass * abs(
                world.gravity.z
            ) + (setup.wheel_load_ratio * state.suspension_force)
            var limit = (
                setup.friction_force_multiplier
                * state.ground_friction
                * load
                * h
            )
            var drive = state.drive_torque / radius * h
            var saturated = abs(drive) > limit
            if setup.traction_control_enabled:
                drive = max(min(drive, limit), -limit)
            var brake = state.brake_torque / radius * h
            if setup.abs_enabled:
                brake = min(brake, limit)
            state.locked = brake > limit
            var cap = setup.cornering_stiffness.value * abs(state.lat_slip) * h
            if state.locked:
                brake = inf[DType.float32]()
                cap = inf[DType.float32]()
            tires.append(
                _Tire(
                    i,
                    state.contact_point,
                    r,
                    support,
                    support_r,
                    forward,
                    lateral,
                    1
                    / (
                        chassis.inverse_mass_along(r, forward)
                        + supports[support].inverse_mass_along(
                            support_r, forward
                        )
                    ),
                    1
                    / (
                        chassis.inverse_mass_along(r, lateral)
                        + supports[support].inverse_mass_along(
                            support_r, lateral
                        )
                    ),
                    drive,
                    brake,
                    limit,
                    cap,
                    0,
                    0,
                    saturated,
                )
            )
        for _ in range(_TIRE_ITERATIONS):  # pragma: no branch
            for k in range(len(tires)):
                ref t = tires[k]
                ref support = supports[t.support]
                var at = chassis.velocity_at(t.r) - support.velocity_at(
                    t.support_r
                )
                var along = max(
                    min(
                        t.along - t.mass_forward * at.dot(t.forward),
                        t.drive + t.brake,
                    ),
                    t.drive - t.brake,
                )
                var across = max(
                    min(
                        t.across - t.mass_lateral * at.dot(t.lateral),
                        t.lateral_cap,
                    ),
                    -t.lateral_cap,
                )
                var size = sqrt(along * along + across * across)
                if size > t.limit:
                    along *= t.limit / size
                    across *= t.limit / size
                var impulse = t.forward * (along - t.along) + t.lateral * (
                    across - t.across
                )
                t.along = along
                t.across = across
                chassis.apply(impulse, t.r)
                if support.responds:
                    support.apply(-impulse, t.support_r)
        for t in tires:
            ref setup = self.physics.wheels[t.wheel]
            ref state = self.wheels[t.wheel]
            var radius = setup.wheel_radius.value
            var force = (t.forward * t.along + t.lateral * t.across) / h
            world.bodies[self.body.value].add_force(force, t.point)
            _push_ground(world, state.ground, -force, t.point)
            var relative = chassis.velocity_at(t.r) - supports[
                t.support
            ].velocity_at(t.support_r)
            var ground = relative.dot(t.forward)
            var sliding = sqrt(t.along * t.along + t.across * t.across)
            state.skidding = (
                sliding >= t.limit * 0.999
                and abs(relative.dot(t.lateral)) > setup.skid_threshold.value
            )
            if state.locked:
                state.spin = 0
                state.omega = 0
            elif t.drive_saturated and not setup.traction_control_enabled:
                var inertia = 0.5 * setup.wheel_mass.value * radius * radius
                state.spin += (
                    (state.drive_torque - t.along / h * radius) / inertia * h
                )
                var most = setup.max_wheelspin_rotation.value
                state.spin = max(min(state.spin, most), -most)
                state.omega = ground / radius + state.spin
            else:
                state.spin = 0
                state.omega = ground / radius
            var slip_speed = state.omega * radius - ground
            state.slipping = abs(slip_speed) > setup.slip_threshold.value
            state.long_slip = slip_speed / max(abs(ground), 0.1)

    def _aerodynamics(mut self, mut world: PhysicsWorld):
        ref body = world.bodies[self.body.value]
        var v = body.linear_velocity
        var area = self.physics.frontal_area().value
        var q = 0.5 * AIR_DENSITY * area
        var drag = v * (-q * self.physics.drag_coefficient * v.length())
        var forward = body.rotation.rotate(Vector3(1, 0, 0)).dot(v)
        var down = body.rotation.rotate(Vector3(0, 0, -1)) * (
            q * self.physics.downforce_coefficient * forward * forward
        )
        var com = body.world_center_of_mass()
        body.add_force(drag + down, com)

    def _rollover(mut self, mut world: PhysicsWorld, h: Float32):
        ref body = world.bodies[self.body.value]
        var m = rotation_matrix(body.rotation)
        # CARLA's roll: atan2 of the third row's middle and last entries.
        var roll = atan2(m.elements[5], m.elements[8]) * Float32(
            180.0 / 3.141592653589793
        )
        if self.rollover_tracker < 4:
            var low = Float32(130 + 10 * self.rollover_tracker)
            # CARLA's window runs from `low` to 230 - 10 k degrees. The
            # roll from atan2 is at most 180, so only the low end can
            # fail, and only a positive roll trips it.
            if low < roll:
                body.angular_velocity = body.angular_velocity * (
                    1 - ROLLOVER_FORCE
                )
                self.rollover_tracker += 1
        elif self.rollover_tracker == 4:
            self.rollover_timer = ROLLOVER_FLAG_TIME
            self.rollover_tracker += 1
        if self.rollover_timer >= 0:
            self.rollover_timer -= h
            # A recovery stops the timer, so the tracker is still past 4.
            if self.rollover_timer < 0:
                self.failure_state = ROLLOVER
        if self.rollover_tracker > 0 and abs(roll) < 30:
            self.rollover_tracker = 0
            self.rollover_timer = -1
            self.failure_state = NO_FAILURE


comptime _TO_RPM = Float32(60.0 / (2.0 * 3.141592653589793))


def _predict_tire_body(
    body: RigidBody, id: BodyId, gravity: Vector3, h: Float32
) -> _TireBody:
    """Predict the world's force kick and its response to tire impulses."""
    var inverse_mass = Float32(0)
    var inverse_inertia = Matrix3()
    inverse_inertia.multiply_scalar(0)
    var v = body.linear_velocity
    var w = body.angular_velocity
    var responds = body.is_dynamic()
    if responds:
        inverse_mass = body.inverse_mass()
        inverse_inertia = body.world_inverse_inertia()
        var linear_factor = 1 / (1 + h * body.linear_damping)
        var angular_factor = 1 / (1 + h * body.angular_damping)
        v = (
            v + (gravity * body.gravity_scale + body.force * inverse_mass) * h
        ) * linear_factor
        w = (w + inverse_inertia.transform(body.torque) * h) * angular_factor
        # Tire forces are accumulated before that same damping kick.
        inverse_mass *= linear_factor
        inverse_inertia.multiply_scalar(angular_factor)
    return _TireBody(
        id,
        body.world_center_of_mass(),
        inverse_mass,
        inverse_inertia,
        v,
        w,
        responds,
    )


def _push_ground(
    mut world: PhysicsWorld, ground: BodyId, force: Vector3, at: Vector3
):
    """Give a dynamic ground the reaction of a wheel's force."""
    ref body = world.bodies[ground.value]
    if body.is_dynamic():
        body.add_force(force, at)
