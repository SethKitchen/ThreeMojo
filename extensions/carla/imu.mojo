# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""CARLA's inertial measurement unit, `sensor.other.imu`.

The source is CARLA's simulator plugin, `Carla/Sensor/
InertialMeasurementUnit.cpp`.

- **Accelerometer.** The second derivative of the parabola through the
  sensor's last three locations: with y0 now, y1 and y2 before, h1 the
  last step and h2 the one before, a = -2 (y1 / (h1 h2) - y2 / (h2 (h1 +
  h2)) - y0 / (h1 (h1 + h2))). Before the first tick the two old
  locations are zero and h2 is the largest `Float32`, as in CARLA, so the
  first reading is mostly gravity. The world's `imu_gravity` is added to
  z, the sum is turned into the sensor's frame, and each part gets a
  normal noise with its own deviation.
- **Gyroscope.** The parent's angular velocity in the parent's frame,
  turned by the sensor's rotation relative to the parent, plus a bias and
  a normal noise for each part, in rad/s.
- **Compass.** The angle from north, (0, -1, 0) in CARLA's frame, to the
  sensor's forward vector flattened onto the ground, from 0 to 2 pi,
  turning toward east.

The noise draws follow CARLA's order: the three accelerometer parts, then
the three gyroscope parts. The arithmetic is in `Float32`, as CARLA's.
"""

from extensions.carla.blueprint import ActorAttributeValue
from extensions.carla.sensor_attributes import (
    attribute_float,
    attribute_int,
)
from extensions.carla.sensor_noise import SensorRandom
from extensions.carla.transform import CarlaRotation
from math.vector3 import Vector3
from std.ffi import external_call

from units.si import (
    RADIAN,
    SECOND,
    Acceleration,
    Angle,
    Duration,
)

# `std::numeric_limits<float>::max()`.
comptime FLOAT_MAX = Float32(3.4028234663852886e38)
# CARLA's `Math::Pi2<float>()`.
comptime _TWO_PI = Float32(2.0) * Float32(3.14159265358979323846)
# North in CARLA's frame, from OpenDRIVE's longitude and latitude.
comptime CARLA_NORTH = Vector3(0, -1, 0)


def _acosf(value: Float32) -> Float32:
    return external_call["acosf", Float32](value)


struct IMUDescription(ImplicitlyCopyable):
    """An IMU's settings, `SetIMU`: all zero by default."""

    var noise_seed: Int
    # The deviations of the accelerometer, in m/s^2, part by part.
    var accelerometer_stddev: Vector3
    # The deviations and the biases of the gyroscope, in rad/s.
    var gyroscope_stddev: Vector3
    var gyroscope_bias: Vector3

    def __init__(out self):
        """Create the settings of CARLA's `sensor.other.imu`: no noise."""
        self.noise_seed = 0
        self.accelerometer_stddev = Vector3(0, 0, 0)
        self.gyroscope_stddev = Vector3(0, 0, 0)
        self.gyroscope_bias = Vector3(0, 0, 0)

    @staticmethod
    def from_attributes(
        attributes: List[ActorAttributeValue],
    ) raises -> IMUDescription:
        """Read the settings from an actor's attributes, `SetIMU`.

        Args:
            attributes: The actor's attributes.

        Returns:
            The settings.

        Raises:
            Error: Never for these inputs; the number reader's error is
                passed on.
        """
        var d = IMUDescription()
        d.noise_seed = attribute_int(attributes, "noise_seed", 0)
        d.accelerometer_stddev = _vector(attributes, "noise_accel_stddev_")
        d.gyroscope_stddev = _vector(attributes, "noise_gyro_stddev_")
        d.gyroscope_bias = _vector(attributes, "noise_gyro_bias_")
        return d


def _vector(
    attributes: List[ActorAttributeValue], prefix: String
) raises -> Vector3:
    return Vector3(
        attribute_float(attributes, prefix + "x", 0),
        attribute_float(attributes, prefix + "y", 0),
        attribute_float(attributes, prefix + "z", 0),
    )


@fieldwise_init
struct IMUMeasurement(ImplicitlyCopyable, Writable):
    """One IMU reading, CARLA's `IMUMeasurement`."""

    # In m/s^2, in the sensor's frame.
    var accelerometer: Vector3
    # In rad/s.
    var gyroscope: Vector3
    var compass: Angle

    def write_to(self, mut writer: Some[Writer]):
        """Write the reading as CARLA's Python API prints it.

        Args:
            writer: The destination.
        """
        writer.write(
            "IMUMeasurement(accelerometer=Vector3D(x=",
            self.accelerometer.x,
            ", y=",
            self.accelerometer.y,
            ", z=",
            self.accelerometer.z,
            "), gyroscope=Vector3D(x=",
            self.gyroscope.x,
            ", y=",
            self.gyroscope.y,
            ", z=",
            self.gyroscope.z,
            "), compass=",
            self.compass.to(RADIAN),
            ")",
        )


def compass(forward: Vector3) -> Angle:
    """Return a heading from north, `ComputeCompass`.

    Args:
        forward: The forward vector, in CARLA's frame.

    Returns:
        The angle from (0, -1, 0) to the forward vector on the ground,
        from 0 to 2 pi, turning toward east (plus x). A forward vector
        that points straight up or down has no ground part, and gives a
        quarter turn, as in CARLA.
    """
    var flat = Vector3(forward.x, forward.y, 0)
    var length = flat.length()
    if length > 1e-8:
        flat = flat / length
    else:
        flat = Vector3(0, 0, 0)
    var dot = CARLA_NORTH.dot(flat)
    if dot >= 1.0:
        return Angle(0, RADIAN)
    var angle = _acosf(dot)
    # The z of north x forward: (-1)(x) - 0 (y).
    if CARLA_NORTH.x * flat.y - CARLA_NORTH.y * flat.x < 0:
        return Angle(_TWO_PI - angle, RADIAN)
    return Angle(angle, RADIAN)


struct Accelerometer(Copyable, Movable):
    """The last two locations and the last step, for the parabola."""

    var older: Vector3
    var old: Vector3
    var previous_delta: Float32

    def __init__(out self):
        """Start as CARLA does: zero locations and the largest step."""
        self.older = Vector3(0, 0, 0)
        self.old = Vector3(0, 0, 0)
        self.previous_delta = FLOAT_MAX

    def step(
        mut self,
        location: Vector3,
        tick: Duration,
        gravity: Acceleration,
        rotation: CarlaRotation,
    ) -> Vector3:
        """Return the reading before noise, `ComputeAccelerometer`.

        Args:
            location: Where the sensor is now, in meters.
            tick: The time since the last reading.
            gravity: The world's `imu_gravity`, added to z.
            rotation: The sensor's rotation in the world.

        Returns:
            The acceleration plus gravity, in the sensor's frame, in m/s^2.
        """
        var h1 = Float32(tick.to(SECOND))
        var h2 = self.previous_delta
        var both = h2 + h1
        var a = self.old / (h1 * h2)
        var b = self.older / (h2 * both)
        var c = location / (h1 * both)
        var out = (a - b - c) * Float32(-2.0)
        self.older = self.old
        self.old = location
        self.previous_delta = h1
        out.z += gravity.value
        return rotation.inverse_rotate_vector(out)


struct IMU(Copyable, Movable):
    """An IMU's state between ticks."""

    var description: IMUDescription
    var rng: SensorRandom
    var accelerometer: Accelerometer

    def __init__(out self, description: IMUDescription):
        """Create an IMU.

        Args:
            description: Its settings. Its seed seeds the engine.
        """
        self.description = description
        self.rng = SensorRandom(description.noise_seed)
        self.accelerometer = Accelerometer()

    def measure(
        mut self,
        location: Vector3,
        rotation: CarlaRotation,
        relative_rotation: CarlaRotation,
        parent_angular_velocity: Vector3,
        parent_rotation: CarlaRotation,
        tick: Duration,
        gravity: Acceleration,
    ) -> IMUMeasurement:
        """Read the sensor, `PostPhysTick`.

        Args:
            location: Where the sensor is, in meters in the world.
            rotation: Its rotation in the world.
            relative_rotation: Its rotation in its parent's frame.
            parent_angular_velocity: The parent's angular velocity in the
                world, in rad/s. Zero without a parent.
            parent_rotation: The parent's rotation in the world.
            tick: The time since the last reading.
            gravity: The world's `imu_gravity`.

        Returns:
            The accelerometer, gyroscope and compass readings.
        """
        var accel = self.accelerometer.step(location, tick, gravity, rotation)
        var s = self.description.accelerometer_stddev
        accel = Vector3(
            accel.x + self.rng.normal(0, s.x),
            accel.y + self.rng.normal(0, s.y),
            accel.z + self.rng.normal(0, s.z),
        )
        var local = parent_rotation.inverse_rotate_vector(
            parent_angular_velocity
        )
        var gyro = relative_rotation.rotate_vector(local)
        var g = self.description.gyroscope_stddev
        var bias = self.description.gyroscope_bias
        gyro = Vector3(
            gyro.x + bias.x + self.rng.normal(0, g.x),
            gyro.y + bias.y + self.rng.normal(0, g.y),
            gyro.z + bias.z + self.rng.normal(0, g.z),
        )
        return IMUMeasurement(accel, gyro, compass(rotation.forward_vector()))
