# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""What the village game writes over its frame: the satchel, what the
player can use, what the player just gathered, what a villager said,
and the errands the player has taken.

`draw_hud` draws five things on a frame, in pixels, with a font of 5 by 7
dots that needs no font file:

1. **The satchel.** A panel in the bottom left lists each kind the player
   holds, with a swatch of its color and its count.
2. **The prompt.** When the player can use a spot or talk to a villager,
   a line in the bottom middle says which button uses it and what it
   does, such as `E  GATHER HERBS`, or `E  TALK TO MAUD`.
3. **The note.** For two seconds after the player gathers something, a
   line over the prompt says what, such as `+3 BERRIES`. It fades over
   its last half second.
4. **The speech.** For `SPEECH_SECONDS` after a villager speaks, a panel
   over the note shows their name and their words.
5. **The errands.** Each errand taken and not yet done is a line in the
   top right, such as `HERBS FOR MAUD 2/5`.

Each dot is a square of `hud_scale` pixels, so the text keeps its size
on the screen at every window's size. Each line has a dark shadow, so it
reads over the sky and the grass alike.
"""

from extensions.village.gathering import (
    BERRIES,
    BITING,
    CHEST,
    FISH,
    GatherKind,
    HERBS,
    KINDS,
    MUSHROOMS,
    ORE,
    SEAL,
    STRIKES,
    WAITING,
    Satchel,
    TRINKET,
    kind_name,
)
from extensions.village.talk import SPEECH_SECONDS
from render.framebuffer import Framebuffer
from render.tasks import TaskGroup
from renderers.renderer import available_workers
from std.math import ceil, floor, sqrt

comptime GLYPHS = (
    "ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789+/:.,!?'-"
    + "abcdefghijklmnopqrstuvwxyz"
)
"""The characters the font draws, in the order of its rows. Any other
character is a space."""
comptime VIGNETTE_CLEAR = Float32(0.45)
"""The share of the way from a frame's middle to its corner that a
vignette leaves clear."""
comptime NOTE_SECONDS = Float32(2.0)
"""How long a note stays, in seconds."""
comptime NOTE_FADE = Float32(0.5)
"""How long a note takes to fade at its end, in seconds."""


comptime _DIGITS = "0123456789ABCDEFGHIJKLMNOPQRSTUV"
"""The 32 values a row of five dots can take, as one character each."""
comptime _FONT = (
    "EHHVHHH UHHUHHU EHGGGHE UHHHHHU VGGUGGV VGGUGGG EHGNHHF HHHVHHH E44444E "
    + "72222IC HIKOKIH GGGGGGV HRLLHHH HHPLJHH EHHHHHE UHHUGGG EHHHLID UHHUKIH "
    + "FGGE11U V444444 HHHHHHE HHHHHA4 HHHLLLA HHA4AHH HHA4444 V1248GV EHJLPHE "
    + "4C4444E EH1248V V2421HE 26AIV22 VGU11HE 68GUHHE V124888 EHHEHHE EHHF12C "
    + "044V440 01248G0 0CC0CC0 00000CC 0000C48 4444404 EH12404 4480000 "
    + "000V000 "
    + "00E1FHF GGMPHHU 00EGGHE 11DJHHF 00EHVGE 698S888 0FHHF1E GGMPHHH 40C444E "
    + "20622IC GGIKOKI C44444E 00QLLHH 00MPHHH 00EHHHE 0UHHUGG 0DJJD11 00MPGGG "
    + "00EGE1U 88S8896 00HHHJD 00HHHA4 00HHLLA 00HA4AH 0HHHF1E 00V248V"
)
"""The font, a group of seven rows a glyph in the order of `GLYPHS`, each
row one character of `_DIGITS`: its value's bit 4 is the left dot."""


def _row(glyph: Int, row: Int) -> Int:
    """Return the dots of one row of a glyph, the left dot in bit 4."""
    var code = String(_FONT).as_bytes()[8 * glyph + row]
    return String(_DIGITS).find(chr(Int(code)))


@fieldwise_init
struct Rgb(ImplicitlyCopyable):
    """A color of the overlay, as sRGB bytes."""

    var r: Int
    var g: Int
    var b: Int


comptime WHITE_TEXT = Rgb(245, 238, 220)
comptime GOLD_TEXT = Rgb(255, 205, 90)
comptime SHADOW = Rgb(10, 8, 6)
comptime PANEL_ALPHA = Float32(0.38)
"""How dark a panel behind a group of the display's words and bars is,
from 0 to 1."""


def hud_scale(height: Int) -> Int:
    """Return the pixels a dot of the font takes on a frame.

    Args:
        height: The frame's height, in pixels.

    Returns:
        One dot a pixel up to 359 pixels tall, and one more pixel for each
        270 pixels past that: 4 at 1080.
    """
    return max(1, height // 270)


def text_width(text: String, scale: Int) -> Int:
    """Return how wide a line of text is drawn.

    Args:
        text: The line.
        scale: The pixels a dot takes.

    Returns:
        Six dots a character, less the gap after the last, in pixels.
    """
    var count = text.byte_length()
    if count == 0:
        return 0
    return (6 * count - 1) * scale


def _blend(mut frame: Framebuffer, x: Int, y: Int, color: Rgb, alpha: Float32):
    """Blend a color over one pixel of the frame."""
    var at = (y * frame.width + x) * 4
    var keep = 1 - alpha
    frame.pixels[at] = UInt8(
        Int(Float32(frame.pixels[at]) * keep + Float32(color.r) * alpha)
    )
    frame.pixels[at + 1] = UInt8(
        Int(Float32(frame.pixels[at + 1]) * keep + Float32(color.g) * alpha)
    )
    frame.pixels[at + 2] = UInt8(
        Int(Float32(frame.pixels[at + 2]) * keep + Float32(color.b) * alpha)
    )


def fill_box(
    mut frame: Framebuffer,
    x0: Int,
    y0: Int,
    x1: Int,
    y1: Int,
    color: Rgb,
    alpha: Float32,
):
    """Blend a color over a box of pixels, clipped to the frame.

    Args:
        frame: The frame.
        x0: The box's left pixel.
        y0: Its top pixel.
        x1: One past its right pixel.
        y1: One past its bottom pixel.
        color: The color.
        alpha: How much of the color covers the frame, from 0 to 1.
    """
    for y in range(max(0, y0), min(frame.height, y1)):
        for x in range(max(0, x0), min(frame.width, x1)):
            _blend(frame, x, y, color, alpha)


def draw_text(
    mut frame: Framebuffer,
    x: Int,
    y: Int,
    text: String,
    scale: Int,
    color: Rgb,
    alpha: Float32,
):
    """Draw a line of text with a shadow, its top left at a pixel.

    A character that the font does not hold is left as a space.

    Args:
        frame: The frame.
        x: The left of the first character, in pixels.
        y: The top of the line, in pixels.
        text: The line.
        scale: The pixels a dot takes.
        color: The text's color.
        alpha: How much the text and its shadow cover the frame, from 0
            to 1.
    """
    var glyphs = String(GLYPHS)
    var bytes = text.as_bytes()
    for k in range(len(bytes)):
        var at = glyphs.find(chr(Int(bytes[k])))
        if at < 0:
            continue
        var left = x + 6 * scale * k
        for shadow in range(2):
            var off = scale if shadow == 0 else 0
            var paint = SHADOW if shadow == 0 else color
            for row in range(7):
                var bits = _row(at, row)
                for dot in range(5):
                    if (bits >> (4 - dot)) & 1 == 0:
                        continue
                    var px = left + dot * scale + off
                    var py = y + row * scale + off
                    fill_box(
                        frame, px, py, px + scale, py + scale, paint, alpha
                    )


def draw_outlined(
    mut frame: Framebuffer,
    x: Int,
    y: Int,
    text: String,
    scale: Int,
    color: Rgb,
    alpha: Float32,
):
    """Draw a line of text ringed by a dark outline, its top left at a
    pixel, so it reads over a bright sky as over dark grass.

    The outline is the text's shape drawn dark a stroke away in each of
    the four diagonals; the stroke is half a dot, and one pixel at
    least. A character that the font does not hold is left as a space.

    Args:
        frame: The frame.
        x: The left of the first character, in pixels.
        y: The top of the line, in pixels.
        text: The line.
        scale: The pixels a dot takes.
        color: The text's color.
        alpha: How much the text and its outline cover the frame, from 0
            to 1.
    """
    var glyphs = String(GLYPHS)
    var bytes = text.as_bytes()
    var stroke = max(1, scale // 2)
    for pass_ in range(5):
        var dx = 0
        var dy = 0
        var paint = SHADOW
        if pass_ < 4:
            dx = stroke if pass_ % 2 == 0 else -stroke
            dy = stroke if pass_ < 2 else -stroke
        else:
            paint = color
        for k in range(len(bytes)):
            var at = glyphs.find(chr(Int(bytes[k])))
            if at < 0:
                continue
            var left = x + 6 * scale * k + dx
            for row in range(7):
                var bits = _row(at, row)
                for dot in range(5):
                    if (bits >> (4 - dot)) & 1 == 0:
                        continue
                    var px = left + dot * scale
                    var py = y + row * scale + dy
                    fill_box(
                        frame, px, py, px + scale, py + scale, paint, alpha
                    )


def kind_color(kind: GatherKind) -> Rgb:
    """Return the swatch color of a kind in the satchel.

    Args:
        kind: The kind.

    Returns:
        Green herbs, red mushrooms, purple berries, copper ore, gold
        coins, blue trinkets, silver fish and black seals.
    """
    if kind == HERBS:
        return Rgb(90, 160, 60)
    if kind == MUSHROOMS:
        return Rgb(200, 50, 40)
    if kind == BERRIES:
        return Rgb(140, 40, 110)
    if kind == ORE:
        return Rgb(200, 110, 50)
    if kind == CHEST:
        return Rgb(250, 200, 70)
    if kind == FISH:
        return Rgb(150, 190, 210)
    if kind == SEAL:
        return Rgb(60, 50, 60)
    return Rgb(80, 140, 240)


def use_prompt(
    kind: GatherKind, strikes: Int, phase: Int = 0, needed: Int = STRIKES
) -> String:
    """Return what the prompt says the use button does at a spot.

    Args:
        kind: The spot's kind.
        strikes: How many times a boulder has been struck.
        phase: A fishing spot's phase: `IDLE`, `WAITING` or `BITING`.
        needed: How many strikes a boulder takes to give its ore.

    Returns:
        The button and the deed, such as "E  GATHER HERBS", or for a
        boulder "E  MINE ORE 1/3". At a fishing spot, it casts the line,
        reels it in, or hooks the fish that bites.
    """
    if kind == HERBS:
        return "E  GATHER HERBS"
    if kind == MUSHROOMS:
        return "E  PICK MUSHROOMS"
    if kind == BERRIES:
        return "E  PICK BERRIES"
    if kind == ORE:
        return String("E  MINE ORE ", strikes, "/", needed)
    if kind == CHEST:
        return "E  OPEN CHEST"
    if kind == FISH and phase == BITING:
        return "E  HOOK IT!"
    if kind == FISH and phase == WAITING:
        return "E  REEL IN"
    if kind == FISH:
        return "E  CAST LINE"
    return "E  TAKE TRINKET"


def note_text(kind: GatherKind, gives: Int) raises -> String:
    """Return the note that says what was gathered.

    Args:
        kind: The kind of spot.
        gives: How many things it gave.

    Returns:
        A plus, the count and the things' name, such as "+3 BERRIES".

    Raises:
        Error: If the kind is not one.
    """
    return String("+", gives, " ", kind_name(kind))


def note_alpha(age: Float32, seconds: Float32 = NOTE_SECONDS) -> Float32:
    """Return how strongly a note shows, by how long it has shown.

    Args:
        age: How long the note has shown, in seconds.
        seconds: How long the note shows.

    Returns:
        One until the fade begins, `NOTE_FADE` before the end, then less,
        to zero at `seconds` and after.
    """
    var left = seconds - age
    if left <= 0:
        return 0
    return min(Float32(1), left / NOTE_FADE)


def draw_vignette(mut frame: Framebuffer, strength: Float32) raises:
    """Redden a frame's edges, as a player who is hurt or near falling
    sees it.

    The red is strongest in the corners, and fades to nothing a
    `VIGNETTE_CLEAR` share of the way out from the middle.

    Args:
        frame: The frame. Its pixels are changed.
        strength: How strong the red is, from 0, none, to 1.

    Raises:
        Error: If the strength is not from 0 to 1.
    """
    if not (strength >= 0 and strength <= 1):
        raise Error("A vignette's strength must be from 0 to 1")
    if strength == 0:
        return
    var tasks = max(1, min(available_workers() * 2, frame.height))
    var group = TaskGroup()
    for t in range(tasks):  # pragma: no branch
        group.create_task(
            _vignette_task(
                frame.pixels.unsafe_ptr().unsafe_origin_cast[MutAnyOrigin](),
                frame.width,
                frame.height,
                strength,
                t * frame.height // tasks,
                (t + 1) * frame.height // tasks,
            )
        )
    group.wait()


def clear_span(
    y: Int, width: Int, height: Int, radius: Float32
) -> Tuple[Int, Int]:
    """Return the pixels of a row that lie, for certain, within a radius
    of the frame's middle, as an edge's tint measures it.

    A pixel's place is `((x + 0.5) / width * 2 - 1, (y + 0.5) / height *
    2 - 1)`. The span keeps a little inside the circle, and a pixel of
    margin at each end, so a pixel near the circle's edge is left to the
    tint's own test.

    Args:
        y: The row.
        width: The frame's width, in pixels.
        height: The frame's height, in pixels.
        radius: The radius, in those units.

    Returns:
        The first pixel of the span and the one past its last; the two
        are equal for a row with no such pixel.
    """
    var dy = (Float32(y) + 0.5) / Float32(height) * 2 - 1
    # A row near the top or the bottom of the circle meets it at a slant,
    # where a rounding of its height moves the ends far: the span keeps
    # a little inside the circle.
    var inside = radius * 0.999
    var room = inside * inside - dy * dy
    if room <= 0:
        return (0, 0)
    var half = sqrt(room)
    var w = Float32(width)
    var first = max(0, Int(ceil((1 - half) * w / 2 - 0.5)) + 1)
    var past = min(width, Int(floor((1 + half) * w / 2 - 0.5)))
    if past <= first:
        return (0, 0)
    return (first, past)


__async def _vignette_task(
    pixels: MutPointer[UInt8, MutAnyOrigin],
    width: Int,
    height: Int,
    strength: Float32,
    first: Int,
    past: Int,
):
    """Redden rows `first` to `past`, past the clear middle."""
    var w = Float32(width)
    var h = Float32(height)
    for y in range(first, past):  # pragma: no branch
        var dy = (Float32(y) + 0.5) / h * 2 - 1
        var clear = clear_span(y, width, height, VIGNETTE_CLEAR * 1.4142)
        var x = 0
        while x < width:
            if x == clear[0] and clear[1] > clear[0]:
                x = clear[1]
                continue
            var dx = (Float32(x) + 0.5) / w * 2 - 1
            var reach = sqrt(dx * dx + dy * dy) / 1.4142
            if reach > VIGNETTE_CLEAR:
                var t = (reach - VIGNETTE_CLEAR) / (1 - VIGNETTE_CLEAR)
                var alpha = min(Float32(0.85), t * t * strength)
                var at = (y * width + x) * 4
                var keep = 1 - alpha
                pixels[unsafe_offset=at] = UInt8(
                    Int(Float32(pixels[unsafe_offset=at]) * keep + 150 * alpha)
                )
                pixels[unsafe_offset=at + 1] = UInt8(
                    Int(Float32(pixels[unsafe_offset=at + 1]) * keep)
                )
                pixels[unsafe_offset=at + 2] = UInt8(
                    Int(Float32(pixels[unsafe_offset=at + 2]) * keep)
                )
            x += 1


def draw_hud(
    mut frame: Framebuffer,
    satchel: Satchel,
    prompt: String,
    note: String,
    note_age: Float32,
    speech: String = String(),
    speech_age: Float32 = SPEECH_SECONDS,
    errands: List[String] = List[String](),
    skills: List[String] = List[String](),
) raises:
    """Draw the satchel, the prompt, the note, what a villager said, the
    errands taken and the player's skills over a frame.

    Args:
        frame: The frame, the window's size.
        satchel: What the player holds. A kind the player holds none of
            is left out, and an empty satchel draws no panel.
        prompt: What the use button does, or empty for no prompt.
        note: What was just gathered, or empty for no note.
        note_age: How long the note has shown, in seconds.
        speech: What a villager last said, or empty for nothing. It shows
            in a panel over the note for `SPEECH_SECONDS`.
        speech_age: How long it has shown, in seconds.
        errands: A line for each errand taken, listed in the top right.
        skills: A line for each skill, listed in the top left.

    Raises:
        Error: Never: each kind's name is known.
    """
    var scale = hud_scale(frame.height)
    var line = 10 * scale
    var margin = 6 * scale
    var shown = List[Int]()
    for k in range(KINDS):  # pragma: no branch
        if satchel.counts[k] > 0:
            shown.append(k)
    if len(shown) > 0:
        var widest = 0
        for k in shown:  # pragma: no branch
            var label = String(kind_name(GatherKind(k)), " ", satchel.counts[k])
            widest = max(widest, text_width(label, scale))
        var top = frame.height - margin - line * len(shown) - 2 * scale
        fill_box(
            frame,
            margin - 3 * scale,
            top - 3 * scale,
            margin + widest + 12 * scale,
            frame.height - margin + scale,
            SHADOW,
            0.45,
        )
        for row in range(len(shown)):  # pragma: no branch
            var k = shown[row]
            var y = top + row * line
            var swatch = kind_color(GatherKind(k))
            fill_box(
                frame,
                margin,
                y,
                margin + 6 * scale,
                y + 7 * scale,
                swatch,
                1,
            )
            draw_text(
                frame,
                margin + 9 * scale,
                y,
                String(kind_name(GatherKind(k)), " ", satchel.counts[k]),
                scale,
                WHITE_TEXT,
                1,
            )
    var bottom = frame.height - margin - 7 * scale
    if prompt.byte_length() > 0:
        var width = text_width(prompt, scale)
        var x = (frame.width - width) // 2
        fill_box(
            frame,
            x - 4 * scale,
            bottom - 3 * scale,
            x + width + 4 * scale,
            bottom + 9 * scale,
            SHADOW,
            0.45,
        )
        draw_text(frame, x, bottom, prompt, scale, WHITE_TEXT, 1)
    var alpha = note_alpha(note_age)
    if note.byte_length() > 0 and alpha > 0:
        var width = text_width(note, scale)
        draw_text(
            frame,
            (frame.width - width) // 2,
            bottom - 2 * line,
            note,
            scale,
            GOLD_TEXT,
            alpha,
        )
    var said = note_alpha(speech_age, SPEECH_SECONDS)
    if speech.byte_length() > 0 and said > 0:
        var width = text_width(speech, scale)
        var x = (frame.width - width) // 2
        var y = bottom - 4 * line
        fill_box(
            frame,
            x - 5 * scale,
            y - 4 * scale,
            x + width + 5 * scale,
            y + 11 * scale,
            SHADOW,
            0.55 * said,
        )
        draw_text(frame, x, y, speech, scale, WHITE_TEXT, said)
    for row in range(len(errands)):
        var width = text_width(errands[row], scale)
        draw_text(
            frame,
            frame.width - margin - width,
            margin + row * line,
            errands[row],
            scale,
            GOLD_TEXT,
            1,
        )
    for row in range(len(skills)):
        draw_text(
            frame,
            margin,
            margin + row * line,
            skills[row],
            scale,
            WHITE_TEXT,
            1,
        )
