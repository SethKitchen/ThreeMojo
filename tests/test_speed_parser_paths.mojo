# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md

"""The speed-parser module and tests stay in reviewed order."""

from std.testing import TestSuite, assert_equal

from tools._migration_records import migration_records
from tools._python_json import PyJson
from tools.carla_speed_gate import (
    speed_parser_paths,
    speed_paths_with_migration,
)


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


def test_the_paths_are_read_before_the_migration_record() raises:
    """The module paths stay ahead of the speed migration path."""
    var text = speed_paths_with_migration()
    var doc = PyJson.parse(text)
    var paths = PyJson.parse(speed_parser_paths())
    var records = PyJson.parse(migration_records())
    var speed = records.at(records.root, "speed")
    var migration = doc.at(doc.root, "migration")
    assert_equal(text.find('{"paths":'), 0)
    assert_equal(
        doc.text(doc.at(doc.at(doc.root, "paths"), "module")),
        paths.text(paths.at(paths.root, "module")),
    )
    assert_equal(
        doc.text(doc.at(migration, "path")),
        records.text(records.at(speed, "path")),
    )
    assert_equal(
        doc.text(doc.at(migration, "sha")),
        records.text(records.at(speed, "sha")),
    )


def main() raises:
    """Run the speed-parser path tests."""
    TestSuite.discover_tests[__functions_in_module()]().run()
