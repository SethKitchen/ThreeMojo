# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Tests for `extensions.energy.solar` and `extensions.energy.weather`.

The solar references are the worked examples and Table 1.6.1 of Duffie
and Beckman, "Solar Engineering of Thermal Processes", 4th edition, 2013.
The EPW reference is the fixture `assets/energy/fixture.epw`, a synthetic
day written for these tests.
"""

from std.math import acos, cos, exp, inf, nan, pi, sin
from std.testing import (
    TestSuite,
    assert_almost_equal,
    assert_equal,
    assert_false,
    assert_raises,
    assert_true,
)
from extensions.energy.ids import (
    BoundaryKind,
    EXTERIOR,
    GROUND,
    INTERZONE,
    SurfaceId,
    WindowId,
    ZoneId,
)
from extensions.energy.solar import (
    SunPosition,
    SurfaceOrientation,
    day_of_year,
    declination,
    declination_cooper,
    equation_of_time,
    hour_angle,
    incidence_cosine,
    orientation,
    solar_time,
    sun_angles,
    sun_position,
    tilted_irradiance,
)
from extensions.energy.weather import (
    WeatherLocation,
    ashrae_clear_sky,
    design_day,
    parse_epw,
    read_epw,
)
from generators.utils import Vec3d
from std.pathlib import Path
from units.si import (
    Angle64,
    DEGREE,
    Duration64,
    HOUR,
    HeatFlux64,
    Length64,
    METER,
    METER_PER_SECOND,
    MINUTE,
    PASCAL,
    Velocity64,
    WATT_PER_SQUARE_METER,
)
from units.temperature import CELSIUS, Temperature64


def _deg(v: Float64) -> Angle64:
    return Angle64(v, DEGREE)


def _flux(v: Float64) -> HeatFlux64:
    return HeatFlux64(v, WATT_PER_SQUARE_METER)


def _fixture() raises -> String:
    return Path("assets/energy/fixture.epw").read_text()


def _replace_line(text: String, index: Int, line: String) raises -> String:
    var lines = text.split("\n")
    var out = String()
    for i in range(len(lines)):
        if i > 0:
            out += "\n"
        if i == index:
            out += line
        else:
            out += String(lines[i])
    return out^


def _set_field(
    text: String, index: Int, field: Int, value: String
) raises -> String:
    var lines = text.split("\n")
    var fields = lines[index].split(",")
    var line = String()
    for i in range(len(fields)):
        if i > 0:
            line += ","
        if i == field:
            line += value
        else:
            line += String(fields[i])
    return _replace_line(text, index, line)


def _location() -> WeatherLocation:
    return WeatherLocation(
        "Golden",
        _deg(39.74),
        _deg(-105.18),
        Duration64(-7, HOUR),
        Length64(1829, METER),
    )


# --- ids --------------------------------------------------------------------


def test_ids_and_kinds() raises:
    assert_true(ZoneId(0).is_valid())
    assert_false(ZoneId(-1).is_valid())
    assert_false(SurfaceId(-1).is_valid())
    assert_false(WindowId(-1).is_valid())
    assert_true(GROUND.is_valid())
    assert_false(BoundaryKind(3).is_valid())
    assert_false(BoundaryKind(-1).is_valid())
    assert_equal(EXTERIOR.name(), "exterior")
    assert_equal(INTERZONE.name(), "interzone")
    assert_equal(BoundaryKind(7).name(), "unknown")


# --- solar ------------------------------------------------------------------


def test_day_of_year() raises:
    assert_equal(day_of_year(1, 1), 1)
    assert_equal(day_of_year(2, 3), 34)
    assert_equal(day_of_year(2, 29), 60)
    assert_equal(day_of_year(3, 1), 60)
    assert_equal(day_of_year(12, 31), 365)
    with assert_raises(contains="month"):
        _ = day_of_year(0, 1)
    with assert_raises(contains="month"):
        _ = day_of_year(13, 1)
    with assert_raises(contains="day"):
        _ = day_of_year(2, 30)
    with assert_raises(contains="day"):
        _ = day_of_year(5, 0)


def test_equation_of_time_example_1_5_1() raises:
    """Duffie and Beckman, Example 1.5.1: at Madison (89.4 W) on February 3
    at 10:30 central standard time, E = -13.5 min and the solar time is
    10:19."""
    var e = equation_of_time(34)
    assert_almost_equal(e.to(MINUTE), -13.5, atol=0.05)
    var solar = solar_time(
        Duration64(10.5, HOUR), 34, _deg(-89.4), Duration64(-6, HOUR)
    )
    assert_almost_equal(solar.to(MINUTE), 10 * 60 + 19, atol=0.2)
    assert_almost_equal(
        hour_angle(Duration64(9.5, HOUR)).to(DEGREE), -37.5, atol=1e-12
    )


def test_declination_table_1_6_1() raises:
    """Duffie and Beckman, Table 1.6.1: the declination on the recommended
    average day of each month, from Cooper's equation. Spencer's series
    changes sign at the equinoxes, March 20 to 21 and September 23 to 24,
    and peaks at the obliquity, 23.44 degrees, at the June solstice."""
    var days = [17, 47, 75, 105, 135, 162, 198, 228, 258, 288, 318, 344]
    var table: List[Float64] = [
        -20.9,
        -13.0,
        -2.4,
        9.4,
        18.8,
        23.1,
        21.2,
        13.5,
        2.2,
        -9.6,
        -18.9,
        -23.0,
    ]
    for i in range(len(days)):
        assert_almost_equal(
            declination_cooper(days[i]).to(DEGREE), table[i], atol=0.06
        )
    assert_true(declination(80).value < 0 and declination(81).value > 0)
    assert_true(declination(266).value > 0 and declination(267).value < 0)
    assert_almost_equal(declination(172).to(DEGREE), 23.44, atol=0.05)
    for bad in [0, 367]:
        with assert_raises(contains="day of the year"):
            _ = declination(bad)
        with assert_raises(contains="day of the year"):
            _ = declination_cooper(bad)
        with assert_raises(contains="day of the year"):
            _ = equation_of_time(bad)


def test_incidence_example_1_6_1() raises:
    """Duffie and Beckman, Example 1.6.1: at 43 N on February 13 at 10:30
    solar time (delta = -14, omega = -22.5 degrees), a surface tilted 45
    degrees and facing 15 degrees west of south has cos(theta) = 0.817 and
    theta = 35 degrees."""
    var sun = sun_angles(_deg(43), _deg(-14), _deg(-22.5))
    var surface = SurfaceOrientation(_deg(45), _deg(15))
    var c = incidence_cosine(surface, sun)
    assert_almost_equal(c, 0.817, atol=0.001)
    assert_almost_equal(acos(c) * 180 / pi, 35.0, atol=0.2)


def test_zenith_and_azimuth_example_1_6_2() raises:
    """Duffie and Beckman, Example 1.6.2: at 43 N, at 9:30 solar time on
    February 13 (delta = -14 degrees) theta_z = 66.5 and gamma_s = -40.0
    degrees; at 18:30 on July 1 (delta = 23.1 degrees) theta_z = 79.6 and
    gamma_s = 112.0 degrees."""
    var morning = sun_angles(_deg(43), _deg(-14), _deg(-37.5))
    assert_almost_equal(morning.zenith.to(DEGREE), 66.5, atol=0.05)
    assert_almost_equal(morning.azimuth.to(DEGREE), -40.0, atol=0.1)
    var evening = sun_angles(_deg(43), _deg(23.1), _deg(97.5))
    assert_almost_equal(evening.zenith.to(DEGREE), 79.6, atol=0.05)
    assert_almost_equal(evening.azimuth.to(DEGREE), 112.0, atol=0.05)
    assert_almost_equal(evening.altitude().to(DEGREE), 10.4, atol=0.05)
    assert_true(evening.is_up())


def test_sun_at_zenith_and_pole() raises:
    var overhead = sun_angles(_deg(20), _deg(20), _deg(0))
    assert_almost_equal(overhead.zenith.value, 0, atol=1e-7)
    assert_equal(overhead.azimuth.value, 0)
    var pole = sun_angles(_deg(90), _deg(10), _deg(45))
    assert_almost_equal(pole.zenith.to(DEGREE), 80, atol=1e-9)
    assert_equal(pole.azimuth.value, 0)
    var night = sun_angles(_deg(40), _deg(0), _deg(180))
    assert_false(night.is_up())
    # Due south at 30 degrees altitude.
    var south = SunPosition(_deg(60), _deg(0))
    var d = south.direction()
    assert_almost_equal(d.x, 0, atol=1e-15)
    assert_almost_equal(d.y, -cos(pi / 6), atol=1e-15)
    assert_almost_equal(d.z, 0.5, atol=1e-15)
    var west = SunPosition(_deg(90), _deg(90)).direction()
    assert_almost_equal(west.x, -1, atol=1e-15)


def test_sun_position_noon() raises:
    # At solar noon the zenith angle is |latitude - declination|.
    var day = 172
    var e = equation_of_time(day).to(HOUR)
    var clock = Duration64(12 - e + (105.0 - 105.0) / 15, HOUR)
    var sun = sun_position(
        _deg(40), _deg(-105), Duration64(-7, HOUR), day, clock
    )
    var delta = declination(day).to(DEGREE)
    assert_almost_equal(sun.zenith.to(DEGREE), 40 - delta, atol=1e-6)
    with assert_raises(contains="day of the year"):
        _ = sun_position(_deg(40), _deg(0), Duration64(0), 0, clock)


def test_orientation() raises:
    var south = orientation(Vec3d(0, -1, 0), _deg(0))
    assert_almost_equal(south.slope.to(DEGREE), 90, atol=1e-12)
    assert_almost_equal(south.azimuth.to(DEGREE), 0, atol=1e-12)
    var east = orientation(Vec3d(2, 0, 0), _deg(0))
    assert_almost_equal(east.azimuth.to(DEGREE), -90, atol=1e-12)
    var up = orientation(Vec3d(0, 0, 1), _deg(30))
    assert_equal(up.slope.value, 0)
    assert_equal(up.azimuth.value, 0)
    var down = orientation(Vec3d(0, 0, -1), _deg(0))
    assert_almost_equal(down.slope.to(DEGREE), 180, atol=1e-12)
    # True north along model -x: the model's +y axis faces east.
    var turned = orientation(Vec3d(0, 1, 0), _deg(90))
    assert_almost_equal(turned.azimuth.to(DEGREE), -90, atol=1e-12)
    with assert_raises(contains="normal"):
        _ = orientation(Vec3d(0, 0, 0), _deg(0))
    with assert_raises(contains="normal"):
        _ = orientation(Vec3d(inf[DType.float64](), 0, 0), _deg(0))


def test_tilted_irradiance_isotropic_sky() raises:
    """Duffie and Beckman, eq. 2.15.1, evaluated by hand."""
    var sun = SunPosition(_deg(60), _deg(20))
    var dni = _flux(700)
    var dhi = _flux(100)
    var ghi = _flux(700 * 0.5 + 100)
    var flat = tilted_irradiance(
        SurfaceOrientation(_deg(0), _deg(0)), sun, dni, dhi, ghi, 0.2
    )
    assert_almost_equal(flat.value, ghi.value, atol=1e-9)
    var wall = SurfaceOrientation(_deg(90), _deg(0))
    var on_wall = tilted_irradiance(wall, sun, dni, dhi, ghi, 0.2)
    var beam = 700 * sin(pi / 3) * cos(20 * pi / 180)
    assert_almost_equal(on_wall.value, beam + 50 + 450 * 0.2 * 0.5, atol=1e-9)
    # A north wall sees no beam.
    var north = SurfaceOrientation(_deg(90), _deg(180))
    var shaded = tilted_irradiance(north, sun, dni, dhi, ghi, 0.2)
    assert_almost_equal(shaded.value, 50 + 45, atol=1e-9)
    # A sun below the horizon gives no beam, even with a beam reading.
    var low = SunPosition(_deg(95), _deg(0))
    var dark = tilted_irradiance(
        SurfaceOrientation(_deg(180), _deg(0)), low, dni, dhi, ghi, 0.5
    )
    assert_almost_equal(dark.value, 450 * 0.5, atol=1e-9)
    with assert_raises(contains="irradiance"):
        _ = tilted_irradiance(wall, sun, _flux(-1), dhi, ghi, 0.2)
    with assert_raises(contains="irradiance"):
        _ = tilted_irradiance(
            wall, sun, dni, _flux(inf[DType.float64]()), ghi, 0.2
        )
    with assert_raises(contains="reflectance"):
        _ = tilted_irradiance(wall, sun, dni, dhi, ghi, -0.1)
    with assert_raises(contains="reflectance"):
        _ = tilted_irradiance(wall, sun, dni, dhi, ghi, 1.1)


# --- EPW --------------------------------------------------------------------


def test_read_epw_fixture() raises:
    var w = read_epw("assets/energy/fixture.epw")
    assert_equal(w.location.name, "Testville")
    assert_almost_equal(w.location.latitude.to(DEGREE), 40, atol=1e-12)
    assert_almost_equal(w.location.longitude.to(DEGREE), -105, atol=1e-12)
    assert_almost_equal(w.location.time_zone.to(HOUR), -7, atol=1e-12)
    assert_almost_equal(w.location.elevation.to(METER), 1600, atol=1e-12)
    assert_equal(len(w.records), 24)
    assert_equal(w.records_per_hour(), 1)
    assert_almost_equal(w.step.to(HOUR), 1, atol=1e-12)
    ref r = w.records[11]
    assert_equal(r.month, 1)
    assert_equal(r.day, 15)
    assert_equal(r.day_of_year(), 15)
    assert_almost_equal(r.end.to(HOUR), 12, atol=1e-12)
    assert_almost_equal(r.dry_bulb.to(CELSIUS), 2.8, atol=1e-9)
    assert_almost_equal(r.dew_point.to(CELSIUS), -8, atol=1e-9)
    assert_almost_equal(r.relative_humidity, 45, atol=1e-12)
    assert_almost_equal(r.pressure.to(PASCAL), 83500, atol=1e-9)
    assert_almost_equal(r.global_horizontal.value, 499, atol=1e-9)
    assert_almost_equal(r.direct_normal.value, 834, atol=1e-9)
    assert_almost_equal(r.diffuse_horizontal.value, 58, atol=1e-9)
    assert_almost_equal(r.wind_direction.to(DEGREE), 260, atol=1e-9)
    assert_almost_equal(r.wind_speed.to(METER_PER_SECOND), 2.2, atol=1e-12)


def test_epw_sub_hourly_and_blank_lines() raises:
    var text = _replace_line(
        _fixture(), 7, "DATA PERIODS,1,4,Data,Sunday, 1/15,1/15"
    )
    text = _replace_line(text, 12, "")
    var w = parse_epw(text)
    assert_equal(w.records_per_hour(), 4)
    assert_equal(len(w.records), 23)
    assert_almost_equal(w.records[0].end.to(HOUR), 0.25, atol=1e-12)
    # The fourth record of hour 4 ends at 4:00; the blank line drops hour 5.
    assert_almost_equal(w.records[3].end.to(HOUR), 4.0, atol=1e-12)
    assert_almost_equal(w.records[4].end.to(HOUR), 5.25, atol=1e-12)
    # 499 Wh/m² over a quarter hour is 1996 W/m².
    assert_almost_equal(
        w.records[10].global_horizontal.value, 499 * 4, atol=1e-9
    )


def test_epw_refuses_malformed_headers() raises:
    var text = _fixture()
    with assert_raises(contains="8 header lines"):
        _ = parse_epw("LOCATION,a\nb\nc")
    with assert_raises(contains="line 1"):
        _ = parse_epw(_replace_line(text, 0, "PLACE,a,b,c,d,e,40,-105,-7,1600"))
    with assert_raises(contains="line 1"):
        _ = parse_epw(_replace_line(text, 0, "LOCATION,a,b,c,d,e,40,-105,-7"))
    with assert_raises(contains="latitude is not a number"):
        _ = parse_epw(_set_field(text, 0, 6, "north"))
    with assert_raises(contains="latitude must be"):
        _ = parse_epw(_set_field(text, 0, 6, "95"))
    with assert_raises(contains="line 8"):
        _ = parse_epw(_replace_line(text, 7, "DATA,1,1"))
    with assert_raises(contains="line 8"):
        _ = parse_epw(_replace_line(text, 7, "DATA PERIODS,1"))
    with assert_raises(contains="not an integer"):
        _ = parse_epw(_set_field(text, 7, 2, "many"))
    with assert_raises(contains="divide 60"):
        _ = parse_epw(_set_field(text, 7, 2, "7"))
    with assert_raises(contains="divide 60"):
        _ = parse_epw(_set_field(text, 7, 2, "0"))
    var lines = text.split("\n")
    var header = String()
    for i in range(8):
        header += String(lines[i], "\n")
    with assert_raises(contains="needs a record"):
        _ = parse_epw(header)
    var bare = String(lines[0])
    for i in range(1, 8):
        bare += String("\n", lines[i])
    with assert_raises(contains="needs a record"):
        _ = parse_epw(bare)
    with assert_raises():
        _ = read_epw("assets/energy/missing.epw")


def test_epw_refuses_malformed_records() raises:
    var text = _fixture()
    with assert_raises(contains="22 fields"):
        _ = parse_epw(_replace_line(text, 8, "2023,1,15,1,60"))
    with assert_raises(contains="EPW line 9: The month is not an integer"):
        _ = parse_epw(_set_field(text, 8, 1, "Jan"))
    with assert_raises(contains="month must be"):
        _ = parse_epw(_set_field(text, 8, 1, "13"))
    with assert_raises(contains="not in its month"):
        _ = parse_epw(_set_field(text, 8, 2, "32"))
    with assert_raises(contains="hour must be"):
        _ = parse_epw(_set_field(text, 8, 3, "0"))
    with assert_raises(contains="hour must be"):
        _ = parse_epw(_set_field(text, 8, 3, "25"))
    with assert_raises(contains="dry-bulb is not a number"):
        _ = parse_epw(_set_field(text, 8, 6, "warm"))
    with assert_raises(contains="dry-bulb is out of range or missing"):
        _ = parse_epw(_set_field(text, 8, 6, "99.9"))
    with assert_raises(contains="dry-bulb is out of range"):
        _ = parse_epw(_set_field(text, 8, 6, "-80"))
    with assert_raises(contains="dew point is out of range"):
        _ = parse_epw(_set_field(text, 8, 7, "99.9"))
    with assert_raises(contains="humidity is out of range"):
        _ = parse_epw(_set_field(text, 8, 8, "999"))
    with assert_raises(contains="pressure is out of range"):
        _ = parse_epw(_set_field(text, 8, 9, "999999"))
    with assert_raises(contains="irradiation is out of range"):
        _ = parse_epw(_set_field(text, 8, 14, "9999"))
    with assert_raises(contains="irradiation is not a number"):
        _ = parse_epw(_set_field(text, 8, 13, "?"))
    with assert_raises(contains="wind direction is out of range"):
        _ = parse_epw(_set_field(text, 8, 20, "999"))
    with assert_raises(contains="wind speed is out of range"):
        _ = parse_epw(_set_field(text, 8, 21, "999"))


def test_location_check() raises:
    _location().check()
    var bad = List[WeatherLocation]()
    bad.append(
        WeatherLocation("a", _deg(-95), _deg(0), Duration64(0), Length64(0))
    )
    bad.append(
        WeatherLocation("b", _deg(95), _deg(0), Duration64(0), Length64(0))
    )
    for i in range(len(bad)):
        with assert_raises(contains="latitude"):
            bad[i].check()
    with assert_raises(contains="longitude"):
        WeatherLocation(
            "c", _deg(0), _deg(-181), Duration64(0), Length64(0)
        ).check()
    with assert_raises(contains="longitude"):
        WeatherLocation(
            "d", _deg(0), _deg(181), Duration64(0), Length64(0)
        ).check()
    with assert_raises(contains="time zone"):
        WeatherLocation(
            "e", _deg(0), _deg(0), Duration64(-13, HOUR), Length64(0)
        ).check()
    with assert_raises(contains="time zone"):
        WeatherLocation(
            "f", _deg(0), _deg(0), Duration64(15, HOUR), Length64(0)
        ).check()
    with assert_raises(contains="elevation"):
        WeatherLocation(
            "g", _deg(0), _deg(0), Duration64(0), Length64(nan[DType.float64]())
        ).check()


# --- design day --------------------------------------------------------------


def test_ashrae_clear_sky() raises:
    """ASHRAE clear-sky model: July A = 1085 W/m², B = 0.207, C = 0.136."""
    var sun = SunPosition(_deg(20), _deg(0))
    var sky = ashrae_clear_sky(7, sun, 1.0)
    var direct = 1085 * exp(-0.207 / cos(20 * pi / 180))
    assert_almost_equal(sky.direct_normal.value, direct, atol=1e-9)
    assert_almost_equal(sky.diffuse_horizontal.value, 0.136 * direct, atol=1e-9)
    assert_almost_equal(
        sky.global_horizontal.value,
        direct * cos(20 * pi / 180) + 0.136 * direct,
        atol=1e-9,
    )
    var hazy = ashrae_clear_sky(1, sun, 0.9)
    assert_almost_equal(
        hazy.direct_normal.value,
        0.9 * 1230 * exp(-0.142 / cos(20 * pi / 180)),
        atol=1e-9,
    )
    var night = ashrae_clear_sky(1, SunPosition(_deg(100), _deg(0)), 1.0)
    assert_equal(night.global_horizontal.value, 0)
    with assert_raises(contains="month"):
        _ = ashrae_clear_sky(0, sun, 1.0)
    with assert_raises(contains="month"):
        _ = ashrae_clear_sky(13, sun, 1.0)
    with assert_raises(contains="clearness"):
        _ = ashrae_clear_sky(7, sun, 0)
    with assert_raises(contains="clearness"):
        _ = ashrae_clear_sky(7, sun, 1.6)


def test_design_day() raises:
    var loc = _location()
    var w = design_day(
        loc,
        7,
        21,
        Temperature64(15, CELSIUS),
        Temperature64(31, CELSIUS),
        Temperature64(10, CELSIUS),
        Velocity64(3, METER_PER_SECOND),
        1.0,
        1,
    )
    assert_equal(len(w.records), 24)
    # A sinusoid sampled evenly averages to its middle.
    var mean = 0.0
    var low = 1e9
    var high = -1e9
    for i in range(24):
        var t = w.records[i].dry_bulb.to(CELSIUS)
        mean += t / 24
        low = min(low, t)
        high = max(high, t)
    assert_almost_equal(mean, 23, atol=1e-9)
    assert_true(low >= 15 and high <= 31)
    # Symmetric about 15:00: the intervals ending 15:00 and 16:00.
    assert_almost_equal(
        w.records[14].dry_bulb.kelvin, w.records[15].dry_bulb.kelvin, atol=1e-9
    )
    assert_equal(w.records[0].global_horizontal.value, 0)
    # At 12:30 the irradiance is the clear-sky model at that sun.
    var sun = sun_position(
        loc.latitude, loc.longitude, loc.time_zone, 202, Duration64(12.5, HOUR)
    )
    var sky = ashrae_clear_sky(7, sun, 1.0)
    assert_almost_equal(
        w.records[12].direct_normal.value, sky.direct_normal.value, atol=1e-9
    )
    assert_true(w.records[12].direct_normal.value > 700)
    # Standard atmosphere at 1829 m: about 81.2 kPa.
    assert_almost_equal(w.records[0].pressure.to(PASCAL), 81200, atol=150)
    assert_true(w.records[12].relative_humidity < 100)
    # A dew point at a constant dry-bulb is saturation.
    var foggy = design_day(
        WeatherLocation("sea", _deg(0), _deg(0), Duration64(0), Length64(0)),
        3,
        21,
        Temperature64(12, CELSIUS),
        Temperature64(12, CELSIUS),
        Temperature64(12, CELSIUS),
        Velocity64(0),
        1.0,
        4,
    )
    assert_equal(len(foggy.records), 96)
    assert_almost_equal(foggy.records[50].relative_humidity, 100, atol=1e-9)
    assert_almost_equal(foggy.records[0].pressure.to(PASCAL), 101325, atol=1e-6)
    assert_almost_equal(foggy.records[0].end.to(HOUR), 0.25, atol=1e-12)


def test_design_day_refuses() raises:
    var loc = _location()
    var t15 = Temperature64(15, CELSIUS)
    var t30 = Temperature64(30, CELSIUS)
    var v = Velocity64(3, METER_PER_SECOND)
    with assert_raises(contains="high"):
        _ = design_day(loc, 7, 21, t30, t15, t15, v, 1.0, 1)
    with assert_raises(contains="dew point"):
        _ = design_day(loc, 7, 21, t15, t30, t30, v, 1.0, 1)
    with assert_raises(contains="wind"):
        _ = design_day(loc, 7, 21, t15, t30, t15, Velocity64(-1), 1.0, 1)
    with assert_raises(contains="wind"):
        _ = design_day(
            loc, 7, 21, t15, t30, t15, Velocity64(inf[DType.float64]()), 1.0, 1
        )
    with assert_raises(contains="clearness"):
        _ = design_day(loc, 7, 21, t15, t30, t15, v, 0.0, 1)
    with assert_raises(contains="divide 60"):
        _ = design_day(loc, 7, 21, t15, t30, t15, v, 1.0, 7)
    with assert_raises(contains="not in its month"):
        _ = design_day(loc, 6, 31, t15, t30, t15, v, 1.0, 1)
    with assert_raises(contains="latitude"):
        _ = design_day(
            WeatherLocation("x", _deg(91), _deg(0), Duration64(0), Length64(0)),
            7,
            21,
            t15,
            t30,
            t15,
            v,
            1.0,
            1,
        )


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
