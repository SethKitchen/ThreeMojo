# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Tests for spring chains: things that hang and swing."""

from core.assets import Assets
from core.object3d import Object3D
from core.scene import Scene
from core.user_data import UserData
from extensions.attire.springs import (
    SPRING_KEY,
    SpringChain,
    SpringCollider,
    SpringSettings,
    add_spring_chain,
    body_colliders,
    chain_settings,
    nearest_on_segment,
    push_out,
    unit_or_down,
    vrm_spring_json,
)
from loaders.json import parse_json
from math.vector3 import Vector3
from std.math import nan
from std.testing import (
    TestSuite,
    assert_almost_equal,
    assert_equal,
    assert_raises,
    assert_true,
)
from tests._attire_fixtures import coarse_person
from units.si import Duration, SECOND


def _frame() -> Duration:
    """Return one thirtieth of a second."""
    return Duration(1.0 / 30.0, SECOND)


def test_settings_check_their_ranges() raises:
    SpringSettings().check()
    var bad = SpringSettings(stiffness=-1)
    with assert_raises(contains="stiffness"):
        bad.check()
    bad = SpringSettings(stiffness=nan[DType.float32]())
    with assert_raises(contains="stiffness"):
        bad.check()
    bad = SpringSettings(gravity=-0.5)
    with assert_raises(contains="gravity must"):
        bad.check()
    bad = SpringSettings(drag=-0.1)
    with assert_raises(contains="drag"):
        bad.check()
    bad = SpringSettings(drag=1.5)
    with assert_raises(contains="drag"):
        bad.check()
    bad = SpringSettings(radius=-1)
    with assert_raises(contains="hit radius"):
        bad.check()
    bad = SpringSettings()
    bad.gravity_direction = Vector3(0, -2, 0)
    with assert_raises(contains="unit vector"):
        bad.check()
    # The upper bound of each range is its own refusal.
    bad = SpringSettings(stiffness=1e7)
    with assert_raises(contains="stiffness"):
        bad.check()
    bad = SpringSettings(gravity=1e7)
    with assert_raises(contains="gravity must"):
        bad.check()
    bad = SpringSettings(radius=1e7)
    with assert_raises(contains="hit radius"):
        bad.check()


def test_capsules_push_points_out() raises:
    var a = Vector3(0, 0, 0)
    var b = Vector3(0, 1, 0)
    assert_equal(nearest_on_segment(Vector3(3, 0.5, 0), a, b).y, 0.5)
    assert_equal(nearest_on_segment(Vector3(3, 4, 0), a, b).y, 1)
    assert_equal(nearest_on_segment(Vector3(3, -4, 0), a, b).y, 0)
    assert_equal(nearest_on_segment(Vector3(3, 4, 0), a, a).y, 0)
    var outside = push_out(Vector3(2, 0.5, 0), a, b, 0.5)
    assert_equal(outside.x, 2)
    var inside = push_out(Vector3(0.1, 0.5, 0), a, b, 0.5)
    assert_almost_equal(inside.x, 0.5, atol=1e-6)
    var on_axis = push_out(Vector3(0, 0.5, 0), a, b, 0.5)
    assert_almost_equal(on_axis.y, 1.0, atol=1e-6)
    assert_equal(unit_or_down(Vector3(0, 0, 0)).y, -1)
    assert_almost_equal(unit_or_down(Vector3(3, 0, 4)).x, 0.6)


def test_a_chain_falls_and_springs_back_toward_rest() raises:
    var scene = Scene()
    var root = scene.add(Object3D())
    # A level chain: gravity pulls its tip down, its stiffness holds it.
    var settings = SpringSettings(stiffness=0.0, gravity=2.0, drag=0.2)
    var chain = add_spring_chain(
        scene,
        root,
        [Vector3(0, 0, 0), Vector3(0.3, 0, 0), Vector3(0.6, 0, 0)],
        settings,
    )
    assert_equal(chain.joint_count(), 2)
    assert_true(scene.get(chain.nodes[0]).user_data.has(String(SPRING_KEY)))
    for _ in range(60):
        scene.update()
        chain.step(scene, _frame())
    scene.update()
    var tip = scene.world_matrix(chain.nodes[2]).transform_point(
        Vector3(0, 0, 0)
    )
    assert_true(tip.y < -0.4)
    # Each bone keeps its length.
    var middle = scene.world_matrix(chain.nodes[1]).transform_point(
        Vector3(0, 0, 0)
    )
    assert_almost_equal((tip - middle).length(), 0.3, atol=1e-4)
    # A stiff chain with no gravity stays level.
    var stiff = add_spring_chain(
        scene,
        root,
        [Vector3(0, 1, 0), Vector3(0.3, 1, 0)],
        SpringSettings(stiffness=4.0, gravity=0.0),
    )
    for _ in range(30):
        scene.update()
        stiff.step(scene, _frame())
    assert_almost_equal(stiff.tails[0].y, 1, atol=1e-4)


def test_a_collider_holds_a_chain_off_the_body() raises:
    var scene = Scene()
    var root = scene.add(Object3D())
    var ball = scene.add(Object3D())
    var chain = add_spring_chain(
        scene,
        root,
        [Vector3(0, 1, 0), Vector3(0, 0.4, 0)],
        SpringSettings(stiffness=0.0, gravity=3.0, radius=0.05),
    )
    # A ball right under the head, a little to one side: the chain falls
    # past it, kept off it.
    chain.colliders.append(
        SpringCollider(ball, Vector3(0.05, 0.6, 0), Vector3(0.05, 0.6, 0), 0.2)
    )
    for _ in range(60):
        scene.update()
        chain.step(scene, _frame())
    var gap = (chain.tails[0] - Vector3(0.05, 0.6, 0)).length()
    assert_true(gap >= 0.245)


def test_a_step_is_refused_when_it_cannot_be_taken() raises:
    var scene = Scene()
    var root = scene.add(Object3D())
    var chain = add_spring_chain(
        scene, root, [Vector3(0, 0, 0), Vector3(0, -0.2, 0)]
    )
    scene.update()
    with assert_raises(contains="above zero"):
        chain.step(scene, Duration(0, SECOND))
    with assert_raises(contains="above zero"):
        chain.step(scene, Duration(1e7, SECOND))
    chain.settings.drag = 3
    with assert_raises(contains="drag"):
        chain.step(scene, _frame())
    with assert_raises(contains="two or more points"):
        _ = add_spring_chain(scene, root, [Vector3(0, 0, 0)])
    with assert_raises(contains="stand apart"):
        _ = add_spring_chain(scene, root, [Vector3(0, 0, 0), Vector3(0, 0, 0)])
    with assert_raises(contains="stiffness"):
        _ = add_spring_chain(
            scene,
            root,
            [Vector3(0, 0, 0), Vector3(0, 1, 0)],
            SpringSettings(stiffness=-2),
        )


def test_a_chain_needs_two_joints_each_placed() raises:
    var scene = Scene()
    var root = scene.add(Object3D())
    var a = scene.add(Object3D())
    var b = scene.add(Object3D())
    var one: List[Vector3] = [Vector3(0, 0, 0)]
    var two: List[Vector3] = [Vector3(0, 0, 0), Vector3(0, -0.2, 0)]
    with assert_raises(contains="two or more joints"):
        _ = SpringChain(root, [a], one.copy(), SpringSettings())
    with assert_raises(contains="two or more joints"):
        _ = SpringChain(root, [a, b], one.copy(), SpringSettings())
    var chain = SpringChain(root, [a, b], two.copy(), SpringSettings())
    assert_equal(chain.joint_count(), 1)


def test_no_chains_write_an_empty_vrm_record() raises:
    var scene = Scene()
    var parsed = parse_json(vrm_spring_json(scene, List[SpringChain]()))
    var root = parsed.root()
    assert_equal(parsed.length(parsed.get(root, "springs")), 0)
    assert_equal(parsed.length(parsed.get(root, "colliders")), 0)


def test_settings_round_trip_through_user_data() raises:
    var scene = Scene()
    var root = scene.add(Object3D())
    var settings = SpringSettings(stiffness=1.5, gravity=0.7, drag=0.25)
    settings.radius = 0.04
    var chain = add_spring_chain(
        scene, root, [Vector3(0, 0, 0), Vector3(0, -0.2, 0)], settings
    )
    var read = chain_settings(scene.get(chain.nodes[0]).user_data)
    assert_almost_equal(read.stiffness, 1.5)
    assert_almost_equal(read.gravity, 0.7)
    assert_almost_equal(read.drag, 0.25)
    assert_almost_equal(read.radius, 0.04)
    assert_almost_equal(read.gravity_direction.y, -1)
    with assert_raises(contains="keeps no spring chain"):
        _ = chain_settings(UserData())
    var record = chain.record()
    var missing = UserData()
    missing.set_json(String(SPRING_KEY), "{}")
    with assert_raises(contains="needs stiffness"):
        _ = chain_settings(missing)
    var short = UserData()
    record.set_json("gravityDir", "[0,-1]")
    short.set_json(String(SPRING_KEY), record.to_json())
    with assert_raises(contains="three components"):
        _ = chain_settings(short)
    var wrong = UserData()
    record.set_json("gravityDir", "[0,-1,0]")
    record.set_number("dragForce", 7)
    wrong.set_json(String(SPRING_KEY), record.to_json())
    with assert_raises(contains="drag"):
        _ = chain_settings(wrong)


def test_chains_write_in_the_shape_of_vrm() raises:
    var scene = Scene()
    var assets = Assets()
    var person = coarse_person(scene, assets)
    var colliders = body_colliders(person)
    assert_equal(len(colliders), 12)
    var chains = List[SpringChain]()
    chains.append(
        add_spring_chain(
            scene, person.bones[0], [Vector3(0, 0, 0), Vector3(0, -0.3, 0)]
        )
    )
    chains[0].colliders = colliders.copy()
    chains.append(
        add_spring_chain(
            scene,
            person.bones[4],
            [Vector3(0, 0.2, 0), Vector3(0, 0.3, 0), Vector3(0, 0.4, 0)],
        )
    )
    var text = vrm_spring_json(scene, chains)
    var document = parse_json(text)
    var root = document.root()
    assert_equal(document.string(document.get(root, "specVersion")), "1.0")
    assert_equal(document.length(document.get(root, "colliders")), 12)
    assert_equal(document.length(document.get(root, "colliderGroups")), 12)
    var springs = document.get(root, "springs")
    assert_equal(document.length(springs), 2)
    var second = document.at(springs, 1)
    assert_equal(document.length(document.get(second, "joints")), 3)
    # The head's collider is a sphere; the others are capsules.
    var last = document.at(document.get(root, "colliders"), 11)
    var shape = document.get(last, "shape")
    assert_true(document.has(shape, "sphere"))
    var first = document.at(document.get(root, "colliders"), 0)
    assert_true(document.has(document.get(first, "shape"), "capsule"))


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
