# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Compare cached vehicle spawn costs against the same source on the base.

Generate the synthetic asset with `carla_model_cache_fixture.py`. Pass its
folder, an instance count, and `batch` or `incremental`. Timing covers
ActorVisuals.sync only. Byte counts cover geometry attributes and indices,
and decoded texture pixels including mipmaps. They exclude object overhead.
"""

from core.assets import Assets
from core.scene import Scene
from extensions.carla.assets import AssetRegistry
from extensions.carla.opendrive import load_opendrive_file
from extensions.carla.render_actors import ActorVisuals
from extensions.carla.transform import CarlaTransform, CarlaRotation
from extensions.carla.world import World
from std.sys import argv
from std.time import perf_counter_ns
from units.si import DEGREE, METER, Angle, Length


def main() raises:
    var args = argv()
    if len(args) != 4:
        raise Error(
            "Usage: carla_model_cache_bench FIXTURE COUNT batch|incremental"
        )
    var folder = args[1]
    var count = atol(args[2])
    var incremental = args[3] == "incremental"
    if count <= 0 or (args[3] != "batch" and not incremental):
        raise Error(
            "COUNT must be positive and mode must be batch or incremental"
        )
    var registry = AssetRegistry.open(folder + "/manifest.json", folder)
    var world = World(load_opendrive_file("assets/carla/town.xodr"))
    var library = world.get_blueprint_library()
    var blueprint = library.at("vehicle.lincoln.mkz")
    var scene = Scene()
    var assets = Assets()
    var visuals = ActorVisuals()
    var elapsed = Int64(0)
    for n in range(count):
        _ = world.spawn_actor(
            blueprint,
            CarlaTransform(
                Length(Float32(n) * 10, METER),
                Length(0, METER),
                Length(3, METER),
                CarlaRotation(
                    Angle(0, DEGREE), Angle(0, DEGREE), Angle(0, DEGREE)
                ),
            ),
        )
        if incremental:
            var start = perf_counter_ns()
            visuals.sync(world, scene, assets, registry)
            elapsed += Int64(perf_counter_ns() - start)
    if not incremental:
        var start = perf_counter_ns()
        visuals.sync(world, scene, assets, registry)
        elapsed = Int64(perf_counter_ns() - start)
    var geometry_bytes = 0
    for g in range(assets.geometries.count()):
        ref geometry = assets.geometries.geometries[g]
        geometry_bytes += len(geometry.index) * 8
        for a in range(len(geometry.values)):
            geometry_bytes += len(geometry.values[a].data) * 4
    var texture_bytes = 0
    for t in range(assets.textures.count()):
        ref texture = assets.textures.textures[t]
        texture_bytes += len(texture.pixels) + len(texture.data) * 4
    var checksum = Float64(0)
    for vehicle in visuals.vehicles:
        checksum += Float64(scene.world_position(vehicle.node).x)
        checksum += Float64(assets.materials.get(vehicle.paint).color.r)
    print(
        "count",
        count,
        "mode",
        args[3],
        "spawn_ns",
        elapsed,
        "geometries",
        assets.geometries.count(),
        "textures",
        assets.textures.count(),
        "materials",
        assets.materials.count(),
        "meshes",
        len(scene.meshes),
        "geometry_bytes",
        geometry_bytes,
        "texture_bytes",
        texture_bytes,
        "checksum",
        checksum,
    )
