# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""The two square roots a GGX lobe shares.

`ggx_smith_root` is the length inside Smith's shadowing. `ggx_base` is
the denominator of the distribution, before it is raised.
"""

from std.math import sqrt


def ggx_smith_root(ndot: Float32, alpha2: Float32) -> Float32:
    """Return the square root in Smith's GGX shadowing.

    Args:
        ndot: The cosine between the normal and one direction.
        alpha2: GGX alpha, already squared.

    Returns:
        `sqrt(a^2 + (1 - a^2) n^2)`.
    """
    return sqrt(alpha2 + (1 - alpha2) * ndot * ndot)


def ggx_base(ndot_h: Float32, alpha2: Float32) -> Float32:
    """Return the base of a GGX distribution.

    Args:
        ndot_h: The cosine between the normal and the half vector.
        alpha2: GGX alpha, already squared.

    Returns:
        `n.h^2 (a^2 - 1) + 1`.
    """
    return ndot_h * ndot_h * (alpha2 - 1) + 1
