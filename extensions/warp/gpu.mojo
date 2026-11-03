# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""The warp solver on a GPU, through MAX.

WarpFactory moves its arrays to a GPU with MATLAB's Parallel Computing
Toolbox. Here one thread solves one point. Each point is computed alone, so
the threads share nothing. The kernel calls `solve_point` of
`extensions/warp/solver.mojo`, the function the CPU tasks call, so the two
take the same finite differences and the same Ricci tensor. A GPU compiler
may fuse a multiply and an add that the CPU rounds twice, so the results
agree to rounding, not bit for bit. `tests/test_warp_solver_gpu.mojo` checks
them against each other.

The solver works in 64-bit floats, as WarpFactory does. A Metal GPU has no
64-bit floats, so on Apple silicon `gpu_stress_energy` and `gpu_curvature`
refuse to run, and `warp_gpu_available` is False.
"""

from max.gpu import global_idx
from max.gpu.host import DeviceBuffer, DeviceContext
from std.math import ceildiv
from std.memory import AddressSpace, stack_allocation
from std.sys import default_accelerator, has_accelerator

from extensions.warp.derivatives import FieldPointer, Stencil
from extensions.warp.kinds import (
    CONTRAVARIANT,
    COORDINATE_FRAME,
    COVARIANT,
    DifferenceOrder,
    FOURTH_ORDER,
)
from extensions.warp.quantities import einstein_coupling
from extensions.warp.solver import Curvature, StressEnergy, solve_point
from extensions.warp.tensor import Matrix4, Metric, TensorField

comptime _GLOBAL = AddressSpace.GLOBAL
comptime _Floats = FieldPointer[_GLOBAL]
comptime _Flags = MutPointer[Int32, MutAnyOrigin, address_space=_GLOBAL]

comptime _BLOCK = 64
"""Threads in a block. A thread keeps 320 doubles of scratch, so blocks are
small."""


def warp_gpu_available() -> Bool:
    """Return True if this machine has a GPU that can run the warp solver.

    Returns:
        Whether there is a GPU with 64-bit floats: one that is not Apple's.
    """
    comptime if default_accelerator().is_apple_gpu():
        return False
    else:
        return has_accelerator()


def warp_solve_kernel(
    metric: _Floats,
    counts: SIMD[DType.int64, 4],
    strides: SIMD[DType.int64, 4],
    steps: SIMD[DType.float64, 4],
    wraps: SIMD[DType.int64, 4],
    reach: Int32,
    first_out: _Floats,
    second_out: _Floats,
    scalar_out: _Floats,
    failed: _Flags,
    kappa: Float64,
    points: Int32,
):
    """Solve one point of a metric, as one CPU task solves each of its points.

    Args:
        metric: g_ab of point p at (4 a + b) N + p.
        counts: The stencil's counts.
        strides: The stencil's strides.
        steps: The stencil's steps.
        wraps: The stencil's wrapping axes.
        reach: The stencil's reach.
        first_out: R_ab, or T^ab when `kappa` is not zero, in the same order.
        second_out: G_ab when `kappa` is zero.
        scalar_out: R when `kappa` is zero.
        failed: Set to 1 at a point where the metric is singular.
        kappa: Zero for the curvatures, or c⁴ / (8 π G) for T^ab.
        points: N, the number of points.
    """
    var point = Int(global_idx.x)
    var n = Int(points)
    if point >= n:
        return
    var stencil = Stencil(
        counts=counts,
        strides=strides,
        steps=steps,
        wraps=wraps,
        reach=Int(reach),
    )
    var d1 = stack_allocation[64, Float64]().unsafe_origin_cast[MutAnyOrigin]()
    var d2 = stack_allocation[256, Float64]().unsafe_origin_cast[MutAnyOrigin]()
    var ok = True
    var r = Matrix4(0)
    var e = Matrix4(0)
    var s = solve_point(metric, stencil, point, d1, d2, kappa, r, e, ok)
    if not ok:
        failed[unsafe_offset=point] = 1
        return
    failed[unsafe_offset=point] = 0
    for k in range(16):
        first_out[unsafe_offset=k * n + point] = r[k]
    if kappa == 0.0:
        scalar_out[unsafe_offset=point] = s
        for k in range(16):
            second_out[unsafe_offset=k * n + point] = e[k]


def _device(buffer: DeviceBuffer[DType.float64]) -> _Floats:
    """Return a buffer's device pointer as the kernel takes it."""
    return (
        buffer.unsafe_ptr()
        .unsafe_mut_cast[True]()
        .unsafe_origin_cast[MutAnyOrigin]()
        .unsafe_address_space_cast[_GLOBAL]()
    )


def _device_flags(buffer: DeviceBuffer[DType.int32]) -> _Flags:
    """Return a flag buffer's device pointer as the kernel takes it."""
    return (
        buffer.unsafe_ptr()
        .unsafe_mut_cast[True]()
        .unsafe_origin_cast[MutAnyOrigin]()
        .unsafe_address_space_cast[_GLOBAL]()
    )


def _gpu_solve(
    metric: Metric,
    order: DifferenceOrder,
    kappa: Float64,
    mut first: List[Float64],
    mut second: List[Float64],
    mut scalar: List[Float64],
) raises:
    """Solve every point on the GPU, and copy the results back."""
    comptime if default_accelerator().is_apple_gpu():
        raise Error(
            "The warp solver needs 64-bit floats, which a Metal GPU does not"
            " have"
        )
    else:
        if not has_accelerator():
            raise Error("The warp solver on the GPU needs a GPU")
        var grid = metric.grid()
        var stencil = Stencil(grid, order)
        var n = grid.points()
        var context = DeviceContext()
        var source = context.enqueue_create_buffer[DType.float64](16 * n)
        context.enqueue_copy(source, metric.tensor.data.unsafe_ptr())
        var first_buffer = context.enqueue_create_buffer[DType.float64](16 * n)
        var second_buffer = context.enqueue_create_buffer[DType.float64](16 * n)
        var scalar_buffer = context.enqueue_create_buffer[DType.float64](n)
        var failed = context.enqueue_create_buffer[DType.int32](n)
        context.enqueue_function[warp_solve_kernel](
            _device(source),
            stencil.counts,
            stencil.strides,
            stencil.steps,
            stencil.wraps,
            Int32(stencil.reach),
            _device(first_buffer),
            _device(second_buffer),
            _device(scalar_buffer),
            _device_flags(failed),
            kappa,
            Int32(n),
            grid_dim=ceildiv(n, _BLOCK),
            block_dim=_BLOCK,
        )
        var flags = List[Int32](length=n, fill=0)
        context.enqueue_copy(first.unsafe_ptr(), first_buffer)
        context.enqueue_copy(flags.unsafe_ptr(), failed)
        if kappa == 0.0:
            context.enqueue_copy(second.unsafe_ptr(), second_buffer)
            context.enqueue_copy(scalar.unsafe_ptr(), scalar_buffer)
        context.synchronize()
        # Release the buffers before the context, as render/gpu.mojo does.
        _ = source^
        _ = first_buffer^
        _ = second_buffer^
        _ = scalar_buffer^
        _ = failed^
        _ = context^
        for point in range(n):
            if flags[point] != 0:
                raise Error("A metric is singular at a grid point")


def gpu_curvature(
    metric: Metric, order: DifferenceOrder = FOURTH_ORDER
) raises -> Curvature:
    """Return the Ricci tensor, the Ricci scalar and the Einstein tensor.

    This is `curvature` of `extensions/warp/solver.mojo`, on the GPU.

    Args:
        metric: The metric.
        order: The order of the finite differences.

    Returns:
        The three curvatures at each point.

    Raises:
        Error: If there is no GPU, the GPU is Apple's, the order is not
            valid, or the metric is singular at a point.
    """
    var grid = metric.grid()
    var ricci = TensorField(grid, COVARIANT, COORDINATE_FRAME)
    var einstein = TensorField(grid, COVARIANT, COORDINATE_FRAME)
    var scalar = List[Float64](length=grid.points(), fill=0.0)
    _gpu_solve(metric, order, 0.0, ricci.data, einstein.data, scalar)
    return Curvature(ricci^, scalar^, einstein^)


def gpu_stress_energy(
    metric: Metric, order: DifferenceOrder = FOURTH_ORDER
) raises -> StressEnergy:
    """Return the stress-energy tensor T^ab that a metric needs, on the GPU.

    This is `stress_energy` of `extensions/warp/solver.mojo`, and
    WarpFactory's `getEnergyTensor` with its GPU option.

    Args:
        metric: The metric.
        order: The order of the finite differences.

    Returns:
        The contravariant tensor in the coordinate frame, in joules per
        cubic meter.

    Raises:
        Error: If there is no GPU, the GPU is Apple's, the order is not
            valid, or the metric is singular at a point.
    """
    var grid = metric.grid()
    var out = TensorField(grid, CONTRAVARIANT, COORDINATE_FRAME)
    var unused = List[Float64](length=16 * grid.points(), fill=0.0)
    var scalars = List[Float64](length=grid.points(), fill=0.0)
    _gpu_solve(metric, order, einstein_coupling(), out.data, unused, scalars)
    return StressEnergy(out^, metric.name, order)
