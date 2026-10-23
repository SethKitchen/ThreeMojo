# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Tests for `extensions.scan.orient`, the up axis of a scan.

A site of flat ground splats and a box of walls is laid out on each of the
six scan axes in turn, so the estimate is checked against an up that is
known. A site with no walls has no sign to read, and takes the default.
"""

from core.gaussian_splat_utils import (
    GaussianSplatGeometry,
    create_gaussian_splat_geometry,
)
from extensions.scan.frame import (
    SCAN_NEGATIVE_Y,
    SCAN_POSITIVE_X,
    SCAN_POSITIVE_Y,
    SCAN_POSITIVE_Z,
    ScanAxis,
)
from extensions.scan.orient import estimate_up, largest_variance
from std.math import sqrt
from std.testing import (
    TestSuite,
    assert_almost_equal,
    assert_equal,
    assert_raises,
    assert_true,
)
from tests._scan_site import site_scan


def test_the_ground_and_the_walls_give_each_of_the_six_axes() raises:
    """The up axis is found whichever scan axis the site stands on."""
    for value in range(6):
        var up = ScanAxis(value)
        var found = estimate_up(site_scan(up, True))
        assert_true(found.axis == up)
        # Ground 900 splats, walls 200: the ground holds most of the weight.
        assert_true(found.share > 0.5)
        assert_true(found.side > 0.9)


def test_a_site_with_no_walls_takes_the_default_sign() raises:
    """With no wall to say which side the building is on, y is down and the
    other axes are up."""
    var along_y = estimate_up(site_scan(SCAN_POSITIVE_Y, False))
    assert_true(along_y.axis == SCAN_NEGATIVE_Y)
    assert_equal(along_y.side, 0.0)
    var along_x = estimate_up(site_scan(SCAN_POSITIVE_X, False))
    assert_true(along_x.axis == SCAN_POSITIVE_X)
    assert_equal(along_x.side, 0.0)
    var along_z = estimate_up(site_scan(SCAN_POSITIVE_Z, False))
    assert_true(along_z.axis == SCAN_POSITIVE_Z)


def test_round_and_empty_splats_do_not_vote() raises:
    """A round splat is not flat, a needle has no middle length, and a splat
    with no extent has no normal; the flat ground still decides."""
    var site = site_scan(SCAN_POSITIVE_Z, True)
    var centers = site.centers.copy()
    var covariances = site.covariances.copy()
    var colors = site.colors.copy()
    # A round splat, a needle along x, and a splat with no extent.
    var more_centers: List[Float32] = [5, 5, 5, 6, 6, 6, 7, 7, 7]
    centers.extend(more_centers^)
    var more_covariances: List[Float32] = [
        1,
        0,
        0,
        1,
        0,
        1,
        1,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
    ]
    covariances.extend(more_covariances^)
    var more_colors = List[UInt8](length=12, fill=255)
    colors.extend(more_colors^)
    var found = estimate_up(
        create_gaussian_splat_geometry(centers^, covariances^, colors^)
    )
    assert_true(found.axis == SCAN_POSITIVE_Z)


def test_a_scan_with_no_flat_splat_has_no_up() raises:
    """Round splats give no normal, and no samples give no vote."""
    var centers: List[Float32] = [0, 0, 0, 1, 1, 1]
    var covariances: List[Float32] = [1, 0, 0, 1, 0, 1, 1, 0, 0, 1, 0, 1]
    var colors = List[UInt8](length=8, fill=255)
    var round = create_gaussian_splat_geometry(centers^, covariances^, colors^)
    with assert_raises(contains="no splat is flat"):
        _ = estimate_up(round)
    with assert_raises(contains="no splat is flat"):
        _ = estimate_up(GaussianSplatGeometry())
    with assert_raises(contains="at least one splat must vote"):
        _ = estimate_up(site_scan(SCAN_POSITIVE_Z, False), 0)


def test_samples_thin_the_vote_without_changing_it() raises:
    """A tenth of the splats find the same axis."""
    var up = ScanAxis(3)
    var found = estimate_up(site_scan(up, True), 100)
    assert_true(found.axis == up)


def test_the_largest_variance_is_the_longest_axis_squared() raises:
    """A diagonal covariance and a turned one give their largest root."""
    var diagonal: List[Float32] = [4, 0, 0, 9, 0, 1]
    assert_almost_equal(largest_variance(diagonal, 0), 9.0, atol=1e-9)
    # The matrix [[5, 4], [4, 5]] in x and y has the eigenvalues 9 and 1.
    var turned: List[Float32] = [5, 4, 0, 5, 0, 2]
    assert_almost_equal(largest_variance(turned, 0), 9.0, atol=1e-9)
    var none: List[Float32] = [0, 0, 0, 0, 0, 0]
    assert_equal(largest_variance(none, 0), 0.0)
    assert_true(sqrt(largest_variance(turned, 0)) > 2.9)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
