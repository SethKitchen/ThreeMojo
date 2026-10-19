# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Whether a width and a height are positive.

A size of zero is not an image, a view, or a window. Callers keep their
own error text. `require_positive_extent` raises that text.
`require_texel_count` checks the buffer length after the sizes are checked.
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

    Nothing. The call returns when every size is positive.

    Args:
        width: The width.
        height: The height.
        message: The error text for this caller.
        depth: A third size. One when the caller has only a width and a
            height.

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
    """Refuse a buffer whose length differs from the texel entry count.

    Check positive sizes separately with `require_positive_extent`.
    This check only compares the length with the product; it does not
    validate the sizes. A product that cannot fit in Int raises the
    caller's error instead of trapping on signed overflow.

    Nothing. The call returns when the length matches.

    Args:
        length: How many entries the buffer holds.
        width: The width, in texels. The caller checks that it is positive.
        height: The height, in texels. The caller checks that it is positive.
        channels: Entries per texel. The caller checks that it is positive.
        message: The error text for this caller.

    Raises:
        Error: If `length` is not the width times the height times the
            channels, or the product cannot fit in Int.
    """
    # Two Int factors fit exactly in Int128, including Int.MIN * -1.
    # Check the last factor against the final sign's magnitude limit.
    # A zero channel count can still make an oversized area fit.
    var area = Int128(width) * Int128(height)
    var factor = Int128(channels)
    var negative = (area < 0) != (factor < 0)
    var limit = Int128(Int.MAX) + Int128(negative)
    if factor != 0 and abs(area) > limit // abs(factor):
        raise Error(message)
    if Int128(length) != area * factor:
        raise Error(message)


def require_closed_count(
    value: Int, low: Int, high: Int, message: String
) raises:
    """Refuse a count outside a closed range.

    Nothing. The call returns when `value` is from `low` through `high`.

    Args:
        value: The count.
        low: The least allowed count.
        high: The greatest allowed count.
        message: The error text for this caller.

    Raises:
        Error: If `value` is below `low` or above `high`.
    """
    if value < low or value > high:
        raise Error(message)
