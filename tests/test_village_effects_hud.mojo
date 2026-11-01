# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""What the combos' effects write over the frame: each effect's flash, the
chain's crooked arc, a mark's reticle and a wound's drop."""

from cameras.perspective_camera import PerspectiveCamera
from extensions.village.battle import CHEST, Flash, Wound
from extensions.village.combos import (
    BLEED,
    CHAIN,
    DRAIN,
    LAUNCH,
    MARK,
    SHOCKWAVE,
    SUNDER,
    ComboEffect,
)
from extensions.village.effects_hud import (
    ARC_STEPS,
    arc_path,
    draw_effects,
    draw_flash,
)
from math.vector3 import Vector3
from render.framebuffer import Color, Framebuffer
from std.testing import (
    TestSuite,
    assert_almost_equal,
    assert_equal,
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


def _look() -> Vector3:
    """Return the way the camera looks."""
    return Vector3(0, -1, -6) / Vector3(0, -1, -6).length()


def _lit(frame: Framebuffer) -> Int:
    """Return how bright a frame is: its color bytes, added."""
    var sum = 0
    for k in range(len(frame.pixels)):
        if k % 4 != 3:
            sum += Int(frame.pixels[k])
    return sum


def _frame() raises -> Framebuffer:
    """Return a black frame of 320 by 180."""
    return Framebuffer(320, 180, Color(0, 0, 0))


def test_a_chains_arc_bends_between_its_ends() raises:
    var start = Vector3(0, 1, -3)
    var end = Vector3(4, 1, -3)
    var path = arc_path(start, end, 2)
    assert_equal(len(path), ARC_STEPS + 1)
    assert_almost_equal((path[0] - start).length(), 0, atol=1e-6)
    assert_almost_equal((path[ARC_STEPS] - end).length(), 0, atol=1e-6)
    var bent = False
    for p in path:
        assert_true(abs(p.y - 1) <= 0.4 + 1.0e-4)
        bent = bent or abs(p.y - 1) > 0.01
    assert_true(bent)


def test_each_effect_has_its_flash() raises:
    var camera = _camera()
    var look = _look()
    var chest = Vector3(0, CHEST, -3)
    var aside = Vector3(2, CHEST, -4)
    var effects: List[ComboEffect] = [
        LAUNCH,
        SUNDER,
        BLEED,
        DRAIN,
        SHOCKWAVE,
        CHAIN,
        MARK,
    ]
    for effect in effects:
        var frame = _frame()
        draw_flash(frame, camera, look, Flash(effect, chest, aside, 0.2), 1)
        assert_true(_lit(frame) > 0)
    # As a flash fades, its light dims.
    var early = _frame()
    draw_flash(early, camera, look, Flash(SUNDER, chest, chest, 0.05), 0)
    var late = _frame()
    draw_flash(late, camera, look, Flash(SUNDER, chest, chest, 0.5), 0)
    assert_true(_lit(late) < _lit(early))
    # Behind the camera, a star shows nothing.
    var behind = _frame()
    var back = Vector3(0, CHEST, 9)
    draw_flash(behind, camera, look, Flash(LAUNCH, back, back, 0.1), 0)
    assert_equal(_lit(behind), 0)


def test_marks_and_wounds_show_over_their_targets() raises:
    var arena = Arena(arena_parameters(1, 1))
    var camera = _camera()
    var look = _look()
    var none = _frame()
    draw_effects(none, arena.battle, camera, look)
    assert_equal(_lit(none), 0)
    # A marked dummy wears its reticle; a wounded one its drop.
    arena.battle.marks[1] = 3
    var marked = _frame()
    draw_effects(marked, arena.battle, camera, look)
    assert_true(_lit(marked) > 0)
    arena.battle.wounds.append(Wound(1, 2, 5, 0, 0.2))
    var wounded = _frame()
    draw_effects(wounded, arena.battle, camera, look)
    assert_true(_lit(wounded) > _lit(marked))
    # A fallen bandit's mark does not show.
    arena.battle.wounds.clear()
    arena.battle.marks[1] = 0
    arena.battle.marks[0] = 3
    arena.battle.foes[0].down = 0
    var fallen = _frame()
    draw_effects(fallen, arena.battle, camera, look)
    assert_equal(_lit(fallen), 0)
    # A flash shows.
    var chest = Vector3(0, CHEST, -3)
    arena.battle.flashes.append(Flash(SHOCKWAVE, chest, chest, 0.1))
    var flash = _frame()
    draw_effects(flash, arena.battle, camera, look)
    assert_true(_lit(flash) > 0)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
