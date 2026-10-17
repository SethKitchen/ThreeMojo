# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""The sub-pixel jitter a temporal upscaler needs.

DLSS builds the output from many renders, each moved by a fraction of a
pixel. The move is a camera offset, and it must stay out of the matrices
that Streamline gets (see `extensions.streamline.constants`).

The offsets are the Halton sequence in bases two and three, as TRAA and
TAAU use it, less a half. Each lies from minus a half to a half of a render
pixel. They are the offsets that `JitteredCamera` takes: the view moves by
the offset and the picture moves the other way.

**What this port decides.** `jitter_phase_count` is eight samples for every
output pixel that one render pixel covers. Streamline does not require a
count. And Streamline's headers do not say which way its `jitterOffset`
points. A native binding must check the sign against a running DLSS before
it passes `jitter_offset` on.
"""

from extensions.streamline.sizing import FrameSize
from math.vector2 import Vector2
from postprocessing.traa import halton
from std.math import ceil


def jitter_phase_count(render: FrameSize, output: FrameSize) raises -> Int:
    """Return how many offsets the jitter walks through.

    Args:
        render: The size the scene is rendered at.
        output: The output's size.

    Returns:
        Eight times the square of the output's width over the render's,
        rounded up. It is never below eight.

    Raises:
        Error: If a size has a side below one pixel, or the render is wider
            than the output.
    """
    if render.width < 1 or render.height < 1:
        raise Error("A render must be at least one pixel each way")
    if output.width < render.width:
        raise Error("A render must not be wider than the output")
    var ratio = Float64(output.width) / Float64(render.width)
    return Int(ceil(8.0 * ratio * ratio))


def jitter_offset(index: Int, phase_count: Int) raises -> Vector2:
    """Return the offset of a frame, in render pixels.

    Args:
        index: The frame's number. It wraps round the phase count.
        phase_count: How many offsets there are.

    Returns:
        The Halton numbers of the frame's place in bases two and three, less
        a half. The offset lies from minus a half to a half each way.

    Raises:
        Error: If the index is negative or the phase count is below one.
    """
    if index < 0:
        raise Error("A frame number must not be negative")
    if phase_count < 1:
        raise Error("A jitter needs at least one phase")
    var place = index % phase_count + 1
    return Vector2(halton(place, 2) - 0.5, halton(place, 3) - 0.5)
