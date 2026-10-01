# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Probe storage and device-index boundary regressions for issue #359."""

from core.scene import Scene
from lights.light_probe_grid import (
    LightProbeGrid,
    MAX_GRID_AXIS,
    _default_probes,
    _probe_count,
)
from lights.lighting import Lighting
from math.spherical_harmonics3 import SphericalHarmonics3
from math.vector3 import Vector3
from std.math import inf, nan
from std.testing import TestSuite, assert_equal, assert_raises
from units.si import Length, METER


def test_a_short_or_long_probe_array_is_rejected_before_lighting() raises:
    var grid = LightProbeGrid()
    _ = grid.probes.pop()
    with assert_raises(contains="one stored probe"):
        grid.validate()
    with assert_raises(contains="one stored probe"):
        _ = Lighting(Scene(), probe_grid=grid)
    grid.probes.append(SphericalHarmonics3())
    grid.probes.append(SphericalHarmonics3())
    with assert_raises(contains="one stored probe"):
        grid.validate()
    with assert_raises(contains="one stored probe"):
        _ = Lighting(Scene(), probe_grid=grid)


def test_changed_resolution_must_match_the_stored_probe_count() raises:
    var grid = LightProbeGrid()
    grid.resolution_x = 3
    with assert_raises(contains="one stored probe"):
        grid.validate()
    grid.resolution_x = 2
    grid.validate()
    assert_equal(grid.count(), len(grid.probes))
    var taps = grid.taps(grid.high(), Vector3(0, 0, 0))
    for corner in range(8):
        assert_equal(taps.probes[corner], Int32(7))


def test_auto_probe_counts_reject_nonfinite_dimensions_before_conversion() raises:
    var bad: List[Float32] = [
        nan[DType.float32](),
        inf[DType.float32](),
        -inf[DType.float32](),
        0,
        -1,
    ]
    for at in range(len(bad)):
        with assert_raises(contains="positive lengths"):
            _ = LightProbeGrid(width=Length(bad[at], METER))
        with assert_raises(contains="positive lengths"):
            _ = LightProbeGrid(height=Length(bad[at], METER))
        with assert_raises(contains="positive lengths"):
            _ = LightProbeGrid(depth=Length(bad[at], METER))
    with assert_raises(contains="device count"):
        _ = LightProbeGrid(width=Length(1e30, METER))


def test_large_probe_counts_fail_before_allocation_or_multiplication() raises:
    with assert_raises(contains="device count"):
        _ = LightProbeGrid(width_probes=MAX_GRID_AXIS + 1)
    with assert_raises(contains="device count"):
        _ = LightProbeGrid(height_probes=MAX_GRID_AXIS + 1)
    with assert_raises(contains="device count"):
        _ = LightProbeGrid(depth_probes=MAX_GRID_AXIS + 1)
    with assert_raises(contains="too many probes"):
        _ = LightProbeGrid(
            width_probes=65536, height_probes=65536, depth_probes=1
        )
    with assert_raises(contains="too many probes"):
        _ = LightProbeGrid(
            width_probes=65536, height_probes=1, depth_probes=65536
        )


def test_empty_sentinel_and_valid_interpolation_keep_their_behavior() raises:
    var empty = LightProbeGrid.none()
    var lighting = Lighting(Scene(), probe_grid=empty)
    assert_equal(len(lighting.grid.flatten()), 0)
    var grid = LightProbeGrid(width_probes=2, height_probes=1, depth_probes=1)
    grid.probes[0].lanes[0] = 2
    grid.probes[1].lanes[0] = 6
    grid.validate()
    var sh = grid.sh_at(Vector3(0, 0, 0), Vector3(0, 0, 0))
    assert_equal(sh.lanes[0], Float32(4))
    _ = Lighting(Scene(), probe_grid=grid)


def test_exact_count_boundaries_are_accepted_without_allocating() raises:
    assert_equal(_probe_count(MAX_GRID_AXIS, 1, 1), MAX_GRID_AXIS)
    assert_equal(_probe_count(1, MAX_GRID_AXIS, 1), MAX_GRID_AXIS)
    assert_equal(_probe_count(1, 1, MAX_GRID_AXIS), MAX_GRID_AXIS)
    assert_equal(
        _default_probes(Length(Float32(MAX_GRID_AXIS - 1), METER)),
        MAX_GRID_AXIS,
    )


def test_intensity_overflow_is_rejected_before_lighting_adopts_the_grid() raises:
    var grid = LightProbeGrid(width_probes=1, height_probes=1, depth_probes=1)
    grid.probes[0].lanes[0] = 1e30
    grid.intensity = 1e30
    with assert_raises(contains="scaled coefficients"):
        grid.validate()
    with assert_raises(contains="scaled coefficients"):
        _ = Lighting(Scene(), probe_grid=grid)
    # Large but representable products remain valid.
    grid.intensity = 1e-10
    grid.validate()
    _ = Lighting(Scene(), probe_grid=grid)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
