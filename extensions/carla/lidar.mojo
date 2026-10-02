# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""CARLA's ray-cast LiDAR, `RayCastLidar` and `RayCastSemanticLidar`.

The lasers are spread evenly from the upper to the lower field-of-view
limit. In one tick each laser fires the same number of rays, sweeping the
horizontal angle that the rotation frequency covers in that time. A hit's
intensity falls with distance as exp(-a d). Before the cast a general
drop-off removes a fraction of the rays. After it, a hit whose intensity
is at or below a limit is kept with a probability that rises with its
intensity.

The laser angles follow CARLA's frame: plus elevation is above the
horizon, and plus azimuth turns from forward toward right. CARLA draws
its random numbers from its simulator's own generator. This port draws
them from a seeded xorshift generator, so a scan repeats exactly for one
seed.
"""

from core.assets import Assets
from core.scene import Scene
from extensions.carla.capture import nearest_hit
from extensions.carla.sensor_attributes import validate_sensor_float
from extensions.carla.transform import CarlaTransform
from math.vector3 import Vector3
from std.math import cos, exp, log, sin, sqrt, trunc
from units.si import (
    DEGREE,
    PER_METER,
    PER_SECOND,
    RADIAN,
    SECOND,
    Angle,
    Duration,
    Frequency,
    InverseLength,
    Length,
    METER,
)


struct LidarDescription(ImplicitlyCopyable):
    """A LiDAR's settings, CARLA's LiDAR description, with its defaults."""

    var channels: Int
    var range: Length
    var points_per_second: Int
    var rotation_frequency: Frequency
    var upper_fov: Angle
    var lower_fov: Angle
    var horizontal_fov: Angle
    var atmosphere_attenuation: InverseLength
    var dropoff_general_rate: Float32
    var dropoff_intensity_limit: Float32
    var dropoff_zero_intensity: Float32
    # The standard deviation of the noise along each ray.
    var noise_stddev: Length

    def __init__(out self):
        """Create the description of CARLA's `sensor.lidar.ray_cast`."""
        self.channels = 32
        self.range = Length(10.0, METER)
        self.points_per_second = 56000
        self.rotation_frequency = Frequency(10.0, PER_SECOND)
        self.upper_fov = Angle(10.0, DEGREE)
        self.lower_fov = Angle(-30.0, DEGREE)
        self.horizontal_fov = Angle(360.0, DEGREE)
        self.atmosphere_attenuation = InverseLength(0.004, PER_METER)
        self.dropoff_general_rate = 0.45
        self.dropoff_intensity_limit = 0.8
        self.dropoff_zero_intensity = 0.4
        self.noise_stddev = Length(0.0, METER)

    def validate(self, rotating: Bool = True) raises:
        """Refuse settings that CARLA would assert on or misread.

        Args:
            rotating: Whether to check rotating scan rates and sweep limits.
                HSS scans ignore the rates and clamp a negative sweep to zero.

        Raises:
            Error: If a consumed physical value is nonfinite, the scan
                dimensions or rates are invalid, the fields of view are
                out of order, a drop-off rate is outside 0 through 1,
                or attenuation or noise is negative. An HSS intensity
                limit can be zero; a rotating LiDAR's must be positive.
        """
        validate_sensor_float(self.range.value, "LiDAR range.value")
        validate_sensor_float(self.upper_fov.value, "LiDAR upper_fov.value")
        validate_sensor_float(self.lower_fov.value, "LiDAR lower_fov.value")
        validate_sensor_float(
            self.horizontal_fov.value, "LiDAR horizontal_fov.value"
        )
        validate_sensor_float(
            self.atmosphere_attenuation.value,
            "LiDAR atmosphere_attenuation.value",
        )
        validate_sensor_float(
            self.dropoff_general_rate, "LiDAR dropoff_general_rate"
        )
        validate_sensor_float(
            self.dropoff_zero_intensity, "LiDAR dropoff_zero_intensity"
        )
        validate_sensor_float(
            self.dropoff_intensity_limit, "LiDAR dropoff_intensity_limit"
        )
        validate_sensor_float(
            self.noise_stddev.value, "LiDAR noise_stddev.value"
        )
        if self.channels < 1:
            raise Error("A LiDAR needs at least one channel")
        if not (self.range.value > 0.0):
            raise Error("A LiDAR needs a positive range")
        if rotating:
            validate_sensor_float(
                self.rotation_frequency.value, "LiDAR rotation_frequency.value"
            )
            if self.points_per_second < 1:
                raise Error("A LiDAR needs a positive point rate")
            if not (self.rotation_frequency.value > 0.0):
                raise Error("A LiDAR needs a positive rotation frequency")
        if self.upper_fov.value < self.lower_fov.value:
            raise Error("A LiDAR's upper fov must not be below its lower fov")
        if rotating:
            if not (
                self.horizontal_fov.value > 0.0
                and self.horizontal_fov.to(DEGREE) <= 360.0
            ):
                raise Error("A LiDAR's horizontal fov must be in (0, 360]")
        if self.atmosphere_attenuation.value < 0.0:
            raise Error("A LiDAR's attenuation cannot be negative")
        if not (
            self.dropoff_general_rate >= 0.0
            and self.dropoff_general_rate <= 1.0
            and self.dropoff_zero_intensity >= 0.0
            and self.dropoff_zero_intensity <= 1.0
        ):
            raise Error("A LiDAR drop-off rate must be from 0 through 1")
        if rotating:
            if not (self.dropoff_intensity_limit > 0.0):
                raise Error("A LiDAR drop-off limit must be positive")
        elif self.dropoff_intensity_limit < 0.0:
            raise Error("An HSS LiDAR drop-off limit cannot be negative")
        if self.noise_stddev.value < 0.0:
            raise Error("A LiDAR's noise cannot be negative")

    def laser_angles(self) -> List[Angle]:
        """Return each laser's elevation, `CreateLasers`.

        Returns:
            One angle per channel, from the upper limit down to the lower.
            One channel points at the upper limit.
        """
        var out = List[Angle]()
        var upper = self.upper_fov.to(DEGREE)
        var delta = Float32(0.0)
        if self.channels > 1:
            delta = (upper - self.lower_fov.to(DEGREE)) / Float32(
                self.channels - 1
            )
        for i in range(self.channels):
            out.append(Angle(upper - Float32(i) * delta, DEGREE))
        return out^

    def points_per_laser(self, tick: Duration) -> Int:
        """Return how many rays one laser fires in one tick.

        Args:
            tick: The simulation step.

        Returns:
            The points per second times the tick over the channels,
            rounded half away from zero.
        """
        var exact = (
            Float32(self.points_per_second)
            * tick.to(SECOND)
            / Float32(self.channels)
        )
        return Int(exact + 0.5)

    def intensity(self, distance: Length) -> Float32:
        """Return a hit's intensity, `ComputeIntensity`.

        Args:
            distance: From the sensor to the hit.

        Returns:
            The exponential of minus attenuation times distance.
        """
        return exp(-self.atmosphere_attenuation.value * distance.value)


def _fmod(a: Float32, b: Float32) -> Float32:
    # C's fmod: the remainder takes the sign of a.
    return a - b * trunc(a / b)


struct _XorShift(Movable):
    var state: UInt64

    def __init__(out self, seed: Int):
        self.state = UInt64(seed) * 6364136223846793005 + 1442695040888963407
        if self.state == 0:
            self.state = 1

    def uniform(mut self) -> Float32:
        self.state ^= self.state << 13
        self.state ^= self.state >> 7
        self.state ^= self.state << 17
        return Float32(Float64(self.state >> 40) / 16777216.0)

    def gauss(mut self) -> Float32:
        var u = max(self.uniform(), Float32(1e-7))
        var v = self.uniform()
        return sqrt(-2.0 * log(u)) * cos(6.2831853 * v)


@fieldwise_init
struct LidarPoint(ImplicitlyCopyable):
    """One detection, in the sensor's CARLA frame."""

    # Forward, right and up, in meters.
    var point: Vector3
    var intensity: Float32
    var channel: Int


struct LidarScan(Movable):
    """The detections of one tick, and where the next tick starts."""

    var points: List[LidarPoint]
    # The horizontal angle the next tick starts from.
    var next_angle: Angle

    def __init__(out self, var points: List[LidarPoint], next_angle: Angle):
        """Create a scan.

        Args:
            points: The detections.
            next_angle: Where the next tick starts.
        """
        self.points = points^
        self.next_angle = next_angle


def scan_lidar(
    scene: Scene,
    assets: Assets,
    sensor: CarlaTransform,
    description: LidarDescription,
    tick: Duration,
    start_angle: Angle,
    seed: Int,
) raises -> LidarScan:
    """Cast one tick of a LiDAR against a scene, `SimulateLidar`.

    Args:
        scene: The scene, updated.
        assets: Its geometry and materials.
        sensor: Where the LiDAR is, in CARLA's world frame.
        description: The LiDAR's settings.
        tick: The simulation step. It must be positive.
        start_angle: The horizontal angle this tick starts from.
        seed: The seed of the drop-off and noise draws.

    Returns:
        The kept detections, channel by channel, and the next start.

    Raises:
        Error: If the description is not valid, `tick` is not positive,
            or a mesh cannot be tested.
    """
    description.validate()
    if not (tick.value > 0.0):
        raise Error("A LiDAR tick must be positive")
    var rng = _XorShift(seed)
    var per_laser = description.points_per_laser(tick)
    var fov = description.horizontal_fov.to(DEGREE)
    var current = start_angle.to(DEGREE)
    var sweep = description.rotation_frequency.value * fov * tick.to(SECOND)
    var angles = description.laser_angles()
    var beta = 1.0 - description.dropoff_zero_intensity
    var alpha = (
        description.dropoff_zero_intensity / description.dropoff_intensity_limit
    )
    var points = List[LidarPoint]()
    if per_laser < 1:
        # CARLA warns and skips the tick: no rays, and no turn.
        return LidarScan(points^, start_angle)
    for channel in range(description.channels):  # pragma: no branch
        var elevation = angles[channel].to(RADIAN)
        for i in range(per_laser):  # pragma: no branch
            if rng.uniform() < description.dropoff_general_rate:
                continue
            var azimuth = (
                _fmod(current + sweep * Float32(i) / Float32(per_laser), fov)
                - fov / 2.0
            ) * Float32(0.017453292519943295)
            var local = Vector3(
                cos(elevation) * cos(azimuth),
                cos(elevation) * sin(azimuth),
                sin(elevation),
            )
            var direction = sensor.rotation.rotate_vector(local)
            var hit = nearest_hit(
                scene, assets, sensor.location, direction, description.range
            )
            if hit.mesh < 0:
                continue
            var intensity = description.intensity(Length(hit.distance, METER))
            var distance = hit.distance
            if description.noise_stddev.value > 0.0:
                distance += rng.gauss() * description.noise_stddev.value
            var at = sensor.location + direction * distance
            if (
                intensity <= description.dropoff_intensity_limit
                and rng.uniform() >= alpha * intensity + beta
            ):
                continue
            points.append(
                LidarPoint(
                    sensor.inverse_transform_point(at), intensity, channel
                )
            )
    var next = _fmod(current + sweep, fov)
    return LidarScan(points^, Angle(next, DEGREE))
