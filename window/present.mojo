# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""The checks a window makes before it draws a frame."""

from render.framebuffer import Framebuffer


def require_open(is_open: Bool) raises:
    """Refuse a closed window.

    Args:
        is_open: Whether the window is open.

    Returns:
        Nothing. The call returns when the window is open.

    Raises:
        Error: If the window is closed.
    """
    if not is_open:
        raise Error("The window is closed")


def require_presented_frame(
    is_open: Bool, frame: Framebuffer, width: Int, height: Int
) raises:
    """Refuse a frame a closed window cannot draw, or one of another size.

    Args:
        is_open: Whether the window is open.
        frame: The frame to draw.
        width: The window's width, in pixels.
        height: The window's height, in pixels.

    Returns:
        Nothing. The call returns when the frame can be drawn.

    Raises:
        Error: If the window is closed, or the frame is another size.
    """
    require_open(is_open)
    if frame.width != width or frame.height != height:
        raise Error(
            "A frame of ",
            frame.width,
            "x",
            frame.height,
            " does not fit a window of ",
            width,
            "x",
            height,
        )
