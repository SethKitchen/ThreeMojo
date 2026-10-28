# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""The envelope budget record keeps the gap between its two counter checks."""

from std.pathlib import Path
from std.testing import (
    TestSuite,
    assert_equal,
    assert_false,
    assert_not_equal,
    assert_true,
)

from tests._python_tokens import token_names, token_sha256
from tools._python_json import PyJson
from tools._sha256 import sha256_hex


comptime _RECORD = "tools/carla_lane_oracle/envelope-budget-contract.json"
"""The reviewed envelope budget record."""
comptime _RECORD_SHA256 = (
    "c43aa2bfdfb2a33575745eefb44b2f8ff0714a71a31ad750e8c4c0572fa7f2be"
)
"""The SHA-256 of that record."""
comptime _START = "    var at = info_index("
"""The first operation after the entry check."""
comptime _END = "    if optional_work > max_terms - terms:"
"""The second capacity check."""


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
        raise Error("missing envelope fragment")
    var head = String(text[byte=:at])
    var tail = String(text[byte = at + before.byte_length() :])
    return head + after + tail


def _span_hits_counter(text: String) raises -> Bool:
    """Return whether the gap between the checks names a counter.

    Args:
        text: The capture function.

    Returns:
        True when `terms` or `max_terms` appears in that gap.

    Raises:
        Error: Either check is missing.
    """
    var start = text.find(_START)
    var end = text.find(_END)
    if start < 0 or end < start:
        raise Error("Reviewed budget admission, routing or arithmetic changed")
    var span = String(text[byte=start:end])
    for name in token_names(span):
        if name == "terms" or name == "max_terms":
            return True
    return False


def test_the_envelope_record_keeps_the_reviewed_gap() raises:
    """The successor removes the repeated counter test and keeps the gap clear.
    """
    var raw = Path(_RECORD).read_bytes()
    assert_equal(sha256_hex(raw), _RECORD_SHA256)
    var doc = PyJson.parse(Path(_RECORD).read_text())
    assert_equal(_field(doc, "schema"), "1")
    assert_equal(_field(doc, "path"), "extensions/carla/curve_bounds.mojo")
    var before = _field(doc, "before_complete_function")
    var after = _field(doc, "after_complete_function")
    var old = (
        "    if terms < 0 or terms > max_terms or optional_work > max_terms -"
        " terms:\n"
    )
    var new = (
        "    # The entry check established 0 <= terms <= max_terms. No"
        " intervening\n    # operation receives either counter by mutable"
        " reference or changes it.\n    if optional_work > max_terms - terms:\n"
    )
    assert_equal(_replace_first(before, old, new), after)
    assert_false(_span_hits_counter(after))
    var changed = after + "\n# Benign source commentary\n"
    changed = _replace_first(
        changed, "optional_work = 1024", "optional_work  =  1024"
    )
    assert_equal(token_sha256(changed), token_sha256(after))
    assert_false(_span_hits_counter(changed))
    raw.append(UInt8(32))
    assert_not_equal(sha256_hex(raw), _RECORD_SHA256)


def test_a_counter_use_in_the_gap_is_refused() raises:
    """A write, a call, or an early debit puts a counter in the gap."""
    var doc = PyJson.parse(Path(_RECORD).read_text())
    var after = _field(doc, "after_complete_function")
    var expected = token_sha256(after)
    var marker = "    var optional_work = 1024 * branches"
    for injection in ["terms = -1", "_mutate_counter(terms)", "max_terms = 0"]:
        var changed = _replace_first(
            after, marker, "    " + injection + "\n" + marker
        )
        assert_not_equal(token_sha256(changed), expected)
        assert_true(_span_hits_counter(changed))
    var moved = _replace_first(after, "    terms += optional_work\n", "")
    moved = _replace_first(
        moved,
        "    if optional_work > max_terms - terms:",
        "    terms += optional_work\n    if optional_work > max_terms - terms:",
    )
    assert_not_equal(token_sha256(moved), expected)
    assert_true(_span_hits_counter(moved))


def test_removing_either_capacity_check_changes_the_function() raises:
    """Dropping the entry guard or the second check changes the token digest."""
    var doc = PyJson.parse(Path(_RECORD).read_text())
    var after = _field(doc, "after_complete_function")
    var expected = token_sha256(after)
    var guard = _replace_first(
        after,
        "terms < 0 or terms > max_terms or 1024 > max_terms - terms",
        "1024 > max_terms - terms",
    )
    assert_not_equal(token_sha256(guard), expected)
    assert_false(_span_hits_counter(guard))
    var second = _replace_first(
        after, "optional_work > max_terms - terms", "False"
    )
    assert_not_equal(token_sha256(second), expected)
    var missing = False
    try:
        _ = _span_hits_counter(second)
    except error:
        missing = True
        assert_true(
            String(error).find(
                "Reviewed budget admission, routing or arithmetic changed"
            )
            >= 0
        )
    assert_true(missing)


def main() raises:
    """Run the envelope budget record tests."""
    TestSuite.discover_tests[__functions_in_module()]().run()
