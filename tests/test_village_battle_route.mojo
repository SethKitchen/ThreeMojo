# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""The companion and the raiders find their ways round a wall, and pass
each other and the player on the stairs."""

from extensions.vegetation.ground import Ground, Lot
from extensions.village.companion import Climb
from extensions.village.route import route_grid
from extensions.village.terrain import Floor, Terrain, WallSpan
from math.vector3 import Vector3
from std.testing import TestSuite, assert_true
from tests._village_arena import Arena, arena_parameters
from units.si import METER, Length


def _walled(roof: Bool) raises -> Terrain:
    """Return flat ground with a wall across z -4 from x -6 to 6, and, if
    asked, a roof over the middle."""
    var walls: List[WallSpan] = [WallSpan(-6, -4, 6, -4, 0.1, 0, 3)]
    var floors = List[Floor]()
    if roof:
        floors.append(Floor(Lot(0, 2, 3, 3, 0), 0, 3))
    return Terrain(
        Ground(hill_height=Length(0.0, METER)),
        List[Lot](),
        walls^,
        floors^,
    )


def test_the_companion_goes_round_a_wall_to_the_player() raises:
    var arena = Arena(arena_parameters(0, 0, 6, ally=True))
    arena.terrain = _walled(False)
    arena.battle.set_grid(route_grid(arena.terrain, 0.5, 30))
    arena.player.position = Vector3(0, 0, -12)
    arena.battle.allies[0].character.position = Vector3(0, 0, 2)
    arena.run(12)
    # She went round the wall's end, and stands past it.
    var at = arena.battle.allies[0].character.position
    assert_true(at.z < -5)


def test_under_a_roof_she_takes_no_way() raises:
    var arena = Arena(arena_parameters(0, 0, 6, ally=True))
    arena.terrain = _walled(True)
    arena.battle.set_grid(route_grid(arena.terrain, 0.5, 30))
    arena.player.position = Vector3(0, 0, -12)
    arena.battle.allies[0].character.position = Vector3(0, 0, 2)
    arena.run(0.05)
    # Under the roof, she walks straight at the wall: no way is kept.
    assert_true(len(arena.battle.allies[0].route.way) == 0)


def test_the_raiders_go_round_a_wall_and_pass_on_the_stairs() raises:
    var arena = Arena(arena_parameters(0, 0, 6, raid=True, raiders=2))
    arena.terrain = _walled(False)
    arena.battle.set_grid(route_grid(arena.terrain, 0.5, 30))
    arena.player.position = Vector3(0, 0, -12)
    for k in range(2):
        ref member = arena.battle.members[k]
        member.joined = True
        member.post = Vector3(0, 0, -12)
        member.character.position = Vector3(Float32(k), 0, 2)
    # The warden stands far off, out of the fight.
    arena.battle.wardens[0].character.position = Vector3(25, 0, 25)
    arena.battle.wardens[0].boss.engaged = False
    # One on the stairs a frame: it passes through the other, and under
    # the player.
    arena.battle.members[0].climb = Climb(0, False)
    arena.run(0.05)
    arena.run(12)
    for k in range(2):
        assert_true(arena.battle.members[k].character.position.z < -5)


def test_under_a_roof_a_raider_takes_no_way() raises:
    var arena = Arena(arena_parameters(0, 0, 6, raid=True, raiders=1))
    arena.terrain = _walled(True)
    arena.battle.set_grid(route_grid(arena.terrain, 0.5, 30))
    arena.player.position = Vector3(0, 0, -12)
    ref member = arena.battle.members[0]
    member.joined = True
    member.post = Vector3(0, 0, -12)
    member.character.position = Vector3(0, 0, 2)
    arena.battle.wardens[0].character.position = Vector3(25, 0, 25)
    arena.battle.wardens[0].boss.engaged = False
    arena.run(0.05)
    assert_true(len(arena.battle.members[0].route.way) == 0)


def test_with_no_grid_the_raiders_walk_straight() raises:
    var arena = Arena(arena_parameters(0, 0, 6, raid=True, raiders=1))
    arena.player.position = Vector3(0, 0, -6)
    ref member = arena.battle.members[0]
    member.joined = True
    member.post = Vector3(0, 0, -6)
    member.character.position = Vector3(0, 0, 2)
    arena.battle.wardens[0].character.position = Vector3(25, 0, 25)
    arena.battle.wardens[0].boss.engaged = False
    arena.run(2)
    assert_true(arena.battle.members[0].character.position.z < 0)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
