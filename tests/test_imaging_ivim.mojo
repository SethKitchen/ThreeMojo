# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Segmented IVIM fits of diffusion MRI, and their maps.

`assets/diffusion/ivim_expected.txt` holds numpy and scipy fits of
synthetic signals. See
`tools/make_mri_signals.mojo` and `assets/diffusion/make_ivim.py`.
"""

from extensions.imaging.diffusion import (
    BValue64,
    SECOND_PER_SQUARE_MILLIMETER,
    SQUARE_MILLIMETER_PER_SECOND,
)
from extensions.imaging.image_volume import ImageVolume
from extensions.imaging.ivim import fit_ivim, ivim_maps
from std.math import expm1, inf, nan
from std.testing import (
    TestSuite,
    assert_almost_equal,
    assert_equal,
    assert_raises,
)
from units.si import MILLIMETER64, Length64


def _b(values: List[Float64]) -> List[BValue64]:
    var out = List[BValue64]()
    for v in values:
        out.append(BValue64(v, SECOND_PER_SQUARE_MILLIMETER))
    return out^


def _split() -> BValue64:
    return BValue64(200.0, SECOND_PER_SQUARE_MILLIMETER)


def _close(a: Float64, b: Float64, tolerance: Float64) raises:
    assert_almost_equal(a, b, atol=tolerance * abs(b), rtol=0)


def _fixture() raises -> Tuple[List[Float64], List[List[Float64]]]:
    var b = List[Float64]()
    var rows = List[List[Float64]]()
    var text = open("assets/diffusion/ivim_expected.txt", "r").read()
    for line in text.splitlines():
        var parts = line.split(" ")
        var values = List[Float64]()
        for at in range(1, len(parts)):
            values.append(atof(String(parts[at])))
        if String(parts[0]) == "b":
            b = values^
        else:
            rows.append(values^)
    return (b^, rows^)


def test_against_scipy() raises:
    var data = _fixture()
    var b = _b(data[0])
    assert_equal(len(data[1]), 8)
    for row in data[1]:
        var fit = fit_ivim(b, List[Float64](row[0:11]), _split())
        _close(fit.diffusion.to(SQUARE_MILLIMETER_PER_SECOND), row[11], 1e-12)
        _close(fit.fraction, row[13], 1e-11)
        # The least of a flat sum of squares is found to about 1e-6.
        _close(
            fit.pseudo_diffusion.to(SQUARE_MILLIMETER_PER_SECOND), row[12], 1e-6
        )
        assert_equal(fit.s0, row[0])


def test_exact_model() raises:
    # With a fast D* of 0.4 mm^2/s, the blood has no signal from b = 200, so
    # D and f come back exactly.
    var b: List[Float64] = [0.0, 10.0, 20.0, 50.0, 100.0, 200.0, 400.0, 800.0]
    var s = List[Float64]()
    for v in b:
        s.append(
            1000.0
            * (0.2 * (1.0 + expm1(-v * 0.4)) + 0.8 * (1.0 + expm1(-v * 1e-3)))
        )
    var fit = fit_ivim(_b(b), s, _split())
    _close(fit.diffusion.to(SQUARE_MILLIMETER_PER_SECOND), 1e-3, 1e-12)
    _close(fit.fraction, 0.2, 1e-12)
    _close(fit.pseudo_diffusion.to(SQUARE_MILLIMETER_PER_SECOND), 0.4, 1e-6)


def test_maps() raises:
    var data = _fixture()
    var rows = data[1].copy()
    var masked = List[Float64](length=11, fill=500.0)
    masked[10] = 20.0
    rows.append(masked^)
    var missing = List[Float64](length=11, fill=500.0)
    missing[3] = nan[DType.float64]()
    rows.append(missing^)
    var endless = List[Float64](length=11, fill=500.0)
    endless[0] = inf[DType.float64]()
    rows.append(endless^)
    var step = Length64(1.0, MILLIMETER64)
    var series = List[ImageVolume]()
    for at in range(11):
        var volume = ImageVolume(4, 2, 2, step, step, step)
        for voxel in range(len(rows)):
            volume.values[voxel] = Float32(rows[voxel][at])
        series.append(volume^)
    var maps = ivim_maps(series, _b(data[0]), _split(), 20.0)
    for voxel in range(8):
        ref row = data[1][voxel]
        _close(Float64(maps.diffusion.values[voxel]), row[11] * 1e6, 1e-6)
        _close(
            Float64(maps.pseudo_diffusion.values[voxel]), row[12] * 1e6, 2e-6
        )
        _close(Float64(maps.fraction.values[voxel]), row[13], 1e-6)
    for voxel in range(8, 16):
        assert_equal(maps.diffusion.values[voxel], 0)
        assert_equal(maps.fraction.values[voxel], 0)


def test_errors() raises:
    var b = _b([0.0, 50.0, 200.0, 400.0])
    var s: List[Float64] = [1000.0, 800.0, 600.0, 500.0]
    with assert_raises(contains="4 b-values or more"):
        _ = fit_ivim(_b([0.0, 200.0, 400.0]), [1.0, 1.0, 1.0], _split())
    var splits: List[Float64] = [0.0, inf[DType.float64]()]
    for v in splits:
        with assert_raises(contains="split"):
            _ = fit_ivim(b, s, BValue64(v, SECOND_PER_SQUARE_MILLIMETER))
    with assert_raises(contains="finite and rise"):
        _ = fit_ivim(_b([0.0, 50.0, 200.0, inf[DType.float64]()]), s, _split())
    with assert_raises(contains="finite and rise"):
        _ = fit_ivim(_b([0.0, 50.0, 50.0, 400.0]), s, _split())
    with assert_raises(contains="first b-value of 0"):
        _ = fit_ivim(_b([10.0, 50.0, 200.0, 400.0]), s, _split())
    with assert_raises(contains="two b-values at or above"):
        _ = fit_ivim(_b([0.0, 50.0, 100.0, 400.0]), s, _split())
    with assert_raises(contains="two b-values at or above"):
        _ = fit_ivim(_b([0.0, 200.0, 400.0, 800.0]), s, _split())
    with assert_raises(contains="one signal for each"):
        _ = fit_ivim(b, [1.0, 1.0], _split())
    with assert_raises(contains="positive and finite"):
        _ = fit_ivim(b, [1000.0, 0.0, 600.0, 500.0], _split())
    with assert_raises(contains="positive and finite"):
        _ = fit_ivim(b, [1000.0, inf[DType.float64](), 600.0, 500.0], _split())
    var step = Length64(1.0, MILLIMETER64)
    var series = List[ImageVolume]()
    for _ in range(4):
        series.append(ImageVolume(2, 2, 2, step, step, step))
    with assert_raises(contains="one volume for each"):
        _ = ivim_maps(List[ImageVolume](series[0:3]), b, _split(), 0.0)
    with assert_raises(contains="threshold"):
        _ = ivim_maps(series, b, _split(), -1.0)
    with assert_raises(contains="threshold"):
        _ = ivim_maps(series, b, _split(), inf[DType.float64]())
    var sizes = [(3, 2, 2), (2, 3, 2), (2, 2, 3)]
    for size in sizes:
        var other = series.copy()
        other[2] = ImageVolume(size[0], size[1], size[2], step, step, step)
        with assert_raises(contains="different grids"):
            _ = ivim_maps(other, b, _split(), 0.0)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
