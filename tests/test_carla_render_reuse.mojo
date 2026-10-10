# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""A new actor takes over a destroyed actor's model of the same key.

Repeated spawn and destroy cycles must keep the scene and the stores the
same size. Survivors keep their materials, and a destroyed actor's id
names no model.
"""

from core.assets import Assets
from core.scene import Scene
from extensions.carla.actor import ActorId
from extensions.carla.assets import AssetRegistry, parse_manifest
from extensions.carla.render_actors import (
    ActorVisuals,
    clothing,
    vehicle_color,
)
from extensions.carla.world import World
from render.framebuffer import Color
from std.os import makedirs
from std.pathlib import Path
from std.testing import TestSuite, assert_equal, assert_false, assert_true
from test_carla_assets import _entry, _file, _manifest
from test_carla_model_cache import _gltf
from test_carla_render_scene import _world
from test_scratch import TestScratch, temporary_path


def _counts(scene: Scene, assets: Assets) -> List[Int]:
    return [
        scene.count(),
        len(scene.meshes),
        len(scene.lights),
        assets.materials.count(),
        assets.geometries.count(),
        assets.textures.count(),
    ]


def _rgb(color: Color) -> List[Int]:
    return [Int(color.r), Int(color.g), Int(color.b)]


def _cached_registry() raises -> AssetRegistry:
    # One cached model for every vehicle and every walker.
    var folder = temporary_path("reuse-models/")
    makedirs(folder, exist_ok=True)
    Path(folder + "model.gltf").write_text(_gltf())
    Path(folder + "checker.png").write_bytes(
        Path("assets/gltf/checker.png").read_bytes()
    )
    return AssetRegistry(
        parse_manifest(
            _manifest(
                _entry(
                    "car",
                    "model",
                    _file("model", "model.gltf")
                    + ","
                    + _file("support", "checker.png"),
                    ',"forward":"+x"',
                ),
                '{"vehicle.*":"car","walker.*":"car"}',
            )
        ),
        folder,
    )


def _cycle(
    mut world: World,
    mut car: ActorId,
    mut walker: ActorId,
    color: String,
    mut dead: List[ActorId],
) raises:
    # Destroy the sedan and the walker, and spawn the same kinds where
    # they stood.
    var library = world.get_blueprint_library()
    var sedan = library.at("vehicle.lincoln.mkz")
    sedan.set_attribute("color", color)
    var pose = world.get_transform(car)
    dead.append(car)
    _ = world.destroy_actor(car)
    car = world.spawn_actor(sedan, pose)
    pose = world.get_transform(walker)
    dead.append(walker)
    _ = world.destroy_actor(walker)
    walker = world.spawn_actor(library.at("walker.pedestrian.0015"), pose)


def _no_stale_models(visuals: ActorVisuals, dead: List[ActorId]) raises:
    for id in dead:
        for v in visuals.vehicles:
            assert_true(v.actor != id)
        for w in visuals.walkers:
            assert_true(w.actor != id)


def test_procedural_cycles_reuse_hidden_models() raises:
    var camera = ActorId(0)
    var cars = List[ActorId]()
    var walker = ActorId(0)
    var world = _world(camera, cars, walker)
    var scene = Scene()
    var assets = Assets()
    var visuals = ActorVisuals()
    visuals.sync(world, scene, assets)
    var counts = _counts(scene, assets)
    var van = _rgb(assets.materials.get(visuals.vehicles[1].paint).color)
    var other = _rgb(assets.materials.get(visuals.vehicles[2].paint).color)
    var stranger = visuals.walkers[1].clothes.copy()
    var stranger_shirt = _rgb(assets.materials.get(stranger[0]).color)
    var car = cars[0]
    var dead = List[ActorId]()
    for cycle in range(4):
        _cycle(world, car, walker, String(40 * cycle) + ",200,30", dead)
        visuals.sync(world, scene, assets)
        assert_equal(_counts(scene, assets), counts)
        assert_equal(len(visuals.vehicles), 3)
        assert_equal(len(visuals.walkers), 2)
        # The first models now belong to the new actors, shown and
        # recolored.
        ref v = visuals.vehicles[0]
        assert_true(v.actor == car)
        assert_true(scene.node(v.node).visible)
        assert_equal(
            _rgb(assets.materials.get(v.paint).color),
            _rgb(vehicle_color(world.actor(car))),
        )
        assert_equal(_rgb(assets.materials.get(v.paint).color)[0], 40 * cycle)
        ref w = visuals.walkers[0]
        assert_true(w.actor == walker)
        assert_true(scene.node(w.node).visible)
        var look = clothing(walker)
        assert_equal(
            _rgb(assets.materials.get(w.clothes[0]).color), _rgb(look[0])
        )
        assert_equal(
            _rgb(assets.materials.get(w.clothes[1]).color), _rgb(look[1])
        )
        assert_equal(
            _rgb(assets.materials.get(w.clothes[2]).color), _rgb(look[2])
        )
        # Survivors keep their own materials.
        assert_equal(
            _rgb(assets.materials.get(visuals.vehicles[1].paint).color), van
        )
        assert_equal(
            _rgb(assets.materials.get(visuals.vehicles[2].paint).color), other
        )
        assert_equal(
            _rgb(assets.materials.get(stranger[0]).color), stranger_shirt
        )
        _no_stale_models(visuals, dead)
    # A hidden model of another key is not taken over: the van's model
    # waits for a van while a living sedan keeps its own.
    var library = world.get_blueprint_library()
    var van_pose = world.get_transform(cars[1])
    _ = world.destroy_actor(cars[1])
    var sedan_pose = van_pose
    sedan_pose.location.x = sedan_pose.location.x + 30
    var sedan = world.spawn_actor(library.at("vehicle.lincoln.mkz"), sedan_pose)
    visuals.sync(world, scene, assets)
    assert_equal(len(visuals.vehicles), 4)
    assert_true(visuals.vehicles[3].actor == sedan)
    assert_false(scene.node(visuals.vehicles[1].node).visible)
    var next = world.spawn_actor(
        library.at("vehicle.sprinter.mercedes"), van_pose
    )
    visuals.sync(world, scene, assets)
    assert_equal(len(visuals.vehicles), 4)
    assert_true(visuals.vehicles[1].actor == next)
    assert_true(scene.node(visuals.vehicles[1].node).visible)
    # A living walker of the same key keeps its model: a second one gets
    # its own.
    var walker_pose = world.get_transform(walker)
    walker_pose.location.x = walker_pose.location.x + 10
    var twin = world.spawn_actor(
        library.at("walker.pedestrian.0015"), walker_pose
    )
    visuals.sync(world, scene, assets)
    assert_equal(len(visuals.walkers), 3)
    assert_true(visuals.walkers[0].actor == walker)
    assert_true(visuals.walkers[2].actor == twin)


def test_cached_cycles_reuse_hidden_models() raises:
    var registry = _cached_registry()
    var camera = ActorId(0)
    var cars = List[ActorId]()
    var walker = ActorId(0)
    var world = _world(camera, cars, walker)
    var scene = Scene()
    var assets = Assets()
    var visuals = ActorVisuals()
    visuals.sync(world, scene, assets, registry)
    var counts = _counts(scene, assets)
    assert_equal(len(visuals.walkers[0].clothes), 0)
    var car = cars[0]
    var dead = List[ActorId]()
    for cycle in range(3):
        _cycle(world, car, walker, "20,40," + String(100 + cycle), dead)
        visuals.sync(world, scene, assets, registry)
        assert_equal(_counts(scene, assets), counts)
        assert_true(visuals.vehicles[0].actor == car)
        assert_true(visuals.walkers[0].actor == walker)
        assert_equal(
            Int(assets.materials.get(visuals.vehicles[0].paint).color.b),
            100 + cycle,
        )
        _no_stale_models(visuals, dead)
    # A sync without the cache builds a procedural model: the cached one's
    # key does not match.
    _cycle(world, car, walker, "1,2,3", dead)
    visuals.sync(world, scene, assets)
    assert_equal(len(visuals.vehicles), 4)
    assert_equal(len(visuals.walkers), 3)
    assert_true(visuals.vehicles[3].actor == car)
    assert_true(visuals.walkers[2].actor == walker)
    assert_false(scene.node(visuals.vehicles[0].node).visible)


def main() raises:
    with TestScratch():
        TestSuite.discover_tests[__functions_in_module()]().run()
