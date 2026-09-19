# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Left or right of the body, as a type rather than a bare integer.

A femur, and later a tibia or a humerus, is not symmetric across the
midline. The head of a right femur points medial, toward minus x in the
bone's own frame; a left femur is that shape with x flipped. The type
stops a bare integer at compile time. A value that is not `LEFT` or
`RIGHT` is still constructible, and the boundary that reads it refuses it.
"""


@fieldwise_init
struct BodySide(Equatable, ImplicitlyCopyable, Writable):
    """Which side of the body a paired bone belongs to."""

    var value: Int

    def is_valid(self) -> Bool:
        """Return True if this is `RIGHT` or `LEFT`."""
        return self == RIGHT or self == LEFT


# The right limb. In the bone's frame plus x is lateral, minus x is medial.
comptime RIGHT = BodySide(0)
# The left limb: the right bone with x flipped.
comptime LEFT = BodySide(1)
