# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md

"""The checker failure prefixes stay reviewed."""

from std.testing import TestSuite, assert_equal

from tools._cli_failures import cli_failures
from tools._python_json import PyJson


def test_checker_failure_prefixes_stay_reviewed() raises:
    """The moment prefix keeps its space, and the other two do not."""
    var doc = PyJson.parse(cli_failures())
    assert_equal(doc.text(doc.at(doc.root, "moments")), "FAIL: ")
    assert_equal(doc.text(doc.at(doc.root, "sampled")), "FAIL:")
    assert_equal(doc.text(doc.at(doc.root, "runtime")), "FAIL:")


def main() raises:
    """Run the checker failure prefix tests."""
    TestSuite.discover_tests[__functions_in_module()]().run()
