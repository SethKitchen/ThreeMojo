# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Cached vehicle resources survive sensor coverage texture growth."""

from core.geometry_store import GeometryId
from extensions.carla.actor import ActorId
from extensions.carla.camera_render import CarlaRenderer
from render.texture_store import NO_TEXTURE
from std.testing import TestSuite, assert_equal, assert_true
from test_carla_model_cache import _gltf, _registry
from test_carla_render_scene import _small, _world
from test_scratch import TestScratch


def test_cached_vehicle_survives_sensor_texture_growth() raises:
    # Paint/head/tail slots are replaced by ActorVisuals. Put the mask on
    # the fixture's untagged fourth primitive so it retains the glTF map.
    var text = _gltf().replace(
        '"extras":{"carla":"other"}',
        (
            '"extras":{"carla":"other"},"alphaMode":"MASK",'
            '"alphaCutoff":0.5,"pbrMetallicRoughness":'
            '{"baseColorTexture":{"index":0}}'
        ),
    )
    var registry = _registry("sensor-models", text)
    var camera = ActorId(0)
    var cars = List[ActorId]()
    var walker = ActorId(0)
    var world = _world(camera, cars, walker)
    var view = CarlaRenderer(world, _small(), 1, 8, False, registry=registry^)
    view.sun.shadow.map_size = 64
    view.update(world)
    var first = view.actors.vehicles[0].first_mesh
    var count = view.actors.vehicles[0].mesh_count
    var source_material = view.scene.meshes[first + 3].material
    var source_texture = view.assets.materials.get(source_material).map
    assert_true(source_texture != NO_TEXTURE)
    var geometry_count = view.assets.geometries.count()
    var texture_count = view.assets.textures.count()
    var geometry_ids = List[GeometryId]()
    for i in range(count):
        geometry_ids.append(view.scene.meshes[first + i].geometry)
    var first_paint = view.actors.vehicles[0].paint
    var original_red = view.assets.materials.get(first_paint).color.r
    _ = view.render_semantic(world, camera)
    _ = view.render_depth(world, camera)
    assert_true(view.assets.textures.count() > texture_count)
    var after_capture = view.assets.textures.count()
    var old_vehicles = len(view.actors.vehicles)
    var blueprint = world.get_blueprint_library().at("vehicle.lincoln.mkz")
    blueprint.set_attribute("color", "20,40,200")
    var pose = world.get_transform(cars[0])
    pose.location.x = 80
    _ = world.spawn_actor(blueprint, pose)
    view.update(world)
    assert_equal(len(view.actors.vehicles), old_vehicles + 1)
    assert_equal(view.assets.geometries.count(), geometry_count)
    assert_equal(view.assets.textures.count(), after_capture)
    var next = view.actors.vehicles[old_vehicles].first_mesh
    assert_equal(view.actors.vehicles[old_vehicles].mesh_count, count)
    for i in range(count):
        assert_equal(view.scene.meshes[next + i].geometry, geometry_ids[i])
    var next_source = view.scene.meshes[next + 3].material
    assert_true(next_source != source_material)
    assert_equal(view.assets.materials.get(next_source).map, source_texture)
    var next_paint = view.actors.vehicles[old_vehicles].paint
    assert_true(next_paint != first_paint)
    assert_equal(view.assets.materials.get(first_paint).color.r, original_red)
    assert_equal(view.assets.materials.get(next_paint).color.b, 200)
    _ = view.render_semantic(world, camera)
    _ = view.render_depth(world, camera)
    assert_equal(view.assets.textures.count(), after_capture)
    assert_equal(view.assets.geometries.count(), geometry_count)


def main() raises:
    with TestScratch():
        TestSuite.discover_tests[__functions_in_module()]().run()
