# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Closed-form metrics, sampled on a grid or differentiated exactly.

An `AnalyticMetric` gives g_ab at any place as jets of the coordinates
x⁰ = c t, x, y and z. One formula then serves two purposes:

- `sample_metric` takes the values on a grid, for the finite-difference
  solver, as WarpFactory does.
- `exact_stress_energy` and `exact_curvature` take the exact first and
  second derivatives from the jets. There is no truncation error and no
  edge of the grid, so the result at each point depends only on that
  point.

`christoffel_symbols` gives the connection at any place, for geodesics.

A metric whose shape depends on a distance r from a center uses
`radial`, which differentiates a function of r through r². This keeps
the derivatives exact at r = 0, where r itself has no derivative.
"""

from std.math import sqrt

from extensions.warp.grid import (
    SpacetimeCenter,
    SpacetimeGrid,
    grid_place,
    grid_time,
    require_cartesian,
)
from extensions.warp.jet import Jet
from extensions.warp.kinds import (
    CONTRAVARIANT,
    COORDINATE_FRAME,
    COVARIANT,
    EXACT_DERIVATIVES,
    X_AXIS,
    Y_AXIS,
    Z_AXIS,
)
from extensions.warp.quantities import SPEED_OF_LIGHT, einstein_coupling
from extensions.warp.solver import (
    Curvature,
    StressEnergy,
    ricci_tensor,
    task_count,
)
from render.tasks import TaskGroup
from extensions.warp.tensor import (
    Matrix4,
    Metric,
    TensorField,
    inverse4,
    multiply4,
)


trait AnalyticMetric(Copyable, Movable):
    """A metric given in closed form at any place."""

    def components(self, place: List[Jet]) -> List[Jet]:
        """Return the covariant components g_ab at a place.

        Args:
            place: The jets of x⁰ = c t, x, y and z, in meters.

        Returns:
            Sixteen jets, g_ab at 4 a + b. The list must be symmetric.
        """
        ...

    def name(self) -> String:
        """Return the name of the metric.

        Returns:
            A name such as "Alcubierre".
        """
        ...


def flat_components() -> List[Jet]:
    """Return the Minkowski components as constant jets.

    Returns:
        Sixteen jets of diag(-1, 1, 1, 1).
    """
    var out = List[Jet](capacity=16)
    for k in range(16):
        var value = 0.0
        if k % 5 == 0:
            value = 1.0
        out.append(Jet.constant(value))
    out[0] = Jet.constant(-1.0)
    return out^


def radial(square: Jet, f: Float64, df: Float64, ddf: Float64) -> Jet:
    """Return the jet of f(r), given the jet of r² and f at r.

    With s = r², f(r) = g(s) where g'(s) = f'(r) / (2 r) and
    g''(s) = (f''(r) - f'(r) / r) / (4 s). At r = 0 the profile must be
    even, so f'(0) = 0, g'(0) = f''(0) / 2, and the gradient of s is zero.

    Args:
        square: The jet of r², a sum of squares of coordinate offsets.
        f: The value f(r).
        df: The slope f'(r).
        ddf: The curvature f''(r).

    Returns:
        The jet of f(r).
    """
    var s = square.value
    if s > 0.0:
        var r = sqrt(s)
        return Jet(
            f,
            (df / (2.0 * r)) * square.gradient,
            (df / (2.0 * r)) * square.hessian
            + ((ddf - df / r) / (4.0 * s)) * _square_of(square.gradient),
        )
    return Jet(f, square.gradient * 0.0, (ddf / 2.0) * square.hessian)


def _square_of(a: SIMD[DType.float64, 4]) -> SIMD[DType.float64, 16]:
    """Return a ⊗ a."""
    var out = SIMD[DType.float64, 16](0)
    for i in range(4):
        for j in range(4):
            out[4 * i + j] = a[i] * a[j]
    return out


def place_jets(
    grid: SpacetimeGrid, center: SpacetimeCenter, point: Int
) -> List[Jet]:
    """Return the coordinate jets of one grid point.

    Args:
        grid: The grid.
        center: The origin.
        point: The flat index of the point.

    Returns:
        The jets of c t, x, y and z at the point, in meters.
    """
    var at = grid.position(point)
    return [
        Jet.variable(
            grid_time(grid, center, Int(at[0])) * SPEED_OF_LIGHT.value, 0
        ),
        Jet.variable(grid_place(grid, center, X_AXIS, Int(at[1])), 1),
        Jet.variable(grid_place(grid, center, Y_AXIS, Int(at[2])), 2),
        Jet.variable(grid_place(grid, center, Z_AXIS, Int(at[3])), 3),
    ]


def sample_metric[
    M: AnalyticMetric
](metric: M, grid: SpacetimeGrid, center: SpacetimeCenter) raises -> Metric:
    """Return the values of a closed-form metric on a grid.

    Parameters:
        M: The type of the metric.

    Args:
        metric: The metric.
        grid: The grid.
        center: The origin.

    Returns:
        The metric, with the name the closed form gives.

    Raises:
        Error: If the grid is not Cartesian, the center is not finite, or
            a component is not finite.
    """
    require_cartesian(grid, "A closed-form metric")
    center.require_finite()
    var out = TensorField(grid, COVARIANT, COORDINATE_FRAME)
    for point in range(grid.points()):  # pragma: no branch
        var g = metric.components(place_jets(grid, center, point))
        for k in range(16):
            out.set(k // 4, k % 4, point, g[k].value)
    return Metric(out^, metric.name())


@fieldwise_init
struct _Derivatives(Movable):
    """g_ab, its first derivatives and its second derivatives at a place."""

    var g: Matrix4
    var d1: List[Float64]
    var d2: List[Float64]


def _derivatives(components: List[Jet]) -> _Derivatives:
    """Return the values and derivatives of the metric's jets, in the
    layout of the solver."""
    var g = Matrix4(0)
    var d1 = List[Float64](length=64, fill=0.0)
    var d2 = List[Float64](length=256, fill=0.0)
    for k in range(16):
        g[k] = components[k].value
        for a in range(4):
            d1[4 * k + a] = components[k].gradient[a]
            for b in range(4):
                d2[16 * k + 4 * a + b] = components[k].hessian[4 * a + b]
    return _Derivatives(g, d1^, d2^)


__async def _exact_chunk[
    M: AnalyticMetric
](
    metric: Pointer[M, ImmutAnyOrigin],
    grid: SpacetimeGrid,
    center: SpacetimeCenter,
    first_out: MutPointer[Float64, MutAnyOrigin],
    second_out: MutPointer[Float64, MutAnyOrigin],
    scalar_out: MutPointer[Float64, MutAnyOrigin],
    failed: MutPointer[Int, MutAnyOrigin],
    task: Int,
    kappa: Float64,
    first: Int,
    past: Int,
):
    """Solve the points from `first` to `past` with exact derivatives.

    With `kappa` zero, write R_ab, G_ab and R. Otherwise write T^ab to
    `first_out`. A singular point sets `failed[task]`.
    """
    var n = grid.points()
    for point in range(first, past):  # pragma: no branch
        var parts = _derivatives(
            metric[].components(place_jets(grid, center, point))
        )
        var gu: Matrix4
        try:
            gu = inverse4(parts.g)
        except:
            failed[unsafe_offset=task] = 1
            continue
        var r = ricci_tensor(gu, parts.d1, parts.d2)
        var s = (gu * r).reduce_add()
        var e = r - 0.5 * s * parts.g
        if kappa == 0.0:
            scalar_out[unsafe_offset=point] = s
            for k in range(16):
                first_out[unsafe_offset=k * n + point] = r[k]
                second_out[unsafe_offset=k * n + point] = e[k]
        else:
            var t = kappa * multiply4(multiply4(gu, e), gu)
            for k in range(16):
                first_out[unsafe_offset=k * n + point] = t[k]


def _exact_solve[
    M: AnalyticMetric
](
    metric: M,
    grid: SpacetimeGrid,
    center: SpacetimeCenter,
    mut first_out: List[Float64],
    mut second_out: List[Float64],
    mut scalar_out: List[Float64],
    kappa: Float64,
    threads: Int,
) raises:
    """Solve every point on `threads` tasks."""
    require_cartesian(grid, "A closed-form metric")
    center.require_finite()
    var n = grid.points()
    var tasks = task_count(threads, n)
    var failed = List[Int](length=tasks, fill=0)
    var group = TaskGroup()
    for task in range(tasks):  # pragma: no branch
        group.create_task(
            _exact_chunk(
                Pointer(to=metric).unsafe_origin_cast[ImmutAnyOrigin](),
                grid,
                center,
                first_out.unsafe_ptr().unsafe_origin_cast[MutAnyOrigin](),
                second_out.unsafe_ptr().unsafe_origin_cast[MutAnyOrigin](),
                scalar_out.unsafe_ptr().unsafe_origin_cast[MutAnyOrigin](),
                failed.unsafe_ptr().unsafe_origin_cast[MutAnyOrigin](),
                task,
                kappa,
                task * n // tasks,
                (task + 1) * n // tasks,
            )
        )
    group.wait()
    _ = len(first_out)
    _ = len(second_out)
    _ = len(scalar_out)
    for task in range(tasks):  # pragma: no branch
        if failed[task] != 0:
            raise Error("A metric is singular at a grid point")


def exact_curvature[
    M: AnalyticMetric
](
    metric: M,
    grid: SpacetimeGrid,
    center: SpacetimeCenter,
    threads: Int = 0,
) raises -> Curvature:
    """Return the Ricci tensor, Ricci scalar and Einstein tensor exactly.

    Parameters:
        M: The type of the metric.

    Args:
        metric: The metric.
        grid: The points to evaluate at.
        center: The origin.
        threads: The tasks to use. 0 means one for each logical core.

    Returns:
        The three curvatures at each point.

    Raises:
        Error: If the grid is not Cartesian, the center is not finite,
            `threads` is negative, or the metric is singular at a point.
    """
    var ricci = TensorField(grid, COVARIANT, COORDINATE_FRAME)
    var einstein = TensorField(grid, COVARIANT, COORDINATE_FRAME)
    var scalar = List[Float64](length=grid.points(), fill=0.0)
    _exact_solve(
        metric, grid, center, ricci.data, einstein.data, scalar, 0.0, threads
    )
    return Curvature(ricci^, scalar^, einstein^)


def exact_stress_energy[
    M: AnalyticMetric
](
    metric: M,
    grid: SpacetimeGrid,
    center: SpacetimeCenter,
    threads: Int = 0,
) raises -> StressEnergy:
    """Return the stress-energy tensor T^ab, with exact derivatives.

    Parameters:
        M: The type of the metric.

    Args:
        metric: The metric.
        grid: The points to evaluate at.
        center: The origin.
        threads: The tasks to use. 0 means one for each logical core.

    Returns:
        The contravariant tensor in the coordinate frame, in joules per
        cubic meter. Its order is `EXACT_DERIVATIVES`.

    Raises:
        Error: If the grid is not Cartesian, the center is not finite,
            `threads` is negative, or the metric is singular at a point.
    """
    var out = TensorField(grid, CONTRAVARIANT, COORDINATE_FRAME)
    var unused = List[Float64](length=16 * grid.points(), fill=0.0)
    var scalars = List[Float64](length=grid.points(), fill=0.0)
    _exact_solve(
        metric,
        grid,
        center,
        out.data,
        unused,
        scalars,
        einstein_coupling(),
        threads,
    )
    return StressEnergy(out^, metric.name(), EXACT_DERIVATIVES)


def christoffel_symbols[
    M: AnalyticMetric
](metric: M, place: SIMD[DType.float64, 4]) raises -> SIMD[DType.float64, 64]:
    """Return the Christoffel symbols of the second kind at a place.

        Γᵃ_bc = g^ad (∂_b g_dc + ∂_c g_db - ∂_d g_bc) / 2

    Parameters:
        M: The type of the metric.

    Args:
        metric: The metric.
        place: The coordinates c t, x, y and z, in meters.

    Returns:
        Γᵃ_bc at 16 a + 4 b + c, per meter.

    Raises:
        Error: If the metric is singular at the place.
    """
    var jets: List[Jet] = [
        Jet.variable(place[0], 0),
        Jet.variable(place[1], 1),
        Jet.variable(place[2], 2),
        Jet.variable(place[3], 3),
    ]
    var parts = _derivatives(metric.components(jets))
    var gu = inverse4(parts.g)
    var out = SIMD[DType.float64, 64](0)
    for a in range(4):
        for b in range(4):
            for c in range(4):
                var total = 0.0
                for d in range(4):
                    total += gu[4 * a + d] * (
                        parts.d1[4 * (4 * d + c) + b]
                        + parts.d1[4 * (4 * d + b) + c]
                        - parts.d1[4 * (4 * b + c) + d]
                    )
                out[16 * a + 4 * b + c] = 0.5 * total
    return out
