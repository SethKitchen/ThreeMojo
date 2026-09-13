# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""P3 (plain text) PPM encoding.

PPM's whole appeal is that the file is human-readable: you can open one in a
text editor and see the pixel values. That makes it a good debugging format and
a bad delivery format. It carries no alpha channel at all, and most viewers —
VS Code's image preview among them — cannot display it. Use `render.png` for
anything you actually want to look at.
"""

from render.framebuffer import Framebuffer


def encode(buffer: Framebuffer, mut writer: Some[Writer]) raises:
    """Write `buffer` to `writer` as a P3 PPM image.

    Alpha is discarded: PPM has no channel for it. Nothing is composited
    against a background first, so a transparent pixel writes its raw color.

    Args:
        buffer: The pixels to encode.
        writer: Destination; a `String` works, so tests can assert exact bytes.

    Raises:
        Error: If a pixel coordinate is out of bounds, which cannot happen
            while iterating the buffer's own dimensions.
    """
    writer.write("P3\n")
    writer.write(buffer.width, " ", buffer.height, "\n")
    writer.write(255, "\n")
    # A Framebuffer always has positive dimensions, so neither loop can run
    # zero times.
    for y in range(buffer.height):  # pragma: no branch
        for x in range(buffer.width):  # pragma: no branch
            var c = buffer.get_pixel(x, y)
            writer.write(c.r, " ", c.g, " ", c.b, "\n")


def to_stdout(buffer: Framebuffer) raises:
    """Write `buffer` to stdout as a P3 PPM image."""
    var out = String("")
    encode(buffer, out)
    print(out, end="")
