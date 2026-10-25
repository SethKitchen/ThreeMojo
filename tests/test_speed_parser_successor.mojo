# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""The speed parser record rejects a changed grammar line."""

from std.pathlib import Path
from std.testing import TestSuite, assert_equal, assert_not_equal, assert_true

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
comptime _NAME = 1
comptime _NUMBER = 2
comptime _STRING = 3
comptime _NEWLINE = 4
comptime _INDENT = 5
comptime _DEDENT = 6
comptime _OP = 55


def _record() raises -> PyJson:
    """Return the speed-parser record.

    Returns:
        The parsed record.

    Raises:
        Error: The record file cannot be read or parsed.
    """
    return PyJson.parse(Path(_MIGRATION).read_text())


def _push(
    mut kinds: List[Int], mut texts: List[String], kind: Int, var text: String
):
    """Append one token.

    Args:
        kinds: The token kinds.
        texts: The token texts, in the same order.
        kind: The Python token number.
        text: The token text.
    """
    kinds.append(kind)
    texts.append(text^)


def _tokenize(
    source: String, mut kinds: List[Int], mut texts: List[String]
) raises:
    """Tokenize `source` as CPython 3.12 `tokenize.generate_tokens` does.

    The kept tokens are names, numbers, strings, newlines, indents, dedents
    and operators. Comments and blank lines are omitted.

    Args:
        source: Mojo source that uses spaces and ASCII quotes.
        kinds: The token kinds, replaced by this call.
        texts: The token texts, replaced by this call.

    Raises:
        Error: The source has an unclosed string, a bad indent, or an
            unclosed bracket.
    """
    var text = source
    if not text.endswith("\n"):
        text += "\n"
    var data = text.as_bytes()
    var levels = List[Int]()
    levels.append(0)
    var index = 0
    var depth = 0
    while index < len(data):
        var line_start = index
        var column = 0
        while index < len(data) and (data[index] == 32 or data[index] == 9):
            if data[index] == 9:
                column = column - column % 8 + 8
            else:
                column += 1
            index += 1
        var blank = index >= len(data) or data[index] == 10 or data[index] == 35
        if depth == 0 and not blank:
            if column > levels[len(levels) - 1]:
                var spaces = String(text[byte=line_start:index])
                _push(kinds, texts, _INDENT, spaces^)
                levels.append(column)
            else:
                while column < levels[len(levels) - 1]:
                    _ = levels.pop()
                    _push(kinds, texts, _DEDENT, String())
                if column != levels[len(levels) - 1]:
                    raise Error("invalid source tokens: bad indent")
        while index < len(data):
            if data[index] == 10 and depth == 0:
                break
            var byte = data[index]
            if byte == 32 or byte == 9:
                index += 1
                continue
            if byte == 10:
                index += 1
                continue
            if byte == 35 and depth == 0:
                while index < len(data) and data[index] != 10:
                    index += 1
                break
            if byte == 34 or byte == 39:
                var quote = byte
                var mark = index
                index += 1
                var triple = (
                    index + 1 < len(data)
                    and data[index] == quote
                    and data[index + 1] == quote
                )
                if triple:
                    index += 2
                var closed = False
                while index < len(data):
                    if (
                        triple
                        and index + 2 < len(data)
                        and data[index] == quote
                        and data[index + 1] == quote
                        and data[index + 2] == quote
                    ):
                        index += 3
                        closed = True
                        break
                    if not triple and data[index] == quote:
                        index += 1
                        closed = True
                        break
                    if data[index] == 10 and not triple:
                        raise Error("invalid source tokens: unclosed string")
                    index += 1
                if not closed:
                    raise Error("invalid source tokens: unclosed string")
                var literal = String(text[byte=mark:index])
                _push(kinds, texts, _STRING, literal^)
                continue
            var name_start = (
                (byte >= 65 and byte <= 90)
                or (byte >= 97 and byte <= 122)
                or byte == 95
            )
            if name_start:
                var mark = index
                index += 1
                while index < len(data):
                    var next = data[index]
                    var keep = (
                        (next >= 65 and next <= 90)
                        or (next >= 97 and next <= 122)
                        or (next >= 48 and next <= 57)
                        or next == 95
                    )
                    if not keep:
                        break
                    index += 1
                var name = String(text[byte=mark:index])
                _push(kinds, texts, _NAME, name^)
                continue
            var number_start = (byte >= 48 and byte <= 57) or (
                byte == 46
                and index + 1 < len(data)
                and data[index + 1] >= 48
                and data[index + 1] <= 57
            )
            if number_start:
                var mark = index
                if byte != 46:
                    while (
                        index < len(data)
                        and data[index] >= 48
                        and data[index] <= 57
                    ):
                        index += 1
                if (
                    index < len(data)
                    and data[index] == 46
                    and index + 1 < len(data)
                    and data[index + 1] >= 48
                    and data[index + 1] <= 57
                ):
                    index += 1
                    while (
                        index < len(data)
                        and data[index] >= 48
                        and data[index] <= 57
                    ):
                        index += 1
                var number = String(text[byte=mark:index])
                _push(kinds, texts, _NUMBER, number^)
                continue
            var two = String()
            if index + 1 < len(data):
                two = String(text[byte = index : index + 2])
            if (
                two == "!="
                or two == "+="
                or two == "->"
                or two == "<="
                or two == ">="
                or two == "=="
                or two == "//"
                or two == "**"
            ):
                _push(kinds, texts, _OP, two^)
                index += 2
                continue
            if byte == 40 or byte == 91 or byte == 123:
                depth += 1
            elif byte == 41 or byte == 93 or byte == 125:
                depth -= 1
                if depth < 0:
                    raise Error("invalid source tokens: extra closer")
            var operator = String(chr(Int(byte)))
            _push(kinds, texts, _OP, operator^)
            index += 1
        if index < len(data) and data[index] == 10:
            index += 1
            if depth == 0 and not blank:
                _push(kinds, texts, _NEWLINE, String("\n"))
    if depth != 0:
        raise Error("invalid source tokens: unclosed bracket")
    while len(levels) > 1:
        _ = levels.pop()
        _push(kinds, texts, _DEDENT, String())


def _token_sha256(source: String) raises -> String:
    """Return the SHA-256 of the kept tokens, as the speed record does.

    Args:
        source: Mojo source.

    Returns:
        The hex digest of the canonical JSON token list.

    Raises:
        Error: The source cannot be tokenized.
    """
    var kinds = List[Int]()
    var texts = List[String]()
    _tokenize(source, kinds, texts)
    var doc = PyJson()
    var rows = doc.new_list()
    for index in range(len(kinds)):
        var pair = doc.new_list()
        doc.append(pair, doc.new_int(kinds[index]))
        doc.append(pair, doc.new_str(texts[index]))
        doc.append(rows, pair)
    doc.root = rows
    return sha256_hex(doc.dumps().as_bytes())


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
    if _token_sha256(text) != expected:
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
    assert_equal(_token_sha256(before), _field(doc, "before_token_sha256"))
    assert_equal(_token_sha256(after), _field(doc, "after_token_sha256"))
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
