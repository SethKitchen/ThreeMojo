# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""The planar wall reference keeps the test's rows current.

The reference prints its exact digits only when built with
`--fp-mode contract=off`; a test build fuses multiply-adds. So these tests
compare within the native tests' tolerances, and check the C library math.
"""

from std.testing import TestSuite, assert_equal, assert_false, assert_true

from tests._tree import Tree
from tools._python_math import exp, float_sum, log, radians, sin, tan
from tools.reference_geotech_wall import check, reference, rows


def test_the_c_library_math_matches_python() raises:
    # repr(math.radians(30)), repr(math.sin(...)), repr(math.tan(...)),
    # repr(math.exp(0.7)) and repr(math.log(0.7)) from CPython 3.12.14.
    assert_equal(String(radians(30)), "0.5235987755982988")
    assert_equal(String(sin(radians(30))), "0.49999999999999994")
    assert_equal(String(tan(radians(30))), "0.5773502691896257")
    assert_equal(String(exp(0.7)), "2.0137527074704766")
    assert_equal(String(log(0.7)), "-0.35667494393873245")
    assert_equal(float_sum([1e16, 1.0, -1e16]), 1.0)


def test_the_first_case_has_its_reference_values() raises:
    var values = reference(3.0, 0.0)
    assert_equal(len(values), 7)
    assert_equal(values[2], 144000.0)
    assert_equal(values[3], 40500.0)
    assert_true(abs(values[4] - 0.07374999999999998) <= 1e-9)
    assert_true(abs(values[6] - 50800.0) <= 1e-6)
    assert_equal(len(rows().split("\n")), 4)


def test_check_reads_the_rows_and_refuses_stale_ones() raises:
    var tree = Tree()
    var block = (
        "        # BEGIN PYTHON WALL REFERENCE\n"
        + rows()
        + "\n        # END PYTHON WALL REFERENCE\n"
    )
    tree.write("tests/test_geotech_wall.mojo", "x = [\n" + block + "]\n")
    assert_true(check(tree.root))
    tree.write(
        "tests/test_geotech_wall.mojo",
        "x = [\n" + block.replace("(3.0, 0.0,", "(3.0, 0.1,") + "]\n",
    )
    assert_false(check(tree.root))
    tree.write("tests/test_geotech_wall.mojo", "nothing\n")
    var refused = False
    try:
        _ = check(tree.root)
    except:
        refused = True
    assert_true(refused)
    tree.close()


def test_the_repository_rows_are_current() raises:
    assert_true(check("."))


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
