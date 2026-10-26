# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""A scan of a site that is known exactly, with any scan axis up.

`site_scan` places flat splats on a square of ground and, if asked, on the
four walls of a box that stands on it. The site is written in building
axes, x, y and z up, and then laid out on the scan axes: the up coordinate
of the scan reads z, and the other two read x and y in order. So a test can
check a reader of a scan's up axis against all six axes.
"""

from core.gaussian_splat_utils import (
    GaussianSplatGeometry,
    create_gaussian_splat_geometry,
)
from extensions.scan.frame import ScanAxis

comptime GROUND = 30
"""The ground is this many splats along each side, one meter apart."""
comptime WALL_HEIGHT = 5
"""The walls are this many splats high, one meter apart."""


struct _Splats(Movable):
    """The arrays of a geometry, filled one splat at a time."""

    var centers: List[Float32]
    var covariances: List[Float32]
    var colors: List[UInt8]

    def __init__(out self):
        self.centers = List[Float32]()
        self.covariances = List[Float32]()
        self.colors = List[UInt8]()

    def add(
        mut self,
        up: ScanAxis,
        x: Float64,
        y: Float64,
        z: Float64,
        thin: Int,
        opacity: UInt8,
    ):
        """Add a flat splat at a building point, thin along one building axis.

        Args:
            up: The scan axis that points up.
            x: East, in meters.
            y: North, in meters.
            z: Up, in meters.
            thin: The building axis it is thin along: 0, 1 or 2.
            opacity: Its opacity byte.
        """
        var coordinate = up.index()
        var others = List[Int]()
        for c in range(3):
            if c != coordinate:
                others.append(c)
        var at = List[Float64](length=3, fill=0)
        at[coordinate] = up.sign() * z
        at[others[0]] = x
        at[others[1]] = y
        # The building axis that each scan coordinate reads.
        var reads = List[Int](length=3, fill=0)
        reads[coordinate] = 2
        reads[others[0]] = 0
        reads[others[1]] = 1
        for c in range(3):
            self.centers.append(Float32(at[c]))
        var variance = List[Float32](length=3, fill=0)
        for c in range(3):
            if reads[c] == thin:
                variance[c] = Float32(0.004 * 0.004)
            else:
                variance[c] = Float32(0.3 * 0.3)
        self.covariances.extend(
            [variance[0], 0, 0, variance[1], 0, variance[2]]
        )
        self.colors.extend([180, 170, 160, opacity])


def site_scan(
    up: ScanAxis, walls: Bool, opacity: UInt8 = 230
) raises -> GaussianSplatGeometry:
    """Return the splats of a site; see the module docstring.

    Args:
        up: The scan axis that points up.
        walls: Whether a box of walls stands on the ground.
        opacity: The opacity byte of every splat.

    Returns:
        A ground of `GROUND` by `GROUND` splats, and with walls a box of
        ten meters on a side and `WALL_HEIGHT` splats high.

    Raises:
        Error: Never, for a valid axis.
    """
    var out = _Splats()
    for a in range(GROUND):
        for b in range(GROUND):
            out.add(up, Float64(a), Float64(b), 0, 2, opacity)
    if walls:
        for h in range(1, WALL_HEIGHT + 1):
            for a in range(10):
                out.add(up, Float64(a) + 10, 10, Float64(h), 1, opacity)
                out.add(up, Float64(a) + 10, 20, Float64(h), 1, opacity)
                out.add(up, 10, Float64(a) + 10, Float64(h), 0, opacity)
                out.add(up, 20, Float64(a) + 10, Float64(h), 0, opacity)
    return create_gaussian_splat_geometry(
        out.centers.copy(), out.covariances.copy(), out.colors.copy()
    )
