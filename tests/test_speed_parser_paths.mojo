# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md

"""The speed-parser module and tests stay in reviewed order."""

from std.testing import TestSuite, assert_equal

from tools._python_json import PyJson
from tools.carla_speed_gate import speed_parser_paths


def test_the_module_precedes_the_two_tests() raises:
    """The speed-limit module stays ahead of the lexical and XML tests."""
    var doc = PyJson.parse(speed_parser_paths())
    var tests = doc.at(doc.root, "tests")
    assert_equal(
        doc.text(doc.at(doc.root, "module")),
        "extensions/carla/speed_limits.mojo",
    )
    assert_equal(doc.length(tests), 2)
    assert_equal(
        doc.text(doc.item(tests, 0)), "tests/test_carla_speed_lexical.mojo"
    )
    assert_equal(
        doc.text(doc.item(tests, 1)), "tests/test_carla_speed_xml_lexical.mojo"
    )


def main() raises:
    """Run the speed-parser path tests."""
    TestSuite.discover_tests[__functions_in_module()]().run()
