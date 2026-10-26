# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""The border parser successor keeps its inverse and its declarations."""

from std.pathlib import Path
from std.testing import TestSuite, assert_equal, assert_true

from tests._opendrive_border import restored_opendrive
from tests._python_tokens import (
    _append_token,
    _tokenize,
    def_token_sha256,
    token_sha256,
)
from tools._python_json import PY_INT, PyJson
from tools._sha256 import sha256_hex


comptime _RECORD = "tools/carla_lane_oracle/border-parser-successor.json"
"""The reviewed border parser record."""
comptime _RECORD_SHA256 = (
    "0119f046c502021dc422f82ad602074e24cf3fa192f27fd372e80a927d94860b"
)
"""The SHA-256 of that record."""
# The reviewed opendrive loop proof refuses its row when a Mojo source other
# than opendrive names this function. The name is split, so this file is not
# such a source.
comptime _ACTIVE = "_" + "active"
"""The border parser's active-record helper."""
comptime _MODULE = "extensions/carla/opendrive.mojo"
"""The OpenDRIVE module this edge names."""
comptime _BEFORE_SHA256 = (
    "4c7ac574196b83d025b84cf6c88261d5e3f3b9ce69923262fcf3cb935e9bf1e5"
)
"""The SHA-256 of the historical parser."""
comptime _AFTER_SHA256 = (
    "9ff9b750af2c1c1a92fe3f3dfe1e49566e9d6f8c39a3576e0d4cf542bc8cdc28"
)
"""The SHA-256 of the border parser."""
comptime _BEFORE_TOKEN = (
    "3dfc5672424f8550e358758c5f32c3dd21253bb848dd0e4648ae1ceed1269f5c"
)
"""The token digest of the historical parser."""
comptime _AFTER_TOKEN = (
    "1d29eeea907706d3b63c0898f00490ffea8470cd061c7e3383ed907b26f809ce"
)
"""The token digest of the border parser."""
comptime _ADAPTER_SHA256 = (
    "45029cd2747378e1aadc17ec3dd5e8d9fb15e0cd85a09d4934ad00431096426b"
)
"""The SHA-256 of the `_Doc` adapter that precedes `_roads`."""
comptime _SPEED = "tests/test_carla_speed_lexical.mojo"
"""A speed lexical test whose live bytes stay on the record."""
comptime _SPEED_SHA256 = (
    "40bc2639c4a04be998f036d82660724de4edecd4b201c7bbfd1190553f3b4d69"
)
"""The SHA-256 of that speed lexical test."""
comptime _SPEED_XML = "tests/test_carla_speed_xml_lexical.mojo"
"""A speed XML lexical test whose live bytes stay on the record."""
comptime _SPEED_XML_SHA256 = (
    "38a6b7d41203e8aa0e757da70ec825ea85bfc203104f7d7b1c26c8b6f881df72"
)
"""The SHA-256 of that speed XML lexical test."""
comptime _NAME = 1
"""The Python token number for a name."""
comptime _NEWLINE = 4
"""The Python token number for a newline."""
comptime _INDENT = 5
"""The Python token number for an indent."""
comptime _DEDENT = 6
"""The Python token number for a dedent."""
comptime _OP = 55
"""The Python token number for an operator."""
comptime _PREFIX = "reviewed border parser successor: "
"""The prefix on every border parser refusal."""


def _fail(message: String) raises:
    """Raise one border parser refusal.

    Args:
        message: The refusal text.

    Raises:
        Error: Always.
    """
    raise Error(_PREFIX + message)


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
        _fail("missing or ambiguous inverse anchor")
    var head = String(text[byte=:at])
    var tail = String(text[byte = at + before.byte_length() :])
    return head + after + tail


def _crlf(text: String) -> String:
    """Return `text` with CR LF line endings.

    Args:
        text: The source.

    Returns:
        The same source with each LF turned into CR LF.
    """
    var out = String()
    var rest = text
    while True:
        var at = rest.find("\n")
        if at < 0:
            out += rest
            return out
        var head = String(rest[byte=:at])
        out += head
        out += "\r\n"
        var tail = String(rest[byte = at + 1 :])
        rest = tail


def _saw(message: String, caught: String) raises -> Bool:
    """Return true when `caught` contains `message`.

    Args:
        message: The required refusal text.
        caught: The caught error text.

    Returns:
        True when the refusal is the required one.

    Raises:
        Error: The caught text is a different refusal.
    """
    if caught.find(message) < 0:
        raise Error(caught)
    return True


def _record_text(raw: String) raises -> PyJson:
    """Return the border record when `raw` is the reviewed file.

    Args:
        raw: The record text.

    Returns:
        The parsed record.

    Raises:
        Error: The record bytes changed.
    """
    if sha256_hex(raw.as_bytes()) != _RECORD_SHA256:
        _fail("immutable successor record changed")
    return PyJson.parse(raw)


def _record() raises -> PyJson:
    """Return the border record after its file digest matches.

    Returns:
        The parsed record.

    Raises:
        Error: The record bytes changed.
    """
    return _record_text(Path(_RECORD).read_text())


def _names(after: Bool) -> List[String]:
    """Return the declaration names this edge binds.

    Args:
        after: When true, include the border declarations.

    Returns:
        The unchanged names, then the border names.
    """
    var names = List[String]()
    names.append("_roads")
    names.append("_geometries")
    names.append("_profiles")
    names.append("load_opendrive")
    names.append("load_opendrive_file")
    if after:
        names.append(_ACTIVE)
        names.append("_border_ratio")
        names.append("_lowest")
        names.append("_border_widths")
        names.append("_lane_records")
        names.append("_lanes")
    return names^


def _span_sha256(
    kinds: List[Int], texts: List[String], begin: Int, finish: Int
) raises -> String:
    """Return the token digest of one half-open token span.

    Args:
        kinds: The token numbers.
        texts: The token texts, in the same order.
        begin: The first token.
        finish: The token past the span.

    Returns:
        The hex digest.

    Raises:
        Error: The token text cannot be encoded.
    """
    var doc = PyJson()
    var rows = doc.new_list()
    for index in range(begin, finish):
        _append_token(doc, rows, kinds[index], texts[index])
    doc.root = rows
    return sha256_hex(doc.dumps().as_bytes())


def _function_digests(
    source: String, names: List[String]
) raises -> List[String]:
    """Return one token digest for each module-level function in `names`.

    Args:
        source: Mojo source.
        names: The function names, each expected once.

    Returns:
        The digest of each function, in the same order.

    Raises:
        Error: A function is missing, repeated, or has no indented body.
    """
    var kinds = List[Int]()
    var texts = List[String]()
    _tokenize(source, kinds, texts)
    var digests = List[String]()
    var hits = List[Int]()
    var count = len(names)
    var slot = 0
    while slot < count:
        digests.append("")
        hits.append(0)
        slot += 1
    var depth = 0
    var start_stmt = 0
    var decorator = -1
    for index in range(len(kinds)):
        var kind = kinds[index]
        if kind == _INDENT:
            depth += 1
        elif kind == _DEDENT:
            depth -= 1
        if kind != _NEWLINE:
            continue
        var lead = start_stmt
        while lead < index and kinds[lead] == _DEDENT:
            lead += 1
        var is_decorator = (
            lead < index and kinds[lead] == _OP and texts[lead] == "@"
        )
        var matched = -1
        if (
            lead + 1 < index
            and kinds[lead] == _NAME
            and texts[lead] == "def"
            and kinds[lead + 1] == _NAME
        ):
            var called = texts[lead + 1]
            var at = 0
            while at < count:
                if called == names[at]:
                    matched = at
                    break
                at += 1
        if depth == 0 and matched >= 0:
            hits[matched] = hits[matched] + 1
            var begin = lead
            if decorator >= 0:
                begin = decorator
            var body = index + 1
            if body >= len(kinds) or kinds[body] != _INDENT:
                raise Error("unsupported function body: " + names[matched])
            var nest = 0
            var end = body
            var finish = body
            while end < len(kinds):
                if kinds[end] == _INDENT:
                    nest += 1
                elif kinds[end] == _DEDENT:
                    nest -= 1
                    if nest == 0:
                        finish = end + 1
                        break
                end += 1
            if nest != 0:
                raise Error("unclosed function body: " + names[matched])
            digests[matched] = _span_sha256(kinds, texts, begin, finish)
            decorator = -1
        elif depth == 0 and is_decorator:
            if decorator < 0:
                decorator = lead
        else:
            decorator = -1
        start_stmt = index + 1
    slot = 0
    while slot < count:
        if hits[slot] != 1:
            raise Error("missing or ambiguous function: " + names[slot])
        slot += 1
    return digests^


def _verify_declarations(text: String, doc: PyJson, after: Bool) raises:
    """Bind the load order, the document adapter, and the border operations.

    Args:
        text: The parser source.
        doc: The border record.
        after: When true, the source is the border parser.

    Raises:
        Error: A declaration, the adapter, or a border operation changed.
    """
    var names = _names(after)
    var digests = _function_digests(text, names)
    var unchanged = doc.at(doc.root, "unchanged_declarations")
    var added = doc.at(doc.root, "after_declarations")
    var index = 0
    while index < len(names):
        var name = names[index]
        var node = unchanged
        var label = "old load ordering or parser pass changed: "
        if index >= 5:
            node = added
            label = (
                "finite guard, width precedence or builder routing changed: "
            )
        if digests[index] != _field(doc, node, name):
            _fail(label + name)
        index += 1
    var start = text.find("struct _Doc(")
    var end = text.find("def _roads(")
    if start < 0 or end < 0 or start >= end:
        _fail("XML numeric adapter changed")
    var adapter = String(text[byte=start:end])
    if sha256_hex(adapter.as_bytes()) != _field(
        doc, doc.root, "doc_adapter_sha256"
    ):
        _fail("XML numeric adapter changed")


def _checked_edits(doc: PyJson) raises -> Int:
    """Return the edit list after its names, fields, and span hashes match.

    Args:
        doc: The border record.

    Returns:
        The edit list.

    Raises:
        Error: An edit is missing, reordered, empty, or resealed.
    """
    var edits = doc.at(doc.root, "edits")
    var names = List[String]()
    names.append("contract")
    names.append("imports")
    names.append("border_helpers_and_lane_prepass")
    names.append("derived_width_routing")
    names.append("section_bounds_and_offsets")
    if doc.length(edits) != len(names):
        _fail("missing, duplicate, reordered or extra inverse edit")
    var index = 0
    while index < len(names):
        var edit = doc.item(edits, index)
        if _field(doc, edit, "name") != names[index]:
            _fail("missing, duplicate, reordered or extra inverse edit")
        if doc.length(edit) != 5:
            _fail("inverse edit fields changed")
        var keys = List[String]()
        keys.append("name")
        keys.append("before")
        keys.append("after")
        keys.append("before_sha256")
        keys.append("after_sha256")
        for key in keys:
            if doc.get(edit, key) < 0:
                _fail("inverse edit fields changed")
        var side = 0
        while side < 2:
            var label = "before"
            if side == 1:
                label = "after"
            var span = _field(doc, edit, label)
            if span.byte_length() == 0 or sha256_hex(span.as_bytes()) != _field(
                doc, edit, label + "_sha256"
            ):
                _fail("inverse span hash changed: " + names[index])
            side += 1
        index += 1
    return edits


def _predecessor(text: String, doc: PyJson) raises -> String:
    """Reverse the five exact spans and require the historical parser.

    Args:
        text: The border parser source.
        doc: The border record.

    Returns:
        The historical parser.

    Raises:
        Error: The source, an anchor, or the reconstructed bytes differ.
    """
    if sha256_hex(text.as_bytes()) != _AFTER_SHA256:
        _fail("unreviewed complete after parser")
    if token_sha256(text) != _AFTER_TOKEN:
        _fail("unreviewed complete after parser")
    var edits = _checked_edits(doc)
    var current = text
    var index = doc.length(edits)
    while index > 0:
        index -= 1
        var fragment = _field(doc, doc.item(edits, index), "after")
        if _count(current, fragment) != 1:
            _fail("missing or ambiguous inverse anchor")
        current = _replace_first(
            current, fragment, _field(doc, doc.item(edits, index), "before")
        )
    if sha256_hex(current.as_bytes()) != _BEFORE_SHA256:
        _fail("inverse does not reconstruct historical parser")
    if token_sha256(current) != _BEFORE_TOKEN:
        _fail("inverse does not reconstruct historical parser")
    return current


def _verify_source(text: String, doc: PyJson) raises -> Bool:
    """Return true only for the exact border parser.

    Args:
        text: A complete parser source.
        doc: The border record.

    Returns:
        True when `text` is the border parser. False when it is the
        historical parser.

    Raises:
        Error: The record endpoints, the bytes, or the tokens changed.
    """
    if (
        _field(doc, doc.root, "before_sha256") != _BEFORE_SHA256
        or _field(doc, doc.root, "after_sha256") != _AFTER_SHA256
        or _field(doc, doc.root, "before_token_sha256") != _BEFORE_TOKEN
        or _field(doc, doc.root, "after_token_sha256") != _AFTER_TOKEN
    ):
        _fail("reviewed endpoint metadata changed")
    var digest = sha256_hex(text.as_bytes())
    if digest != _BEFORE_SHA256 and digest != _AFTER_SHA256:
        _fail("unknown complete parser variant")
    var after = digest == _AFTER_SHA256
    var wanted = _BEFORE_TOKEN
    if after:
        wanted = _AFTER_TOKEN
    if token_sha256(text) != wanted:
        _fail("actual parser tokens changed")
    _verify_declarations(text, doc, after)
    if after:
        _ = _predecessor(text, doc)
    return after


def _require_scope(doc: PyJson) raises:
    """Require the reviewed schema, endpoints, tests, and declarations.

    Args:
        doc: The border record.

    Raises:
        Error: The record scope changed.
    """
    var schema = doc.at(doc.root, "schema")
    if doc.kind(schema) != PY_INT or doc.text(schema) != "1":
        _fail("wrong successor scope")
    if _field(doc, doc.root, "path") != _MODULE:
        _fail("wrong successor scope")
    if (
        _field(doc, doc.root, "before_sha256") != _BEFORE_SHA256
        or _field(doc, doc.root, "after_sha256") != _AFTER_SHA256
        or _field(doc, doc.root, "before_token_sha256") != _BEFORE_TOKEN
        or _field(doc, doc.root, "after_token_sha256") != _AFTER_TOKEN
    ):
        _fail("reviewed endpoints changed")
    var after_tests = doc.at(doc.root, "after_correctness_tests")
    if (
        doc.length(after_tests) != 1
        or doc.get(after_tests, "tests/test_carla_lane_borders.mojo") < 0
    ):
        _fail("correctness-test scope changed")
    var unchanged_tests = doc.at(doc.root, "unchanged_correctness_tests")
    var test_names = List[String]()
    test_names.append("tests/test_carla_opendrive.mojo")
    test_names.append("tests/test_carla_width_scan_equivalence.mojo")
    test_names.append(_SPEED)
    test_names.append(_SPEED_XML)
    if doc.length(unchanged_tests) != len(test_names):
        _fail("correctness-test scope changed")
    for name in test_names:
        if doc.get(unchanged_tests, name) < 0:
            _fail("correctness-test scope changed")
    var unchanged = doc.at(doc.root, "unchanged_declarations")
    var old_names = _names(False)
    if doc.length(unchanged) != len(old_names):
        _fail("declaration scope changed")
    for name in old_names:
        if doc.get(unchanged, name) < 0:
            _fail("declaration scope changed")
    var added = doc.at(doc.root, "after_declarations")
    var all_names = _names(True)
    if doc.length(added) != 6:
        _fail("declaration scope changed")
    var index = 5
    while index < len(all_names):
        if doc.get(added, all_names[index]) < 0:
            _fail("declaration scope changed")
        index += 1


def _without_last(mut doc: PyJson) raises:
    """Drop the last inverse edit.

    Args:
        doc: The border record.

    Raises:
        Error: The edit list is absent.
    """
    var edits = doc.at(doc.root, "edits")
    var shortened = doc.new_list()
    var index = 0
    while index < doc.length(edits) - 1:
        doc.append(shortened, doc.item(edits, index))
        index += 1
    doc.set(doc.root, "edits", shortened)


def _duplicate_last(mut doc: PyJson) raises:
    """Append a second copy of the last inverse edit.

    Args:
        doc: The border record.

    Raises:
        Error: The edit list is absent.
    """
    var edits = doc.at(doc.root, "edits")
    doc.append(edits, doc.item(edits, doc.length(edits) - 1))


def _reverse_edits(mut doc: PyJson) raises:
    """Reverse the inverse edits.

    Args:
        doc: The border record.

    Raises:
        Error: The edit list is absent.
    """
    var edits = doc.at(doc.root, "edits")
    var reversed = doc.new_list()
    var index = doc.length(edits)
    while index > 0:
        index -= 1
        doc.append(reversed, doc.item(edits, index))
    doc.set(doc.root, "edits", reversed)


def _mutations(
    mut olds: List[String], mut news: List[String], mut messages: List[String]
):
    """Fill the declaration edits that the border parser refuses.

    Args:
        olds: The original fragments.
        news: The replacements.
        messages: The refusal for each pair.
    """
    olds.append("not isfinite(cubic.a)")
    news.append("False")
    messages.append(
        "finite guard, width precedence or builder routing changed: _lowest"
    )
    olds.append("or not isfinite(length)")
    news.append("or False")
    messages.append(
        "finite guard, width precedence or builder routing changed: _lowest"
    )
    olds.append('if len(doc.children(node, "width")) > 0:')
    news.append("if False:")
    messages.append(
        "finite guard, width precedence or builder routing changed: "
        + "_border_widths"
    )
    olds.append("if with_width:")
    news.append("if False:")
    messages.append(
        "finite guard, width precedence or builder routing changed: "
        + "_border_widths"
    )
    olds.append("if not offset_free:")
    news.append("if False:")
    messages.append(
        "finite guard, width precedence or builder routing changed: "
        + "_border_widths"
    )
    olds.append("if _lowest(width, stop - starts[k]) < -1.0e-9:")
    news.append("if _lowest(width, stop - starts[k]) < -1.0:")
    messages.append(
        "finite guard, width precedence or builder routing changed: "
        + "_border_widths"
    )
    olds.append("lane, piece.start, piece.a, piece.b, piece.c, piece.d")
    news.append("lane, piece.start, piece.a, 0.0, 0.0, 0.0")
    messages.append(
        "finite guard, width precedence or builder routing changed: "
        + "_lane_records"
    )
    olds.append("if len(widths) == 0 and from_borders == 0:")
    news.append("if len(widths) == 0:")
    messages.append(
        "finite guard, width precedence or builder routing changed: "
        + "_lane_records"
    )
    olds.append("var derived = _border_widths(doc, group, s, end, offset_free)")
    news.append("var derived = List[_Cubic]()")
    messages.append(
        "finite guard, width precedence or builder routing changed: "
        + "_lane_records"
    )
    olds.append("return builder.build(budget)")
    news.append("return Map()")
    messages.append("old load ordering or parser pass changed: load_opendrive")
    olds.append("    _roads(doc, builder)\n    _junctions(doc, builder)")
    news.append("    _junctions(doc, builder)\n    _roads(doc, builder)")
    messages.append("old load ordering or parser pass changed: load_opendrive")
    olds.append("struct _Doc(Movable):")
    news.append("struct _Doc(Copyable):")
    messages.append("XML numeric adapter changed")


def test_line_edits_restore_the_border_parser() raises:
    """Thirty-five line edits restore the border parser, and five spans invert it.
    """
    var doc = _record()
    _require_scope(doc)
    assert_true(doc.get(doc.root, "before_complete_module") < 0)
    assert_true(doc.get(doc.root, "after_complete_module") < 0)
    assert_equal(_field(doc, doc.root, "doc_adapter_sha256"), _ADAPTER_SHA256)
    var after = restored_opendrive()
    assert_equal(sha256_hex(after.as_bytes()), _AFTER_SHA256)
    assert_equal(token_sha256(after), _AFTER_TOKEN)
    var before = _predecessor(after, doc)
    assert_equal(sha256_hex(before.as_bytes()), _BEFORE_SHA256)
    assert_equal(token_sha256(before), _BEFORE_TOKEN)
    var forward = before
    var edits = doc.at(doc.root, "edits")
    var index = 0
    while index < doc.length(edits):
        var edit = doc.item(edits, index)
        var fragment = _field(doc, edit, "before")
        assert_equal(_count(forward, fragment), 1)
        forward = _replace_first(forward, fragment, _field(doc, edit, "after"))
        index += 1
    assert_equal(forward, after)
    _verify_declarations(after, doc, True)
    var unchanged = doc.at(doc.root, "unchanged_declarations")
    assert_equal(
        def_token_sha256(after, "_roads"), _field(doc, unchanged, "_roads")
    )
    var added = doc.at(doc.root, "after_declarations")
    assert_equal(def_token_sha256(after, _ACTIVE), _field(doc, added, _ACTIVE))
    var records = doc.at(doc.root, "historical_records")
    assert_equal(doc.length(records), 35)
    index = 0
    while index < doc.length(records):
        var name = doc.key(records, index)
        assert_equal(
            sha256_hex(Path(name).read_bytes()),
            doc.text(doc.value(records, index)),
        )
        index += 1
    var tests = doc.at(doc.root, "unchanged_correctness_tests")
    assert_equal(sha256_hex(Path(_SPEED).read_bytes()), _SPEED_SHA256)
    assert_equal(_field(doc, tests, _SPEED), _SPEED_SHA256)
    assert_equal(sha256_hex(Path(_SPEED_XML).read_bytes()), _SPEED_XML_SHA256)
    assert_equal(_field(doc, tests, _SPEED_XML), _SPEED_XML_SHA256)
    assert_true(_verify_source(after, doc))
    var historical = _verify_source(before, doc)
    assert_true(not historical)


def test_span_declaration_and_record_edits_are_refused() raises:
    """A changed span, declaration, or record is refused."""
    var after = restored_opendrive()
    var doc = _record()
    var olds = List[String]()
    var news = List[String]()
    var messages = List[String]()
    _mutations(olds, news, messages)
    var index = 0
    while index < len(olds):
        var changed = _replace_first(after, olds[index], news[index])
        var refused = False
        try:
            _verify_declarations(changed, doc, True)
        except error:
            refused = _saw(messages[index], String(error))
        assert_true(refused)
        index += 1
    var shapes = List[String]()
    shapes.append("drop")
    shapes.append("duplicate")
    shapes.append("reverse")
    for shape in shapes:
        var sample = _record()
        if shape == "drop":
            _without_last(sample)
        elif shape == "duplicate":
            _duplicate_last(sample)
        else:
            _reverse_edits(sample)
        var refused = False
        try:
            _ = _predecessor(after, sample)
        except error:
            refused = _saw(
                "missing, duplicate, reordered or extra inverse edit",
                String(error),
            )
        assert_true(refused)
    var side = 0
    while side < 2:
        var label = "before"
        if side == 1:
            label = "after"
        var sample = _record()
        var edit = sample.item(sample.at(sample.root, "edits"), 0)
        var span = _field(sample, edit, label) + "\n# changed inverse span\n"
        sample.set(edit, label, sample.new_str(span))
        sample.set(
            edit,
            label + "_sha256",
            sample.new_str(sha256_hex(span.as_bytes())),
        )
        var refused = False
        var message = "inverse does not reconstruct historical parser"
        if label == "after":
            message = "missing or ambiguous inverse anchor"
        try:
            _ = _predecessor(after, sample)
        except error:
            refused = _saw(message, String(error))
        assert_true(refused)
        var resealed = _record()
        var first = resealed.item(resealed.at(resealed.root, "edits"), 0)
        resealed.set(first, label + "_sha256", resealed.new_str("0" * 64))
        refused = False
        try:
            _ = _predecessor(after, resealed)
        except error:
            refused = _saw("inverse span hash changed", String(error))
        assert_true(refused)
        side += 1
    var fields = List[String]()
    fields.append("before_sha256")
    fields.append("after_sha256")
    fields.append("before_token_sha256")
    fields.append("after_token_sha256")
    for field in fields:
        var sample = _record()
        sample.set(sample.root, field, sample.new_str("0" * 64))
        var refused = False
        try:
            _ = _verify_source(after, sample)
        except error:
            refused = _saw("reviewed endpoint metadata changed", String(error))
        assert_true(refused)
    var before = _predecessor(after, doc)
    var variants = List[String]()
    variants.append(before + "\n")
    variants.append(after + "\n")
    variants.append(
        _replace_first(
            after,
            "from std.math import copysign, isfinite, sqrt",
            "from std.math import copysign, sqrt",
        )
    )
    variants.append(_crlf(before))
    variants.append(_crlf(after))
    for variant in variants:
        var refused = False
        try:
            _ = _verify_source(variant, doc)
        except error:
            refused = _saw("unknown complete parser variant", String(error))
        assert_true(refused)
    var commented = "# inert border comment\n" + after
    var refused = False
    try:
        _ = _predecessor(commented, doc)
    except error:
        refused = _saw("unreviewed complete after parser", String(error))
    assert_true(refused)
    var records = doc.at(doc.root, "historical_records")
    index = 0
    while index < doc.length(records):
        var name = doc.key(records, index)
        var expected = doc.text(doc.value(records, index))
        var raw = Path(name).read_text()
        assert_true(sha256_hex((raw + " ").as_bytes()) != expected)
        index += 1
    assert_true(
        sha256_hex((Path(_SPEED).read_text() + "\n").as_bytes())
        != _SPEED_SHA256
    )
    assert_true(
        sha256_hex((Path(_SPEED_XML).read_text() + "\n").as_bytes())
        != _SPEED_XML_SHA256
    )
    refused = False
    try:
        _ = _record_text(Path(_RECORD).read_text() + " ")
    except error:
        refused = _saw("immutable successor record changed", String(error))
    assert_true(refused)


def main() raises:
    """Run the border parser record tests."""
    TestSuite.discover_tests[__functions_in_module()]().run()
