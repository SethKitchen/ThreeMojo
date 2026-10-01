# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Repeated weather and sensor captures keep their state and silhouettes."""

from core.geometry_store import GeometryId
from core.object3d import Object3D
from extensions.carla.actor import ActorId
from extensions.carla.cameras import DVSEvent, _by_time
from extensions.carla.mesh_factory import ROAD_SURFACE
from extensions.carla.sensor import ROAD, VEGETATION
from extensions.carla.weather import weather_preset
from geometries.box import box
from materials.material import Material
from objects.mesh import Mesh
from render.framebuffer import Color
from render.texture import COVERAGE, Texture, float_texture
from std.testing import TestSuite, assert_equal, assert_raises, assert_true
from test_carla_render_scene import _renderer, _world
from units.si import METER, Length


def test_event_sort_is_stable_for_interleaved_pixel_runs() raises:
    var events = List[DVSEvent]()
    for pixel in range(4096):
        events.append(DVSEvent(pixel, 0, 20, True))
        events.append(DVSEvent(pixel, 0, 10, False))
    var ordered = _by_time(events^)
    for pixel in range(4096):
        assert_equal(ordered[pixel].t, 10)
        assert_equal(ordered[pixel].x, pixel)
        assert_equal(ordered[pixel + 4096].t, 20)
        assert_equal(ordered[pixel + 4096].x, pixel)
    assert_equal(len(_by_time(List[DVSEvent]())), 0)
    var one: List[DVSEvent] = [DVSEvent(1, 2, 3, True)]
    assert_equal(_by_time(one^)[0].t, 3)
    var odd: List[DVSEvent] = [
        DVSEvent(0, 0, 3, True),
        DVSEvent(1, 0, 1, True),
        DVSEvent(2, 0, 2, True),
    ]
    var sorted = _by_time(odd^)
    assert_equal(sorted[0].t, 1)
    assert_equal(sorted[2].t, 3)


def test_weather_reuses_resources_and_repeats_roughness() raises:
    var camera = ActorId(0)
    var cars = List[ActorId]()
    var walker = ActorId(0)
    var world = _world(camera, cars, walker)
    var view = _renderer(world)
    world.set_weather(weather_preset("HardRainNoon"))
    view.update(world)
    var id = view.town.materials.surface(ROAD_SURFACE)
    var first = view.assets.materials.get(id)
    var cubes = view.assets.cube_textures.count()
    var textures = view.assets.textures.count()
    var materials = view.assets.materials.count()
    view.update(world)
    assert_equal(view.assets.materials.get(id).roughness, first.roughness)
    assert_equal(
        view.assets.materials.get(id).roughness_map, first.roughness_map
    )
    world.set_weather(weather_preset("WetSunset"))
    view.update(world)
    assert_equal(view.assets.cube_textures.count(), cubes)
    assert_equal(view.assets.textures.count(), textures)
    assert_equal(view.assets.materials.count(), materials)
    assert_equal(view.assets.materials.get(id).roughness, 1)
    assert_equal(
        view.assets.materials.get(id).roughness_map, first.roughness_map
    )


def test_sensor_overrides_refresh_alpha_and_preserve_coverage_settings() raises:
    var camera = ActorId(0)
    var cars = List[ActorId]()
    var walker = ActorId(0)
    var world = _world(camera, cars, walker)
    var view = _renderer(world)
    var image = float_texture(1, 1, [Float32(0.2), 0.3, 0.4, 0.5])
    var map = view.assets.textures.add(image^)
    var source = Material(Color(50, 60, 70), map=map, alpha_test=0.25)
    source.visible = False
    var id = view.assets.materials.add(source)
    var first = view._sensor_material(id, ROAD)
    var second = view._sensor_material(id, VEGETATION)
    assert_true(first != second)
    var flat = view.assets.materials.get(first)
    assert_equal(flat.alpha_test, 0.25)
    assert_equal(flat.visible, False)
    assert_equal(view.assets.textures.get(flat.map).data[0], 1)
    assert_equal(view.assets.textures.get(flat.map).data[3], 0.5)
    view.assets.textures.textures[map.value].data[3] = 0.75
    view.coverage_read.clear()
    assert_equal(view._sensor_material(id, ROAD), first)
    assert_equal(view.assets.textures.get(flat.map).data[3], 0.75)
    var hashed = Material(Color(255, 255, 255))
    hashed.alpha_hash = True
    var hash_id = view.assets.materials.add(hashed)
    var hash_flat = view._sensor_material(hash_id, ROAD)
    assert_equal(view.assets.materials.get(hash_flat).alpha_hash, True)
    var covered = Material(Color(255, 255, 255), map=map)
    covered.alpha_to_coverage = True
    var covered_id = view.assets.materials.add(covered)
    var covered_flat = view._sensor_material(covered_id, ROAD)
    assert_equal(
        view.assets.materials.get(covered_flat).alpha_to_coverage, True
    )


def test_cutout_depth_and_capture_materials_are_stable() raises:
    var camera = ActorId(0)
    var cars = List[ActorId]()
    var walker = ActorId(0)
    var world = _world(camera, cars, walker)
    var view = _renderer(world)
    var before = view.render_depth(world, camera)
    var pixels: List[UInt8] = [255, 0, 0, 0]
    var texture = Texture(1, 1, pixels^, alpha=COVERAGE)
    var map = view.assets.textures.add(texture^)
    var material = view.assets.materials.add(
        Material(Color(255, 0, 0), map=map, alpha_test=0.5)
    )
    var node = Object3D()
    node.set_position(12, 2, 1.75)
    view.scene.add_mesh(
        Mesh(
            view.assets.geometries.add(
                box(Length(1, METER), Length(10, METER), Length(10, METER))
            ),
            material,
            view.scene.add(node^),
        )
    )
    view.scene.update()
    var after = view.render_depth(world, camera)
    for y in range(before.height):
        for x in range(before.width):
            assert_equal(before.get_pixel(x, y).r, after.get_pixel(x, y).r)
            assert_equal(before.get_pixel(x, y).g, after.get_pixel(x, y).g)
            assert_equal(before.get_pixel(x, y).b, after.get_pixel(x, y).b)
    var count = view.assets.materials.count()
    var images = view.assets.textures.count()
    _ = view.render_semantic(world, camera)
    _ = view.render_depth(world, camera)
    assert_equal(view.assets.materials.count(), count)
    assert_equal(view.assets.textures.count(), images)
    var original = view.scene.meshes[0].material
    view.scene.meshes[0].geometry = GeometryId(-1)
    with assert_raises():
        _ = view.render_depth(world, camera)
    assert_equal(view.scene.meshes[0].material, original)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
