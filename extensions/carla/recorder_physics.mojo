# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""The recorder's physics control record, `CarlaRecorderPhysicsControl`.

CARLA writes a vehicle's `rpc::VehiclePhysicsControl` field by field:
the actor's id as a `uint32`, then the setup's numbers as `float`s, the
differential as a byte and the flags as `bool`s, in the order below, and
then five lists, each a `uint32` count and its items: the torque curve,
the forward and reverse gear ratios, the steering curve and the wheels.
A curve's point is two `float`s.

A wheel is a copy of CARLA's C++ `rpc::WheelPhysicsControl` record, 208
bytes, as the LP64 ABI of Linux and macOS lays it out: each field sits at
a multiple of its size, and the record ends at a multiple of eight.

| Offset | Field |
|---|---|
| 0 | axle type, a byte |
| 4 | offset, three `float`s |
| 16 | radius, width, mass, cornering stiffness, friction multiplier, side slip modifier, slip and skid thresholds, max steer angle |
| 52 | the six flags: steering, brake, handbrake, engine, ABS, traction control |
| 60 | max wheelspin rotation |
| 64 | torque combine method, a byte |
| 72 | the lateral slip graph: a C++ `std::vector`, three pointers |
| 96 | suspension axis and force offset, three `float`s each |
| 120 | max raise, max drop, damping ratio, load ratio, spring rate, preload |
| 144 | suspension smoothing, an `int` |
| 148 | rollbar scaling |
| 152 | sweep shape and sweep type, a byte each |
| 156 | max brake and handbrake torque |
| 164 | wheel index, an `int` |
| 168 | location, old location and velocity, three `float`s each |

CARLA copies the lateral slip graph's pointers into the file, not its
points. An empty graph is three null pointers, 24 zero bytes. This port
writes 24 zero bytes for every graph, and reads every graph as empty.
The padding bytes are zero.

The numbers keep CARLA's units: lengths in centimeters, a speed in
centimeters per second, an engine speed in revolutions per minute, an
angle in degrees and the wheelspin limit in radians per second, as the
physics tier reads them. `from_control` turns a `VehiclePhysicsControl`
into them. The physics tier does not keep a wheel's index, location, old
location or velocity: `from_control` writes the wheel's place in the list
and zero vectors.

The source is CARLA's simulator plugin, `Carla/Recorder/
CarlaRecorderPhysicsControl.cpp`, and `LibCarla/source/carla/rpc/
VehiclePhysicsControl.h` and `WheelPhysicsControl.h`.
"""

from extensions.carla.actor import ActorId
from extensions.carla.physics.quantities import (
    NEWTON_METER,
    NEWTON_PER_CENTIMETER,
    NEWTON_PER_DEGREE,
    REVOLUTION_PER_MINUTE,
    REVOLUTION_PER_MINUTE_PER_SECOND,
)
from extensions.carla.physics.vehicle_physics import (
    AxleType,
    DifferentialType,
    SweepShape,
    SweepType,
    TorqueCombineMethod,
    VehiclePhysicsControl,
)
from extensions.carla.recorder_format import c_fixed, c_general
from extensions.carla.recorder_packets import (
    LogReader,
    PACKET_PHYSICS_CONTROL,
    write_packet,
)
from extensions.carla.sensor_data import ByteWriter
from math.vector2 import Vector2
from math.vector3 import Vector3
from units.si import (
    AreaUnit,
    CENTIMETER,
    DEGREE,
    KILOGRAM,
    KILOGRAM_SQUARE_METER,
    NEWTON,
    RADIAN_PER_SECOND,
    SECOND,
    VelocityUnit,
)

comptime SQUARE_CENTIMETER = AreaUnit(1.0e-4, "cm^2")
comptime CENTIMETER_PER_SECOND = VelocityUnit(0.01, "cm/s")

# The bytes of one wheel record.
comptime WHEEL_RECORD_SIZE = 208


def _cm(v: Vector3) -> Vector3:
    return Vector3(v.x * 100, v.y * 100, v.z * 100)


def _write_vector3(mut w: ByteWriter, v: Vector3):
    w.f32(v.x)
    w.f32(v.y)
    w.f32(v.z)


def _read_vector3(mut r: LogReader) -> Vector3:
    var x = r.f32()
    var y = r.f32()
    var z = r.f32()
    return Vector3(x, y, z)


def _write_curve(mut w: ByteWriter, curve: List[Vector2]):
    w.u32(len(curve))
    for p in curve:
        w.f32(p.x)
        w.f32(p.y)


def _read_curve(mut r: LogReader) -> List[Vector2]:
    var n = r.u32()
    var out = List[Vector2]()
    for _ in range(n):
        var x = r.f32()
        var y = r.f32()
        out.append(Vector2(x, y))
    return out^


def _write_floats(mut w: ByteWriter, values: List[Float32]):
    w.u32(len(values))
    for v in values:
        w.f32(v)


def _read_floats(mut r: LogReader) -> List[Float32]:
    var n = r.u32()
    var out = List[Float32]()
    for _ in range(n):
        out.append(r.f32())
    return out^


def _flag(value: Bool) -> UInt8:
    return UInt8(Int(value))


@fieldwise_init
struct RecordedWheelPhysics(Copyable, Movable):
    """One wheel's setup as the file holds it, in CARLA's units."""

    var axle_type: AxleType
    var offset: Vector3
    var wheel_radius: Float32
    var wheel_width: Float32
    var wheel_mass: Float32
    var cornering_stiffness: Float32
    var friction_force_multiplier: Float32
    var side_slip_modifier: Float32
    var slip_threshold: Float32
    var skid_threshold: Float32
    var max_steer_angle: Float32
    var affected_by_steering: Bool
    var affected_by_brake: Bool
    var affected_by_handbrake: Bool
    var affected_by_engine: Bool
    var abs_enabled: Bool
    var traction_control_enabled: Bool
    var max_wheelspin_rotation: Float32
    var external_torque_combine_method: TorqueCombineMethod
    var suspension_axis: Vector3
    var suspension_force_offset: Vector3
    var suspension_max_raise: Float32
    var suspension_max_drop: Float32
    var suspension_damping_ratio: Float32
    var wheel_load_ratio: Float32
    var spring_rate: Float32
    var spring_preload: Float32
    var suspension_smoothing: Int
    var rollbar_scaling: Float32
    var sweep_shape: SweepShape
    var sweep_type: SweepType
    var max_brake_torque: Float32
    var max_hand_brake_torque: Float32
    var wheel_index: Int
    var location: Vector3
    var old_location: Vector3
    var velocity: Vector3

    def write(self, mut w: ByteWriter) raises:
        """Write the 208-byte record.

        Args:
            w: Where the bytes go.

        Raises:
            Error: If a kind is not valid.
        """
        if not (
            self.axle_type.is_valid()
            and self.external_torque_combine_method.is_valid()
            and self.sweep_shape.is_valid()
            and self.sweep_type.is_valid()
        ):
            raise Error("Recorder: a wheel's kind is not valid")
        w.u8(UInt8(self.axle_type.value))
        w.zeros(3)
        _write_vector3(w, self.offset)
        w.f32(self.wheel_radius)
        w.f32(self.wheel_width)
        w.f32(self.wheel_mass)
        w.f32(self.cornering_stiffness)
        w.f32(self.friction_force_multiplier)
        w.f32(self.side_slip_modifier)
        w.f32(self.slip_threshold)
        w.f32(self.skid_threshold)
        w.f32(self.max_steer_angle)
        w.u8(_flag(self.affected_by_steering))
        w.u8(_flag(self.affected_by_brake))
        w.u8(_flag(self.affected_by_handbrake))
        w.u8(_flag(self.affected_by_engine))
        w.u8(_flag(self.abs_enabled))
        w.u8(_flag(self.traction_control_enabled))
        w.zeros(2)
        w.f32(self.max_wheelspin_rotation)
        w.u8(UInt8(self.external_torque_combine_method.value))
        # Seven bytes of padding, then the graph's three pointers.
        w.zeros(7 + 24)
        _write_vector3(w, self.suspension_axis)
        _write_vector3(w, self.suspension_force_offset)
        w.f32(self.suspension_max_raise)
        w.f32(self.suspension_max_drop)
        w.f32(self.suspension_damping_ratio)
        w.f32(self.wheel_load_ratio)
        w.f32(self.spring_rate)
        w.f32(self.spring_preload)
        w.u32(self.suspension_smoothing)
        w.f32(self.rollbar_scaling)
        w.u8(UInt8(self.sweep_shape.value))
        w.u8(UInt8(self.sweep_type.value))
        w.zeros(2)
        w.f32(self.max_brake_torque)
        w.f32(self.max_hand_brake_torque)
        w.u32(self.wheel_index)
        _write_vector3(w, self.location)
        _write_vector3(w, self.old_location)
        _write_vector3(w, self.velocity)
        w.zeros(4)

    @staticmethod
    def read(mut r: LogReader) raises -> RecordedWheelPhysics:
        """Read the 208-byte record.

        Args:
            r: The reader.

        Returns:
            The wheel. Its lateral slip graph is not in the file.

        Raises:
            Error: If a kind is not valid.
        """
        var axle = AxleType(r.u8())
        r.skip(3)
        var offset = _read_vector3(r)
        var f = List[Float32]()
        for _ in range(9):  # pragma: no branch
            f.append(r.f32())
        var flags = List[Bool]()
        for _ in range(6):  # pragma: no branch
            flags.append(r.boolean())
        r.skip(2)
        var spin = r.f32()
        var combine = TorqueCombineMethod(r.u8())
        r.skip(7 + 24)
        var axis = _read_vector3(r)
        var force_offset = _read_vector3(r)
        var s = List[Float32]()
        for _ in range(6):  # pragma: no branch
            s.append(r.f32())
        var smoothing = r.i32()
        var rollbar = r.f32()
        var shape = SweepShape(r.u8())
        var sweep = SweepType(r.u8())
        r.skip(2)
        var brake = r.f32()
        var hand = r.f32()
        var index = r.i32()
        var location = _read_vector3(r)
        var old = _read_vector3(r)
        var velocity = _read_vector3(r)
        r.skip(4)
        if not (
            axle.is_valid()
            and combine.is_valid()
            and shape.is_valid()
            and sweep.is_valid()
        ):
            raise Error("Recorder: a wheel's kind is not valid")
        return RecordedWheelPhysics(
            axle,
            offset,
            f[0],
            f[1],
            f[2],
            f[3],
            f[4],
            f[5],
            f[6],
            f[7],
            f[8],
            flags[0],
            flags[1],
            flags[2],
            flags[3],
            flags[4],
            flags[5],
            spin,
            combine,
            axis,
            force_offset,
            s[0],
            s[1],
            s[2],
            s[3],
            s[4],
            s[5],
            smoothing,
            rollbar,
            shape,
            sweep,
            brake,
            hand,
            index,
            location,
            old,
            velocity,
        )


@fieldwise_init
struct RecordedPhysicsControl(Copyable, Movable):
    """A vehicle's setup as the file holds it, in CARLA's units."""

    var database_id: ActorId
    var max_torque: Float32
    var max_rpm: Float32
    var idle_rpm: Float32
    var brake_effect: Float32
    var rev_up_moi: Float32
    var rev_down_rate: Float32
    var differential_type: DifferentialType
    var front_rear_split: Float32
    var use_automatic_gears: Bool
    var gear_change_time: Float32
    var final_ratio: Float32
    var change_up_rpm: Float32
    var change_down_rpm: Float32
    var transmission_efficiency: Float32
    var mass: Float32
    var drag_coefficient: Float32
    var center_of_mass: Vector3
    var chassis_width: Float32
    var chassis_height: Float32
    var downforce_coefficient: Float32
    var drag_area: Float32
    var inertia_tensor_scale: Vector3
    var sleep_threshold: Float32
    var sleep_slope_limit: Float32
    var use_sweep_wheel_collision: Bool
    var torque_curve: List[Vector2]
    var forward_gear_ratios: List[Float32]
    var reverse_gear_ratios: List[Float32]
    var steering_curve: List[Vector2]
    var wheels: List[RecordedWheelPhysics]

    @staticmethod
    def from_control(
        id: ActorId, control: VehiclePhysicsControl
    ) -> RecordedPhysicsControl:
        """Turn a vehicle's setup into CARLA's units.

        Args:
            id: The vehicle.
            control: Its setup.

        Returns:
            The record: lengths in centimeters, the drag area in square
            centimeters, speeds in centimeters per second.
        """
        var wheels = List[RecordedWheelPhysics]()
        for i in range(len(control.wheels)):
            ref w = control.wheels[i]
            wheels.append(
                RecordedWheelPhysics(
                    w.axle_type,
                    _cm(w.offset),
                    w.wheel_radius.to(CENTIMETER),
                    w.wheel_width.to(CENTIMETER),
                    w.wheel_mass.to(KILOGRAM),
                    w.cornering_stiffness.to(NEWTON_PER_DEGREE),
                    w.friction_force_multiplier,
                    w.side_slip_modifier,
                    w.slip_threshold.to(CENTIMETER_PER_SECOND),
                    w.skid_threshold.to(CENTIMETER_PER_SECOND),
                    w.max_steer_angle.to(DEGREE),
                    w.affected_by_steering,
                    w.affected_by_brake,
                    w.affected_by_handbrake,
                    w.affected_by_engine,
                    w.abs_enabled,
                    w.traction_control_enabled,
                    w.max_wheelspin_rotation.to(RADIAN_PER_SECOND),
                    w.external_torque_combine_method,
                    w.suspension_axis,
                    _cm(w.suspension_force_offset),
                    w.suspension_max_raise.to(CENTIMETER),
                    w.suspension_max_drop.to(CENTIMETER),
                    w.suspension_damping_ratio,
                    w.wheel_load_ratio,
                    w.spring_rate.to(NEWTON_PER_CENTIMETER),
                    w.spring_preload.to(NEWTON),
                    w.suspension_smoothing,
                    w.rollbar_scaling,
                    w.sweep_shape,
                    w.sweep_type,
                    w.max_brake_torque.to(NEWTON_METER),
                    w.max_hand_brake_torque.to(NEWTON_METER),
                    i,
                    Vector3(0, 0, 0),
                    Vector3(0, 0, 0),
                    Vector3(0, 0, 0),
                )
            )
        return RecordedPhysicsControl(
            id,
            control.max_torque.to(NEWTON_METER),
            control.max_rpm.to(REVOLUTION_PER_MINUTE),
            control.idle_rpm.to(REVOLUTION_PER_MINUTE),
            control.brake_effect.to(NEWTON_METER),
            control.rev_up_moi.to(KILOGRAM_SQUARE_METER),
            control.rev_down_rate.to(REVOLUTION_PER_MINUTE_PER_SECOND),
            control.differential_type,
            control.front_rear_split,
            control.use_automatic_gears,
            control.gear_change_time.to(SECOND),
            control.final_ratio,
            control.change_up_rpm.to(REVOLUTION_PER_MINUTE),
            control.change_down_rpm.to(REVOLUTION_PER_MINUTE),
            control.transmission_efficiency,
            control.mass.to(KILOGRAM),
            control.drag_coefficient,
            _cm(control.center_of_mass),
            control.chassis_width.to(CENTIMETER),
            control.chassis_height.to(CENTIMETER),
            control.downforce_coefficient,
            control.drag_area.to(SQUARE_CENTIMETER),
            control.inertia_tensor_scale,
            control.sleep_threshold,
            control.sleep_slope_limit,
            control.use_sweep_wheel_collision,
            control.torque_curve.copy(),
            control.forward_gear_ratios.copy(),
            control.reverse_gear_ratios.copy(),
            control.steering_curve.copy(),
            wheels^,
        )

    def write(self, mut w: ByteWriter) raises:
        """Write the record.

        Args:
            w: Where the bytes go.

        Raises:
            Error: If the id, the differential or a wheel's kind is not
                valid.
        """
        if not self.database_id.is_valid():
            raise Error("Recorder: an actor id must fit 32 bits")
        if not self.differential_type.is_valid():
            raise Error("Recorder: the differential type is not valid")
        w.u32(self.database_id.value)
        w.f32(self.max_torque)
        w.f32(self.max_rpm)
        w.f32(self.idle_rpm)
        w.f32(self.brake_effect)
        w.f32(self.rev_up_moi)
        w.f32(self.rev_down_rate)
        w.u8(UInt8(self.differential_type.value))
        w.f32(self.front_rear_split)
        w.u8(_flag(self.use_automatic_gears))
        w.f32(self.gear_change_time)
        w.f32(self.final_ratio)
        w.f32(self.change_up_rpm)
        w.f32(self.change_down_rpm)
        w.f32(self.transmission_efficiency)
        w.f32(self.mass)
        w.f32(self.drag_coefficient)
        _write_vector3(w, self.center_of_mass)
        w.f32(self.chassis_width)
        w.f32(self.chassis_height)
        w.f32(self.downforce_coefficient)
        w.f32(self.drag_area)
        _write_vector3(w, self.inertia_tensor_scale)
        w.f32(self.sleep_threshold)
        w.f32(self.sleep_slope_limit)
        w.u8(_flag(self.use_sweep_wheel_collision))
        _write_curve(w, self.torque_curve)
        _write_floats(w, self.forward_gear_ratios)
        _write_floats(w, self.reverse_gear_ratios)
        _write_curve(w, self.steering_curve)
        w.u32(len(self.wheels))
        for wheel in self.wheels:
            wheel.write(w)

    @staticmethod
    def read(mut r: LogReader) raises -> RecordedPhysicsControl:
        """Read the record.

        Args:
            r: The reader.

        Returns:
            The record.

        Raises:
            Error: If the differential or a wheel's kind is not valid.
        """
        var id = ActorId(r.u32())
        var a = List[Float32]()
        for _ in range(6):  # pragma: no branch
            a.append(r.f32())
        var differential = DifferentialType(r.u8())
        if not differential.is_valid():
            raise Error("Recorder: the differential type is not valid")
        var split = r.f32()
        var automatic = r.boolean()
        var b = List[Float32]()
        for _ in range(7):  # pragma: no branch
            b.append(r.f32())
        var center = _read_vector3(r)
        var c = List[Float32]()
        for _ in range(4):  # pragma: no branch
            c.append(r.f32())
        var scale = _read_vector3(r)
        var sleep = r.f32()
        var slope = r.f32()
        var sweep = r.boolean()
        var torque = _read_curve(r)
        var forward = _read_floats(r)
        var reverse = _read_floats(r)
        var steering = _read_curve(r)
        var n = r.u32()
        var wheels = List[RecordedWheelPhysics]()
        for _ in range(n):
            wheels.append(RecordedWheelPhysics.read(r))
        return RecordedPhysicsControl(
            id,
            a[0],
            a[1],
            a[2],
            a[3],
            a[4],
            a[5],
            differential,
            split,
            automatic,
            b[0],
            b[1],
            b[2],
            b[3],
            b[4],
            b[5],
            b[6],
            center,
            c[0],
            c[1],
            c[2],
            c[3],
            scale,
            sleep,
            slope,
            sweep,
            torque^,
            forward^,
            reverse^,
            steering^,
            wheels^,
        )


def physics_controls_packet(
    mut w: ByteWriter, records: List[RecordedPhysicsControl]
) raises:
    """Write a `PhysicsControl` packet, or nothing with no record.

    Args:
        w: Where the bytes go.
        records: The records.

    Raises:
        Error: If a record is refused.
    """
    if len(records) == 0:
        return
    var body = ByteWriter()
    body.u16(len(records))
    # There is a record, checked above.
    for r in records:  # pragma: no branch
        r.write(body)
    write_packet(w, PACKET_PHYSICS_CONTROL, body^.finish())


def _g(value: Float32) -> String:
    return c_general(Float64(value))


def _printf_vector(v: Vector3) raises -> String:
    """A vector as CARLA's `FormatVectorLike` writes it with `%f`."""
    return (
        "("
        + c_fixed(Float64(v.x), 6)
        + ", "
        + c_fixed(Float64(v.y), 6)
        + ", "
        + c_fixed(Float64(v.z), 6)
        + ")"
    )


def _byte(value: Int) -> String:
    """A `uint8_t` put on a stream: the byte itself, as a character."""
    return chr(value)


def _bool(value: Bool) -> String:
    return "1" if value else "0"


def physics_control_text(control: RecordedPhysicsControl) raises -> String:
    """Write one record as CARLA's file-info query does.

    The byte fields, the differential, a wheel's axle type, torque combine
    method and sweep shape and type, are C++ `uint8_t`s: the stream writes
    each as the character with that code, not as a number. A flag is `0`
    or `1`. CARLA passes the curves through its curve type first, which
    sorts the points by x; the points are written in the file's order,
    which is that order for any curve CARLA records.

    Args:
        control: The record.

    Returns:
        The lines, from `  Id:` to the last wheel, ending with a newline.

    Raises:
        Error: Never; the formats are fixed.
    """
    var out = String()
    out += "  Id: " + String(control.database_id.value) + "\n"
    out += "   max_torque = " + _g(control.max_torque) + "\n"
    out += "   max_rpm = " + _g(control.max_rpm) + "\n"
    out += "   MOI = " + _g(control.rev_up_moi) + "\n"
    out += "   rev_down_rate = " + _g(control.rev_down_rate) + "\n"
    out += (
        "   differential_type = "
        + _byte(control.differential_type.value)
        + "\n"
    )
    out += "   front_rear_split = " + _g(control.front_rear_split) + "\n"
    out += (
        "   use_gear_auto_box = "
        + ("true" if control.use_automatic_gears else "false")
        + "\n"
    )
    out += "   gear_change_time = " + _g(control.gear_change_time) + "\n"
    out += "   final_ratio = " + _g(control.final_ratio) + "\n"
    out += "   change_up_rpm = " + _g(control.change_up_rpm) + "\n"
    out += "   change_down_rpm = " + _g(control.change_down_rpm) + "\n"
    out += (
        "   transmission_efficiency = "
        + _g(control.transmission_efficiency)
        + "\n"
    )
    out += "   mass = " + _g(control.mass) + "\n"
    out += "   drag_coefficient = " + _g(control.drag_coefficient) + "\n"
    var c = control.center_of_mass
    out += (
        "   center_of_mass = ("
        + _g(c.x)
        + ", "
        + _g(c.y)
        + ", "
        + _g(c.z)
        + ")\n"
    )
    out += "   torque_curve ="
    for p in control.torque_curve:
        out += " (" + _g(p.x) + ", " + _g(p.y) + ")"
    out += "\n   steering_curve ="
    for p in control.steering_curve:
        out += " (" + _g(p.x) + ", " + _g(p.y) + ")"
    out += "\n   forward_gear_ratios:\n"
    for i in range(len(control.forward_gear_ratios)):
        out += (
            "    gear "
            + String(i)
            + ": ratio "
            + _g(control.forward_gear_ratios[i])
            + "\n"
        )
    out += "   reverse_gear_ratios:\n"
    for i in range(len(control.reverse_gear_ratios)):
        out += (
            "    gear "
            + String(i)
            + ": ratio "
            + _g(control.reverse_gear_ratios[i])
            + "\n"
        )
    out += "   wheels:"
    for i in range(len(control.wheels)):
        ref w = control.wheels[i]
        out += "\nwheel #" + String(i) + ":\n"
        out += " axle_type: " + _byte(w.axle_type.value)
        out += " offset: " + _printf_vector(w.offset)
        out += " wheel_radius: " + _g(w.wheel_radius)
        out += " wheel_width: " + _g(w.wheel_width)
        out += " wheel_mass: " + _g(w.wheel_mass)
        out += " cornering_stiffness: " + _g(w.cornering_stiffness)
        out += " friction_force_multiplier: " + _g(w.friction_force_multiplier)
        out += " side_slip_modifier: " + _g(w.side_slip_modifier)
        out += " slip_threshold: " + _g(w.slip_threshold)
        out += " skid_threshold: " + _g(w.skid_threshold)
        out += " max_steer_angle: " + _g(w.max_steer_angle)
        out += " affected_by_steering: " + _bool(w.affected_by_steering)
        out += " affected_by_brake: " + _bool(w.affected_by_brake)
        out += " affected_by_handbrake: " + _bool(w.affected_by_handbrake)
        out += " affected_by_engine: " + _bool(w.affected_by_engine)
        out += " abs_enabled: " + _bool(w.abs_enabled)
        out += " traction_control_enabled: " + _bool(w.traction_control_enabled)
        out += " max_wheelspin_rotation: " + _g(w.max_wheelspin_rotation)
        out += " external_torque_combine_method: " + _byte(
            w.external_torque_combine_method.value
        )
        out += " lateral_slip_graph: []"
        out += " suspension_axis: " + _printf_vector(w.suspension_axis)
        out += " suspension_force_offset: " + _printf_vector(
            w.suspension_force_offset
        )
        out += " suspension_max_raise: " + _g(w.suspension_max_raise)
        out += " suspension_max_drop: " + _g(w.suspension_max_drop)
        out += " suspension_damping_ratio: " + _g(w.suspension_damping_ratio)
        out += " wheel_load_ratio: " + _g(w.wheel_load_ratio)
        out += " spring_rate: " + _g(w.spring_rate)
        out += " spring_preload: " + _g(w.spring_preload)
        out += " suspension_smoothing: " + String(w.suspension_smoothing)
        out += " rollbar_scaling: " + _g(w.rollbar_scaling)
        out += " sweep_shape: " + _byte(w.sweep_shape.value)
        out += " sweep_type: " + _byte(w.sweep_type.value)
        out += " max_brake_torque: " + _g(w.max_brake_torque)
        out += " max_hand_brake_torque: " + _g(w.max_hand_brake_torque)
        out += " wheel_index: " + String(w.wheel_index)
        out += " location: " + _printf_vector(w.location)
        out += " old_location: " + _printf_vector(w.old_location)
        out += " velocity: " + _printf_vector(w.velocity)
    out += "\n"
    return out
