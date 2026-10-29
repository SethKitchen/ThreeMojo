# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""What the village game writes over its frame: the satchel, the prompt
and the note."""

from extensions.village.gathering import (
    BERRIES,
    CHEST,
    GatherKind,
    HERBS,
    MUSHROOMS,
    ORE,
    Satchel,
    TRINKET,
)
from extensions.village.hud import (
    GOLD_TEXT,
    NOTE_SECONDS,
    Rgb,
    WHITE_TEXT,
    draw_hud,
    draw_text,
    fill_box,
    hud_scale,
    kind_color,
    note_alpha,
    note_text,
    text_width,
    use_prompt,
)
from render.framebuffer import Framebuffer
from std.testing import (
    TestSuite,
    assert_almost_equal,
    assert_equal,
    assert_false,
    assert_true,
)


def _frame(width: Int, height: Int) raises -> Framebuffer:
    """Return a gray frame."""
    return Framebuffer(
        width, height, List[UInt8](length=width * height * 4, fill=100)
    )


def _changed(frame: Framebuffer) -> Int:
    """Return how many pixels are no longer gray."""
    var count = 0
    for k in range(frame.width * frame.height):
        if frame.pixels[4 * k] != 100:
            count += 1
    return count


def test_the_text_keeps_its_size_on_the_screen() raises:
    assert_equal(hud_scale(270), 1)
    assert_equal(hud_scale(200), 1)
    assert_equal(hud_scale(1080), 4)
    assert_equal(text_width("", 2), 0)
    assert_equal(text_width("AB", 1), 11)
    assert_equal(text_width("AB", 3), 33)


def test_a_box_is_blended_and_clipped() raises:
    var frame = _frame(8, 8)
    fill_box(frame, -4, -4, 2, 2, Rgb(200, 0, 0), 0.5)
    assert_equal(_changed(frame), 4)
    assert_equal(Int(frame.pixels[0]), 150)
    assert_equal(Int(frame.pixels[1]), 50)
    # A box off the frame changes nothing.
    fill_box(frame, 10, 10, 12, 12, Rgb(200, 0, 0), 1)
    fill_box(frame, -6, 0, -2, 4, Rgb(200, 0, 0), 1)
    assert_equal(_changed(frame), 4)


def test_text_is_drawn_with_a_shadow() raises:
    var frame = _frame(40, 12)
    draw_text(frame, 1, 1, "", 1, WHITE_TEXT, 1)
    assert_equal(_changed(frame), 0)
    # An unknown character is a space.
    draw_text(frame, 1, 1, "#", 1, WHITE_TEXT, 1)
    assert_equal(_changed(frame), 0)
    # A capital I: seven dots down its middle and two pairs at its ends,
    # eleven dots, and its shadow.
    draw_text(frame, 1, 1, "i", 1, WHITE_TEXT, 1)
    var lit = 0
    var dark = 0
    for k in range(40 * 12):
        if Int(frame.pixels[4 * k]) == WHITE_TEXT.r:
            lit += 1
        elif Int(frame.pixels[4 * k]) != 100:
            dark += 1
    assert_equal(lit, 11)
    assert_true(dark > 0)


def test_each_kind_has_a_color_and_a_prompt() raises:
    var kinds: List[GatherKind] = [
        HERBS,
        MUSHROOMS,
        BERRIES,
        ORE,
        CHEST,
        TRINKET,
    ]
    var reds = List[Int]()
    var prompts = List[String]()
    for kind in kinds:
        reds.append(kind_color(kind).g * 1000 + kind_color(kind).r)
        prompts.append(use_prompt(kind, 1))
    for a in range(6):
        for b in range(a + 1, 6):
            assert_true(reds[a] != reds[b])
            assert_true(prompts[a] != prompts[b])
    assert_equal(use_prompt(ORE, 2), "E  MINE ORE 2/3")
    assert_equal(use_prompt(HERBS, 0), "E  GATHER HERBS")
    assert_equal(note_text(BERRIES, 3), "+3 berries")


def test_a_note_fades_at_its_end() raises:
    assert_equal(note_alpha(0), 1)
    assert_equal(note_alpha(NOTE_SECONDS - 0.6), 1)
    assert_almost_equal(note_alpha(NOTE_SECONDS - 0.25), 0.5, atol=1e-5)
    assert_equal(note_alpha(NOTE_SECONDS), 0)
    assert_equal(note_alpha(NOTE_SECONDS + 3), 0)


def test_the_hud_shows_the_satchel_the_prompt_and_the_note() raises:
    var satchel = Satchel()
    # Nothing to show draws nothing.
    var bare = _frame(480, 270)
    draw_hud(bare, satchel, "", "", 0)
    assert_equal(_changed(bare), 0)
    # A note that has faded draws nothing either.
    draw_hud(bare, satchel, "", "+1 herbs", NOTE_SECONDS)
    assert_equal(_changed(bare), 0)
    # The satchel, in the bottom left, lists only what it holds.
    satchel.counts[HERBS.value] = 2
    var held = _frame(480, 270)
    draw_hud(held, satchel, "", "", 0)
    var left = 0
    var right = 0
    for y in range(270):
        for x in range(480):
            if held.pixels[4 * (y * 480 + x)] != 100:
                if x < 240:
                    left += 1
                else:
                    right += 1
    assert_true(left > 0)
    assert_equal(right, 0)
    satchel.counts[ORE.value] = 1
    var two = _frame(480, 270)
    draw_hud(two, satchel, "", "", 0)
    assert_true(_changed(two) > _changed(held))
    # The prompt and the note are drawn in the middle.
    var prompted = _frame(480, 270)
    draw_hud(prompted, Satchel(), "E  GATHER HERBS", "", 0)
    var noted = _frame(480, 270)
    draw_hud(noted, Satchel(), "", "+1 herbs", 0)
    assert_true(_changed(prompted) > 0)
    assert_true(_changed(noted) > 0)
    var gold = False
    for k in range(480 * 270):
        if Int(noted.pixels[4 * k]) == GOLD_TEXT.r:
            gold = True
    assert_true(gold)
    assert_false(_changed(prompted) == _changed(noted))


def test_the_hud_shows_what_was_said_and_the_errands() raises:
    var satchel = Satchel()
    # Speech that has faded draws nothing.
    var quiet = _frame(480, 270)
    draw_hud(quiet, satchel, "", "", 0, "ANN: HELLO.", 9)
    assert_equal(_changed(quiet), 0)
    var said = _frame(480, 270)
    draw_hud(said, satchel, "", "", 0, "ANN: HELLO.", 0)
    assert_true(_changed(said) > 0)
    # The errands are listed in the top right.
    var listed = _frame(480, 270)
    var errands: List[String] = ["herbs for Ann 1/3", "ore for Bo 0/2"]
    draw_hud(listed, satchel, "", "", 0, "", 0, errands)
    var top_right = 0
    var elsewhere = 0
    for y in range(270):
        for x in range(480):
            if listed.pixels[4 * (y * 480 + x)] != 100:
                if x > 240 and y < 40:
                    top_right += 1
                else:
                    elsewhere += 1
    assert_true(top_right > 0)
    assert_equal(elsewhere, 0)
    # A note lasts as long as it is given.
    assert_equal(note_alpha(4, 5), 1)
    assert_equal(note_alpha(5, 5), 0)


def test_punctuation_is_drawn() raises:
    for mark in [".", ",", "!", "?", "'", "-"]:
        var frame = _frame(12, 12)
        draw_text(frame, 1, 1, mark, 1, WHITE_TEXT, 1)
        assert_true(_changed(frame) > 0)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
