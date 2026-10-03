# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Bounded overlap witnesses for two canonical implicit solids.

A negative field value is an interior witness. The fields need not be
exact distance functions. Their values are not penetration depth or
physical clearance. A positive gap between conservative bounding boxes
is a clearance lower bound. No sampled hit does not prove no overlap.
"""

from extensions.humanoid.skeleton.field import DistanceField, finite_point
from extensions.humanoid.skeleton.limb.sampling import SampleGrid
from extensions.humanoid.skeleton.occupancy import check_mass_step
from math.vector3 import Vector3
from std.math import isfinite, max, min, sqrt
from units.si import Length, Volume


@fieldwise_init
struct PairDiagnostic(ImplicitlyCopyable):
    """A bounding-box clearance bound and sampled overlap evidence.

    `overlap_volume` is a midpoint estimate. It can miss thin overlap.
    `field_witness` is meaningful only when `samples` is positive.
    """

    var bounds_gap: Length
    """Clearance lower bound between conservative field boxes."""
    var samples: Int
    """Number of tested cell centers."""
    var overlap_samples: Int
    """Number of centers with both field values negative."""
    var overlap_volume: Volume
    """Estimated common-interior volume from accepted cells."""
    var field_witness: Length
    """Minimum sampled maximum field value; not a true distance."""


def _check_bounds(low: Vector3, high: Vector3) raises:
    """Refuse invalid bounds even when the other box is disjoint."""
    finite_point(low, "lower bound", "overlap diagnostic")
    finite_point(high, "upper bound", "overlap diagnostic")
    if low.x >= high.x or low.y >= high.y or low.z >= high.z:
        raise Error("Diagnostic bounds must be strictly ordered")


def diagnose_pair[
    F: DistanceField, G: DistanceField
](
    first: F,
    first_low: Vector3,
    first_high: Vector3,
    second: G,
    second_low: Vector3,
    second_high: Vector3,
    step: Length,
) raises -> PairDiagnostic:
    """Sample the intersecting box of two already validated solids.

    Parameters:
        F: Type of the first canonical field.
        G: Type of the second canonical field.

    Args:
        first: The first canonical field.
        first_low: Its conservative lower bound, in meters.
        first_high: Its conservative upper bound, in meters.
        second: The second field in the same coordinate frame.
        second_low: Its conservative lower bound, in meters.
        second_high: Its conservative upper bound, in meters.
        step: Grid width, 2 mm through 20 mm.

    Returns:
        A clearance lower bound and explicitly sampled overlap evidence.

    Raises:
        Error: If a step or bound is invalid, the requested work is too
            large, or a field returns a non-finite value.
    """
    check_mass_step(step, "overlap diagnostic")
    _check_bounds(first_low, first_high)
    _check_bounds(second_low, second_high)
    var low = Vector3(
        max(first_low.x, second_low.x),
        max(first_low.y, second_low.y),
        max(first_low.z, second_low.z),
    )
    var high = Vector3(
        min(first_high.x, second_high.x),
        min(first_high.y, second_high.y),
        min(first_high.z, second_high.z),
    )
    var dx = max(Float64(low.x) - Float64(high.x), Float64(0))
    var dy = max(Float64(low.y) - Float64(high.y), Float64(0))
    var dz = max(Float64(low.z) - Float64(high.z), Float64(0))
    var distance = sqrt(dx * dx + dy * dy + dz * dz)
    if not isfinite(Float32(distance)):
        raise Error("Diagnostic clearance exceeds the supported length range")
    var gap = Length(Float32(distance))
    if low.x >= high.x or low.y >= high.y or low.z >= high.z:
        return PairDiagnostic(gap, 0, 0, Volume(0), Length(0))
    var grid = SampleGrid(low, high, step)
    var hits = 0
    var volume = Float64(0)
    var witness = Float32.MAX
    for iz in range(grid.nz):  # pragma: no branch
        for iy in range(grid.ny):  # pragma: no branch
            for ix in range(grid.nx):  # pragma: no branch
                var p, widths = grid._cell(ix, iy, iz)
                var a = first.distance(p)
                var b = second.distance(p)
                if not isfinite(a) or not isfinite(b):
                    raise Error("A diagnostic field value must be finite")
                witness = min(witness, max(a, b))
                if a < 0 and b < 0:
                    hits += 1
                    volume += (
                        Float64(widths.x)
                        * Float64(widths.y)
                        * Float64(widths.z)
                    )
    return PairDiagnostic(
        gap,
        grid.nx * grid.ny * grid.nz,
        hits,
        Volume(Float32(volume)),
        Length(witness),
    )
