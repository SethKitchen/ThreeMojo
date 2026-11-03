# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""The move of a tensor into the frame of the Eulerian observer.

The Eulerian observer is at rest in the slices of constant time. Its
frame is orthonormal: in it the metric is the Minkowski metric η. Its
T^00 is the energy density that this observer measures, and its T^0i is
the momentum density.

`eulerian_transform` is WarpFactory's `getEulerianTransformationMatrix`:
the explicit Cholesky factor M with Mᵀ g M = η. M is lower triangular,
with a positive diagonal. `to_eulerian` is WarpFactory's
`doFrameTransfer`: T̂_ab = Mᵀ T_ab M, then T̂^0i = -T̂_0i.

## Differences from WarpFactory

WarpFactory warns when M is infinite or imaginary and goes on. This port
raises an error: the metric has no Eulerian frame at that point, for
example inside a horizon.
"""

from std.math import isfinite, sqrt

from extensions.warp.kinds import (
    CONTRAVARIANT,
    COVARIANT,
    EULERIAN_FRAME,
)
from extensions.warp.solver import StressEnergy
from extensions.warp.tensor import (
    Matrix4,
    Metric,
    TensorField,
    change_index,
    multiply4,
    transpose4,
)


def eulerian_transform(g: Matrix4) raises -> Matrix4:
    """Return the lower triangular M with Mᵀ g M = η.

    Args:
        g: The covariant metric at one point. It must be symmetric.

    Returns:
        M, in row-major order. Column 0 is the observer's 4-velocity.

    Raises:
        Error: If an entry of M is not finite. Then the slice of constant
            time is not spacelike at the point.
    """
    var g11 = g[0]
    var g12 = g[1]
    var g13 = g[2]
    var g14 = g[3]
    var g22 = g[5]
    var g23 = g[6]
    var g24 = g[7]
    var g33 = g[10]
    var g34 = g[11]
    var g44 = g[15]
    var f0 = g44
    var f1 = -g34 * g34 + g33 * f0
    var f2 = (
        2.0 * g23 * g24 * g34 - g44 * g23 * g23 - g33 * g24 * g24 + g22 * f1
    )
    var f3 = (
        -2.0 * g44 * g12 * g13 * g23
        + 2.0 * g13 * g14 * g23 * g24
        + 2.0 * g12 * g13 * g24 * g34
        + 2.0 * g12 * g14 * g23 * g34
        - g12 * g12 * g34 * g34
        - g13 * g13 * g24 * g24
        - g14 * g14 * g23 * g23
        + g33 * (-2.0 * g12 * g14 * g24 + g44 * g12 * g12)
        + g22 * (-2.0 * g13 * g14 * g34 + g44 * g13 * g13 + g33 * g14 * g14)
        - g11 * f2
    )
    var m = Matrix4(0)
    var root23 = sqrt(f2 * f3)
    var root12 = sqrt(f1 * f2)
    var root01 = sqrt(f0 * f1)
    m[0] = sqrt(f2 / f3)
    m[4] = (
        g12 * g34 * g34
        + g13 * g23 * g44
        - g13 * g24 * g34
        - g14 * g23 * g34
        + g14 * g24 * g33
        - g12 * g33 * g44
    ) / root23
    m[8] = (
        g13 * g24 * g24
        - g14 * g23 * g24
        + g12 * g23 * g44
        - g12 * g24 * g34
        - g13 * g22 * g44
        + g14 * g22 * g34
    ) / root23
    m[12] = (
        g14 * g23 * g23
        - g13 * g23 * g24
        - g12 * g23 * g34
        + g12 * g24 * g33
        + g13 * g22 * g34
        - g14 * g22 * g33
    ) / root23
    m[5] = sqrt(f1 / f2)
    m[9] = (g24 * g34 - g23 * g44) / root12
    m[13] = (g23 * g34 - g24 * g33) / root12
    m[10] = sqrt(f0 / f1)
    m[14] = -g34 / root01
    m[15] = sqrt(1.0 / f0)
    for k in range(16):
        if not isfinite(m[k]):
            raise Error("A metric has no Eulerian frame at a grid point")
    return m


def to_eulerian(energy: StressEnergy, metric: Metric) raises -> StressEnergy:
    """Return a stress-energy tensor in the Eulerian frame.

    This is WarpFactory's `doFrameTransfer` with the frame "Eulerian". A
    tensor that is in the Eulerian frame already is returned unchanged.

    Args:
        energy: The tensor, at any index position.
        metric: The metric. It must have the same grid.

    Returns:
        The tensor, contravariant, in the Eulerian frame.

    Raises:
        Error: If the grids differ, the metric is singular at a point, or
            the metric has no Eulerian frame at a point.
    """
    if energy.tensor.frame == EULERIAN_FRAME:
        return energy.copy()
    var lowered = change_index(energy.tensor, COVARIANT, metric)
    var grid = metric.grid()
    var out = TensorField(grid, CONTRAVARIANT, EULERIAN_FRAME)
    for point in range(grid.points()):  # pragma: no branch
        var m = eulerian_transform(metric.at(point))
        var value = multiply4(
            multiply4(transpose4(m), lowered.matrix(point)), m
        )
        for i in range(1, 4):
            value[i] = -value[i]
            value[4 * i] = -value[4 * i]
        out.set_matrix(point, value)
    return StressEnergy(out^, energy.name, energy.order)
