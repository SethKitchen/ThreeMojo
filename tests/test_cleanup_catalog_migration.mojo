# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md

"""The premise catalog is checked before the frozen migration record."""

from std.testing import TestSuite, assert_equal, assert_raises

from tools._cleanup_premises import catalog_then_frozen_migration


def test_missing_texts_fail_before_the_migration_record() raises:
    """A catalog without texts fails before the frozen record is returned."""
    with assert_raises(contains="KeyError: 'texts'"):
        _ = catalog_then_frozen_migration("{}")


def test_a_short_source_fails_inside_the_catalog() raises:
    """The first catalog declaration is required before the frozen record."""
    with assert_raises(
        contains=(
            "missing or ambiguous actual guard declaration: "
            "_rounded_line_axis_context"
        )
    ):
        _ = catalog_then_frozen_migration(
            '{"texts":["def f():\\n    return 1\\n"]}'
        )


def main() raises:
    """Run the catalog and frozen-migration tests."""
    TestSuite.discover_tests[__functions_in_module()]().run()
