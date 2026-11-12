# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""The stress-energy tensor that a metric needs, by the Einstein equations.

`stress_energy` is WarpFactory's `getEnergyTensor`. It takes finite
differences of the metric, and from them gets the Ricci tensor, the Ricci
scalar, the Einstein tensor G_ab and then

    T^ab = c⁴ / (8 π G) g^ac G_cd g^db

in joules per cubic meter. `curvature` gives the steps before the last.

The Ricci tensor is the coordinate form in terms of the metric and its
first and second derivatives, from the introduction of the Wikipedia
article "Ricci curvature", as WarpFactory uses it. Each point is
computed alone, so the derivatives of the metric are not stored.

## Differences from WarpFactory

- The second-order solver uses the same G and c as the fourth-order one.
  WarpFactory's `einE2` uses G = 6.674e-11 and c = 2.99792e8, so its
  second-order energy densities are larger by about 2 parts in 10⁵.
- The GPU path is `extensions/warp/gpu.mojo`, through MAX. WarpFactory
  moves the arrays to a GPU with MATLAB's Parallel Computing Toolbox.
  Both paths call `solve_point`, so they take the same steps at each
  point.
"""

from std.memory import AddressSpace
from std.sys import num_logical_cores

from render.tasks import TaskGroup
from extensions.warp.derivatives import FieldPointer, Stencil, field_pointer
from extensions.warp.kinds import (
    CONTRAVARIANT,
    COORDINATE_FRAME,
    COVARIANT,
    DifferenceOrder,
    FOURTH_ORDER,
)
from extensions.warp.quantities import EnergyDensity64, einstein_coupling
from extensions.warp.tensor import (
    Matrix4,
    Metric,
    TensorField,
    checked_inverse4,
    multiply4,
)
from units.si import InverseArea64


struct Curvature(Copyable, Movable):
    """The Ricci tensor, the Ricci scalar and the Einstein tensor."""

    var ricci: TensorField
    """R_ab, covariant, per square meter."""
    var scalar: List[Float64]
    """R = g^ab R_ab at each point, per square meter."""
    var einstein: TensorField
    """G_ab = R_ab - g_ab R / 2, covariant, per square meter."""

    def __init__(
        out self,
        var ricci: TensorField,
        var scalar: List[Float64],
        var einstein: TensorField,
    ):
        """Hold the three curvatures.

        Args:
            ricci: R_ab.
            scalar: R.
            einstein: G_ab.
        """
        self.ricci = ricci^
        self.scalar = scalar^
        self.einstein = einstein^

    def scalar_at(self, point: Int) -> InverseArea64:
        """Return the Ricci scalar at one point.

        Args:
            point: The flat index of the point.

        Returns:
            R.
        """
        return InverseArea64(self.scalar[point])


struct StressEnergy(Copyable, Movable):
    """A stress-energy tensor field, with the metric it came from."""

    var tensor: TensorField
    """The components, in joules per cubic meter."""
    var name: String
    """The name of the metric."""
    var order: DifferenceOrder
    """The order of the finite differences."""

    def __init__(
        out self, var tensor: TensorField, name: String, order: DifferenceOrder
    ):
        """Hold a stress-energy tensor.

        Args:
            tensor: The components, in joules per cubic meter.
            name: The name of the metric.
            order: The order of the finite differences.
        """
        self.tensor = tensor^
        self.name = name
        self.order = order

    def component(self, a: Int, b: Int, point: Int) -> EnergyDensity64:
        """Return one component at one point.

        Args:
            a: The first index, 0 to 3.
            b: The second index, 0 to 3.
            point: The flat index of the point.

        Returns:
            The component. T^00 is the energy density.
        """
        return EnergyDensity64(self.tensor.get(a, b, point))


@always_inline
def _d1[
    space: AddressSpace
](d1: FieldPointer[space], i: Int, j: Int, k: Int) -> Float64:
    """Return ∂_k g_ij from the scratch storage."""
    return d1[unsafe_offset=(4 * i + j) * 4 + k]


@always_inline
def _d2[
    space: AddressSpace
](d2: FieldPointer[space], i: Int, j: Int, k: Int, n: Int) -> Float64:
    """Return ∂_k ∂_n g_ij from the scratch storage."""
    return d2[unsafe_offset=((4 * i + j) * 4 + k) * 4 + n]


def _metric_derivatives[
    space: AddressSpace, scratch: AddressSpace
](
    data: FieldPointer[space],
    stencil: Stencil,
    point: Int,
    n: Int,
    d1: FieldPointer[scratch],
    d2: FieldPointer[scratch],
):
    """Fill the first and second derivatives of g_ij at one point.

    Both are symmetric in i and j, and the second is symmetric in its two
    derivative axes, so each value is computed once and copied.
    """
    var at = stencil.position(point)
    for i in range(4):
        for j in range(i, 4):  # pragma: no branch
            var base = (4 * i + j) * n
            for k in range(4):
                var first = stencil.first(data, base, point, at, k)
                d1[unsafe_offset=(4 * i + j) * 4 + k] = first
                d1[unsafe_offset=(4 * j + i) * 4 + k] = first
                for m in range(k, 4):  # pragma: no branch
                    var second = stencil.second(data, base, point, at, k, m)
                    d2[unsafe_offset=((4 * i + j) * 4 + k) * 4 + m] = second
                    d2[unsafe_offset=((4 * i + j) * 4 + m) * 4 + k] = second
                    d2[unsafe_offset=((4 * j + i) * 4 + k) * 4 + m] = second
                    d2[unsafe_offset=((4 * j + i) * 4 + m) * 4 + k] = second


def ricci_tensor(gu: Matrix4, d1: List[Float64], d2: List[Float64]) -> Matrix4:
    """Return R_ij at one point from g^ab and the derivatives of g_ab.

    This is WarpFactory's `ricciT`, term for term, at one point.

    Args:
        gu: The contravariant metric g^ab.
        d1: ∂_k g_ij at (4 i + j) 4 + k.
        d2: ∂_k ∂_n g_ij at ((4 i + j) 4 + k) 4 + n.

    Returns:
        The covariant Ricci tensor, per square meter.
    """
    return ricci_tensor(gu, field_pointer(d1), field_pointer(d2))


def ricci_tensor[
    space: AddressSpace
](gu: Matrix4, d1: FieldPointer[space], d2: FieldPointer[space]) -> Matrix4:
    """Return R_ij at one point from g^ab and derivatives in any storage.

    Parameters:
        space: The address space of the derivatives.

    Args:
        gu: The contravariant metric g^ab.
        d1: ∂_k g_ij at (4 i + j) 4 + k.
        d2: ∂_k ∂_n g_ij at ((4 i + j) 4 + k) 4 + n.

    Returns:
        The covariant Ricci tensor, per square meter.
    """
    var out = Matrix4(0)
    for i in range(4):
        for j in range(i, 4):  # pragma: no branch
            var total = 0.0
            for a in range(4):
                for b in range(4):
                    var term = -(
                        _d2(d2, i, j, a, b)
                        + _d2(d2, a, b, i, j)
                        - _d2(d2, i, b, j, a)
                        - _d2(d2, j, b, i, a)
                    )
                    for r in range(4):
                        var t3 = 0.0
                        var t4 = 0.0
                        var t5 = 0.0
                        for d in range(4):
                            var up = gu[4 * r + d]
                            t3 += _d1(d1, b, d, j) * up
                            t4 += (_d1(d1, j, d, b) - _d1(d1, j, b, d)) * up
                            t5 -= (
                                2.0 * _d1(d1, b, d, a) - _d1(d1, a, b, d)
                            ) * up
                        term += t4 * _d1(d1, i, r, a) + 0.5 * (
                            t3 * _d1(d1, a, r, i)
                            + t5
                            * (
                                _d1(d1, j, r, i)
                                + _d1(d1, i, r, j)
                                - _d1(d1, j, i, r)
                            )
                        )
                    total += gu[4 * a + b] * term
            out[4 * i + j] = 0.5 * total
            out[4 * j + i] = 0.5 * total
    return out


def _sum_products(a: Matrix4, b: Matrix4) -> Float64:
    """Return Σ a_ij b_ij."""
    return (a * b).reduce_add()


def solve_point[
    space: AddressSpace, scratch: AddressSpace
](
    data: FieldPointer[space],
    stencil: Stencil,
    point: Int,
    d1: FieldPointer[scratch],
    d2: FieldPointer[scratch],
    kappa: Float64,
    mut first: Matrix4,
    mut second: Matrix4,
    mut ok: Bool,
) -> Float64:
    """Solve the Einstein equations at one point of a metric.

    The CPU tasks and the GPU kernel both call this, so they take the same
    steps.

    Parameters:
        space: The address space of the metric's storage.
        scratch: The address space of the scratch storage.

    Args:
        data: The covariant metric, g_ab of point p at (4 a + b) N + p,
            where N is the number of points.
        stencil: The stencil of the metric's grid.
        point: The flat index of the point.
        d1: Scratch storage for 64 values.
        d2: Scratch storage for 256 values.
        kappa: Zero for the curvatures, or c⁴ / (8 π G) for T^ab.
        first: Set to R_ab, or to T^ab when `kappa` is not zero.
        second: Set to G_ab when `kappa` is zero.
        ok: Set to False if the metric is singular at the point.

    Returns:
        The Ricci scalar R, or zero at a singular point.
    """
    var n = Int(stencil.counts.reduce_mul())
    var g = Matrix4(0)
    for k in range(16):
        g[k] = data[unsafe_offset=k * n + point]
    var gu = checked_inverse4(g, ok)
    if not ok:
        return 0.0
    _metric_derivatives(data, stencil, point, n, d1, d2)
    var r = ricci_tensor(gu, d1, d2)
    var s = _sum_products(gu, r)
    var e = r - 0.5 * s * g
    if kappa == 0.0:
        first = r
        second = e
    else:
        first = kappa * multiply4(multiply4(gu, e), gu)
    return s


def task_count(threads: Int, points: Int) raises -> Int:
    """Return how many tasks to split a grid's points among.

    Args:
        threads: The tasks asked for. 0 means one for each logical core.
        points: The number of points.

    Returns:
        A count from 1 to the number of points.

    Raises:
        Error: If `threads` is negative.
    """
    if threads < 0:
        raise Error("A thread count must not be negative")
    var asked = threads
    if asked == 0:
        asked = num_logical_cores()
    return max(1, min(asked, points))


__async def _solve_chunk(
    metric: Pointer[Metric, ImmutAnyOrigin],
    stencil: Stencil,
    first_out: MutPointer[Float64, MutAnyOrigin],
    second_out: MutPointer[Float64, MutAnyOrigin],
    scalar_out: MutPointer[Float64, MutAnyOrigin],
    failed: MutPointer[Int, MutAnyOrigin],
    task: Int,
    kappa: Float64,
    first: Int,
    past: Int,
):
    """Solve the points from `first` to `past`.

    With `kappa` zero, write R_ab, G_ab and R. Otherwise write T^ab to
    `first_out`. A singular point sets `failed[task]`.
    """
    var n = metric[].tensor.grid.points()
    var data = field_pointer(metric[].tensor.data)
    var d1 = List[Float64](length=64, fill=0.0)
    var d2 = List[Float64](length=256, fill=0.0)
    for point in range(first, past):  # pragma: no branch
        var ok = True
        var r = Matrix4(0)
        var e = Matrix4(0)
        var s = solve_point(
            data,
            stencil,
            point,
            field_pointer(d1),
            field_pointer(d2),
            kappa,
            r,
            e,
            ok,
        )
        if not ok:
            failed[unsafe_offset=task] = 1
            continue
        if kappa == 0.0:
            scalar_out[unsafe_offset=point] = s
            for k in range(16):
                first_out[unsafe_offset=k * n + point] = r[k]
                second_out[unsafe_offset=k * n + point] = e[k]
        else:
            for k in range(16):
                first_out[unsafe_offset=k * n + point] = r[k]


def _solve(
    metric: Metric,
    stencil: Stencil,
    mut first_out: List[Float64],
    mut second_out: List[Float64],
    mut scalar_out: List[Float64],
    kappa: Float64,
    threads: Int,
) raises:
    """Solve every point on `threads` tasks."""
    var n = metric.grid().points()
    var tasks = task_count(threads, n)
    var failed = List[Int](length=tasks, fill=0)
    var group = TaskGroup()
    for task in range(tasks):  # pragma: no branch
        group.create_task(
            _solve_chunk(
                Pointer(to=metric).unsafe_origin_cast[ImmutAnyOrigin](),
                stencil,
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


def curvature(
    metric: Metric, order: DifferenceOrder = FOURTH_ORDER, threads: Int = 0
) raises -> Curvature:
    """Return the Ricci tensor, the Ricci scalar and the Einstein tensor.

    These are WarpFactory's `ricciT`, `ricciS` and `einT`. The points are
    split among `threads` tasks. Each point is computed alone, so the
    result does not depend on the count.

    Args:
        metric: The metric.
        order: The order of the finite differences.
        threads: The tasks to use. 0 means one for each logical core.

    Returns:
        The three curvatures at each point.

    Raises:
        Error: If the order is not valid, `threads` is negative, or the
            metric is singular at a point.
    """
    var grid = metric.grid()
    var stencil = Stencil(grid, order)
    var ricci = TensorField(grid, COVARIANT, COORDINATE_FRAME)
    var einstein = TensorField(grid, COVARIANT, COORDINATE_FRAME)
    var scalar = List[Float64](length=grid.points(), fill=0.0)
    _solve(metric, stencil, ricci.data, einstein.data, scalar, 0.0, threads)
    return Curvature(ricci^, scalar^, einstein^)


def stress_energy(
    metric: Metric, order: DifferenceOrder = FOURTH_ORDER, threads: Int = 0
) raises -> StressEnergy:
    """Return the stress-energy tensor T^ab that a metric needs.

    This is WarpFactory's `getEnergyTensor` on the CPU. The tensor is
    contravariant and in the coordinate frame. The points are split among
    `threads` tasks. Each point is computed alone, so the result does not
    depend on the count.

    Args:
        metric: The metric.
        order: The order of the finite differences. The fourth order
            needs 5 points along an axis, the second order 3, for that
            axis to have derivatives.
        threads: The tasks to use. 0 means one for each logical core.

    Returns:
        The tensor, in joules per cubic meter.

    Raises:
        Error: If the order is not valid, `threads` is negative, or the
            metric is singular at a point.
    """
    var grid = metric.grid()
    var stencil = Stencil(grid, order)
    var out = TensorField(grid, CONTRAVARIANT, COORDINATE_FRAME)
    var unused = List[Float64](length=16 * grid.points(), fill=0.0)
    var scalars = List[Float64](length=grid.points(), fill=0.0)
    _solve(
        metric, stencil, out.data, unused, scalars, einstein_coupling(), threads
    )
    return StressEnergy(out^, metric.name, order)
