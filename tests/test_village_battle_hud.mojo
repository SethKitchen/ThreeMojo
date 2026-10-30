# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""What a fight writes over the frame: the gauges, the combo, the foes'
bars, the lock's mark and the blows' numbers."""

from cameras.perspective_camera import PerspectiveCamera
from extensions.village.battle import Popup
from extensions.village.battle_hud import (
    draw_bar,
    draw_battle,
    on_screen,
    stance_label,
)
from extensions.village.combat import (
    HEAVY,
    LIGHT_ONE,
    HIGH_STANCE,
    LOW_STANCE,
    MID_STANCE,
    STAGGER,
)
from extensions.village.foes import CIRCLING, POSTED
from extensions.village.hud import WHITE_TEXT
from math.vector3 import Vector3
from render.framebuffer import Color, Framebuffer
from std.testing import (
    TestSuite,
    assert_equal,
    assert_false,
    assert_true,
)
from tests._village_arena import Arena, arena_parameters
from units.si import DEGREE, METER, Angle, Length


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


def test_a_stance_and_a_bar_are_drawn() raises:
    assert_equal(stance_label(HIGH_STANCE), "HIGH STANCE")
    assert_equal(stance_label(MID_STANCE), "MID STANCE")
    assert_equal(stance_label(LOW_STANCE), "LOW STANCE")
    var empty = _frame()
    draw_bar(empty, 10, 10, 20, 4, -1, WHITE_TEXT)
    var full = _frame()
    draw_bar(full, 10, 10, 20, 4, 3, WHITE_TEXT)
    assert_true(_changed(full) > _changed(empty))
    # A point before the camera lands on the frame; one behind does not.
    var camera = _camera()
    var look = Vector3(0, -1, -6) / Vector3(0, -1, -6).length()
    assert_true(on_screen(camera, look, Vector3(0, 1, -2), 320, 180))
    assert_false(on_screen(camera, look, Vector3(0, 1, 9), 320, 180))


def test_the_fight_writes_its_gauges_bars_mark_and_numbers() raises:
    var arena = Arena(arena_parameters(1, 1, 5))
    var camera = _camera()
    var look = Vector3(0, -1, -6) / Vector3(0, -1, -6).length()
    # At rest: the gauges alone.
    var rest = _frame()
    draw_battle(rest, arena.battle, arena.scene, camera, look)
    var gauges = _changed(rest)
    assert_true(gauges > 0)
    # A combo, a fighting bandit, a tired dummy, a lock and a number.
    ref b = arena.battle
    b.fighter.combo = 5
    b.fighter.health = 50
    b.foes[0].brain.state = CIRCLING
    b.dummies[0].fighter.ki = 10
    b.lock = 0
    b.popups.append(Popup(Vector3(0, 2, -3), "30", WHITE_TEXT, 0.1))
    b.popups.append(Popup(Vector3(0, 2, 9), "99", WHITE_TEXT, 0.1))
    # And a swing's trail.
    b.trail.shown = LIGHT_ONE.value
    b.trail.sweep = 1
    b.trail.glow = 1
    arena.scene.update()
    var busy = _frame()
    draw_battle(busy, arena.battle, arena.scene, camera, look)
    assert_true(_changed(busy) > gauges)
    # A staggered bandit shows its break, and a heavy wind-up its warning.
    # A posted bandit that is hurt shows its bars.
    arena.battle.foes[0].brain.state = POSTED
    arena.battle.foes[0].fighter.health = 200
    arena.battle.foes[0].fighter.move = STAGGER
    # Over Limit, the limit gauge says so.
    arena.battle.fighter.over = 5
    var broken = _frame()
    draw_battle(broken, arena.battle, arena.scene, camera, look)
    # A broken bandit that a heavy attack would finish says so.
    arena.battle.foes[0].fighter.health = 50
    var finish = _frame()
    draw_battle(finish, arena.battle, arena.scene, camera, look)
    arena.battle.foes[0].fighter.move = HEAVY
    arena.battle.foes[0].fighter.clock = 0.1
    var warned = _frame()
    draw_battle(warned, arena.battle, arena.scene, camera, look)
    arena.battle.foes[0].fighter.clock = 0.6
    var struck = _frame()
    draw_battle(struck, arena.battle, arena.scene, camera, look)
    assert_true(_changed(warned) > _changed(struck))
    # Behind the camera, a bandit, a dummy and the lock's mark are not
    # drawn; nor is a fallen bandit, nor a gauge of no arte points.
    arena.battle.foes[0].character.position = Vector3(0, 0, 9)
    arena.battle.dummies[0].dummy.post.z = 9
    arena.battle.fighter.parameters.arte_points = 0
    var behind = _frame()
    draw_battle(behind, arena.battle, arena.scene, camera, look)
    arena.battle.foes[0].down = 0
    arena.battle.lock = -1
    var fallen = _frame()
    draw_battle(fallen, arena.battle, arena.scene, camera, look)
    assert_true(_changed(fallen) <= _changed(behind))


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
