# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""The cache-key successor keeps its three exact edits and predecessor bytes."""

from std.pathlib import Path
from std.testing import TestSuite, assert_equal, assert_true

from tests._python_tokens import token_sha256
from tools._python_json import PyJson
from tools._sha256 import sha256_hex


comptime _RECORD = "tools/carla_lane_oracle/cache-key-migration.json"
"""The reviewed cache-key record."""
comptime _RECORD_SHA256 = (
    "06f0aefb02a1f897563f4e7d25e0a26f3fc56f1bef5f3fcb8eb68b5cd1188d5b"
)
"""The SHA-256 of that record."""
comptime _BEFORE_SHA256 = (
    "13afed281e9df7549d3acb022680e2e20a57ea54411817eed6f45bf9042e5938"
)
"""The SHA-256 of the predecessor, which is the lane-order successor."""
comptime _BEFORE_TOKEN = (
    "ad94f8e2a32d175b01e55f3e226c676a9aee371b49e00fc7b502ab56b6acfb46"
)
"""The token digest of that predecessor."""
comptime _AFTER_TOKEN = (
    "9893380d70f28a8cd85d41f21cb05102905f4ba528e7916437ba4397058895e0"
)
"""The token digest of the cache-key successor."""
comptime _MODULE = "extensions/carla/lane_refinement.mojo"
"""The lane module this edge names."""
comptime _ORACLE = "tools/carla_lane_oracle/"
"""The directory that holds the preserved records."""


def _field(doc: PyJson, node: Int, name: String) raises -> String:
    """Return one string field.

    Args:
        doc: The document.
        node: The object.
        name: The field name.

    Returns:
        The field text.

    Raises:
        Error: The field is absent.
    """
    return doc.text(doc.at(node, name))


def _count(text: String, needle: String) -> Int:
    """Return how many times `needle` occurs.

    Args:
        text: The source.
        needle: The fragment.

    Returns:
        The number of matches.
    """
    var count = 0
    var rest = text
    while True:
        var at = rest.find(needle)
        if at < 0:
            return count
        count += 1
        var tail = String(rest[byte = at + needle.byte_length() :])
        rest = tail


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
        raise Error("cache-key successor: missing or duplicate delta")
    var head = String(text[byte=:at])
    var tail = String(text[byte = at + before.byte_length() :])
    return head + after + tail


def _record() raises -> PyJson:
    """Return the cache-key record after its file digest matches.

    Returns:
        The parsed record.

    Raises:
        Error: The record bytes changed.
    """
    var raw = Path(_RECORD).read_bytes()
    if sha256_hex(raw) != _RECORD_SHA256:
        raise Error("cache-key successor: migration record changed")
    return PyJson.parse(Path(_RECORD).read_text())


def _reverse(text: String, doc: PyJson) raises -> String:
    """Undo the three exact edits and require the predecessor bytes.

    Args:
        text: The successor source.
        doc: The cache-key record.

    Returns:
        The predecessor source.

    Raises:
        Error: The source, the edit set, or the reconstructed bytes differ.
    """
    var after = _field(doc, doc.root, "after")
    var before = _field(doc, doc.root, "before")
    var current = text
    if current != after or sha256_hex(current.as_bytes()) != _field(
        doc, doc.root, "after_sha256"
    ):
        raise Error(
            "cache-key successor: complete live successor bytes changed"
        )
    var edits = doc.at(doc.root, "edits")
    if doc.length(edits) != 3:
        raise Error("cache-key successor: wrong exact delta set")
    var names = List[String]()
    names.append("helper")
    names.append("cached_fast")
    names.append("cached_expansion")
    var index = 0
    while index < 3:
        var edit = doc.item(edits, index)
        if _field(doc, edit, "name") != names[index]:
            raise Error("cache-key successor: wrong exact delta set")
        var fragment = _field(doc, edit, "after")
        if _count(current, fragment) != 1:
            raise Error(
                "cache-key successor: missing or duplicate delta: "
                + names[index]
            )
        current = _replace_first(current, fragment, _field(doc, edit, "before"))
        index += 1
    if current != before or sha256_hex(current.as_bytes()) != _BEFORE_SHA256:
        raise Error(
            "cache-key successor: byte-exact predecessor reconstruction failed"
        )
    return current


def test_the_three_edits_restore_the_lane_order_successor() raises:
    """The three edits restore the predecessor, and the preserved records stay bound.
    """
    var doc = _record()
    assert_equal(_field(doc, doc.root, "schema"), "1")
    assert_equal(_field(doc, doc.root, "module"), _MODULE)
    var before = _field(doc, doc.root, "before")
    var after = _field(doc, doc.root, "after")
    assert_equal(sha256_hex(before.as_bytes()), _BEFORE_SHA256)
    assert_equal(token_sha256(before), _BEFORE_TOKEN)
    assert_equal(
        sha256_hex(after.as_bytes()), _field(doc, doc.root, "after_sha256")
    )
    assert_equal(token_sha256(after), _AFTER_TOKEN)
    assert_equal(_reverse(after, doc), before)
    var preserved = doc.at(doc.root, "preserved_records")
    assert_equal(doc.length(preserved), 12)
    var index = 0
    while index < doc.length(preserved):
        var name = doc.key(preserved, index)
        assert_equal(
            sha256_hex(Path(_ORACLE + name).read_bytes()),
            doc.text(doc.value(preserved, index)),
        )
        index += 1
    var commented = "# inert cache-key comment\n" + after
    assert_equal(token_sha256(commented), _AFTER_TOKEN)
    var refused = False
    try:
        _ = _reverse(commented, doc)
    except error:
        refused = True
        assert_true(
            String(error).find("complete live successor bytes changed") >= 0
        )
    assert_true(refused)


def test_helper_edits_and_a_changed_delta_set_are_refused() raises:
    """A helper edit changes the successor digest, and a changed delta set is refused.
    """
    var doc = _record()
    var after = _field(doc, doc.root, "after")
    var cases = List[String]()
    cases.append("](station, scale) == SIMD")
    cases.append("](station, scale) != SIMD")
    cases.append("](station, scale)")
    cases.append("](scale, station)")
    cases.append("station: UInt64, scale: UInt64")
    cases.append("station: UInt32, scale: UInt64")
    cases.append("SIMD[DType.uint64, 2]")
    cases.append("SIMD[DType.uint64, 4]")
    cases.append("cached_fast.value()[0],")
    cases.append("cached_fast.value()[1],")
    cases.append("cached_expansion.value()[1],")
    cases.append("cached_expansion.value()[0],")
    cases.append("and _same_cache_key(")
    cases.append("and wrong_key(")
    cases.append("and cached_fast\n")
    cases.append("and True\n")
    cases.append("certificate.terms += work")
    cases.append("certificate.terms += 0")
    cases.append("if task[2] >= max_depth:")
    cases.append("if task[2] > max_depth:")
    cases.append("var best = certificate.s")
    cases.append("var best = low")
    var index = 0
    while index < len(cases):
        var changed = _replace_first(after, cases[index], cases[index + 1])
        assert_true(token_sha256(changed) != _AFTER_TOKEN)
        index += 2
    var extras = List[String]()
    extras.append(
        "\ndef unexpected():\n    return _same_cache_key(1, 2, 1, 2)\n"
    )
    extras.append("\nalias hidden_key = _same_cache_key\n")
    extras.append(
        "\ndef _same_cache_key(a: UInt64) -> Bool:\n    return True\n"
    )
    extras.append("\nfrom elsewhere import SIMD\n")
    for extra in extras:
        assert_true(token_sha256(after + extra) != _AFTER_TOKEN)
    var edits = doc.at(doc.root, "edits")
    var fast = doc.item(edits, 1)
    var wrong = _replace_first(after, _field(doc, fast, "after"), "")
    assert_true(wrong != _field(doc, doc.root, "before"))
    var partial = after
    var step = 0
    while step < 2:
        var edit = doc.item(edits, step)
        partial = _replace_first(
            partial, _field(doc, edit, "after"), _field(doc, edit, "before")
        )
        step += 1
    assert_true(partial != _field(doc, doc.root, "before"))
    var raw = Path(_RECORD).read_text()
    var renamed = _replace_first(raw, "cached_fast", "cached_wrong")
    assert_true(sha256_hex(renamed.as_bytes()) != _RECORD_SHA256)


def main() raises:
    """Run the cache-key record tests."""
    TestSuite.discover_tests[__functions_in_module()]().run()
