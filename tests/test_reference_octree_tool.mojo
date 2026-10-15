# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""The octree contact oracle adds and solves as its Python original did.

The expected sums are what CPython 3.12.14 printed for the same lists.
"""

from std.testing import TestSuite, assert_equal, assert_false, assert_true

from tools._python_math import py_sum
from tools.reference_octree_contacts import (
    clamp,
    report,
    self_check,
    whole,
    dot_kind,
    ints,
)


def test_sum_compensates_floats_but_not_ints() raises:
    # sum([1e16, 1.0, -1e16]) == 1.0
    assert_equal(py_sum([1e16, 1.0, -1e16], [False, False, False])[0], 1.0)
    # sum([1e16, 1, -1e16]) == 0.0: an int item adds plainly.
    assert_equal(py_sum([1e16, 1.0, -1e16], [False, True, False])[0], 0.0)
    # sum([1e16, 1.0, -1e16, 1]) == 2.0
    assert_equal(
        py_sum([1e16, 1.0, -1e16, 1.0], [False, False, False, True])[0], 2.0
    )
    # sum([1, 1e16, 1.0, -1e16]) == 1.0: the leading int is lost in 1e16.
    assert_equal(
        py_sum([1.0, 1e16, 1.0, -1e16], [True, False, False, False])[0], 1.0
    )


def test_sums_of_ints_stay_ints_and_zero_has_no_sign() raises:
    var total = py_sum([2.0, -3.0, 1.0], [True, True, True])
    assert_equal(total[0], 0.0)
    assert_true(total[1])
    # sum([-0.0]) == 0.0, because the sum starts from the int 0.
    var zero = py_sum([-0.0], [False])
    assert_false(zero[1])
    assert_equal(String(zero[0]), "0.0")
    var mixed = dot_kind(whole(1, 2, 3), ints(1.5, 2, 3, False, True, True))
    assert_equal(mixed[0], 14.5)
    assert_false(mixed[1])


def test_clamp_returns_int_limits() raises:
    assert_true(clamp(2.5)[1] and clamp(2.5)[0] == 1)
    assert_true(clamp(1.0)[1])
    assert_true(clamp(-0.5)[1] and clamp(-0.5)[0] == 0)
    assert_false(clamp(0.25)[1])


def test_the_solver_answers_its_known_cases() raises:
    self_check()
    var text = report()
    for name in [
        "sphere_ground",
        "sphere_shallow",
        "sphere_wall",
        "capsule_ground",
        "capsule_wall",
        "capsule_slope",
    ]:
        assert_true(text.find('"' + name + '": {') >= 0, name)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
