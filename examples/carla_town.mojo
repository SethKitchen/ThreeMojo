# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""A CARLA town in four weathers, seen by an RGB camera behind a car.

    mojo run -I . examples/carla_town.mojo [path.png]

The page is CARLA rendering. The town is `assets/carla/town.xodr`: a road
with sidewalks that meets a junction, with a traffic light, a stop sign
and a yield sign. A `World` spawns cars in the lanes and walkers on the
sidewalks and ticks them for two seconds. A `sensor.camera.rgb` rides
behind the ego car. `CarlaRenderer` draws what the camera sees under four
of CARLA's weathers: clear noon, a wet sunset, hard rain with fog, and a
clear night with the lamps lit. Each image is 800 by 600, CARLA's camera
default. The four make one page, two by two, and each is also written
alone beside the page, as `_clear_noon`, `_wet_sunset`, `_rain` and
`_night`.

The town wears the assets in `.cache/carla-assets/` that
`assets/carla/tools/carla_assets.py fetch` downloads: photoscanned roads,
sidewalks and grass, an HDRI sky, and CARLA's own vehicle models. An asset
the cache lacks is procedural, so the example runs without a download.
"""

from extensions.carla.actor import ActorId
from extensions.carla.assets import AssetRegistry
from extensions.carla.camera_render import CarlaRenderer
from extensions.carla.map import Waypoint
from extensions.carla.opendrive import load_opendrive_file
from extensions.carla.physics.vehicle_control import VehicleControl
from extensions.carla.physics.walker import WalkerControl
from extensions.carla.road_info import LaneId, RoadId, SectionId
from extensions.carla.town import TownSettings
from extensions.carla.transform import CarlaRotation, CarlaTransform
from extensions.carla.vehicle import LIGHT_BRAKE, LIGHT_LOW_BEAM, LIGHT_POSITION
from extensions.carla.weather import weather_preset
from extensions.carla.world import EpisodeSettings, World
from math.vector3 import Vector3
from render.framebuffer import Color, Framebuffer
from render.png import encode
from renderers.renderer import available_workers
from std.pathlib import Path
from std.sys import argv
from std.time import perf_counter_ns
from units.si import (
    DEGREE,
    METER,
    SECOND,
    Angle,
    Duration,
    Length,
    METER_PER_SECOND,
    Velocity,
)

comptime DEFAULT_OUTPUT = "out/carla_town.png"
comptime WIDTH = 800
comptime HEIGHT = 600
comptime MANIFEST = "assets/carla/manifest.json"
comptime CACHE = ".cache/carla-assets/"


def _lane_pose(
    world: World, road: Int, lane: Int, s: Float64, lift: Float32
) raises -> CarlaTransform:
    var pose = world.map.compute_transform(
        Waypoint(RoadId(road), SectionId(0), LaneId(lane), s)
    )
    pose.location.z += lift
    return pose


def build_world(mut camera: ActorId, mut ids: List[ActorId]) raises -> World:
    """Spawn the cars, the walkers and the camera, and tick two seconds.

    Args:
        camera: Set to the camera.
        ids: The cars are appended.

    Returns:
        The world.

    Raises:
        Error: If a spawn or a tick fails.
    """
    var world = World(load_opendrive_file("assets/carla/town.xodr"))
    var settings = EpisodeSettings()
    settings.synchronous_mode = True
    settings.fixed_delta_seconds = Duration(0.05, SECOND)
    _ = world.apply_settings(settings)
    var library = world.get_blueprint_library()
    # (road, lane, s, blueprint, color)
    var cars: List[Tuple[Int, Int, Float64, String, String]] = [
        (1, -1, 19.0, "vehicle.lincoln.mkz", "190,30,28"),
        (1, -1, 30.0, "vehicle.mini.cooper", "20,60,150"),
        (1, 1, 22.0, "vehicle.dodge.charger", "30,30,32"),
        (1, 1, 44.0, "vehicle.nissan.patrol", "235,235,235"),
        (1, -1, 46.0, "vehicle.taxi.ford", "240,190,20"),
        (2, -1, 20.0, "vehicle.sprinter.mercedes", "210,212,215"),
        (2, 1, 12.0, "vehicle.lincoln.mkz", "120,125,130"),
    ]
    for car in cars:
        var blueprint = library.at(car[3])
        blueprint.set_attribute("color", car[4])
        ids.append(
            world.spawn_actor(
                blueprint, _lane_pose(world, car[0], car[1], car[2], 0.3)
            )
        )
    var walkers: List[Tuple[Int, Float64, Float64]] = [
        (-2, 20.0, 0.0),
        (-2, 33.0, 180.0),
        (2, 16.0, 0.0),
        (2, 38.0, 180.0),
        (-2, 52.0, 0.0),
    ]
    var n = 0
    for w in walkers:
        var pose = _lane_pose(world, 1, w[0], w[1], 1.1)
        pose.rotation = CarlaRotation(
            Angle(0, DEGREE), Angle(Float32(w[2]), DEGREE), Angle(0, DEGREE)
        )
        var id = world.spawn_actor(
            library.at("walker.pedestrian.00" + String(15 + n * 3)), pose
        )
        var control = WalkerControl()
        control.direction = pose.rotation.forward_vector()
        control.speed = Velocity(1.3, METER_PER_SECOND)
        world.apply_walker_control(id, control)
        n += 1
    # The ego car, and the one ahead of it, drive; the others wait.
    for k in range(2):
        var control = VehicleControl()
        control.throttle = 0.45
        world.apply_control(ids[k], control)
    var camera_blueprint = library.at("sensor.camera.rgb")
    camera_blueprint.set_attribute("image_size_x", String(WIDTH))
    camera_blueprint.set_attribute("image_size_y", String(HEIGHT))
    camera_blueprint.set_attribute("fov", "90")
    var mount = CarlaTransform(
        Length(-5.8, METER),
        Length(0, METER),
        Length(2.6, METER),
        CarlaRotation(Angle(-10, DEGREE), Angle(0, DEGREE), Angle(0, DEGREE)),
    )
    camera = world.spawn_actor(camera_blueprint, mount, ids[0])
    for _ in range(40):
        _ = world.tick()
    return world^


def sibling(destination: String, suffix: String) -> String:
    """Return the path of one view's still beside the page.

    Args:
        destination: The page's path, such as `out/carla_town.png`.
        suffix: The view's name, such as `night`.

    Returns:
        The page's path with `_` and the suffix before its extension, such
        as `out/carla_town_night.png`.
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
    var start = perf_counter_ns()
    var camera = ActorId(0)
    var cars = List[ActorId]()
    var world = build_world(camera, cars)
    var view = CarlaRenderer(
        world,
        TownSettings(),
        available_workers(),
        registry=AssetRegistry.open(MANIFEST, CACHE),
    )
    print("Town built in", Float64(perf_counter_ns() - start) / 1e9, "s")

    # One frame first, so the motion blur of the first still sees the
    # frame before it.
    view.update(world)
    _ = view.render_rgb(world, camera)
    var names: List[String] = [
        "ClearNoon",
        "WetSunset",
        "HardRainNoon",
        "ClearNight",
    ]
    var files: List[String] = ["clear_noon", "wet_sunset", "rain", "night"]
    var page = Framebuffer(WIDTH * 2, HEIGHT * 2, Color(0, 0, 0))
    for k in range(len(names)):
        var weather = weather_preset(names[k])
        # The sun stands behind the camera at noon, and ahead and to the
        # left of it at sunset.
        weather.sun_azimuth_angle = Angle(
            Float32(200) if k == 0 else Float32(340), DEGREE
        )
        if k == 2:
            weather.fog_density = 25
            weather.fog_distance = Length(8, METER)
        world.set_weather(weather)
        var night = k == 3
        for id in cars:
            var lights = (
                LIGHT_POSITION
                | LIGHT_LOW_BEAM if night else LIGHT_POSITION if k
                == 2 else world.get_light_state(id)
            )
            world.set_light_state(id, lights)
        world.set_light_state(
            cars[2], world.get_light_state(cars[2]) | LIGHT_BRAKE
        )
        var shot_start = perf_counter_ns()
        _ = world.tick()
        view.update(world)
        var image = view.render_rgb(world, camera)
        print(
            names[k], "in", Float64(perf_counter_ns() - shot_start) / 1e9, "s"
        )
        var still = sibling(destination, files[k])
        Path(still).write_bytes(encode(image))
        print("Wrote", still, image.width, "x", image.height)
        var ox = (k % 2) * WIDTH
        var oy = (k // 2) * HEIGHT
        for y in range(HEIGHT):
            for x in range(WIDTH):
                page.set_pixel(ox + x, oy + y, image.get_pixel(x, y))
    Path(destination).write_bytes(encode(page))
    print(
        "Wrote",
        destination,
        "in",
        Float64(perf_counter_ns() - start) / 1e9,
        "s",
    )
