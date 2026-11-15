# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Diffusion MRI: ADC and kurtosis fits, their maps, and computed images.

`assets/diffusion/diffusion_expected.txt` holds numpy fits of synthetic
signals. See `assets/diffusion/make_diffusion.py`.
"""

from extensions.imaging.diffusion import (
    AdcMaps,
    BValue64,
    Diffusivity64,
    SECOND_PER_SQUARE_MILLIMETER,
    SQUARE_MICROMETER_PER_SECOND,
    SQUARE_MILLIMETER_PER_SECOND,
    adc_maps,
    computed_dwi,
    fit_adc,
    fit_kurtosis,
    kurtosis_maps,
)
from extensions.imaging.image_volume import ImageVolume, MILLIMETER64
from extensions.sdf.vector import v3
from std.math import expm1, inf, log, nan
from std.testing import (
    TestSuite,
    assert_almost_equal,
    assert_equal,
    assert_raises,
    assert_true,
)
from units.si import Length64


struct _Rows(Movable):
    """The b-values and the voxel rows of one model in the fixture."""

    var b_values: List[BValue64]
    var rows: List[List[Float64]]

    def __init__(out self):
        self.b_values = List[BValue64]()
        self.rows = List[List[Float64]]()


def _numbers(line: String) raises -> List[Float64]:
    var values = List[Float64]()
    var first = True
    for part in line.split(" "):
        if first:
            first = False
            continue
        values.append(atof(String(part)))
    return values^


def _fixture(name: String) raises -> _Rows:
    """Read the rows of `adc` or `kurtosis` from the fixture."""
    var out = _Rows()
    var text = open("assets/diffusion/diffusion_expected.txt", "r").read()
    for line in text.splitlines():
        var head = String(line.split(" ")[0])
        if head == name + "_b":
            out.b_values = _b(_numbers(String(line)))
        elif head == name:
            out.rows.append(_numbers(String(line)))
    return out^


def _b(values: List[Float64]) -> List[BValue64]:
    var out = List[BValue64]()
    for v in values:
        out.append(BValue64(v, SECOND_PER_SQUARE_MILLIMETER))
    return out^


def _mm2s(d: Diffusivity64) -> Float64:
    return d.to(SQUARE_MILLIMETER_PER_SECOND)


def _close(a: Float64, b: Float64, tolerance: Float64) raises:
    assert_almost_equal(a, b, atol=tolerance * abs(b), rtol=0)


def _series(
    rows: List[List[Float64]], count: Int, nx: Int, ny: Int, nz: Int
) raises -> List[ImageVolume]:
    """Put the first `count` values of each row in one voxel each."""
    var step = Length64(2.0, MILLIMETER64)
    var out = List[ImageVolume]()
    for at in range(count):
        var volume = ImageVolume(
            nx, ny, nz, step, step, Length64(4.0, MILLIMETER64)
        )
        volume.origin = v3(0.01, -0.02, 0.03)
        for voxel in range(len(rows)):
            volume.values[voxel] = Float32(rows[voxel][at])
        out.append(volume^)
    return out^


def test_adc_against_numpy() raises:
    var data = _fixture("adc")
    assert_equal(len(data.rows), 12)
    for row in data.rows:
        var fit = fit_adc(data.b_values, List[Float64](row[0:5]))
        _close(_mm2s(fit.adc), row[5], 1e-12)
        _close(fit.s0, row[6], 1e-12)


def test_kurtosis_against_numpy() raises:
    var data = _fixture("kurtosis")
    assert_equal(len(data.rows), 8)
    for row in data.rows:
        var fit = fit_kurtosis(data.b_values, List[Float64](row[0:6]))
        _close(_mm2s(fit.diffusivity), row[6], 1e-11)
        _close(fit.kurtosis, row[7], 1e-10)
        _close(fit.s0, row[8], 1e-12)


def test_two_b_values() raises:
    # Half the signal at b = 1000: ADC = ln 2 / 1000 mm^2/s.
    var fit = fit_adc(_b([0.0, 1000.0]), [1000.0, 500.0])
    _close(_mm2s(fit.adc), log(2.0) / 1000.0, 1e-14)
    _close(fit.s0, 1000.0, 1e-14)
    # A signal that rises gives an ADC below 0.
    var rising = fit_adc(_b([0.0, 1000.0]), [500.0, 1000.0])
    _close(_mm2s(rising.adc), -log(2.0) / 1000.0, 1e-14)


def test_exact_models() raises:
    # Exact signals give back the model to rounding.
    var b: List[Float64] = [0.0, 300.0, 700.0, 1000.0, 1400.0, 2000.0]
    var mono = List[Float64]()
    var kurt = List[Float64]()
    for value in b:
        var bd = value * 1.1e-3
        mono.append(800.0 * (1.0 + expm1(-bd)))
        kurt.append(1500.0 * (1.0 + expm1(-bd + bd * bd * 0.9 / 6.0)))
    var adc = fit_adc(_b(b), mono)
    _close(_mm2s(adc.adc), 1.1e-3, 1e-13)
    _close(adc.s0, 800.0, 1e-13)
    var fit = fit_kurtosis(_b(b), kurt)
    _close(_mm2s(fit.diffusivity), 1.1e-3, 1e-12)
    _close(fit.kurtosis, 0.9, 1e-11)
    _close(fit.s0, 1500.0, 1e-13)
    # Free diffusion has a kurtosis of 0.
    var free = fit_kurtosis(_b(b), mono)
    assert_almost_equal(free.kurtosis, 0.0, atol=1e-11)


def test_adc_maps_match_the_fits() raises:
    var data = _fixture("adc")
    var series = _series(data.rows, 5, 3, 2, 2)
    var maps = adc_maps(series, data.b_values, 0.0)
    assert_equal(maps.adc.nx, 3)
    assert_equal(maps.adc.nz, 2)
    assert_equal(maps.adc.spacing_z.to(MILLIMETER64), 4.0)
    assert_equal(maps.s0.origin.y, -0.02)
    var low = Float64(maps.adc.values[0])
    var high = low
    for voxel in range(12):
        var row = data.rows[voxel].copy()
        var adc = Float64(maps.adc.values[voxel])
        # In 10^-6 mm^2/s, to the rounding of a 32-bit value.
        _close(adc, row[5] * 1e6, 1e-6)
        _close(Float64(maps.s0.values[voxel]), row[6], 1e-6)
        low = min(low, adc)
        high = max(high, adc)
    # The window fits the values of the map.
    _close(maps.adc.window_center, (low + high) / 2, 1e-12)
    _close(maps.adc.window_width, high - low, 1e-12)


def test_threshold_masks_voxels() raises:
    var data = _fixture("adc")
    var series = _series(data.rows, 5, 3, 2, 2)
    # Voxel 1 falls to the threshold at b = 1000, voxel 2 holds no number
    # and voxel 3 holds an infinite signal.
    series[4].values[1] = 100
    series[4].values[2] = nan[DType.float32]()
    series[0].values[3] = inf[DType.float32]()
    var maps = adc_maps(series, data.b_values, 100.0)
    assert_equal(maps.adc.values[1], 0)
    assert_equal(maps.s0.values[1], 0)
    assert_equal(maps.adc.values[2], 0)
    assert_equal(maps.adc.values[3], 0)
    _close(Float64(maps.adc.values[0]), data.rows[0][5] * 1e6, 1e-6)
    assert_true(maps.adc.values[11] > 2900)


def test_kurtosis_maps_match_the_fits() raises:
    var data = _fixture("kurtosis")
    # A ninth voxel rises with b, and a tenth is under the threshold.
    data.rows.append([100.0, 120.0, 150.0, 190.0, 240.0, 300.0])
    data.rows.append([40.0, 30.0, 20.0, 15.0, 12.0, 10.0])
    var series = _series(data.rows, 6, 5, 2, 1)
    var maps = kurtosis_maps(series, data.b_values, 10.0)
    for voxel in range(8):
        var row = data.rows[voxel].copy()
        _close(Float64(maps.diffusivity.values[voxel]), row[6] * 1e6, 1e-6)
        _close(Float64(maps.kurtosis.values[voxel]), row[7], 1e-5)
        _close(Float64(maps.s0.values[voxel]), row[8], 1e-6)
    for voxel in range(8, 10):
        assert_equal(maps.diffusivity.values[voxel], 0)
        assert_equal(maps.kurtosis.values[voxel], 0)
        assert_equal(maps.s0.values[voxel], 0)
    assert_true(maps.kurtosis.window_width > 0.5)


def test_computed_dwi() raises:
    var data = _fixture("adc")
    var series = _series(data.rows, 5, 3, 2, 2)
    series[4].values[5] = 0
    var maps = adc_maps(series, data.b_values, 1.0)
    var image = computed_dwi(
        maps, BValue64(1500.0, SECOND_PER_SQUARE_MILLIMETER)
    )
    for voxel in range(12):
        if voxel == 5:
            assert_equal(image.values[voxel], 0)
            continue
        _close(Float64(image.values[voxel]), data.rows[voxel][7], 1e-5)
    # At b = 0, the image is S0.
    var flat = computed_dwi(maps, BValue64(0.0, SECOND_PER_SQUARE_MILLIMETER))
    for voxel in range(12):
        assert_equal(flat.values[voxel], maps.s0.values[voxel])
    assert_equal(flat.origin.x, 0.01)


def test_units() raises:
    var d = Diffusivity64(3.0e-3, SQUARE_MILLIMETER_PER_SECOND)
    _close(d.to(SQUARE_MICROMETER_PER_SECOND), 3000.0, 1e-15)
    var b = BValue64(1000.0, SECOND_PER_SQUARE_MILLIMETER)
    # b times ADC has no unit: 1000 s/mm^2 times 3e-3 mm^2/s is 3.
    _close((b * d).value, 3.0, 1e-15)


def test_fit_errors() raises:
    var b = _b([0.0, 500.0, 1000.0])
    var s: List[Float64] = [1000.0, 600.0, 360.0]
    with assert_raises(contains="2 b-values or more"):
        _ = fit_adc(_b([0.0]), [1.0])
    with assert_raises(contains="3 b-values or more"):
        _ = fit_kurtosis(_b([0.0, 1.0]), [1.0, 1.0])
    with assert_raises(contains="0 or more"):
        _ = fit_adc(_b([0.0, -1.0]), [1.0, 1.0])
    with assert_raises(contains="0 or more"):
        _ = fit_adc(_b([0.0, inf[DType.float64]()]), [1.0, 1.0])
    with assert_raises(contains="0 or more"):
        _ = fit_adc(_b([nan[DType.float64](), 1.0]), [1.0, 1.0])
    with assert_raises(contains="two distinct"):
        _ = fit_adc(_b([500.0, 500.0, 500.0]), s)
    with assert_raises(contains="three distinct"):
        _ = fit_kurtosis(_b([0.0, 1000.0, 0.0, 1000.0]), [9.0, 3.0, 9.0, 3.0])
    with assert_raises(contains="one signal for each"):
        _ = fit_adc(b, [1.0, 1.0])
    with assert_raises(contains="positive and finite"):
        _ = fit_adc(b, [1.0, 0.0, 1.0])
    with assert_raises(contains="positive and finite"):
        _ = fit_kurtosis(b, [1.0, inf[DType.float64](), 1.0])
    with assert_raises(contains="fall with b"):
        _ = fit_kurtosis(b, [360.0, 600.0, 1000.0])


def test_map_errors() raises:
    var data = _fixture("adc")
    var series = _series(data.rows, 5, 3, 2, 2)
    var b = data.b_values.copy()
    with assert_raises(contains="one volume for each"):
        _ = adc_maps(series, List[BValue64](b[0:4]), 0.0)
    with assert_raises(contains="threshold"):
        _ = adc_maps(series, b, -1.0)
    with assert_raises(contains="threshold"):
        _ = kurtosis_maps(series, b, inf[DType.float64]())
    with assert_raises(contains="two distinct"):
        _ = adc_maps(List[ImageVolume](series[0:2]), _b([5.0, 5.0]), 0.0)
    with assert_raises(contains="three distinct"):
        _ = kurtosis_maps(
            List[ImageVolume](series[0:3]), _b([5.0, 5.0, 9.0]), 0.0
        )
    var step = Length64(1.0, MILLIMETER64)
    var sizes = [(4, 2, 2), (3, 3, 2), (3, 2, 1)]
    for size in sizes:
        var other = series.copy()
        other[2] = ImageVolume(size[0], size[1], size[2], step, step, step)
        with assert_raises(contains="different grids"):
            _ = adc_maps(other, b, 0.0)
    var maps = adc_maps(series, b, 0.0)
    with assert_raises(contains="0 or more"):
        _ = computed_dwi(maps, BValue64(-1.0, SECOND_PER_SQUARE_MILLIMETER))
    with assert_raises(contains="0 or more"):
        _ = computed_dwi(
            maps, BValue64(inf[DType.float64](), SECOND_PER_SQUARE_MILLIMETER)
        )
    for size in sizes:
        var other = maps.copy()
        other.s0 = ImageVolume(size[0], size[1], size[2], step, step, step)
        with assert_raises(contains="different grids"):
            _ = computed_dwi(other, BValue64(1.0, SECOND_PER_SQUARE_MILLIMETER))


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
