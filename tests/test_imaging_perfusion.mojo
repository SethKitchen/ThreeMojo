# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Perfusion of CT and DSC-MRI by truncated SVD deconvolution.

`assets/perfusion/perfusion_expected.txt` holds numpy deconvolutions of
synthetic curves. See
`tools/make_perfusion.mojo` and `assets/perfusion/make_perfusion.py`.
"""

from extensions.imaging.ids import LabelId
from extensions.imaging.image_volume import ImageVolume
from extensions.imaging.labels import LabelMap
from extensions.imaging.perfusion import (
    BRAIN_DENSITY,
    BloodFlow64,
    Deconvolution,
    HEMATOCRIT_FACTOR,
    MILLILITER_PER_100_GRAM,
    MILLILITER_PER_100_GRAM_PER_MINUTE,
    PerfusionFit,
    PerfusionMaps,
    ct_concentration,
    ct_concentration_series,
    dsc_concentration,
    perfusion_maps,
    perfusion_mismatch,
)
from std.math import inf, nan
from std.testing import (
    TestSuite,
    assert_almost_equal,
    assert_equal,
    assert_raises,
    assert_true,
)
from units.si import (
    CUBIC_METER,
    GRAM_PER_CUBIC_CENTIMETER,
    MILLIMETER64,
    MILLISECOND64,
    PER_SECOND,
    SECOND,
    Density64,
    Duration64,
    Frequency64,
    Length64,
)


def _close(a: Float64, b: Float64, tolerance: Float64) raises:
    assert_almost_equal(a, b, atol=tolerance * abs(b), rtol=0)


def _density() -> Density64:
    return Density64(BRAIN_DENSITY, GRAM_PER_CUBIC_CENTIMETER)


def _step() -> Duration64:
    return Duration64(1.5, SECOND)


def _rows(path: String, kind: String) raises -> List[List[Float64]]:
    """Return the values of each line of a kind, after the kind and, for
    a tissue line, its number."""
    var out = List[List[Float64]]()
    var text = open(path, "r").read()
    for line in text.splitlines():
        var parts = line.split(" ")
        if String(parts[0]) != kind:
            continue
        var first = 1
        if kind == "tissue" or kind == "ssvd" or kind == "csvd":
            first = 2
        var row = List[Float64]()
        for at in range(first, len(parts)):
            row.append(atof(String(parts[at])))
        out.append(row^)
    return out^


comptime DATA = "assets/perfusion/perfusion_data.txt"
comptime EXPECTED = "assets/perfusion/perfusion_expected.txt"


def _check(
    deconvolution: Deconvolution,
    tissues: List[List[Float64]],
    expected: List[List[Float64]],
) raises:
    for at in range(len(tissues)):
        var tissue = ct_concentration(tissues[at], 4)
        var k = deconvolution.residue(tissue)
        ref row = expected[at]
        var n = len(k)
        assert_equal(len(row), n + 3)
        var peak = row[n]
        for i in range(n):
            assert_almost_equal(k[i], row[i], atol=1e-11 * peak, rtol=0)
        var fit = deconvolution.fit(tissue)
        _close(fit.flow.to(PER_SECOND), peak, 1e-11)
        _close(fit.tmax.to(SECOND), row[n + 1], 1e-15)
        _close(fit.volume, row[n + 2], 1e-13)


def test_against_numpy() raises:
    var step = _rows(DATA, "step")
    assert_equal(step[0][0], 1.5)
    var arterial = ct_concentration(_rows(DATA, "arterial")[0], 4)
    var tissues = _rows(DATA, "tissue")
    assert_equal(len(tissues), 4)
    var lower = Deconvolution(arterial, _step(), 0.2)
    assert_equal(lower.size, 40)
    _check(lower, tissues, _rows(EXPECTED, "ssvd"))
    var circular = Deconvolution.circular(arterial, _step(), 0.15)
    assert_equal(circular.size, 80)
    _check(circular, tissues, _rows(EXPECTED, "csvd"))


def test_dsc() raises:
    var signal = _rows(DATA, "dsc")[0].copy()
    var expected = _rows(EXPECTED, "dsc")[0].copy()
    var r2 = dsc_concentration(signal, 4, Duration64(30, MILLISECOND64))
    for at in range(len(r2)):
        assert_almost_equal(r2[at], expected[at], atol=1e-12, rtol=0)


def _exact(
    arterial: List[Float64], k: List[Float64], dt: Float64
) -> List[Float64]:
    """Return the discrete convolution `dt sum Ca[j - i] k[i]`."""
    var out = List[Float64]()
    for j in range(len(arterial)):
        var total = 0.0
        for i in range(j + 1):
            total += arterial[j - i] * k[i]
        out.append(dt * total)
    return out^


def test_exact_and_delays() raises:
    # Ca = 0.5^j makes a well conditioned matrix, so with every singular
    # value kept the residue comes back exactly.
    var arterial = List[Float64]()
    var k = List[Float64]()
    var value = 1.0
    for j in range(16):
        arterial.append(value)
        value *= 0.5
        k.append(0.01 * (1.0 / (1.0 + Float64(j))))
    var tissue = _exact(arterial, k, 1.5)
    var full = Deconvolution(arterial, _step(), 0.01)
    assert_equal(full.kept, 16)
    var back = full.residue(tissue)
    for at in range(16):
        assert_almost_equal(back[at], k[at], atol=1e-15, rtol=0)
    var fit = full.fit(tissue)
    _close(fit.flow.to(PER_SECOND), 0.01, 1e-13)
    assert_equal(fit.tmax.to(SECOND), 0.0)
    # A delay of 3 frames moves Tmax by 4.5 s. The circular deconvolution
    # keeps the flow. The lower triangular one loses 0.4 percent of it.
    # The curves end by frame 10, so a delay of 3 frames is a shift.
    var gamma = List[Float64](length=16, fill=0.0)
    var residue = List[Float64](length=16, fill=0.0)
    for j in range(6):
        var t = Float64(j)
        gamma[j] = t * t * 0.6**j
        residue[j] = 0.01 * 0.7**j
    var early = _exact(gamma, residue, 1.5)
    assert_equal(early[13], 0.0)
    var late = List[Float64](length=3, fill=0.0)
    for j in range(13):
        late.append(early[j])
    var circular = Deconvolution.circular(gamma, _step(), 0.1)
    var a = circular.fit(early)
    var b = circular.fit(late)
    _close(b.flow.to(PER_SECOND), a.flow.to(PER_SECOND), 1e-11)
    _close(b.tmax.to(SECOND) - a.tmax.to(SECOND), 4.5, 1e-15)
    var lower = Deconvolution(gamma, _step(), 0.1)
    assert_true(
        lower.fit(late).flow.to(PER_SECOND)
        < 0.999 * lower.fit(early).flow.to(PER_SECOND)
    )


def test_units() raises:
    var fit = PerfusionFit(
        Frequency64(0.01, PER_SECOND), 0.05, Duration64(3, SECOND)
    )
    # CBF = 0.01 / s x (0.55 / 0.75) / 1.04 g/mL, in mL/100 g/min.
    _close(
        fit.blood_flow(_density(), HEMATOCRIT_FACTOR).to(
            MILLILITER_PER_100_GRAM_PER_MINUTE
        ),
        0.01 * 6000.0 * (0.55 / 0.75) / 1.04,
        1e-14,
    )
    _close(
        fit.blood_volume(_density(), HEMATOCRIT_FACTOR).to(
            MILLILITER_PER_100_GRAM
        ),
        5.0 * (0.55 / 0.75) / 1.04,
        1e-14,
    )
    _close(fit.mtt().to(SECOND), 5.0, 1e-15)


def _grid(n: Int) raises -> ImageVolume:
    var step = Length64(2.0, MILLIMETER64)
    return ImageVolume(n, 1, 1, step, step, step)


def test_maps() raises:
    var arterial = ct_concentration(_rows(DATA, "arterial")[0], 4)
    var tissues = _rows(DATA, "tissue")
    var deconvolution = Deconvolution(arterial, _step(), 0.2)
    # Five voxels: the four tissues, and one outside the label.
    var series = List[ImageVolume]()
    for frame in range(40):
        var volume = _grid(5)
        for v in range(4):
            volume.values[v] = Float32(tissues[v][frame])
        volume.values[4] = Float32(40.0)
        series.append(volume^)
    var concentration = ct_concentration_series(series, 4)
    var map = LabelMap(series[0])
    for v in range(4):
        map.labels[v] = 1
    var maps = perfusion_maps(
        concentration,
        deconvolution,
        map,
        LabelId(1),
        _density(),
        HEMATOCRIT_FACTOR,
    )
    for v in range(4):
        var curve = List[Float64]()
        for frame in range(40):
            curve.append(Float64(concentration[frame].values[v]))
        var fit = deconvolution.fit(curve)
        _close(
            Float64(maps.cbf.values[v]),
            fit.blood_flow(_density(), HEMATOCRIT_FACTOR).to(
                MILLILITER_PER_100_GRAM_PER_MINUTE
            ),
            1e-6,
        )
        _close(Float64(maps.tmax.values[v]), fit.tmax.to(SECOND), 1e-7)
        _close(Float64(maps.mtt.values[v]), fit.mtt().to(SECOND), 1e-6)
        _close(
            Float64(maps.cbv.values[v]),
            fit.blood_volume(_density(), HEMATOCRIT_FACTOR).to(
                MILLILITER_PER_100_GRAM
            ),
            1e-6,
        )
    assert_equal(maps.cbf.values[4], 0)
    # A curve with no enhancement has no flow above 0, and no MTT.
    var empty = List[ImageVolume]()
    for _ in range(40):
        empty.append(_grid(5))
    var flat = perfusion_maps(
        empty, deconvolution, map, LabelId(1), _density(), 1.0
    )
    assert_equal(flat.cbf.values[0], 0)
    assert_equal(flat.mtt.values[0], 0)


def test_mismatch() raises:
    var maps = PerfusionMaps(_grid(6))
    var cbf: List[Float32] = [50, 10, 14, 20, 40, 5]
    var tmax: List[Float32] = [1, 12, 9, 7, 3, 2]
    for v in range(6):
        maps.cbf.values[v] = cbf[v]
        maps.tmax.values[v] = tmax[v]
    var map = LabelMap(maps.cbf)
    for v in range(5):
        map.labels[v] = 1
    var reference = BloodFlow64(50, MILLILITER_PER_100_GRAM_PER_MINUTE)
    var found = perfusion_mismatch(
        maps, map, LabelId(1), reference, 0.3, Duration64(6, SECOND)
    )
    # Voxels of 8 mm^3: two below 15 are core, three above 6 s at risk.
    _close(found.core.to(CUBIC_METER), 16e-9, 1e-12)
    _close(found.hypoperfused.to(CUBIC_METER), 24e-9, 1e-12)
    _close(found.ratio(), 1.5, 1e-12)
    _close(found.difference().to(CUBIC_METER), 8e-9, 1e-9)
    var none = perfusion_mismatch(
        maps, map, LabelId(1), reference, 0.05, Duration64(6, SECOND)
    )
    with assert_raises(contains="core above 0"):
        _ = none.ratio()


def test_errors() raises:
    var curve: List[Float64] = [0.0, 1.0, 2.0, 1.0]
    with assert_raises(contains="from 1 frame"):
        _ = ct_concentration(curve, 0)
    with assert_raises(contains="from 1 frame"):
        _ = ct_concentration(curve, 5)
    with assert_raises(contains="finite values"):
        _ = ct_concentration([1.0, nan[DType.float64]()], 1)
    var te = Duration64(30, MILLISECOND64)
    with assert_raises(contains="echo time"):
        _ = dsc_concentration([1.0, 2.0], 1, Duration64(0, SECOND))
    with assert_raises(contains="echo time"):
        _ = dsc_concentration(
            [1.0, 2.0], 1, Duration64(inf[DType.float64](), SECOND)
        )
    with assert_raises(contains="positive and finite"):
        _ = dsc_concentration([1.0, 0.0], 1, te)
    with assert_raises(contains="positive and finite"):
        _ = dsc_concentration([1.0, inf[DType.float64]()], 1, te)
    with assert_raises(contains="from 2 to 128"):
        _ = Deconvolution([1.0], _step(), 0.2)
    with assert_raises(contains="from 2 to 128"):
        _ = Deconvolution(List[Float64](length=129, fill=1.0), _step(), 0.2)
    var steps: List[Float64] = [0.0, inf[DType.float64]()]
    for s in steps:
        with assert_raises(contains="step"):
            _ = Deconvolution(curve, Duration64(s, SECOND), 0.2)
    var thresholds: List[Float64] = [0.0, 1.0, nan[DType.float64]()]
    for t in thresholds:
        with assert_raises(contains="threshold"):
            _ = Deconvolution.circular(curve, _step(), t)
    with assert_raises(contains="finite values"):
        _ = Deconvolution([1.0, inf[DType.float64]()], _step(), 0.2)
    with assert_raises(contains="sum above 0"):
        _ = Deconvolution([1.0, -1.0], _step(), 0.2)
    var deconvolution = Deconvolution(curve, _step(), 0.2)
    with assert_raises(contains="one value for each frame"):
        _ = deconvolution.residue([1.0])
    with assert_raises(contains="finite values"):
        _ = deconvolution.fit([1.0, 1.0, 1.0, nan[DType.float64]()])
    var fit = PerfusionFit(
        Frequency64(0, PER_SECOND), 0.05, Duration64(0, SECOND)
    )
    with assert_raises(contains="flow above 0"):
        _ = fit.mtt()
    var densities: List[Float64] = [0.0, inf[DType.float64]()]
    for d in densities:
        with assert_raises(contains="density"):
            _ = fit.blood_flow(Density64(d, GRAM_PER_CUBIC_CENTIMETER), 1.0)
    var factors: List[Float64] = [0.0, inf[DType.float64]()]
    for f in factors:
        with assert_raises(contains="hematocrit"):
            _ = fit.blood_volume(_density(), f)
    var series = List[ImageVolume]()
    for _ in range(4):
        series.append(_grid(2))
    var other = series.copy()
    other[2] = _grid(3)
    var step = Length64(2.0, MILLIMETER64)
    var sizes = [(3, 1, 1), (2, 2, 1), (2, 1, 2)]
    for size in sizes:
        var odd = series.copy()
        odd[2] = ImageVolume(size[0], size[1], size[2], step, step, step)
        with assert_raises(contains="different grids"):
            _ = ct_concentration_series(odd, 2)
    with assert_raises(contains="from 1 frame"):
        _ = ct_concentration_series(series, 0)
    var map = LabelMap(series[0])
    with assert_raises(contains="not the background"):
        _ = perfusion_maps(
            series, deconvolution, map, LabelId(0), _density(), 1.0
        )
    with assert_raises(contains="one volume for each frame"):
        _ = perfusion_maps(
            List[ImageVolume](series[0:3]),
            deconvolution,
            map,
            LabelId(1),
            _density(),
            1.0,
        )
    with assert_raises(contains="different grids"):
        _ = perfusion_maps(
            other, deconvolution, map, LabelId(1), _density(), 1.0
        )
    with assert_raises(contains="density"):
        _ = perfusion_maps(
            series,
            deconvolution,
            map,
            LabelId(1),
            Density64(0, GRAM_PER_CUBIC_CENTIMETER),
            1.0,
        )
    var maps = PerfusionMaps(series[0])
    var reference = BloodFlow64(50, MILLILITER_PER_100_GRAM_PER_MINUTE)
    var six = Duration64(6, SECOND)
    with assert_raises(contains="not the background"):
        _ = perfusion_mismatch(maps, map, LabelId(0), reference, 0.3, six)
    with assert_raises(contains="different grids"):
        _ = perfusion_mismatch(
            maps, LabelMap(_grid(3)), LabelId(1), reference, 0.3, six
        )
    var flows: List[Float64] = [0.0, inf[DType.float64]()]
    for f in flows:
        with assert_raises(contains="reference CBF"):
            _ = perfusion_mismatch(
                maps,
                map,
                LabelId(1),
                BloodFlow64(f, MILLILITER_PER_100_GRAM_PER_MINUTE),
                0.3,
                six,
            )
    var shares: List[Float64] = [0.0, 1.0]
    for s in shares:
        with assert_raises(contains="core share"):
            _ = perfusion_mismatch(maps, map, LabelId(1), reference, s, six)
    var limits: List[Float64] = [0.0, inf[DType.float64]()]
    for t in limits:
        with assert_raises(contains="Tmax threshold"):
            _ = perfusion_mismatch(
                maps, map, LabelId(1), reference, 0.3, Duration64(t, SECOND)
            )


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
