# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""One of CARLA's own towns in four weathers, seen by an RGB camera behind
a car.

    mojo run -I . examples/carla_towns.mojo [path.png] [Town10HD]

The page is CARLA rendering. The town is CARLA's own: its package and its
OpenDRIVE map, from the cache that `assets/carla/tools/carla_assets.py
fetch` fills. Cars wait in a lane of the town's longest road, and a
`sensor.camera.rgb` rides behind the first. `CarlaRenderer` draws what the
camera sees under four of CARLA's weathers: clear noon, a wet sunset, hard
rain with fog, and a clear night with the street lamps lit. Each image is
800 by 600, CARLA's camera default. The four make one page, two by two,
and each is also written alone beside the page.

The town must be in the cache: the example stops if its package is not.
"""

from extensions.carla.actor import ActorId
from extensions.carla.assets import AssetRegistry
from extensions.carla.camera_render import CarlaRenderer
from extensions.carla.map import Waypoint
from extensions.carla.opendrive import load_opendrive_file
from extensions.carla.road_info import LaneId, SectionId
from extensions.carla.town import TownSettings
from extensions.carla.transform import CarlaRotation, CarlaTransform
from extensions.carla.vehicle import LIGHT_LOW_BEAM, LIGHT_POSITION
from extensions.carla.weather import weather_preset
from extensions.carla.world import EpisodeSettings, World
from render.framebuffer import Color, Framebuffer
from render.png import encode
from renderers.renderer import available_workers
from std.pathlib import Path
from std.sys import argv
from std.time import perf_counter_ns
from units.si import DEGREE, METER, SECOND, Angle, Duration, Length

comptime DEFAULT_OUTPUT = "out/carla_towns.png"
comptime DEFAULT_TOWN = "Town10HD"
comptime WIDTH = 800
comptime HEIGHT = 600
comptime MANIFEST = "assets/carla/manifest.json"
comptime CACHE = ".cache/carla-assets/"


def build_world(
    town: String, mut camera: ActorId, mut cars: List[ActorId]
) raises -> World:
    """Load a town's map, line cars up in its longest road, and mount the
    camera behind the first.

    Args:
        town: The town's name, such as `Town10HD`.
        camera: Set to the camera.
        cars: The cars are appended.

    Returns:
        The world.

    Raises:
        Error: If the town's map is not in the cache, or a spawn fails.
    """
    var folder = CACHE + "carla/towns/carla.town." + town.lower() + "/"
    var world = World(load_opendrive_file(folder + town + ".xodr"))
    var settings = EpisodeSettings()
    settings.synchronous_mode = True
    settings.fixed_delta_seconds = Duration(0.05, SECOND)
    _ = world.apply_settings(settings)
    # The longest road outside the junctions with a lane on its right.
    var road = -1
    var length = 0.0
    for r in range(len(world.map.roads)):
        ref candidate = world.map.roads[r]
        if candidate.is_junction or candidate.length <= length:
            continue
        try:
            _ = world.map.compute_transform(
                Waypoint(candidate.id, SectionId(0), LaneId(-1), 1.0)
            )
            road = r
            length = candidate.length
        except:
            pass
    var id = world.map.roads[road].id
    var library = world.get_blueprint_library()
    var models: List[Tuple[String, String]] = [
        ("vehicle.lincoln.mkz", "190,30,28"),
        ("vehicle.mini.cooper", "20,60,150"),
        ("vehicle.nissan.patrol", "235,235,235"),
        ("vehicle.dodge.charger", "30,30,32"),
    ]
    for k in range(len(models)):
        var blueprint = library.at(models[k][0])
        blueprint.set_attribute("color", models[k][1])
        var pose = world.map.compute_transform(
            Waypoint(id, SectionId(0), LaneId(-1), 6.0 + 11.0 * Float64(k))
        )
        pose.location.z += 0.3
        cars.append(world.spawn_actor(blueprint, pose))
    var camera_blueprint = library.at("sensor.camera.rgb")
    camera_blueprint.set_attribute("image_size_x", String(WIDTH))
    camera_blueprint.set_attribute("image_size_y", String(HEIGHT))
    camera_blueprint.set_attribute("fov", "90")
    var mount = CarlaTransform(
        Length(-5.8, METER),
        Length(0, METER),
        Length(2.6, METER),
        CarlaRotation(Angle(-8, DEGREE), Angle(0, DEGREE), Angle(0, DEGREE)),
    )
    camera = world.spawn_actor(camera_blueprint, mount, cars[0])
    for _ in range(10):
        _ = world.tick()
    return world^


def sibling(destination: String, suffix: String) -> String:
    """Return the path of one view's still beside the page.

    Args:
        destination: The page's path, such as `out/carla_towns.png`.
        suffix: The view's name, such as `night`.

    Returns:
        The page's path with `_` and the suffix before its extension.
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
    var town = String(DEFAULT_TOWN)
    if len(args) > 2:
        town = String(args[2])
    var start = perf_counter_ns()
    var registry = AssetRegistry.open(MANIFEST, CACHE)
    if not Bool(registry.cached_entry("town." + town)):
        raise Error(
            "The town "
            + town
            + " is not in the cache: run"
            + " assets/carla/tools/carla_assets.py fetch carla.town."
            + town.lower()
        )
    var camera = ActorId(0)
    var cars = List[ActorId]()
    var world = build_world(town, camera, cars)
    var settings = TownSettings()
    settings.package = town
    var view = CarlaRenderer(
        world, settings^, available_workers(), registry=registry^
    )
    print("Town built in", Float64(perf_counter_ns() - start) / 1e9, "s")
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
        if k == 2:
            weather.fog_density = 25
            weather.fog_distance = Length(8, METER)
        world.set_weather(weather)
        for id in cars:
            world.set_light_state(
                id,
                LIGHT_POSITION | LIGHT_LOW_BEAM if k == 3 else LIGHT_POSITION,
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
