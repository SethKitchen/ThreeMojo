# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""The checks a window makes before it opens or draws a frame."""

from core.extent import positive_extent
from render.framebuffer import Framebuffer

# `XCreateSimpleWindow` takes a `c_int` for each side.
comptime NATIVE_WINDOW_MAX = Int(Int32.MAX)


def require_window_size(width: Int, height: Int) raises:
    """Refuse a window whose size is not positive.

    Nothing. The call returns when both sizes are positive.

    Args:
        width: The width, in pixels.
        height: The height, in pixels.

    Raises:
        Error: If the width or the height is not positive.
    """
    if not positive_extent(width, height):
        raise Error(
            "A window's size must be positive, got ", width, "x", height
        )


def require_native_window_size(width: Int, height: Int) raises:
    """Refuse a size Xlib cannot pass, or whose pixel buffer would wrap.

    Nothing. The call returns when both sizes are positive, fit in a
    native `c_int`, and four bytes a pixel fit in an integer.

    Args:
        width: The width, in pixels.
        height: The height, in pixels.

    Raises:
        Error: If the size is not positive, a side does not fit in a
            native integer, or four bytes a pixel do not fit.
    """
    require_window_size(width, height)
    if width > NATIVE_WINDOW_MAX or height > NATIVE_WINDOW_MAX:
        raise Error("A window's size does not fit in a native integer")
    if width > (Int.MAX // 4) // height:
        raise Error("A window is larger than this port stores")


def require_open(is_open: Bool) raises:
    """Refuse a closed window.

    Nothing. The call returns when the window is open.

    Args:
        is_open: Whether the window is open.

    Raises:
        Error: If the window is closed.
    """
    if not is_open:
        raise Error("The window is closed")


def require_presented_frame(
    is_open: Bool, frame: Framebuffer, width: Int, height: Int
) raises:
    """Refuse a frame a closed window cannot draw, or one of another size.

    Nothing. The call returns when the frame can be drawn.

    Args:
        is_open: Whether the window is open.
        frame: The frame to draw.
        width: The window's width, in pixels.
        height: The window's height, in pixels.

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
