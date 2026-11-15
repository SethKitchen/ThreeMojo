# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""ROC curves, AUC and DeLong's test.

`assets/roc/roc_expected.txt` holds the results of scikit-learn 1.9.1 and
MLstatkit 0.1.91 on the synthetic markers of `assets/roc/markers.txt`. See
`assets/roc/make_roc.py`.
"""

from extensions.clinical.roc import (
    RocCurve,
    compare_roc,
    roc_curve,
    roc_image,
)
from extensions.imaging.transfer import Rgba
from render.framebuffer import Framebuffer
from std.math import inf, isinf, nan, sqrt
from std.testing import (
    TestSuite,
    assert_almost_equal,
    assert_equal,
    assert_raises,
    assert_true,
)


def _numbers(line: String) raises -> List[Float64]:
    var out = List[Float64]()
    var first = True
    for part in line.split(" "):
        if first:
            first = False
            continue
        out.append(atof(String(part)))
    return out^


def _markers() raises -> Tuple[List[Float64], List[Float64], List[Bool]]:
    var a = List[Float64]()
    var b = List[Float64]()
    var sick = List[Bool]()
    var text = open("assets/roc/markers.txt", "r").read()
    for line in text.splitlines():
        var words = String(line).split(" ")
        sick.append(String(words[0]) == "1")
        a.append(atof(String(words[1])))
        b.append(atof(String(words[2])))
    return (a^, b^, sick^)


def test_markers() raises:
    var data = _markers()
    var lines = open("assets/roc/roc_expected.txt", "r").read().splitlines()
    var curve_a = _numbers(String(lines[0]))
    var auc = _numbers(String(lines[1]))
    var delong = _numbers(String(lines[2]))
    var youden = _numbers(String(lines[3]))
    var a = roc_curve(data[0], data[2])
    var b = roc_curve(data[1], data[2])
    assert_equal(a.diseased, 60)
    assert_equal(a.healthy, 90)
    var count = Int(curve_a[0])
    assert_equal(len(a.thresholds), count)
    assert_true(isinf(a.thresholds[0]))
    for i in range(count):
        if i > 0:
            assert_equal(a.thresholds[i], curve_a[1 + 3 * i])
        assert_equal(a.false_positive_rate[i], curve_a[2 + 3 * i])
        assert_equal(a.sensitivity[i], curve_a[3 + 3 * i])
    assert_almost_equal(a.auc, auc[0], rtol=1e-15)
    assert_almost_equal(b.auc, auc[1], rtol=1e-15)
    var band_a = a.interval()
    var band_b = b.interval()
    assert_almost_equal(band_a[0], delong[2], rtol=1e-13)
    assert_almost_equal(band_a[1], delong[3], rtol=1e-13)
    assert_almost_equal(band_b[0], delong[4], rtol=1e-13)
    assert_almost_equal(band_b[1], delong[5], rtol=1e-13)
    var test = compare_roc(data[0], data[1], data[2])
    assert_almost_equal(test.difference, auc[1] - auc[0], rtol=1e-14)
    assert_almost_equal(test.z, delong[0], rtol=1e-12)
    assert_almost_equal(test.p_value, delong[1], rtol=1e-11)
    assert_almost_equal(test.standard_error, sqrt(delong[6]), rtol=1e-12)
    var cut = a.youden()
    assert_equal(cut[0], youden[0])
    assert_equal(cut[1], youden[1])
    assert_equal(cut[2], youden[2])


def test_by_hand() raises:
    # Diseased 3, 2 and 2; healthy 2, 1 and 0. Of the nine pairs, seven
    # are higher and two tie: an AUC of 8/9.
    var scores: List[Float64] = [3.0, 2.0, 2.0, 2.0, 1.0, 0.0]
    var sick: List[Bool] = [True, True, True, False, False, False]
    var curve = roc_curve(scores, sick)
    assert_almost_equal(curve.auc, 8.0 / 9.0, rtol=1e-15)
    # The components of the diseased are 1, 5/6 and 5/6: squares about
    # 8/9 of 1/54, and a sample variance of 1/108. Those of the healthy
    # are 2/3, 1 and 1: squares of 2/27, and a sample variance of 1/27.
    var variance = (1.0 / 108.0) / 3.0 + (1.0 / 27.0) / 3.0
    assert_almost_equal(curve.standard_error, sqrt(variance), rtol=1e-14)
    assert_equal(len(curve.thresholds), 5)
    assert_equal(curve.sensitivity[2], 1.0)
    assert_almost_equal(curve.false_positive_rate[2], 1.0 / 3.0, rtol=1e-15)
    # The best cut is 2: all diseased, one of three healthy.
    var cut = curve.youden()
    assert_equal(cut[0], 2.0)
    # A perfect test: an AUC of 1, held to 1 at the top of its interval.
    var perfect = roc_curve([4.0, 3.0, 1.0, 0.0], [True, True, False, False])
    assert_equal(perfect.auc, 1.0)
    assert_equal(perfect.standard_error, 0.0)
    assert_equal(perfect.interval()[1], 1.0)
    # A test that is all ties has an AUC of a half, and a low end of 0
    # for two patients of each kind.
    var flat = roc_curve([1.0, 1.0, 1.0, 1.0], [True, False, True, False])
    assert_equal(flat.auc, 0.5)
    var tiny = roc_curve([0.0, 1.0, 1.0, 0.0], [True, True, False, False])
    assert_equal(tiny.interval()[0], 0.0)


def test_compare() raises:
    var scores: List[Float64] = [3.0, 2.0, 2.0, 2.0, 1.0, 0.0]
    var sick: List[Bool] = [True, True, True, False, False, False]
    # A test against itself: no difference and no variance.
    var same = compare_roc(scores, scores, sick)
    assert_equal(same.difference, 0.0)
    assert_equal(same.z, 0.0)
    assert_equal(same.p_value, 1.0)
    # A perfect test against a reversed one: a difference with no
    # variance.
    with assert_raises(contains="no variance"):
        _ = compare_roc(
            [4.0, 3.0, 1.0, 0.0],
            [0.0, 1.0, 3.0, 4.0],
            [True, True, False, False],
        )
    with assert_raises(contains="one score for each patient"):
        _ = compare_roc(scores, [1.0], sick)


def test_refusals() raises:
    with assert_raises(contains="one score for each patient"):
        _ = roc_curve(List[Float64](), List[Bool]())
    with assert_raises(contains="one score for each patient"):
        _ = roc_curve([1.0, 2.0], [True])
    var bad: List[Float64] = [inf[DType.float64](), nan[DType.float64]()]
    for b in bad:
        with assert_raises(contains="must be finite"):
            _ = roc_curve([1.0, b, 2.0, 3.0], [True, True, False, False])
    with assert_raises(contains="two diseased and two healthy"):
        _ = roc_curve([1.0, 2.0, 3.0], [True, False, False])
    with assert_raises(contains="two diseased and two healthy"):
        _ = roc_curve([1.0, 2.0, 3.0], [True, True, False])
    with assert_raises(contains="no Youden index"):
        _ = RocCurve().youden()


def _rgb(image: Framebuffer, x: Int, y: Int) -> Tuple[Int, Int, Int]:
    var at = (y * image.width + x) * 4
    return (
        Int(image.pixels[at]),
        Int(image.pixels[at + 1]),
        Int(image.pixels[at + 2]),
    )


def test_roc_image() raises:
    # A perfect test runs up the left edge and along the top edge.
    var perfect = roc_curve([4.0, 3.0, 1.0, 0.0], [True, True, False, False])
    var red = Rgba(1, 0, 0, 1)
    var curves = List[RocCurve]()
    curves.append(perfect^)
    var image = roc_image(curves, [red], 101)
    assert_true(_rgb(image, 0, 50) == (255, 0, 0))
    assert_true(_rgb(image, 50, 0) == (255, 0, 0))
    # The chance diagonal, and a grid line at a false positive rate of 0.3.
    assert_true(_rgb(image, 65, 35) == (153, 153, 161))
    assert_true(_rgb(image, 30, 55) == (214, 214, 219))
    assert_true(_rgb(image, 33, 55) == (255, 255, 255))
    var none = List[RocCurve]()
    with assert_raises(contains="one color for each"):
        _ = roc_image(none, List[Rgba](), 64)
    with assert_raises(contains="one color for each"):
        _ = roc_image(curves, List[Rgba](), 64)
    var sizes: List[Int] = [63, 4097]
    for s in sizes:
        with assert_raises(contains="pixels on a side"):
            _ = roc_image(curves, [red], s)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
