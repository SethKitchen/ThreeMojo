# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""CARLA rendering: one camera's RGB, semantic and depth images.

The world and the renderer are `test_carla_render_scene`'s: see its
docstring for the town they stand on. These tests draw whole frames, so
each suite holds a few, and the coverage run measures them side by side.
"""

from extensions.carla.actor import ActorId
from extensions.carla.sensor import ROAD, SKY, cityscapes_color, decode_depth
from std.testing import TestSuite, assert_equal, assert_true
from test_carla_render_scene import _renderer, _same, _world
from units.si import METER


def test_render_rgb_semantic_and_depth() raises:
    var camera = ActorId(0)
    var cars = List[ActorId]()
    var walker = ActorId(0)
    var world = _world(camera, cars, walker)
    var view = _renderer(world)
    # Rendering before an update draws the sky first.
    var noon = view.render_rgb(world, camera)
    assert_equal(noon.width, 16)
    assert_equal(noon.height, 12)
    # The sky at the top is brighter blue than red.
    var top = noon.get_pixel(8, 0)
    assert_true(top.b > top.r)
    var semantic = view.render_semantic(world, camera)
    _same(semantic.get_pixel(8, 0), cityscapes_color(SKY))
    _same(semantic.get_pixel(8, 11), cityscapes_color(ROAD))
    var depth = view.render_depth(world, camera)
    assert_equal(decode_depth(depth.get_pixel(8, 0)).to(METER), 1000)
    var near = decode_depth(depth.get_pixel(8, 11)).to(METER)
    # The bottom row looks 5 + 36.9 degrees down from 2 m: the road about
    # 2.9 m ahead, less a little for the tilt of the row's plane.
    assert_true(near > 1.5 and near < 4)
    var tags = view.semantic_tags(world)
    assert_equal(len(tags), len(view.scene.meshes))


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
