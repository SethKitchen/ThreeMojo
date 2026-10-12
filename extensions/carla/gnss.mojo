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
from units.si import Angle, Length, DEGREE, METER


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

    def __init__(
        out self,
        noise_seed: Int,
        latitude_stddev: Angle,
        latitude_bias: Angle,
        longitude_stddev: Angle,
        longitude_bias: Angle,
        altitude_stddev: Length,
        altitude_bias: Length,
    ) raises:
        """Create typed noise settings with CARLA's Float32 storage.

        Args:
            noise_seed: The random engine's seed.
            latitude_stddev: The nonnegative latitude noise deviation.
            latitude_bias: The signed latitude bias.
            longitude_stddev: The nonnegative longitude noise deviation.
            longitude_bias: The signed longitude bias.
            altitude_stddev: The nonnegative altitude noise deviation.
            altitude_bias: The signed altitude bias.

        Returns:
            The initialized receiver settings.

        Raises:
            Error: If a converted value is nonfinite or a deviation is negative.
        """
        self.noise_seed = noise_seed
        self.latitude_stddev = latitude_stddev.to(DEGREE)
        self.latitude_bias = latitude_bias.to(DEGREE)
        self.longitude_stddev = longitude_stddev.to(DEGREE)
        self.longitude_bias = longitude_bias.to(DEGREE)
        self.altitude_stddev = altitude_stddev.to(METER)
        self.altitude_bias = altitude_bias.to(METER)
        self.validate()

    def latitude_stddev_angle(self) raises -> Angle:
        """Return the checked latitude stddev as a quantity.

        Args:
            self: The raw CARLA settings.

        Returns:
            The latitude stddev with its unit.

        Raises:
            Error: If the raw field is nonfinite or negative.
        """
        validate_sensor_nonnegative(self.latitude_stddev, "latitude_stddev")
        return Angle(self.latitude_stddev, DEGREE)

    def latitude_bias_angle(self) raises -> Angle:
        """Return the checked latitude bias as a quantity.

        Args:
            self: The raw CARLA settings.

        Returns:
            The latitude bias with its unit.

        Raises:
            Error: If the raw field is nonfinite.
        """
        validate_sensor_float(self.latitude_bias, "latitude_bias")
        return Angle(self.latitude_bias, DEGREE)

    def set_latitude_noise(mut self, stddev: Angle, bias: Angle) raises:
        """Set the latitude noise after checking both quantities.

        Args:
            stddev: The nonnegative standard deviation.
            bias: The signed bias.

        Returns:
            Nothing; both raw CARLA fields are updated together.

        Raises:
            Error: If a converted value is nonfinite or the deviation is negative.
        """
        var deviation = stddev.to(DEGREE)
        var offset = bias.to(DEGREE)
        validate_sensor_nonnegative(deviation, "latitude_stddev")
        validate_sensor_float(offset, "latitude_bias")
        self.latitude_stddev = deviation
        self.latitude_bias = offset

    def longitude_stddev_angle(self) raises -> Angle:
        """Return the checked longitude stddev as a quantity.

        Args:
            self: The raw CARLA settings.

        Returns:
            The longitude stddev with its unit.

        Raises:
            Error: If the raw field is nonfinite or negative.
        """
        validate_sensor_nonnegative(self.longitude_stddev, "longitude_stddev")
        return Angle(self.longitude_stddev, DEGREE)

    def longitude_bias_angle(self) raises -> Angle:
        """Return the checked longitude bias as a quantity.

        Args:
            self: The raw CARLA settings.

        Returns:
            The longitude bias with its unit.

        Raises:
            Error: If the raw field is nonfinite.
        """
        validate_sensor_float(self.longitude_bias, "longitude_bias")
        return Angle(self.longitude_bias, DEGREE)

    def set_longitude_noise(mut self, stddev: Angle, bias: Angle) raises:
        """Set the longitude noise after checking both quantities.

        Args:
            stddev: The nonnegative standard deviation.
            bias: The signed bias.

        Returns:
            Nothing; both raw CARLA fields are updated together.

        Raises:
            Error: If a converted value is nonfinite or the deviation is negative.
        """
        var deviation = stddev.to(DEGREE)
        var offset = bias.to(DEGREE)
        validate_sensor_nonnegative(deviation, "longitude_stddev")
        validate_sensor_float(offset, "longitude_bias")
        self.longitude_stddev = deviation
        self.longitude_bias = offset

    def altitude_stddev_length(self) raises -> Length:
        """Return the checked altitude stddev as a quantity.

        Args:
            self: The raw CARLA settings.

        Returns:
            The altitude stddev with its unit.

        Raises:
            Error: If the raw field is nonfinite or negative.
        """
        validate_sensor_nonnegative(self.altitude_stddev, "altitude_stddev")
        return Length(self.altitude_stddev, METER)

    def altitude_bias_length(self) raises -> Length:
        """Return the checked altitude bias as a quantity.

        Args:
            self: The raw CARLA settings.

        Returns:
            The altitude bias with its unit.

        Raises:
            Error: If the raw field is nonfinite.
        """
        validate_sensor_float(self.altitude_bias, "altitude_bias")
        return Length(self.altitude_bias, METER)

    def set_altitude_noise(mut self, stddev: Length, bias: Length) raises:
        """Set the altitude noise after checking both quantities.

        Args:
            stddev: The nonnegative standard deviation.
            bias: The signed bias.

        Returns:
            Nothing; both raw CARLA fields are updated together.

        Raises:
            Error: If a converted value is nonfinite or the deviation is negative.
        """
        var deviation = stddev.to(METER)
        var offset = bias.to(METER)
        validate_sensor_nonnegative(deviation, "altitude_stddev")
        validate_sensor_float(offset, "altitude_bias")
        self.altitude_stddev = deviation
        self.altitude_bias = offset

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
        return GeoLocation._from_raw(
            at.latitude_degrees + Float64(d.latitude_bias) + Float64(lat_error),
            at.longitude_degrees
            + Float64(d.longitude_bias)
            + Float64(lon_error),
            at.altitude_meters + Float64(d.altitude_bias) + Float64(alt_error),
        )
