# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md

"""The restored capture is prepared as Python syntax in that same check."""

from std.testing import TestSuite, assert_equal, assert_raises, assert_true

from tools._python_json import PyJson
from tools.carla_restore_reference import restored_then_syntax


def _source() -> String:
    """Return one reviewed try-only proof and its old capture."""
    return (
        "def _lane_jet_model_proof[capture: Bool](\n"
        + "    ideal_translation: Bool = False,\n"
        + "    require_reuse: Bool = False,\n"
        + ") -> Int:\n"
        + "    if reused:\n"
        + "        point = reused.value()\n"
        + "    elif require_reuse:\n"
        + "        return _unknown_point()\n"
        + "    else:\n"
        + "        point = 1\n"
        + "    return point\n"
        + "def _try_lane_envelope_capture():\n    return old\n"
    )


def _replacement() -> String:
    """Return the historical capture."""
    return "def _try_lane_envelope_capture():\n    return historical\n"


def test_a_changed_refusal_fails_before_the_syntax() raises:
    """A changed refusal fails before the syntax is prepared."""
    with assert_raises(contains="try-only parameter changed"):
        _ = restored_then_syntax(
            "def _lane_jet_model_proof():\n    return 1\n", "not a function"
        )


def test_a_restored_capture_includes_its_syntax() raises:
    """The restored source stays ahead of the prepared syntax."""
    var doc = PyJson.parse(restored_then_syntax(_source(), _replacement()))
    assert_equal(doc.key(doc.root, 0), "restored")
    assert_equal(doc.key(doc.root, 1), "syntax")
    var restored = doc.text(doc.at(doc.root, "restored"))
    assert_true(restored.find("return historical") >= 0)
    assert_true(restored.find("return old") < 0)
    var syntax = doc.at(doc.root, "syntax")
    assert_true(
        doc.get(syntax, "fallback") != -1 or doc.get(syntax, "source") != -1
    )


def main() raises:
    """Run the restore and syntax tests."""
    TestSuite.discover_tests[__functions_in_module()]().run()
