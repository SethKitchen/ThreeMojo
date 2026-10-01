# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""CARLA rendering: the town, the props, the actors and the camera.

The world stands on `assets/carla/town.xodr`. Its road 1 runs east from
the origin with a 3.5 m driving lane and a 2 m sidewalk on each side, so
the outer edge of a side is 5.5 m from the reference line. It has a
traffic light (signal 1001), a stop sign (1002), a yield sign (1003) and
a speed limit (1004) whose empty subtype CARLA gives no sign.

The expected numbers come from the file, from hand geometry, from
CARLA's attribute defaults in its blueprint library, and from this
port's documented choices, such as `LAMP_GLOW` and `BRAKE_GLOW`. The
images are drawn small, one worker, so that the suite stays quick.
"""

from core.assets import Assets
from core.buffer_geometry import NORMAL, POSITION
from core.scene import Scene
from extensions.carla.actor import ActorId, GREEN, OFF, RED, YELLOW
from extensions.carla.blueprint import (
    ATTRIBUTE_BOOL,
    ATTRIBUTE_FLOAT,
    ATTRIBUTE_INT,
    ATTRIBUTE_STRING,
    ActorAttributeValue,
)
from extensions.carla.assets import AssetRegistry, parse_manifest
from test_carla_assets import town_registry
from extensions.carla.bounding_box import BoundingBox
from extensions.carla.camera_render import (
    CarlaRenderer,
    ExposureMode,
    HISTOGRAM_EXPOSURE,
    LUMINANCE_SCALE,
    MANUAL_EXPOSURE,
    camera_ev100,
    camera_exposure,
    camera_passes,
    ev100_exposure,
    metered_ev100,
    rgb_camera_settings,
    vertical_fov,
    white_balance,
)
from extensions.carla.map import Map, Waypoint
from extensions.carla.map_builder import MapBuilder
from extensions.carla.mesh_factory import (
    CROSSWALK_SURFACE,
    CURB_SURFACE,
    ROAD_SURFACE,
    SIDEWALK_SURFACE,
    SurfaceKind,
    WALL_SURFACE,
    WHITE_MARK_SURFACE,
    YELLOW_MARK_SURFACE,
)
from extensions.carla.opendrive import load_opendrive_file
from extensions.carla.props import (
    LAMP_GLOW,
    MAX_REACH,
    PropKind,
    Props,
    SPEED_LIMIT_PROP,
    STOP_PROP,
    TRAFFIC_LIGHT_PROP,
    YIELD_PROP,
    lamp_intensity,
    prop_kind_of,
    signal_facing,
    signal_prop,
    signal_props,
)
from extensions.carla.render_actors import (
    ActorVisuals,
    BRAKE_GLOW,
    BodyStyle,
    DEFAULT_PAINT,
    HATCHBACK,
    HIGH_BEAM_GLOW,
    HIGH_BEAM_LIGHT,
    LOW_BEAM_GLOW,
    LOW_BEAM_LIGHT,
    POSITION_GLOW,
    SEDAN,
    SUV,
    TAIL_GLOW,
    VAN,
    beam_intensity,
    body_geometry,
    body_profile,
    body_style_of,
    cabin_geometry,
    car_paint,
    clothing,
    headlight_glow,
    loft,
    stride,
    superellipse,
    tail_light_glow,
    vehicle_color,
    vehicle_model,
    wheel_inset,
)
from extensions.carla.road_info import (
    JuncId,
    LANE_NONE,
    LANE_SIDEWALK,
    LaneId,
    RoadId,
    SectionId,
    SignalId,
)
from extensions.carla.sensor import (
    BUILDING,
    CAR,
    PEDESTRIAN,
    POLE,
    ROAD,
    ROAD_LINE,
    SIDEWALK,
    SKY,
    SemanticTag,
    TERRAIN,
    TRAFFIC_LIGHT,
    TRAFFIC_SIGN,
    VEGETATION,
    WALL,
    cityscapes_color,
    decode_depth,
)
from extensions.carla.town import (
    GROUND_FLOOR,
    LAMP_GLOW as TOWN_LAMP_GLOW,
    LAMP_INTENSITY,
    PARAPET,
    Town,
    TownMaterials,
    TownSettings,
    WINDOW_GLOW,
    building_geometry,
    building_lots,
    crosswalk_stripes,
    lamp_posts,
    lumpy_crown,
    road_bounds,
    roadside,
    skyline_lots,
    surface_color,
    surface_roughness,
    town_kind_casts,
    town_kind_tag,
    wet_color,
    _clear_of_roads,
)
from extensions.carla.render_weather import WetSurface
from extensions.carla.render_sky import (
    GROUND,
    NIGHT_ZENITH,
    cloud_density,
    sky_texel,
)
from extensions.carla.render_weather import SkySettings
from extensions.carla.transform import CarlaRotation, CarlaTransform
from extensions.carla.vehicle import (
    LIGHT_BRAKE,
    LIGHT_HIGH_BEAM,
    LIGHT_LOW_BEAM,
    LIGHT_POSITION,
    VehicleLightState,
)
from extensions.carla.weather import WeatherParameters, weather_preset
from extensions.carla.world import EpisodeSettings, World
from math.bounds import Box3
from math.noise import ImprovedNoise
from math.vector3 import Vector3
from postprocessing.composer import (
    BLOOM,
    CHROMATIC_ABERRATION,
    LENSFLARE,
    MOTION_BLUR,
    RENDER,
    SSR_NODE,
)
from render.color_utils import kelvin_color
from render.framebuffer import Color, FloatColor
from std.math import atan, log2, pi, pow, sqrt
from std.os import makedirs
from std.pathlib import Path
from std.testing import (
    TestSuite,
    assert_almost_equal,
    assert_equal,
    assert_false,
    assert_raises,
    assert_true,
)
from units.photometry import NIT
from units.si import DEGREE, METER, SECOND, Angle, Duration, Length
from units.temperature import KELVIN, Temperature


def _same(a: Color, b: Color) raises:
    assert_equal(Int(a.r), Int(b.r))
    assert_equal(Int(a.g), Int(b.g))
    assert_equal(Int(a.b), Int(b.b))


def _map() raises -> Map:
    return load_opendrive_file("assets/carla/town.xodr")


def _path_map() raises -> Map:
    """Return a 10 m road with a 2 m sidewalk on its right and nothing
    else: no driving lane, no mark, no crosswalk and no signal."""
    var builder = MapBuilder()
    var road = builder.add_road(
        RoadId(1), "path", 10.0, JuncId(-1), RoadId(0), RoadId(0), True
    )
    builder.add_road_geometry_line(road, 0.0, 0.0, 0.0, 0.0, 10.0)
    _ = builder.add_road_section(road, SectionId(0), 0.0)
    _ = builder.add_road_section_lane(
        road, 0, LaneId(0), LANE_NONE, False, LaneId(0), LaneId(0)
    )
    _ = builder.add_road_section_lane(
        road, 0, LaneId(-1), LANE_SIDEWALK, False, LaneId(0), LaneId(0)
    )
    builder.create_lane_width(
        builder.lane(RoadId(1), LaneId(0), 0.0), 0.0, 0.0, 0, 0, 0
    )
    builder.create_lane_width(
        builder.lane(RoadId(1), LaneId(-1), 0.0), 0.0, 2.0, 0, 0, 0
    )
    builder.create_section_offset(road, 0.0, 0, 0, 0, 0)
    builder.add_road_elevation_profile(road, 0.0, 0, 0, 0, 0)
    return builder.build()


def _small() -> TownSettings:
    var s = TownSettings()
    s.texture_size = 8
    s.resolution = Length(2, METER)
    return s^


def _attribute(id: String, value: String) -> ActorAttributeValue:
    var type = ATTRIBUTE_FLOAT
    if id == "image_size_x" or id == "image_size_y" or id == "blade_count":
        type = ATTRIBUTE_INT
    elif id == "enable_postprocess_effects":
        type = ATTRIBUTE_BOOL
    elif id == "exposure_mode" or id == "camera_model":
        type = ATTRIBUTE_STRING
    return ActorAttributeValue(id, type, value)


# The town.


def test_materials_by_surface_kind() raises:
    # The textured road and concrete are white under their maps; paint is
    # off-white or yellow; a wall is a darker gray.
    _same(surface_color(ROAD_SURFACE), Color(255, 255, 255))
    _same(surface_color(SIDEWALK_SURFACE), Color(255, 255, 255))
    _same(surface_color(WALL_SURFACE), Color(170, 166, 160))
    _same(surface_color(CROSSWALK_SURFACE), Color(226, 226, 220))
    _same(surface_color(WHITE_MARK_SURFACE), Color(226, 226, 220))
    _same(surface_color(YELLOW_MARK_SURFACE), Color(226, 170, 40))
    assert_equal(surface_roughness(ROAD_SURFACE), 1)
    assert_equal(surface_roughness(CURB_SURFACE), 1)
    assert_almost_equal(surface_roughness(YELLOW_MARK_SURFACE), 0.55)
    with assert_raises(contains="one of the seven"):
        _ = surface_color(SurfaceKind(9))
    with assert_raises(contains="one of the seven"):
        _ = surface_roughness(SurfaceKind(-1))
    with assert_raises(contains="no material"):
        _ = TownMaterials().surface(ROAD_SURFACE)
    with assert_raises(contains="no material"):
        _ = TownMaterials().surface(SurfaceKind(12))


def test_wet_color_darkens_in_linear_light() raises:
    var gray = Color(200, 100, 0)
    _same(wet_color(gray, WetSurface(0, 0)), gray)
    # (200 / 255)^2.2 * 0.55, back through 1 / 2.2: 152.4, worked in
    # Python.
    var wet = wet_color(gray, WetSurface(1, 0))
    assert_equal(Int(wet.r), 152)
    assert_equal(Int(wet.g), 76)
    assert_equal(Int(wet.b), 0)


def test_roadside() raises:
    var map = _map()
    ref road = map.road(RoadId(1))
    # The right side's outer edge is 5.5 m right of the reference line:
    # CARLA's plus y.
    var right = roadside(road, 10, True).value()
    assert_almost_equal(right[0].x, 10, atol=1e-3)
    assert_almost_equal(right[0].y, 5.5, atol=1e-3)
    assert_almost_equal(right[1].y, 1, atol=1e-5)
    var left = roadside(road, 10, False).value()
    assert_almost_equal(left[0].y, -5.5, atol=1e-3)
    assert_almost_equal(left[1].y, -1, atol=1e-5)
    # Road 3 has lanes on its right only.
    assert_false(Bool(roadside(map.road(RoadId(3)), 5, False)))


def test_lots_and_lamps() raises:
    var map = _map()
    var lots = building_lots(map, _small())
    assert_true(len(lots) > 0)
    for lot in lots:
        # Every lot stands clear of the lanes: 4 m back, 12 m deep.
        var found = map.closest_waypoint_on_road(lot.center)
        var at = map.compute_transform(found.value()).location
        var gap = Vector3(at.x - lot.center.x, at.y - lot.center.y, 0)
        assert_true(gap.length() > 5)
        assert_true(lot.height.to(METER) >= 6 and lot.height.to(METER) < 24)
    assert_true("Lot(" in String(lots[0]))
    var posts = lamp_posts(map, Length(24, METER))
    # Road 1 is 60 m long: lamps at 12, 36 and 60 m less than 60, on each
    # side; the first on the right stands 0.4 m in from the edge.
    var first = posts[0]
    assert_almost_equal(first.foot.x, 12, atol=1e-3)
    assert_almost_equal(first.foot.y, 5.1, atol=1e-3)
    assert_almost_equal(first.inward.y, -1, atol=1e-5)
    with assert_raises(contains="positive spacing"):
        _ = lamp_posts(map, Length(0, METER))


def test_skyline() raises:
    var bounds = Box3(Vector3(-10, -10, 0), Vector3(10, 10, 0))
    var lots = skyline_lots(bounds, 4, 3)
    assert_equal(len(lots), 4)
    var corner = Float32(sqrt(200.0))
    for lot in lots:
        var reach = Vector3(lot.center.x, lot.center.y, 0).length()
        assert_true(reach >= corner + 90 - 1e-3)
        assert_true(reach <= corner + 210 + 1e-3)
        assert_true(lot.height.to(METER) >= 20)
    with assert_raises(contains="at least one"):
        _ = skyline_lots(bounds, 0, 3)


def test_crosswalk_stripes() raises:
    # A 3 m by 12 m outline: stripes at 0.25, 1.25, ... 11.25 m along the
    # long side, 0.5 m wide: twelve stripes of two triangles.
    var zones: List[Vector3] = [
        Vector3(0, 0, 0),
        Vector3(0, 12, 0),
        Vector3(3, 12, 0),
        Vector3(3, 0, 0),
        Vector3(0, 0, 0),
    ]
    var stripes = crosswalk_stripes(zones)
    assert_equal(len(stripes.index), 72)
    assert_equal(stripes.groups[0].material_index, CROSSWALK_SURFACE.material())
    # The other turn faces up too, as does the long side first.
    var turned: List[Vector3] = [
        Vector3(0, 0, 0),
        Vector3(3, 0, 0),
        Vector3(3, 12, 0),
        Vector3(0, 12, 0),
        Vector3(0, 0, 0),
    ]
    assert_equal(len(crosswalk_stripes(turned).index), 72)
    # A triangle, or an outline that never closes, has no stripes.
    var odd: List[Vector3] = [
        Vector3(0, 0, 0),
        Vector3(0, 12, 0),
        Vector3(3, 12, 0),
        Vector3(0, 0, 0),
        Vector3(5, 5, 0),
    ]
    assert_equal(len(crosswalk_stripes(odd).index), 0)
    assert_equal(len(crosswalk_stripes(List[Vector3]()).index), 0)


def test_building_geometry() raises:
    var b = building_geometry(
        Length(10, METER), Length(8, METER), Length(12, METER)
    )
    # Four upper walls, the roof, four shop fronts, then the cornice and
    # four parapet walls, each a box of six faces.
    assert_equal(len(b.groups), 4)
    assert_equal(b.groups[0].count, 24)
    assert_equal(b.groups[1].count, 6)
    assert_equal(b.groups[2].count, 24)
    assert_equal(b.groups[3].count, 5 * 36)
    var box = b.bounding_box()
    assert_almost_equal(box.max.y, 12 + PARAPET.to(METER), atol=1e-5)
    assert_almost_equal(box.max.x, 5.2, atol=1e-5)
    with assert_raises(contains="ground floor"):
        _ = building_geometry(Length(10, METER), Length(8, METER), GROUND_FLOOR)
    with assert_raises(contains="positive width"):
        _ = building_geometry(
            Length(0, METER), Length(8, METER), Length(12, METER)
        )


def test_crown() raises:
    var crown = lumpy_crown(Length(1, METER), 3)
    ref p = crown.attribute_view(POSITION)
    for i in range(p.count()):
        var r = p.vector3(i).length()
        # Improved noise stays within one, so the push within 45 percent.
        assert_true(r > 0.5 and r < 1.5)
    with assert_raises(contains="positive radius"):
        _ = lumpy_crown(Length(0, METER), 3)


def test_road_bounds() raises:
    var bounds = road_bounds(_map())
    # Road 1 starts at the origin and road 2 ends 130 m east; road 6 runs
    # 200 m north, CARLA's minus y.
    assert_almost_equal(bounds.min.x, 0, atol=1e-3)
    assert_almost_equal(bounds.max.x, 130, atol=1e-3)
    assert_true(bounds.min.y < -190)


def test_town_builds_and_takes_the_weather() raises:
    var map = _map()
    var scene = Scene()
    var assets = Assets()
    var town = Town(map, scene, assets, _small())
    # One tag per mesh the town added.
    assert_equal(len(town.tags), len(scene.meshes))
    var seen = List[SemanticTag]()
    for tag in town.tags:
        seen.append(tag)
    var wanted: List[SemanticTag] = [
        ROAD,
        SIDEWALK,
        ROAD_LINE,
        TERRAIN,
        BUILDING,
        VEGETATION,
        POLE,
    ]
    for w in wanted:
        var found = False
        for t in seen:
            if t == w:
                found = True
        assert_true(found)
    # Night: the lamps light and the windows glow.
    town.set_weather(scene, assets, weather_preset("ClearNight"))
    assert_equal(scene.lights[town.lamp_lights[0]].intensity, LAMP_INTENSITY)
    assert_equal(
        assets.materials.get(town.materials.facades[0]).emissive_intensity,
        WINDOW_GLOW,
    )
    # Rain: the road is darker and smoother, with a puddle map.
    var rain = weather_preset("HardRainNoon")
    var before = assets.materials.get(town.materials.surface(ROAD_SURFACE))
    town.set_weather(scene, assets, rain)
    var road = assets.materials.get(town.materials.surface(ROAD_SURFACE))
    assert_true(road.color.r < 255)
    assert_false(road.roughness_map == before.roughness_map)
    var curb = assets.materials.get(town.materials.surface(CURB_SURFACE))
    assert_true(curb.roughness < 1)
    assert_equal(scene.lights[town.lamp_lights[0]].intensity, 0)
    # The same wetness again keeps the puddle map.
    town.set_weather(scene, assets, rain)
    var again = assets.materials.get(town.materials.surface(ROAD_SURFACE))
    assert_true(again.roughness_map == road.roughness_map)
    # Dry again: the dry map.
    town.set_weather(scene, assets, weather_preset("ClearNoon"))
    var dry = assets.materials.get(town.materials.surface(ROAD_SURFACE))
    assert_true(dry.roughness_map == town.asphalt_roughness_id)


def test_a_bare_town() raises:
    var settings = _small()
    settings.buildings = False
    settings.trees = False
    settings.lamps = False
    var scene = Scene()
    var assets = Assets()
    var town = Town(_map(), scene, assets, settings^)
    assert_equal(len(town.lamp_lights), 0)
    town.set_weather(scene, assets, weather_preset("ClearNight"))


def test_a_town_on_a_path() raises:
    # No driving lane: no mark, no crosswalk, no tree and, on 10 m, no
    # lamp.
    var map = _path_map()
    var scene = Scene()
    var assets = Assets()
    var town = Town(map, scene, assets, _small())
    assert_equal(len(town.lamp_lights), 0)
    assert_equal(len(signal_props(map)), 0)
    var props = Props(map, scene, assets)
    assert_equal(len(props.tags), 0)
    with assert_raises(contains="No traffic light"):
        props.set_state(assets, SignalId("1001"), RED)
    # A world on it has no traffic light, so the town's lights stay.
    var world = World(_map())
    var town_props = Props(_map(), scene, assets)
    var path = World(_path_map())
    town_props.set_states(assets, path)
    town_props.set_states(assets, world)
    props.set_states(assets, path)
    var view = CarlaRenderer(path, _small(), 1, 8, False)
    view.update(path)
    var tags = view.semantic_tags(path)
    assert_equal(len(tags), len(view.scene.meshes))


def test_an_empty_map() raises:
    var builder = MapBuilder()
    var empty = builder.build()
    assert_true(_clear_of_roads(empty, Vector3(0, 0, 0), 1))
    assert_equal(len(building_lots(empty, _small())), 0)
    assert_equal(len(lamp_posts(empty, Length(10, METER))), 0)
    with assert_raises(contains="no roads"):
        _ = road_bounds(empty)


def test_a_light_near_the_line_has_no_arm() raises:
    var map = _map()
    map.signals[0].t = -1.5
    assert_equal(signal_prop(map, map.signals[0]).value().reach.to(METER), 0)
    var scene = Scene()
    var assets = Assets()
    var props = Props(map, scene, assets)
    assert_equal(len(props.lamps), 1)


# The props.


def test_props_at_the_signals() raises:
    var map = _map()
    var props = signal_props(map)
    # The light, the stop sign, the yield sign, and the two poles named
    # Speed_30 and Speed_STATIC_40. Signal 1004 has no subtype, so no sign.
    assert_equal(len(props), 5)
    var light = props[0].copy()
    assert_equal(light.kind, TRAFFIC_LIGHT_PROP)
    assert_equal(light.signal_id.value, "1001")
    # 8 m right of the line: the arm reaches 8 - 2 = 6 m.
    assert_almost_equal(light.reach.to(METER), 6, atol=1e-5)
    assert_almost_equal(light.height.to(METER), 3, atol=1e-5)
    # Orientation "+": it faces back along the road, toward minus x.
    assert_almost_equal(light.facing.x, -1, atol=1e-5)
    # From the right side, toward the line is minus y.
    assert_almost_equal(light.inward.y, -1, atol=1e-5)
    assert_equal(props[1].kind, STOP_PROP)
    assert_equal(props[1].reach.to(METER), 0)
    assert_equal(props[2].kind, YIELD_PROP)
    # Signal 1003 stands 6 m left of road 2: toward the line is plus y.
    assert_almost_equal(props[2].inward.y, 1, atol=1e-5)
    assert_equal(props[3].kind, SPEED_LIMIT_PROP)
    assert_true("SignalProp(" in String(light))
    # A light 20 m out reaches no further than MAX_REACH.
    var far = map.signals[0].copy()
    far.t = -20
    var held = signal_prop(map, far).value().copy()
    assert_almost_equal(held.reach.to(METER), MAX_REACH.to(METER), atol=1e-5)
    # A limit with a subtype of 30 is a speed-limit sign. Standing on the
    # line, it takes the road's right as the way in.
    var limit = map.signals[3].copy()
    assert_equal(limit.signal_id.value, "1004")
    assert_false(Bool(prop_kind_of(limit)))
    assert_false(Bool(signal_prop(map, limit)))
    limit.subtype = "30"
    assert_equal(prop_kind_of(limit).value(), SPEED_LIMIT_PROP)
    limit.transform.location.y = 0
    var on_line = signal_prop(map, limit).value().copy()
    assert_almost_equal(on_line.inward.y, 1, atol=1e-5)
    assert_true(PropKind(3).is_valid())
    assert_false(PropKind(4).is_valid())
    assert_false(PropKind(-1).is_valid())
    assert_equal(String(STOP_PROP), "PropKind(1)")


def test_lamp_states() raises:
    assert_equal(lamp_intensity(RED, RED), 1)
    assert_equal(lamp_intensity(RED, GREEN), 0)
    assert_equal(lamp_intensity(OFF, YELLOW), 0)
    with assert_raises(contains="red, yellow or green"):
        _ = lamp_intensity(RED, OFF)
    var scene = Scene()
    var assets = Assets()
    var props = Props(_map(), scene, assets)
    assert_equal(len(props.tags), len(scene.meshes))
    var set = props.lamps[0].copy()
    props.set_state(assets, SignalId("1001"), GREEN)
    assert_equal(assets.materials.get(set.green).emissive_intensity, LAMP_GLOW)
    assert_equal(assets.materials.get(set.red).emissive_intensity, 0)
    props.set_state(assets, SignalId("1001"), YELLOW)
    assert_equal(assets.materials.get(set.yellow).emissive_intensity, LAMP_GLOW)
    assert_equal(assets.materials.get(set.green).emissive_intensity, 0)
    with assert_raises(contains="No traffic light"):
        props.set_state(assets, SignalId("1002"), RED)


# The actors.


def test_lamps_follow_the_light_state() raises:
    assert_equal(headlight_glow(VehicleLightState(0)), 0)
    assert_equal(headlight_glow(LIGHT_POSITION), POSITION_GLOW)
    assert_equal(headlight_glow(LIGHT_LOW_BEAM), LOW_BEAM_GLOW)
    assert_equal(
        headlight_glow(LIGHT_LOW_BEAM | LIGHT_HIGH_BEAM), HIGH_BEAM_GLOW
    )
    assert_equal(tail_light_glow(VehicleLightState(0)), 0)
    assert_equal(tail_light_glow(LIGHT_POSITION), TAIL_GLOW)
    assert_equal(tail_light_glow(LIGHT_LOW_BEAM), TAIL_GLOW)
    assert_equal(tail_light_glow(LIGHT_HIGH_BEAM), TAIL_GLOW)
    assert_equal(tail_light_glow(LIGHT_POSITION | LIGHT_BRAKE), BRAKE_GLOW)
    assert_equal(beam_intensity(LIGHT_POSITION), 0)
    assert_equal(beam_intensity(LIGHT_LOW_BEAM), LOW_BEAM_LIGHT)
    assert_equal(beam_intensity(LIGHT_HIGH_BEAM), HIGH_BEAM_LIGHT)


def test_body_styles() raises:
    assert_equal(body_style_of("vehicle.mercedes.sprinter", 2.4), VAN)
    assert_equal(body_style_of("vehicle.mini.cooper", 1.5), HATCHBACK)
    assert_equal(body_style_of("vehicle.nissan.patrol", 1.5), SUV)
    assert_equal(body_style_of("vehicle.lincoln.mkz", 1.5), SEDAN)
    assert_false(BodyStyle(4).is_valid())
    assert_false(BodyStyle(-1).is_valid())
    assert_equal(String(VAN), "BodyStyle(3)")
    var styles: List[BodyStyle] = [SEDAN, HATCHBACK, SUV, VAN]
    for style in styles:
        var p = body_profile(style)
        # The cabin's lines run in order along the body.
        assert_true(p.cabin_start < p.roof_start)
        assert_true(p.roof_start < p.roof_end)
        assert_true(p.roof_end < p.cabin_end)
    with assert_raises(contains="one of the four"):
        _ = body_profile(BodyStyle(7))


def test_superellipse_and_loft() raises:
    assert_equal(superellipse(0, 4), 1)
    assert_equal(superellipse(1, 4), 0)
    assert_almost_equal(superellipse(0.5, 2), Float32(sqrt(0.75)), atol=1e-6)
    var g = loft(
        [Float32(-1), 1],
        [Float32(1), 1],
        [Float32(0), 0],
        [Float32(2), 2],
        0,
        8,
    )
    # Two rings of eight corners; the first corner is on plus z, at mid
    # height, with a normal out along plus z.
    assert_equal(g.attribute_view(POSITION).count(), 16)
    assert_equal(len(g.index), 8 * 6)
    var p = g.attribute_view(POSITION).vector3(0)
    assert_almost_equal(p.z, 1, atol=1e-6)
    assert_almost_equal(p.y, 1, atol=1e-6)
    assert_true(g.attribute_view(NORMAL).vector3(0).z > 0.5)
    with assert_raises(contains="two or more stations"):
        _ = loft([Float32(0)], [Float32(1)], [Float32(0)], [Float32(1)], 0, 8)
    with assert_raises(contains="two or more stations"):
        _ = loft(
            [Float32(0), 1],
            [Float32(1)],
            [Float32(0), 0],
            [Float32(1), 1],
            0,
            8,
        )
    with assert_raises(contains="two or more stations"):
        _ = loft(
            [Float32(0), 1],
            [Float32(1), 1],
            [Float32(0)],
            [Float32(1), 1],
            0,
            8,
        )
    with assert_raises(contains="two or more stations"):
        _ = loft(
            [Float32(0), 1],
            [Float32(1), 1],
            [Float32(0), 0],
            [Float32(1)],
            0,
            8,
        )
    with assert_raises(contains="four corners"):
        _ = loft(
            [Float32(0), 1],
            [Float32(1), 1],
            [Float32(0), 0],
            [Float32(1), 1],
            0,
            3,
        )


def test_body_and_cabin() raises:
    var body = body_geometry(4.8, 1.84, 1.5, SEDAN)
    var box = body.bounding_box()
    # The body stays inside its box, and its belt line is below the roof.
    assert_true(box.max.x <= 2.4 + 1e-4 and box.min.x >= -2.4 - 1e-4)
    assert_true(box.max.y < 1.0)
    assert_true(box.max.z <= 0.92 + 1e-4)
    var cabin = cabin_geometry(4.8, 1.84, 1.5, SEDAN)
    assert_equal(len(cabin.groups), 2)
    assert_true(cabin.groups[0].count > 0 and cabin.groups[1].count > 0)
    assert_almost_equal(cabin.bounding_box().max.y, 1.48, atol=1e-3)
    assert_almost_equal(wheel_inset(4.8), 0.9, atol=1e-6)
    var assets = Assets()
    var model = vehicle_model(
        assets, BoundingBox(Vector3(0, 0, 0.75), Vector3(2.4, 1, 0.75)), VAN
    )
    assert_equal(model.style, VAN)
    with assert_raises(contains="at least 1 x 0.5 x 0.8"):
        _ = vehicle_model(
            assets, BoundingBox(Vector3(0, 0, 0), Vector3(0.4, 1, 1)), SEDAN
        )
    with assert_raises(contains="at least 1 x 0.5 x 0.8"):
        _ = vehicle_model(
            assets, BoundingBox(Vector3(0, 0, 0), Vector3(2, 0.2, 1)), SEDAN
        )
    with assert_raises(contains="at least 1 x 0.5 x 0.8"):
        _ = vehicle_model(
            assets, BoundingBox(Vector3(0, 0, 0), Vector3(2, 1, 0.3)), SEDAN
        )


def test_paint_and_clothing() raises:
    var paint = car_paint(Color(200, 10, 10))
    _same(paint.color, Color(200, 10, 10))
    assert_almost_equal(paint.clearcoat, 1, atol=1e-6)
    var a = clothing(ActorId(7))
    var b = clothing(ActorId(7))
    _same(a[0], b[0])
    assert_equal(stride(0).to(DEGREE), 0)
    assert_almost_equal(stride(1).to(DEGREE), 12, atol=1e-5)
    assert_almost_equal(stride(9).to(DEGREE), 30, atol=1e-5)
    assert_equal(stride(-2).to(DEGREE), 0)


def _world(
    mut camera: ActorId, mut cars: List[ActorId], mut walker: ActorId
) raises -> World:
    var world = World(_map())
    var settings = EpisodeSettings()
    settings.synchronous_mode = True
    settings.fixed_delta_seconds = Duration(0.05, SECOND)
    _ = world.apply_settings(settings)
    var library = world.get_blueprint_library()
    var red = library.at("vehicle.lincoln.mkz")
    red.set_attribute("color", "190,30,28")
    var pose = world.map.compute_transform(
        Waypoint(RoadId(1), SectionId(0), LaneId(-1), 20.0)
    )
    pose.location.z += 0.3
    cars.append(world.spawn_actor(red, pose))
    var van = library.at("vehicle.sprinter.mercedes")
    pose = world.map.compute_transform(
        Waypoint(RoadId(1), SectionId(0), LaneId(1), 30.0)
    )
    pose.location.z += 0.3
    cars.append(world.spawn_actor(van, pose))
    # A second sedan shares the first one's model.
    pose = world.map.compute_transform(
        Waypoint(RoadId(1), SectionId(0), LaneId(-1), 45.0)
    )
    pose.location.z += 0.3
    cars.append(world.spawn_actor(library.at("vehicle.lincoln.mkz"), pose))
    pose = world.map.compute_transform(
        Waypoint(RoadId(1), SectionId(0), LaneId(-2), 26.0)
    )
    pose.location.z += 1.1
    walker = world.spawn_actor(library.at("walker.pedestrian.0015"), pose)
    pose = world.map.compute_transform(
        Waypoint(RoadId(1), SectionId(0), LaneId(2), 34.0)
    )
    pose.location.z += 1.1
    _ = world.spawn_actor(library.at("walker.pedestrian.0016"), pose)
    var bp = library.at("sensor.camera.rgb")
    bp.set_attribute("image_size_x", "16")
    bp.set_attribute("image_size_y", "12")
    camera = world.spawn_actor(
        bp,
        CarlaTransform(
            Length(8, METER),
            Length(1.75, METER),
            Length(2, METER),
            CarlaRotation(
                Angle(-5, DEGREE), Angle(0, DEGREE), Angle(0, DEGREE)
            ),
        ),
    )
    _ = world.tick()
    return world^


def test_vehicle_color() raises:
    var camera = ActorId(0)
    var cars = List[ActorId]()
    var walker = ActorId(0)
    var world = _world(camera, cars, walker)
    _same(vehicle_color(world.actor(cars[0])), Color(190, 30, 28))
    # The van's blueprint has no color attribute.
    _same(vehicle_color(world.actor(walker)), DEFAULT_PAINT)


def test_actor_visuals_follow_the_world() raises:
    var camera = ActorId(0)
    var cars = List[ActorId]()
    var walker = ActorId(0)
    var world = _world(camera, cars, walker)
    var scene = Scene()
    var assets = Assets()
    var visuals = ActorVisuals()
    visuals.sync(world, scene, assets)
    assert_equal(len(visuals.vehicles), 3)
    assert_equal(len(visuals.walkers), 2)
    # The two sedans share one model; the van has its own.
    assert_equal(len(visuals.models), 2)
    world.set_light_state(cars[0], LIGHT_LOW_BEAM | LIGHT_BRAKE)
    visuals.sync(world, scene, assets)
    var v = visuals.vehicles[0].copy()
    assert_equal(
        assets.materials.get(v.heads).emissive_intensity, LOW_BEAM_GLOW
    )
    assert_equal(assets.materials.get(v.tails).emissive_intensity, BRAKE_GLOW)
    assert_equal(scene.lights[v.beam].intensity, LOW_BEAM_LIGHT)
    # The model stands on the road where the car is.
    var at = world.get_transform(cars[0]).location
    ref node = scene.node(v.node)
    assert_almost_equal(node.position.x, at.x, atol=1e-3)
    assert_almost_equal(node.position.z, at.y, atol=1e-3)
    # Tags: a car's meshes are a car's, a walker's a pedestrian's.
    var tags = List[SemanticTag](length=len(scene.meshes), fill=SKY)
    visuals.tag_meshes(world, tags)
    assert_equal(tags[v.first_mesh], CAR)
    assert_equal(tags[visuals.walkers[0].first_mesh], PEDESTRIAN)
    var short = List[SemanticTag](length=2, fill=SKY)
    with assert_raises(contains="do not cover"):
        visuals.tag_meshes(world, short)
    # A destroyed actor's model hides, and its beam goes out.
    _ = world.destroy_actor(cars[0])
    _ = world.destroy_actor(walker)
    visuals.sync(world, scene, assets)
    assert_false(scene.node(v.node).visible)
    assert_equal(scene.lights[v.beam].intensity, 0)
    visuals.tag_meshes(world, tags)
    assert_equal(tags[v.first_mesh], CAR)


# The sky.


def test_clouds_and_sky_texels() raises:
    var noise = ImprovedNoise()
    assert_equal(cloud_density(noise, Vector3(0, -1, 0), 1), 0)
    assert_equal(cloud_density(noise, Vector3(0, 1, 0), 0), 0)
    # Full cover is cloud everywhere high enough.
    assert_almost_equal(cloud_density(noise, Vector3(0, 1, 0), 1), 1, atol=1e-6)
    var settings = SkySettings(2, 3, 0.005, 0.8, Vector3(0, 1, 0), 0)
    # Straight up on a clear day: the sky times its gain, plus the night's
    # zenith.
    var up = sky_texel(
        FloatColor(1, 1, 1),
        Vector3(0, 1, 0),
        settings,
        FloatColor(0, 0, 0),
        1,
        0,
        0.15,
        0,
    )
    assert_almost_equal(up.r, 0.15 + NIGHT_ZENITH.r, atol=1e-6)
    # Straight down: the ground, a diffuse surface, shines its light over
    # pi.
    var down = sky_texel(
        FloatColor(1, 1, 1),
        Vector3(0, -1, 0),
        settings,
        FloatColor(0, 0, 0),
        1,
        0,
        0.15,
        Float32(pi),
    )
    assert_almost_equal(down.r, GROUND.r, atol=1e-6)


# The camera.


def test_camera_defaults_are_carlas() raises:
    var s = rgb_camera_settings(List[ActorAttributeValue]())
    assert_equal(s.image_width, 800)
    assert_equal(s.image_height, 600)
    assert_almost_equal(s.fov.to(DEGREE), 90, atol=1e-5)
    assert_true(s.enable_postprocess_effects)
    assert_almost_equal(s.gamma, 2.2, atol=1e-6)
    assert_equal(s.exposure_mode, HISTOGRAM_EXPOSURE)
    assert_almost_equal(s.shutter_speed, 200, atol=1e-4)
    assert_almost_equal(s.fstop, 1.4, atol=1e-6)
    assert_almost_equal(s.bloom_intensity, 0.675, atol=1e-6)
    assert_almost_equal(s.lens_flare_intensity, 0.1, atol=1e-6)
    assert_almost_equal(s.motion_blur_intensity, 0.45, atol=1e-6)
    assert_almost_equal(s.lens.k, -1, atol=1e-6)
    assert_almost_equal(s.lens.x_size, 0.08, atol=1e-6)
    assert_almost_equal(s.temp.to(KELVIN), 6500, atol=1e-3)
    assert_false(Bool(s.wide_angle))
    assert_true("800x600" in String(s))
    assert_true(ExposureMode(1).is_valid())
    assert_false(ExposureMode(2).is_valid())
    assert_false(ExposureMode(-1).is_valid())
    assert_equal(String(MANUAL_EXPOSURE), "ExposureMode(1)")


def test_camera_attributes_map_onto_the_settings() raises:
    var attributes: List[ActorAttributeValue] = [
        _attribute("image_size_x", "320"),
        _attribute("image_size_y", "200"),
        _attribute("fov", "60"),
        _attribute("enable_postprocess_effects", "false"),
        _attribute("gamma", "1.8"),
        _attribute("exposure_mode", "manual"),
        _attribute("exposure_compensation", "1.5"),
        _attribute("shutter_speed", "60"),
        _attribute("iso", "400"),
        _attribute("fstop", "8"),
        _attribute("bloom_intensity", "0.2"),
        _attribute("lens_flare_intensity", "0.3"),
        _attribute("motion_blur_intensity", "0.1"),
        _attribute("chromatic_aberration_intensity", "0.5"),
        _attribute("temp", "4500"),
        _attribute("tint", "0.2"),
        _attribute("blade_count", "7"),
        _attribute("focal_distance", "25"),
        _attribute("lens_k", "-0.5"),
        _attribute("lens_circle_multiplier", "1"),
    ]
    var s = rgb_camera_settings(attributes)
    assert_equal(s.image_width, 320)
    assert_equal(s.image_height, 200)
    assert_almost_equal(s.fov.to(DEGREE), 60, atol=1e-5)
    assert_false(s.enable_postprocess_effects)
    assert_almost_equal(s.gamma, 1.8, atol=1e-6)
    assert_equal(s.exposure_mode, MANUAL_EXPOSURE)
    assert_almost_equal(s.exposure_compensation, 1.5, atol=1e-6)
    assert_almost_equal(s.iso, 400, atol=1e-4)
    assert_almost_equal(s.chromatic_aberration_intensity, 0.5, atol=1e-6)
    assert_almost_equal(s.temp.to(KELVIN), 4500, atol=1e-3)
    assert_equal(s.blade_count, 7)
    assert_almost_equal(s.focal_distance.to(METER), 25, atol=1e-5)
    assert_almost_equal(s.lens.k, -0.5, atol=1e-6)
    assert_almost_equal(s.lens.circle_multiplier, 1, atol=1e-6)
    # A fisheye camera has a lens, and may see past 180 degrees.
    var fisheye: List[ActorAttributeValue] = [
        _attribute("camera_model", "equidistant"),
        _attribute("fov", "200"),
    ]
    assert_true(Bool(rgb_camera_settings(fisheye).wide_angle))
    # What is refused.
    with assert_raises(contains="one pixel"):
        _ = rgb_camera_settings([_attribute("image_size_x", "0")])
    with assert_raises(contains="one pixel"):
        _ = rgb_camera_settings([_attribute("image_size_y", "0")])
    with assert_raises(contains="fov"):
        _ = rgb_camera_settings([_attribute("fov", "0")])
    with assert_raises(contains="fov"):
        _ = rgb_camera_settings([_attribute("fov", "200")])
    with assert_raises(contains="histogram or manual"):
        _ = rgb_camera_settings([_attribute("exposure_mode", "auto")])


def test_field_of_view_and_exposure() raises:
    # CARLA's fov is horizontal: 2 atan(tan(45) 600 / 800) = 73.74 degrees.
    assert_almost_equal(
        vertical_fov(Angle(90, DEGREE), 800, 600).to(DEGREE),
        73.7397953,
        atol=1e-3,
    )
    var s = rgb_camera_settings(List[ActorAttributeValue]())
    # log2(1.4^2 200) = log2(392).
    assert_almost_equal(camera_ev100(s), 8.61470984, atol=1e-4)
    s.iso = 400
    assert_almost_equal(camera_ev100(s), 6.61470984, atol=1e-4)
    # A luminance of 1 is 4000 cd/m^2: log2(4000 100 / 16).
    assert_almost_equal(metered_ev100(1, 16), 14.6096405, atol=1e-4)
    # At that EV100 a luminance of 1 is exposed to middle gray.
    assert_almost_equal(ev100_exposure(14.6096405, 16, 0), 0.18, atol=1e-4)
    assert_almost_equal(ev100_exposure(14.6096405, 16, 1), 0.36, atol=1e-4)
    # The histogram mode clamps to the bright limits, CARLA's 10 to 12 read
    # `CAMERA_EV_OFFSET` (3) stops higher: 13 to 15.
    s = rgb_camera_settings(List[ActorAttributeValue]())
    assert_almost_equal(
        camera_exposure(s, 100), ev100_exposure(15, 16, 0), atol=1e-6
    )
    assert_almost_equal(
        camera_exposure(s, 0.0001), ev100_exposure(13, 16, 0), atol=1e-6
    )
    # EV 14: 2^14 16 / 100 / 4000 = 0.65536 metered, inside the limits.
    assert_almost_equal(
        camera_exposure(s, 0.65536), ev100_exposure(14, 16, 0), atol=1e-5
    )
    # The manual mode takes the camera's EV100, 3 stops higher.
    s.exposure_mode = MANUAL_EXPOSURE
    assert_almost_equal(
        camera_exposure(s, 1), ev100_exposure(11.61470984, 16, 0), atol=1e-4
    )
    assert_almost_equal(LUMINANCE_SCALE.to(NIT), 4000, atol=1e-3)


def test_white_balance() raises:
    var neutral = white_balance(Temperature(6500, KELVIN), 0)
    assert_almost_equal(neutral.r, 1, atol=1e-5)
    assert_almost_equal(neutral.b, 1, atol=1e-5)
    # Balanced for warm light, the camera cools the image.
    var warm = white_balance(Temperature(3000, KELVIN), 0)
    assert_true(warm.b > warm.r)
    # A positive tint takes green away, so red and blue gain on it.
    var tinted = white_balance(Temperature(6500, KELVIN), 0.4)
    assert_almost_equal(tinted.r, 1 / 0.9, atol=1e-4)


def test_camera_passes() raises:
    var s = rgb_camera_settings(List[ActorAttributeValue]())
    var dry = camera_passes(s, 0)
    # Render, motion blur, bloom, lens flare; no aberration by default.
    assert_equal(len(dry), 4)
    assert_equal(dry[0].kind, RENDER)
    assert_equal(dry[1].kind, MOTION_BLUR)
    assert_equal(dry[2].kind, BLOOM)
    assert_equal(dry[3].kind, LENSFLARE)
    s.chromatic_aberration_intensity = 0.4
    var wet = camera_passes(s, 0.8)
    assert_equal(wet[1].kind, SSR_NODE)
    assert_equal(wet[5].kind, CHROMATIC_ABERRATION)
    s.motion_blur_intensity = 0
    s.bloom_intensity = 0
    s.lens_flare_intensity = 0
    s.chromatic_aberration_intensity = 0
    assert_equal(len(camera_passes(s, 0)), 1)
    s.enable_postprocess_effects = False
    s.bloom_intensity = 1
    assert_equal(len(camera_passes(s, 0.5)), 2)


def _renderer(world: World) raises -> CarlaRenderer:
    var view = CarlaRenderer(world, _small(), 1, 8, False)
    view.sun.shadow.map_size = 64
    return view^


def test_render_rgb_semantic_and_depth() raises:
    var camera = ActorId(0)
    var cars = List[ActorId]()
    var walker = ActorId(0)
    var world = _world(camera, cars, walker)
    var view = _renderer(world)
    # Rendering before an update draws the sky first.
    var noon = view.render_rgb(world, camera)
    assert_equal(noon.width, 16)
    assert_equal(noon.height, 12)
    # The sky at the top is brighter blue than red.
    var top = noon.get_pixel(8, 0)
    assert_true(top.b > top.r)
    var semantic = view.render_semantic(world, camera)
    _same(semantic.get_pixel(8, 0), cityscapes_color(SKY))
    _same(semantic.get_pixel(8, 11), cityscapes_color(ROAD))
    var depth = view.render_depth(world, camera)
    assert_equal(decode_depth(depth.get_pixel(8, 0)).to(METER), 1000)
    var near = decode_depth(depth.get_pixel(8, 11)).to(METER)
    # The bottom row looks 5 + 36.9 degrees down from 2 m: the road about
    # 2.9 m ahead, less a little for the tilt of the row's plane.
    assert_true(near > 1.5 and near < 4)
    var tags = view.semantic_tags(world)
    assert_equal(len(tags), len(view.scene.meshes))


def test_render_ground_truth_first_and_without_effects() raises:
    var camera = ActorId(0)
    var cars = List[ActorId]()
    var walker = ActorId(0)
    var world = _world(camera, cars, walker)
    var view = _renderer(world)
    # The semantic camera first draws the sky too.
    var semantic = view.render_semantic(world, camera)
    assert_equal(semantic.width, 16)
    _ = view.render_rgb(world, camera)
    # A camera of the same width and another height, with no effects.
    var bp = world.get_blueprint_library().at("sensor.camera.rgb")
    bp.set_attribute("image_size_x", "16")
    bp.set_attribute("image_size_y", "10")
    bp.set_attribute("enable_postprocess_effects", "false")
    var plain = world.spawn_actor(bp, world.get_transform(camera))
    var image = view.render_rgb(world, plain)
    assert_equal(image.height, 10)
    assert_equal(view.renderer.height, 10)


def test_render_through_the_weathers() raises:
    var camera = ActorId(0)
    var cars = List[ActorId]()
    var walker = ActorId(0)
    var world = _world(camera, cars, walker)
    var view = _renderer(world)
    view.supersample = 2
    var rain = weather_preset("HardRainNoon")
    world.set_weather(rain)
    view.update(world)
    var wet = view.render_rgb(world, camera)
    assert_equal(wet.width, 16)
    # The same weather again keeps the sky.
    var sky = view.sky.value().background
    view.update(world)
    assert_equal(view.sky.value().background, sky)
    world.set_weather(weather_preset("ClearNight"))
    world.set_light_state(cars[0], LIGHT_LOW_BEAM)
    view.update(world)
    assert_false(view.sun.cast_shadow)
    var night = view.render_rgb(world, camera)
    var day_sky = wet.get_pixel(8, 0)
    var night_sky = night.get_pixel(8, 0)
    assert_true(Int(night_sky.b) < Int(day_sky.b))


def test_render_a_fisheye_camera() raises:
    var camera = ActorId(0)
    var cars = List[ActorId]()
    var walker = ActorId(0)
    var world = _world(camera, cars, walker)
    var library = world.get_blueprint_library()
    var bp = library.at("sensor.camera.rgb_fisheye")
    bp.set_attribute("image_size_x", "12")
    bp.set_attribute("image_size_y", "12")
    bp.set_attribute("camera_model", "equidistant")
    bp.set_attribute("fov", "180")
    bp.set_attribute("fov_mask", "true")
    var fisheye = world.spawn_actor(
        bp,
        CarlaTransform(
            Length(8, METER),
            Length(1.75, METER),
            Length(2, METER),
            CarlaRotation(Angle(0, DEGREE), Angle(0, DEGREE), Angle(0, DEGREE)),
        ),
    )
    var w = weather_preset("ClearNoon")
    w.fog_density = 40
    world.set_weather(w)
    var view = _renderer(world)
    view.update(world)
    var image = view.render_rgb(world, fisheye)
    assert_equal(image.width, 12)
    # The mask blacks out the corners, past 90 degrees from the axis.
    var corner = image.get_pixel(0, 0)
    assert_equal(Int(corner.r) + Int(corner.g) + Int(corner.b), 0)
    # Without fog; then wet, where the reflections are left out.
    var clear = weather_preset("ClearNoon")
    clear.fog_density = 0
    world.set_weather(clear)
    view.update(world)
    _ = view.render_rgb(world, fisheye)
    world.set_weather(weather_preset("WetNoon"))
    view.update(world)
    _ = view.render_rgb(world, fisheye)
    # Without its effects, nothing follows the drawing.
    bp.set_attribute("enable_postprocess_effects", "false")
    var plain = world.spawn_actor(
        bp,
        CarlaTransform(
            Length(8, METER),
            Length(1.75, METER),
            Length(2, METER),
            CarlaRotation(Angle(0, DEGREE), Angle(0, DEGREE), Angle(0, DEGREE)),
        ),
    )
    world.set_weather(clear)
    view.update(world)
    assert_equal(view.render_rgb(world, plain).width, 12)


# The town from a registry.

# A car of one triangle drawn three times: its paint, its head lamps and
# its tail lamps, as the vehicle exporter tags them.
comptime SCANNED_CAR = (
    '{"asset":{"version":"2.0"},"scene":0,"scenes":[{"nodes":[0]}],'
    '"nodes":[{"mesh":0}],"buffers":[{"byteLength":36,"uri":'
    '"data:application/octet-stream;base64,'
    'AAAAAAAAAAAAAAAAAACAPwAAAAAAAAAAAAAAAAAAgD8AAAAA"}],'
    '"bufferViews":[{"buffer":0,"byteLength":36}],"accessors":'
    '[{"bufferView":0,"componentType":5126,"count":3,"type":"VEC3",'
    '"min":[0,0,0],"max":[1,1,0]}],"materials":[{"extras":{"carla":'
    '"paint"}},{"extras":{"carla":"heads"}},{"extras":{"carla":"tails"}}],'
    '"meshes":[{"primitives":[{"attributes":{"POSITION":0},"material":0},'
    '{"attributes":{"POSITION":0},"material":1},{"attributes":'
    '{"POSITION":0},"material":2}]}]}'
)


def _scanned_file(role: String, path: String) -> String:
    return (
        '{"role": "'
        + role
        + '", "url": null, "sha256": "'
        + "0" * 64
        + '", "path": "'
        + path
        + '"}'
    )


def _scanned_entry(
    id: String, kind: String, files: String, extra: String
) -> String:
    return (
        '{"id": "'
        + id
        + '", "kind": "'
        + kind
        + '", "license": "CC0-1.0", "author": "A", "source":'
        ' "https://example.org", "provenance": "A fixture.", "files": ['
        + files
        + "]"
        + extra
        + "}"
    )


def _scanned_registry() raises -> AssetRegistry:
    """A cache in /tmp of the repository's fixtures: a checker for every
    surface, a Radiance panorama for every sky, a box for the tree and the
    walkers, and the tagged car for every vehicle."""
    var folder = "/tmp/threemojo_carla_scanned/"
    makedirs(folder, exist_ok=True)
    for name in ["gltf/checker.png", "gltf/box.gltf", "gltf/box.bin"]:
        Path(folder + name.split("/")[1]).write_bytes(
            Path("assets/" + name).read_bytes()
        )
    Path(folder + "sky.hdr").write_bytes(
        Path("assets/hdr_cube/px.hdr").read_bytes()
    )
    Path(folder + "car.gltf").write_text(SCANNED_CAR)
    var checker = (
        _scanned_file("albedo", "checker.png")
        + ", "
        + _scanned_file("roughness", "checker.png")
        + ", "
        + _scanned_file("normal", "checker.png")
    )
    var entries = (
        _scanned_entry("scan", "texture_set", checker, ', "tile_meters": 2')
        + ", "
        + _scanned_entry("sky", "hdri", _scanned_file("hdri", "sky.hdr"), "")
        + ", "
        + _scanned_entry(
            "box",
            "model",
            _scanned_file("model", "box.gltf")
            + ", "
            + _scanned_file("support", "box.bin"),
            ', "forward": "+z"',
        )
        + ", "
        + _scanned_entry(
            "car",
            "model",
            _scanned_file("model", "car.gltf"),
            ', "forward": "+x"',
        )
    )
    var bindings = (
        '{"surface.road": "scan", "surface.sidewalk": "scan", "surface.curb":'
        ' "scan", "surface.wall": "scan", "ground.grass": "scan",'
        ' "ground.paving": "scan", "sky.clear": "sky", "sky.low_sun": "sky",'
        ' "sky.overcast": "sky", "sky.night": "sky", "tree": "box",'
        ' "vehicle.*": "car", "walker.*": "box"}'
    )
    return AssetRegistry(
        parse_manifest(
            '{"format": 1, "entries": ['
            + entries
            + '], "bindings": '
            + bindings
            + "}"
        ),
        folder,
    )


def test_render_a_town_from_the_registry() raises:
    var camera = ActorId(0)
    var cars = List[ActorId]()
    var walker = ActorId(0)
    var world = _world(camera, cars, walker)
    var view = CarlaRenderer(
        world, _small(), 1, 8, False, registry=_scanned_registry()
    )
    view.sun.shadow.map_size = 64
    view.update(world)
    var image = view.render_rgb(world, camera)
    assert_equal(image.width, 16)
    # Every vehicle wears the town's paint and lamps on its tagged meshes.
    for v in view.actors.vehicles:
        assert_true(view.scene.meshes[v.first_mesh].material == v.paint)
        assert_true(view.scene.meshes[v.first_mesh + 1].material == v.heads)
        assert_true(view.scene.meshes[v.first_mesh + 2].material == v.tails)
    # The lamps glow at night.
    world.set_weather(weather_preset("ClearNight"))
    world.set_light_state(cars[0], LIGHT_LOW_BEAM)
    view.update(world)
    var heads = view.assets.materials.get(view.actors.vehicles[0].heads)
    assert_true(heads.emissive_intensity > 0)
    _ = view.render_rgb(world, camera)


def test_a_town_package_stands_in_for_the_dressing() raises:
    var camera = ActorId(0)
    var cars = List[ActorId]()
    var walker = ActorId(0)
    var world = _world(camera, cars, walker)
    var settings = _small()
    settings.package = "Town02"
    settings.near_distance = Length(10, METER)
    var view = CarlaRenderer(
        world, settings^, 1, 8, False, registry=town_registry()
    )
    ref town = view.town
    assert_true(Bool(town.package))
    # The town's meshes are the package's, and no procedural dressing.
    assert_equal(len(town.tags), 7)
    assert_true(town.tags[0] == BUILDING)
    assert_true(town.tags[2] == ROAD_LINE)
    assert_false(town.settings.buildings)
    # A light for each of the package's three lamps, the pool being larger.
    assert_equal(len(town.lamp_lights), 3)
    assert_equal(len(town.lamp_glass), 1)
    # The package's traffic light is hidden: the props draw the map's.
    var light = town.package.value().first_mesh + 4
    assert_false(view.scene.get(view.scene.meshes[light].node).visible)
    # The paint and the road share one material, which the rain wets.
    assert_equal(len(town.wet_materials), 1)
    view.update(world)
    var road = town.wet_materials[0]
    var dry = view.assets.materials.get(road).color
    world.set_weather(weather_preset("HardRainNoon"))
    view.update(world)
    var wet = view.assets.materials.get(road).color
    assert_true(wet.r < dry.r)
    assert_true(view.assets.materials.get(road).roughness < 0.5)
    # A frame shows each tile at the camera's level of detail.
    var image = view.render_rgb(world, camera)
    assert_equal(image.width, 16)
    # At night the lamps light, and their glass glows.
    world.set_weather(weather_preset("ClearNight"))
    view.update(world)
    ref lit = view.town
    assert_equal(
        view.scene.lights[lit.lamp_lights[0]].intensity, LAMP_INTENSITY
    )
    assert_equal(
        view.assets.materials.get(lit.lamp_glass[0]).emissive_intensity,
        TOWN_LAMP_GLOW,
    )
    # The pool follows the camera: its nearest light stands at the lamp
    # nearest the eye.
    view.town.place_lamps(view.scene, Vector3(100, 0, 0))
    var bulb = view.scene.get(view.town.lamp_bulbs[0]).position
    assert_equal(bulb.x, 100)
    assert_equal(bulb.y, 5)
    # A package the cache lacks leaves the town procedural.
    var other = _small()
    other.package = "Town09"
    var procedural = CarlaRenderer(
        world, other^, 1, 8, False, registry=town_registry()
    )
    assert_false(Bool(procedural.town.package))
    assert_true(len(procedural.town.tags) > 7)


def test_each_town_kind_has_its_tag_and_its_shadow() raises:
    # Each kind `build_towns.py` writes, its CityScapes tag number, and
    # whether it casts the sun's shadow.
    var kinds: List[Tuple[String, Int, Bool]] = [
        ("building", 3, True),
        ("road", 1, False),
        ("road_line", 24, False),
        ("sidewalk", 2, False),
        ("ground", 25, False),
        ("terrain", 10, False),
        ("water", 23, False),
        ("rail", 27, False),
        ("wall", 4, True),
        ("fence", 5, False),
        ("vegetation", 9, True),
        ("pole", 6, False),
        ("traffic_light", 7, False),
        ("traffic_sign", 8, False),
        ("parked_vehicle", 14, True),
        ("prop", 20, False),
        ("something_new", 20, False),
    ]
    for kind in kinds:
        assert_equal(town_kind_tag(kind[0]).value, kind[1])
        assert_equal(town_kind_casts(kind[0]), kind[2])


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
