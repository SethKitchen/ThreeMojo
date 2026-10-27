# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md

"""A changed envelope budget record fails the gate."""

from std.testing import TestSuite, assert_raises

from tools.carla_envelope_gate import envelope_record, envelope_token


def test_a_changed_record_is_refused() raises:
    """Bytes that are not the reviewed record fail closed."""
    with assert_raises(
        contains="Unreviewed envelope budget predecessor record"
    ):
        envelope_record(String("").as_bytes())


def test_a_changed_admission_token_is_refused() raises:
    """A source that does not have the recorded token digest fails closed."""
    with assert_raises(
        contains="Reviewed budget admission, routing or arithmetic changed"
    ):
        envelope_token("def changed():\n    pass\n", "00")


def main() raises:
    """Run the envelope gate tests."""
    TestSuite.discover_tests[__functions_in_module()]().run()
