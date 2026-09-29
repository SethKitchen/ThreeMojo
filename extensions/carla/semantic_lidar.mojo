# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""CARLA's three LiDARs cast against any `RayScene`: the semantic LiDAR,
the ray-cast LiDAR and the fixed-sweep HSS LiDAR.

The sources are CARLA's simulator plugin, `Carla/Sensor/
RayCastSemanticLidar.cpp`, `RayCastLidar.cpp`, `HSSLidar.cpp` and
`LidarDescription.h`, and `LibCarla/source/carla/sensor/data/
SemanticLidarData.h` and `LidarData.h`.

**One tick.** Each laser of a rotating LiDAR fires the points per second
times the tick over the channels, rounded half away from zero. The rays
of one laser sweep the horizontal angle that the rotation frequency
covers in the tick, from where the last tick stopped. Ray i of a laser
points at fmod(start + step i, fov) - fov / 2 degrees, where step is the
sweep over the rays. A laser's elevation is from
`LidarDescription.laser_angles`. The measurement keeps the next start in
radians, as CARLA's header does.

- The semantic LiDAR keeps every hit: the point in the sensor's frame,
  the cosine between the surface normal and the way back to the sensor,
  the actor id (zero for a map surface) and the semantic tag.
- The ray-cast LiDAR draws a general drop-off for each ray before the
  cast. After it, each hit, channel by channel, gets the intensity
  exp(-a d), the noise along its own direction, and the intensity
  drop-off. Its draws come from a `SensorRandom` in CARLA's order.
- The HSS LiDAR does not turn. Each laser fires one ray for each step of
  its horizontal resolution across the field of view, centered on
  forward, and applies the ray-cast LiDAR's drop-off and noise.

A tick with no points to fire gives no measurement. CARLA sends the last
measurement again in that case.

**Reuse.** The description, its defaults and the laser angles are
`extensions.carla.lidar.LidarDescription`. A detection is
`extensions.carla.pointcloud.SemanticLidarDetection` or
`LidarDetection`, which also write CARLA's PLY files.
"""

from extensions.carla.blueprint import ActorAttributeValue
from extensions.carla.lidar import LidarDescription
from extensions.carla.pointcloud import (
    LidarDetection,
    SemanticLidarDetection,
)
from extensions.carla.sensor_attributes import (
    attribute_float,
    attribute_int,
)
from extensions.carla.sensor_noise import SensorRandom
from extensions.carla.sensor_rays import (
    RayScene,
    SensorHit,
)
from extensions.carla.transform import CarlaTransform
from math.vector3 import Vector3
from std.ffi import external_call
from std.math import (
    cos,
    sin,
    trunc,
)
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

# CARLA's `Math::ToDegrees` and `ToRadians` factors, worked in `Float32`.
comptime _TO_DEGREES = Float32(180.0) / Float32(3.14159265358979323846)
comptime _TO_RADIANS = Float32(3.14159265358979323846) / Float32(180.0)
comptime _FLOAT_EPSILON = Float32(1.1920928955078125e-07)
# The HSS LiDAR's smallest horizontal step, in degrees.
comptime _MIN_HSS_RESOLUTION = Float32(0.01)


def _expf(value: Float32) -> Float32:
    return external_call["expf", Float32](value)


def _roundf(value: Float32) -> Float32:
    return external_call["roundf", Float32](value)


def round_half_from_zero(value: Float32) -> Int:
    """Round to the nearest integer, halves away from zero.

    Args:
        value: The number.

    Returns:
        The integer.
    """
    if value < 0:
        return -Int(trunc(-value + 0.5))
    return Int(trunc(value + 0.5))


def _fmod(a: Float32, b: Float32) -> Float32:
    return external_call["fmodf", Float32](a, b)


def lidar_description_from(
    attributes: List[ActorAttributeValue],
) raises -> LidarDescription:
    """Read a LiDAR's settings from its attributes, `SetLidar`.

    Args:
        attributes: The actor's attributes.

    Returns:
        The description. A missing attribute keeps the default of CARLA's
        LiDAR description; a missing range is 10 m.

    Raises:
        Error: Never for these inputs; the number reader's error is passed
            on.
    """
    var d = LidarDescription()
    d.channels = attribute_int(attributes, "channels", d.channels)
    d.range = Length(attribute_float(attributes, "range", 10.0), METER)
    d.points_per_second = attribute_int(
        attributes, "points_per_second", d.points_per_second
    )
    d.rotation_frequency = Frequency(
        attribute_float(
            attributes, "rotation_frequency", d.rotation_frequency.value
        ),
        PER_SECOND,
    )
    d.upper_fov = Angle(
        attribute_float(attributes, "upper_fov", d.upper_fov.to(DEGREE)),
        DEGREE,
    )
    d.lower_fov = Angle(
        attribute_float(attributes, "lower_fov", d.lower_fov.to(DEGREE)),
        DEGREE,
    )
    d.horizontal_fov = Angle(
        attribute_float(
            attributes, "horizontal_fov", d.horizontal_fov.to(DEGREE)
        ),
        DEGREE,
    )
    d.atmosphere_attenuation = InverseLength(
        attribute_float(
            attributes,
            "atmosphere_attenuation_rate",
            d.atmosphere_attenuation.value,
        ),
        PER_METER,
    )
    d.dropoff_general_rate = attribute_float(
        attributes, "dropoff_general_rate", d.dropoff_general_rate
    )
    d.dropoff_intensity_limit = attribute_float(
        attributes, "dropoff_intensity_limit", d.dropoff_intensity_limit
    )
    d.dropoff_zero_intensity = attribute_float(
        attributes, "dropoff_zero_intensity", d.dropoff_zero_intensity
    )
    d.noise_stddev = Length(
        attribute_float(attributes, "noise_stddev", d.noise_stddev.value),
        METER,
    )
    return d


def hss_resolution_from(
    attributes: List[ActorAttributeValue],
) raises -> Angle:
    """Read the HSS LiDAR's horizontal resolution.

    Args:
        attributes: The actor's attributes.

    Returns:
        The `horizontal_resolution` attribute, 0.1 degrees without it.

    Raises:
        Error: Never for these inputs; the number reader's error is passed
            on.
    """
    return Angle(
        attribute_float(attributes, "horizontal_resolution", 0.1), DEGREE
    )


struct SemanticLidarMeasurement(Copyable, Movable):
    """One tick of a semantic LiDAR, CARLA's `SemanticLidarData`."""

    # Where the next tick starts, in radians, as CARLA's header keeps it.
    var horizontal_angle: Angle
    var channel_count: Int
    var points_per_channel: List[Int]
    # Channel by channel.
    var detections: List[SemanticLidarDetection]

    def __init__(out self, channel_count: Int, horizontal_angle: Angle):
        """Create an empty measurement.

        Args:
            channel_count: The lasers.
            horizontal_angle: Where the next tick starts.
        """
        self.horizontal_angle = horizontal_angle
        self.channel_count = channel_count
        self.points_per_channel = List[Int](length=channel_count, fill=0)
        self.detections = List[SemanticLidarDetection]()


struct LidarMeasurement(Copyable, Movable):
    """One tick of a ray-cast LiDAR, CARLA's `LidarData`."""

    # Where the next tick starts, in radians.
    var horizontal_angle: Angle
    var channel_count: Int
    var points_per_channel: List[Int]
    # Channel by channel.
    var detections: List[LidarDetection]

    def __init__(out self, channel_count: Int, horizontal_angle: Angle):
        """Create an empty measurement.

        Args:
            channel_count: The lasers.
            horizontal_angle: Where the next tick starts.
        """
        self.horizontal_angle = horizontal_angle
        self.channel_count = channel_count
        self.points_per_channel = List[Int](length=channel_count, fill=0)
        self.detections = List[LidarDetection]()


def _laser(elevation: Float32, azimuth: Float32) -> Vector3:
    # A laser's rotator: pitch up from the horizon, yaw toward right.
    var e = elevation * _TO_RADIANS
    var a = azimuth * _TO_RADIANS
    return Vector3(cos(e) * cos(a), cos(e) * sin(a), sin(e))


def _cast_channels[
    T: RayScene
](
    mut scene: T,
    sensor: CarlaTransform,
    description: LidarDescription,
    azimuths: List[Float32],
    keep: List[Bool],
) raises -> List[List[SensorHit]]:
    """Cast every kept ray, laser by laser, `ShootLaser`."""
    var angles = description.laser_angles()
    var per_laser = len(azimuths)
    var out = List[List[SensorHit]]()
    # The callers check that there is a channel and a ray a laser.
    for channel in range(description.channels):  # pragma: no branch
        var hits = List[SensorHit]()
        var elevation = angles[channel].to(DEGREE)
        for i in range(per_laser):  # pragma: no branch
            if not keep[channel * per_laser + i]:
                continue
            var direction = sensor.rotation.rotate_vector(
                _laser(elevation, azimuths[i])
            )
            var hit = scene.cast_ray(
                sensor.location, direction, description.range
            )
            if hit.hit:
                hits.append(hit)
        out.append(hits^)
    return out^


def _sweep(
    description: LidarDescription,
    tick: Duration,
    start_angle: Angle,
    per_laser: Int,
) -> List[Float32]:
    var fov = description.horizontal_fov.to(DEGREE)
    var current = start_angle.to(RADIAN) * _TO_DEGREES
    var of_tick = description.rotation_frequency.value * fov * tick.to(SECOND)
    var step = of_tick / Float32(per_laser)
    var out = List[Float32]()
    # The caller checks that a laser has a ray.
    for i in range(per_laser):  # pragma: no branch
        out.append(_fmod(current + step * Float32(i), fov) - fov / 2)
    return out^


def _next_angle(
    description: LidarDescription, tick: Duration, start_angle: Angle
) -> Angle:
    var fov = description.horizontal_fov.to(DEGREE)
    var current = start_angle.to(RADIAN) * _TO_DEGREES
    var of_tick = description.rotation_frequency.value * fov * tick.to(SECOND)
    return Angle(_fmod(current + of_tick, fov) * _TO_RADIANS, RADIAN)


def _per_laser(description: LidarDescription, tick: Duration) -> Int:
    return round_half_from_zero(
        Float32(description.points_per_second)
        * tick.to(SECOND)
        / Float32(description.channels)
    )


def semantic_detection(
    sensor: CarlaTransform, hit: SensorHit
) -> SemanticLidarDetection:
    """Turn a hit into a detection, `ComputeRawDetection`.

    Args:
        sensor: Where the LiDAR is.
        hit: A hit of one of its rays.

    Returns:
        The point in the sensor's frame, the cosine between the normal and
        the way back to the sensor, the actor id and the tag.
    """
    var back = sensor.location - hit.point
    var length = back.length()
    var cos_inc = Float32(0)
    if length > 0:
        cos_inc = (back / length).dot(hit.normal)
    return SemanticLidarDetection(
        sensor.inverse_transform_point(hit.point),
        cos_inc,
        UInt32(hit.actor.value),
        UInt32(hit.tag.value),
    )


def _check(description: LidarDescription, tick: Duration) raises:
    description.validate()
    if not (tick.value > 0.0):
        raise Error("A LiDAR tick must be positive")


def scan_semantic_lidar[
    T: RayScene
](
    mut scene: T,
    sensor: CarlaTransform,
    description: LidarDescription,
    tick: Duration,
    start_angle: Angle,
) raises -> Optional[SemanticLidarMeasurement]:
    """Cast one tick of a semantic LiDAR, `RayCastSemanticLidar`.

    Args:
        scene: What the rays meet.
        sensor: Where the LiDAR is, in CARLA's world frame.
        description: Its settings.
        tick: The time since its last measurement.
        start_angle: Where this tick starts: the last measurement's
            `horizontal_angle`, or zero.

    Returns:
        The measurement, or None when a laser has no ray to fire.

    Raises:
        Error: If the description is not valid, the tick is not positive,
            or the scene cannot be tested.
    """
    _check(description, tick)
    var per_laser = _per_laser(description, tick)
    if per_laser <= 0:
        return None
    var keep = List[Bool](length=description.channels * per_laser, fill=True)
    var hits = _cast_channels(
        scene,
        sensor,
        description,
        _sweep(description, tick, start_angle, per_laser),
        keep,
    )
    var out = SemanticLidarMeasurement(
        description.channels, _next_angle(description, tick, start_angle)
    )
    # The description is checked: it has a channel.
    for channel in range(description.channels):  # pragma: no branch
        out.points_per_channel[channel] = len(hits[channel])
        for h in hits[channel]:
            out.detections.append(semantic_detection(sensor, h))
    return out^


def _unit(v: Vector3) -> Vector3:
    # `Vector3D::MakeUnitVector`: times the reciprocal of the length.
    var k = Float32(1.0) / v.length()
    return Vector3(v.x * k, v.y * k, v.z * k)


def _postprocess(
    sensor: CarlaTransform,
    description: LidarDescription,
    hits: List[List[SensorHit]],
    alpha: Float32,
    beta: Float32,
    horizontal_angle: Angle,
    mut rng: SensorRandom,
) -> LidarMeasurement:
    """`ComputeAndSaveDetections` of the ray-cast LiDAR."""
    var out = LidarMeasurement(description.channels, horizontal_angle)
    var noise = description.noise_stddev.value
    # The callers check that there is a channel.
    for channel in range(description.channels):  # pragma: no branch
        var kept = 0
        for h in hits[channel]:
            var point = sensor.inverse_transform_point(h.point)
            var intensity = _expf(
                -description.atmosphere_attenuation.value * point.length()
            )
            if noise > _FLOAT_EPSILON:
                point = point + _unit(point) * rng.normal(0, noise)
            if not (intensity > description.dropoff_intensity_limit):
                if not (rng.uniform() < alpha * intensity + beta):
                    continue
            out.detections.append(LidarDetection(point, intensity))
            kept += 1
        out.points_per_channel[channel] = kept
    return out^


def _dropoff_mask(
    description: LidarDescription, count: Int, mut rng: SensorRandom
) -> List[Bool]:
    """`PreprocessRays`: the general drop-off, one draw a ray."""
    var active = description.dropoff_general_rate > _FLOAT_EPSILON
    var keep = List[Bool]()
    # The callers check that there is a channel and a ray a laser.
    for _ in range(count):  # pragma: no branch
        keep.append(
            not (active and rng.uniform() < description.dropoff_general_rate)
        )
    return keep^


def scan_ray_cast_lidar[
    T: RayScene
](
    mut scene: T,
    sensor: CarlaTransform,
    description: LidarDescription,
    tick: Duration,
    start_angle: Angle,
    mut rng: SensorRandom,
) raises -> Optional[LidarMeasurement]:
    """Cast one tick of a ray-cast LiDAR, `RayCastLidar`.

    Args:
        scene: What the rays meet.
        sensor: Where the LiDAR is, in CARLA's world frame.
        description: Its settings.
        tick: The time since its last measurement.
        start_angle: Where this tick starts.
        rng: The sensor's engine, seeded with its `noise_seed`.

    Returns:
        The kept detections and their intensities, or None when a laser
        has no ray to fire.

    Raises:
        Error: If the description is not valid, the tick is not positive,
            or the scene cannot be tested.
    """
    _check(description, tick)
    var per_laser = _per_laser(description, tick)
    if per_laser <= 0:
        return None
    var keep = _dropoff_mask(description, description.channels * per_laser, rng)
    var hits = _cast_channels(
        scene,
        sensor,
        description,
        _sweep(description, tick, start_angle, per_laser),
        keep,
    )
    var beta = 1.0 - description.dropoff_zero_intensity
    var alpha = (
        description.dropoff_zero_intensity / description.dropoff_intensity_limit
    )
    return _postprocess(
        sensor,
        description,
        hits,
        alpha,
        beta,
        _next_angle(description, tick, start_angle),
        rng,
    )


def hss_points_per_laser(
    description: LidarDescription, resolution: Angle
) -> Int:
    """Return how many rays one HSS laser fires, `AHSSLidar::SimulateLidar`.

    Args:
        description: The LiDAR's settings.
        resolution: The horizontal step.

    Returns:
        The field of view over the step, rounded half away from zero. The
        step is snapped to 0.01 degrees and is 0.01 at least; a negative
        field of view counts as zero.
    """
    var step = max(
        _roundf(resolution.to(DEGREE) / _MIN_HSS_RESOLUTION)
        * _MIN_HSS_RESOLUTION,
        _MIN_HSS_RESOLUTION,
    )
    var fov = max(description.horizontal_fov.to(DEGREE), 0)
    return round_half_from_zero(fov / step)


def scan_hss_lidar[
    T: RayScene
](
    mut scene: T,
    sensor: CarlaTransform,
    description: LidarDescription,
    resolution: Angle,
    mut rng: SensorRandom,
) raises -> Optional[LidarMeasurement]:
    """Cast one tick of the fixed-sweep HSS LiDAR, `AHSSLidar`.

    Args:
        scene: What the rays meet.
        sensor: Where the LiDAR is, in CARLA's world frame.
        description: Its settings. Only the channels, the range, the
            fields of view, the attenuation, the drop-off and the noise
            count.
        resolution: The horizontal step.
        rng: The sensor's engine, seeded with its `noise_seed`.

    Returns:
        The kept detections, or None when the field of view holds no
        step. The horizontal angle stays zero: the sensor does not turn.

    Raises:
        Error: If there are no channels, the range is not positive, or the
            scene cannot be tested.
    """
    if description.channels < 1:
        raise Error("A LiDAR needs at least one channel")
    if not (description.range.value > 0.0):
        raise Error("A LiDAR needs a positive range")
    var per_laser = hss_points_per_laser(description, resolution)
    if per_laser == 0:
        return None
    var step = max(
        _roundf(resolution.to(DEGREE) / _MIN_HSS_RESOLUTION)
        * _MIN_HSS_RESOLUTION,
        _MIN_HSS_RESOLUTION,
    )
    var fov = max(description.horizontal_fov.to(DEGREE), 0)
    var azimuths = List[Float32]()
    # `per_laser` is not zero, checked above.
    for i in range(per_laser):  # pragma: no branch
        azimuths.append(-fov / 2 + Float32(i) * step)
    var keep = _dropoff_mask(description, description.channels * per_laser, rng)
    var hits = _cast_channels(scene, sensor, description, azimuths, keep)
    var beta = 1.0 - description.dropoff_zero_intensity
    var alpha = Float32(0)
    if description.dropoff_intensity_limit > _FLOAT_EPSILON:
        alpha = (
            description.dropoff_zero_intensity
            / description.dropoff_intensity_limit
        )
    return _postprocess(
        sensor, description, hits, alpha, beta, Angle(0, RADIAN), rng
    )
