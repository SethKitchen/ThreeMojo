# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""MRI relaxometry: T2 from multi-echo decays, T1 from inversion recovery.

`assets/relaxometry/relaxometry_expected.txt` holds numpy and scipy fits of
synthetic signals. See
`tools/make_mri_signals.mojo` and `assets/relaxometry/make_relaxometry.py`.
The test finds T2 and S0 from the coefficients of numpy's fit.
"""

from extensions.imaging.image_volume import ImageVolume
from extensions.imaging.relaxometry import fit_t1, fit_t2, t1_maps, t2_maps
from extensions.numerics.elementary import precise_exp
from std.math import exp, expm1, inf, nan
from std.testing import (
    TestSuite,
    assert_almost_equal,
    assert_equal,
    assert_raises,
    assert_true,
)
from units.si import MILLIMETER64, MILLISECOND64, Duration64, Length64


struct _Rows(Movable):
    var times: List[Duration64]
    var rows: List[List[Float64]]

    def __init__(out self, head: String, name: String) raises:
        self.times = List[Duration64]()
        self.rows = List[List[Float64]]()
        var text = open(
            "assets/relaxometry/relaxometry_expected.txt", "r"
        ).read()
        for line in text.splitlines():
            var parts = line.split(" ")
            var values = List[Float64]()
            for at in range(1, len(parts)):
                values.append(atof(String(parts[at])))
            if String(parts[0]) == head:
                self.times = _ms(values)
            elif String(parts[0]) == name:
                if name == "t2":
                    # numpy fits ln S = ln S0 - TE / T2: the row ends with
                    # its slope and intercept, for T2 in ms and S0.
                    var last = len(values) - 1
                    var slope = values[last - 1]
                    values[last - 1] = -1.0 / slope
                    values[last] = precise_exp(values[last])
                self.rows.append(values^)


def _ms(values: List[Float64]) -> List[Duration64]:
    var out = List[Duration64]()
    for v in values:
        out.append(Duration64(v, MILLISECOND64))
    return out^


def _close(a: Float64, b: Float64, tolerance: Float64) raises:
    assert_almost_equal(a, b, atol=tolerance * abs(b), rtol=0)


def _series(rows: List[List[Float64]], count: Int) raises -> List[ImageVolume]:
    """Put the first `count` values of each row in one voxel each, on a grid
    of 4 by 2 by 2."""
    var step = Length64(1.0, MILLIMETER64)
    var out = List[ImageVolume]()
    for at in range(count):
        var volume = ImageVolume(4, 2, 2, step, step, step)
        for voxel in range(len(rows)):
            volume.values[voxel] = Float32(rows[voxel][at])
        out.append(volume^)
    return out^


def test_t2_against_numpy() raises:
    var data = _Rows("te", "t2")
    assert_equal(len(data.rows), 8)
    for row in data.rows:
        var fit = fit_t2(data.times, List[Float64](row[0:8]))
        _close(fit.t2.to(MILLISECOND64), row[8], 1e-12)
        _close(fit.s0, row[9], 1e-12)


def test_t1_against_scipy() raises:
    var data = _Rows("ti", "t1")
    assert_equal(len(data.rows), 8)
    for row in data.rows:
        var fit = fit_t1(data.times, List[Float64](row[0:8]))
        _close(fit.t1.to(MILLISECOND64), row[8], 1e-8)
        _close(fit.a, row[9], 1e-8)
        _close(fit.b, row[10], 1e-8)
        assert_equal(fit.flips, Int(row[11]))


def test_exact_curves() raises:
    var te: List[Float64] = [10.0, 20.0, 40.0, 80.0]
    var decay = List[Float64]()
    for t in te:
        decay.append(1000.0 * (1.0 + expm1(-t / 50.0)))
    var t2 = fit_t2(_ms(te), decay)
    _close(t2.t2.to(MILLISECOND64), 50.0, 1e-13)
    _close(t2.s0, 1000.0, 1e-13)
    # A full inversion crosses 0 at T1 ln 2, 554.5 ms: three signals are
    # negative.
    var ti: List[Float64] = [
        50.0,
        150.0,
        300.0,
        600.0,
        1000.0,
        1500.0,
        2500.0,
        4000.0,
    ]
    var recovery = List[Float64]()
    for t in ti:
        recovery.append(abs(1000.0 - 2000.0 * (1.0 + expm1(-t / 800.0))))
    var t1 = fit_t1(_ms(ti), recovery)
    _close(t1.t1.to(MILLISECOND64), 800.0, 1e-10)
    _close(t1.a, 1000.0, 1e-11)
    _close(t1.b, 2000.0, 1e-11)
    assert_equal(t1.flips, 3)
    assert_true(t1.residual < 1e-15)


def test_maps() raises:
    var t2 = _Rows("te", "t2")
    var rows = t2.rows.copy()
    var special: List[List[Float64]] = [
        [100.0, 80.0, 60.0, 5.0, 4.0, 3.0, 2.0, 1.0],
        [inf[DType.float64](), 80.0, 60.0, 50.0, 40.0, 30.0, 20.0, 10.0],
        [10.0, 20.0, 30.0, 40.0, 50.0, 60.0, 70.0, 80.0],
        [100.0, 90.0, 80.0, 70.0, 60.0, 50.0, 40.0, 30.0],
    ]
    var count = 0
    for row in special:
        rows.append(row.copy())
        count += 1
    var series = _series(rows, 8)
    # Twelve rows on a grid of sixteen: the last four voxels are 0.
    var maps = t2_maps(series, t2.times, 5.0)
    for voxel in range(8):
        _close(Float64(maps.time.values[voxel]), t2.rows[voxel][8], 1e-6)
        _close(Float64(maps.amplitude.values[voxel]), t2.rows[voxel][9], 1e-6)
    for voxel in range(8, 11):
        assert_equal(maps.time.values[voxel], 0)
    assert_true(maps.time.values[11] > 0)
    assert_equal(maps.time.values[15], 0)
    var t1 = _Rows("ti", "t1")
    var recovery = t1.rows.copy()
    recovery.append([500.0, 300.0, 100.0, 50.0, 30.0, 20.0, 10.0, 4.0])
    recovery.append(
        [500.0, nan[DType.float64](), 100.0, 50.0, 300.0, 400.0, 500.0, 600.0]
    )
    recovery.append([500.0, -1.0, 100.0, 50.0, 300.0, 400.0, 500.0, 600.0])
    var inversions = t1_maps(_series(recovery, 8), t1.times, 5.0)
    for voxel in range(8):
        _close(Float64(inversions.time.values[voxel]), t1.rows[voxel][8], 1e-6)
        _close(
            Float64(inversions.amplitude.values[voxel]), t1.rows[voxel][9], 1e-6
        )
    for voxel in range(8, 16):
        assert_equal(inversions.time.values[voxel], 0)


def test_errors() raises:
    var two = _ms([10.0, 20.0])
    with assert_raises(contains="2 times or more"):
        _ = fit_t2(_ms([10.0]), [1.0])
    with assert_raises(contains="4 times or more"):
        _ = fit_t1(_ms([10.0, 20.0, 30.0]), [1.0, 1.0, 1.0])
    with assert_raises(contains="0 or more"):
        _ = fit_t2(_ms([-1.0, 20.0]), [2.0, 1.0])
    with assert_raises(contains="0 or more"):
        _ = fit_t2(_ms([10.0, inf[DType.float64]()]), [2.0, 1.0])
    with assert_raises(contains="must rise"):
        _ = fit_t2(_ms([10.0, 10.0]), [2.0, 1.0])
    with assert_raises(contains="one signal for each"):
        _ = fit_t2(two, [1.0])
    with assert_raises(contains="finite and 0 or more"):
        _ = fit_t2(two, [1.0, -1.0])
    with assert_raises(contains="finite and 0 or more"):
        _ = fit_t2(two, [1.0, inf[DType.float64]()])
    with assert_raises(contains="above 0"):
        _ = fit_t2(two, [1.0, 0.0])
    with assert_raises(contains="fall with the echo time"):
        _ = fit_t2(two, [1.0, 2.0])
    var step = Length64(1.0, MILLIMETER64)
    var series = List[ImageVolume]()
    series.append(ImageVolume(2, 2, 2, step, step, step))
    series.append(ImageVolume(2, 2, 2, step, step, step))
    with assert_raises(contains="one volume for each"):
        _ = t2_maps(series, _ms([10.0, 20.0, 30.0]), 0.0)
    with assert_raises(contains="threshold"):
        _ = t2_maps(series, two, -1.0)
    with assert_raises(contains="threshold"):
        _ = t2_maps(series, two, inf[DType.float64]())
    var sizes = [(3, 2, 2), (2, 3, 2), (2, 2, 3)]
    for size in sizes:
        var other = series.copy()
        other[1] = ImageVolume(size[0], size[1], size[2], step, step, step)
        with assert_raises(contains="different grids"):
            _ = t2_maps(other, two, 0.0)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
