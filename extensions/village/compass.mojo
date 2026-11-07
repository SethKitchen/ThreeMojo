# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""A compass over the village game's frame: which way the camera looks,
and where the places that matter lie.

`draw_compass` draws a strip at the top middle of a frame. It shows
`COMPASS_SPAN` of the turn round the player, centered on the way the
camera looks:

- a tick each 15 degrees, and the letters `N`, `E`, `S` and `W` at the
  four points. North is minus z, the way a yaw of zero looks;
- a mark for each `CompassMark`, in its color, at the way it lies from
  the player. A mark past the strip's end stands at that end, half as
  bright, so the player knows which way to turn;
- under the strip, a caption: the hour and the weather.

`clock_text` writes an hour as a twelve-hour clock.

This is not a three.js port. See Extensions.

    var marks: List[CompassMark] = [
        CompassMark(Vector3(4, 0, -9), GOLD_TEXT),
    ]
    draw_compass(frame, player, camera_yaw, marks, "2:00 PM  CLEAR")
"""

from extensions.village.hud import (
    GOLD_TEXT,
    draw_pill,
    TextStyle,
    draw_styled,
    styled_width,
    Rgb,
    SHADOW,
    WHITE_TEXT,
    draw_outlined,
    draw_text,
    fill_box,
    hud_scale,
    text_width,
)
from math.vector3 import Vector3
from render.framebuffer import Framebuffer
from std.math import atan2, pi
from units.si import RADIAN, Angle

comptime COMPASS_SPAN = Float32(pi * 2 / 3)
"""How much of the turn the strip shows, in radians: 120 degrees."""
comptime COMPASS_SHARE = Float32(0.36)
"""How much of the frame's width the strip spans."""
comptime COMPASS_FADE = Float32(0.18)
"""How much of the strip's width, at each end, fades out."""
comptime TICK = Float32(pi / 12)
"""How far apart the strip's ticks are, in radians: 15 degrees."""


@fieldwise_init
struct CompassMark(ImplicitlyCopyable):
    """A place the compass points to, and its color."""

    var at: Vector3
    var color: Rgb


def bearing(origin: Vector3, at: Vector3, yaw: Angle) -> Float32:
    """Return how far a place lies from the way a camera looks, as a turn
    on the ground.

    Args:
        origin: Where the player stands.
        at: The place.
        yaw: The way the camera looks: zero along minus z.

    Returns:
        The turn from the camera's way to the place's, from -pi to pi
        radians: above zero to the left, below zero to the right, as a yaw
        turns.
    """
    var dx = at.x - origin.x
    var dz = at.z - origin.z
    var way = atan2(-dx, -dz)
    return _wrap(way - Float32(yaw.to(RADIAN)))


def _wrap(angle: Float32) -> Float32:
    """Return an angle as one from -pi to pi."""
    var a = angle
    var turn = Float32(2 * pi)
    while a > Float32(pi):
        a -= turn
    while a < -Float32(pi):
        a += turn
    return a


def clock_text(hour: Float32) -> String:
    """Return an hour as a twelve-hour clock, to the minute.

    Args:
        hour: The hour, from 0 to less than 24.

    Returns:
        Such as `2:05 PM`, or `12:00 AM` at midnight.
    """
    var minutes = Int(hour * 60) % (24 * 60)
    var h = minutes // 60
    var m = minutes % 60
    var shown = h % 12
    if shown == 0:
        shown = 12
    var half = "AM" if h < 12 else "PM"
    var tens = "0" if m < 10 else ""
    return String(shown, ":", tens, m, " ", half)


def draw_compass(
    mut frame: Framebuffer,
    origin: Vector3,
    yaw: Angle,
    marks: List[CompassMark],
    caption: String,
    drop: Int = 0,
):
    """Draw the compass at the top middle of a frame.

    Args:
        frame: The frame, the window's size.
        origin: Where the player stands.
        yaw: The way the camera looks.
        marks: The places to point to.
        caption: A line under the strip, or empty for none.
        drop: How far down from its place the compass stands, in dots of
            the heads-up display's font: room for a bar over it.
    """
    var scale = hud_scale(frame.height)
    var half = Int(Float32(frame.width) * COMPASS_SHARE / 2)
    var middle = frame.width // 2
    var top = (6 + drop) * scale
    var height = 9 * scale
    # The strip: dark at its middle, fading out to each end, with a light
    # line along its foot.
    var span = 2 * half
    for x in range(
        max(0, middle - half), min(frame.width, middle + half)
    ):  # pragma: no branch
        var t = Float32(x - middle + half) / Float32(span)
        var fade = min(Float32(1), min(t, 1 - t) / COMPASS_FADE)
        fill_box(frame, x, top, x + 1, top + height, SHADOW, 0.4 * fade)
        fill_box(
            frame,
            x,
            top + height - 1,
            x + 1,
            top + height,
            WHITE_TEXT,
            0.35 * fade,
        )
    var per = Float32(2 * half) / COMPASS_SPAN
    var turn = Float32(yaw.to(RADIAN))
    # A tick each `TICK`, and a letter at each point: the north gold.
    var letters: List[String] = ["N", "W", "S", "E"]
    var size = Float32(scale) * 5
    for k in range(24):  # pragma: no branch
        var at = _wrap(Float32(k) * TICK - turn)
        if abs(at) > COMPASS_SPAN / 2:
            continue
        var x = middle - Int(at * per)
        var t = Float32(x - middle + half) / Float32(span)
        var fade = min(Float32(1), min(t, 1 - t) / COMPASS_FADE)
        if k % 6 == 0:
            var letter = letters[k // 6]
            var color = GOLD_TEXT if k == 0 else WHITE_TEXT
            draw_styled(
                frame,
                Float32(x) - styled_width(letter, size) / 2,
                Float32(top) + (Float32(height) - size) / 2,
                letter,
                TextStyle(size, color, fade, 0, size * 0.1, 0.3 * size / 7, 0),
            )
        else:
            var tall = 3 * scale if k % 2 == 0 else 2 * scale
            fill_box(
                frame,
                x,
                top + height - tall - scale,
                x + max(1, scale // 3),
                top + height - scale,
                WHITE_TEXT,
                0.55 * fade,
            )
    # The way the camera looks: a small gold wedge under the strip.
    var tip = 2 * scale
    for row in range(tip):  # pragma: no branch
        var w = tip - row
        fill_box(
            frame,
            middle - w,
            top + height + row,
            middle + w + 1,
            top + height + row + 1,
            GOLD_TEXT,
            0.95,
        )
    for mark in marks:
        var at = bearing(origin, mark.at, yaw)
        var bright = Float32(1)
        if abs(at) > COMPASS_SPAN / 2:
            at = COMPASS_SPAN / 2 if at > 0 else -COMPASS_SPAN / 2
            bright = 0.5
        var x = middle - Int(at * per)
        # A diamond, ringed dark.
        var r = 2 * scale
        var y = top + height // 2
        for dy in range(-r - 1, r + 2):  # pragma: no branch
            var w = r + 1 - abs(dy)
            fill_box(frame, x - w, y + dy, x + w + 1, y + dy + 1, SHADOW, 0.6)
        for dy in range(-r, r + 1):  # pragma: no branch
            var w = r - abs(dy)
            fill_box(
                frame, x - w, y + dy, x + w + 1, y + dy + 1, mark.color, bright
            )
    if caption.byte_length() > 0:
        # The caption stands over the sky: a dark pill keeps it clear.
        var small = Float32(scale) * 4.5
        var wide = styled_width(caption, small)
        var y = top + height + 4 * scale
        var pill = Int(small) + 4 * scale
        draw_pill(
            frame,
            middle - Int(wide / 2) - 4 * scale,
            y - 2 * scale,
            middle + Int(wide / 2) + 4 * scale,
            y - 2 * scale + pill,
            0.42,
        )
        draw_styled(
            frame,
            Float32(middle) - wide / 2,
            Float32(y),
            caption,
            TextStyle(small, WHITE_TEXT, 1, 0, small * 0.1, 0, 0),
        )
