# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""The cloth solve on a GPU: the substeps and colors of `ClothSolver`,
one thread to a particle or to a constraint.

`GpuCloth` steps a `ClothSolver` on the device. Each substep runs three
kernels, as the CPU step runs three loops:

1. `predict_kernel` moves each free particle along its damped velocity
   and down, and each pinned particle toward its target.
2. `relax_kernel` settles the constraints of one color, one launch to a
   color. No two constraints of a color share a particle, so the threads
   of a launch never write the same particle.
3. `settle_kernel` holds each free particle to its tether and pushes it
   out of each capsule.

The kernels call the CPU solver's own arithmetic: `glide`, `predict`,
`relax_pair`, `settle` and `push_out`. So the two solves agree but for
the device's fused multiplies and adds. Each kernel reads and writes its
buffers in its own body and passes only values to those functions. No
device pointer crosses a call, which Apple's AIR linker cannot take; see
`tools/check_air_calls.mojo`.

The step reads the pins' targets, the colliders and the settings from the
`ClothSolver` each time, and writes the particles back to it. A cloak
steps on the GPU with the same calls it makes on the CPU.

This is not a three.js port. See Extensions.

    var gpu = GpuCloth(cloak.solver)
    gpu.step(cloak.solver, Duration(1.0 / 30.0, SECOND))
"""

from max.gpu import global_idx
from max.gpu.host import DeviceBuffer, DeviceContext
from max.gpu.memory import AddressSpace
from std.math import ceildiv
from std.sys import has_accelerator

from extensions.attire.cloth import (
    ClothSolver,
    glide,
    predict,
    relax_pair,
    settle,
)
from extensions.attire.springs import push_out
from math.vector3 import Vector3
from units.si import SECOND, Duration

comptime _GLOBAL = AddressSpace.GLOBAL
comptime _Floats = MutPointer[Float32, MutAnyOrigin, address_space=_GLOBAL]
comptime _Ints = MutPointer[Int32, MutAnyOrigin, address_space=_GLOBAL]

comptime BLOCK = 128
"""Threads to a block in every cloth kernel."""
comptime CAPSULE_FLOATS = 7
"""Floats to a capsule on the device: one end, the other end, the radius."""


def _device[
    dtype: DType
](buffer: DeviceBuffer[dtype]) -> MutPointer[
    Scalar[dtype], MutAnyOrigin, address_space=_GLOBAL
]:
    return (
        buffer.unsafe_ptr()
        .unsafe_mut_cast[True]()
        .unsafe_origin_cast[MutAnyOrigin]()
        .unsafe_address_space_cast[_GLOBAL]()
    )


def predict_kernel(
    points: _Floats,
    previous: _Floats,
    starts: _Floats,
    targets: _Floats,
    weights: _Floats,
    count: Int32,
    damping: Float32,
    fall_x: Float32,
    fall_y: Float32,
    fall_z: Float32,
    share: Float32,
):
    """Move each particle before the constraints, as the CPU step does.

    Args:
        points: Three floats a particle: where it is.
        previous: Where it was a substep ago.
        starts: Where it was at the start of the step.
        targets: Where each pinned particle is to be at the end of it.
        weights: Each particle's inverse mass.
        count: The particles.
        damping: The share of velocity lost each substep.
        fall_x: Gravity times the substep's length squared, along x.
        fall_y: Along y.
        fall_z: Along z.
        share: How far through the step this substep ends.
    """
    var k = Int(global_idx.x)
    if k >= Int(count):
        return
    var at = 3 * k
    var now = Vector3(
        points[unsafe_offset=at],
        points[unsafe_offset=at + 1],
        points[unsafe_offset=at + 2],
    )
    var next: Vector3
    if weights[unsafe_offset=k] == 0:
        var start = Vector3(
            starts[unsafe_offset=at],
            starts[unsafe_offset=at + 1],
            starts[unsafe_offset=at + 2],
        )
        var target = Vector3(
            targets[unsafe_offset=at],
            targets[unsafe_offset=at + 1],
            targets[unsafe_offset=at + 2],
        )
        next = glide(start, target, share)
    else:
        var before = Vector3(
            previous[unsafe_offset=at],
            previous[unsafe_offset=at + 1],
            previous[unsafe_offset=at + 2],
        )
        next = predict(now, before, damping, Vector3(fall_x, fall_y, fall_z))
    previous[unsafe_offset=at] = now.x
    previous[unsafe_offset=at + 1] = now.y
    previous[unsafe_offset=at + 2] = now.z
    points[unsafe_offset=at] = next.x
    points[unsafe_offset=at + 1] = next.y
    points[unsafe_offset=at + 2] = next.z


def relax_kernel(
    points: _Floats,
    weights: _Floats,
    pairs: _Ints,
    rests: _Floats,
    bending: _Ints,
    order: _Ints,
    first: Int32,
    size: Int32,
    stretch: Float32,
    bend: Float32,
    scale: Float32,
):
    """Settle the constraints of one color, one thread to a constraint.

    Args:
        points: Three floats a particle.
        weights: Each particle's inverse mass.
        pairs: Two particles a constraint.
        rests: Each constraint's rest distance.
        bending: One for a bending constraint, zero for a stretching one.
        order: The constraints, color by color.
        first: Where this color starts in `order`.
        size: How many constraints this color has.
        stretch: The stretching compliance.
        bend: The bending compliance.
        scale: One over the substep's length squared.
    """
    var t = Int(global_idx.x)
    if t >= Int(size):
        return
    var c = Int(order[unsafe_offset=Int(first) + t])
    var i = Int(pairs[unsafe_offset=2 * c])
    var j = Int(pairs[unsafe_offset=2 * c + 1])
    var a = Vector3(
        points[unsafe_offset=3 * i],
        points[unsafe_offset=3 * i + 1],
        points[unsafe_offset=3 * i + 2],
    )
    var b = Vector3(
        points[unsafe_offset=3 * j],
        points[unsafe_offset=3 * j + 1],
        points[unsafe_offset=3 * j + 2],
    )
    var compliance = stretch
    if bending[unsafe_offset=c] != 0:
        compliance = bend
    var moved = relax_pair(
        a,
        b,
        weights[unsafe_offset=i],
        weights[unsafe_offset=j],
        rests[unsafe_offset=c],
        compliance,
        scale,
    )
    points[unsafe_offset=3 * i] = moved[0].x
    points[unsafe_offset=3 * i + 1] = moved[0].y
    points[unsafe_offset=3 * i + 2] = moved[0].z
    points[unsafe_offset=3 * j] = moved[1].x
    points[unsafe_offset=3 * j + 1] = moved[1].y
    points[unsafe_offset=3 * j + 2] = moved[1].z


def settle_kernel(
    points: _Floats,
    tethers: _Ints,
    reaches: _Floats,
    capsules: _Floats,
    colliders: Int32,
    thickness: Float32,
    count: Int32,
):
    """Hold each free particle to its tether and out of each capsule.

    A pinned particle has no tether and does not move here, so a thread
    reads its pin while no other thread writes it.

    Args:
        points: Three floats a particle.
        tethers: Each particle's pin, or -1 for a pinned particle.
        reaches: How far each particle may stand from its pin.
        capsules: `CAPSULE_FLOATS` a capsule: one end, the other, the
            radius.
        colliders: How many capsules.
        thickness: The cloth's thickness, added to each radius.
        count: The particles.
    """
    var k = Int(global_idx.x)
    if k >= Int(count):
        return
    var pin = Int(tethers[unsafe_offset=k])
    if pin < 0:
        return
    var p = Vector3(
        points[unsafe_offset=3 * k],
        points[unsafe_offset=3 * k + 1],
        points[unsafe_offset=3 * k + 2],
    )
    var anchor = Vector3(
        points[unsafe_offset=3 * pin],
        points[unsafe_offset=3 * pin + 1],
        points[unsafe_offset=3 * pin + 2],
    )
    p = settle(p, anchor, reaches[unsafe_offset=k])
    for c in range(Int(colliders)):
        var at = CAPSULE_FLOATS * c
        var start = Vector3(
            capsules[unsafe_offset=at],
            capsules[unsafe_offset=at + 1],
            capsules[unsafe_offset=at + 2],
        )
        var end = Vector3(
            capsules[unsafe_offset=at + 3],
            capsules[unsafe_offset=at + 4],
            capsules[unsafe_offset=at + 5],
        )
        p = push_out(p, start, end, capsules[unsafe_offset=at + 6] + thickness)
    points[unsafe_offset=3 * k] = p.x
    points[unsafe_offset=3 * k + 1] = p.y
    points[unsafe_offset=3 * k + 2] = p.z


def _flat(points: List[Vector3]) -> List[Float32]:
    """Return three floats a point."""
    var flat = List[Float32](capacity=3 * len(points))
    for p in points:
        flat.append(p.x)
        flat.append(p.y)
        flat.append(p.z)
    return flat^


def _upload[
    dtype: DType
](context: DeviceContext, values: List[Scalar[dtype]]) raises -> DeviceBuffer[
    dtype
]:
    """Copy a list to a new device buffer and wait for the copy, so the list
    outlives it. An empty list takes one element."""
    var buffer = context.enqueue_create_buffer[dtype](max(len(values), 1))
    if len(values) > 0:
        context.enqueue_copy(buffer, values.unsafe_ptr())
        context.synchronize()
    _ = len(values)
    return buffer^


def _refill(
    context: DeviceContext,
    buffer: DeviceBuffer[DType.float32],
    values: List[Float32],
) raises:
    """Copy a list into a device buffer and wait for the copy."""
    if len(values) > 0:
        context.enqueue_copy(buffer, values.unsafe_ptr())
        context.synchronize()
    _ = len(values)


def _drain(context: DeviceContext):
    # Wait for queued work after a failure. A queue that cannot be waited
    # on has failed already, and the original error is the one to report.
    try:
        context.synchronize()
    except:
        pass


struct GpuCloth(Movable):
    """A cloth's constraints on a GPU, ready to step its `ClothSolver`."""

    var context: DeviceContext
    """The device the cloth steps on."""
    var count: Int
    """The particles of the cloth it was made from."""
    var constraints: Int
    """The constraints of that cloth."""
    var runs: List[Int]
    """Where each color starts in the constraint order, and the end."""
    var _weights: DeviceBuffer[DType.float32]
    var _pairs: DeviceBuffer[DType.int32]
    var _rests: DeviceBuffer[DType.float32]
    var _bending: DeviceBuffer[DType.int32]
    var _order: DeviceBuffer[DType.int32]
    var _tethers: DeviceBuffer[DType.int32]
    var _reaches: DeviceBuffer[DType.float32]
    var _points: DeviceBuffer[DType.float32]
    var _previous: DeviceBuffer[DType.float32]
    var _starts: DeviceBuffer[DType.float32]
    var _targets: DeviceBuffer[DType.float32]

    def __init__(out self, cloth: ClothSolver) raises:
        """Copy a cloth's constraints, weights and tethers to the GPU.

        Args:
            cloth: The cloth to step.

        Raises:
            Error: If there is no GPU, or a copy fails.
        """
        if not has_accelerator():
            raise Error("GpuCloth needs a GPU")
        var context = DeviceContext()
        self.count = cloth.count()
        self.constraints = len(cloth.rests)
        self.runs = [0]
        var order = List[Int32]()
        for color in cloth.colors:
            for c in color:
                order.append(Int32(c))
            self.runs.append(len(order))
        var pairs = List[Int32](capacity=len(cloth.pairs))
        for p in cloth.pairs:
            pairs.append(Int32(p))
        var bending = List[Int32](capacity=len(cloth.bending))
        for flag in cloth.bending:
            bending.append(Int32(1) if flag else Int32(0))
        var tethers = List[Int32](capacity=len(cloth.tethers))
        for t in cloth.tethers:
            tethers.append(Int32(t))
        try:
            self._weights = _upload[DType.float32](context, cloth.weights)
            self._pairs = _upload[DType.int32](context, pairs)
            self._rests = _upload[DType.float32](context, cloth.rests)
            self._bending = _upload[DType.int32](context, bending)
            self._order = _upload[DType.int32](context, order)
            self._tethers = _upload[DType.int32](context, tethers)
            self._reaches = _upload[DType.float32](context, cloth.reaches)
            var floats = max(3 * self.count, 1)
            self._points = context.enqueue_create_buffer[DType.float32](floats)
            self._previous = context.enqueue_create_buffer[DType.float32](
                floats
            )
            self._starts = context.enqueue_create_buffer[DType.float32](floats)
            self._targets = context.enqueue_create_buffer[DType.float32](floats)
        except error:
            _drain(context)
            raise error^
        self.context = context^

    def step(self, mut cloth: ClothSolver, time: Duration) raises:
        """Move a cloth one frame on the GPU, as `ClothSolver.step` does.

        Args:
            cloth: The cloth this was made from. Its pins' targets, its
                colliders and its settings are read, and its particles are
                written back.
            time: The frame's length, above zero.

        Raises:
            Error: If the settings do not check, the time is not above
                zero, the cloth is another one, or the device fails.
        """
        cloth.settings.check()
        var dt = Float32(time.to(SECOND))
        if not (dt > 0 and dt < 1e6):
            raise Error("A cloth's step must be above zero")
        if cloth.count() != self.count or len(cloth.rests) != self.constraints:
            raise Error("A GPU cloth steps only the cloth it was made from")
        if self.count == 0:
            return
        var substeps = cloth.settings.substeps
        var h = dt / Float32(substeps)
        var scale = 1 / (h * h)
        var fall = cloth.settings.gravity * (h * h)
        var capsules = List[Float32]()
        for c in range(len(cloth.radii)):
            capsules.append(cloth.starts[c].x)
            capsules.append(cloth.starts[c].y)
            capsules.append(cloth.starts[c].z)
            capsules.append(cloth.ends[c].x)
            capsules.append(cloth.ends[c].y)
            capsules.append(cloth.ends[c].z)
            capsules.append(cloth.radii[c])
        var points = _flat(cloth.points)
        var previous = _flat(cloth.previous)
        var blocks = ceildiv(self.count, BLOCK)
        try:
            var capsule_buffer = _upload[DType.float32](self.context, capsules)
            _refill(self.context, self._points, points)
            _refill(self.context, self._starts, points)
            _refill(self.context, self._previous, previous)
            _refill(self.context, self._targets, _flat(cloth.targets))
            for s in range(substeps):
                var share = Float32(s + 1) / Float32(substeps)
                self.context.enqueue_function[predict_kernel](
                    _device(self._points),
                    _device(self._previous),
                    _device(self._starts),
                    _device(self._targets),
                    _device(self._weights),
                    Int32(self.count),
                    cloth.settings.damping,
                    fall.x,
                    fall.y,
                    fall.z,
                    share,
                    grid_dim=blocks,
                    block_dim=BLOCK,
                )
                for color in range(len(self.runs) - 1):
                    var size = self.runs[color + 1] - self.runs[color]
                    self.context.enqueue_function[relax_kernel](
                        _device(self._points),
                        _device(self._weights),
                        _device(self._pairs),
                        _device(self._rests),
                        _device(self._bending),
                        _device(self._order),
                        Int32(self.runs[color]),
                        Int32(size),
                        cloth.settings.stretch,
                        cloth.settings.bend,
                        scale,
                        grid_dim=ceildiv(size, BLOCK),
                        block_dim=BLOCK,
                    )
                self.context.enqueue_function[settle_kernel](
                    _device(self._points),
                    _device(self._tethers),
                    _device(self._reaches),
                    _device(capsule_buffer),
                    Int32(len(cloth.radii)),
                    cloth.settings.thickness,
                    Int32(self.count),
                    grid_dim=blocks,
                    block_dim=BLOCK,
                )
            self.context.enqueue_copy(points.unsafe_ptr(), self._points)
            self.context.enqueue_copy(previous.unsafe_ptr(), self._previous)
            self.context.synchronize()
        except error:
            _drain(self.context)
            raise error^
        for k in range(self.count):
            cloth.points[k] = Vector3(
                points[3 * k], points[3 * k + 1], points[3 * k + 2]
            )
            cloth.previous[k] = Vector3(
                previous[3 * k], previous[3 * k + 1], previous[3 * k + 2]
            )
