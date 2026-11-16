# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""The double-double survival references keep their expected files current.

`tools/reference_parametric.mojo` and `tools/reference_aft.mojo` must give
the committed `parametric_expected.txt` and `aft_expected.txt` byte for
byte, from the committed data. Their values equal those of the mpmath
fits at 40 digits that they replace, to the last bit of each double.
"""

from std.testing import TestSuite, assert_equal, assert_raises

from tools.reference_aft import fit, groups
from tools.reference_aft import reference as aft_reference
from tools.reference_parametric import probes
from tools.reference_parametric import reference as parametric_reference


def test_the_parametric_file_is_current() raises:
    var data = open("assets/parametric/parametric_data.txt", "r").read()
    var expected = open("assets/parametric/parametric_expected.txt", "r").read()
    assert_equal(parametric_reference(data), expected)


def test_the_aft_file_is_current() raises:
    var data = open("assets/aft/aft_cohort.txt", "r").read()
    var expected = open("assets/aft/aft_expected.txt", "r").read()
    assert_equal(aft_reference(data), expected)


def test_refusals() raises:
    assert_equal(len(probes("drug")), 4)
    assert_equal(len(groups()), 4)
    with assert_raises(contains="no group"):
        _ = probes("other")
    with assert_raises(contains="a name, a unit and times"):
        _ = parametric_reference("drug wk")
    with assert_raises(contains="needs an event"):
        _ = parametric_reference("drug wk 5+ 6+")
    with assert_raises(contains="a group, a time and an event"):
        _ = aft_reference("trial 5")
    with assert_raises(contains="no patient in group trial"):
        _ = aft_reference("cohort 5.0 1.0 0.0 0.0 0.0")
    with assert_raises(contains="needs an event"):
        _ = fit([5.0, 6.0], [False, False], [List[Float64](), List[Float64]()])


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
