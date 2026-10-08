# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Timing refusal precedes mutations of a CARLA world."""

from extensions.carla.opendrive import load_opendrive
from extensions.carla.world import EpisodeSettings, World
from std.math import inf, nan
from std.memory import bitcast
from std.testing import TestSuite, assert_equal, assert_raises, assert_false
from units.si import Duration


def test_settings_finite_domain_and_legacy_disable_sentinel() raises:
    for step in [Float32(0), Float32(-1)]:
        var settings = EpisodeSettings(True, False, Duration(step))
        assert_false(Bool(settings.fixed_delta_seconds))
    for bad in [
        nan[DType.float32](),
        inf[DType.float32](),
        -inf[DType.float32](),
    ]:
        with assert_raises(contains="finite"):
            _ = EpisodeSettings(True, False, Duration(bad))
        var settings = EpisodeSettings()
        settings.fixed_delta_seconds = Duration(bad)
        with assert_raises(contains="fixed_delta_seconds"):
            settings.check()
        settings.fixed_delta_seconds = Duration(0.05)
        settings.max_substep_delta_time = Duration(bad)
        with assert_raises(contains="max_substep_delta_time"):
            settings.check()


def test_substep_count_clamps_before_integer_conversion() raises:
    var settings = EpisodeSettings()
    settings.max_substep_delta_time = Duration(
        bitcast[DType.float32](UInt32(1))
    )
    settings.max_substeps = 16
    assert_equal(settings.substep_count(Duration(1e30)), 16)
    settings = EpisodeSettings()
    assert_equal(settings.substep_count(Duration(0.05)), 5)
    assert_equal(settings.substep_count(Duration(0.035)), 4)
    settings.substepping = False
    assert_equal(settings.substep_count(Duration(0.25)), 1)
    for bad in [
        Float32(0),
        Float32(-1),
        nan[DType.float32](),
        inf[DType.float32](),
    ]:
        with assert_raises(contains="duration"):
            _ = settings.substep_count(Duration(bad))


def test_invalid_settings_do_not_change_world_clocks() raises:
    var world = World(load_opendrive("<OpenDRIVE/>"))
    for bad in [
        Float32(-1),
        Float32(0),
        nan[DType.float32](),
        inf[DType.float32](),
    ]:
        var candidate = EpisodeSettings()
        candidate.fixed_delta_seconds = Duration(bad)
        with assert_raises(contains="fixed_delta_seconds"):
            _ = world.apply_settings(candidate)
        assert_false(Bool(world.settings.fixed_delta_seconds))
        # Public mutation cannot bypass tick's preflight.
        world.settings.fixed_delta_seconds = Duration(bad)
        with assert_raises(contains="fixed_delta_seconds"):
            _ = world.tick()
        assert_equal(world.frame, 0)
        assert_equal(world.elapsed_seconds, Float64(0))
        assert_equal(world.delta_seconds, Float64(0))
        assert_equal(world.snapshot.frame(), 0)
        world.settings.fixed_delta_seconds = None


def test_unrepresentable_clock_advance_precedes_mutation() raises:
    var world = World(load_opendrive("<OpenDRIVE/>"))
    _ = world.apply_settings(EpisodeSettings(True, False, Duration(0.05)))
    world.elapsed_seconds = 1e300
    with assert_raises(contains="cannot advance"):
        _ = world.tick()
    assert_equal(world.elapsed_seconds, Float64(1e300))
    assert_equal(world.frame, 0)
    assert_equal(world.delta_seconds, Float64(0))
    assert_equal(world.snapshot.frame(), 0)
    for bad in [Float64(-1), nan[DType.float64](), inf[DType.float64]()]:
        world.elapsed_seconds = bad
        with assert_raises(contains="elapsed time must be finite"):
            _ = world.tick()
        assert_equal(
            bitcast[DType.uint64](world.elapsed_seconds),
            bitcast[DType.uint64](bad),
        )
        assert_equal(world.frame, 0)
    world.elapsed_seconds = 0
    world.frame = -1
    with assert_raises(contains="frame cannot advance"):
        _ = world.tick()
    assert_equal(world.frame, -1)
    assert_equal(world.elapsed_seconds, Float64(0))
    world.frame = 9223372036854775807
    with assert_raises(contains="frame cannot advance"):
        _ = world.tick()
    assert_equal(world.frame, 9223372036854775807)
    assert_equal(world.elapsed_seconds, Float64(0))
    world.frame = 0
    assert_equal(world.tick(), 1)
    assert_equal(world.snapshot.timestamp.delta().value, Float64(Float32(0.05)))


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
