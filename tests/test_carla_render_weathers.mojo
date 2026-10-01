# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""CARLA rendering: the ground-truth cameras first and without effects,
and the RGB camera through the weathers.

The world and the renderer are `test_carla_render_scene`'s: see its
docstring for the town they stand on. These tests draw whole frames, so
each suite holds a few, and the coverage run measures them side by side.
"""

from extensions.carla.actor import ActorId
from extensions.carla.vehicle import LIGHT_LOW_BEAM
from extensions.carla.weather import weather_preset
from std.testing import TestSuite, assert_equal, assert_false, assert_true
from test_carla_render_scene import _renderer, _world


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


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
