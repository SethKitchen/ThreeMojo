# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""CARLA's radar, `sensor.other.radar`, cast against any `RayScene`.

The source is CARLA's simulator plugin, `Carla/Sensor/Radar.cpp`, and
`LibCarla/source/carla/sensor/data/RadarData.h`.

**One tick.** The radar fires the points per second times the tick,
truncated. Each ray draws a radius r from 0 to 1 and an angle a from 0
to 2 pi, in that order, ray by ray. The ray runs from the radar to the
point (range, R_x r cos a, R_y r sin a) in the radar's frame, where
R_x = tan(horizontal fov / 2) range and R_y = tan(vertical fov / 2)
range. The ray stops at that point, so off the axis it reaches a little
past the range. A ray that meets something gives a detection:

- The velocity is the hit actor's velocity minus the radar's own, along
  the unit direction from the radar to the hit, in m/s. The radar's own
  velocity is its change of location over the tick.
- The azimuth and the altitude are the direction's angles in the radar's
  frame: the azimuth turns from forward toward right, and the altitude
  rises above the forward-right plane. This port works them as the
  spherical angles atan2(y, x) and atan2(z, sqrt(x^2 + y^2)).
- The depth is the distance to the hit.

The detections keep the order of the rays.
"""

from extensions.carla.blueprint import ActorAttributeValue
from extensions.carla.sensor_attributes import (
    attribute_float,
    attribute_int,
    validate_sensor_nonnegative,
    validate_sensor_positive,
)
from extensions.carla.sensor_noise import SensorRandom
from extensions.carla.sensor_rays import RayScene
from extensions.carla.transform import CarlaTransform
from math.vector3 import Vector3
from std.math import atan2, cos, sin, sqrt, tan
from units.si import DEGREE, RADIAN, SECOND, Angle, Duration, Length, METER

# CARLA's `Math::Pi2<float>()`.
comptime _TWO_PI = Float32(2.0) * Float32(3.14159265358979323846)


struct RadarDescription(ImplicitlyCopyable):
    """A radar's settings, with CARLA's defaults, `SetRadar`."""

    var horizontal_fov: Angle
    var vertical_fov: Angle
    var range: Length
    var points_per_second: Int
    var noise_seed: Int

    def __init__(out self):
        """Create the settings of CARLA's `sensor.other.radar`: 30 by 30
        degrees, 100 m, 1500 points a second and seed 0."""
        self.horizontal_fov = Angle(30, DEGREE)
        self.vertical_fov = Angle(30, DEGREE)
        self.range = Length(100, METER)
        self.points_per_second = 1500
        self.noise_seed = 0

    def validate(self) raises:
        """Reject nonfinite physical settings and invalid domains.

        Raises:
            Error: If a physical setting is nonfinite or outside its domain.
        """
        validate_sensor_nonnegative(
            self.horizontal_fov.value, "horizontal_fov.value"
        )
        validate_sensor_nonnegative(
            self.vertical_fov.value, "vertical_fov.value"
        )
        validate_sensor_positive(self.range.value, "range.value")
        if self.horizontal_fov.to(DEGREE) >= 180:
            raise Error("A radar horizontal fov must be less than 180 degrees")
        if self.vertical_fov.to(DEGREE) >= 180:
            raise Error("A radar vertical fov must be less than 180 degrees")
        if self.points_per_second < 0:
            raise Error("A radar point rate cannot be negative")

    @staticmethod
    def from_attributes(
        attributes: List[ActorAttributeValue],
    ) raises -> RadarDescription:
        """Read the settings from an actor's attributes, `SetRadar`.

        Args:
            attributes: The actor's attributes.

        Returns:
            The settings. A missing attribute keeps its default.

        Raises:
            Error: If a physical setting is nonfinite or outside its domain.
        """
        var d = RadarDescription()
        d.horizontal_fov = Angle(
            attribute_float(attributes, "horizontal_fov", 30), DEGREE
        )
        d.vertical_fov = Angle(
            attribute_float(attributes, "vertical_fov", 30), DEGREE
        )
        d.range = Length(attribute_float(attributes, "range", 100), METER)
        d.points_per_second = attribute_int(
            attributes, "points_per_second", 1500
        )
        d.noise_seed = attribute_int(attributes, "noise_seed", 0)
        d.validate()
        return d

    def points_in(self, tick: Duration) -> Int:
        """Return how many rays one tick fires.

        Args:
            tick: The time since the last measurement.

        Returns:
            The points per second times the tick, truncated.
        """
        return Int(Float32(self.points_per_second) * tick.to(SECOND))


@fieldwise_init
struct RadarDetection(Equatable, ImplicitlyCopyable, Writable):
    """One radar detection, CARLA's `RadarDetection`."""

    # Toward the radar is negative, in m/s.
    var velocity: Float32
    var azimuth: Angle
    var altitude: Angle
    var depth: Length

    def __eq__(self, other: Self) -> Bool:
        """Return True if the four numbers are equal.

        Args:
            other: The other detection.

        Returns:
            Whether they are equal.
        """
        return (
            self.velocity == other.velocity
            and self.azimuth.value == other.azimuth.value
            and self.altitude.value == other.altitude.value
            and self.depth.value == other.depth.value
        )

    def write_to(self, mut writer: Some[Writer]):
        """Write the detection as CARLA's Python API prints it.

        Args:
            writer: The destination.
        """
        writer.write(
            "RadarDetection(velocity=",
            self.velocity,
            ", azimuth=",
            self.azimuth.to(RADIAN),
            ", altitude=",
            self.altitude.to(RADIAN),
            ", depth=",
            self.depth.value,
            ")",
        )


struct Radar(Copyable, Movable):
    """A radar's state between ticks: its engine and its last location."""

    var description: RadarDescription
    var rng: SensorRandom
    var previous_location: Vector3

    def __init__(
        out self, description: RadarDescription, location: Vector3
    ) raises:
        """Create a radar where it spawns, `BeginPlay`.

        Args:
            description: Its settings. Its seed seeds the engine.
            location: Where it is when it starts.

        Raises:
            Error: If a physical setting is nonfinite or outside its domain.
        """
        description.validate()
        self.description = description
        self.rng = SensorRandom(description.noise_seed)
        self.previous_location = location

    def measure[
        T: RayScene
    ](
        mut self, mut scene: T, sensor: CarlaTransform, tick: Duration
    ) raises -> List[RadarDetection]:
        """Fire one tick, `PostPhysTick`.

        Args:
            scene: What the rays meet.
            sensor: Where the radar is now, in CARLA's world frame.
            tick: The time since the last measurement. It must be positive.

        Returns:
            The detections, in the order of the rays.

        Raises:
            Error: If the tick is not positive, the range is not positive,
                or the scene cannot be tested.
        """
        if not (tick.value > 0):
            raise Error("A radar tick must be positive")
        if not (self.description.range.value > 0):
            raise Error("A radar needs a positive range")
        var own_velocity = (sensor.location - self.previous_location) / Float32(
            tick.to(SECOND)
        )
        self.previous_location = sensor.location
        var reach = self.description.range.value
        var max_rx = (
            tan(self.description.horizontal_fov.to(RADIAN) * 0.5) * reach
        )
        var max_ry = tan(self.description.vertical_fov.to(RADIAN) * 0.5) * reach
        var count = self.description.points_in(tick)
        var radii = List[Float32]()
        var angles = List[Float32]()
        for _ in range(count):
            radii.append(self.rng.uniform())
            angles.append(self.rng.uniform_in(0, _TWO_PI))
        var out = List[RadarDetection]()
        for i in range(count):
            var local = Vector3(
                reach,
                max_rx * radii[i] * cos(angles[i]),
                max_ry * radii[i] * sin(angles[i]),
            )
            var hit = scene.cast_ray(
                sensor.location,
                sensor.rotation.rotate_vector(local),
                Length(local.length(), METER),
            )
            if not hit.hit:
                continue
            var toward = hit.point - sensor.location
            var length = toward.length()
            var unit = Vector3(0, 0, 0)
            if length > 0:
                unit = toward / length
            var velocity = (hit.actor_velocity - own_velocity).dot(unit)
            var flat = sqrt(local.x * local.x + local.y * local.y)
            out.append(
                RadarDetection(
                    velocity,
                    Angle(atan2(local.y, local.x), RADIAN),
                    Angle(atan2(local.z, flat), RADIAN),
                    hit.distance,
                )
            )
        return out^
