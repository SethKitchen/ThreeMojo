# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Rejected cascade updates preserve scene state, issue #361."""

from cameras.perspective_camera import PerspectiveCamera
from core.assets import Assets
from core.object3d import NodeId
from core.scene import Scene
from lights.csm import CSM
from lights.light import POINT
from lights.shadow import LightShadow
from lights.sun_light import SunLight, fit_sun
from math.vector3 import Vector3
from renderers.light_probe_grid_utils import (
    replace_sun_lights,
    restore_sun_lights,
)
from std.math import inf, nan
from std.testing import TestSuite, assert_equal, assert_raises
from units.si import Angle, DEGREE, Length, METER


def _camera() raises -> PerspectiveCamera:
    """Return a small perspective volume for cascade fitting."""
    return PerspectiveCamera(
        Angle(60, DEGREE), 1, Length(1, METER), Length(10, METER)
    )


def test_rejected_sun_updates_keep_both_cascades_and_world_state() raises:
    var scene = Scene()
    var sun = SunLight(scene)
    var camera = _camera()
    sun.update(scene, camera)
    var first = scene.lights[sun.lights[0]]
    var second = scene.lights[sun.lights[1]]
    var position = scene.world_position(sun.nodes[0])
    var bad: List[Float32] = [-1, nan[DType.float32](), inf[DType.float32]()]
    for at in range(len(bad)):
        sun.intensity = bad[at]
        with assert_raises(contains="intensity"):
            sun.update(scene, camera)
        assert_equal(scene.lights[sun.lights[0]].intensity, first.intensity)
        assert_equal(scene.lights[sun.lights[1]].intensity, second.intensity)
        # This read also proves the rejected update did not leave the scene stale.
        assert_equal(scene.world_position(sun.nodes[0]).x, position.x)
        assert_equal(scene.world_position(sun.nodes[0]).y, position.y)
        assert_equal(scene.world_position(sun.nodes[0]).z, position.z)
    sun.intensity = 2
    sun.update(scene, camera)
    assert_equal(scene.lights[sun.lights[0]].intensity, Float32(2))
    assert_equal(scene.lights[sun.lights[1]].intensity, Float32(2))


def test_a_rejected_sun_constructor_adds_no_nodes_or_lights() raises:
    var scene = Scene()
    with assert_raises(contains="intensity"):
        _ = SunLight(scene, intensity=-1)
    assert_equal(scene.count(), 0)
    assert_equal(len(scene.lights), 0)


def test_sun_mapping_errors_are_rejected_before_indexing() raises:
    for mode in range(6):
        var scene = Scene()
        var sun = SunLight(scene)
        var node = sun.nodes[0]
        var before = scene.world_position(node)
        if mode == 0:
            _ = sun.lights.pop()
        elif mode == 1:
            _ = sun.nodes.pop()
        elif mode == 2:
            _ = sun.targets.pop()
        elif mode == 3:
            sun.lights[0] = -1
        elif mode == 4:
            sun.targets[0] = NodeId(9999)
            scene.lights[sun.lights[0]].target = NodeId(9999)
        else:
            sun.lights[1] = sun.lights[0]
        with assert_raises():
            sun.update(scene, _camera())
        assert_equal(scene.world_position(node).y, before.y)


def test_public_sun_fitting_checks_shadow_settings_first() raises:
    var shadow = LightShadow()
    shadow.map_size = 0
    with assert_raises(contains="shadow map"):
        _ = fit_sun(Scene(), _camera(), Vector3(0, 1, 0), shadow)
    shadow.map_size = 8
    shadow.radius = inf[DType.float32]()
    with assert_raises(contains="radius"):
        _ = fit_sun(Scene(), _camera(), Vector3(0, 1, 0), shadow)


def test_csm_mapping_and_frustum_shapes_are_checked_before_update() raises:
    for mode in range(8):
        var scene = Scene()
        var camera = _camera()
        var csm = CSM(scene, camera, shadow_map_size=8)
        var node = csm.nodes[0]
        var before = scene.world_position(node)
        if mode == 0:
            _ = csm.lights.pop()
        elif mode == 1:
            _ = csm.nodes.pop()
        elif mode == 2:
            _ = csm.targets.pop()
        elif mode == 3:
            csm.lights[0] = -1
        elif mode == 4:
            _ = csm.frustums.pop()
        elif mode == 5:
            _ = csm.frustums[0].near.pop()
        elif mode == 6:
            _ = csm.frustums[0].far.pop()
        else:
            scene.lights[csm.lights[0]].kind = POINT
        with assert_raises():
            csm.update(scene, camera)
        assert_equal(scene.world_position(node).y, before.y)


def test_csm_removal_checks_parallel_mapping_lengths() raises:
    var scene = Scene()
    var csm = CSM(scene, _camera(), shadow_map_size=8)
    _ = csm.targets.pop()
    with assert_raises(contains="mapping"):
        csm.remove(scene)


def test_two_casting_suns_can_be_replaced_and_restored_together() raises:
    var scene = Scene()
    var first = SunLight(scene)
    var second = SunLight(scene)
    scene.node(second.nodes[1]).set_position(1, 1, 0)
    scene.update()
    for index in range(len(scene.lights)):
        scene.lights[index].cast_shadow = True
    var before = scene.world_position(second.nodes[1])
    var saved = replace_sun_lights(scene, Assets())
    assert_equal(scene.lights[first.lights[0]].intensity, Float32(0))
    assert_equal(scene.lights[second.lights[0]].intensity, Float32(0))
    assert_equal(scene.lights[first.lights[1]].cascade.is_cascade(), False)
    assert_equal(scene.lights[second.lights[1]].cascade.is_cascade(), False)
    _ = scene.world_position(second.nodes[1])
    restore_sun_lights(scene, saved)
    for index in range(len(scene.lights)):
        assert_equal(scene.lights[index].intensity, Float32(1))
        assert_equal(scene.lights[index].cascade.is_cascade(), True)
    assert_equal(scene.world_position(second.nodes[1]).x, before.x)
    assert_equal(scene.world_position(second.nodes[1]).y, before.y)


def test_replacement_preflight_failure_keeps_earlier_suns_unchanged() raises:
    var scene = Scene()
    var first = SunLight(scene)
    var second = SunLight(scene)
    for index in range(len(scene.lights)):
        scene.lights[index].cast_shadow = True
    var before = scene.world_position(first.nodes[1])
    scene.lights[second.lights[1]].target = NodeId(9999)
    with assert_raises():
        _ = replace_sun_lights(scene, Assets())
    for index in range(len(scene.lights)):
        assert_equal(scene.lights[index].intensity, Float32(1))
        assert_equal(scene.lights[index].cascade.is_cascade(), True)
    assert_equal(scene.world_position(first.nodes[1]).y, before.y)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
