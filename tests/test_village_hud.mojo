# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""What the village game writes over its frame: the satchel, the prompt
and the note."""

from extensions.village.gathering import (
    BERRIES,
    BITING,
    CHEST,
    FISH,
    IDLE,
    WAITING,
    GatherKind,
    HERBS,
    MUSHROOMS,
    ORE,
    SEAL,
    Satchel,
    TRINKET,
)
from extensions.village.hud import (
    CHIP,
    draw_arcs,
    TextStyle,
    draw_chip,
    draw_gauge,
    draw_panel,
    draw_pill,
    draw_styled,
    styled_width,
    text_size,
    clear_span,
    draw_vignette,
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
from std.math import ceil
from std.testing import (
    TestSuite,
    assert_almost_equal,
    assert_equal,
    assert_false,
    assert_raises,
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
    # The font is proportional: a W is wider than an I. Three times the
    # scale is three times as wide.
    assert_true(text_width("W", 2) > text_width("I", 2))
    var one = styled_width("AB", text_size(1))
    assert_almost_equal(styled_width("AB", text_size(3)), 3 * one, atol=1e-3)
    assert_equal(text_width("AB", 1), Int(ceil(one)))
    # A character that the font does not hold is a space.
    assert_almost_equal(styled_width("#", 10), styled_width(" ", 10), atol=1e-6)


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


def _lit(frame: Framebuffer, color: Rgb) -> Int:
    """Return how many pixels are within 12 of a color in each channel."""
    var count = 0
    for k in range(frame.width * frame.height):
        var r = Int(frame.pixels[4 * k])
        var g = Int(frame.pixels[4 * k + 1])
        var b = Int(frame.pixels[4 * k + 2])
        if abs(r - color.r) <= 12 and abs(g - color.g) <= 12:
            if abs(b - color.b) <= 12:
                count += 1
    return count


def test_text_is_drawn_with_a_shadow() raises:
    var frame = _frame(40, 24)
    draw_text(frame, 1, 1, "", 2, WHITE_TEXT, 1)
    assert_equal(_changed(frame), 0)
    # An unknown character is a space.
    draw_text(frame, 1, 1, "#", 2, WHITE_TEXT, 1)
    assert_equal(_changed(frame), 0)
    # A capital I: its stem in the text's color, its edges between, and
    # its shadow dark.
    draw_text(frame, 1, 1, "I", 2, WHITE_TEXT, 1)
    var lit = _lit(frame, WHITE_TEXT)
    var dark = 0
    var between = 0
    for k in range(40 * 24):
        var r = Int(frame.pixels[4 * k])
        if r < 100:
            dark += 1
        elif r > 100 and r < WHITE_TEXT.r - 12:
            between += 1
    assert_true(lit > 0)
    assert_true(dark > 0)
    assert_true(between > 0)
    # A small i is its own glyph.
    var small = _frame(40, 24)
    draw_text(small, 1, 1, "i", 2, WHITE_TEXT, 1)
    assert_true(_changed(small) > 0)
    assert_false(_changed(small) == _changed(frame))


def test_a_style_rings_leans_and_thickens_its_letters() raises:
    var size = Float32(20)
    var plain = _frame(80, 40)
    draw_styled(plain, 4, 8, "H", TextStyle(size, WHITE_TEXT, 1, 0, 0, 0, 0))
    var lit = _lit(plain, WHITE_TEXT)
    assert_true(lit > 0)
    # Nothing is drawn with no strength or no size.
    var none = _frame(80, 40)
    draw_styled(none, 4, 8, "H", TextStyle(size, WHITE_TEXT, 0, 2, 2, 0, 0))
    draw_styled(none, 4, 8, "H", TextStyle(0, WHITE_TEXT, 1, 2, 2, 0, 0))
    assert_equal(_changed(none), 0)
    # A ring darkens round the letters; a bolder letter covers more.
    var ringed = _frame(80, 40)
    draw_styled(ringed, 4, 8, "H", TextStyle(size, WHITE_TEXT, 1, 2, 0, 0, 0))
    assert_true(_changed(ringed) > _changed(plain))
    var bold = _frame(80, 40)
    draw_styled(bold, 4, 8, "H", TextStyle(size, WHITE_TEXT, 1, 0, 0, 1.5, 0))
    assert_true(_lit(bold, WHITE_TEXT) > lit)
    # A leaning letter's top stands right of its foot.
    var leaning = _frame(80, 40)
    draw_styled(
        leaning, 4, 8, "I", TextStyle(size, WHITE_TEXT, 1, 0, 0, 0, 0.3)
    )
    var upright = _frame(80, 40)
    draw_styled(upright, 4, 8, "I", TextStyle(size, WHITE_TEXT, 1, 0, 0, 0, 0))
    assert_true(_left_at(leaning, 10) > _left_at(upright, 10))
    # A letter off the frame, and a ring and a shadow wider than the
    # field holds, draw no box round the letters.
    var off = _frame(80, 40)
    draw_styled(off, -60, -60, "W", TextStyle(size, WHITE_TEXT, 1, 9, 9, 0, 0))
    draw_styled(off, 70, 30, "W", TextStyle(size, WHITE_TEXT, 1, 9, 9, 0, 0))
    var wide = _frame(80, 40)
    draw_styled(wide, 30, 10, ".", TextStyle(size, WHITE_TEXT, 1, 30, 30, 0, 0))
    assert_equal(Int(wide.pixels[0]), 100)
    assert_true(_changed(off) > 0)


def _left_at(frame: Framebuffer, y: Int) -> Int:
    """Return the first pixel of a row lit in the text's color, or -1."""
    for x in range(frame.width):
        if Int(frame.pixels[4 * (y * frame.width + x)]) >= WHITE_TEXT.r - 12:
            return x
    return -1


def test_a_gauge_leans_and_shows_what_a_blow_took() raises:
    var green = Rgb(96, 200, 90)
    # No size, no gauge.
    var none = _frame(200, 20)
    draw_gauge(none, 4, 4, 0, 6, 0.5, green)
    draw_gauge(none, 4, 4, 100, 0, 0.5, green)
    assert_equal(_changed(none), 0)
    # Empty, half full and full: the plate shows; the fill grows.
    var shares: List[Float32] = [0, 0.5, 1]
    var lit = List[Int]()
    for share in shares:
        var frame = _frame(200, 20)
        draw_gauge(frame, 4, 4, 160, 8, share, green)
        assert_true(_changed(frame) > 0)
        var greenish = 0
        for k in range(200 * 20):
            if Int(frame.pixels[4 * k + 1]) > Int(frame.pixels[4 * k]) + 40:
                greenish += 1
        lit.append(greenish)
    assert_equal(lit[0], 0)
    assert_true(lit[1] > 0 and lit[2] > lit[1])
    # What a blow took is pale past the fill.
    var chip = _frame(200, 20)
    draw_gauge(chip, 4, 4, 160, 8, 0.5, green, 0.8)
    var pale = 0
    for k in range(200 * 20):
        var r = Int(chip.pixels[4 * k])
        if r >= 200 and Int(chip.pixels[4 * k + 2]) >= CHIP.b - 60:
            pale += 1
    assert_true(pale > 0)
    # A small gauge has no ticks: neither a short one nor a narrow one.
    var thin = _frame(200, 20)
    draw_gauge(thin, 4, 4, 160, 3, 1, green)
    var narrow = _frame(200, 20)
    draw_gauge(narrow, 4, 4, 100, 8, 1, green)
    assert_true(_changed(thin) > 0 and _changed(narrow) > 0)
    # A gauge past the frame's foot is clipped.
    var low = _frame(200, 20)
    draw_gauge(low, 4, 16, 160, 8, 1, green)
    assert_true(_changed(low) > 0)


def test_a_ring_of_arcs_leaves_gaps_at_its_four_points() raises:
    var whole = _frame(60, 60)
    draw_arcs(whole, 30, 30, 20, 3, 0, WHITE_TEXT, 1)
    var arcs = _frame(60, 60)
    draw_arcs(arcs, 30, 30, 20, 3, 8, WHITE_TEXT, 1)
    assert_true(_changed(arcs) > 0)
    assert_true(_changed(arcs) < _changed(whole))
    # The top point is in a gap; the middle and far corners are untouched.
    assert_equal(Int(arcs.pixels[4 * (10 * 60 + 29)]), 100)
    assert_true(Int(whole.pixels[4 * (10 * 60 + 29)]) > 100)
    assert_equal(Int(whole.pixels[4 * (30 * 60 + 30)]), 100)
    # A dot of no radius, and a ring past the frame's edge, are clipped.
    var dot = _frame(60, 60)
    draw_arcs(dot, 0, 0, 0, 6, 0, WHITE_TEXT, 1)
    draw_arcs(dot, 60, 60, 10, 2, 4, WHITE_TEXT, 1)
    assert_true(Int(dot.pixels[0]) > 100)
    # A ring off the frame, above it or beside it, draws nothing.
    var none = _frame(60, 60)
    draw_arcs(none, 30, -100, 10, 2, 4, WHITE_TEXT, 1)
    draw_arcs(none, -100, 30, 10, 2, 4, WHITE_TEXT, 1)
    assert_equal(_changed(none), 0)


def test_glass_chips_and_pills_round_their_corners() raises:
    var frame = _frame(80, 40)
    # Off the frame, or empty: nothing.
    draw_panel(frame, 90, 0, 120, 20, 2)
    draw_panel(frame, 10, 10, 10, 30, 2)
    draw_chip(frame, 20, 20, 20, 30, WHITE_TEXT, 1)
    draw_chip(frame, 20, 20, 30, 20, WHITE_TEXT, 1)
    assert_equal(_changed(frame), 0)
    draw_panel(frame, -10, 4, 50, 60, 2)
    # Its corners are round: the corner's pixel keeps its gray.
    assert_equal(Int(frame.pixels[4 * (4 * 80 + 49)]), 100)
    var middle = 4 * (20 * 80 + 20)
    assert_true(Int(frame.pixels[middle]) < 100)
    var pill = _frame(80, 40)
    draw_pill(pill, 10, 10, 70, 30, 0.5)
    assert_equal(Int(pill.pixels[4 * (10 * 80 + 10)]), 100)
    assert_true(Int(pill.pixels[4 * (20 * 80 + 40)]) < 100)
    var chip = _frame(80, 40)
    draw_chip(chip, 10, 10, 30, 30, GOLD_TEXT, 1)
    assert_true(_lit(chip, GOLD_TEXT) > 0)


def test_a_vignette_reddens_the_corners_and_not_the_middle() raises:
    var frame = _frame(40, 40)
    draw_vignette(frame, 0)
    assert_equal(_changed(frame), 0)
    draw_vignette(frame, 1)
    assert_true(Int(frame.pixels[0]) > Int(frame.pixels[1]))
    var middle = (20 * 40 + 20) * 4
    assert_equal(Int(frame.pixels[middle]), 100)
    with assert_raises(contains="strength"):
        draw_vignette(frame, 2)
    with assert_raises(contains="strength"):
        draw_vignette(frame, -1)


def test_each_kind_has_a_color_and_a_prompt() raises:
    var kinds: List[GatherKind] = [
        HERBS,
        MUSHROOMS,
        BERRIES,
        ORE,
        CHEST,
        TRINKET,
        FISH,
    ]
    var reds = List[Int]()
    var prompts = List[String]()
    for kind in kinds:
        reds.append(kind_color(kind).g * 1000 + kind_color(kind).r)
        prompts.append(use_prompt(kind, 1))
    for a in range(7):
        for b in range(a + 1, 7):
            assert_true(reds[a] != reds[b])
            assert_true(prompts[a] != prompts[b])
    # A seal of the warden's has a color of its own.
    var seal = kind_color(SEAL).g * 1000 + kind_color(SEAL).r
    for red in reds:
        assert_true(red != seal)
    assert_equal(use_prompt(ORE, 2), "E  MINE ORE 2/3")
    assert_equal(use_prompt(ORE, 0, 0, 1), "E  MINE ORE 0/1")
    assert_equal(use_prompt(HERBS, 0), "E  GATHER HERBS")
    assert_equal(use_prompt(FISH, 0, IDLE), "E  CAST LINE")
    assert_equal(use_prompt(FISH, 0, WAITING), "E  REEL IN")
    assert_equal(use_prompt(FISH, 0, BITING), "E  HOOK IT!")
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
    # A prompt with no button stands alone on its pill.
    var keyless = _frame(480, 270)
    draw_hud(keyless, Satchel(), "LOOK", "", 0)
    assert_true(_changed(keyless) > 0)
    assert_true(_changed(keyless) < _changed(prompted))
    var noted = _frame(480, 270)
    draw_hud(noted, Satchel(), "", "+1 herbs", 0)
    assert_true(_changed(prompted) > 0)
    assert_true(_changed(noted) > 0)
    # Its letters are gold: red well over blue.
    var warm = 0
    for k in range(480 * 270):
        if Int(noted.pixels[4 * k]) - Int(noted.pixels[4 * k + 2]) > 40:
            warm += 1
    assert_true(warm > 0)
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
    # The skills are listed in the top left.
    var skilled = _frame(480, 270)
    var skills: List[String] = ["MINING 2  60/150"]
    draw_hud(skilled, satchel, "", "", 0, "", 0, List[String](), skills)
    var top_left = 0
    var other = 0
    for y in range(270):
        for x in range(480):
            if skilled.pixels[4 * (y * 480 + x)] != 100:
                if x < 240 and y < 40:
                    top_left += 1
                else:
                    other += 1
    assert_true(top_left > 0)
    assert_equal(other, 0)
    # A note lasts as long as it is given.
    assert_equal(note_alpha(4, 5), 1)
    assert_equal(note_alpha(5, 5), 0)


def test_punctuation_is_drawn() raises:
    for mark in [".", ",", "!", "?", "'", "-"]:
        var frame = _frame(12, 12)
        draw_text(frame, 1, 1, mark, 1, WHITE_TEXT, 1)
        assert_true(_changed(frame) > 0)


def test_a_row_skips_only_what_lies_clear_inside_a_circle() raises:
    # The middle row of a wide circle: a long span, short of its ends.
    var wide = clear_span(50, 100, 101, 1)
    assert_true(wide[0] > 0 and wide[0] < 5)
    assert_true(wide[1] > 95 and wide[1] < 100)
    # Each pixel in the span lies inside the circle.
    for x in range(wide[0], wide[1]):
        var dx = (Float32(x) + 0.5) / 100 * 2 - 1
        assert_true(dx * dx <= 1)
    # A row past the circle, and a row that meets it in less than a pixel
    # or two, skip nothing.
    var past = clear_span(0, 100, 100, 0.5)
    assert_equal(past[0], past[1])
    var thin = clear_span(50, 100, 101, 0.02)
    assert_equal(thin[0], 0)
    assert_equal(thin[1], 0)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
