# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""The village's raid: its parameters, each raider's strength, the clip the
warden plays for each attack, and the ring of stones."""

from core.assets import Assets
from core.scene import Scene
from extensions.village.boss import (
    CHARGE,
    CLEAVE,
    ROCKFALL,
    SLAM,
    STOMP,
    SUMMON,
    Boss,
    BossAttack,
)
from extensions.village.combat import (
    CAST,
    FALL,
    FREE,
    GROUND_WAVE,
    HEAVY,
    MEND,
    PIERCE,
    PLUNGE,
    STAGGER,
    move_data,
)
from extensions.village.party import (
    ARCHER,
    HEALER,
    STRIKER,
    TANK,
    PartyRole,
)
from extensions.village.raid import (
    RING_RADIUS,
    STONES,
    RaidParameters,
    add_stones,
    member_fighter,
    puppet_move,
    stone_places,
)
from extensions.village.surfaces import house_looks
from math.vector3 import Vector3
from std.math import sqrt
from std.testing import (
    TestSuite,
    assert_almost_equal,
    assert_equal,
    assert_raises,
    assert_true,
)
from units.si import SECOND


def test_the_default_raid_has_its_warden_and_four_raiders() raises:
    var raid = RaidParameters()
    raid.check()
    assert_equal(len(raid.raiders), 4)
    assert_true(raid.raiders[0].role == TANK)
    assert_true(raid.raiders[3].role == ARCHER)
    var crowd = RaidParameters()
    for _ in range(5):
        crowd.raiders.append(crowd.raiders[0].copy())
    with assert_raises(contains="8 raiders"):
        crowd.check()
    var odd = RaidParameters()
    odd.raiders[1].role = PartyRole(7)
    with assert_raises(contains="role"):
        odd.check()


def test_each_role_has_its_strength() raises:
    var tank = member_fighter(TANK)
    var healer = member_fighter(HEALER)
    var striker = member_fighter(STRIKER)
    var archer = member_fighter(ARCHER)
    assert_equal(tank.health, 900)
    assert_true(tank.parry.to(SECOND) > 0)
    assert_equal(healer.health, 420)
    assert_equal(striker.health, 520)
    assert_equal(archer.health, 450)
    assert_equal(archer.parry.to(SECOND), 0)
    assert_equal(striker.limit_gain, 0)
    with assert_raises(contains="four"):
        _ = member_fighter(PartyRole(-1))


def test_the_warden_plays_a_clip_for_each_attack() raises:
    var boss = Boss(1, 3)
    var still = puppet_move(boss)
    assert_true(still[0] == FREE)
    var moves: List[Int] = [
        HEAVY.value,
        PLUNGE.value,
        GROUND_WAVE.value,
        PIERCE.value,
        CAST.value,
        MEND.value,
    ]
    var attacks: List[BossAttack] = [
        CLEAVE,
        SLAM,
        STOMP,
        CHARGE,
        ROCKFALL,
        SUMMON,
    ]
    for k in range(len(attacks)):
        boss.attack = attacks[k]
        boss.clock = 0.3
        var shown = puppet_move(boss)
        assert_equal(shown[0].value, moves[k])
        assert_almost_equal(shown[1], 0.3, atol=1e-6)
        # The clip strikes as the attack does.
        var data = move_data(shown[0])
        var strike = data.startup.to(SECOND) + data.active.to(SECOND) * 0.5
        assert_almost_equal(
            shown[2], max(Float32(0.2), boss.windup() / strike), atol=1e-4
        )
    boss.staggered = 3
    var reel = puppet_move(boss)
    assert_true(reel[0] == STAGGER)
    assert_true(reel[2] > 1)
    boss.health = 0
    assert_true(puppet_move(boss)[0] == FALL)


def test_a_ring_of_stones_stands_around_the_arena() raises:
    var center = Vector3(4, 0, -2)
    var places = stone_places(center)
    assert_equal(len(places), STONES)
    for at in places:
        var dx = at.x - center.x
        var dz = at.z - center.z
        assert_almost_equal(sqrt(dx * dx + dz * dz), RING_RADIUS, atol=1e-4)
    var assets = Assets()
    var scene = Scene()
    var looks = house_looks(assets, 4, 1)
    var heights = List[Float32](length=STONES, fill=0)
    var before = len(scene.meshes)
    var node = add_stones(scene, assets, looks, center, heights)
    assert_equal(len(scene.meshes) - before, 1)
    assert_almost_equal(scene.node(node).position.x, 4, atol=1e-6)
    _ = heights.pop()
    with assert_raises(contains="each stone"):
        _ = add_stones(scene, assets, looks, center, heights)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
