# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Whether a width and a height are positive.

A size of zero is not an image, a view, or a window. Callers keep their
own error text.
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
