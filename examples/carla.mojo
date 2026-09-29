# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""One CARLA sensor rig on an OpenDRIVE road.

    mojo run -I . examples/carla.mojo [path.png]

The road is a line, a spiral and an arc, with two lanes each way, built
with CARLA's `MapBuilder`. A `World` stands on it, with cars in its lanes
at CARLA's waypoint transforms. `CarlaRenderer` builds the town around
the road and draws what one camera on the ego car's roof sees, three ways
side by side, each 800 by 600 as CARLA's cameras are: the RGB image with
one LiDAR sweep on top, the CityScapes semantic image, and the
logarithmic depth image. Each image is also written alone beside the
page, as `_rgb`, `_semantic` and `_depth`. The page is CARLA.
"""

from extensions.carla.camera_render import CarlaRenderer
from extensions.carla.geometry import RoadGeometry, line, spiral
from extensions.carla.lidar import LidarDescription, scan_lidar
from extensions.carla.map import Map, Waypoint
from extensions.carla.map_builder import MapBuilder
from extensions.carla.road_info import (
    JuncId,
    LANE_DRIVING,
    LANE_NONE,
    LaneId,
    RoadId,
    SectionId,
)
from extensions.carla.sensor import (
    CameraIntrinsics,
    logarithmic_gray,
    normalized_depth,
)
from extensions.carla.town import TownSettings
from extensions.carla.transform import CarlaRotation, CarlaTransform
from extensions.carla.weather import weather_preset
from extensions.carla.world import EpisodeSettings, World
from render.framebuffer import Color, Framebuffer
from render.png import encode
from renderers.renderer import available_workers
from std.pathlib import Path
from std.sys import argv
from units.si import (
    DEGREE,
    InverseLength,
    Length,
    METER,
    PER_METER,
    RADIAN,
    SECOND,
    Angle,
    Duration,
)

comptime DEFAULT_OUTPUT = "out/carla.png"
comptime WIDTH = 800
comptime HEIGHT = 600
comptime FOV = Float32(90)


def _m(value: Float32) -> Length:
    return Length(value, METER)


def _next_start(record: RoadGeometry) -> Tuple[Float32, Float32, Float32]:
    var end = record.pos_from_dist(_m(Float32(record.length)))
    return (Float32(end.x), Float32(end.y), Float32(end.tangent))


def build_map() raises -> Map:
    """Return one road: a line, a spiral and an arc, two lanes each way.

    Returns:
        The map, with the road's lanes and marks.

    Raises:
        Error: If a record is not valid, which it is.
    """
    var first = line(_m(0), _m(0), _m(0), Angle(0, RADIAN), _m(40))
    var a = _next_start(first)
    var second = spiral(
        _m(40),
        _m(a[0]),
        _m(a[1]),
        Angle(a[2], RADIAN),
        _m(30),
        InverseLength(0.0, PER_METER),
        InverseLength(0.02, PER_METER),
    )
    var b = _next_start(second)
    var builder = MapBuilder()
    var road = builder.add_road(
        RoadId(1), "demo", 130.0, JuncId(-1), RoadId(0), RoadId(0), True
    )
    builder.add_road_geometry_line(road, 0.0, 0.0, 0.0, 0.0, 40.0)
    builder.add_road_geometry_spiral(
        road, 40.0, Float64(a[0]), Float64(a[1]), Float64(a[2]), 30.0, 0.0, 0.02
    )
    builder.add_road_geometry_arc(
        road, 70.0, Float64(b[0]), Float64(b[1]), Float64(b[2]), 60.0, 0.02
    )
    _ = builder.add_road_section(road, SectionId(0), 0.0)
    for id in [-2, -1, 0, 1, 2]:
        var kind = LANE_NONE if id == 0 else LANE_DRIVING
        _ = builder.add_road_section_lane(
            road, 0, LaneId(id), kind, False, LaneId(0), LaneId(0)
        )
        var lane = builder.lane(RoadId(1), LaneId(id), 0.0)
        builder.create_lane_width(lane, 0.0, 0.0 if id == 0 else 3.5, 0, 0, 0)
        # The center line is solid and 0.3 m wide; the lanes between are
        # broken and the outer edges solid, 0.15 m wide.
        var mark = "broken" if abs(id) == 1 else "solid"
        var width = 0.3 if id == 0 else 0.15
        builder.create_road_mark(
            lane,
            0,
            0.0,
            mark,
            "",
            "white",
            "",
            width,
            "",
            0.0,
            "",
            0.0,
            True,
        )
    builder.create_section_offset(road, 0.0, 0, 0, 0, 0)
    builder.add_road_elevation_profile(road, 0.0, 0, 0, 0, 0)
    return builder.build()


def _lane_transform(map: Map, s: Float64, lane: Int) raises -> CarlaTransform:
    return map.compute_transform(
        Waypoint(RoadId(1), SectionId(0), LaneId(lane), s)
    )


def sibling(destination: String, suffix: String) -> String:
    """Return the path of one panel's image beside the page.

    Args:
        destination: The page's path, such as `out/carla.png`.
        suffix: The panel's name, such as `rgb`.

    Returns:
        The page's path with `_` and the suffix before its extension, such
        as `out/carla_rgb.png`.
    """
    if destination.endswith(".png"):
        var stem = destination.byte_length() - 4
        return String(destination[byte=:stem]) + "_" + suffix + ".png"
    return destination + "_" + suffix + ".png"


def main() raises:
    var args = argv()
    var destination = String(DEFAULT_OUTPUT)
    if len(args) > 1:
        destination = String(args[1])

    var world = World(build_map())
    var settings = EpisodeSettings()
    settings.synchronous_mode = True
    settings.fixed_delta_seconds = Duration(0.05, SECOND)
    _ = world.apply_settings(settings)
    var library = world.get_blueprint_library()
    # (s, lane, blueprint, color)
    var cars: List[Tuple[Float64, Int, String, String]] = [
        (30.0, -1, "vehicle.lincoln.mkz", "180,30,36"),
        (52.0, -2, "vehicle.mini.cooper", "40,90,170"),
        (70.0, 1, "vehicle.nissan.patrol", "230,230,228"),
        (95.0, -1, "vehicle.dodge.charger", "30,30,34"),
        (44.0, 2, "vehicle.sprinter.mercedes", "210,212,215"),
    ]
    for c in cars:
        var blueprint = library.at(c[2])
        blueprint.set_attribute("color", c[3])
        var pose = _lane_transform(world.map, c[0], c[1])
        pose.location.z += 0.3
        _ = world.spawn_actor(blueprint, pose)

    # The ego car drives lane -1. Its camera sits on the roof.
    var ego = _lane_transform(world.map, 16.0, -1)
    var camera_pose = CarlaTransform(
        _m(ego.location.x),
        _m(ego.location.y),
        _m(2.2),
        CarlaRotation(
            Angle(0, DEGREE), Angle(ego.rotation.yaw, DEGREE), Angle(0, DEGREE)
        ),
    )
    var rgb_blueprint = library.at("sensor.camera.rgb")
    rgb_blueprint.set_attribute("image_size_x", String(WIDTH))
    rgb_blueprint.set_attribute("image_size_y", String(HEIGHT))
    rgb_blueprint.set_attribute("fov", String(Int(FOV)))
    var camera = world.spawn_actor(rgb_blueprint, camera_pose)
    var weather = weather_preset("ClearNoon")
    weather.sun_azimuth_angle = Angle(230, DEGREE)
    world.set_weather(weather)
    # A second lets the cars settle on their wheels.
    for _ in range(20):
        _ = world.tick()

    var view = CarlaRenderer(world, TownSettings(), available_workers())
    view.update(world)
    var rgb = view.render_rgb(world, camera)
    var semantic = view.render_semantic(world, camera)
    var depth = view.render_depth(world, camera)

    var lidar = LidarDescription()
    lidar.range = _m(60)
    lidar.points_per_second = 90000
    lidar.upper_fov = Angle(2, DEGREE)
    lidar.lower_fov = Angle(-24, DEGREE)
    var sensor = CarlaTransform(
        _m(ego.location.x), _m(ego.location.y), _m(2.4), ego.rotation
    )
    var sweep = scan_lidar(
        view.scene,
        view.assets,
        sensor,
        lidar,
        Duration(0.1, SECOND),
        Angle(0, DEGREE),
        1,
    )

    var gray_depth = Framebuffer(WIDTH, HEIGHT, Color(0, 0, 0))
    for y in range(HEIGHT):
        for x in range(WIDTH):
            var gray = logarithmic_gray(normalized_depth(depth.get_pixel(x, y)))
            var level = UInt8(Int(gray * 255.0 + 0.5))
            gray_depth.set_pixel(x, y, Color(level, level, level))
    var panels: List[String] = ["rgb", "semantic", "depth"]
    Path(sibling(destination, panels[0])).write_bytes(encode(rgb))
    Path(sibling(destination, panels[1])).write_bytes(encode(semantic))
    Path(sibling(destination, panels[2])).write_bytes(encode(gray_depth))
    for name in panels:
        print("Wrote", sibling(destination, name), WIDTH, "x", HEIGHT)

    var out = Framebuffer(WIDTH * 3, HEIGHT, Color(0, 0, 0))
    for y in range(HEIGHT):
        for x in range(WIDTH):
            out.set_pixel(x, y, rgb.get_pixel(x, y))
            out.set_pixel(WIDTH + x, y, semantic.get_pixel(x, y))
            out.set_pixel(2 * WIDTH + x, y, gray_depth.get_pixel(x, y))
    var k = CameraIntrinsics(WIDTH, HEIGHT, Angle(FOV, DEGREE))
    for p in sweep.points:
        var world_point = sensor.transform_point(p.point)
        var pixel = k.project(camera_pose, world_point)
        var px = Int(pixel.x)
        var py = Int(pixel.y)
        if pixel.z > 0.0 and px >= 0 and px < WIDTH and py >= 0 and py < HEIGHT:
            # Yellow near, cyan at 40 m and beyond.
            var t = min(pixel.z / 40.0, Float32(1.0))
            out.set_pixel(
                px,
                py,
                Color(
                    UInt8(Int(255.0 * (1.0 - t))),
                    UInt8(Int(210.0 + 30.0 * t)),
                    UInt8(Int(255.0 * t)),
                ),
            )

    Path(destination).write_bytes(encode(out))
    print(
        "Wrote",
        destination,
        WIDTH * 3,
        "x",
        HEIGHT,
        "-",
        len(sweep.points),
        "LiDAR points",
    )
