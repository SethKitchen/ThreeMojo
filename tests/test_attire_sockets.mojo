# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Tests for sockets on the body and the props that hang from them."""

from core.assets import Assets
from core.buffer_geometry import COLOR, POSITION
from core.object3d import Object3D
from core.scene import Scene
from extensions.attire.props import (
    heater_shield,
    shield_half_width,
    sword_in_scabbard,
)
from extensions.attire.sockets import (
    BACK,
    BELT_FRONT,
    CROWN,
    LEFT_GRIP,
    LEFT_HIP,
    LEFT_SHOULDER,
    RIGHT_GRIP,
    RIGHT_HIP,
    RIGHT_SHOULDER,
    SOCKET_COUNT,
    Socket,
    attach,
    require_socket,
    socket_joint,
    socket_label,
    socket_place,
)
from extensions.humanoid.rig.joints import (
    CHEST,
    HEAD,
    HIPS,
    LEFT_HAND,
    RIGHT_HAND,
    RIGHT_THIGH,
)
from math.vector3 import Vector3
from render.framebuffer import Color
from std.testing import (
    TestSuite,
    assert_almost_equal,
    assert_equal,
    assert_raises,
    assert_true,
)
from tests._attire_fixtures import line_rig
from tests._attire_people import coarse_person
from units.si import Length, METER


def test_sockets_are_named_and_ride_bones() raises:
    assert_equal(socket_label(CROWN), "crown")
    assert_equal(socket_label(LEFT_GRIP), "leftGrip")
    assert_equal(socket_label(Socket(SOCKET_COUNT)), "socket")
    assert_true(BACK.is_valid())
    assert_true(not Socket(-1).is_valid())
    require_socket(BELT_FRONT)
    with assert_raises(contains="named socket"):
        require_socket(Socket(SOCKET_COUNT))
    assert_equal(socket_joint(CROWN), HEAD)
    assert_equal(socket_joint(BACK), CHEST)
    assert_equal(socket_joint(LEFT_HIP), HIPS)
    assert_equal(socket_joint(RIGHT_GRIP), RIGHT_HAND)
    assert_equal(socket_joint(LEFT_GRIP), LEFT_HAND)
    with assert_raises(contains="named socket"):
        _ = socket_joint(Socket(-2))
    with assert_raises(contains="named socket"):
        _ = socket_place(line_rig(), Socket(99))


def test_sockets_stand_where_the_body_has_them() raises:
    var scene = Scene()
    var assets = Assets()
    var person = coarse_person(scene, assets)
    var rig = person.rig.copy()
    var hips = rig.joints[HIPS.value]
    # The crown tops the head; the back is behind the chest and the
    # belt in front of the hips; each hip and shoulder is on its side.
    assert_equal(socket_place(rig, CROWN).y, rig.ends[HEAD.value].y)
    assert_true(socket_place(rig, BACK).z < rig.joints[CHEST.value].z)
    assert_true(socket_place(rig, BELT_FRONT).z > hips.z)
    var right = rig.joints[RIGHT_THIGH.value].x - hips.x
    assert_true((socket_place(rig, RIGHT_HIP).x - hips.x) * right > 0)
    assert_true((socket_place(rig, LEFT_HIP).x - hips.x) * right < 0)
    assert_true(socket_place(rig, RIGHT_SHOULDER).y > hips.y)
    assert_true(socket_place(rig, LEFT_SHOULDER).y > hips.y)
    var grip = socket_place(rig, RIGHT_GRIP)
    var wrist = rig.joints[RIGHT_HAND.value]
    assert_true((grip - wrist).length() > 0.02)
    assert_true(socket_place(rig, LEFT_GRIP).x * grip.x < 0)
    # A node hung from a socket stands there at rest.
    var node = attach(scene, person, LEFT_HIP, Object3D())
    scene.update()
    var world = scene.world_matrix(node)
    var at = world.transform_point(Vector3(0, 0, 0))
    var expected = scene.world_matrix(person.root).transform_point(
        socket_place(rig, LEFT_HIP)
    )
    assert_almost_equal(at.x, expected.x, atol=1e-5)
    assert_almost_equal(at.y, expected.y, atol=1e-5)
    assert_almost_equal(at.z, expected.z, atol=1e-5)


def test_a_rig_with_its_thighs_together_still_has_sides() raises:
    var rig = line_rig()
    rig.joints[RIGHT_THIGH.value] = Vector3(0, 0, 0)
    rig.joints[RIGHT_THIGH.value + 4] = Vector3(0, 0, 0)
    var right = socket_place(rig, RIGHT_HIP)
    var left = socket_place(rig, LEFT_HIP)
    assert_true(right.x > left.x)


def test_a_heater_shield_is_flat_topped_and_pointed() raises:
    assert_equal(shield_half_width(0), 1)
    assert_equal(shield_half_width(0.3), 1)
    assert_almost_equal(shield_half_width(1), 0, atol=1e-6)
    assert_true(shield_half_width(0.8) < 1)
    var shield = heater_shield(
        Length(0.7, METER), Color(30, 60, 150), Color(240, 240, 240)
    )
    ref placed = shield.attribute_view(String(POSITION))
    var lowest = Float32(1)
    var widest = Float32(0)
    for v in range(placed.count()):
        lowest = min(lowest, placed.vector3(v).y)
        widest = max(widest, abs(placed.vector3(v).x))
    assert_almost_equal(lowest, -0.7, atol=1e-5)
    assert_true(widest > 0.25 and widest < 0.35)
    ref colors = shield.attribute_view(String(COLOR))
    assert_true(colors.component(0, 2) > colors.component(0, 0))
    assert_almost_equal(
        colors.component(placed.count() - 1, 0),
        colors.component(placed.count() - 1, 2),
        atol=0.05,
    )
    with assert_raises(contains="positive height"):
        _ = heater_shield(Length(0, METER), Color(0, 0, 0), Color(0, 0, 0))


def test_a_sword_hangs_in_its_scabbard() raises:
    var parts = sword_in_scabbard(Length(0.85, METER))
    assert_equal(len(parts), 2)
    var lowest = Float32(1)
    var highest = Float32(-1)
    for k in range(2):
        assert_true(parts[k].has_attribute(String(COLOR)))
        ref placed = parts[k].attribute_view(String(POSITION))
        for v in range(placed.count()):
            lowest = min(lowest, placed.vector3(v).y)
            highest = max(highest, placed.vector3(v).y)
    assert_true(lowest < -0.85)
    assert_true(highest > 0.15)
    with assert_raises(contains="positive length"):
        _ = sword_in_scabbard(Length(-1, METER))


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
