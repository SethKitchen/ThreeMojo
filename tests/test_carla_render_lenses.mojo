# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""CARLA rendering: a fisheye camera, with and without its mask and its
effects.

The world and the renderer are `test_carla_render_scene`'s: see its
docstring for the town they stand on. These tests draw whole frames, so
each suite holds a few, and the coverage run measures them side by side.
"""

from extensions.carla.actor import ActorId
from extensions.carla.transform import CarlaRotation, CarlaTransform
from extensions.carla.weather import weather_preset
from std.testing import TestSuite, assert_equal
from test_carla_render_scene import _renderer, _world
from units.si import DEGREE, METER, Angle, Length


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


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
