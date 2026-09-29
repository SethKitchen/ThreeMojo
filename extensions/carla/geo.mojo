# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""CARLA's geographic reference: `GeoLocation`, `GeoProjection` and the
OpenDRIVE `geoReference` parser.

The sources are `LibCarla/source/carla/geom/GeoLocation.h`,
`GeoProjection.h`, `GeoProjection.cpp`, `GeoProjectionsParams.h` and
`opendrive/parser/GeoReferenceParser.cpp`. A map's projection turns a
CARLA location into a latitude, a longitude and an altitude, which is
what the GNSS sensor reports and what `Map::TransformToGeolocation`
returns. CARLA supports four projections: transverse Mercator, universal
transverse Mercator (UTM), web Mercator and Lambert conformal conic with
two standard parallels. The formulas are Snyder's, to the sixth order, as
CARLA writes them.

**Why the numbers are `Float64`.** CARLA keeps a latitude, a longitude,
an altitude and the ellipsoid's axis in `double`. A `units.si.Angle`
holds a `Float32`, which keeps a latitude to about a meter only. So the
degrees and the meters of this module are `Float64`, and the field and
argument names say the unit. `GeoLocation.latitude_angle` and
`longitude_angle` give `Angle` values for code that does not need the
precision. A location in the CARLA frame is a `Vector3` in meters, as
CARLA's `Location` is a `float` vector.

**Numbers.** `std.math` works `log`, `exp` and `pow` out through other
functions, and is off by up to 1e-11. At the size of the Earth that is
tens of micrometers. So this module calls the C library's `log`, `exp`
and `pow`, as CARLA does.

**Differences from CARLA.**

- A number in a PROJ string is read as `std::stod` reads it, except a
  hexadecimal float, which reads as the zero before the `x`.
- A UTM zone must be from 1 to 60, and a bad number raises. CARLA takes
  any zone. CARLA logs a warning for a missing parameter, and this port
  logs nothing.
"""

from loaders.js_number import js_pow
from loaders.xml import NO_ELEMENT, XmlDocument
from math.vector3 import Vector3
from std.collections import Dict, Optional
from std.ffi import external_call
from std.math import (
    atan,
    atan2,
    cos,
    hypot,
    inf,
    isinf,
    nan,
    pi,
    sin,
    sqrt,
    tan,
)
from units.si import DEGREE, Angle


def _log(value: Float64) -> Float64:
    return external_call["log", Float64](value)


def _exp(value: Float64) -> Float64:
    return external_call["exp", Float64](value)


def _radians(degrees: Float64) -> Float64:
    return degrees * pi / 180.0


def _degrees(radians: Float64) -> Float64:
    return radians * 180.0 / pi


# --- GeoLocation ---------------------------------------------------------------


@fieldwise_init
struct GeoLocation(Equatable, ImplicitlyCopyable, Writable):
    """A latitude, a longitude and an altitude, CARLA's `GeoLocation`."""

    # North of the equator, in degrees.
    var latitude_degrees: Float64
    # East of the prime meridian, in degrees.
    var longitude_degrees: Float64
    # Above the reference, in meters.
    var altitude_meters: Float64

    def __init__(out self):
        """Create CARLA's default: zero, zero and zero."""
        self.latitude_degrees = 0.0
        self.longitude_degrees = 0.0
        self.altitude_meters = 0.0

    def latitude_angle(self) -> Angle:
        """Return the latitude as an `Angle`.

        Returns:
            The latitude, rounded to a `Float32`.
        """
        return Angle(Float32(self.latitude_degrees), DEGREE)

    def longitude_angle(self) -> Angle:
        """Return the longitude as an `Angle`.

        Returns:
            The longitude, rounded to a `Float32`.
        """
        return Angle(Float32(self.longitude_degrees), DEGREE)

    def __eq__(self, other: Self) -> Bool:
        """Return True if the three numbers are equal.

        Args:
            other: The other location.

        Returns:
            Whether they are equal.
        """
        return (
            self.latitude_degrees == other.latitude_degrees
            and self.longitude_degrees == other.longitude_degrees
            and self.altitude_meters == other.altitude_meters
        )

    def write_to(self, mut writer: Some[Writer]):
        """Write the location as CARLA's Python API prints it.

        Args:
            writer: The destination.
        """
        writer.write(
            "GeoLocation(latitude=",
            self.latitude_degrees,
            ", longitude=",
            self.longitude_degrees,
            ", altitude=",
            self.altitude_meters,
            ")",
        )


# --- Ellipsoid -------------------------------------------------------------------


@fieldwise_init
struct Ellipsoid(Equatable, ImplicitlyCopyable):
    """An ellipsoid of revolution, CARLA's `geom::Ellipsoid`."""

    # The semi-major axis, in meters.
    var a_meters: Float64
    # The inverse flattening. Infinity is a sphere.
    var f_inv: Float64

    def __init__(out self):
        """Create CARLA's default: a sphere of radius 6378137 meters."""
        self.a_meters = 6378137.0
        self.f_inv = inf[DType.float64]()

    def f(self) -> Float64:
        """Return the flattening.

        Returns:
            One over `f_inv`.
        """
        return 1.0 / self.f_inv

    def b_meters(self) -> Float64:
        """Return the semi-minor axis.

        Returns:
            The value a (1 - f), in meters.
        """
        return self.a_meters * (1.0 - self.f())

    def e2(self) -> Float64:
        """Return the square of the first eccentricity.

        Returns:
            The value f (2 - f).
        """
        return self.f() * (2.0 - self.f())

    def ep2(self) -> Float64:
        """Return the square of the second eccentricity.

        Returns:
            The value e2 / (1 - e2).
        """
        return self.e2() / (1.0 - self.e2())

    def from_b(mut self, b_meters: Float64):
        """Set the flattening from a semi-minor axis, `fromb`.

        Args:
            b_meters: The semi-minor axis, in meters.
        """
        self.f_inv = 1.0 / (1.0 - b_meters / self.a_meters)

    def from_f(mut self, f: Float64):
        """Set the flattening, `fromf`.

        Args:
            f: The flattening.
        """
        self.f_inv = 1.0 / f

    def __eq__(self, other: Self) -> Bool:
        """Return True if the axes and flattenings are equal.

        Args:
            other: The other ellipsoid.

        Returns:
            Whether they are equal.
        """
        return self.a_meters == other.a_meters and self.f_inv == other.f_inv


def named_ellipsoid(name: String) -> Optional[Ellipsoid]:
    """Look up one of CARLA's named ellipsoids, `custom_ellipsoids`.

    Args:
        name: The PROJ name: `wgs84`, `grs80`, `intl`, `bessel`, `clrk66`,
            `airy`, `wgs72`, `wgs66` or `sphere`. Case does not matter.

    Returns:
        The ellipsoid, or nothing for another name.
    """
    var key = name.lower()
    if key == "wgs84":
        return Ellipsoid(6378137.0, 298.257223563)
    if key == "grs80":
        return Ellipsoid(6378137.0, 298.257222101)
    if key == "intl":
        return Ellipsoid(6378388.0, 297.0)
    if key == "bessel":
        return Ellipsoid(6377397.155, 299.1528128)
    if key == "clrk66":
        return Ellipsoid(6378206.4, 294.9786982138)
    if key == "airy":
        return Ellipsoid(6377563.396, 299.3249646)
    if key == "wgs72":
        return Ellipsoid(6378135.0, 298.26)
    if key == "wgs66":
        return Ellipsoid(6378145.0, 298.25)
    if key == "sphere":
        return Ellipsoid(6370997.0, inf[DType.float64]())
    return None


# --- OffsetTransform -----------------------------------------------------------


@fieldwise_init
struct OffsetTransform(Equatable, ImplicitlyCopyable):
    """The OpenDRIVE header `offset`, CARLA's `geom::OffsetTransform`.

    CARLA applies it to a location before it undoes a UTM projection. It
    negates y, adds the offset and turns by minus the heading.
    """

    var offset_x_meters: Float64
    var offset_y_meters: Float64
    var offset_z_meters: Float64
    var offset_cos_h: Float64
    var offset_sin_h: Float64

    def __init__(
        out self,
        x_meters: Float64,
        y_meters: Float64,
        z_meters: Float64,
        heading_radians: Float64,
    ):
        """Create an offset.

        Args:
            x_meters: The x offset, in meters.
            y_meters: The y offset, in meters.
            z_meters: The z offset, in meters.
            heading_radians: The heading, in radians.
        """
        self.offset_x_meters = x_meters
        self.offset_y_meters = y_meters
        self.offset_z_meters = z_meters
        self.offset_cos_h = cos(-heading_radians)
        self.offset_sin_h = sin(-heading_radians)

    def apply(self, location: Vector3) -> Vector3:
        """Apply the offset, `ApplyTransformation`.

        Args:
            location: A CARLA location, in meters.

        Returns:
            The location in the projected frame.
        """
        var tx = Float64(location.x) + self.offset_x_meters
        var ty = -Float64(location.y) + self.offset_y_meters
        var x_rot = (tx * self.offset_cos_h) - (ty * self.offset_sin_h)
        var y_rot = (tx * self.offset_sin_h) + (ty * self.offset_cos_h)
        return Vector3(
            Float32(x_rot),
            Float32(y_rot),
            Float32(Float64(location.z) + self.offset_z_meters),
        )

    def apply_inverse(self, location: Vector3) -> Vector3:
        """Undo `apply`, `ApplyInverseTransformation`.

        Args:
            location: A location in the projected frame, in meters.

        Returns:
            The CARLA location.
        """
        var x = Float64(location.x)
        var y = Float64(location.y)
        var tx = (x * self.offset_cos_h) + (y * self.offset_sin_h)
        var ty = -(x * self.offset_sin_h) + (y * self.offset_cos_h)
        return Vector3(
            Float32(tx - self.offset_x_meters),
            Float32(self.offset_y_meters - ty),
            Float32(Float64(location.z) - self.offset_z_meters),
        )

    def __eq__(self, other: Self) -> Bool:
        """Return True if the five numbers are equal.

        Args:
            other: The other offset.

        Returns:
            Whether they are equal.
        """
        return (
            self.offset_x_meters == other.offset_x_meters
            and self.offset_y_meters == other.offset_y_meters
            and self.offset_z_meters == other.offset_z_meters
            and self.offset_cos_h == other.offset_cos_h
            and self.offset_sin_h == other.offset_sin_h
        )


# --- projection parameters -----------------------------------------------------


@fieldwise_init
struct UtmZone(Equatable, ImplicitlyCopyable, Writable):
    """A UTM zone number, from 1 to 60."""

    var value: Int

    def is_valid(self) -> Bool:
        """Return True if the zone is from 1 to 60."""
        return self.value >= 1 and self.value <= 60

    def central_meridian_degrees(self) -> Float64:
        """Return the zone's central meridian, 6 zone - 183.

        Returns:
            The longitude, in degrees.
        """
        return Float64(6 * self.value - 183)


@fieldwise_init
struct ProjectionType(Equatable, ImplicitlyCopyable, Writable):
    """Which projection a `GeoProjection` uses, CARLA's `ProjectionType`."""

    var value: Int

    def is_valid(self) -> Bool:
        """Return True if this names one of the four projections."""
        return self.value >= 0 and self.value < 4


comptime TRANSVERSE_MERCATOR = ProjectionType(0)
comptime UNIVERSAL_TRANSVERSE_MERCATOR = ProjectionType(1)
comptime WEB_MERCATOR = ProjectionType(2)
comptime LAMBERT_CONFORMAL_CONIC = ProjectionType(3)


@fieldwise_init
struct TransverseMercatorParams(Equatable, ImplicitlyCopyable):
    """A transverse Mercator projection, `TransverseMercatorParams`."""

    var lat_0_degrees: Float64
    var lon_0_degrees: Float64
    # The scale on the central meridian.
    var k: Float64
    var x_0_meters: Float64
    var y_0_meters: Float64
    var ellps: Ellipsoid

    def __init__(out self):
        """Create CARLA's default: origin 0, 0, scale one, a sphere."""
        self = TransverseMercatorParams(0.0, 0.0, 1.0, 0.0, 0.0, Ellipsoid())

    def __eq__(self, other: Self) -> Bool:
        """Return True if every parameter is equal.

        Args:
            other: The other parameters.

        Returns:
            Whether they are equal.
        """
        return (
            self.lat_0_degrees == other.lat_0_degrees
            and self.lon_0_degrees == other.lon_0_degrees
            and self.k == other.k
            and self.x_0_meters == other.x_0_meters
            and self.y_0_meters == other.y_0_meters
            and self.ellps == other.ellps
        )


@fieldwise_init
struct UniversalTransverseMercatorParams(Equatable, ImplicitlyCopyable):
    """A UTM projection, `UniversalTransverseMercatorParams`."""

    var zone: UtmZone
    var north: Bool
    var ellps: Ellipsoid
    var offset: Optional[OffsetTransform]

    def __init__(out self):
        """Create CARLA's default: zone 31 north on a sphere, no offset."""
        self = UniversalTransverseMercatorParams(
            UtmZone(31), True, Ellipsoid(), None
        )

    def __eq__(self, other: Self) -> Bool:
        """Return True if every parameter is equal.

        Args:
            other: The other parameters.

        Returns:
            Whether they are equal. Two missing offsets are equal.
        """
        var same_offset = Bool(self.offset) == Bool(other.offset)
        if same_offset and Bool(self.offset):
            same_offset = self.offset.value() == other.offset.value()
        return (
            self.zone == other.zone
            and self.north == other.north
            and self.ellps == other.ellps
            and same_offset
        )


@fieldwise_init
struct WebMercatorParams(Equatable, ImplicitlyCopyable):
    """A web Mercator projection, `WebMercatorParams`."""

    var ellps: Ellipsoid

    def __init__(out self):
        """Create CARLA's default, on a sphere."""
        self.ellps = Ellipsoid()

    def __eq__(self, other: Self) -> Bool:
        """Return True if the ellipsoids are equal.

        Args:
            other: The other parameters.

        Returns:
            Whether they are equal.
        """
        return self.ellps == other.ellps


@fieldwise_init
struct LambertConformalConicParams(Equatable, ImplicitlyCopyable):
    """A Lambert conformal conic projection with two standard parallels,
    `LambertConformalConicParams`."""

    var lat_0_degrees: Float64
    var lat_1_degrees: Float64
    var lat_2_degrees: Float64
    var lon_0_degrees: Float64
    var x_0_meters: Float64
    var y_0_meters: Float64
    var ellps: Ellipsoid

    def __init__(out self):
        """Create CARLA's default: parallels at -5 and 5, a sphere."""
        self = LambertConformalConicParams(
            0.0, -5.0, 5.0, 0.0, 0.0, 0.0, Ellipsoid()
        )

    def __eq__(self, other: Self) -> Bool:
        """Return True if every parameter is equal.

        Args:
            other: The other parameters.

        Returns:
            Whether they are equal.
        """
        return (
            self.lat_0_degrees == other.lat_0_degrees
            and self.lat_1_degrees == other.lat_1_degrees
            and self.lat_2_degrees == other.lat_2_degrees
            and self.lon_0_degrees == other.lon_0_degrees
            and self.x_0_meters == other.x_0_meters
            and self.y_0_meters == other.y_0_meters
            and self.ellps == other.ellps
        )


# --- the projections -------------------------------------------------------------


def _meridional_arc(e2: Float64, a: Float64, phi: Float64) -> Float64:
    var e4 = e2 * e2
    var e6 = e4 * e2
    return a * (
        (1.0 - e2 / 4.0 - 3.0 * e4 / 64.0 - 5.0 * e6 / 256.0) * phi
        - (3.0 * e2 / 8.0 + 3.0 * e4 / 32.0 + 45.0 * e6 / 1024.0)
        * sin(2.0 * phi)
        + (15.0 * e4 / 256.0 + 45.0 * e6 / 1024.0) * sin(4.0 * phi)
        - (35.0 * e6 / 3072.0) * sin(6.0 * phi)
    )


def _tm_forward(
    lat: Float64,
    dlon: Float64,
    ellps: Ellipsoid,
    k: Float64,
    x_0: Float64,
    y_0: Float64,
    m_0: Float64,
) -> Tuple[Float64, Float64]:
    """Snyder's ellipsoidal transverse Mercator, forward, to the sixth
    order: easting and northing."""
    var a = ellps.a_meters
    var e2 = ellps.e2()
    var ep2 = ellps.ep2()
    var n = a / sqrt(1.0 - e2 * sin(lat) * sin(lat))
    var t = tan(lat) * tan(lat)
    var c = ep2 * cos(lat) * cos(lat)
    var aa = cos(lat) * dlon
    var m = _meridional_arc(e2, a, lat)
    var x = x_0 + k * n * (
        aa
        + (1.0 - t + c) * js_pow(aa, 3) / 6.0
        + (5.0 - 18.0 * t + t * t + 72.0 * c - 58.0 * ep2)
        * js_pow(aa, 5)
        / 120.0
    )
    var y = y_0 + k * (
        (m - m_0)
        + n
        * tan(lat)
        * (
            (aa * aa) / 2.0
            + (5.0 - t + 9.0 * c + 4.0 * c * c) * js_pow(aa, 4) / 24.0
            + (61.0 - 58.0 * t + t * t + 600.0 * c - 330.0 * ep2)
            * js_pow(aa, 6)
            / 720.0
        )
    )
    return (x, y)


def _tm_inverse(
    x: Float64, m: Float64, lon_0: Float64, ellps: Ellipsoid
) -> Tuple[Float64, Float64]:
    """Snyder's ellipsoidal transverse Mercator, inverse, to the sixth
    order: latitude and longitude in radians. `x` is the scaled easting
    from the false origin, `m` the meridional distance."""
    var a = ellps.a_meters
    var e2 = ellps.e2()
    var ep2 = ellps.ep2()
    var e4 = e2 * e2
    var e6 = e4 * e2
    var mu = m / (a * (1.0 - e2 / 4.0 - 3.0 * e4 / 64.0 - 5.0 * e6 / 256.0))
    var e1 = (1.0 - sqrt(1.0 - e2)) / (1.0 + sqrt(1.0 - e2))
    var e1_2 = e1 * e1
    var e1_3 = e1_2 * e1
    var e1_4 = e1_3 * e1
    var phi1 = (
        mu
        + (3.0 * e1 / 2.0 - 27.0 * e1_3 / 32.0) * sin(2.0 * mu)
        + (21.0 * e1_2 / 16.0 - 55.0 * e1_4 / 32.0) * sin(4.0 * mu)
        + (151.0 * e1_3 / 96.0) * sin(6.0 * mu)
        + (1097.0 * e1_4 / 512.0) * sin(8.0 * mu)
    )
    var sin1 = sin(phi1)
    var cos1 = cos(phi1)
    var tan1 = tan(phi1)
    var n = a / sqrt(1.0 - e2 * sin1 * sin1)
    var r = a * (1.0 - e2) / js_pow(1.0 - e2 * sin1 * sin1, 1.5)
    var t = tan1 * tan1
    var c = ep2 * cos1 * cos1
    var d = x / n
    var lat = phi1 - (n * tan1 / r) * (
        (d * d) / 2.0
        - (5.0 + 3.0 * t + 10.0 * c - 4.0 * c * c - 9.0 * ep2)
        * js_pow(d, 4)
        / 24.0
        + (
            61.0
            + 90.0 * t
            + 298.0 * c
            + 45.0 * t * t
            - 252.0 * ep2
            - 3.0 * c * c
        )
        * js_pow(d, 6)
        / 720.0
    )
    var lon = (
        lon_0
        + (
            d
            - (1.0 + 2.0 * t + c) * js_pow(d, 3) / 6.0
            + (
                5.0
                - 2.0 * c
                + 28.0 * t
                + 3.0 * c * c
                + 8.0 * ep2
                + 24.0 * t * t
            )
            * js_pow(d, 5)
            / 120.0
        )
        / cos1
    )
    lon = atan2(sin(lon), cos(lon))
    return (lat, lon)


def geo_location_to_transform_transverse_mercator(
    geolocation: GeoLocation, p: TransverseMercatorParams
) -> Vector3:
    """Project a geolocation, `GeoLocationToTransformTransverseMercator`.

    Args:
        geolocation: The geolocation.
        p: The projection.

    Returns:
        The easting, the northing and the altitude, in meters, as
        `Float32` values.
    """
    var lat = _radians(geolocation.latitude_degrees)
    var lon = _radians(geolocation.longitude_degrees)
    var lat_0 = _radians(p.lat_0_degrees)
    var lon_0 = _radians(p.lon_0_degrees)
    var dlon = atan2(sin(lon - lon_0), cos(lon - lon_0))
    var m_0 = _meridional_arc(p.ellps.e2(), p.ellps.a_meters, lat_0)
    var xy = _tm_forward(
        lat, dlon, p.ellps, p.k, p.x_0_meters, p.y_0_meters, m_0
    )
    return Vector3(
        Float32(xy[0]), Float32(xy[1]), Float32(geolocation.altitude_meters)
    )


def transform_to_geo_location_transverse_mercator(
    location: Vector3, p: TransverseMercatorParams
) -> GeoLocation:
    """Undo a transverse Mercator projection,
    `TransformToGeoLocationTransverseMercator`.

    Args:
        location: The easting, the northing and the altitude, in meters.
        p: The projection.

    Returns:
        The geolocation. The longitude is wrapped to -180 through 180.
    """
    var lat_0 = _radians(p.lat_0_degrees)
    var lon_0 = _radians(p.lon_0_degrees)
    var x = (Float64(location.x) - p.x_0_meters) / p.k
    var y = (Float64(location.y) - p.y_0_meters) / p.k
    var m = _meridional_arc(p.ellps.e2(), p.ellps.a_meters, lat_0) + y
    var ll = _tm_inverse(x, m, lon_0, p.ellps)
    return GeoLocation(_degrees(ll[0]), _degrees(ll[1]), Float64(location.z))


comptime _UTM_K = 0.9996
comptime _UTM_X_0 = 500000.0


def _utm_y_0(north: Bool) -> Float64:
    if north:
        return 0.0
    return 10000000.0


def geo_location_to_transform_universal_transverse_mercator(
    geolocation: GeoLocation, p: UniversalTransverseMercatorParams
) raises -> Vector3:
    """Project a geolocation on UTM,
    `GeoLocationToTransformUniversalTransverseMercator`.

    Args:
        geolocation: The geolocation.
        p: The projection. An offset, if any, is undone after projecting,
            so a round trip gives the geolocation back.

    Returns:
        The location, in meters.

    Raises:
        Error: If the zone is not valid.
    """
    if not p.zone.is_valid():
        raise Error("A UTM zone must be from 1 to 60")
    var lat = _radians(geolocation.latitude_degrees)
    var lon = _radians(geolocation.longitude_degrees)
    var lon_0 = _radians(p.zone.central_meridian_degrees())
    var dlon = atan2(sin(lon - lon_0), cos(lon - lon_0))
    var xy = _tm_forward(
        lat, dlon, p.ellps, _UTM_K, _UTM_X_0, _utm_y_0(p.north), 0.0
    )
    var result = Vector3(
        Float32(xy[0]), Float32(xy[1]), Float32(geolocation.altitude_meters)
    )
    if Bool(p.offset):
        result = p.offset.value().apply_inverse(result)
    return result


def transform_to_geo_location_universal_transverse_mercator(
    location_in: Vector3, p: UniversalTransverseMercatorParams
) raises -> GeoLocation:
    """Undo a UTM projection,
    `TransformToGeoLocationUniversalTransverseMercator`.

    Args:
        location_in: The location, in meters. The offset, if any, is
            applied first.
        p: The projection.

    Returns:
        The geolocation. The altitude is the z after the offset.

    Raises:
        Error: If the zone is not valid.
    """
    if not p.zone.is_valid():
        raise Error("A UTM zone must be from 1 to 60")
    var lon_0 = _radians(p.zone.central_meridian_degrees())
    var location = location_in
    if Bool(p.offset):
        location = p.offset.value().apply(location_in)
    var x = (Float64(location.x) - _UTM_X_0) / _UTM_K
    var y = (Float64(location.y) - _utm_y_0(p.north)) / _UTM_K
    var ll = _tm_inverse(x, y, lon_0, p.ellps)
    return GeoLocation(_degrees(ll[0]), _degrees(ll[1]), Float64(location.z))


def geo_location_to_transform_web_mercator(
    geolocation: GeoLocation, p: WebMercatorParams
) -> Vector3:
    """Project a geolocation on web Mercator,
    `GeoLocationToTransformWebMercator`.

    Args:
        geolocation: The geolocation.
        p: The projection. Only the semi-major axis is used.

    Returns:
        The location, in meters.
    """
    var lat = _radians(geolocation.latitude_degrees)
    var lon = _radians(geolocation.longitude_degrees)
    var x = p.ellps.a_meters * lon
    var y = p.ellps.a_meters * _log(tan(pi / 4.0 + lat / 2.0))
    return Vector3(Float32(x), Float32(y), Float32(geolocation.altitude_meters))


def transform_to_geo_location_web_mercator(
    location: Vector3, p: WebMercatorParams
) -> GeoLocation:
    """Undo a web Mercator projection, `TransformToGeoLocationWebMercator`.

    Args:
        location: The location, in meters.
        p: The projection.

    Returns:
        The geolocation.
    """
    var lon = Float64(location.x) / p.ellps.a_meters
    var lat = 2 * atan(_exp(Float64(location.y) / p.ellps.a_meters)) - pi / 2
    return GeoLocation(_degrees(lat), _degrees(lon), Float64(location.z))


def _lcc_t(phi: Float64, e: Float64) -> Float64:
    return tan(pi / 4 - phi / 2) / js_pow(
        (1.0 - e * sin(phi)) / (1.0 + e * sin(phi)), e / 2
    )


def _lcc_m(phi: Float64, e2: Float64) -> Float64:
    return cos(phi) / sqrt(1.0 - e2 * sin(phi) * sin(phi))


@fieldwise_init
struct _LccCone(ImplicitlyCopyable):
    var n: Float64
    var f: Float64
    var rho0: Float64


def _lcc_cone(p: LambertConformalConicParams) -> _LccCone:
    var a = p.ellps.a_meters
    var e2 = p.ellps.e2()
    var e = sqrt(e2)
    var lat_0 = _radians(p.lat_0_degrees)
    var lat_1 = _radians(p.lat_1_degrees)
    var lat_2 = _radians(p.lat_2_degrees)
    var m1 = _lcc_m(lat_1, e2)
    var m2 = _lcc_m(lat_2, e2)
    var t0 = _lcc_t(lat_0, e)
    var t1 = _lcc_t(lat_1, e)
    var t2 = _lcc_t(lat_2, e)
    var n = (_log(m1) - _log(m2)) / (_log(t1) - _log(t2))
    var f = m1 / (n * js_pow(t1, n))
    return _LccCone(n, f, a * f * js_pow(t0, n))


def geo_location_to_transform_lambert_conformal_conic(
    geolocation: GeoLocation, p: LambertConformalConicParams
) -> Vector3:
    """Project a geolocation on a Lambert conformal conic,
    `GeoLocationToTransformLambertConformalConic`.

    Args:
        geolocation: The geolocation.
        p: The projection.

    Returns:
        The location, in meters.
    """
    var cone = _lcc_cone(p)
    var lat = _radians(geolocation.latitude_degrees)
    var lon = _radians(geolocation.longitude_degrees)
    var lon_0 = _radians(p.lon_0_degrees)
    var t = _lcc_t(lat, sqrt(p.ellps.e2()))
    var rho = p.ellps.a_meters * cone.f * js_pow(t, cone.n)
    var theta = cone.n * atan2(sin(lon - lon_0), cos(lon - lon_0))
    var x = p.x_0_meters + rho * sin(theta)
    var y = p.y_0_meters + cone.rho0 - rho * cos(theta)
    return Vector3(Float32(x), Float32(y), Float32(geolocation.altitude_meters))


def transform_to_geo_location_lambert_conformal_conic(
    location: Vector3, p: LambertConformalConicParams
) -> GeoLocation:
    """Undo a Lambert conformal conic projection,
    `TransformToGeoLocationLambertConformalConic`.

    The latitude is found by fixed-point iteration from the spherical
    guess, at most ten steps, stopping when a step moves less than 1e-12
    radians.

    Args:
        location: The location, in meters.
        p: The projection.

    Returns:
        The geolocation.
    """
    var cone = _lcc_cone(p)
    var a = p.ellps.a_meters
    var e = sqrt(p.ellps.e2())
    var x = Float64(location.x) - p.x_0_meters
    var y = Float64(location.y) - p.y_0_meters
    var sgn = 1.0 if cone.n >= 0.0 else -1.0
    var big_y = cone.rho0 - y
    var rho = sgn * hypot(x, big_y)
    var theta = atan2(sgn * x, sgn * big_y)
    var t = js_pow(rho / (a * cone.f), 1.0 / cone.n)
    var lat = pi * 0.5 - 2.0 * atan(t)
    for _ in range(10):  # pragma: no branch
        var lat_next = pi * 0.5 - 2.0 * atan(
            t * js_pow((1.0 - e * sin(lat)) / (1.0 + e * sin(lat)), 0.5 * e)
        )
        if abs(lat_next - lat) < 1e-12:
            lat = lat_next
            break
        lat = lat_next
    var lon = _radians(p.lon_0_degrees) + theta / cone.n
    lon = atan2(sin(lon), cos(lon))
    return GeoLocation(_degrees(lat), _degrees(lon), Float64(location.z))


# --- GeoProjection -------------------------------------------------------------


struct GeoProjection(Copyable, Movable):
    """A map's projection and its PROJ string, CARLA's `GeoProjection`.

    CARLA holds the parameters in a variant. This struct holds one set of
    parameters for each projection, and `projection_type` says which is
    used.
    """

    var projection_type: ProjectionType
    var transverse_mercator: TransverseMercatorParams
    var universal_transverse_mercator: UniversalTransverseMercatorParams
    var web_mercator: WebMercatorParams
    var lambert_conformal_conic: LambertConformalConicParams
    # The PROJ string the map gave, or empty.
    var proj_string: String

    def __init__(out self):
        """Create CARLA's default: a transverse Mercator with its defaults."""
        self.projection_type = TRANSVERSE_MERCATOR
        self.transverse_mercator = TransverseMercatorParams()
        self.universal_transverse_mercator = UniversalTransverseMercatorParams()
        self.web_mercator = WebMercatorParams()
        self.lambert_conformal_conic = LambertConformalConicParams()
        self.proj_string = String()

    @staticmethod
    def make(p: TransverseMercatorParams) -> GeoProjection:
        """Make a transverse Mercator projection, `GeoProjection::Make`.

        Args:
            p: The parameters.

        Returns:
            The projection.
        """
        var out = GeoProjection()
        out.transverse_mercator = p
        return out^

    @staticmethod
    def make(p: UniversalTransverseMercatorParams) -> GeoProjection:
        """Make a UTM projection, `GeoProjection::Make`.

        Args:
            p: The parameters.

        Returns:
            The projection.
        """
        var out = GeoProjection()
        out.projection_type = UNIVERSAL_TRANSVERSE_MERCATOR
        out.universal_transverse_mercator = p
        return out^

    @staticmethod
    def make(p: WebMercatorParams) -> GeoProjection:
        """Make a web Mercator projection, `GeoProjection::Make`.

        Args:
            p: The parameters.

        Returns:
            The projection.
        """
        var out = GeoProjection()
        out.projection_type = WEB_MERCATOR
        out.web_mercator = p
        return out^

    @staticmethod
    def make(p: LambertConformalConicParams) -> GeoProjection:
        """Make a Lambert conformal conic projection, `GeoProjection::Make`.

        Args:
            p: The parameters.

        Returns:
            The projection.
        """
        var out = GeoProjection()
        out.projection_type = LAMBERT_CONFORMAL_CONIC
        out.lambert_conformal_conic = p
        return out^

    def _check(self) raises:
        if not self.projection_type.is_valid():
            raise Error("A projection type must name one of four projections")

    def geo_location_to_transform(
        self, geolocation: GeoLocation
    ) raises -> Vector3:
        """Project a geolocation to a CARLA location,
        `GeoLocationToTransform`.

        Args:
            geolocation: The geolocation.

        Returns:
            The location, in meters.

        Raises:
            Error: If the projection type or the UTM zone is not valid.
        """
        self._check()
        if self.projection_type == UNIVERSAL_TRANSVERSE_MERCATOR:
            return geo_location_to_transform_universal_transverse_mercator(
                geolocation, self.universal_transverse_mercator
            )
        if self.projection_type == WEB_MERCATOR:
            return geo_location_to_transform_web_mercator(
                geolocation, self.web_mercator
            )
        if self.projection_type == LAMBERT_CONFORMAL_CONIC:
            return geo_location_to_transform_lambert_conformal_conic(
                geolocation, self.lambert_conformal_conic
            )
        return geo_location_to_transform_transverse_mercator(
            geolocation, self.transverse_mercator
        )

    def transform_to_geo_location(
        self, location: Vector3
    ) raises -> GeoLocation:
        """Turn a CARLA location into a geolocation,
        `TransformToGeoLocation`. This is the math of the GNSS sensor and
        of `Map::TransformToGeolocation`.

        Args:
            location: The location, in meters.

        Returns:
            The geolocation.

        Raises:
            Error: If the projection type or the UTM zone is not valid.
        """
        self._check()
        if self.projection_type == UNIVERSAL_TRANSVERSE_MERCATOR:
            return transform_to_geo_location_universal_transverse_mercator(
                location, self.universal_transverse_mercator
            )
        if self.projection_type == WEB_MERCATOR:
            return transform_to_geo_location_web_mercator(
                location, self.web_mercator
            )
        if self.projection_type == LAMBERT_CONFORMAL_CONIC:
            return transform_to_geo_location_lambert_conformal_conic(
                location, self.lambert_conformal_conic
            )
        return transform_to_geo_location_transverse_mercator(
            location, self.transverse_mercator
        )


# --- reading numbers as the C library does -----------------------------------


def _is_c_space(byte: Int) -> Bool:
    return byte == 32 or (byte >= 9 and byte <= 13)


def _is_digit(byte: Int) -> Bool:
    return byte >= 48 and byte <= 57


def _lower_byte(byte: Int) -> Int:
    if byte >= 65 and byte <= 90:
        return byte + 32
    return byte


def _matches_word(bytes: Span[Byte, _], at: Int, word: String) -> Bool:
    var w = word.as_bytes()
    if at + len(w) > len(bytes):
        return False
    for i in range(len(w)):  # pragma: no branch
        if _lower_byte(Int(bytes[at + i])) != Int(w[i]):
            return False
    return True


@fieldwise_init
struct _Number(ImplicitlyCopyable):
    # The value, or NaN when nothing was read.
    var value: Float64
    # Whether a number was read at all.
    var read: Bool
    # Whether a digit other than zero was read, to spot an underflow.
    var nonzero: Bool
    # Whether the text spelled a word, `inf` or `nan`, and not digits.
    var word: Bool


def _strtod(text: String) raises -> _Number:
    """Read the longest number at the start of `text`, as `strtod` does:
    blanks, a sign, then `inf`, `infinity`, `nan` or a decimal number with
    an optional exponent."""
    var bytes = text.as_bytes()
    var i = 0
    while i < len(bytes) and _is_c_space(Int(bytes[i])):
        i += 1
    var negative = False
    if i < len(bytes) and (Int(bytes[i]) == 43 or Int(bytes[i]) == 45):
        negative = Int(bytes[i]) == 45
        i += 1
    var sign = -1.0 if negative else 1.0
    if _matches_word(bytes, i, "inf"):
        return _Number(sign * inf[DType.float64](), True, True, True)
    if _matches_word(bytes, i, "nan"):
        return _Number(nan[DType.float64](), True, True, True)
    var start = i
    var digits = 0
    var nonzero = False
    while i < len(bytes) and _is_digit(Int(bytes[i])):
        nonzero = nonzero or Int(bytes[i]) != 48
        digits += 1
        i += 1
    if i < len(bytes) and Int(bytes[i]) == 46:
        i += 1
        while i < len(bytes) and _is_digit(Int(bytes[i])):
            nonzero = nonzero or Int(bytes[i]) != 48
            digits += 1
            i += 1
    if digits == 0:
        return _Number(nan[DType.float64](), False, False, False)
    var end = i
    if i < len(bytes) and _lower_byte(Int(bytes[i])) == 101:
        var j = i + 1
        if j < len(bytes) and (Int(bytes[j]) == 43 or Int(bytes[j]) == 45):
            j += 1
        if j < len(bytes) and _is_digit(Int(bytes[j])):
            while j < len(bytes) and _is_digit(Int(bytes[j])):
                j += 1
            end = j
    var value = Float64(String(text[byte=start:end]))
    return _Number(sign * value, True, nonzero, False)


def stod(text: String) raises -> Float64:
    """Read a number as C++'s `std::stod` does.

    Args:
        text: The text. Blanks may lead, and anything after the longest
            number is ignored.

    Returns:
        The number.

    Raises:
        Error: If no number starts the text, or it is out of range: too
            large for a `Float64`, or too small to be told from zero.
    """
    var number = _strtod(text)
    if not number.read:
        raise Error("stod: no number in '" + text + "'")
    var magnitude = abs(number.value)
    var overflow = isinf(magnitude) and not number.word
    var underflow = number.nonzero and magnitude < 2.2250738585072014e-308
    if overflow or underflow:
        raise Error("stod: out of range: '" + text + "'")
    return number.value


def xml_as_double(text: String) raises -> Float64:
    """Read an XML attribute as a number, as pugixml's `as_double` does.

    Args:
        text: The attribute's value.

    Returns:
        What `strtod` reads from the start, or zero when it reads nothing.

    Raises:
        Error: If the number text cannot be converted.
    """
    var number = _strtod(text)
    if not number.read:
        return 0.0
    return number.value


def stoll(text: String) raises -> Int:
    """Read a whole number as C++'s `std::stoll` does, in base ten.

    Args:
        text: The text. Blanks may lead, and anything after the digits is
            ignored.

    Returns:
        The number.

    Raises:
        Error: If no digits start the text, or the number does not fit in
            64 bits.
    """
    var bytes = text.as_bytes()
    var i = 0
    while i < len(bytes) and _is_c_space(Int(bytes[i])):
        i += 1
    var negative = False
    if i < len(bytes) and (Int(bytes[i]) == 43 or Int(bytes[i]) == 45):
        negative = Int(bytes[i]) == 45
        i += 1
    var start = i
    # The magnitude, which may reach 2^63 for the smallest Int64.
    var limit = Int128(9223372036854775807) + Int128(1 if negative else 0)
    var value = Int128(0)
    while i < len(bytes) and _is_digit(Int(bytes[i])):
        value = value * 10 + Int128(Int(bytes[i]) - 48)
        if value > limit:
            raise Error("stoll: out of range: '" + text + "'")
        i += 1
    if i == start:
        raise Error("stoll: no number in '" + text + "'")
    if negative:
        value = -value
    return Int(value)


# --- the geoReference parser -----------------------------------------------------


def _key_byte(byte: Int) -> Bool:
    return (
        _is_digit(byte)
        or (byte >= 65 and byte <= 90)
        or (byte >= 97 and byte <= 122)
        or byte == 95
    )


def _closing(bytes: Span[Byte, _], at: Int, quote: Int) -> Int:
    for j in range(at + 1, len(bytes)):
        if Int(bytes[j]) == quote:
            return j
    return -1


def parse_projection_parameters(text: String) -> Dict[String, String]:
    """Read the `+key=value` pairs of a PROJ string,
    `ParseProjectionParameters`.

    CARLA matches the pattern `\\+(\\w+)(?:=("[^"]*"|'[^']*'|[^ \\t\\r\\n+]+))?`
    left to right. This reads the same matches.

    Args:
        text: The PROJ string.

    Returns:
        Each key and its value. A bare flag such as `+south` has an empty
        value. A quoted value keeps its quotes. A later key replaces an
        earlier one.
    """
    var out = Dict[String, String]()
    var bytes = text.as_bytes()
    var i = 0
    while i < len(bytes):
        if (
            Int(bytes[i]) != 43
            or i + 1 >= len(bytes)
            or not _key_byte(Int(bytes[i + 1]))
        ):
            i += 1
            continue
        var key_start = i + 1
        var j = key_start
        while j < len(bytes) and _key_byte(Int(bytes[j])):
            j += 1
        var key = String(text[byte=key_start:j])
        var value = String()
        if j < len(bytes) and Int(bytes[j]) == 61:
            var v = j + 1
            var end = -1
            if v < len(bytes) and (Int(bytes[v]) == 34 or Int(bytes[v]) == 39):
                var close = _closing(bytes, v, Int(bytes[v]))
                if close >= 0:
                    end = close + 1
            if end < 0:
                var k = v
                while k < len(bytes) and not (
                    _is_c_space(Int(bytes[k]))
                    and Int(bytes[k]) != 11
                    and Int(bytes[k]) != 12
                    or Int(bytes[k]) == 43
                ):
                    k += 1
                if k > v:
                    end = k
            if end >= 0:
                value = String(text[byte=v:end])
                j = end
        out[key] = value
        i = j
    return out^


def create_ellipsoid(parameters: Dict[String, String]) raises -> Ellipsoid:
    """Read the ellipsoid of a PROJ string, `CreateEllipsoid`.

    Args:
        parameters: The pairs from `parse_projection_parameters`.

    Returns:
        The named `ellps`, or else the named `datum`, then changed by `a`,
        `b`, `f` and `rf` in that order. WGS 84 when none of them is given
        or names a known ellipsoid.

    Raises:
        Error: If a number cannot be read.
    """
    var ellps = Ellipsoid()
    var initialized = False
    var name = parameters.get("datum", "")
    if "ellps" in parameters:
        name = parameters["ellps"]
    var found = named_ellipsoid(name)
    if Bool(found):
        ellps = found.value()
        initialized = True
    if "a" in parameters:
        ellps.a_meters = stod(parameters["a"])
        initialized = True
    if "b" in parameters:
        ellps.from_b(stod(parameters["b"]))
        initialized = True
    if "f" in parameters:
        ellps.from_f(stod(parameters["f"]))
        initialized = True
    if "rf" in parameters:
        ellps.f_inv = stod(parameters["rf"])
        initialized = True
    if not initialized:
        ellps = named_ellipsoid("wgs84").value()
    return ellps


def create_offset_transform(
    offsets: Dict[String, Float64]
) -> Optional[OffsetTransform]:
    """Read the header `offset`, `CreateOffsetTransform`.

    Args:
        offsets: Each attribute of the `offset` element and its number.

    Returns:
        Nothing when there are no attributes, else the offset from `x`, `y`,
        `z` and `hdg`, each zero when it is missing.
    """
    if len(offsets) == 0:
        return None
    return OffsetTransform(
        offsets.get("x", 0.0),
        offsets.get("y", 0.0),
        offsets.get("z", 0.0),
        offsets.get("hdg", 0.0),
    )


def _read_into(
    mut out: Float64, parameters: Dict[String, String], key: String
) raises:
    if key in parameters:
        out = stod(parameters[key])


def parse_geo_projection_and_reference(
    proj_string: String, offsets: Dict[String, Float64]
) raises -> Tuple[GeoProjection, GeoLocation]:
    """Read a map's projection and geo reference,
    `ParseGeoProjectionAndReference`.

    Args:
        proj_string: The text of the header's `geoReference`.
        offsets: The attributes of the header's `offset`, if any.

    Returns:
        The projection and the geo reference. `tmerc`, `utm`, `merc` and
        `lcc` pick a projection. Without `+proj`, or with another one, the
        default transverse Mercator on the parsed ellipsoid, with no PROJ
        string and a zero reference.

    Raises:
        Error: If a number cannot be read or the UTM zone is not valid.
    """
    var parameters = parse_projection_parameters(proj_string)
    var ellipsoid = create_ellipsoid(parameters)
    var reference = GeoLocation()
    # A missing `+proj` and an unknown one both give the default.
    var proj = parameters.get("proj", "")
    if proj == "tmerc":
        var p = TransverseMercatorParams()
        _read_into(p.lat_0_degrees, parameters, "lat_0")
        _read_into(p.lon_0_degrees, parameters, "lon_0")
        _read_into(p.k, parameters, "k")
        _read_into(p.x_0_meters, parameters, "x_0")
        _read_into(p.y_0_meters, parameters, "y_0")
        p.ellps = ellipsoid
        var projection = GeoProjection.make(p)
        projection.proj_string = proj_string
        reference.latitude_degrees = p.lat_0_degrees
        reference.longitude_degrees = p.lon_0_degrees
        return (projection^, reference)
    if proj == "utm":
        var p = UniversalTransverseMercatorParams()
        if "zone" in parameters:
            p.zone = UtmZone(Int(Int32(stoll(parameters["zone"]))))
            if not p.zone.is_valid():
                raise Error("A UTM zone must be from 1 to 60")
            reference.longitude_degrees = 6.0 * stod(parameters["zone"]) - 183.0
        p.north = "south" not in parameters
        p.ellps = ellipsoid
        p.offset = create_offset_transform(offsets)
        var projection = GeoProjection.make(p)
        projection.proj_string = proj_string
        return (projection^, reference)
    if proj == "merc":
        var projection = GeoProjection.make(WebMercatorParams(ellipsoid))
        projection.proj_string = proj_string
        return (projection^, reference)
    if proj == "lcc":
        var p = LambertConformalConicParams()
        _read_into(p.lon_0_degrees, parameters, "lon_0")
        _read_into(p.lat_0_degrees, parameters, "lat_0")
        _read_into(p.lat_1_degrees, parameters, "lat_1")
        _read_into(p.lat_2_degrees, parameters, "lat_2")
        _read_into(p.x_0_meters, parameters, "x_0")
        _read_into(p.y_0_meters, parameters, "y_0")
        p.ellps = ellipsoid
        var projection = GeoProjection.make(p)
        projection.proj_string = proj_string
        reference.latitude_degrees = p.lat_0_degrees
        reference.longitude_degrees = p.lon_0_degrees
        return (projection^, reference)
    var default = TransverseMercatorParams()
    default.ellps = ellipsoid
    return (GeoProjection.make(default), reference)


def parse_geo_reference(
    document: XmlDocument,
) raises -> Tuple[GeoProjection, GeoLocation]:
    """Read the projection of an OpenDRIVE document,
    `GeoReferenceParser::Parse`.

    Args:
        document: The parsed `.xodr` file.

    Returns:
        What `parse_geo_projection_and_reference` reads from the text of
        `OpenDRIVE/header/geoReference` and the attributes of
        `OpenDRIVE/header/offset`. A missing element reads as empty.

    Raises:
        Error: If a number cannot be read or the UTM zone is not valid.
    """
    var proj_string = String()
    var offsets = Dict[String, Float64]()
    var root = document.root()
    if document.count() > 0 and document.name(root) == "OpenDRIVE":
        var header = document.child(root, "header")
        if header != NO_ELEMENT:
            var reference = document.child(header, "geoReference")
            if reference != NO_ELEMENT:
                proj_string = document.text(reference)
            var offset = document.child(header, "offset")
            if offset != NO_ELEMENT:
                ref element = document.elements[offset]
                for i in range(len(element.attribute_names)):
                    offsets[element.attribute_names[i]] = xml_as_double(
                        element.attribute_values[i]
                    )
    return parse_geo_projection_and_reference(proj_string, offsets)
