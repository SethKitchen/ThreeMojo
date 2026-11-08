# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""What a fight writes over the frame: the gauges, the combo, the foes'
bars, the lock's mark and the blows' numbers."""

from cameras.perspective_camera import PerspectiveCamera
from extensions.village.slashes import Impact
from extensions.village.battle import (
    CHEST,
    HEAD,
    POPUP_SECONDS,
    Bolt,
    Knife,
    Popup,
    Wave,
)
from extensions.village.styles import MAGIC, SWORD
from extensions.village.battle_hud import (
    popup_style,
    pop_grow,
    POP_EASE,
    POP_GROW,
    HURT_TINT,
    TOP_BAND,
    POP_SECONDS,
    POPUP_FADE,
    draw_bar,
    draw_battle,
    fill_triangle,
    popup_alpha,
    popup_scale,
    on_screen,
    stance_label,
    stack_boxes,
    tint_edges,
)
from extensions.village.combat import (
    PIERCE,
    Blow,
    HEAVY,
    LIGHT_ONE,
    HIGH_STANCE,
    LOW_STANCE,
    MID_STANCE,
    FREE,
    ULTIMATE,
    PLUNGE,
    STAGGER,
)
from extensions.village.foes import CIRCLING, POSTED
from extensions.village.hud import (
    Rgb,
    GOLD_TEXT,
    WHITE_TEXT,
    draw_outlined,
    draw_text,
)
from math.vector3 import Vector3
from render.framebuffer import Color, Framebuffer
from std.testing import (
    TestSuite,
    assert_almost_equal,
    assert_equal,
    assert_false,
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


def _changed(frame: Framebuffer) -> Int:
    """Return how bright a frame is: its color bytes, added."""
    var sum = 0
    for k in range(len(frame.pixels)):
        if k % 4 != 3:
            sum += Int(frame.pixels[k])
    return sum


comptime WOUNDED_TEST = Rgb(225, 70, 50)


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


def test_a_bar_shows_what_a_blow_took() raises:
    # Half full, three quarters a moment ago: the quarter between is pale.
    var plain = _frame()
    draw_bar(plain, 10, 10, 40, 4, 0.5, WOUNDED_TEST)
    var chipped = _frame()
    draw_bar(chipped, 10, 10, 40, 4, 0.5, WOUNDED_TEST, 0.75)
    assert_true(_changed(chipped) > _changed(plain))
    var at = (11 * 320 + 10 + 25) * 4
    assert_true(Int(chipped.pixels[at + 2]) > 150)
    assert_true(Int(plain.pixels[at + 2]) < 20)
    # A chip under the share shows nothing more.
    var under = _frame()
    draw_bar(under, 10, 10, 40, 4, 0.5, WOUNDED_TEST, 0.25)
    assert_equal(_changed(under), _changed(plain))


def test_a_number_pops_and_outlines() raises:
    # A word keeps the display's size; a number is half again as large; a
    # critical number twice as large; each number a dot more as it pops.
    assert_equal(popup_scale("PARRY", WHITE_TEXT, 0.5, 4), 4)
    assert_equal(popup_scale("", WHITE_TEXT, 0.5, 4), 4)
    assert_equal(popup_scale("37", WHITE_TEXT, 0.5, 4), 6)
    assert_equal(popup_scale("+12", WHITE_TEXT, 0.5, 2), 3)
    assert_equal(popup_scale("37", GOLD_TEXT, 0.5, 4), 8)
    assert_equal(popup_scale("37", WHITE_TEXT, POP_SECONDS / 2, 4), 8)
    assert_equal(popup_scale("37", WHITE_TEXT, 0, 1), 3)
    # Full until its fade, then less, and gone at its end.
    assert_equal(popup_alpha(0), 1)
    assert_true(popup_alpha(POPUP_SECONDS - POPUP_FADE / 2) < 1)
    assert_equal(popup_alpha(POPUP_SECONDS), 0)
    # An outline darkens more of a light frame than a shadow does.
    var shadowed = Framebuffer(64, 32, Color(200, 200, 200))
    draw_text(shadowed, 4, 4, "8", 2, WHITE_TEXT, 1)
    var outlined = Framebuffer(64, 32, Color(200, 200, 200))
    draw_outlined(outlined, 4, 4, "8~", 2, WHITE_TEXT, 1)
    assert_true(_changed(outlined) < _changed(shadowed))
    # No text draws nothing.
    var blank = Framebuffer(64, 32, Color(200, 200, 200))
    var before = _changed(blank)
    draw_outlined(blank, 4, 4, "", 2, WHITE_TEXT, 1)
    assert_equal(_changed(blank), before)


def test_a_triangle_fills_the_pixels_inside_it_either_way_round() raises:
    var one = _frame()
    fill_triangle(one, 10, 10, 30, 10, 10, 30, GOLD_TEXT, 1)
    var other = _frame()
    fill_triangle(other, 10, 10, 10, 30, 30, 10, GOLD_TEXT, 1)
    assert_true(_changed(one) > 0)
    assert_equal(_changed(one), _changed(other))
    # A pixel inside is gold, and one past the long edge is not.
    var inside = (12 * 320 + 12) * 4
    assert_equal(Int(one.pixels[inside]), Int(GOLD_TEXT.r))
    var past = (28 * 320 + 28) * 4
    assert_equal(Int(one.pixels[past]), 0)
    # A flat triangle fills nothing; one past the edge is clipped.
    var flat = _frame()
    fill_triangle(flat, 10, 10, 20, 20, 30, 30, GOLD_TEXT, 1)
    assert_equal(_changed(flat), 0)
    var edge = _frame()
    fill_triangle(edge, -20, -20, 400, 10, 10, 400, GOLD_TEXT, 1)
    assert_true(_changed(edge) > 0)
    # One wholly off the frame, above it or to its left, fills nothing.
    var off = _frame()
    fill_triangle(off, 10, -40, 30, -40, 10, -20, GOLD_TEXT, 1)
    fill_triangle(off, -40, 10, -40, 30, -20, 10, GOLD_TEXT, 1)
    assert_equal(_changed(off), 0)


def test_numbers_that_would_cover_each_other_stand_one_over_another() raises:
    # The newest, the last, keeps its place; the older moves over it.
    var tops = stack_boxes([100, 110], [50, 52], [40, 40], [20, 20])
    assert_equal(tops[1], 52)
    assert_equal(tops[0], 32)
    # Side by side, or apart in height, they do not move.
    var apart = stack_boxes([100, 150], [50, 52], [40, 40], [20, 20])
    assert_equal(apart[0], 50)
    var left = stack_boxes([150, 100], [50, 52], [40, 40], [20, 20])
    assert_equal(left[0], 50)
    var over = stack_boxes([100, 100], [10, 50], [40, 40], [20, 20])
    assert_equal(over[0], 10)
    var under = stack_boxes([100, 100], [90, 50], [40, 40], [20, 20])
    assert_equal(under[0], 90)
    # The oldest of three goes over the middle one, which went over the
    # newest.
    var three = stack_boxes(
        [100, 100, 100], [50, 50, 50], [40, 40, 40], [20, 20, 20]
    )
    assert_equal(three[2], 50)
    assert_equal(three[1], 30)
    assert_equal(three[0], 10)
    # A move over the newest can cross the middle one: it moves again.
    var again = stack_boxes(
        [100, 100, 100], [50, 25, 60], [40, 40, 40], [20, 20, 20]
    )
    assert_equal(again[1], 25)
    assert_equal(again[0], 5)
    assert_equal(len(stack_boxes([], [], [], [])), 0)


def test_a_nearer_foes_bar_keeps_its_place_over_a_crowd() raises:
    var arena = Arena(arena_parameters(3, 0, 5))
    var camera = _camera()
    var look = Vector3(0, -1, -6) / Vector3(0, -1, -6).length()
    ref foes = arena.battle.foes
    # The nearest, the farthest, and one between, nearly in a line.
    foes[0].character.position = Vector3(0, 0, -2)
    foes[1].character.position = Vector3(0.2, 0, -6)
    foes[2].character.position = Vector3(-0.1, 0, -4)
    for k in range(3):
        foes[k].brain.state = CIRCLING
    var crowd = _frame()
    draw_battle(crowd, arena.battle, arena.scene, camera, look)
    foes[1].down = 0
    foes[2].down = 0
    var alone = _frame()
    draw_battle(alone, arena.battle, arena.scene, camera, look)
    # Each pixel that the nearest bar drew is the same in the crowd: no
    # other bar covers it.
    var drawn = 0
    for k in range(len(alone.pixels)):
        if alone.pixels[k] != 0 and k % 4 != 3:
            drawn += 1
            assert_equal(crowd.pixels[k], alone.pixels[k])
    assert_true(drawn > 0)
    assert_true(_changed(crowd) > _changed(alone))


def test_a_quick_combo_writes_a_short_column_of_numbers() raises:
    var arena = Arena(arena_parameters(0, 0, 5))
    var camera = _camera()
    camera.place(Vector3(0, 5, 4), Vector3(0, 1, -2))
    var look = Vector3(0, -1, -6) / Vector3(0, -1, -6).length()
    var at = Vector3(0, 1, -1)
    var rows = List[Int]()
    for many in [1, 4, 9]:
        arena.battle.popups.clear()
        for _ in range(many):
            arena.battle.popups.append(Popup(at, "88", WHITE_TEXT, 0.5))
        var bare = _frame()
        arena.battle.popups.clear()
        draw_battle(bare, arena.battle, arena.scene, camera, look)
        for _ in range(many):
            arena.battle.popups.append(Popup(at, "88", WHITE_TEXT, 0.5))
        var shown = _frame()
        draw_battle(shown, arena.battle, arena.scene, camera, look)
        var top = 180
        var bottom = 0
        for k in range(len(shown.pixels)):
            if shown.pixels[k] != bare.pixels[k]:
                top = min(top, k // 4 // 320)
                bottom = max(bottom, k // 4 // 320)
        rows.append(bottom - top)
    # Four numbers stand one over another; nine stand no taller than four.
    assert_true(rows[1] > 3 * rows[0])
    assert_equal(rows[2], rows[1])


def test_a_number_over_a_foe_stands_over_its_bar() raises:
    var arena = Arena(arena_parameters(1, 0, 5))
    # A camera high over the foe, so its head stands well under the band.
    var camera = _camera()
    camera.place(Vector3(0, 5, 4), Vector3(0, 1, -2))
    var look = Vector3(0, -1, -6) / Vector3(0, -1, -6).length()
    ref foe = arena.battle.foes[0]
    foe.character.position = Vector3(0, 0, -1)
    foe.brain.state = CIRCLING
    var bar = _frame()
    draw_battle(bar, arena.battle, arena.scene, camera, look)
    # A number where the bar stands, over the foe's head.
    arena.battle.popups.append(
        Popup(Vector3(0, HEAD + 0.2, -1), "88", WHITE_TEXT, 0.5)
    )
    var both = _frame()
    draw_battle(both, arena.battle, arena.scene, camera, look)
    var drawn = 0
    for k in range(len(bar.pixels)):
        if bar.pixels[k] != 0 and k % 4 != 3:
            drawn += 1
            assert_equal(both.pixels[k], bar.pixels[k])
    assert_true(drawn > 0)
    assert_true(_changed(both) > _changed(bar))


def test_the_fight_writes_its_gauges_bars_mark_and_numbers() raises:
    var arena = Arena(arena_parameters(1, 1, 5))
    var camera = _camera()
    var look = Vector3(0, -1, -6) / Vector3(0, -1, -6).length()
    # At rest: the gauges alone.
    var rest = _frame()
    draw_battle(rest, arena.battle, arena.scene, camera, look)
    var gauges = _changed(rest)
    assert_true(gauges > 0)
    # Magic's gauges show its mana too.
    _ = arena.battle.fighter.set_style(MAGIC)
    var magic = _frame()
    draw_battle(magic, arena.battle, arena.scene, camera, look)
    assert_true(_changed(magic) > gauges)
    _ = arena.battle.fighter.set_style(SWORD)
    # A number over a head high in the frame stands under the top band.
    var high = Vector3(0, 6, -6)
    assert_true(on_screen(camera, look, high, 320, 180).value().y < TOP_BAND)
    arena.battle.popups.append(Popup(high, "77", WHITE_TEXT, 0.1))
    var lowered = _frame()
    draw_battle(lowered, arena.battle, arena.scene, camera, look)
    arena.battle.popups.clear()
    var moved = 0
    for k in range(len(rest.pixels)):
        if rest.pixels[k] != lowered.pixels[k]:
            moved += 1
            assert_true(k // 4 // 320 >= TOP_BAND)
    assert_true(moved > 0)
    # A combo, a fighting bandit, a tired dummy, a lock and a number.
    ref b = arena.battle
    b.fighter.combo = 5
    b.fighter.health = 50
    b.foes[0].brain.state = CIRCLING
    b.dummies[0].fighter.stamina = 10
    b.lock = 0
    b.popups.append(Popup(Vector3(0, 2, -3), "30", WHITE_TEXT, 0.1))
    # And a ground wave's wave.
    b.waves.append(
        Wave(
            Vector3(0, 0, -3),
            Vector3(0, 0, -1),
            2,
            Blow(
                45,
                10,
                Velocity(2.0, METER_PER_SECOND),
                Velocity(0.0, METER_PER_SECOND),
            ),
            List[Int](),
        )
    )
    b.popups.append(Popup(Vector3(0, 2, 9), "99", WHITE_TEXT, 0.1))
    b.popups.append(Popup(Vector3(1, 2, -3), "PARRY", WHITE_TEXT, 0.1))
    # A critical blow's gold number, with its halo.
    b.popups.append(Popup(Vector3(-1, 2, -3), "88", GOLD_TEXT, 0.1))
    # A gold word has no halo: only a number glows.
    b.popups.append(Popup(Vector3(-1, 1, -3), "CRITICAL", GOLD_TEXT, 0.1))
    # And a blow's flash.
    b.impacts.append(Impact(Vector3(0, 1.2, -3), Vector3(255, 235, 190), 1, 0))
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
    # In a surge, the limit gauge says so.
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
    # A piercing attack's wind-up glows red at the chest, and the glow grows.
    arena.battle.foes[0].fighter.move = PIERCE
    arena.battle.foes[0].fighter.clock = 0.1
    var glowing = _frame()
    draw_battle(glowing, arena.battle, arena.scene, camera, look)
    arena.battle.foes[0].fighter.clock = 0.6
    var grown = _frame()
    draw_battle(grown, arena.battle, arena.scene, camera, look)
    assert_true(_changed(glowing) > _changed(struck))
    assert_true(_changed(grown) > _changed(glowing))
    # A raging bandit says so under its bars.
    arena.battle.foes[0].fighter.parameters.rage = 0.5
    var raging = _frame()
    draw_battle(raging, arena.battle, arena.scene, camera, look)
    assert_true(_changed(raging) > _changed(grown))
    arena.battle.foes[0].fighter.parameters.rage = 0
    # A camera at the chest, looking up at the bars, draws no glow.
    var chest = arena.battle.foes[0].character.position + Vector3(0, CHEST, 0)
    var under = _camera()
    under.place(chest, chest + Vector3(0, 1, -0.2))
    var up = Vector3(0, 1, -0.2) / Vector3(0, 1, -0.2).length()
    var close = _frame()
    draw_battle(close, arena.battle, arena.scene, under, up)
    arena.battle.foes[0].fighter.move = HEAVY
    var plain = _frame()
    draw_battle(plain, arena.battle, arena.scene, under, up)
    assert_equal(_changed(close), _changed(plain))
    assert_true(on_screen(under, up, chest + Vector3(0, 0.9, 0), 320, 180))
    # Behind the camera, a bandit, a dummy and the lock's mark are not
    # drawn; nor is a fallen bandit, nor a gauge of no special points.
    arena.battle.foes[0].character.position = Vector3(0, 0, 9)
    arena.battle.dummies[0].dummy.post.z = 9
    arena.battle.fighter.parameters.special_points = 0
    var behind = _frame()
    draw_battle(behind, arena.battle, arena.scene, camera, look)
    arena.battle.foes[0].down = 0
    arena.battle.lock = -1
    var fallen = _frame()
    draw_battle(fallen, arena.battle, arena.scene, camera, look)
    assert_true(_changed(fallen) <= _changed(behind))
    # An ultimate's start-up writes its name large, and a gold star grows
    # at the sword hand. After the start-up, neither shows.
    arena.battle.fighter.move = ULTIMATE
    # Just begun, the name stands larger, and eases to its size.
    arena.battle.fighter.clock = 0
    arena.scene.update()
    var landing = _frame()
    draw_battle(landing, arena.battle, arena.scene, camera, look)
    arena.battle.fighter.clock = 0.3
    arena.scene.update()
    var rising = _frame()
    draw_battle(rising, arena.battle, arena.scene, camera, look)
    # The name's rows: a quarter down the frame.
    var title_landing = 0
    var title_rising = 0
    for k in range(20 * 320 * 4, 70 * 320 * 4):
        if k % 4 != 3:
            title_landing += Int(landing.pixels[k])
            title_rising += Int(rising.pixels[k])
    assert_true(title_landing > title_rising)
    arena.battle.fighter.clock = 0.7
    var spun = _frame()
    draw_battle(spun, arena.battle, arena.scene, camera, look)
    assert_true(_changed(rising) > _changed(spun))
    # A camera past the player, looking away, shows the name alone.
    var away = _camera()
    away.place(Vector3(0, 1.5, -3), Vector3(0, 1.5, -9))
    var ahead = Vector3(0, 0, -1)
    var after = _frame()
    draw_battle(after, arena.battle, arena.scene, away, ahead)
    arena.battle.fighter.clock = 0.3
    var named = _frame()
    draw_battle(named, arena.battle, arena.scene, away, ahead)
    assert_true(_changed(named) > _changed(after))
    # A plunge rings the ground as it strikes, and not before or after.
    arena.battle.fighter.move = PLUNGE
    arena.battle.fighter.clock = 0.1
    var early = _frame()
    draw_battle(early, arena.battle, arena.scene, camera, look)
    arena.battle.fighter.clock = 0.2
    var ringing = _frame()
    draw_battle(ringing, arena.battle, arena.scene, camera, look)
    arena.battle.fighter.clock = 0.5
    var late = _frame()
    draw_battle(late, arena.battle, arena.scene, camera, look)
    assert_true(_changed(ringing) > _changed(early))
    assert_equal(_changed(late), _changed(early))


def test_the_companion_shows_her_bolts_and_her_gauge() raises:
    var arena = Arena(arena_parameters(0, 0, ally=True))
    var camera = _camera()
    var look = Vector3(0, -1, -6) / Vector3(0, -1, -6).length()
    arena.scene.update()
    var plain = _frame()
    draw_battle(plain, arena.battle, arena.scene, camera, look)
    # A bolt before the camera shows as a star, and a assist attack's too.
    var blow = Blow(
        28,
        10,
        Velocity(1.5, METER_PER_SECOND),
        Velocity(0.0, METER_PER_SECOND),
    )
    var at = Vector3(0, 1, -3)
    arena.battle.bolts.append(Bolt(at, at, 0, blow, False, 0))
    var lit = _frame()
    draw_battle(lit, arena.battle, arena.scene, camera, look)
    assert_true(_changed(lit) > _changed(plain))
    arena.battle.bolts[0].assisted = True
    var gold = _frame()
    draw_battle(gold, arena.battle, arena.scene, camera, look)
    assert_true(_changed(gold) > _changed(plain))
    # A knife is a star too.
    arena.battle.bolts[0].at = Vector3(0, 1, 9)
    arena.battle.knives.append(Knife(at, Vector3(0, 0, 1), at, 0, blow, 0))
    var knife = _frame()
    draw_battle(knife, arena.battle, arena.scene, camera, look)
    assert_true(_changed(knife) > _changed(plain))
    arena.battle.knives.clear()
    # One behind the camera does not.
    var behind = _frame()
    draw_battle(behind, arena.battle, arena.scene, camera, look)
    assert_equal(_changed(behind), _changed(plain))
    # A full assist gauge says so.
    arena.battle.allies[0].mind.charge(1000)
    var ready = _frame()
    draw_battle(ready, arena.battle, arena.scene, camera, look)
    assert_true(_changed(ready) > _changed(plain))


def test_the_edges_tint_and_a_ki_pulse_rings() raises:
    var arena = Arena(arena_parameters(0, 0))
    var camera = _camera()
    var look = Vector3(0, -1, -6) / Vector3(0, -1, -6).length()
    arena.scene.update()
    var plain = _frame()
    draw_battle(plain, arena.battle, arena.scene, camera, look)
    # A perfect dodge's slow tints the corners blue.
    arena.battle.slow = 0.5
    var slowed = _frame()
    draw_battle(slowed, arena.battle, arena.scene, camera, look)
    assert_true(Int(slowed.pixels[2]) > Int(slowed.pixels[0]) + 20)
    # An ultimate tints them gold.
    arena.battle.fighter.move = ULTIMATE
    arena.battle.fighter.clock = 0.7
    var ultimate = _frame()
    draw_battle(ultimate, arena.battle, arena.scene, camera, look)
    assert_true(Int(ultimate.pixels[0]) > Int(ultimate.pixels[2]) + 20)
    arena.battle.fighter.move = FREE
    arena.battle.slow = 0
    # Low health tints them red; a fallen player's do not.
    arena.battle.fighter.health = 50
    var hurt = _frame()
    draw_battle(hurt, arena.battle, arena.scene, camera, look)
    assert_true(Int(hurt.pixels[0]) > Int(hurt.pixels[1]) + 20)
    arena.battle.fighter.health = 0
    var fallen = _frame()
    draw_battle(fallen, arena.battle, arena.scene, camera, look)
    assert_equal(Int(fallen.pixels[0]), 0)
    arena.battle.fighter.health = 500
    # A stamina recovery rings the player's feet, and the ring fades.
    arena.battle.pulsed = 0.1
    var pulse = _frame()
    draw_battle(pulse, arena.battle, arena.scene, camera, look)
    assert_true(_changed(pulse) > _changed(plain))
    arena.battle.pulsed = 0.5
    var gone = _frame()
    draw_battle(gone, arena.battle, arena.scene, camera, look)
    assert_equal(_changed(gone), _changed(plain))
    # No strength tints nothing; the middle of the frame is never tinted.
    var none = _frame()
    tint_edges(none, HURT_TINT, 0)
    assert_equal(_changed(none), 0)
    var full = _frame()
    tint_edges(full, HURT_TINT, 1)
    assert_equal(Int(full.pixels[(90 * 320 + 160) * 4]), 0)
    assert_true(Int(full.pixels[0]) > 150)


def _point_at(
    camera: PerspectiveCamera, look: Vector3, x: Int, y: Int
) raises -> Vector3:
    """Return a point 4 meters before the camera that lands within a few
    pixels of a pixel of a frame of 320 by 180."""
    var best = Vector3(0, 0, 0)
    var least = Float32(1.0e30)
    for i in range(-40, 41):
        for j in range(-20, 21):
            var p = Vector3(Float32(i) * 0.1, 1 + Float32(j) * 0.1, -2)
            var at = on_screen(camera, look, p, 320, 180)
            if at:
                var dx = at.value().x - Float32(x)
                var dy = at.value().y - Float32(y)
                if dx * dx + dy * dy < least:
                    least = dx * dx + dy * dy
                    best = p
    return best


def test_a_number_over_the_party_panel_is_not_drawn() raises:
    var arena = Arena(arena_parameters(0, 0, 6, raid=True, raiders=2))
    var camera = _camera()
    var look = Vector3(0, -1, -6) / Vector3(0, -1, -6).length()
    for k in range(2):
        arena.battle.members[k].joined = True
    var plain = _frame()
    draw_battle(plain, arena.battle, arena.scene, camera, look)
    # A number on the panel, over a raider's row, is hidden by it.
    arena.battle.popups.append(
        Popup(_point_at(camera, look, 30, 80), "55", WHITE_TEXT, 0.5)
    )
    var over = _frame()
    draw_battle(over, arena.battle, arena.scene, camera, look)
    assert_equal(_changed(over), _changed(plain))
    # A number under the panel, in its columns, is drawn.
    arena.battle.popups.clear()
    arena.battle.popups.append(
        Popup(_point_at(camera, look, 30, 160), "55", WHITE_TEXT, 0.5)
    )
    var below = _frame()
    draw_battle(below, arena.battle, arena.scene, camera, look)
    assert_true(_changed(below) != _changed(plain))


def test_a_thrower_is_named_over_its_bars() raises:
    var arena = Arena(arena_parameters(1, 0, 5))
    var camera = _camera()
    var look = Vector3(0, -1, -6) / Vector3(0, -1, -6).length()
    ref foe = arena.battle.foes[0]
    foe.brain.state = CIRCLING
    var plain = _frame()
    draw_battle(plain, arena.battle, arena.scene, camera, look)
    # A thrower's name stands over its bars: the frame is brighter.
    foe.brain.throws = True
    var named = _frame()
    draw_battle(named, arena.battle, arena.scene, camera, look)
    assert_true(_changed(named) > _changed(plain))
    # Staggered, or winding up a heavy attack, it is not named: the word
    # or the warning stands there.
    foe.fighter.move = STAGGER
    var broken = _frame()
    draw_battle(broken, arena.battle, arena.scene, camera, look)
    foe.brain.throws = False
    var plain_broken = _frame()
    draw_battle(plain_broken, arena.battle, arena.scene, camera, look)
    assert_equal(_changed(broken), _changed(plain_broken))
    foe.fighter.move = HEAVY
    foe.fighter.clock = 0.6
    foe.brain.throws = True
    var heavy = _frame()
    draw_battle(heavy, arena.battle, arena.scene, camera, look)
    foe.brain.throws = False
    var plain_heavy = _frame()
    draw_battle(plain_heavy, arena.battle, arena.scene, camera, look)
    assert_equal(_changed(heavy), _changed(plain_heavy))
    # A wolf is not named.
    foe.fighter.move = FREE
    foe.beast = True
    var wolf = _frame()
    draw_battle(wolf, arena.battle, arena.scene, camera, look)
    foe.beast = False
    assert_true(_changed(wolf) <= _changed(named))


def test_the_lock_turns_red_on_a_heavy_wind_up() raises:
    var arena = Arena(arena_parameters(1, 1, 5))
    var camera = _camera()
    var look = Vector3(0, -1, -6) / Vector3(0, -1, -6).length()
    arena.battle.lock = 0
    var calm = _frame()
    draw_battle(calm, arena.battle, arena.scene, camera, look)
    arena.battle.foes[0].fighter.move = HEAVY
    arena.battle.foes[0].fighter.clock = 0.9
    var warned = _frame()
    draw_battle(warned, arena.battle, arena.scene, camera, look)
    # Red, not gold: less green in the frame.
    var green_calm = 0
    var green_warned = 0
    for k in range(1, len(calm.pixels), 4):
        green_calm += Int(calm.pixels[k])
        green_warned += Int(warned.pixels[k])
    assert_true(green_warned < green_calm)
    # Locked on a dummy, past the foes, the ring stays gold.
    arena.battle.lock = 1
    var dummy = _frame()
    draw_battle(dummy, arena.battle, arena.scene, camera, look)
    assert_true(_changed(dummy) > 0)


def test_the_health_number_reddens_as_a_blow_drains() raises:
    var arena = Arena(arena_parameters(0, 0, 5))
    var camera = _camera()
    var look = Vector3(0, -1, -6) / Vector3(0, -1, -6).length()
    ref f = arena.battle.fighter
    f.health = 300
    f.chip = 300
    var steady = _frame()
    draw_battle(steady, arena.battle, arena.scene, camera, look)
    f.chip = 400
    var drained = _frame()
    draw_battle(drained, arena.battle, arena.scene, camera, look)
    # Red, not white: less blue in the frame, though the pale chip adds.
    var blue_steady = 0
    var blue_drained = 0
    var right = 320 * 4
    for y in range(120, 180):
        for k in range(y * right + 200 * 4 + 2, (y + 1) * right, 4):
            blue_steady += Int(steady.pixels[k])
            blue_drained += Int(drained.pixels[k])
    assert_true(blue_drained != blue_steady)


def test_low_stamina_turns_the_gauge_amber() raises:
    var arena = Arena(arena_parameters(0, 0, 5))
    var camera = _camera()
    var look = Vector3(0, -1, -6) / Vector3(0, -1, -6).length()
    ref f = arena.battle.fighter
    f.stamina = f.parameters.stamina * 0.3
    var some = _frame()
    draw_battle(some, arena.battle, arena.scene, camera, look)
    f.stamina = f.parameters.stamina * 0.2
    var low = _frame()
    draw_battle(low, arena.battle, arena.scene, camera, look)
    # Amber is redder than the blue it was.
    var red_some = 0
    var red_low = 0
    for k in range(0, len(low.pixels), 4):
        red_some += Int(some.pixels[k])
        red_low += Int(low.pixels[k])
    assert_true(red_low > red_some)


def test_the_combo_count_pops_with_each_hit() raises:
    var arena = Arena(arena_parameters(0, 0, 5))
    var camera = _camera()
    var look = Vector3(0, -1, -6) / Vector3(0, -1, -6).length()
    arena.battle.fighter.combo = 7
    arena.battle.fighter.combo_age = POP_EASE
    var settled = _frame()
    draw_battle(settled, arena.battle, arena.scene, camera, look)
    # Just hit: the count stands larger, and lights more of the frame.
    arena.battle.fighter.combo_age = 0
    var fresh = _frame()
    draw_battle(fresh, arena.battle, arena.scene, camera, look)
    assert_true(_changed(fresh) > _changed(settled))


def test_a_number_pops_and_eases_back() raises:
    assert_almost_equal(pop_grow(0), 1 + POP_GROW, atol=1e-6)
    assert_true(pop_grow(POP_EASE / 2) < pop_grow(0))
    assert_true(pop_grow(POP_EASE / 2) > 1)
    assert_equal(pop_grow(POP_EASE), 1)
    assert_equal(pop_grow(5), 1)


def test_a_number_leans_and_a_word_stands_upright() raises:
    var number = popup_style("42", WHITE_TEXT, 1, 2)
    var word = popup_style("PARRY", WHITE_TEXT, 1, 2)
    var empty = popup_style("", WHITE_TEXT, 1, 2)
    assert_true(number.slant > 0 and number.weight > 0)
    assert_equal(word.slant, 0)
    assert_equal(empty.slant, 0)
    assert_true(word.outline > 0 and number.outline > 0)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
