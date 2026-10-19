# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Signed distance of a dermal shell.

The shell is the band from an outer surface inward by a thickness. The
deep interior and the exterior are both outside that band.
"""

from std.math import max


def dermal_shell_distance(outer: Float32, thickness: Float32) -> Float32:
    """Return the signed distance to a dermal shell, in meters.

    Args:
        outer: Signed distance to the outer surface, in meters. Negative
            is inside the body.
        thickness: Shell thickness, in meters.

    Returns:
        Negative inside the shell. The deep interior and the exterior
        are both outside it.
    """
    return max(outer, -outer - thickness)
