# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Products that round before a following sum can fuse them.

JavaScript rounds each `*` before it adds. A compiler may fuse
`a * b + c` into one multiply-add. `@no_inline` keeps the product as
its own rounding. Earcut, IES, SVG, noise, a convex cut, a color
matrix and a lookup table use it so they match three.js. A lerp of
that form is `rounded_lerp`.
"""


@no_inline
def rounded_product(a: Float64, b: Float64) -> Float64:
    """Return `a * b`, rounded once before any sum uses it.

    Args:
        a: The left factor.
        b: The right factor.

    Returns:
        The product, as JavaScript rounds a `*` before a `+`.
    """
    return a * b


def rounded_lerp(x: Float64, y: Float64, t: Float64) -> Float64:
    """Return `(1 - t) * x + t * y`, each product rounded before the sum.

    This is three.js's `MathUtils.lerp`.

    Args:
        x: The start.
        y: The end.
        t: The fraction.

    Returns:
        The mix.

    Raises:
        Error: Never.
    """
    return rounded_product(1 - t, x) + rounded_product(t, y)
