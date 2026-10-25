# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""The speed parser record rejects a changed grammar line."""

from std.pathlib import Path
from std.testing import TestSuite, assert_equal, assert_not_equal, assert_true

from tests._python_tokens import token_sha256
from tools._python_json import PyJson
from tools._sha256 import sha256_hex


comptime _MIGRATION = "tools/carla_lane_oracle/speed-parser-successor.json"
"""The reviewed speed-parser record."""
comptime _MIGRATION_SHA256 = (
    "47e949673fb8740816c06d455654c7e7ae43f65ce7d7568a201e83ae16c49364"
)
"""The SHA-256 of that record."""
comptime _ACCEPTED = "tools/carla_lane_oracle/accepted-successor-migration.json"
"""The migration the speed record names as its predecessor."""


def _record() raises -> PyJson:
    """Return the speed-parser record.

    Returns:
        The parsed record.

    Raises:
        Error: The record file cannot be read or parsed.
    """
    return PyJson.parse(Path(_MIGRATION).read_text())


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


def _replace_once(text: String, before: String, after: String) raises -> String:
    """Replace the one occurrence of `before`.

    Args:
        text: The source.
        before: The original line fragment.
        after: The replacement.

    Returns:
        The changed source.

    Raises:
        Error: `before` is missing or repeated.
    """
    var at = text.find(before)
    if at < 0:
        raise Error("missing grammar line")
    if text.find(before, at + before.byte_length()) >= 0:
        raise Error("ambiguous grammar line")
    var head = String(text[byte=:at])
    var tail = String(text[byte = at + before.byte_length() :])
    return head + after + tail


def _grammar(text: String, expected: String) raises:
    """Require the token digest of `text` to equal `expected`.

    Args:
        text: The module source.
        expected: The recorded token digest.

    Raises:
        Error: The grammar, validation, binding, or mantissa graph changed.
    """
    if token_sha256(text) != expected:
        raise Error(
            "reviewed speed parser successor: actual grammar, validation,"
            " binding or mantissa graph changed"
        )


def test_recorded_speed_modules_keep_their_digests() raises:
    """Both recorded speed modules keep their byte and token digests."""
    var raw = Path(_MIGRATION).read_bytes()
    assert_equal(sha256_hex(raw), _MIGRATION_SHA256)
    var doc = PyJson.parse(Path(_MIGRATION).read_text())
    assert_equal(_field(doc, "schema"), "1")
    assert_equal(_field(doc, "path"), "extensions/carla/speed_limits.mojo")
    assert_not_equal(_field(doc, "before_sha256"), _field(doc, "after_sha256"))
    var before = _field(doc, "before_complete_module")
    var after = _field(doc, "after_complete_module")
    assert_equal(sha256_hex(before.as_bytes()), _field(doc, "before_sha256"))
    assert_equal(sha256_hex(after.as_bytes()), _field(doc, "after_sha256"))
    assert_equal(token_sha256(before), _field(doc, "before_token_sha256"))
    assert_equal(token_sha256(after), _field(doc, "after_token_sha256"))
    var tests = doc.at(doc.root, "correctness_tests")
    assert_equal(doc.length(tests), 2)
    for index in range(doc.length(tests)):
        var path = doc.key(tests, index)
        var digest = doc.text(doc.value(tests, index))
        assert_equal(sha256_hex(Path(path).read_bytes()), digest)
        var changed = Path(path).read_bytes()
        changed.append(UInt8(32))
        assert_not_equal(sha256_hex(changed), digest)
    var prior = _field(doc, "prior_accepted_migration_sha256")
    assert_equal(sha256_hex(Path(_ACCEPTED).read_bytes()), prior)
    raw.append(UInt8(32))
    assert_not_equal(sha256_hex(raw), _MIGRATION_SHA256)


def test_a_grammar_line_change_revokes_the_recorded_module() raises:
    """Each grammar mutation changes the recorded token digest."""
    var doc = _record()
    var after = _field(doc, "after_complete_module")
    var expected = _field(doc, "after_token_sha256")
    _grammar(after, expected)
    var cases = List[String]()
    cases.append("if not _speed_decimal_syntax(number):")
    cases.append("if False:")
    cases.append("if byte >= 48 and byte <= 57:")
    cases.append("if byte >= 48:")
    cases.append("if byte >= 49:")
    cases.append("if byte >= 48:")
    cases.append("if byte == 101 or byte == 69:")
    cases.append("if byte == 69:")
    cases.append("mantissa_digits > 0")
    cases.append("mantissa_digits >= 0")
    var index = 0
    while index < len(cases):
        var changed = _replace_once(after, cases[index], cases[index + 1])
        var failed = False
        try:
            _grammar(changed, expected)
        except error:
            failed = True
            assert_true(
                String(error).find(
                    "actual grammar, validation, binding or mantissa graph"
                    " changed"
                )
                >= 0
            )
        assert_true(failed)
        index += 2


def main() raises:
    """Run the speed parser record tests."""
    TestSuite.discover_tests[__functions_in_module()]().run()
