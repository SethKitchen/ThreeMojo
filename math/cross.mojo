# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""The cross product of two vectors, as a new vector.

`Vector3.cross` keeps the product in one statement. A caller that must
leave both inputs unchanged uses `cross_vectors`.
"""

from math.vector3 import Vector3


def cross_vectors(a: Vector3, b: Vector3) -> Vector3:
    """Return the cross product of `a` and `b`.

    `a` and `b` stay as they were.

    Args:
        a: The first vector.
        b: The second vector.

    Returns:
        The product `a` x `b`.
    """
    var out = a
    out.cross(b)
    return out
