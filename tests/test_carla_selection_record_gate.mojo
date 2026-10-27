# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md

"""A changed selection predecessor record fails the gate."""

from std.testing import TestSuite, assert_raises

from tools.carla_selection_record_gate import (
    selection_record,
    selection_restored,
)


def test_a_changed_record_is_refused() raises:
    """Bytes that are not the reviewed record fail closed."""
    with assert_raises(contains="Unreviewed selection predecessor record"):
        selection_record(String("").as_bytes())


def test_a_changed_restored_token_is_refused() raises:
    """A restored module that does not have the recorded token fails closed."""
    with assert_raises(contains="Selection predecessor reconstruction failed"):
        selection_restored("def changed():\n    pass\n", "00")


def main() raises:
    """Run the selection record gate tests."""
    TestSuite.discover_tests[__functions_in_module()]().run()
