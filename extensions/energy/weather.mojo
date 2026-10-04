# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Weather: an EPW file reader and a synthetic design day.

An EPW file is text. It has 8 header lines and then one record per line,
with comma-separated fields. The first header line starts with LOCATION
and gives the site. The eighth starts with DATA PERIODS and gives the
number of records per hour. Each record gives the date, the hour, the
air state, the solar irradiance and the wind. The reader keeps:

| Field | Meaning | Unit in the file |
|---|---|---|
| 2, 3, 4 | Month, day, hour (1 to 24, the end of the interval) | |
| 7, 8 | Dry-bulb and dew-point temperature | degrees Celsius |
| 9 | Relative humidity | percent |
| 10 | Atmospheric station pressure | Pa |
| 14, 15, 16 | Global horizontal, direct normal and diffuse horizontal irradiation | Wh/m² over the interval |
| 21, 22 | Wind direction and speed | degrees from north, m/s |

An irradiation in Wh/m² over one hour is the mean irradiance in W/m² over
that hour. For a file with more than one record per hour, the reader
divides by the interval length.

The design day is a synthetic day of clear sky. Its dry-bulb temperature
is a sinusoid between a low at 03:00 and a high at 15:00 local standard
time. Its solar irradiance is the clear-sky model of the ASHRAE
Handbook of Fundamentals (1985 to 2005 editions): I_DN = CN A exp(-B /
cos theta_z) and I_d = C I_DN on the horizontal, with the monthly A, B
and C of that model for the 21st day of each month.
"""

from std.math import cos, exp, isfinite, pi
from std.pathlib import Path
from extensions.energy.solar import SunPosition, day_of_year, sun_position
from units.si import (
    Angle64,
    DEGREE,
    Duration64,
    HOUR,
    HeatFlux64,
    Length64,
    METER,
    METER_PER_SECOND,
    PASCAL,
    Pressure64,
    Velocity64,
    WATT_PER_SQUARE_METER,
)
from units.temperature import CELSIUS, Temperature64


struct WeatherLocation(Copyable, Movable):
    """The site of a weather file."""

    var name: String
    var latitude: Angle64
    var longitude: Angle64
    # The offset of local standard time from universal time, east positive.
    var time_zone: Duration64
    var elevation: Length64

    def __init__(
        out self,
        var name: String,
        latitude: Angle64,
        longitude: Angle64,
        time_zone: Duration64,
        elevation: Length64,
    ):
        """Create a location. Call `check` before use.

        Args:
            name: The name of the station or the city.
            latitude: The latitude, north positive.
            longitude: The longitude, east positive.
            time_zone: The offset of standard time from universal time.
            elevation: The height above sea level.
        """
        self.name = name^
        self.latitude = latitude
        self.longitude = longitude
        self.time_zone = time_zone
        self.elevation = elevation

    def check(self) raises:
        """Refuse a location that is not on the Earth.

        Raises:
            Error: If the latitude is outside -90 to 90 degrees, the
                longitude outside -180 to 180, the time zone outside -12 to
                14 hours, or the elevation is not finite.
        """
        var lat = self.latitude.to(DEGREE)
        var lon = self.longitude.to(DEGREE)
        var zone = self.time_zone.to(HOUR)
        if not (lat >= -90 and lat <= 90):
            raise Error("A latitude must be from -90 to 90 degrees")
        if not (lon >= -180 and lon <= 180):
            raise Error("A longitude must be from -180 to 180 degrees")
        if not (zone >= -12 and zone <= 14):
            raise Error("A time zone must be from -12 to 14 hours")
        if not isfinite(self.elevation.to(METER)):
            raise Error("An elevation must be finite")


@fieldwise_init
struct WeatherRecord(ImplicitlyCopyable):
    """The weather over one interval."""

    var month: Int
    var day: Int
    # The end of the interval, from local standard midnight. Up to 24 h.
    var end: Duration64
    var dry_bulb: Temperature64
    var dew_point: Temperature64
    # In percent.
    var relative_humidity: Float64
    var pressure: Pressure64
    var global_horizontal: HeatFlux64
    var direct_normal: HeatFlux64
    var diffuse_horizontal: HeatFlux64
    # The direction the wind comes from, clockwise from north.
    var wind_direction: Angle64
    var wind_speed: Velocity64

    def day_of_year(self) raises -> Int:
        """Return the day of the year of the record.

        Returns:
            The day, 1 to 365.

        Raises:
            Error: If the date is not in the calendar.
        """
        return day_of_year(self.month, self.day)


struct Weather(Movable):
    """A location, an interval length and the records, in time order."""

    var location: WeatherLocation
    var step: Duration64
    var records: List[WeatherRecord]

    def __init__(
        out self,
        var location: WeatherLocation,
        step: Duration64,
        var records: List[WeatherRecord],
    ):
        """Hold weather records.

        Args:
            location: The site.
            step: The length of one record's interval.
            records: The records, in time order.
        """
        self.location = location^
        self.step = step
        self.records = records^

    def records_per_hour(self) -> Int:
        """Return the number of records in one hour.

        Returns:
            One hour divided by the step, rounded.
        """
        return Int(1.0 / self.step.to(HOUR) + 0.5)


def _at(line: Int, message: String) -> Error:
    return Error(String("EPW line ", line, ": ", message))


def _number(field: StringSlice, what: String, line: Int) raises -> Float64:
    try:
        return atof(field)
    except:
        raise _at(line, String(what, " is not a number"))


def _integer(field: StringSlice, what: String, line: Int) raises -> Int:
    try:
        return atol(field.strip())
    except:
        raise _at(line, String(what, " is not an integer"))


def _within(
    value: Float64, low: Float64, high: Float64, what: String, line: Int
) raises -> Float64:
    if not (value >= low and value <= high):
        raise _at(line, String(what, " is out of range or missing"))
    return value


def _check_steps(steps: Int) raises:
    if steps < 1 or 60 % steps != 0:
        raise Error("Records per hour must divide 60")


def parse_epw(text: String) raises -> Weather:
    """Return the weather in the text of an EPW file.

    Args:
        text: The whole file.

    Returns:
        The location, the interval and the records.

    Raises:
        Error: If the header is short or malformed, the location is not on
            the Earth, the records per hour do not divide 60, there is no
            record, a record has fewer than 22 fields, or a field is not a
            number, is out of the range of the format or is missing.
    """
    var lines = text.split("\n")
    if len(lines) < 8:
        raise Error("An EPW file needs 8 header lines")
    var head = lines[0].split(",")
    if String(head[0].strip()) != "LOCATION" or len(head) < 10:
        raise _at(1, "The first line must be LOCATION with 10 fields")
    var location = WeatherLocation(
        String(head[1].strip()),
        Angle64(_number(head[6], "The latitude", 1), DEGREE),
        Angle64(_number(head[7], "The longitude", 1), DEGREE),
        Duration64(_number(head[8], "The time zone", 1), HOUR),
        Length64(_number(head[9], "The elevation", 1), METER),
    )
    location.check()
    var periods = lines[7].split(",")
    if String(periods[0].strip()) != "DATA PERIODS" or len(periods) < 3:
        raise _at(8, "The eighth line must be DATA PERIODS")
    var steps = _integer(periods[2], "The records per hour", 8)
    _check_steps(steps)
    var hours = 1.0 / Float64(steps)
    var records = List[WeatherRecord]()
    for i in range(8, len(lines)):
        var line = i + 1
        var stripped = lines[i].strip()
        if stripped.byte_length() == 0:
            continue
        var f = stripped.split(",")
        if len(f) < 22:
            raise _at(line, "A record needs at least 22 fields")
        var month = _integer(f[1], "The month", line)
        var day = _integer(f[2], "The day", line)
        try:
            _ = day_of_year(month, day)
        except e:
            raise _at(line, String(e))
        var hour = _integer(f[3], "The hour", line)
        if hour < 1 or hour > 24:
            raise _at(line, "The hour must be 1 to 24")
        var sub = len(records) % steps
        var end = Float64(hour - 1) + Float64(sub + 1) * hours
        var dry = _within(
            _number(f[6], "The dry-bulb", line), -70, 70, "The dry-bulb", line
        )
        var dew = _within(
            _number(f[7], "The dew point", line), -70, 70, "The dew point", line
        )
        var rh = _within(
            _number(f[8], "The humidity", line), 0, 110, "The humidity", line
        )
        var p = _within(
            _number(f[9], "The pressure", line),
            31000,
            120000,
            "The pressure",
            line,
        )
        var flux = List[Float64]()
        for k in range(13, 16):  # pragma: no branch
            var v = _number(f[k], "An irradiation", line)
            flux.append(_within(v, 0, 9998, "An irradiation", line) / hours)
        var direction = _within(
            _number(f[20], "The wind direction", line),
            0,
            360,
            "The wind direction",
            line,
        )
        var speed = _within(
            _number(f[21], "The wind speed", line),
            0,
            40,
            "The wind speed",
            line,
        )
        records.append(
            WeatherRecord(
                month,
                day,
                Duration64(end, HOUR),
                Temperature64(dry, CELSIUS),
                Temperature64(dew, CELSIUS),
                rh,
                Pressure64(p, PASCAL),
                HeatFlux64(flux[0], WATT_PER_SQUARE_METER),
                HeatFlux64(flux[1], WATT_PER_SQUARE_METER),
                HeatFlux64(flux[2], WATT_PER_SQUARE_METER),
                Angle64(direction, DEGREE),
                Velocity64(speed, METER_PER_SECOND),
            )
        )
    if len(records) == 0:
        raise Error("An EPW file needs a record")
    return Weather(location^, Duration64(hours, HOUR), records^)


def read_epw(path: String) raises -> Weather:
    """Return the weather in an EPW file.

    Args:
        path: The file.

    Returns:
        The location, the interval and the records.

    Raises:
        Error: If the file cannot be read, or `parse_epw` refuses it.
    """
    return parse_epw(Path(path).read_text())


def _check_clearness(clearness: Float64) raises:
    if not (clearness > 0 and clearness <= 1.5):
        raise Error("A clearness number must be over zero and up to 1.5")


@fieldwise_init
struct ClearSky(ImplicitlyCopyable):
    """The irradiance of a clear sky."""

    var direct_normal: HeatFlux64
    var diffuse_horizontal: HeatFlux64
    var global_horizontal: HeatFlux64


def ashrae_clear_sky(
    month: Int, sun: SunPosition, clearness: Float64
) raises -> ClearSky:
    """Return the irradiance of a clear sky by the ASHRAE model.

    I_DN = CN A exp(-B / cos theta_z), I_d = C I_DN on the horizontal and
    I = I_DN cos theta_z + I_d. A, B and C are the monthly values of the
    ASHRAE Handbook of Fundamentals clear-sky model, from 1230 W/m², 0.142
    and 0.058 in January to 1085 W/m², 0.207 and 0.136 in July.

    Args:
        month: The month, 1 to 12.
        sun: The position of the sun.
        clearness: The clearness number CN, 1 for an average clear sky.

    Returns:
        The irradiance. It is zero when the sun is below the horizon.

    Raises:
        Error: If the month is not 1 to 12 or the clearness is not over
            zero and up to 1.5.
    """
    if month < 1 or month > 12:
        raise Error("A month must be 1 to 12")
    _check_clearness(clearness)
    var zero = HeatFlux64(0)
    if not sun.is_up():
        return ClearSky(zero, zero, zero)
    var a: List[Float64] = [
        1230,
        1215,
        1186,
        1136,
        1104,
        1088,
        1085,
        1107,
        1151,
        1192,
        1221,
        1233,
    ]
    var b: List[Float64] = [
        0.142,
        0.144,
        0.156,
        0.180,
        0.196,
        0.205,
        0.207,
        0.201,
        0.177,
        0.160,
        0.149,
        0.142,
    ]
    var c: List[Float64] = [
        0.058,
        0.060,
        0.071,
        0.097,
        0.121,
        0.134,
        0.136,
        0.122,
        0.092,
        0.073,
        0.063,
        0.057,
    ]
    var m = month - 1
    var cos_z = cos(sun.zenith.value)
    var direct = clearness * a[m] * exp(-b[m] / cos_z)
    var diffuse = c[m] * direct
    return ClearSky(
        HeatFlux64(direct, WATT_PER_SQUARE_METER),
        HeatFlux64(diffuse, WATT_PER_SQUARE_METER),
        HeatFlux64(direct * cos_z + diffuse, WATT_PER_SQUARE_METER),
    )


def _vapor_pressure(celsius: Float64) -> Float64:
    # Magnus form of Alduchov and Eskridge (1996), in hPa.
    return 6.1094 * exp(17.625 * celsius / (celsius + 243.04))


def design_day(
    location: WeatherLocation,
    month: Int,
    day: Int,
    low: Temperature64,
    high: Temperature64,
    dew_point: Temperature64,
    wind_speed: Velocity64,
    clearness: Float64,
    steps_per_hour: Int,
) raises -> Weather:
    """Return a synthetic clear day of weather.

    The dry-bulb temperature at time t hours is low + (high - low)
    (1 + cos(2 pi (t - 15) / 24)) / 2. Each record holds the state at the
    middle of its interval. The relative humidity follows from the dew
    point by the Magnus form of Alduchov and Eskridge (1996). The pressure
    is that of the standard atmosphere at the elevation, ASHRAE Handbook
    of Fundamentals chapter 1: 101.325 (1 - 2.25577e-5 Z)^5.2559 kPa.

    Args:
        location: The site.
        month: The month, 1 to 12.
        day: The day of the month.
        low: The lowest dry-bulb temperature, at 03:00.
        high: The highest dry-bulb temperature, at 15:00.
        dew_point: The dew point, constant over the day.
        wind_speed: The wind speed, constant over the day, from the north.
        clearness: The ASHRAE clearness number, 1 for an average clear sky.
        steps_per_hour: The records per hour. It must divide 60.

    Returns:
        One day of weather.

    Raises:
        Error: If the location or the date is not valid, the high is below
            the low, the dew point is above the low, the wind speed is
            negative or not finite, the clearness is out of range, or the
            steps do not divide 60.
    """
    location.check()
    var n = day_of_year(month, day)
    _check_steps(steps_per_hour)
    var t_low = low.to(CELSIUS)
    var t_high = high.to(CELSIUS)
    var t_dew = dew_point.to(CELSIUS)
    if not (t_low <= t_high):
        raise Error("A design day's high must not be below its low")
    if not (t_dew <= t_low):
        raise Error("A design day's dew point must not be above its low")
    var v = wind_speed.to(METER_PER_SECOND)
    if not (v >= 0 and isfinite(v)):
        raise Error("A wind speed must be zero or more and finite")
    _check_clearness(clearness)
    var z = location.elevation.to(METER)
    var pressure = 101325.0 * (1 - 2.25577e-5 * z) ** 5.2559
    var hours = 1.0 / Float64(steps_per_hour)
    var records = List[WeatherRecord]()
    for k in range(24 * steps_per_hour):  # pragma: no branch
        var end = Float64(k + 1) * hours
        var middle = end - hours / 2
        var t = (
            t_low
            + (t_high - t_low) * (1 + cos(2 * pi * (middle - 15) / 24)) / 2
        )
        var rh = 100 * _vapor_pressure(t_dew) / _vapor_pressure(t)
        var sun = sun_position(
            location.latitude,
            location.longitude,
            location.time_zone,
            n,
            Duration64(middle, HOUR),
        )
        var sky = ashrae_clear_sky(month, sun, clearness)
        records.append(
            WeatherRecord(
                month,
                day,
                Duration64(end, HOUR),
                Temperature64(t, CELSIUS),
                dew_point,
                rh,
                Pressure64(pressure, PASCAL),
                sky.global_horizontal,
                sky.direct_normal,
                sky.diffuse_horizontal,
                Angle64(0),
                wind_speed,
            )
        )
    return Weather(location.copy(), Duration64(hours, HOUR), records^)
