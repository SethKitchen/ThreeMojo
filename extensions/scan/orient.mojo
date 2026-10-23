# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Which way is up in a scan, read from its splats.

A scan keeps the axes of the software that trained it, and a drone scan or
a video scan has no upright of its own. A building has floors, and a floor
or the ground is a wide flat surface. So the splats that lie flat vote for
the up axis: a flat splat is much thinner along its normal than across it,
and each one adds its weight, its opacity times its area, to the scan axis
that its normal is nearest to. The axis with most of the weight is up, or
down.

The sign comes from the walls. A wall stands on the floor, so the weight
of the splats that stand upright is on the up side of the floor's layer.
The floor's layer is the heaviest layer of flat splats along the axis. A
scan with no wall splats, or one whose walls are as much above the floor
as below it, has no sign to read. Then the estimate has a `side` of 0, and
takes the sign that most scans have: the y axis points down in COLMAP, so
up is -y.

The normal of a splat is the eigenvector of its covariance with the
smallest eigenvalue. It is found by the power method on the trace times the
identity less the covariance, which has the largest eigenvalue where the
covariance has the smallest.
"""

from core.gaussian_splat_utils import GaussianSplatGeometry
from extensions.scan.frame import ScanAxis
from std.math import sqrt

comptime ORIENT_SAMPLES = 200000
"""How many splats vote, at most. They are spread evenly through the scan."""
comptime FLAT_RATIO = Float64(0.05)
"""A flat splat's least variance is at most this share of its middle one."""
comptime HORIZONTAL = Float64(0.8)
"""A splat's normal is along an axis when its cosine with it is more than this."""
comptime UPRIGHT = Float64(0.35)
"""A wall splat's normal is across the axis, with a cosine of less than this."""
comptime LAYER_BINS = 128
"""The bins of the layers' histogram along the up axis."""
comptime POWER_STEPS = 32
"""The steps of the power method for a normal."""
comptime TINY = Float64(1e-300)
"""A length this small is zero: the vector it divides stays zero."""


@fieldwise_init
struct UpEstimate(ImplicitlyCopyable):
    """The up axis of a scan and how well the splats say it."""

    var axis: ScanAxis
    """The scan axis that points up."""
    var share: Float64
    """The share of the flat splats' weight that the up coordinate holds,
    from one third, no preference, to 1."""
    var side: Float64
    """How plainly the walls give the sign, from 0 to 1. At 0 the sign is the
    default, -y for y."""


def _normal(covariances: List[Float32], at: Int) -> SIMD[DType.float64, 4]:
    """Return a splat's normal and its three variances' summary.

    Args:
        covariances: Six numbers a splat: xx, xy, xz, yy, yz and zz.
        at: The first of the splat's six.

    Returns:
        The unit normal in the first three lanes, with the smallest variance
        in the last, or all zeros for a splat with no extent.
    """
    var xx = Float64(covariances[at])
    var xy = Float64(covariances[at + 1])
    var xz = Float64(covariances[at + 2])
    var yy = Float64(covariances[at + 3])
    var yz = Float64(covariances[at + 4])
    var zz = Float64(covariances[at + 5])
    var trace = xx + yy + zz
    if not (trace > 0):
        return SIMD[DType.float64, 4](0)
    # The largest eigenvalue of trace * I - C is trace less C's smallest.
    var x = Float64(0.5774)
    var y = Float64(0.5773)
    var z = Float64(0.5772)
    var value = Float64(0)
    for _ in range(POWER_STEPS):  # pragma: no branch
        var nx = (trace - xx) * x - xy * y - xz * z
        var ny = -xy * x + (trace - yy) * y - yz * z
        var nz = -xz * x - yz * y + (trace - zz) * z
        var length = sqrt(nx * nx + ny * ny + nz * nz)
        var inverse = 1 / max(length, TINY)
        x = nx * inverse
        y = ny * inverse
        z = nz * inverse
        value = length
    return SIMD[DType.float64, 4](x, y, z, trace - value)


def largest_variance(covariances: List[Float32], at: Int) -> Float64:
    """Return a covariance's largest eigenvalue, by the power method.

    Args:
        covariances: Six numbers a splat: xx, xy, xz, yy, yz and zz.
        at: The first of the splat's six.

    Returns:
        The eigenvalue: the variance along the splat's longest axis, in
        square scan units.
    """
    var x = Float64(0.5774)
    var y = Float64(0.5773)
    var z = Float64(0.5772)
    var value = Float64(0)
    for _ in range(POWER_STEPS):  # pragma: no branch
        var nx = (
            Float64(covariances[at]) * x
            + Float64(covariances[at + 1]) * y
            + Float64(covariances[at + 2]) * z
        )
        var ny = (
            Float64(covariances[at + 1]) * x
            + Float64(covariances[at + 3]) * y
            + Float64(covariances[at + 4]) * z
        )
        var nz = (
            Float64(covariances[at + 2]) * x
            + Float64(covariances[at + 4]) * y
            + Float64(covariances[at + 5]) * z
        )
        var length = sqrt(nx * nx + ny * ny + nz * nz)
        var inverse = 1 / max(length, TINY)
        x = nx * inverse
        y = ny * inverse
        z = nz * inverse
        value = length
    return value


def estimate_up(
    geometry: GaussianSplatGeometry, samples: Int = ORIENT_SAMPLES
) raises -> UpEstimate:
    """Return the up axis of a scan; see the module docstring.

    Args:
        geometry: The splats.
        samples: How many splats vote, at most, 1 or more.

    Returns:
        The up axis, with the share of the weight behind it and how plainly
        the walls gave its sign.

    Raises:
        Error: If there are no samples, or no splat is flat.
    """
    if samples < 1:
        raise Error("Scan orient: at least one splat must vote")
    var count = geometry.count()
    var step = max(1, count // samples)
    var votes = List[Float64](length=3, fill=0)
    # For each flat splat that votes, its weight and its three normals.
    var kept = List[Int]()
    var normals = List[SIMD[DType.float64, 4]]()
    var weights = List[Float64]()
    var index = 0
    while index < count:
        var at = index * 6
        var n = _normal(geometry.covariances, at)
        var smallest = n[3]
        # The normal is a unit vector, or zero for a splat with no extent.
        if n[0] * n[0] + n[1] * n[1] + n[2] * n[2] > 0.5:
            var largest = largest_variance(geometry.covariances, at)
            var trace = (
                Float64(geometry.covariances[at])
                + Float64(geometry.covariances[at + 3])
                + Float64(geometry.covariances[at + 5])
            )
            var middle = trace - smallest - largest
            if middle > 0 and smallest <= FLAT_RATIO * middle:
                var weight = (
                    Float64(geometry.colors[index * 4 + 3])
                    / 255
                    * sqrt(largest * middle)
                )
                for a in range(3):  # pragma: no branch
                    votes[a] += weight * n[a] * n[a]
                kept.append(index)
                normals.append(n)
                weights.append(weight)
        index += step
    var total = votes[0] + votes[1] + votes[2]
    if not (total > 0):
        raise Error("Scan orient: no splat is flat")
    var coordinate = 0
    for a in range(1, 3):  # pragma: no branch
        if votes[a] > votes[coordinate]:
            coordinate = a
    var share = votes[coordinate] / total

    # The heights of the flat splats along the up coordinate, for the layers.
    var low = Float64(geometry.centers[kept[0] * 3 + coordinate])
    var high = low
    for place in range(len(kept)):  # pragma: no branch
        var h = Float64(geometry.centers[kept[place] * 3 + coordinate])
        low = min(low, h)
        high = max(high, h)
    var span = max(high - low, 1e-12)
    var layers = List[Float64](length=LAYER_BINS, fill=0)
    for place in range(len(kept)):  # pragma: no branch
        var n = normals[place]
        if abs(n[coordinate]) < HORIZONTAL:
            continue
        var h = Float64(geometry.centers[kept[place] * 3 + coordinate])
        var bin = min(
            Int((h - low) / span * Float64(LAYER_BINS)), LAYER_BINS - 1
        )
        layers[bin] += weights[place]
    var floor = 0
    for bin in range(1, LAYER_BINS):  # pragma: no branch
        if layers[bin] > layers[floor]:
            floor = bin
    var floor_height = low + (Float64(floor) + 0.5) / Float64(LAYER_BINS) * span
    # The walls' weight above and below the floor's layer.
    var above = Float64(0)
    var below = Float64(0)
    for place in range(len(kept)):  # pragma: no branch
        var n = normals[place]
        if abs(n[coordinate]) > UPRIGHT:
            continue
        var h = Float64(geometry.centers[kept[place] * 3 + coordinate])
        if h > floor_height:
            above += weights[place]
        else:
            below += weights[place]
    var side = Float64(0)
    if above + below > 0:
        side = abs(above - below) / (above + below)
    var positive = above > below
    if side == 0:
        # The default sign: y points down, and the other axes point up.
        positive = coordinate != 1
    return UpEstimate(
        ScanAxis(coordinate * 2 + (0 if positive else 1)), share, side
    )
