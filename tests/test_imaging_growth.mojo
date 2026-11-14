# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Tumor doubling times, growth rates, longest diameters and RECIST 1.1."""

from extensions.imaging.growth import (
    DAY64,
    PER_DAY64,
    doubling_time,
    growth_rate,
    longest_diameter,
    recist_response,
    response_name,
)
from extensions.imaging.ids import (
    BACKGROUND,
    COMPLETE_RESPONSE,
    LabelId,
    PARTIAL_RESPONSE,
    PROGRESSIVE_DISEASE,
    ResponseCategory,
    STABLE_DISEASE,
    require_response,
)
from extensions.imaging.image_volume import ImageVolume, MILLIMETER64
from extensions.imaging.labels import LabelMap
from std.math import inf, log, nan, sqrt
from std.testing import (
    TestSuite,
    assert_almost_equal,
    assert_equal,
    assert_raises,
    assert_true,
)
from units.si import CUBIC_METER, Duration64, Length64, METER, Volume64


def _cc(value: Float64) -> Volume64:
    return Volume64(value * 1e-6, CUBIC_METER)


def _days(value: Float64) -> Duration64:
    return Duration64(value, DAY64)


def _mm(value: Float64) -> Length64:
    return Length64(value, MILLIMETER64)


def test_doubling_and_growth() raises:
    # A volume that doubles in 100 days, one that quadruples, and one
    # that halves.
    assert_almost_equal(
        doubling_time(_cc(1), _cc(2), _days(100)).to(DAY64), 100.0
    )
    assert_almost_equal(
        doubling_time(_cc(1), _cc(4), _days(100)).to(DAY64), 50.0
    )
    assert_almost_equal(
        doubling_time(_cc(2), _cc(1), _days(100)).to(DAY64), -100.0
    )
    assert_almost_equal(
        growth_rate(_cc(1), _cc(2), _days(100)).to(PER_DAY64),
        log(2.0) / 100.0,
    )
    assert_equal(growth_rate(_cc(3), _cc(3), _days(10)).to(PER_DAY64), 0.0)
    with assert_raises(contains="no doubling time"):
        _ = doubling_time(_cc(3), _cc(3), _days(10))
    var bad: List[Float64] = [0.0, inf[DType.float64]()]
    for v in bad:
        with assert_raises(contains="tumor volume"):
            _ = growth_rate(_cc(v), _cc(1), _days(10))
        with assert_raises(contains="tumor volume"):
            _ = growth_rate(_cc(1), _cc(v), _days(10))
        with assert_raises(contains="between two scans"):
            _ = growth_rate(_cc(1), _cc(2), _days(v))


def _search(map: LabelMap, mark: UInt8) -> Float64:
    """The longest distance between two voxels of a label in one slice,
    over every pair."""
    var sx = map.spacing_x.to(METER)
    var sy = map.spacing_y.to(METER)
    var best = 0.0
    for k in range(map.nz):
        for a in range(map.nx * map.ny):
            if map.labels[k * map.nx * map.ny + a] != mark:
                continue
            for b in range(map.nx * map.ny):
                if map.labels[k * map.nx * map.ny + b] != mark:
                    continue
                var dx = Float64(a % map.nx - b % map.nx) * sx
                var dy = Float64(a // map.nx - b // map.nx) * sy
                best = max(best, sqrt(dx * dx + dy * dy))
    return best


def test_longest_diameter() raises:
    var volume = ImageVolume(21, 19, 4, _mm(0.5), _mm(0.8), _mm(3.0))
    var map = LabelMap(volume)
    # A blob of uneven shape on two slices, and a bar on another.
    for k in range(1, 3):
        for j in range(19):
            for i in range(21):
                var dx = Float64(i - 9) / Float64(6 + k)
                var dy = Float64(j - 8) / 5.0
                if dx * dx + dy * dy + 0.1 * dx * dy <= 1.0:
                    map.labels[map.index(i, j, k)] = 1
    for i in range(3, 10):
        map.labels[map.index(i, 15, 3)] = 2
    var blob = longest_diameter(map, LabelId(1))
    assert_almost_equal(blob.length.to(METER), _search(map, 1), atol=1e-15)
    assert_equal(blob.first[2], blob.second[2])
    var bar = longest_diameter(map, LabelId(2))
    assert_almost_equal(bar.length.to(METER), 0.003)
    assert_equal(bar.first[0], 3)
    assert_equal(bar.second[0], 9)
    # One voxel has no length.
    map.labels[map.index(20, 0, 0)] = 3
    assert_equal(longest_diameter(map, LabelId(3)).length.to(METER), 0.0)
    # A label that fills a slice runs corner to corner.
    var full = LabelMap(ImageVolume(5, 4, 1, _mm(1.0), _mm(1.0), _mm(1.0)))
    for v in range(full.count()):
        full.labels[v] = 1
    var corner = longest_diameter(full, LabelId(1))
    assert_almost_equal(corner.length.to(METER), 0.005)
    with assert_raises(contains="not the background"):
        _ = longest_diameter(map, BACKGROUND)
    with assert_raises(contains="label"):
        _ = longest_diameter(map, LabelId(300))
    with assert_raises(contains="one voxel or more"):
        _ = longest_diameter(map, LabelId(7))


def test_recist() raises:
    # A fall of 30 percent of the baseline, exactly, is a partial response.
    assert_true(
        recist_response(_mm(100), _mm(100), _mm(70)) == PARTIAL_RESPONSE
    )
    assert_true(
        recist_response(_mm(100), _mm(100), _mm(70.1)) == STABLE_DISEASE
    )
    # 20 percent and 10 mm over the nadir is progression.
    assert_true(
        recist_response(_mm(100), _mm(50), _mm(60)) == PROGRESSIVE_DISEASE
    )
    # 20 percent but 4 mm is not: the sum is still 76 percent below the
    # baseline.
    assert_true(recist_response(_mm(100), _mm(20), _mm(24)) == PARTIAL_RESPONSE)
    # 10 percent over the nadir is not progression.
    assert_true(recist_response(_mm(100), _mm(50), _mm(55)) == PARTIAL_RESPONSE)
    # Progression comes before a partial response.
    assert_true(
        recist_response(_mm(100), _mm(20), _mm(30)) == PROGRESSIVE_DISEASE
    )
    # After a complete response, a lesion of 5 mm is progression.
    assert_true(recist_response(_mm(40), _mm(0), _mm(5)) == PROGRESSIVE_DISEASE)
    assert_true(recist_response(_mm(40), _mm(0), _mm(0)) == COMPLETE_RESPONSE)
    var names: List[String] = ["CR", "PR", "SD", "PD"]
    for r in range(4):
        assert_equal(response_name(ResponseCategory(r)), names[r])
    with assert_raises(contains="response"):
        require_response(ResponseCategory(4))
    with assert_raises(contains="response"):
        _ = response_name(ResponseCategory(-1))
    var baselines: List[Float64] = [0.0, inf[DType.float64]()]
    for b in baselines:
        with assert_raises(contains="baseline sum"):
            _ = recist_response(_mm(b), _mm(0), _mm(1))
    var nadirs: List[Float64] = [-1.0, 101.0, nan[DType.float64]()]
    for n in nadirs:
        with assert_raises(contains="nadir sum"):
            _ = recist_response(_mm(100), _mm(n), _mm(1))
    var currents: List[Float64] = [-1.0, inf[DType.float64]()]
    for c in currents:
        with assert_raises(contains="current sum"):
            _ = recist_response(_mm(100), _mm(50), _mm(c))


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
