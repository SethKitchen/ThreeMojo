# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Wijnendale Castle through a day, and what an engineer reads from it.

    mojo run -I . examples/wijnendale_simulation.mojo [path.png [survey.json]]

The page is Castle. The frames are 19 October from the morning to the
evening. Each frame puts the sun where the equations of Duffie and Beckman
put it over Torhout, so the shadow of the keep sweeps across the courtyard
and the moat as the day goes on. The sky, the colour of the light and the
mirror of the moat follow the sun.

The program prints what the analysis modules find for the same plan: the
shadows of the keep, the wind on the keep, the line of thrust in a bridge
arch, the wall at the edge of the moat and the water balance of the moat in
a normal year and in a dry one. It also prints how the keep and the arch
answer when every length of the plan is 15 percent too small or too large.

Every dimension of the built-in plan is an estimate. A second argument names a
JSON file of surveyed dimensions, in the form of `plan_to_json`. The program
then uses the survey in place of the estimate.
"""

from tools._example_output import (
    example_destination,
    gallery_camera,
    gallery_renderer,
    write_frames,
)

from cameras.perspective_camera import PerspectiveCamera
from core.assets import Assets
from core.fog import linear_fog
from core.object3d import NodeId, Object3D
from core.scene import Scene
from extensions.castle.arch import analyze_bridge
from extensions.castle.masonry import clay_brick_masonry
from extensions.castle.plan import CastlePlan, PlanPoint, wijnendale
from extensions.castle.survey import plan_from_json
from extensions.castle.render import CastleOptions, add_castle
from extensions.castle.sun import (
    castle_sun,
    day_length,
    scene_direction,
    shadow_length,
)
from extensions.castle.wall import GravityWall, check_wall, required_thickness
from extensions.castle.water_balance import (
    Weir,
    flanders_climate,
    required_inflow,
    simulate_year,
)
from extensions.castle.wind import (
    check_tower_base,
    cantilever_frequency,
    flanders_wind,
    tower_wind_load,
)
from extensions.energy.solar import SunPosition, day_of_year
from extensions.geotech.quantities import (
    KILONEWTON_PER_CUBIC_METER,
    UnitWeight64,
)
from geometries.plane import plane
from lights.light import ambient_light, directional_light
from lights.shadow import PCF_SOFT_SHADOW_MAP
from math.vector3 import Vector3
from objects.reflector import Reflector
from objects.sky import Sky
from render.framebuffer import Color, Framebuffer
from render.tonemap import ACES_FILMIC_TONE_MAPPING
from std.math import floor
from std.pathlib import Path
from std.sys import argv
from units.si import (
    Angle,
    Angle64,
    DEGREE,
    DEGREE64,
    Duration64,
    Force64,
    HOUR,
    KILONEWTON,
    KILONEWTON_METER,
    KILOPASCAL,
    Length,
    Length64,
    MEGAPASCAL,
    METER,
    METER_PER_SECOND,
    Pressure64,
    Velocity64,
)

comptime DEFAULT_OUTPUT = "out/castle-simulation.png"
comptime WIDTH = 256
comptime HEIGHT = 320
comptime FRAMES = 12
comptime DELAY_MS = 400
# Belgian clocks are two hours ahead of Greenwich until the last Sunday of
# October, which was 25 October in 2026.
comptime ZONE_HOURS = 2.0
comptime FIRST_HOUR = 9.0
comptime LAST_HOUR = 17.75


def _round(value: Float64, places: Int) -> Float64:
    """Return a number rounded to some decimal places, for printing."""
    var scale = 1.0
    for _ in range(places):
        scale *= 10.0
    var shifted = value * scale
    if shifted < 0.0:
        return -floor(-shifted + 0.5) / scale
    return floor(shifted + 0.5) / scale


def _clock(hours: Float64) -> String:
    """Return a time of day as hours and minutes, such as 15:30."""
    var whole = Int(floor(hours))
    var minutes = Int(floor((hours - Float64(whole)) * 60.0 + 0.5))
    var pad = String("")
    if minutes < 10:
        pad = "0"
    return String(whole, ":", pad, minutes)


def _mix(low: Float64, high: Float64, t: Float64) -> Float64:
    """Return a point between two numbers."""
    return low + (high - low) * t


def _byte(value: Float64) -> UInt8:
    """Return a number from 0 to 255 as a byte."""
    return UInt8(Int(max(0.0, min(255.0, value))))


def _report(plan: CastlePlan, day: Int) raises:
    """Print the engineering results for the plan."""
    var zone = Duration64(ZONE_HOURS, HOUR)
    print(plan.name, "-", "19 October, day", day)
    print(
        "  site:",
        _round(plan.latitude.to(DEGREE64), 4),
        "N,",
        _round(plan.longitude.to(DEGREE64), 4),
        "E; day length",
        _round(day_length(plan.latitude, day).to(HOUR), 2),
        "h",
    )
    print(
        "  the sun, and the shadow of the keep (", plan.tallest().value, "m ):"
    )
    for k in range(FRAMES):
        var hours = _hour(k)
        var sun = castle_sun(plan, day, Duration64(hours, HOUR), zone)
        var altitude = sun.altitude().to(DEGREE64)
        var line = String("   ", _clock(hours), "  altitude ")
        line += String(_round(altitude, 1), " deg, azimuth ")
        line += String(_round(sun.azimuth.to(DEGREE64), 1), " deg")
        if sun.is_up():
            line += String(
                ", shadow ",
                _round(shadow_length(plan.tallest(), sun).value, 1),
                " m",
            )
        print(line)

    var keep = plan.towers[_tallest_tower(plan)].copy()
    var masonry = clay_brick_masonry()
    var wind = flanders_wind()
    var load = tower_wind_load(wind, keep)
    var base = check_tower_base(
        keep, masonry, wind, Force64(300.0, KILONEWTON), 2.2
    )
    print("  keep, wind of 26 m/s in open country:")
    print(
        "   wind force",
        _round(load.force.to(KILONEWTON), 0),
        "kN, moment",
        _round(load.moment.to(KILONEWTON_METER), 0),
        "kN m, first natural frequency",
        _round(cantilever_frequency(keep, masonry).value, 2),
        "Hz",
    )
    print(
        "   base stress",
        _round(base.windward.to(MEGAPASCAL), 2),
        "to",
        _round(base.leeward.to(MEGAPASCAL), 2),
        "MPa against a design strength of",
        _round(masonry.design_strength(2.2).to(MEGAPASCAL), 2),
        "MPa; utilization",
        _round(base.utilization, 2),
        ", equilibrium ratio",
        _round(base.equ_ratio, 1),
        ", passes",
        base.passes(),
    )

    var fill = UnitWeight64(19.0, KILONEWTON_PER_CUBIC_METER)
    var arch = analyze_bridge(
        plan.bridge, masonry, fill, Pressure64(5.0, KILOPASCAL), 24
    )
    print("  bridge arch, limit analysis with a deck load of 5 kPa:")
    print(
        "   a line of thrust fits:",
        arch.safe,
        "; horizontal thrust",
        _round(arch.thrust_min.to(KILONEWTON), 0),
        "to",
        _round(arch.thrust_max.to(KILONEWTON), 0),
        "kN; geometric factor",
        _round(arch.geometric_factor, 1),
        "; least ring",
        _round(arch.minimum_thickness.value * 1000.0, 0),
        "mm of",
        _round(plan.bridge.ring.value * 1000.0, 0),
        "mm",
    )

    var height = plan.moat.depth + Length64(plan.moat.freeboard.value, METER)
    var wall = GravityWall(
        height,
        Length64(1.0, METER),
        masonry.copy(),
        UnitWeight64(18.0, KILONEWTON_PER_CUBIC_METER),
        Angle64(30.0, DEGREE64),
        0.4,
        Pressure64(5.0, KILOPASCAL),
        Pressure64(150.0, KILOPASCAL),
    )
    var full = Length64(plan.moat.depth.value, METER)
    var empty = Length64(0.0, METER)
    var full_wall = required_thickness(wall, full, full)
    var drained = required_thickness(wall, full, empty)
    print("  wall at the edge of the moat,", _round(height.value, 1), "m high:")
    print(
        "   least thickness with the moat full",
        _round(full_wall.value, 2),
        "m and with the moat drained",
        _round(drained.value, 2),
        "m (a plain gravity wall, with no buttress and no backing)",
    )
    var thin = wall.copy()
    thin.thickness = Length64(1.0, METER)
    var one_meter = check_wall(thin, full, empty)
    print(
        "   a wall of 1 m, drained: overturning",
        _round(one_meter.overturning, 2),
        ", sliding",
        _round(one_meter.sliding, 2),
        ", governs by",
        one_meter.governing().name(),
    )

    var climate = flanders_climate()
    var weir = Weir(Length64(1.5, METER), 0.62)
    var leakage = Velocity64(2.0e-8, METER_PER_SECOND)
    var normal = simulate_year(plan.moat, climate, weir, leakage, 1.0, 1.0)
    var dry = simulate_year(plan.moat, climate, weir, leakage, 0.6, 0.0)
    print("  moat of", _round(plan.moat.water_area().value, 0), "m2:")
    print(
        "   normal year: lowest level",
        _round(normal.lowest().value * 100.0, 0),
        "cm below the weir crest, spill",
        _round(normal.spilled.value, 0),
        "m3",
    )
    print(
        "   dry year with the stream failed: lowest level",
        _round(dry.lowest().value * 100.0, 0),
        "cm below the crest, more than 10 cm down on",
        dry.days_below(Length64(0.1, METER)),
        "days; the stream must give",
        _round(
            required_inflow(plan.moat, climate, leakage, 6, 0.6).value * 1000.0,
            2,
        ),
        "L/s in July",
    )


def _tallest_tower(plan: CastlePlan) -> Int:
    """Return the place of the tallest tower, the keep."""
    var best = 0
    for i in range(len(plan.towers)):
        if plan.towers[i].apex() > plan.towers[best].apex():
            best = i
    return best


def _plan() raises -> CastlePlan:
    """Return the plan: a survey if a file is named, else the estimate."""
    var args = argv()
    if len(args) > 2:
        return plan_from_json(Path(String(args[2])).read_text())
    return wijnendale()


def _sensitivity(plan: CastlePlan) raises:
    """Print the keep and the arch with every length scaled by a factor."""
    var masonry = clay_brick_masonry()
    var wind = flanders_wind()
    var fill = UnitWeight64(19.0, KILONEWTON_PER_CUBIC_METER)
    print("  every length of the plan scaled, for the error of the estimate:")
    for factor in [0.85, 1.0, 1.15]:
        var scaled = plan.scaled(factor)
        var keep = scaled.towers[_tallest_tower(scaled)].copy()
        var base = check_tower_base(
            keep, masonry, wind, Force64(300.0, KILONEWTON), 2.2
        )
        var arch = analyze_bridge(
            scaled.bridge, masonry, fill, Pressure64(5.0, KILOPASCAL), 24
        )
        print(
            "   x",
            factor,
            ": keep",
            _round(keep.height.value, 1),
            "m, use of the strength",
            _round(base.utilization, 2),
            ", equilibrium ratio",
            _round(base.equ_ratio, 1),
            "; arch geometric factor",
            _round(arch.geometric_factor, 1),
        )


def _hour(frame: Int) -> Float64:
    """Return the clock time of a frame."""
    return _mix(FIRST_HOUR, LAST_HOUR, Float64(frame) / Float64(FRAMES - 1))


def _camera() raises -> PerspectiveCamera:
    """Return the camera, above the front of the moat and looking north."""
    return gallery_camera(
        WIDTH,
        HEIGHT,
        Vector3(6, 50, 108),
        Vector3(13, 8, -2),
        field_of_view=Angle(55.0, DEGREE),
        near=Length(1.0, METER),
        far=Length(4000.0, METER),
    )


def main() raises:
    var destination = example_destination(String(DEFAULT_OUTPUT))
    var plan = _plan()
    var day = day_of_year(10, 19)
    _report(plan, day)
    _sensitivity(plan)

    var assets = Assets()
    var scene = Scene()
    var options = CastleOptions.default()
    options.water = False
    options.trees = 360
    options.clearing = PlanPoint(Length64(6.0, METER), Length64(-108.0, METER))
    options.clearing_radius = Length64(58.0, METER)
    _ = add_castle(scene, assets, plan, options)

    var dome = Object3D()
    dome.set_scale(4400, 4400, 4400)
    var sky_node = scene.add(dome^)
    var sky = Sky(assets, sky_node)
    scene.add_mesh(sky.mesh)
    assets.programs.get(sky.program).set_uniform("turbidity", Float32(2.5))
    assets.programs.get(sky.program).set_uniform("rayleigh", Float32(1.6))
    assets.materials.materials[sky.mesh.material.value].fog = False

    var water = Object3D()
    water.rotate_x(Angle(-90.0, DEGREE))
    water.set_position(
        Float32(plan.moat.center.x.value),
        Float32(-plan.moat.freeboard.value),
        Float32(-plan.moat.center.y.value),
    )
    var water_node = scene.add(water^)
    var mirror = Reflector(
        assets,
        assets.geometries.add(
            plane(Length(130.0, METER), Length(110.0, METER))
        ),
        water_node,
        color=Color(104, 128, 126),
        texture_width=WIDTH,
        texture_height=HEIGHT,
        multisample=0,
    )
    scene.add_mesh(mirror.mesh)

    var lamp = Object3D()
    lamp.set_position(0, 160, 0)
    var lamp_node = scene.add(lamp^)
    var sun_light = directional_light(Color(255, 232, 196), lamp_node, 3.4)
    sun_light.cast_shadow = True
    sun_light.shadow.map_size = 1024
    sun_light.shadow.bias = -0.0005
    sun_light.shadow.normal_bias = 0.15
    sun_light.shadow.set_extent(Length(70.0, METER))
    sun_light.shadow.near = Length(40.0, METER)
    sun_light.shadow.far = Length(300.0, METER)
    scene.add_light(sun_light)
    scene.add_light(ambient_light(Color(176, 198, 232), 0.75))

    var haze = Color(176, 192, 208)
    scene.fog = linear_fog(haze, Length(300.0, METER), Length(3000.0, METER))
    var renderer = gallery_renderer(WIDTH, HEIGHT, haze)
    renderer.shadow_map_type = PCF_SOFT_SHADOW_MAP
    renderer.set_tone_mapping(ACES_FILMIC_TONE_MAPPING, Float32(0.8))
    var camera = _camera()

    var frames = List[Framebuffer]()
    for k in range(FRAMES):
        var sun = castle_sun(
            plan,
            day,
            Duration64(_hour(k), HOUR),
            Duration64(ZONE_HOURS, HOUR),
        )
        _light(scene, assets, sky, lamp_node, sun)
        scene.update()
        _ = mirror.update(renderer, scene, assets, camera)
        frames.append(renderer.render(scene, assets, camera))
    write_frames(frames, destination, DELAY_MS, FRAMES)


def _light(
    mut scene: Scene,
    mut assets: Assets,
    sky: Sky,
    lamp: NodeId,
    sun: SunPosition,
) raises:
    """Move the sun and tint its light by how high it stands."""
    var toward = scene_direction(sun)
    var warm = max(0.0, min(1.0, (sun.altitude().to(DEGREE64) - 3.0) / 25.0))
    var vector = Vector3(
        Float32(toward.x), Float32(toward.y), Float32(toward.z)
    )
    assets.programs.get(sky.program).set_uniform("sunPosition", vector)
    scene.node(lamp).set_position(
        vector.x * 160, vector.y * 160, vector.z * 160
    )
    scene.lights[0].color = Color(
        255,
        _byte(_mix(150.0, 232.0, warm)),
        _byte(_mix(90.0, 196.0, warm)),
    )
    scene.lights[0].intensity = Float32(_mix(1.8, 3.4, warm))
    scene.lights[1].intensity = Float32(_mix(1.0, 0.75, warm))
