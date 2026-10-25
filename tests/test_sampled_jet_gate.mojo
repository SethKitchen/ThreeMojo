# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""The stored jet aliases and derivative gate stay checked."""

from std.pathlib import Path
from std.testing import TestSuite, assert_raises

from tools.sampled_jet_gate import stored_jet_gate


def _source() raises -> String:
    """Return the live curve-interval module.

    Returns:
        The module text.

    Raises:
        Error: The file is unreadable.
    """
    return Path("extensions/carla/curve_interval.mojo").read_text()


def _refuse(source: String, message: String) raises:
    """Require `source` to fail with `message`.

    Args:
        source: The module under test.
        message: The expected failure text.

    Raises:
        Error: The failure text differs.
    """
    with assert_raises(contains=message):
        stored_jet_gate(source)


def test_the_live_jet_gate_holds() raises:
    """The live aliases and stored helpers keep the gate."""
    var source = _source()
    stored_jet_gate(source)
    stored_jet_gate(source.replace("comptime _Jet ", "_Jet "))
    stored_jet_gate(
        source.replace(
            (
                "    var result = value *"
                " _JetExpression[derivatives].constant(0.5)\n"
            ),
            (
                "    # value.first stays a comment\n    var result = value *"
                " _JetExpression[derivatives].constant(0.5)\n"
            ),
        )
    )


def test_a_changed_jet_gate_is_refused() raises:
    """A changed alias, a missing helper, or a derivative read is refused."""
    var source = _source()
    _refuse(
        source.replace("_JetExpression[True]", "_JetExpression[False]"),
        "actual derivative alias changed: _Jet",
    )
    _refuse(
        source.replace("comptime _Jet = _JetExpression[True]\n", ""),
        "missing or ambiguous actual alias: _Jet",
    )
    _refuse(
        source.replace(
            "comptime _Jet = _JetExpression[True]\n",
            (
                "comptime _Jet = _JetExpression[True]\ncomptime _Jet ="
                " _JetExpression[True]\n"
            ),
        ),
        "missing or ambiguous actual alias: _Jet",
    )
    _refuse(
        source.replace("_JetExpression[False]", "_JetExpression[True]"),
        "actual derivative alias changed: _ValueJet",
    )
    _refuse(
        source.replace("def _stored_half[", "def _stored_half_other["),
        "missing or ambiguous function: _stored_half",
    )
    _refuse(
        source.replace(
            "var result = value * _JetExpression[derivatives].constant(0.5)",
            (
                "var result = value.first *"
                " _JetExpression[derivatives].constant(0.5)"
            ),
        ),
        "derivative-field/flag read in stored helper: _stored_half",
    )
    _refuse(
        source.replace(
            "var result = one - two", "var result = one.second - two"
        ),
        "derivative-field/flag read in stored helper: _stored_difference",
    )
    _refuse(
        source.replace(
            (
                "return _ValueJet(\n        value.value, _Interval.whole(),"
                " _Interval.whole(), value.error\n    )"
            ),
            (
                "return _ValueJet(\n        value.derivatives,"
                " _Interval.whole(), _Interval.whole(), value.error\n    )"
            ),
        ),
        "derivative-field/flag read in stored helper: _without_derivatives",
    )
    _refuse(
        (
            "def _stored_half[\n    derivatives: Bool\n]() -> None:\n    return"
            " 0\n  return 1\n"
        ),
        "unsupported ideal source syntax",
    )


def main() raises:
    """Run the stored jet gate tests."""
    TestSuite.discover_tests[__functions_in_module()]().run()
