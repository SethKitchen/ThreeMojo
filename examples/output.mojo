# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Read an example's output path and write its animated PNG.

Each example builds its own scene. This file reads the path from the
first argument and stores the frames.
"""

from core.clock import Clock
from render.apng import encode
from render.framebuffer import Framebuffer
from std.pathlib import Path
from std.sys import argv, stderr
from units.si import MILLISECOND


def example_destination(default_name: String) -> String:
    """Return the first program argument, or `default_name`.

    Args:
        default_name: The path used when the program has no argument.

    Returns:
        The output path.
    """
    var args = argv()
    if len(args) > 1:
        return String(args[1])
    return default_name


def write_example(
    frames: List[Framebuffer],
    destination: String,
    delay_ms: Int,
    frame_count: Int,
    mut clock: Clock,
) raises:
    """Write `frames` and print how long the render took.

    Args:
        frames: The rendered frames, in order.
        destination: The path of the animated PNG.
        delay_ms: How long each frame is shown, in milliseconds.
        frame_count: How many frames the example says it wrote.
        clock: The clock started before the first frame.

    Raises:
        Error: If the frames cannot be encoded or the path cannot be
            written.
    """
    print(
        '{"frames_ms": ',
        clock.elapsed().to(MILLISECOND),
        "}",
        sep="",
        file=stderr,
    )
    Path(destination).write_bytes(encode(frames, delay_ms=delay_ms))
    print("Wrote", destination, "-", frame_count, "frames")
