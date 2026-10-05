# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Bounded scalar controls for inertia, interval division and audio metadata."""

from extensions.anatomy.inertia import InertiaTally, _central_moment
from extensions.carla.curve_distance import (
    _DistanceInterval,
    _next_down,
    _next_up,
)
from extensions.humanoid.skeleton.head.aligned_speech import (
    AlignedSpeech,
    _json_time,
    aligned_phonemes,
    read_aligned_speech,
)
from math.vector3 import Vector3
from std.math import inf
from std.testing import TestSuite, assert_equal, assert_raises
from units.si import Duration, Length, Mass


def test_central_moment_rejects_nonfinite_subtraction() raises:
    assert_equal(_central_moment(3.0, 1.0), 2.0)
    assert_equal(_central_moment(1.0, 1.0), 0.0)
    with assert_raises(contains="Central second moments must be finite"):
        _ = _central_moment(1e308, -1e308)


def test_segment_length_and_underflow_mass_are_refused() raises:
    var tally = InertiaTally()
    tally.add_cell(1.0, Vector3(0, 0, 0), Vector3(1, 1, 1))
    var segment = tally.result(1)
    segment.check()
    segment.length = Length(inf[DType.float32]())
    with assert_raises(contains="length must be finite"):
        segment.check()
    segment = tally.result(1)
    segment.mass = Mass(inf[DType.float32]())
    with assert_raises(contains="finite positive mass"):
        segment.check()
    var tiny = InertiaTally()
    tiny.add_cell(1e-100, Vector3(0, 0, 0), Vector3(0, 0, 0))
    with assert_raises(contains="mass must fit positive finite SI"):
        _ = tiny.result(0)


def test_extended_interval_division_encloses_indeterminate_endpoints() raises:
    var infinity = inf[DType.float64]()
    var whole = _DistanceInterval.whole()
    var zero = _DistanceInterval.point(0.0)
    var divided = zero / _DistanceInterval(2.0, infinity)
    assert_equal(divided.low, _next_down(0.0))
    assert_equal(divided.high, _next_up(0.0))
    # Each endpoint quotient is independently the first indeterminate one.
    var numerators: List[_DistanceInterval] = [
        _DistanceInterval(infinity, infinity),
        _DistanceInterval(infinity, infinity),
        _DistanceInterval(2.0, infinity),
        _DistanceInterval(2.0, infinity),
    ]
    var denominators: List[_DistanceInterval] = [
        _DistanceInterval(infinity, infinity),
        _DistanceInterval(2.0, infinity),
        _DistanceInterval(infinity, infinity),
        _DistanceInterval(2.0, infinity),
    ]
    for i in range(4):
        var result = numerators[i] / denominators[i]
        assert_equal(result.low, whole.low)
        assert_equal(result.high, whole.high)


def test_empty_audio_alignment_is_rest_and_roundtrips() raises:
    var speech = aligned_phonemes("silence", Duration(1), [])
    for weight in speech.sample(Duration(0.5)).weights:
        assert_equal(weight, 0)
    var data = speech.metadata()
    var restored = read_aligned_speech(data)
    assert_equal(restored.metadata().to_json(), data.to_json())
    for weight in restored.sample(Duration(0.5)).weights:
        assert_equal(weight, 0)


def test_json_audio_clock_and_interval_boundaries() raises:
    assert_equal(_json_time(0).value, 0)
    assert_equal(_json_time(0.5).value, Float32(0.5))
    with assert_raises(contains="finite and nonnegative"):
        _ = _json_time(inf[DType.float64]())
    with assert_raises(contains="clock resolution"):
        _ = _json_time(1e100)
    var original = AlignedSpeech("bounds", Duration(2), [])
    for intervals in [
        (
            '[{"viseme":1,"start_seconds":0,"end_seconds":1},'
            '{"viseme":1,"start_seconds":0.5,"end_seconds":1.5}]'
        ),
        '[{"viseme":1,"start_seconds":0,"end_seconds":3}]',
    ]:
        var data = original.metadata()
        data.set_json("intervals", intervals)
        with assert_raises(contains="ordered and within duration"):
            _ = read_aligned_speech(data)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
