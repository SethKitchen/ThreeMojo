# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""CARLA's GNSS receiver, `sensor.other.gnss`.

The source is CARLA's simulator plugin, `Carla/Sensor/GnssSensor.cpp`.
The receiver projects its location to a latitude, a longitude and an
altitude with the map's projection, `GeoProjection.
transform_to_geo_location`. Each of the three then gets its bias and a
normal noise with its own deviation, drawn in the order latitude,
longitude, altitude. The biases and deviations are in degrees for the
latitude and the longitude, and in meters for the altitude.
"""

from extensions.carla.blueprint import ActorAttributeValue
from extensions.carla.geo import GeoLocation, GeoProjection
from extensions.carla.sensor_attributes import (
    attribute_float,
    attribute_int,
    validate_sensor_float,
    validate_sensor_nonnegative,
)
from extensions.carla.sensor_noise import SensorRandom
from math.vector3 import Vector3


struct GnssDescription(ImplicitlyCopyable):
    """A GNSS receiver's settings, `SetGnss`: all zero by default."""

    var noise_seed: Int
    # In degrees.
    var latitude_stddev: Float32
    var latitude_bias: Float32
    var longitude_stddev: Float32
    var longitude_bias: Float32
    # In meters.
    var altitude_stddev: Float32
    var altitude_bias: Float32

    def __init__(out self):
        """Create the settings of CARLA's `sensor.other.gnss`: no noise."""
        self.noise_seed = 0
        self.latitude_stddev = 0
        self.latitude_bias = 0
        self.longitude_stddev = 0
        self.longitude_bias = 0
        self.altitude_stddev = 0
        self.altitude_bias = 0

    def validate(self) raises:
        """Reject nonfinite physical settings and invalid domains.

        Raises:
            Error: If a physical setting is nonfinite or outside its domain.
        """
        validate_sensor_nonnegative(self.latitude_stddev, "latitude_stddev")
        validate_sensor_float(self.latitude_bias, "latitude_bias")
        validate_sensor_nonnegative(self.longitude_stddev, "longitude_stddev")
        validate_sensor_float(self.longitude_bias, "longitude_bias")
        validate_sensor_nonnegative(self.altitude_stddev, "altitude_stddev")
        validate_sensor_float(self.altitude_bias, "altitude_bias")

    @staticmethod
    def from_attributes(
        attributes: List[ActorAttributeValue],
    ) raises -> GnssDescription:
        """Read the settings from an actor's attributes, `SetGnss`.

        Args:
            attributes: The actor's attributes.

        Returns:
            The settings.

        Raises:
            Error: If a physical setting is nonfinite or outside its domain.
        """
        var d = GnssDescription()
        d.noise_seed = attribute_int(attributes, "noise_seed", 0)
        d.latitude_stddev = attribute_float(attributes, "noise_lat_stddev", 0)
        d.longitude_stddev = attribute_float(attributes, "noise_lon_stddev", 0)
        d.altitude_stddev = attribute_float(attributes, "noise_alt_stddev", 0)
        d.latitude_bias = attribute_float(attributes, "noise_lat_bias", 0)
        d.longitude_bias = attribute_float(attributes, "noise_lon_bias", 0)
        d.altitude_bias = attribute_float(attributes, "noise_alt_bias", 0)
        d.validate()
        return d


struct Gnss(Copyable, Movable):
    """A GNSS receiver's engine and settings."""

    var description: GnssDescription
    var rng: SensorRandom

    def __init__(out self, description: GnssDescription) raises:
        """Create a receiver.

        Args:
            description: Its settings. Its seed seeds the engine.

        Raises:
            Error: If a physical setting is nonfinite or outside its domain.
        """
        description.validate()
        self.description = description
        self.rng = SensorRandom(description.noise_seed)

    def measure(
        mut self, location: Vector3, projection: GeoProjection
    ) raises -> GeoLocation:
        """Read the receiver, `PostPhysTick`.

        Args:
            location: Where it is, in meters in CARLA's frame.
            projection: The map's projection.

        Returns:
            The geolocation plus the biases and the noise.

        Raises:
            Error: If the projection is not valid.
        """
        var at = projection.transform_to_geo_location(location)
        var d = self.description
        var lat_error = self.rng.normal(0, d.latitude_stddev)
        var lon_error = self.rng.normal(0, d.longitude_stddev)
        var alt_error = self.rng.normal(0, d.altitude_stddev)
        return GeoLocation(
            at.latitude_degrees + Float64(d.latitude_bias) + Float64(lat_error),
            at.longitude_degrees
            + Float64(d.longitude_bias)
            + Float64(lon_error),
            at.altitude_meters + Float64(d.altitude_bias) + Float64(alt_error),
        )
