# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md

"""A changed envelope budget record fails the gate."""

from std.testing import TestSuite, assert_raises

from tests._python_tokens import declaration_text
from tools._python_json import PyJson
from tools.carla_envelope_gate import (
    envelope_module_span,
    envelope_module_successor,
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


def _module_pair(source: String, expected: String) raises -> String:
    """Return one module successor payload.

    Args:
        source: The module text.
        expected: The recorded function text.

    Returns:
        JSON with those two fields.

    Raises:
        Error: The document cannot be built.
    """
    var doc = PyJson()
    var root = doc.new_dict()
    doc.set(root, "source", doc.new_str(source))
    doc.set(root, "expected", doc.new_str(expected))
    doc.root = root
    return doc.dumps()


def test_the_module_selects_the_capture_function() raises:
    """The module check reads the capture function before the gap and the successor."""
    var source = (
        "def other():\n    return None\n"
        + "def _try_lane_envelope_capture():\n"
        + "    var at = info_index(x)\n"
        + "    if optional_work > max_terms - terms:\n"
        + "        return None\n"
    )
    var owners = List[String]()
    var expected = declaration_text(
        source, "_try_lane_envelope_capture", owners
    )
    envelope_module_span(source)
    envelope_module_successor(_module_pair(source, expected))
    var marked = source.replace(
        "    var at = info_index(x)\n",
        "    var at = info_index(x)\n    terms = -1\n",
    )
    with assert_raises(contains="Intervening span can access budget parameters"):
        envelope_module_span(marked)
    with assert_raises(contains="Envelope budget successor function changed"):
        envelope_module_successor(_module_pair(marked, expected))
    with assert_raises(
        contains="missing or ambiguous actual guard declaration: "
        + "_try_lane_envelope_capture"
    ):
        envelope_module_span("def other():\n    return None\n")


def main() raises:
    """Run the envelope gate tests."""
    TestSuite.discover_tests[__functions_in_module()]().run()
