# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""The GPU cloth agrees with the CPU cloth.

Both solves run the same arithmetic in the same order: `glide`,
`predict`, `relax_pair`, `settle` and `push_out`. The device fuses
multiplies and adds where the host does not, so a particle can differ in
its last bits, and a difference can grow as the sheet folds over a
capsule. The parity test drops a sheet across a capsule for twenty frames
and allows each particle two millimeters. The bound has not yet been
measured on a GPU; the suite was written where none was present.
"""

from extensions.attire.cloth import ClothSettings, ClothSolver, cloth_grid
from extensions.attire.cloth_gpu import GpuCloth
from math.vector3 import Vector3
from std.sys import has_accelerator
from std.testing import TestSuite, assert_raises, assert_true
from units.si import SECOND, Duration

comptime SIDE = 21
"""Particles along each side of the sheet."""
comptime FRAMES = 20
"""Frames each solve steps."""
comptime TOLERANCE = Float32(0.002)
"""How far a GPU particle may stand from its CPU twin, in meters."""


def _skipped(name: String) -> Bool:
    # An early return looks like a pass, so a skip says so.
    if has_accelerator():
        return False
    print("SKIP (no GPU):", name)
    return True


def _sheet() raises -> ClothSolver:
    """Return a level sheet pinned along one edge, over a capsule."""
    var grid = cloth_grid(
        Vector3(-0.5, 0, 0),
        Vector3(0.05, 0, 0),
        Vector3(0, 0, 0.05),
        SIDE,
        SIDE,
    )
    var pinned = List[Bool](length=SIDE * SIDE, fill=False)
    for c in range(SIDE):
        pinned[c] = True
    var sheet = ClothSolver(
        grid[0].copy(), pinned, grid[1].copy(), grid[2].copy(), ClothSettings()
    )
    sheet.set_colliders(
        [Vector3(-1, -0.25, 0.45)], [Vector3(1, -0.25, 0.45)], [Float32(0.1)]
    )
    return sheet^


def _frame() -> Duration:
    """Return one thirtieth of a second."""
    return Duration(1.0 / 30.0, SECOND)


def test_the_gpu_cloth_follows_the_cpu_cloth() raises:
    if _skipped("test_the_gpu_cloth_follows_the_cpu_cloth"):
        return
    var host = _sheet()
    var device = _sheet()
    var gpu = GpuCloth(device)
    for _ in range(FRAMES):
        host.step(_frame())
        gpu.step(device, _frame())
    var farthest = Float32(0)
    var lowest = Float32(0)
    for k in range(host.count()):
        farthest = max(farthest, (host.points[k] - device.points[k]).length())
        lowest = min(lowest, device.points[k].y)
    print("largest CPU and GPU difference, m:", farthest)
    assert_true(farthest <= TOLERANCE)
    # The sheet fell: its free edge swung down past the capsule.
    assert_true(lowest < -0.3)
    # Pinned particles stay on their targets.
    for c in range(SIDE):
        assert_true((device.points[c] - host.points[c]).length() < 1e-6)


def test_a_gpu_cloth_steps_only_its_own_cloth() raises:
    if _skipped("test_a_gpu_cloth_steps_only_its_own_cloth"):
        return
    var sheet = _sheet()
    var gpu = GpuCloth(sheet)
    var small = cloth_grid(
        Vector3(0, 0, 0), Vector3(0.1, 0, 0), Vector3(0, -0.1, 0), 3, 3
    )
    var other = ClothSolver(
        small[0].copy(),
        List[Bool](length=9, fill=False),
        small[1].copy(),
        small[2].copy(),
        ClothSettings(),
    )
    with assert_raises(contains="made from"):
        gpu.step(other, _frame())
    with assert_raises(contains="above zero"):
        gpu.step(sheet, Duration(0, SECOND))
    sheet.settings.substeps = 0
    with assert_raises(contains="substeps"):
        gpu.step(sheet, _frame())


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
