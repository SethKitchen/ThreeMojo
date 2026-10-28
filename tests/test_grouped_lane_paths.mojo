# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md

"""The grouped table is checked before the lane-control record paths."""

from std.testing import TestSuite, assert_equal, assert_raises

from tests._python_tokens import token_sha256
from tools._python_json import PyJson
from tools.carla_grouped_gate import grouped_checked_then_paths


def test_a_missing_module_fails_before_the_paths() raises:
    """The grouped module is required before the record paths are read."""
    with assert_raises(contains="KeyError: 'module'"):
        _ = grouped_checked_then_paths("{}")


def test_a_digest_mismatch_skips_the_record_paths() raises:
    """A different digest returns restore and does not read the paths."""
    var text = grouped_checked_then_paths(
        '{"module":"def f():\\n    return 1\\n","geometry":"x","digest":"nope"}'
    )
    var doc = PyJson.parse(text)
    assert_equal(text, '{"restore":true}')
    assert_equal(doc.flag(doc.at(doc.root, "restore")), True)


def test_a_matching_digest_fails_inside_the_table_check() raises:
    """A matching digest enters the table check before the paths."""
    var module = String("def f():\n    return 1\n")
    var digest = token_sha256(module)
    with assert_raises(contains="Reviewed grouped consumer graph changed"):
        _ = grouped_checked_then_paths(
            '{"module":"def f():\\n    return 1\\n","geometry":"x","digest":"'
            + digest
            + '"}'
        )


def main() raises:
    """Run the grouped-table and lane-path tests."""
    TestSuite.discover_tests[__functions_in_module()]().run()
