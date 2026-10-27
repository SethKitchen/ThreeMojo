# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md

"""Frozen lane renames stay in declaration order."""

from std.testing import TestSuite, assert_equal

from tests._python_tokens import replace_firsts


def test_replacements_keep_their_order() raises:
    """Each text keeps its own first replacement."""
    assert_equal(
        replace_firsts(
            '[{"source":"def foo(\\ndef foo(","old":"def foo(",'
            + '"new":"def _referencefoo("},{"source":"abc","old":"",'
            + '"new":"X"},{"source":"none","old":"def foo(",'
            + '"new":"def _referencefoo("}]'
        ),
        '["def _referencefoo(\\ndef foo(","Xabc","none"]',
    )


def main() raises:
    """Run the replacement tests."""
    TestSuite.discover_tests[__functions_in_module()]().run()
