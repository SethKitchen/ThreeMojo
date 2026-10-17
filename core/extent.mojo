# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Whether a width and a height are positive.

A size of zero is not an image, a view, or a window. Callers keep their
own error text. `require_positive_extent` raises that text.
`require_texel_count` refuses a buffer whose length is not one entry a texel.
`require_closed_count` refuses a count outside a closed range.
"""


def positive_extent(width: Int, height: Int, depth: Int = 1) -> Bool:
    """Return True when every size is positive.

    Args:
        width: The width.
        height: The height.
        depth: A third size. One when the caller has only a width and a
            height.

    Returns:
        True when `width`, `height`, and `depth` are all greater than zero.
    """
    return width > 0 and height > 0 and depth > 0


def require_positive_extent(
    width: Int, height: Int, message: String, depth: Int = 1
) raises:
    """Refuse a size that is not positive.

    Args:
        width: The width.
        height: The height.
        message: The error text for this caller.
        depth: A third size. One when the caller has only a width and a
            height.

    Returns:
        Nothing. The call returns when every size is positive.

    Raises:
        Error: If `width`, `height`, or `depth` is not positive.
    """
    if not positive_extent(width, height, depth):
        raise Error(message)


def require_texel_count(
    length: Int,
    width: Int,
    height: Int,
    channels: Int,
    message: String,
) raises:
    """Refuse a buffer whose length is not one entry a texel.

    Args:
        length: How many entries the buffer holds.
        width: The width, in texels.
        height: The height, in texels.
        channels: How many entries one texel holds.
        message: The error text for this caller.

    Returns:
        Nothing. The call returns when the length matches.

    Raises:
        Error: If `length` is not the width times the height times the
            channels.
    """
    if length != width * height * channels:
        raise Error(message)


def require_closed_count(
    value: Int, low: Int, high: Int, message: String
) raises:
    """Refuse a count outside a closed range.

    Args:
        value: The count.
        low: The least allowed count.
        high: The greatest allowed count.
        message: The error text for this caller.

    Returns:
        Nothing. The call returns when `value` is from `low` through `high`.

    Raises:
        Error: If `value` is below `low` or above `high`.
    """
    if value < low or value > high:
        raise Error(message)
