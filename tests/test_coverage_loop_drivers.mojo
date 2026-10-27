# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md

"""The native loop source and the production drivers stay reviewed."""

from std.testing import TestSuite, assert_true

from tools._coverage_loop_drivers import coverage_loop_drivers
from tools._python_json import PyJson


def test_coverage_loop_drivers_keep_the_alarm_and_the_result() raises:
    """The production driver arms the alarm, and the source prints its result.
    """
    var doc = PyJson.parse(coverage_loop_drivers())
    var production = doc.text(doc.at(doc.root, "production"))
    var hang = doc.text(doc.at(doc.root, "hang"))
    var broken = doc.text(doc.at(doc.root, "compile_error"))
    var source = doc.text(doc.at(doc.root, "source"))
    assert_true(
        production.find('external_call["alarm", UInt32](UInt32(5))') >= 0
    )
    assert_true(hang.find('external_call["pause", Int32]()') >= 0)
    assert_true(broken.find("var broken =") >= 0)
    assert_true(source.find('print("RESULT constant loops")') >= 0)


def main() raises:
    """Run the coverage-loop driver tests."""
    TestSuite.discover_tests[__functions_in_module()]().run()
