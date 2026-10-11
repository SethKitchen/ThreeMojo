# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Products that round before a following sum can fuse them.

JavaScript rounds each `*` before it adds. A compiler may fuse
`a * b + c` into one multiply-add. `@no_inline` keeps the product as
its own rounding. Earcut, IES and SVG use it so they match three.js.
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
