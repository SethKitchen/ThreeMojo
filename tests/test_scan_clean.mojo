# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Tests for `extensions.scan.clean`: leaving out the sky, the floaters and
the faint splats of a scan, and copying a subset of splats.

The site of `tests/_scan_site.mojo` is the scan. A few splats are added that
each break one rule: one far outside, one faint, and one huge.
"""

from core.gaussian_splat_utils import (
    GaussianSplatGeometry,
    create_gaussian_splat_geometry,
    sh_band_words,
)
from extensions.scan.clean import (
    CleanOptions,
    clean_scan,
    default_clean_options,
    splat_subset,
)
from extensions.scan.frame import SCAN_POSITIVE_Z
from std.math import nan
from std.testing import (
    TestSuite,
    assert_equal,
    assert_raises,
    assert_true,
)
from tests._scan_site import GROUND, site_scan


def _with_strays() raises -> GaussianSplatGeometry:
    """Return the site with three strays after its own splats: a splat 500 m
    outside, a splat that is faint, and a splat 60 m long."""
    var site = site_scan(SCAN_POSITIVE_Z, True)
    var centers = site.centers.copy()
    var covariances = site.covariances.copy()
    var colors = site.colors.copy()
    var strays: List[Float32] = [500, 5, 5, 8, 8, 1, 12, 12, 1]
    centers.extend(strays^)
    var thin: List[Float32] = [0.01, 0, 0, 0.01, 0, 0.01]
    var huge: List[Float32] = [400, 0, 0, 400, 0, 400]
    covariances.extend(thin.copy())
    covariances.extend(thin.copy())
    covariances.extend(huge.copy())
    var bytes: List[UInt8] = [
        200,
        200,
        200,
        255,
        200,
        200,
        200,
        3,
        200,
        200,
        200,
        255,
    ]
    colors.extend(bytes^)
    return create_gaussian_splat_geometry(centers^, covariances^, colors^)


def test_each_rule_leaves_out_its_own_splats() raises:
    """The stray outside, the faint one and the huge one are left out, once
    each, and the site is kept."""
    var scan = _with_strays()
    var cleaned = clean_scan(scan, default_clean_options())
    assert_equal(cleaned.report.outside, 1)
    assert_equal(cleaned.report.faint, 1)
    assert_equal(cleaned.report.huge, 1)
    assert_equal(cleaned.report.kept, scan.count() - 3)
    assert_equal(cleaned.geometry.count(), scan.count() - 3)


def test_a_stray_below_the_site_is_outside_too() raises:
    """A splat far below the site is left out, as one far above is."""
    var site = site_scan(SCAN_POSITIVE_Z, True)
    var centers = site.centers.copy()
    var covariances = site.covariances.copy()
    var colors = site.colors.copy()
    var stray: List[Float32] = [-500, 5, 5]
    centers.extend(stray^)
    var thin: List[Float32] = [0.01, 0, 0, 0.01, 0, 0.01]
    covariances.extend(thin^)
    var opaque: List[UInt8] = [200, 200, 200, 255]
    colors.extend(opaque^)
    var scan = create_gaussian_splat_geometry(centers^, covariances^, colors^)
    var cleaned = clean_scan(scan, default_clean_options())
    assert_equal(cleaned.report.outside, 1)
    assert_equal(cleaned.report.kept, scan.count() - 1)


def test_a_looser_rule_keeps_more() raises:
    """With no opacity limit and a huge allowance, only the outside stray
    goes."""
    var scan = _with_strays()
    var cleaned = clean_scan(scan, CleanOptions(0.005, 0.1, 0.0, 100.0))
    assert_equal(cleaned.report.outside, 1)
    assert_equal(cleaned.report.faint, 0)
    assert_equal(cleaned.report.huge, 0)


def test_options_must_describe_a_clean() raises:
    """Each number is checked."""
    with assert_raises(contains="the trim must be finite"):
        _ = clean_scan(
            _with_strays(), CleanOptions(nan[DType.float64](), 0.1, 0.1, 0.1)
        )
    with assert_raises(contains="the margin must be finite"):
        _ = clean_scan(
            _with_strays(), CleanOptions(0.0, nan[DType.float64](), 0.1, 0.1)
        )
    with assert_raises(contains="the opacity must be finite"):
        _ = clean_scan(
            _with_strays(), CleanOptions(0.0, 0.1, nan[DType.float64](), 0.1)
        )
    with assert_raises(contains="the extent must be finite"):
        _ = clean_scan(
            _with_strays(), CleanOptions(0.0, 0.1, 0.1, nan[DType.float64]())
        )
    with assert_raises(contains="the trim is 0 up to 0.5"):
        _ = clean_scan(_with_strays(), CleanOptions(0.5, 0.1, 0.1, 0.1))
    with assert_raises(contains="the trim is 0 up to 0.5"):
        _ = clean_scan(_with_strays(), CleanOptions(-0.1, 0.1, 0.1, 0.1))
    with assert_raises(contains="the margin is 0 or more"):
        _ = clean_scan(_with_strays(), CleanOptions(0.0, -0.1, 0.1, 0.1))
    with assert_raises(contains="the opacity is 0 to 1"):
        _ = clean_scan(_with_strays(), CleanOptions(0.0, 0.1, 1.5, 0.1))
    with assert_raises(contains="the opacity is 0 to 1"):
        _ = clean_scan(_with_strays(), CleanOptions(0.0, 0.1, -0.5, 0.1))
    with assert_raises(contains="the extent must be positive"):
        _ = clean_scan(_with_strays(), CleanOptions(0.0, 0.1, 0.1, 0.0))


def test_a_scan_with_nothing_to_keep_is_refused() raises:
    """No splat at all, and no splat that passes, are errors."""
    with assert_raises(contains="the scan has no splat"):
        _ = clean_scan(GaussianSplatGeometry(), default_clean_options())
    var centers: List[Float32] = [0, 0, 0]
    var covariances: List[Float32] = [0.01, 0, 0, 0.01, 0, 0.01]
    var colors: List[UInt8] = [200, 200, 200, 2]
    var faint = create_gaussian_splat_geometry(centers^, covariances^, colors^)
    with assert_raises(contains="no splat is kept"):
        _ = clean_scan(faint, default_clean_options())


def test_a_subset_keeps_each_splat_and_its_harmonics() raises:
    """The chosen splats come out in the order given, with their bytes."""
    var count = 5
    var centers = List[Float32]()
    var covariances = List[Float32]()
    var colors = List[UInt8]()
    for i in range(count):
        var at: List[Float32] = [Float32(i), Float32(10 * i), Float32(100 * i)]
        centers.extend(at^)
        var spread: List[Float32] = [1, 0, 0, 1, 0, 1]
        covariances.extend(spread^)
        var color: List[UInt8] = [UInt8(i), 2, 3, 4]
        colors.extend(color^)
    var degree_one = List[UInt8]()
    for i in range(count):
        for n in range(sh_band_words(1) * 4):
            degree_one.append(UInt8(i * 16 + n))
    var scan = create_gaussian_splat_geometry(
        centers^, covariances^, colors^, degree_one^
    )
    var picked = splat_subset(scan, [3, 1])
    assert_equal(picked.count(), 2)
    assert_equal(picked.centers[0], 3.0)
    assert_equal(picked.centers[4], 10.0)
    assert_equal(picked.colors[0], 3)
    assert_equal(picked.colors[4], 1)
    assert_equal(picked.spherical_harmonics_degree(), 1)
    assert_equal(picked.sh1[0], 48)
    assert_equal(picked.sh1[sh_band_words(1) * 4], 16)
    with assert_raises(contains="splat 5 is not there"):
        _ = splat_subset(scan, [5])
    with assert_raises(contains="splat -1 is not there"):
        _ = splat_subset(scan, [-1])


def test_the_defaults_suit_a_building() raises:
    """The default rules are the ones the module docstring names."""
    var options = default_clean_options()
    assert_equal(options.trim, 0.005)
    assert_equal(options.margin, 0.15)
    assert_equal(options.min_opacity, 0.05)
    assert_equal(options.max_extent, 0.05)
    assert_true(GROUND > 0)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
