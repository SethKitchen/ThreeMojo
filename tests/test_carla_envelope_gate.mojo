# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md

"""A changed envelope budget record fails the gate."""

from std.testing import TestSuite, assert_raises

from tools._python_json import PyJson
from tools.carla_envelope_gate import (
    envelope_record,
    envelope_successor,
    envelope_token,
)


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


def _pair(actual: String, expected: String) raises -> String:
    """Return one successor payload.

    Args:
        actual: The live function text.
        expected: The recorded function text.

    Returns:
        JSON with those two fields.

    Raises:
        Error: The document cannot be built.
    """
    var doc = PyJson()
    var root = doc.new_dict()
    doc.set(root, "actual", doc.new_str(actual))
    doc.set(root, "expected", doc.new_str(expected))
    doc.root = root
    return doc.dumps()


def test_the_successor_function_keeps_its_significant_tokens() raises:
    """Comments do not change the successor, and a statement does."""
    var kept = "def capture():\n    pass\n"
    envelope_successor(_pair(kept, "def capture():\n    pass  # note\n"))
    with assert_raises(contains="Envelope budget successor function changed"):
        envelope_successor(_pair(kept, "def capture():\n    return\n"))
    with assert_raises():
        envelope_successor("{}")


def main() raises:
    """Run the envelope gate tests."""
    TestSuite.discover_tests[__functions_in_module()]().run()
