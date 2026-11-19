# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Numbers in the fixed-width fields of Fortran records."""

from extensions.chemistry.fields import fortran_number
from std.testing import TestSuite, assert_equal, assert_raises


def test_fortran_numbers() raises:
    assert_equal(fortran_number(" 2.5D+02 ", 1), 250.0)
    assert_equal(fortran_number("-1.25d-1", 1), -0.125)
    assert_equal(fortran_number("   3.0E+00", 1), 3.0)
    with assert_raises(contains="Line 4: ' x ' is not a number"):
        _ = fortran_number(" x ", 4)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
