# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""A day at Wijnendale Castle: the sun, the shadows, the moat and the wind.

    mojo run -I . examples/wijnendale_simulation.mojo [path.png]

The page is Castle analysis. The example draws the castle each hour from 09:00
to 18:00 local time on 19 October 2026 and writes the pictures as an animated
PNG. The sun is where it stands over Torhout. The shadow of each tower, the
share of the courtyard in the sun, and the level of the moat are worked out for
the same hours and printed. Then the report gives the analyses of the
engineering of the castle:

- the wind on the donjon by EN 1991-1-4, and the stresses at its base;
- the arch of the bridge by Heyman's limit analysis;
- the quay wall as a gravity retaining wall;
- the water balance of the moat, with its weir.

Every figure of the plan that no survey gives is marked as an estimate in the
page.
"""

from tools._example_output import (
    example_destination,
    gallery_camera,
    write_example,
)

from core.clock import Clock
from extensions.castle.arch import arch_check, bridge_arch
from extensions.castle.moat_wall import (
    least_thickness,
    moat_drawn_down,
    moat_full,
    quay_wall,
    wall_stability,
)
from extensions.castle.moat_water import DayWeather, wijnendale_moat
from extensions.castle.scene import (
    SceneSettings,
    advance_water,
    aim_sun,
    build_castle_scene,
    castle_renderer,
    draw_castle,
)
from extensions.castle.shadow import donjon_shadow, lit_fraction
from extensions.castle.sun import (
    day_of_year,
    solar_noon,
    solar_position,
    sunrise_and_sunset,
)
from extensions.castle.wijnendale import (
    latitude,
    longitude,
    wijnendale_plan,
)
from extensions.castle.wind import (
    base_check,
    donjon_shaft,
    shaft_frequency_beam,
    shaft_frequency_en,
    shaft_frequency_fe,
    tower_wind,
    wijnendale_wind_site,
)
from math.vector3 import Vector3
from render.framebuffer import Framebuffer
from std.math import atan2, pi
from units.si import (
    Angle,
    DEGREE,
    DEGREE64,
    Duration64,
    Length,
    Length64,
    METER,
    PER_SECOND,
)

comptime DEFAULT_OUTPUT = "out/wijnendale_simulation.png"
comptime WIDTH = 480
comptime HEIGHT = 600
comptime DELAY_MS = 600
comptime YEAR = 2026
# Summer time: local time is two hours ahead of Coordinated Universal Time.
comptime LOCAL_OFFSET = 2
comptime FIRST_HOUR = 9
comptime LAST_HOUR = 18
# The weather of an average day of October at Torhout, as depths of water: the
# normal rain is about 75 mm in the month, and the evaporation of open water
# about 35 mm.
comptime RAIN_MM = 2.4
comptime EVAPORATION_MM = 1.1


def _fixed(value: Float64, places: Int) -> String:
    """Return a number with a fixed count of decimal places."""
    var scale = 1
    for _ in range(places):
        scale *= 10
    var scaled = Int(abs(value) * Float64(scale) + 0.5)
    var text = String(scaled // scale)
    if places > 0:
        var digits = String(scaled % scale)
        while digits.byte_length() < places:
            digits = "0" + digits
        text += "." + digits
    if value < 0.0 and scaled > 0:
        text = "-" + text
    return text


def _smooth(x: Float64) -> Float64:
    """Return the smooth step of a number clamped to 0 through 1."""
    var t = min(max(x, 0.0), 1.0)
    return t * t * (3.0 - 2.0 * t)


def _left(text: String, width: Int) -> String:
    """Return a text padded on the left to a width."""
    var padded = text
    while padded.byte_length() < width:
        padded = " " + padded
    return padded


def _clock(seconds_utc: Float64) -> String:
    """Return a time of day as local hours and minutes."""
    var minutes = Int(seconds_utc / 60.0 + 0.5) + LOCAL_OFFSET * 60
    var hours = (minutes // 60) % 24
    var rest = minutes % 60
    var tens = "0" if rest < 10 else ""
    var pad = "0" if hours < 10 else ""
    return pad + String(hours) + ":" + tens + String(rest)


def _compass(azimuth_degrees: Float64) -> String:
    """Return the nearest of the eight points of the compass."""
    var names = ["N", "NE", "E", "SE", "S", "SW", "W", "NW"]
    var at = Int((azimuth_degrees + 22.5) / 45.0) % 8
    return names[at]


def _heading(east: Float64, north: Float64) -> Float64:
    """Return the bearing of a vector, clockwise from north, in degrees."""
    var bearing = atan2(east, north) * 180.0 / pi
    if bearing < 0.0:
        bearing += 360.0
    return bearing


def _title(text: String):
    print()
    print(text)
    var rule = String("")
    for _ in range(text.byte_length()):
        rule += "-"
    print(rule)


def _report_site() raises:
    var day = day_of_year(YEAR, 10, 19)
    var times = sunrise_and_sunset(latitude(), longitude(), YEAR, day)
    var noon = solar_noon(longitude(), YEAR, day)
    var high = solar_position(
        latitude(), longitude(), YEAR, day, noon.value / 3600.0
    )
    _title("Wijnendale Castle, 19 October 2026")
    print(
        "Site: ",
        _fixed(latitude().to(DEGREE64), 4),
        " N, ",
        _fixed(longitude().to(DEGREE64), 4),
        " E (Torhout, West Flanders). Times are local, UTC+2.",
        sep="",
    )
    print(
        "Sunrise ",
        _clock(times[0].value),
        ", solar noon ",
        _clock(noon.value),
        ", sunset ",
        _clock(times[1].value),
        ". Greatest height of the sun ",
        _fixed(high.altitude.to(DEGREE64), 1),
        " degrees.",
        sep="",
    )


def _report_wind() raises:
    var plan = wijnendale_plan()
    var shaft = donjon_shaft(plan)
    var site = wijnendale_wind_site()
    var f_en = shaft_frequency_en(shaft)
    var f_beam = shaft_frequency_beam(shaft)
    var f_fe = shaft_frequency_fe(shaft, 12)
    var wind = tower_wind(site, shaft, f_fe)
    var check = base_check(shaft, wind)
    _title("Wind on the donjon, EN 1991-1-4")
    print(
        "The donjon is a hollow brick shaft: ",
        _fixed(shaft.outer_diameter.value, 2),
        " m across, a wall of ",
        _fixed(shaft.wall_thickness.value, 1),
        " m (assumed), ",
        _fixed(shaft.height.value, 2),
        " m high from the water, ",
        _fixed(shaft.weight().value / 1.0e6, 2),
        " MN.",
        sep="",
    )
    print(
        "Natural frequency: F.3 chimney formula ",
        _fixed(f_en.to(PER_SECOND), 2),
        " Hz, cantilever beam ",
        _fixed(f_beam.to(PER_SECOND), 2),
        " Hz, finite element model ",
        _fixed(f_fe.to(PER_SECOND), 2),
        " Hz. The model is used.",
        sep="",
    )
    print(
        "Wind: basic velocity ",
        _fixed(site.basic_velocity.value, 0),
        " m/s (the top of the Belgian zones), terrain category II,",
        " peak pressure ",
        _fixed(wind.peak_pressure.value / 1000.0, 2),
        " kN/m2 at the top.",
        sep="",
    )
    print(
        "Force coefficient: Re ",
        _fixed(wind.reynolds / 1.0e6, 1),
        "e6, cf0 ",
        _fixed(wind.cf0, 2),
        ", slenderness ",
        _fixed(wind.slenderness, 1),
        ", end effect ",
        _fixed(wind.end_effect, 2),
        ", cf ",
        _fixed(wind.cf, 2),
        ". Structural factor ",
        _fixed(wind.structural.value, 3),
        " (Annex B), 1.0 used.",
        sep="",
    )
    print(
        "Vortex shedding: critical velocity ",
        _fixed(wind.critical_velocity.value, 0),
        " m/s; the check is ",
        "needed" if wind.vortex_check_needed else "not needed",
        " (h/b ",
        _fixed(shaft.height.value / shaft.outer_diameter.value, 1),
        " is under 6).",
        sep="",
    )
    print(
        "Base: shear ",
        _fixed(wind.base_shear.value / 1000.0, 0),
        " kN, moment ",
        _fixed(wind.base_moment.value / 1.0e6, 2),
        " MN m. At the design level: compression ",
        _fixed(check.maximum_stress.value / 1.0e6, 2),
        " MPa of ",
        _fixed(check.design_strength.value / 1.0e6, 2),
        " (",
        _fixed(100.0 * check.compression_utilization, 0),
        " percent), no tension (",
        "yes" if check.tension_free else "NO",
        "), shear ",
        _fixed(100.0 * check.shear_utilization, 0),
        " percent, overturning ",
        _fixed(100.0 * check.overturning_utilization, 0),
        " percent.",
        sep="",
    )


def _report_arch() raises:
    var plan = wijnendale_plan()
    var arch = bridge_arch(plan)
    var check = arch_check(arch)
    _title("Arch of the bridge, Heyman's limit analysis")
    print(
        "A semicircular ring of mean radius ",
        _fixed(arch.mean_radius.value, 2),
        " m and thickness ",
        _fixed(arch.thickness.value, 2),
        " m: t/R is ",
        _fixed(check.ratio, 3),
        ". A ring of uniform thickness stands down to ",
        _fixed(check.minimum_ratio, 4),
        " of the radius under its own weight.",
        sep="",
    )
    print(
        "Geometrical factor of safety ",
        _fixed(check.geometric_factor, 2),
        ". Horizontal thrust ",
        _fixed(check.least_thrust.value / 1000.0, 1),
        " to ",
        _fixed(check.greatest_thrust.value / 1000.0, 1),
        " kN per meter of width; the springing carries ",
        _fixed(check.springing_force.value / 1000.0, 1),
        " kN/m, ",
        _fixed(100.0 * check.crushing_utilization, 1),
        " percent of the strength of the masonry.",
        sep="",
    )


def _report_wall() raises:
    var plan = wijnendale_plan()
    var wall = quay_wall(plan)
    _title("Quay wall as a gravity wall")
    print(
        "A brick wall ",
        _fixed(wall.thickness.value, 1),
        " m thick (assumed) and ",
        _fixed(wall.height.value, 2),
        " m high holds ",
        _fixed(wall.retained.value, 2),
        " m of earth, with the moat in front of it.",
        sep="",
    )
    var cases = [moat_full(plan), moat_drawn_down(plan)]
    var names = ["moat full", "moat drawn down"]
    for at in range(2):
        var stable = wall_stability(wall, cases[at])
        var least = least_thickness(wall, cases[at])
        print(
            "  ",
            names[at],
            ": overturning factor ",
            _fixed(stable.overturning_factor, 2),
            ", sliding factor ",
            _fixed(stable.sliding_factor, 2),
            ", free-standing wall needs ",
            _fixed(least.value, 1),
            " m.",
            sep="",
        )
    print(
        "The thickness of 0.9 m is a facing. The earth is held by ties,",
        " counterforts or the foundations of the buildings.",
        sep="",
    )


def main() raises:
    var destination = example_destination(String(DEFAULT_OUTPUT))
    var plan = wijnendale_plan()
    var day = day_of_year(YEAR, 10, 19)

    _report_site()

    var renderer = castle_renderer(WIDTH, HEIGHT)
    var eye = Vector3(-30, 49, 16)
    var castle = build_castle_scene(
        plan,
        SceneSettings(
            256,
            64,
            2048,
            True,
            String("assets/pebbles.jpg"),
            Length64(1.0, METER),
        ),
        Float64(eye.x),
        Float64(-eye.z),
        45.0,
    )
    var camera = gallery_camera(
        WIDTH,
        HEIGHT,
        eye,
        Vector3(32, 20, -42),
        field_of_view=Angle(58.0, DEGREE),
        near=Length(1.0, METER),
        far=Length(6000.0, METER),
    )

    var moat = wijnendale_moat(plan)
    var weather = DayWeather(
        Length64(RAIN_MM / 1000.0), Length64(EVAPORATION_MM / 1000.0)
    )
    var level = plan.moat.water_level

    _title("The sun, the shadows and the moat, hour by hour")
    print(
        "  time  height  bearing  donjon shadow   tip toward  courtyard in sun",
        "  moat (m TAW)  weir (L/s)",
        sep="",
    )
    var frame_clock = Clock()
    frame_clock.start()
    var frames = List[Framebuffer]()
    for hour in range(FIRST_HOUR, LAST_HOUR + 1):
        var hours_utc = Float64(hour - LOCAL_OFFSET)
        var sun = solar_position(latitude(), longitude(), YEAR, day, hours_utc)
        var toward = sun.toward()
        aim_sun(
            castle,
            renderer,
            Vector3(
                Float32(toward[0]), Float32(toward[2]), Float32(-toward[1])
            ),
        )
        advance_water(castle, 1.0)
        # The eye adapts: the lower the sun, the more the exposure opens.
        var height = sun.altitude.to(DEGREE64)
        var open = 1.0 - _smooth(height / 20.0)
        renderer.tone_mapping_exposure = Float32(0.55 * (1.0 + 1.2 * open))
        frames.append(draw_castle(castle, renderer, camera, 0.55, 5))
        var shadow = donjon_shadow(plan, sun)
        var share = lit_fraction(plan, sun, Length64(2.0, METER))
        level = moat.step(level, weather, Duration64(3600.0))
        print(
            _left(_clock(hours_utc * 3600.0), 6),
            _left(_fixed(sun.altitude.to(DEGREE64), 1), 7),
            _left(_fixed(sun.azimuth.to(DEGREE64), 0), 9),
            _left(_fixed(shadow[0].value, 1) + " m", 13),
            _left(_compass(_heading(shadow[1].value, shadow[2].value)), 14),
            _left(_fixed(100.0 * share, 0) + " %", 18),
            _left(_fixed(level.value, 3), 14),
            _left(_fixed(moat.weir.discharge(level).value * 1000.0, 1), 12),
            sep="",
        )

    _report_wind()
    _report_arch()
    _report_wall()
    var written = moat.weir.discharge(level).value
    _title("Moat water balance")
    print(
        "The moat holds ",
        _fixed(moat.storage(level, Length64(plan.moat.bed().value)), 0),
        " m3 on ",
        _fixed(moat.area.value, 0),
        " m2. A weir of ",
        _fixed(moat.weir.width.value, 1),
        " m (assumed) passes ",
        _fixed(written * 1000.0, 1),
        " L/s, so the water is renewed in ",
        _fixed(
            moat.residence_time(level, Length64(plan.moat.bed().value)).value
            / 86400.0,
            1,
        ),
        " days.",
        sep="",
    )
    write_example(frames, destination, DELAY_MS, len(frames), frame_clock)
