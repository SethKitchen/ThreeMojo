# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Tofts models of DCE-MRI: exact curves, fits and maps.

`assets/dce/dce_expected.txt` holds curves from dcmri 0.6.20. See
`assets/dce/make_dce.py`.
"""

from extensions.imaging.dce import (
    MINUTE64,
    PER_MINUTE64,
    ToftsFit,
    fit_tofts,
    parker_aif,
    tofts_curve,
    tofts_maps,
)
from extensions.imaging.ids import (
    BACKGROUND,
    EXTENDED_TOFTS,
    LabelId,
    STANDARD_TOFTS,
    ToftsModel,
    require_tofts_model,
)
from extensions.imaging.image_volume import ImageVolume, MILLIMETER64
from extensions.imaging.labels import LabelMap
from std.math import expm1, inf, nan
from std.testing import (
    TestSuite,
    assert_almost_equal,
    assert_equal,
    assert_raises,
    assert_true,
)
from units.si import Duration64, Frequency64, Length64, SECOND


def _curves() raises -> List[List[Float64]]:
    """The rows of the dcmri file: times, blood, plasma, standard and
    extended."""
    var out = List[List[Float64]]()
    var text = open("assets/dce/dce_expected.txt", "r").read()
    for line in text.splitlines():
        var values = List[Float64]()
        var first = True
        for part in line.split(" "):
            if first:
                first = False
                continue
            values.append(atof(String(part)))
        out.append(values^)
    return out^


def _seconds(values: List[Float64]) -> List[Duration64]:
    var out = List[Duration64]()
    for v in values:
        out.append(Duration64(v, SECOND))
    return out^


def _rate(per_minute: Float64) -> Frequency64:
    return Frequency64(per_minute, PER_MINUTE64)


def _close(a: Float64, b: Float64, tolerance: Float64) raises:
    assert_almost_equal(a, b, atol=tolerance * max(abs(b), 1e-3), rtol=0)


def test_closed_forms() raises:
    # A plasma step of 2 from the first time: Ct = ve 2 (1 - exp(-kep t)).
    # The references take expm1, which is exact in Mojo 1.2 where exp is not.
    var minutes: List[Float64] = [0.0, 0.05, 0.5, 1.0, 3.0, 7.5]
    var times = List[Duration64]()
    var step = List[Float64]()
    var ramp = List[Float64]()
    for m in minutes:
        times.append(Duration64(m, MINUTE64))
        step.append(2.0)
        ramp.append(3.0 * m)
    var curve = tofts_curve(times, step, _rate(0.3), 0.4, 0.05)
    var ramped = tofts_curve(times, ramp, _rate(0.3), 0.4, 0.0)
    var kep = 0.75
    for n in range(len(minutes)):
        var t = minutes[n]
        _close(curve[n], 0.4 * 2.0 * -expm1(-kep * t) + 0.1, 1e-14)
        # A ramp of 3 a minute: 3 Ktrans (t / kep - (1 - exp(-kep t)) / kep^2).
        var want = 3.0 * 0.3 * (t / kep + expm1(-kep * t) / (kep * kep))
        _close(ramped[n], want, 1e-13)
    # A tiny kep takes the series. The same closed form, as its series
    # in k t, holds to 1e-12.
    var slow = tofts_curve(times, ramp, _rate(1e-5), 0.5, 0.0)
    var k = 2e-5
    for n in range(len(minutes)):
        var t = minutes[n]
        var bracket = t * t * (0.5 - k * t * (1.0 / 6.0 - k * t / 24.0))
        _close(slow[n], 3.0 * 1e-5 * bracket, 1e-12)
    # No uptake: only the plasma part.
    var none = tofts_curve(times, step, _rate(0), 0.4, 0.05)
    assert_equal(none[3], 0.1)


def test_dcmri_curves() raises:
    var rows = _curves()
    var times = _seconds(rows[0])
    # dcmri rounds the heights of its Gaussians to six digits.
    var blood = parker_aif(times)
    for n in range(len(blood)):
        _close(blood[n], rows[1][n], 1e-5)
    var standard = tofts_curve(times, rows[2], _rate(0.25), 0.3, 0.0)
    var extended = tofts_curve(times, rows[2], _rate(0.12), 0.45, 0.06)
    for n in range(len(standard)):
        _close(standard[n], rows[3][n], 1e-12)
        _close(extended[n], rows[4][n], 1e-12)
    assert_equal(len(parker_aif(List[Duration64]())), 0)


def test_fits() raises:
    var rows = _curves()
    var times = _seconds(rows[0])
    var a = fit_tofts(times, rows[2], rows[3], STANDARD_TOFTS)
    _close(a.ktrans.to(PER_MINUTE64), 0.25, 1e-6)
    _close(a.ve, 0.3, 1e-6)
    _close(a.kep.to(PER_MINUTE64), 0.25 / 0.3, 1e-6)
    assert_equal(a.vp, 0.0)
    assert_true(a.rms < 1e-7)
    var b = fit_tofts(times, rows[2], rows[4], EXTENDED_TOFTS)
    _close(b.ktrans.to(PER_MINUTE64), 0.12, 1e-6)
    _close(b.ve, 0.45, 1e-6)
    _close(b.vp, 0.06, 1e-6)
    # The standard model on an extended tissue misfits it.
    var c = fit_tofts(times, rows[2], rows[4], STANDARD_TOFTS)
    assert_true(c.rms > 100 * b.rms)
    # A tissue of plasma alone is all vp, and one of nothing is all zero.
    var vessel = List[Float64]()
    var empty = List[Float64]()
    for p in rows[2]:
        vessel.append(0.08 * p)
        empty.append(0.0)
    var d = fit_tofts(times, rows[2], vessel, EXTENDED_TOFTS)
    assert_true(d.ktrans.to(PER_MINUTE64) < 1e-9)
    _close(d.vp, 0.08, 1e-9)
    var e = fit_tofts(times, rows[2], empty, STANDARD_TOFTS)
    assert_equal(e.ktrans.to(PER_MINUTE64), 0.0)
    assert_equal(e.ve, 0.0)
    assert_equal(e.kep.to(PER_MINUTE64), 0.0)
    assert_equal(e.rms, 0.0)
    # Two samples of plasma that start at 0 make Ktrans and vp one
    # direction: the fit keeps one of them.
    var short = _seconds([0.0, 30.0, 60.0])
    var f = fit_tofts(short, [0.0, 0.0, 4.0], [0.0, 0.0, 1.0], EXTENDED_TOFTS)
    assert_true(f.rms < 1e-12)


def test_maps() raises:
    var rows = _curves()
    var times = _seconds(rows[0])
    var step = Length64(1.0, MILLIMETER64)
    var grid = ImageVolume(3, 2, 1, step, step, step)
    var series = List[ImageVolume]()
    for n in range(len(times)):
        var volume = grid.copy()
        volume.values[0] = Float32(rows[3][n])
        volume.values[1] = Float32(rows[4][n])
        series.append(volume^)
    var map = LabelMap(grid)
    map.labels[0] = 1
    map.labels[1] = 1
    var maps = tofts_maps(
        series, times, rows[2], map, LabelId(1), EXTENDED_TOFTS
    )
    # The volumes hold 32-bit values, so the fits hold to 1e-4.
    _close(Float64(maps.ktrans.values[0]), 0.25, 1e-4)
    _close(Float64(maps.ve.values[1]), 0.45, 1e-4)
    _close(Float64(maps.vp.values[1]), 0.06, 1e-3)
    assert_equal(maps.ktrans.values[2], 0)
    assert_true(maps.rms.values[0] < 1e-4)
    with assert_raises(contains="not the background"):
        _ = tofts_maps(series, times, rows[2], map, BACKGROUND, STANDARD_TOFTS)
    with assert_raises(contains="label"):
        _ = tofts_maps(
            series, times, rows[2], map, LabelId(300), STANDARD_TOFTS
        )
    var fewer = series.copy()
    _ = fewer.pop()
    with assert_raises(contains="one volume for each time"):
        _ = tofts_maps(fewer, times, rows[2], map, LabelId(1), STANDARD_TOFTS)
    var other = LabelMap(ImageVolume(2, 2, 1, step, step, step))
    with assert_raises(contains="different grids"):
        _ = tofts_maps(
            series, times, rows[2], other, LabelId(1), STANDARD_TOFTS
        )


def test_refusals() raises:
    with assert_raises(contains="Tofts model"):
        require_tofts_model(ToftsModel(2))
    var times = _seconds([0.0, 10.0, 20.0])
    var plasma: List[Float64] = [1.0, 2.0, 1.5]
    var tissue: List[Float64] = [0.0, 0.1, 0.2]
    with assert_raises(contains="Tofts model"):
        _ = fit_tofts(times, plasma, tissue, ToftsModel(-1))
    with assert_raises(contains="3 times or more"):
        _ = fit_tofts(
            _seconds([0.0, 10.0]), [1.0, 2.0], [0.0, 1.0], STANDARD_TOFTS
        )
    with assert_raises(contains="2 times or more"):
        _ = tofts_curve(_seconds([0.0]), [1.0], _rate(0.1), 0.5, 0.0)
    with assert_raises(contains="must rise"):
        _ = tofts_curve(
            _seconds([0.0, 10.0, 10.0]), plasma, _rate(0.1), 0.5, 0.0
        )
    with assert_raises(contains="must be finite"):
        _ = tofts_curve(
            _seconds([0.0, inf[DType.float64]()]),
            [1.0, 2.0],
            _rate(0.1),
            0.5,
            0.0,
        )
    with assert_raises(contains="must be finite"):
        _ = parker_aif(_seconds([nan[DType.float64]()]))
    with assert_raises(contains="one value for each time"):
        _ = tofts_curve(times, [1.0, 2.0], _rate(0.1), 0.5, 0.0)
    with assert_raises(contains="finite values"):
        _ = fit_tofts(
            times, plasma, [0.0, nan[DType.float64](), 0.0], STANDARD_TOFTS
        )
    var rates: List[Float64] = [-0.1, inf[DType.float64]()]
    for k in rates:
        with assert_raises(contains="Ktrans"):
            _ = tofts_curve(times, plasma, _rate(k), 0.5, 0.0)
    var ves: List[Float64] = [0.0, 1.5]
    for v in ves:
        with assert_raises(contains="ve must"):
            _ = tofts_curve(times, plasma, _rate(0.1), v, 0.0)
    var vps: List[Float64] = [-0.1, 1.5]
    for v in vps:
        with assert_raises(contains="vp must"):
            _ = tofts_curve(times, plasma, _rate(0.1), 0.5, v)
    with assert_raises(contains="0 or more"):
        _ = fit_tofts(times, [1.0, -2.0, 1.0], tissue, STANDARD_TOFTS)
    with assert_raises(contains="a value above 0"):
        _ = fit_tofts(times, [0.0, 0.0, 0.0], tissue, STANDARD_TOFTS)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
