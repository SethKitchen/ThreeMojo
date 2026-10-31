# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""What the raid, the styles and the combos write over the frame: the
zones, the mark, the warden's bars, the party, the style, the routes, the
book and the missiles."""

from cameras.perspective_camera import PerspectiveCamera
from extensions.village.boss import (
    CIRCLE,
    CONE,
    ENRAGE_SECONDS,
    FURY,
    LAST_STAND,
    LINE,
    OPENING,
    SLAM,
    SUMMON,
    BossPhase,
    Zone,
)
from extensions.village.combat import Blow
from extensions.village.combos import LIGHT_KEY
from extensions.village.missiles import ARROW, ORB, SPARK, Missile
from extensions.village.raid_hud import draw_raid, draw_zone, zone_corners
from extensions.village.styles import AXE, MAGIC, SWORD
from math.vector3 import Vector3
from render.framebuffer import Color, Framebuffer
from std.testing import (
    TestSuite,
    assert_almost_equal,
    assert_equal,
    assert_true,
)
from tests._village_arena import Arena, arena_parameters
from units.si import DEGREE, METER, METER_PER_SECOND, Angle, Length, Velocity


def _camera() raises -> PerspectiveCamera:
    """Return a camera behind the player, looking along -z."""
    var camera = PerspectiveCamera(
        Angle(55.0, DEGREE),
        16.0 / 9.0,
        Length(0.1, METER),
        Length(100.0, METER),
    )
    camera.place(Vector3(0, 2, 4), Vector3(0, 1, -2))
    return camera^


def _look() -> Vector3:
    """Return the way the camera looks."""
    return Vector3(0, -1, -6) / Vector3(0, -1, -6).length()


def _changed(frame: Framebuffer) -> Int:
    """Return how bright a frame is: its color bytes, added."""
    var sum = 0
    for k in range(len(frame.pixels)):
        if k % 4 != 3:
            sum += Int(frame.pixels[k])
    return sum


def _frame() raises -> Framebuffer:
    """Return a black frame of 320 by 180."""
    return Framebuffer(320, 180, Color(0, 0, 0))


def _blow() -> Blow:
    """Return a blow of 10 damage."""
    return Blow(
        10, 2, Velocity(0.0, METER_PER_SECOND), Velocity(0.0, METER_PER_SECOND)
    )


def test_each_zone_has_its_corners() raises:
    var circle = Zone(CIRCLE, Vector3(0, 0, 0), Vector3(0, 0, 1), 4, 0)
    var ring = zone_corners(circle, 0.5, 1)
    assert_almost_equal((ring[1] - Vector3(0, 0, 0)).length(), 4, atol=1e-4)
    assert_almost_equal((ring[0] - Vector3(0, 0, 0)).length(), 2, atol=1e-4)
    var cone = Zone(CONE, Vector3(0, 0, 0), Vector3(0, 0, 1), 6, 90)
    var fan = zone_corners(cone, 0, 1)
    assert_almost_equal(fan[1].length(), 6, atol=1e-4)
    assert_true(fan[1].x < 0 or fan[1].x > 0)
    var line = Zone(LINE, Vector3(0, 0, 0), Vector3(0, 0, 1), 10, 2)
    var band = zone_corners(line, 0, 1)
    assert_equal(len(band), 26)
    assert_almost_equal(abs(band[0].x), 1, atol=1e-5)
    assert_almost_equal(band[25].z, 10, atol=1e-4)


def test_a_zone_is_laid_in_red_light() raises:
    var camera = _camera()
    var frame = _frame()
    var circle = Zone(CIRCLE, Vector3(0, 0, -3), Vector3(0, 0, 1), 2, 0)
    draw_zone(frame, camera, _look(), circle, 0)
    var edge = _changed(frame)
    assert_true(edge > 0)
    var full = _frame()
    draw_zone(full, camera, _look(), circle, 0.9)
    assert_true(_changed(full) > edge)


def test_the_raid_writes_its_bars_party_mark_and_zones() raises:
    var arena = Arena(arena_parameters(0, 0, 6, raid=True, raiders=2))
    var camera = _camera()
    var look = _look()
    # Out of the fight, nothing of the raid shows but the style.
    var calm = _frame()
    draw_raid(calm, arena.battle, camera, look, 1)
    var style = _changed(calm)
    assert_true(style > 0)
    ref warden = arena.battle.wardens[0]
    warden.character.position = Vector3(0, 0, -4)
    ref boss = warden.boss
    boss.engaged = True
    boss.attack = SLAM
    boss.clock = 0.5
    boss.zone = Zone(CIRCLE, Vector3(0, 0, -3), Vector3(0, 0, 1), 2, 0)
    for k in range(2):
        arena.battle.members[k].joined = True
    arena.battle.members[1].down = 1
    arena.battle.members[1].revive = 1
    arena.battle.members[0].fighter.health = 10
    var fight = _frame()
    draw_raid(fight, arena.battle, camera, look, 1)
    assert_true(_changed(fight) > style)
    # Each phase, a stagger and the enrage say so; a summon lays no zone.
    var phases: List[BossPhase] = [OPENING, FURY, LAST_STAND]
    for phase in phases:
        boss.phase = phase
        var frame = _frame()
        draw_raid(frame, arena.battle, camera, look, 1)
        assert_true(_changed(frame) > 0)
    boss.staggered = 2
    boss.fight_time = ENRAGE_SECONDS + 1
    boss.attack = SUMMON
    boss.clock = 0.1
    boss.zone.size = 0
    var raged = _frame()
    draw_raid(raged, arena.battle, camera, look, 1)
    assert_true(_changed(raged) > 0)
    # A fallen raider not yet revived, and a raider who left.
    arena.battle.members[1].revive = 0
    arena.battle.members[0].joined = False
    var left = _frame()
    draw_raid(left, arena.battle, camera, look, 1)
    assert_true(_changed(left) > 0)
    # A fallen warden shows no bars.
    boss.health = 0
    var gone = _frame()
    draw_raid(gone, arena.battle, camera, look, 1)
    assert_true(_changed(gone) < _changed(left))


def test_a_rockfalls_mark_rings_the_marked() raises:
    var arena = Arena(arena_parameters(0, 0, 6, raid=True, raiders=1))
    var camera = _camera()
    var look = _look()
    var none = _frame()
    draw_raid(none, arena.battle, camera, look, 1)
    ref boss = arena.battle.wardens[0].boss
    boss.marked = 0
    boss.mark_clock = 2.5
    arena.battle.feet = Vector3(0, 0, -3)
    var player = _frame()
    draw_raid(player, arena.battle, camera, look, 1)
    assert_true(_changed(player) > _changed(none))
    # On a raider before the camera, and one behind it.
    boss.marked = 1
    arena.battle.members[0].character.position = Vector3(1, 0, -4)
    var raider = _frame()
    draw_raid(raider, arena.battle, camera, look, 1)
    assert_true(_changed(raider) > _changed(none))
    arena.battle.members[0].character.position = Vector3(0, 0, 20)
    var behind = _frame()
    draw_raid(behind, arena.battle, camera, look, 1)
    assert_true(_changed(behind) >= _changed(none))


def test_the_style_routes_beat_and_book_show() raises:
    var arena = Arena(arena_parameters(0, 0))
    var camera = _camera()
    var look = _look()
    ref battle = arena.battle
    var plain = _frame()
    draw_raid(plain, battle, camera, look, 1)
    # The specialty's book, before its master combo is learned.
    battle.reading = True
    var early = _frame()
    draw_raid(early, battle, camera, look, 1)
    assert_true(_changed(early) > _changed(plain))
    battle.reading = False
    # The routes of a string, and a press on the beat.
    battle.levels[SWORD.value] = 10
    _ = battle.book.teach(SWORD, 10)
    battle.tracker.press(LIGHT_KEY, False)
    battle.tracker.press(LIGHT_KEY, True)
    battle.beat = 0.1
    var routes = _frame()
    draw_raid(routes, battle, camera, look, 1)
    assert_true(_changed(routes) > _changed(plain))
    # Past its flash, the beat does not show.
    battle.beat = 5
    var later = _frame()
    draw_raid(later, battle, camera, look, 1)
    assert_true(_changed(later) < _changed(routes))
    # The book: learned, not yet learned, and only the specialty's.
    battle.reading = True
    var book = _frame()
    draw_raid(book, battle, camera, look, 1)
    assert_true(_changed(book) > _changed(later))
    _ = battle.fighter.set_style(AXE)
    _ = battle.book.teach(AXE, 2)
    var axe = _frame()
    draw_raid(axe, battle, camera, look, 1)
    assert_true(_changed(axe) > 0)
    # Magic shows its mana.
    battle.reading = False
    _ = battle.fighter.set_style(MAGIC)
    var magic = _frame()
    draw_raid(magic, battle, camera, look, 1)
    assert_true(_changed(magic) > 0)


def test_each_missile_shows_as_a_star() raises:
    var arena = Arena(arena_parameters(0, 0))
    var camera = _camera()
    var look = _look()
    var none = _frame()
    draw_raid(none, arena.battle, camera, look, 1)
    ref shots = arena.battle.shots
    var arrow = Missile(
        ARROW, Vector3(0, 1, -3), Vector3(0, 0, -40), -1, -1, _blow()
    )
    arrow.last = Vector3(0, 1, -2)
    shots.append(arrow^)
    shots.append(
        Missile(SPARK, Vector3(1, 1, -3), Vector3(0, 0, -1), -1, -1, _blow())
    )
    shots.append(
        Missile(ORB, Vector3(-1, 1, -3), Vector3(0, 0, -1), -1, -1, _blow())
    )
    shots.append(
        Missile(ARROW, Vector3(0, 1, 9), Vector3(0, 0, 1), -1, -1, _blow())
    )
    var lit = _frame()
    draw_raid(lit, arena.battle, camera, look, 1)
    assert_true(_changed(lit) > _changed(none))


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
