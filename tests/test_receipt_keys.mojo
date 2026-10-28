# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md

"""A repeated coverage receipt key fails closed."""

from std.testing import TestSuite, assert_raises

from tools.coverage_io import _reject_duplicate_keys


def test_a_repeated_receipt_key_is_refused() raises:
    """A repeated key keeps its name, and a unique document passes."""
    with assert_raises(contains="Duplicate receipt key: a"):
        _reject_duplicate_keys('{"a":1,"a":2}')
    _reject_duplicate_keys('{"a":1,"b":2}')


def main() raises:
    """Run the receipt key tests."""
    TestSuite.discover_tests[__functions_in_module()]().run()
