# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""The grouped Y record keeps one successor and refuses a changed premise."""

from std.pathlib import Path
from std.testing import TestSuite, assert_equal, assert_not_equal, assert_true

from tests._python_tokens import token_sha256
from tools._python_json import PyJson
from tools._sha256 import sha256_hex


comptime _RECORD = "tools/carla_lane_oracle/grouped-y-successor-record.json"
"""The reviewed grouped Y successor record."""
comptime _RECORD_SHA256 = (
    "4b72cd07de22d61d70c7aa489e566cd25468189b6a60b5e105fa26ea726e6853"
)
"""The SHA-256 of that record."""
comptime _MODULE = "extensions/carla/spiral_grouped_roundoff_proof.mojo"
"""The only module the Y projection restores."""


def _field(doc: PyJson, name: String) raises -> String:
    """Return one string field of the record.

    Args:
        doc: The record.
        name: The field name.

    Returns:
        The field text.

    Raises:
        Error: The field is absent.
    """
    return doc.text(doc.at(doc.root, name))


def _replace_first(
    text: String, before: String, after: String
) raises -> String:
    """Replace the first occurrence of `before`.

    Args:
        text: The source.
        before: The original fragment.
        after: The replacement.

    Returns:
        The changed source.

    Raises:
        Error: `before` is missing.
    """
    var at = text.find(before)
    if at < 0:
        raise Error("missing grouped premise")
    var head = String(text[byte=:at])
    var tail = String(text[byte = at + before.byte_length() :])
    return head + after + tail


def _premise(text: String, expected: String) raises:
    """Require the grouped module's token digest to equal `expected`.

    Args:
        text: The module source.
        expected: The recorded successor token digest.

    Raises:
        Error: A premise, the graph, a write, or the order changed.
    """
    if token_sha256(text) != expected:
        raise Error(
            "Y-finiteness premise, graph, writes or ordering changed: "
            + _MODULE
        )


def _restore(path: String, before: String) raises -> String:
    """Return the predecessor text for the grouped module.

    Args:
        path: The requested module.
        before: The recorded predecessor source.

    Returns:
        `before` when `path` is the grouped module.

    Raises:
        Error: `path` is a different module.
    """
    if path != _MODULE:
        raise Error("Y projection permits only its exact grouped module")
    return before


def test_the_grouped_record_keeps_both_complete_modules() raises:
    """The record hash, both modules, and the five dependencies stay bound."""
    var raw = Path(_RECORD).read_bytes()
    assert_equal(sha256_hex(raw), _RECORD_SHA256)
    var doc = PyJson.parse(Path(_RECORD).read_text())
    assert_equal(doc.length(doc.root), 9)
    assert_equal(_field(doc, "module"), _MODULE)
    var before = _field(doc, "before_complete_module")
    var after = _field(doc, "after_complete_module")
    assert_equal(
        sha256_hex(before.as_bytes()), _field(doc, "predecessor_file_sha256")
    )
    assert_equal(
        sha256_hex(after.as_bytes()), _field(doc, "successor_file_sha256")
    )
    assert_equal(token_sha256(before), _field(doc, "predecessor_token_sha256"))
    assert_equal(token_sha256(after), _field(doc, "successor_token_sha256"))
    assert_not_equal(
        _field(doc, "predecessor_token_sha256"),
        _field(doc, "successor_token_sha256"),
    )
    var deps = doc.at(doc.root, "dependencies")
    assert_equal(doc.length(deps), 5)
    assert_equal(
        doc.text(doc.at(deps, _MODULE)),
        _field(doc, "successor_token_sha256"),
    )
    assert_equal(
        doc.text(doc.at(deps, "extensions/carla/curve_interval.mojo")),
        "e2e87c519ed45fb4ec77d9a54aad08406461b17805287874c9b05ddb6bf49b11",
    )
    assert_equal(
        doc.text(doc.at(deps, "extensions/carla/curve_trig.mojo")),
        "523d5700201b957152eaa79ae6cce9ca8cb9a2a0098d5b105584667360a6de7f",
    )
    assert_equal(
        doc.text(doc.at(deps, "extensions/carla/geometry.mojo")),
        "a1979bd37d0ea725f452e0a0a269c7aaef3cda485b291e8fe79b49b35850adcb",
    )
    assert_equal(
        doc.text(doc.at(deps, "extensions/carla/curve_sum2.mojo")),
        "3fbcbb7f6ba0b9120500698665f0419acf6618d8bd34b7e18b9d10896282383d",
    )
    var changed = raw.copy()
    changed.append(UInt8(32))
    var refused = False
    try:
        if sha256_hex(changed) != _RECORD_SHA256:
            raise Error("Unreviewed grouped Y successor record")
    except error:
        refused = True
        assert_true(
            String(error).find("Unreviewed grouped Y successor record") >= 0
        )
    assert_true(refused)


def test_only_the_y_call_changes_between_the_two_modules() raises:
    """The successor drops the Y refusal and keeps the same call."""
    var doc = PyJson.parse(Path(_RECORD).read_text())
    var before = _field(doc, "before_complete_module")
    var after = _field(doc, "after_complete_module")
    var old = (
        "            if not _grouped_term(y, copies, y_ideal, y_magnitude,"
        " y_inherited):\n                return None\n"
    )
    var new = (
        "            # The source-bound Y-finiteness lemma proves this call"
        " succeeds\n            # after X. Keep the call and all three"
        " accumulator writes.\n            _ = _grouped_term(y, copies,"
        " y_ideal, y_magnitude, y_inherited)\n"
    )
    assert_equal(_replace_first(before, old, new), after)
    assert_equal(
        _field(doc, "only_change"),
        (
            "Caller Y refusal removed; the same _grouped_term call and all its"
            " writes remain after unchanged X refusal. All later origin-error"
            " refusals and metering unchanged."
        ),
    )
    assert_equal(_restore(_MODULE, before), before)
    var refused = False
    try:
        _ = _restore("extensions/carla/spiral_roundoff_proof.mojo", before)
    except error:
        refused = True
        assert_true(
            String(error).find(
                "Y projection permits only its exact grouped module"
            )
            >= 0
        )
    assert_true(refused)


def test_a_comment_or_wider_spacing_keeps_the_successor_digest() raises:
    """A comment and extra spaces keep the successor token digest."""
    var doc = PyJson.parse(Path(_RECORD).read_text())
    var after = _field(doc, "after_complete_module")
    var expected = _field(doc, "successor_token_sha256")
    var changed = after + "\n# harmless source annotation\n"
    changed = _replace_first(changed, "copies =", "copies  =")
    assert_not_equal(changed, after)
    assert_equal(token_sha256(changed), expected)


def _revoke(
    text: String, expected: String, before: String, after: String
) raises:
    """Require one first-occurrence edit to change the token digest.

    Args:
        text: The successor source.
        expected: The successor token digest.
        before: The original fragment.
        after: The replacement.

    Raises:
        Error: The fragment is missing, or the edit keeps the digest.
    """
    var changed = _replace_first(text, before, after)
    var failed = False
    try:
        _premise(changed, expected)
    except error:
        failed = True
        assert_true(
            String(error).find(
                "Y-finiteness premise, graph, writes or ordering changed"
            )
            >= 0
        )
    assert_true(failed)


def test_grouped_admission_and_phase_edits_revoke() raises:
    """An admission or phase edit changes the successor token digest."""
    var doc = PyJson.parse(Path(_RECORD).read_text())
    var after = _field(doc, "after_complete_module")
    var expected = _field(doc, "successor_token_sha256")
    _premise(after, expected)
    var cases = List[String]()
    cases.append("pieces > 64")
    cases.append("pieces > 128")
    cases.append("pieces < 1")
    cases.append("pieces < 0")
    cases.append("geometry.heading != 0.0")
    cases.append("False")
    cases.append("geometry.curvature_start != 0.0")
    cases.append("False")
    cases.append("or d.value.low > d.value.high")
    cases.append("")
    cases.append("or not isfinite(d.error)")
    cases.append("")
    cases.append("or d.error < 0.0")
    cases.append("")
    cases.append("domain.low <= 0.0")
    cases.append("domain.low < 0.0")
    cases.append("phase.magnitude() > _PHASE_LIMIT")
    cases.append("False")
    cases.append("floor(selection.low) != 0.0")
    cases.append("False")
    cases.append("floor(selection.high) != 0.0")
    cases.append("False")
    var index = 0
    while index < len(cases):
        _revoke(after, expected, cases[index], cases[index + 1])
        index += 2


def test_grouped_call_order_and_writes_revoke() raises:
    """A call, a write, or the Y-before-X order changes the token digest."""
    var doc = PyJson.parse(Path(_RECORD).read_text())
    var after = _field(doc, "after_complete_module")
    var expected = _field(doc, "successor_token_sha256")
    var cases = List[String]()
    cases.append("1 if weight == 2 else 2")
    cases.append("1 if weight == 2 else 640")
    cases.append("for group in range(4):")
    cases.append("for group in range(400):")
    cases.append("var copies = (high - low) * multiplicity")
    cases.append("var copies = 0")
    cases.append(
        "if not _grouped_term(x, copies, x_ideal, x_magnitude, x_inherited):"
    )
    cases.append("if False:")
    cases.append(
        "_ = _grouped_term(y, copies, y_ideal, y_magnitude, y_inherited)"
    )
    cases.append("_ = True")
    cases.append("var y = factors[weight] * trig[0]")
    cases.append("var y = factors[weight] * trig[1]")
    cases.append("ideal = ideal + copies * term.value")
    cases.append("ideal = term.value")
    cases.append(
        "magnitude = magnitude + copies * _Interval.point(rounded.magnitude())"
    )
    cases.append("magnitude = _Interval.point(0.0)")
    cases.append("inherited = inherited + copies * _Interval.point(term.error)")
    cases.append("inherited = _Interval.point(0.0)")
    cases.append("if not isfinite(x_error) or not isfinite(y_error):")
    cases.append("if False:")
    cases.append("terms += work")
    cases.append("terms += 0")
    var index = 0
    while index < len(cases):
        _revoke(after, expected, cases[index], cases[index + 1])
        index += 2
    var guard = (
        "            if not _grouped_term(x, copies, x_ideal, x_magnitude,"
        " x_inherited):\n                return None"
    )
    var early = (
        "            _ = _grouped_term(y, copies, y_ideal, y_magnitude,"
        " y_inherited)\n"
        + guard
    )
    _revoke(after, expected, guard, early)


def main() raises:
    """Run the grouped Y record tests."""
    TestSuite.discover_tests[__functions_in_module()]().run()
