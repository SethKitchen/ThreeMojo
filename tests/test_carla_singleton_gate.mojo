# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md

"""A changed rounded LINE singleton record fails the gate."""

from std.testing import TestSuite, assert_raises

from tools.carla_singleton_gate import singleton_record, singleton_views


def test_a_changed_record_is_refused() raises:
    """Bytes that are not the reviewed record fail closed."""
    with assert_raises(
        contains="rounded LINE singleton contract: unreviewed migration record"
    ):
        singleton_record(String("").as_bytes())


def test_disagreeing_lane_views_are_refused() raises:
    """Text and decoded views with different tokens fail closed."""
    with assert_raises(
        contains=(
            "rounded LINE singleton contract: consumer lane source text/bytes"
            " disagree"
        )
    ):
        singleton_views(
            "def changed():\n    pass\n", "def other():\n    pass\n"
        )


def main() raises:
    """Run the singleton gate tests."""
    TestSuite.discover_tests[__functions_in_module()]().run()
