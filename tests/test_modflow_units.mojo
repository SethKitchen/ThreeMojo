# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Check the small functions of the MODFLOW 6 port with chosen values.

The reference cases reach most branches of these functions. These tests
reach the rest: the zero, the edge and the degenerate inputs.
"""

from std.math import sqrt
from std.os import remove, rmdir
from std.os.path import join
from std.pathlib import Path
from std.tempfile import mkdtemp
from std.testing import TestSuite, assert_equal, assert_false, assert_true

from extensions.groundwater.blocks import InputFile
from extensions.groundwater.cmath import cstrtod, fsign, is_close, powi
from extensions.groundwater.conductance import (
    CCOND_AMTHMK,
    CCOND_AMTLMK,
    CCOND_HMEAN,
    CCOND_LMEAN,
    condmean,
    hcond,
    logmean,
    vcond,
)
from extensions.groundwater.ims import (
    ImsLinear,
    LinearSettings,
    dnrm2,
    testcnvg,
)
from extensions.groundwater.kinds import (
    BoundaryKind,
    CellAveraging,
    InnerConvergence,
    LinearAcceleration,
    Preconditioner,
    Reordering,
    SCALING_L2NORM,
    BICGSTAB,
    Scaling,
    UnderRelaxation,
)
from extensions.groundwater.npf import hyeff
from extensions.groundwater.smoothing import (
    squadratic_saturation,
    squadratic_saturation_derivative,
)


def test_kinds_are_checked() raises:
    """Each kind accepts its own values and no other."""
    assert_true(BoundaryKind(6).is_valid())
    assert_false(BoundaryKind(7).is_valid())
    assert_true(UnderRelaxation(3).is_valid())
    assert_false(UnderRelaxation(-1).is_valid())
    assert_true(LinearAcceleration(2).is_valid())
    assert_false(LinearAcceleration(0).is_valid())
    assert_true(Preconditioner(4).is_valid())
    assert_false(Preconditioner(5).is_valid())
    assert_true(Scaling(2).is_valid())
    assert_false(Scaling(3).is_valid())
    assert_true(Reordering(2).is_valid())
    assert_false(Reordering(3).is_valid())
    assert_true(InnerConvergence(4).is_valid())
    assert_false(InnerConvergence(5).is_valid())
    assert_true(CellAveraging(3).is_valid())
    assert_false(CellAveraging(4).is_valid())


def test_c_math() raises:
    """`powi` takes a negative exponent, and `is_close` an exact match."""
    assert_equal(powi(2.0, -3), 0.125)
    assert_equal(powi(3.0, 0), 1.0)
    assert_true(is_close(1.5, 1.5))
    assert_false(is_close(1.0, 1.1))
    assert_equal(fsign(2.0, -0.0), -2.0)
    var used = 7
    _ = cstrtod("", used)
    assert_equal(used, 0)


def test_saturation_of_a_flat_cell() raises:
    """A cell of no thickness is empty under its bottom and full above it."""
    assert_equal(squadratic_saturation(5.0, 5.0, 4.0), 0.0)
    assert_equal(squadratic_saturation(5.0, 5.0, 6.0), 1.0)


def test_saturation_near_the_top() raises:
    """The top quadratic piece has a saturation and a slope under 1."""
    var s = squadratic_saturation(10.0, 0.0, 10.0 - 1.0e-6, 1.0e-3)
    assert_true(s < 1.0 and s > 0.999)
    var d = squadratic_saturation_derivative(10.0, 0.0, 10.0 - 1.0e-6, 1.0e-3)
    assert_true(d > 0.0 and d < 0.1)
    assert_equal(squadratic_saturation_derivative(10.0, 0.0, 11.0), 0.0)


def test_horizontal_conductance() raises:
    """A confined cell beside a convertible one, and equal upstream heads."""
    var c = hcond(
        1,
        1,
        0,
        1,
        0,
        0,
        9.0,
        5.0,
        4.0,
        1.0,
        0.5,
        2.0,
        2.0,
        10.0,
        10.0,
        0.0,
        0.0,
        5.0,
        5.0,
        10.0,
    )
    assert_true(abs(c - 10.0 * 20.0 * 10.0 / (20.0 * 5.0 + 10.0 * 5.0)) < 1e-12)
    assert_equal(
        hcond(
            1,
            1,
            1,
            1,
            1,
            0,
            8.0,
            5.0,
            5.0,
            0.25,
            0.5,
            1.0,
            1.0,
            10.0,
            10.0,
            0.0,
            0.0,
            5.0,
            5.0,
            10.0,
        ),
        4.0,
    )
    assert_equal(
        hcond(
            1,
            0,
            1,
            1,
            0,
            0,
            8.0,
            5.0,
            5.0,
            1.0,
            1.0,
            1.0,
            1.0,
            10.0,
            10.0,
            0.0,
            0.0,
            5.0,
            5.0,
            10.0,
        ),
        0.0,
    )


def test_vertical_conductance() raises:
    """Each branch of `vcond`, with n under m as well as over it."""
    # m is dry.
    assert_equal(
        vcond(
            1,
            0,
            1,
            1,
            0,
            1,
            0,
            3.0,
            5.0,
            5.0,
            1.0,
            1.0,
            1.0,
            1.0,
            10.0,
            0.0,
            0.0,
            -10.0,
            100.0,
        ),
        0.0,
    )
    # n is confined and m is not: the saturations count.
    assert_equal(
        vcond(
            1,
            1,
            0,
            1,
            0,
            1,
            0,
            3.0,
            5.0,
            5.0,
            1.0,
            1.0,
            1.0,
            1.0,
            10.0,
            0.0,
            0.0,
            -10.0,
            100.0,
        ),
        10.0,
    )
    # n is full and m is not.
    var c = vcond(
        1,
        1,
        1,
        1,
        0,
        1,
        0,
        3.0,
        12.0,
        -2.0,
        1.0,
        1.0,
        1.0,
        0.8,
        10.0,
        0.0,
        0.0,
        -10.0,
        100.0,
    )
    assert_true(abs(c - 100.0 / 10.0) < 1e-12)
    # n under m: the saturation of n counts as full.
    c = vcond(
        1,
        1,
        1,
        1,
        0,
        1,
        0,
        3.0,
        -2.0,
        8.0,
        1.0,
        1.0,
        0.8,
        1.0,
        0.0,
        10.0,
        -10.0,
        0.0,
        100.0,
    )
    assert_true(abs(c - 100.0 / 10.0) < 1e-12)
    # DEWATERED: a partly full n under m conducts as empty.
    c = vcond(
        1,
        1,
        1,
        1,
        0,
        1,
        1,
        3.0,
        -2.0,
        8.0,
        1.0,
        1.0,
        0.8,
        1.0,
        0.0,
        10.0,
        -10.0,
        0.0,
        100.0,
    )
    assert_true(abs(c - 100.0 / 5.0) < 1e-12)
    c = vcond(
        1,
        1,
        1,
        1,
        0,
        1,
        1,
        3.0,
        -2.0,
        8.0,
        1.0,
        1.0,
        1.0,
        1.0,
        0.0,
        10.0,
        -10.0,
        0.0,
        100.0,
    )
    assert_true(abs(c - 100.0 / 10.0) < 1e-12)
    # DEWATERED over a partly full m, with n empty: no resistance is left.
    assert_equal(
        vcond(
            1,
            1,
            1,
            1,
            0,
            1,
            1,
            3.0,
            2.0,
            -2.0,
            1.0,
            1.0,
            0.0,
            0.8,
            10.0,
            0.0,
            0.0,
            -10.0,
            100.0,
        ),
        0.0,
    )


def test_conductance_means_of_empty_cells() raises:
    """Each mean gives zero when a cell has no transmissivity."""
    assert_equal(condmean(1.0, 2.0, 0.0, 3.0, 5.0, 5.0, 10.0, CCOND_HMEAN), 0.0)
    assert_equal(condmean(1.0, 2.0, 0.0, 3.0, 5.0, 5.0, 10.0, CCOND_LMEAN), 0.0)
    assert_equal(
        condmean(0.0, 2.0, 1.0, 3.0, 5.0, 5.0, 10.0, CCOND_AMTLMK), 0.0
    )
    assert_equal(
        condmean(0.0, 0.0, 1.0, 3.0, 5.0, 5.0, 10.0, CCOND_AMTHMK), 0.0
    )
    assert_equal(logmean(2.0, 2.0), 2.0)
    assert_true(abs(logmean(1.0, 3.0) - 2.0 / 1.0986122886681098) < 1e-12)


def test_conductivity_in_a_direction() raises:
    """`hyeff` along a principal axis, with no conductivity, and arithmetic."""
    assert_equal(hyeff(2.0, 3.0, 4.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0), 2.0)
    assert_equal(hyeff(2.0, 3.0, 4.0, 0.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0), 3.0)
    assert_equal(hyeff(2.0, 3.0, 4.0, 0.0, 0.0, 0.0, 0.0, 0.0, 1.0, 0), 4.0)
    var r = sqrt(0.5)
    assert_equal(hyeff(0.0, 0.0, 0.0, 0.0, 0.0, 0.0, r, r, 0.0, 0), 0.0)
    var k = hyeff(2.0, 3.0, 4.0, 0.0, 0.0, 0.0, r, r, 0.0, 1)
    assert_true(abs(k - 2.5) < 1e-12)


def test_norm_of_short_vectors() raises:
    """The norm of no entries, of one entry, and of zeros."""
    var x: List[Float64] = [0.0, -3.0, 0.0, 4.0]
    assert_equal(dnrm2(0, x), 0.0)
    assert_equal(dnrm2(1, x), 3.0)
    assert_equal(dnrm2(3, x), 5.0)
    var z: List[Float64] = [0.0, 0.0, 0.0]
    assert_equal(dnrm2(2, z), 0.0)


def test_inner_convergence() raises:
    """Each outcome of each inner convergence test."""
    # opt, iiter, dvmax, rmax, rmax0, ep, want
    var rows: List[Float64] = [
        0,
        1,
        0.1,
        0.1,
        1.0,
        0.1,
        0,
        0,
        1,
        0.0,
        0.0,
        1.0,
        0.1,
        1,
        0,
        1,
        0.0,
        0.1,
        1.0,
        0.1,
        0,
        1,
        1,
        0.0,
        0.0,
        1.0,
        0.1,
        1,
        1,
        2,
        0.0,
        0.0,
        1.0,
        0.1,
        -1,
        1,
        1,
        0.0,
        0.1,
        1.0,
        0.1,
        0,
        2,
        1,
        0.0,
        0.1,
        1.0,
        0.1,
        1,
        2,
        1,
        0.1,
        0.0,
        1.0,
        0.1,
        1,
        2,
        1,
        0.1,
        0.05,
        1.0,
        0.1,
        -1,
        2,
        1,
        0.1,
        0.5,
        1.0,
        0.1,
        0,
        3,
        1,
        0.0,
        0.5,
        1.0,
        0.1,
        1,
        3,
        1,
        0.1,
        0.005,
        1.0,
        0.1,
        -1,
        3,
        1,
        0.1,
        0.5,
        1.0,
        0.1,
        0,
        4,
        1,
        0.0,
        0.0,
        1.0,
        0.1,
        1,
        4,
        1,
        0.0,
        0.05,
        1.0,
        0.1,
        -1,
        4,
        1,
        0.1,
        0.005,
        1.0,
        0.001,
        0,
        4,
        1,
        0.1,
        0.5,
        1.0,
        0.1,
        0,
    ]
    for i in range(0, len(rows), 7):
        var icnvg = 0
        testcnvg(
            Int(rows[i]),
            icnvg,
            Int(rows[i + 1]),
            rows[i + 2],
            rows[i + 3],
            rows[i + 4],
            rows[i + 5],
            0.01,
            0.01,
        )
        assert_equal(icnvg, Int(rows[i + 6]), String("row ", i // 7))


def _solver(relax: Float64) raises -> ImsLinear:
    """Return a solver of three equations in which row 1 joins rows 2 and 3.

    Rows 2 and 3 do not join each other, so the fill between them drops.

    Args:
        relax: The relaxation factor of MILU0.

    Returns:
        The solver.

    Raises:
        Error: The settings are out of range.
    """
    var s = LinearSettings(1)
    s.relax = relax
    var ia: List[Int] = [0, 1, 4, 6, 8]
    var ja: List[Int] = [0, 1, 2, 3, 2, 1, 3, 1]
    return ImsLinear(s^, ia, ja)


def test_a_zero_pivot_becomes_small() raises:
    """A zero pivot stays zero as the diagonal grows, so the tenth try sets it.
    """
    var ims = _solver(0.0)
    var a: List[Float64] = [0.0, 0.0, 1.0, 1.0, 1.0, 1.0, 1.0, 1.0]
    ims._pcu(a)
    assert_true(abs(ims.apc[1] - 1.0e6) < 1.0e-3)


def test_a_pivot_of_the_wrong_sign_becomes_small() raises:
    """MILU0 moves the dropped fill to the diagonal, and that flips a pivot."""
    var ims = _solver(1.0)
    var a: List[Float64] = [0.0, 1.0, 1.0, 1.0, 1.5, 1.0, 1.5, 1.0]
    ims._pcu(a)
    assert_true(abs(ims.apc[2] - 1.0e6) < 1.0e-3)


def test_scaling_of_a_zero_row_and_column() raises:
    """L2NORM scaling leaves a row and a column of zeros unscaled."""
    var s = LinearSettings(1)
    s.iscl = SCALING_L2NORM
    s.ilinmeth = BICGSTAB
    s.iter1 = 3
    var ia: List[Int] = [0, 1, 3, 5]
    var ja: List[Int] = [0, 1, 2, 2, 1]
    var ims = ImsLinear(s^, ia, ja)
    var a: List[Float64] = [0.0, 0.0, 0.0, 2.0, 0.0]
    var b: List[Float64] = [0.0, 0.0, 4.0]
    var x: List[Float64] = [0.0, 0.0, 0.0]
    _ = ims.apply(a, b, x, 1)
    assert_equal(ims.dscale[1], 1.0)
    assert_equal(ims.dscale2[1], 1.0)
    assert_equal(a[3], 2.0)


def test_an_empty_file_has_no_blocks() raises:
    """An empty input file has no block of any name."""
    var folder = mkdtemp(prefix="modflow-units-")
    var path = join(folder, "empty.txt")
    Path(path).write_text("")
    var file = InputFile(folder, "empty.txt")
    remove(path)
    rmdir(folder)
    assert_equal(len(file.find_all("PERIOD")), 0)
    assert_equal(file.find("OPTIONS"), -1)


def test_cg_with_each_l2_norm_test() raises:
    """CG takes the L2 norm of the residual for the three L2 norm tests."""
    for opt in range(2, 5):
        var s = LinearSettings(1)
        s.icnvgopt = InnerConvergence(opt)
        var ia: List[Int] = [0, 1, 3, 5]
        var ja: List[Int] = [0, 1, 2, 2, 1]
        var ims = ImsLinear(s^, ia, ja)
        var a: List[Float64] = [0.0, 2.0, -1.0, 2.0, -1.0]
        var b: List[Float64] = [0.0, 1.0, 1.0]
        var x: List[Float64] = [0.0, 0.0, 0.0]
        var r = ims.apply(a, b, x, 1)
        assert_equal(r[0], 1, String("opt ", opt))
        assert_true(abs(x[1] - 1.0) < 1.0e-2 and abs(x[2] - 1.0) < 1.0e-2)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
