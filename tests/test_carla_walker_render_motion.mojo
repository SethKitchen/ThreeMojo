# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Issue #290 counterexample using only the pre-fix public rendering API.

A walker travels at 1.5 m/s for 0.75 seconds. Its legs must alternate;
the original fixed stride(speed) leaves the left leg positive throughout.
"""

from core.assets import Assets
from core.scene import Scene
from extensions.carla.actor import ActorId
from extensions.carla.physics.walker import WalkerControl
from extensions.carla.render_actors import ActorVisuals
from extensions.carla.world import World
from math.vector3 import Vector3
from std.testing import (
    TestSuite,
    assert_almost_equal,
    assert_equal,
    assert_false,
    assert_true,
)
from tests.test_carla_world import _pose, _spawn, _world
from units.si import Duration, SECOND, Velocity


def _moving_world(mut walker: ActorId) raises -> World:
    var world = _world()
    walker = _spawn(world, "walker.pedestrian.0015", _pose(20, -4.5, 1.06, 0))
    var control = WalkerControl()
    control.speed = Velocity(1.5)
    world.apply_walker_control(walker, control)
    world.set_target_velocity(walker, Vector3(1.5, 0, 0))
    return world^


def test_constant_speed_alternates_without_capture_clock() raises:
    var walker = ActorId(0)
    var world = _moving_world(walker)
    var scene = Scene()
    var assets = Assets()
    var visuals = ActorVisuals()
    visuals.sync(world, scene, assets)
    for _ in range(5):
        _ = world.tick()
    visuals.sync(world, scene, assets)
    var limbs = visuals.walkers[0].limbs.copy()
    var first = scene.node(limbs[0]).quaternion.z
    assert_true(first > 0.05)
    assert_almost_equal(scene.node(limbs[1]).quaternion.z, -first, atol=1e-6)
    assert_almost_equal(scene.node(limbs[2]).quaternion.z, -first, atol=1e-6)
    assert_equal(scene.node(limbs[3]).quaternion.z, first)
    # Ten simulation ticks pass with no camera capture.
    for _ in range(10):
        _ = world.tick()
    assert_almost_equal(world.get_velocity(walker).x, 1.5, atol=1e-5)
    visuals.sync(world, scene, assets)
    assert_true(scene.node(limbs[0]).quaternion.z < -0.05)
    var pose = scene.node(limbs[0]).quaternion
    var meshes = len(scene.meshes)
    var geometries = len(assets.geometries.geometries)
    var materials = len(assets.materials.materials)
    for _ in range(4):
        visuals.sync(world, scene, assets)
        assert_equal(scene.node(limbs[0]).quaternion.z, pose.z)
        assert_equal(scene.node(limbs[0]).quaternion.w, pose.w)
    assert_equal(len(scene.meshes), meshes)
    assert_equal(len(assets.geometries.geometries), geometries)
    assert_equal(len(assets.materials.materials), materials)
    # A renderer created late sees the same pose, rather than phase zero.
    var late_scene = Scene()
    var late_assets = Assets()
    var late_visuals = ActorVisuals()
    late_visuals.sync(world, late_scene, late_assets)
    assert_equal(
        late_scene.node(late_visuals.walkers[0].limbs[0]).quaternion.z, pose.z
    )


def test_stopping_teleport_and_actor_lifecycle() raises:
    var walker = ActorId(0)
    var world = _moving_world(walker)
    var scene = Scene()
    var assets = Assets()
    var visuals = ActorVisuals()
    for _ in range(5):
        _ = world.tick()
    visuals.sync(world, scene, assets)
    var limb = visuals.walkers[0].limbs[0]
    var moving = scene.node(limb).quaternion.z
    world.apply_walker_control(walker, WalkerControl())
    world.set_target_velocity(walker, Vector3(0, 0, 0))
    # Neither control changes nor teleports advance time or reset the pose.
    world.set_transform(walker, _pose(40, -4.5, 1.06, 0))
    visuals.sync(world, scene, assets)
    assert_equal(scene.node(limb).quaternion.z, moving)
    _ = world.tick()
    visuals.sync(world, scene, assets)
    var stopped = scene.node(limb).quaternion.z
    assert_true(stopped > 0 and stopped < moving)
    for _ in range(60):
        _ = world.tick()
    visuals.sync(world, scene, assets)
    assert_almost_equal(scene.node(limb).quaternion.z, 0, atol=1e-6)
    _ = world.destroy_actor(walker)
    _ = world.tick()
    visuals.sync(world, scene, assets)
    assert_false(scene.node(visuals.walkers[0].node).visible)
    var fresh = _spawn(
        world, "walker.pedestrian.0015", _pose(50, -4.5, 1.06, 0)
    )
    visuals.sync(world, scene, assets)
    assert_true(fresh != walker)
    assert_equal(len(visuals.walkers), 2)
    assert_equal(scene.node(visuals.walkers[1].limbs[0]).quaternion.z, 0)
    # A stationary airborne walker must not swing from vertical velocity.
    world.set_transform(fresh, _pose(50, -4.5, 10, 0))
    _ = world.tick()
    visuals.sync(world, scene, assets)
    assert_equal(scene.node(visuals.walkers[1].limbs[0]).quaternion.z, 0)


def test_variable_world_steps_and_capture_cadence() raises:
    var id_a = ActorId(0)
    var id_b = ActorId(0)
    var a = _moving_world(id_a)
    var b = _moving_world(id_b)
    var scene_a = Scene()
    var scene_b = Scene()
    var assets_a = Assets()
    var assets_b = Assets()
    var visual_a = ActorVisuals()
    var visual_b = ActorVisuals()
    for dt in [Float32(0.01), 0.04, 0.03, 0.07, 0.1]:
        var settings = a.get_settings()
        settings.fixed_delta_seconds = Duration(dt, SECOND)
        _ = a.apply_settings(settings)
        _ = b.apply_settings(settings)
        _ = a.tick()
        _ = b.tick()
        visual_a.sync(a, scene_a, assets_a)
        visual_a.sync(a, scene_a, assets_a)
    visual_b.sync(b, scene_b, assets_b)
    for k in range(4):
        assert_equal(
            scene_a.node(visual_a.walkers[0].limbs[k]).quaternion.z,
            scene_b.node(visual_b.walkers[0].limbs[k]).quaternion.z,
        )


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
