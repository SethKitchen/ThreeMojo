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


def test_empty_custom_draw_list_captures_sky_and_restores_state() raises:
    var camera = ActorId(0)
    var cars = List[ActorId]()
    var walker = ActorId(0)
    var world = _world(camera, cars, walker)
    var view = _renderer(world)
    view.update(world)
    # Scene draw lists are swappable. Keep the corresponding tag and
    # actor-model lists in sync when replacing the town with an empty view.
    view.scene.meshes.clear()
    view.town.tags.clear()
    view.props.tags.clear()
    view.actors.vehicles.clear()
    view.actors.walkers.clear()
    var background = view.scene.background
    var materials = view.assets.materials.count()
    assert_equal(len(view.semantic_tags(world)), 0)
    var semantic = view.render_semantic(world, camera)
    assert_equal(semantic.width, 16)
    assert_equal(semantic.height, 12)
    assert_equal(len(view.scene.meshes), 0)
    assert_equal(view.scene.background.kind, background.kind)
    assert_equal(view.scene.background.cube, background.cube)
    var depth = view.render_depth(world, camera)
    assert_equal(depth.width, 16)
    assert_equal(depth.height, 12)
    for y in range(semantic.height):
        for x in range(semantic.width):
            _same(semantic.get_pixel(x, y), cityscapes_color(SKY))
            # CARLA reserves the far depth (1000 meters) for the sky.
            assert_equal(decode_depth(depth.get_pixel(x, y)).to(METER), 1000)
    assert_equal(len(view.scene.meshes), 0)
    assert_equal(view.scene.background.kind, background.kind)
    assert_equal(view.scene.background.cube, background.cube)
    assert_equal(view.assets.materials.count(), materials)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
