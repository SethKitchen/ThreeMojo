# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md

"""The moment pin file, table, and word count stay reviewed."""

from std.testing import TestSuite, assert_equal

from tools._python_json import PyJson
from tools.carla_moment_gate import moment_files


def test_the_pin_file_table_and_word_count_stay_reviewed() raises:
    """The pin file and the stored table keep the 2816-word count."""
    var doc = PyJson.parse(moment_files())
    assert_equal(
        doc.text(doc.at(doc.root, "pins")),
        "tools/carla_lane_oracle/spiral-moment-pins.json",
    )
    assert_equal(
        doc.text(doc.at(doc.root, "table")),
        "extensions/carla/spiral_moment_table_data.mojo",
    )
    assert_equal(doc.text(doc.at(doc.root, "words")), "2816")


def main() raises:
    """Run the moment file tests."""
    TestSuite.discover_tests[__functions_in_module()]().run()
