# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""The winner and sign helpers keep their live fees and fresh guards."""

from std.pathlib import Path
from std.testing import TestSuite, assert_equal, assert_true

from tests._python_tokens import (
    _tokenize,
    def_token_sha256,
    token_sha256,
)
from tools._python_json import PyJson
from tools._sha256 import sha256_hex


comptime _RECORD = "tools/carla_lane_oracle/winner-sign-query-migration.json"
"""The reviewed winner and sign record."""
comptime _RECORD_SHA256 = (
    "b154b18213f9f0400661aff93e47b86bf83990c8838dfa0fca00b0fe6710b9a3"
)
"""The SHA-256 of that record."""
comptime _PRIOR = (
    "tools/carla_lane_oracle/default-query-restoration-migration.json"
)
"""The restoration record this review extends."""
comptime _MAP = "extensions/carla/map.mojo"
"""The live map that holds the seed helpers."""
comptime _NEWLINE = 4
comptime _INDENT = 5
comptime _DEDENT = 6


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
        raise Error("missing winner fragment")
    var head = String(text[byte=:at])
    var tail = String(text[byte = at + before.byte_length() :])
    return head + after + tail


def _replace_function(
    source: String, name: String, before: String, after: String
) raises -> String:
    """Replace `before` inside one module-level function.

    Args:
        source: The module.
        name: The function name.
        before: The original fragment.
        after: The replacement.

    Returns:
        The module with that function changed.

    Raises:
        Error: The function or the fragment is missing.
    """
    var marker = "def " + name
    var at = source.find(marker)
    var column = at == 0
    if at > 0:
        column = String(source[byte = at - 1 : at]) == "\n"
    if at < 0 or not column:
        raise Error("missing winner function " + name)
    var rest = String(source[byte=at:])
    var next = rest.find("\ndef ")
    var end = source.byte_length()
    if next >= 0:
        end = at + next
    var chunk = String(source[byte=at:end])
    var head = String(source[byte=:at])
    var tail = String(source[byte=end:])
    return head + _replace_first(chunk, before, after) + tail


def _words(source: String) raises -> List[String]:
    """Return the token words, without spacing or comments.

    Args:
        source: Mojo source.

    Returns:
        Names, numbers, strings, and operators, in order.

    Raises:
        Error: The source cannot be tokenized.
    """
    var kinds = List[Int]()
    var texts = List[String]()
    _tokenize(source, kinds, texts)
    var words = List[String]()
    for index in range(len(kinds)):
        var kind = kinds[index]
        if kind == _NEWLINE or kind == _INDENT or kind == _DEDENT:
            continue
        words.append(texts[index])
    return words^


def _sequence(words: List[String], needle: List[String]) -> Int:
    """Return how many times `needle` occurs in `words`.

    Args:
        words: The token words.
        needle: The required sequence.

    Returns:
        The number of matches.
    """
    var count = 0
    if len(needle) == 0 or len(words) < len(needle):
        return 0
    var index = 0
    while index + len(needle) <= len(words):
        var same = True
        var offset = 0
        while offset < len(needle):
            if words[index + offset] != needle[offset]:
                same = False
                break
            offset += 1
        if same:
            count += 1
        index += 1
    return count


def _contains(source: String, fragment: String, label: String) raises:
    """Require `fragment` once, as token words, inside `source`.

    Args:
        source: The function or module.
        fragment: The required operation.
        label: The refusal text.

    Raises:
        Error: The operation is missing or repeated.
    """
    var actual = _words(source)
    var expected = _words(fragment)
    if _sequence(actual, expected) != 1:
        raise Error("winner/sign source contract: " + label)


def _body(kinds: List[Int], texts: List[String], name: String) raises -> Int:
    """Return the indent token that opens one module-level function.

    Args:
        kinds: The token kinds.
        texts: The token texts.
        name: The function name.

    Returns:
        The index of the body indent.

    Raises:
        Error: The function is missing, repeated, or has no body.
    """
    var depth = 0
    var start_stmt = 0
    var hits = 0
    var indent = -1
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
        var is_def = (
            lead + 1 < index
            and kinds[lead] == 1
            and texts[lead] == "def"
            and kinds[lead + 1] == 1
            and texts[lead + 1] == name
        )
        if depth == 0 and is_def:
            hits += 1
            var body = index + 1
            if body >= len(kinds) or kinds[body] != _INDENT:
                raise Error("unsupported function body: " + name)
            indent = body
        start_stmt = index + 1
    if hits != 1 or indent < 0:
        raise Error("missing or ambiguous function: " + name)
    return indent


def _fresh(source: String, name: String) raises:
    """Require the sum2 guard to be the function's first operation.

    Args:
        source: The module.
        name: The function name.

    Raises:
        Error: Another operation precedes the guard, or the function is missing.
    """
    var kinds = List[Int]()
    var texts = List[String]()
    _tokenize(source, kinds, texts)
    var indent = _body(kinds, texts, name)
    var start = indent + 1
    if (
        start + 3 >= len(kinds)
        or texts[start] != "_require_sum2_environment"
        or texts[start + 1] != "("
        or texts[start + 2] != ")"
        or texts[start + 3] != "\n"
    ):
        raise Error(
            "winner/sign source contract: fresh environment guard must be the"
            " first operation"
        )


def _record() raises -> PyJson:
    """Return the winner record after its file digest matches.

    Returns:
        The parsed record.

    Raises:
        Error: The record bytes changed.
    """
    var raw = Path(_RECORD).read_bytes()
    if sha256_hex(raw) != _RECORD_SHA256:
        raise Error("winner/sign source contract: unreviewed migration record")
    return PyJson.parse(Path(_RECORD).read_text())


def test_live_seed_helpers_keep_their_fees_and_fresh_guards() raises:
    """The four module helpers, their fees, and the two fresh guards stay bound.
    """
    var doc = _record()
    assert_equal(_field(doc, doc.root, "schema"), "1")
    assert_equal(
        sha256_hex(Path(_PRIOR).read_bytes()),
        _field(doc, doc.root, "prior_default_restoration_sha256"),
    )
    var helpers = doc.at(doc.root, "new_helper_source")
    assert_equal(doc.length(helpers), 4)
    var fresh = doc.at(doc.root, "fresh_guard_helpers")
    assert_equal(doc.length(fresh), 2)
    var methods = doc.at(doc.root, "unchanged_public_methods")
    assert_equal(doc.length(methods), 8)
    var canonical = doc.at(doc.root, "canonical_source_unchanged")
    assert_equal(doc.length(canonical), 112)
    var text = Path(_MAP).read_text()
    var names = List[String]()
    names.append("_seed_exact_interval")
    names.append("_seed_reference_domain")
    names.append("_winner_seed_room")
    names.append("_try_winner_seed")
    for name in names:
        _ = def_token_sha256(text, name)
        var owned = False
        try:
            _ = _body_at_map(text, name)
            owned = True
        except error:
            assert_true(
                String(error).find("guard caller owner/scope changed") >= 0
            )
        assert_true(not owned)
    assert_equal(
        def_token_sha256(text, "_seed_exact_interval"),
        token_sha256(doc.text(doc.at(helpers, "_seed_exact_interval"))),
    )
    var missing = False
    try:
        _ = def_token_sha256(text, "_closest_lane_certificate_with_work")
    except error:
        missing = True
        assert_true(String(error).find("missing or ambiguous function") >= 0)
    assert_true(missing)
    _fresh(text, "_seed_reference_domain")
    _fresh(text, "_try_winner_seed")
    _contains(text, "work._step(60)", "fixed admission must be prepaid")
    _contains(
        text, "work._step(12)", "local-band retry must be separately prepaid"
    )
    _contains(text, "for level in range(8):", "dyadic proposal depth changed")
    _contains(
        text,
        "if _wide_point_order(point, incumbent, query) < 0:",
        "only strict exact point improvement can replace the incumbent",
    )
    _contains(
        text,
        "work.charge(0, point_work, node_cost)",
        "scalar proposal work must be charged",
    )
    _contains(
        text,
        "var winner_followup = min(len(winner.cells), 16373) + 12",
        "winner continuation reserve changed",
    )
    _contains(
        text,
        "var target_followup = target_cells + 12",
        "competitor continuation reserve changed",
    )
    _contains(
        text,
        "var winner_units = proof_nodes + 255 + 50",
        "complete regular/tiny term reserve changed",
    )
    _contains(
        text,
        "return target_reference <= terms_left // 50",
        "competitor term reserve changed",
    )


def _body_at_map(source: String, name: String) raises -> Int:
    """Refuse a module helper when it is read as a `Map` method.

    Args:
        source: The module.
        name: The function name.

    Returns:
        This function does not return.

    Raises:
        Error: The helper is a module function, so the `Map` owner is wrong.
    """
    var kinds = List[Int]()
    var texts = List[String]()
    _tokenize(source, kinds, texts)
    _ = _body(kinds, texts, name)
    raise Error(
        "winner/sign source contract: guard caller owner/scope changed: " + name
    )


def test_fee_guard_and_record_edits_are_refused() raises:
    """A fee edit, a moved guard, a comment, or a changed record is refused."""
    var text = Path(_MAP).read_text()
    var cases = List[String]()
    cases.append("work._step(60)")
    cases.append("work._step(59)")
    cases.append("var winner_followup = min(len(winner.cells), 16373) + 12")
    cases.append("var winner_followup = min(len(winner.cells), 16373) + 11")
    cases.append("var target_followup = target_cells + 12")
    cases.append("var target_followup = target_cells + 11")
    cases.append("var winner_units = proof_nodes + 255 + 50")
    cases.append("var winner_units = proof_nodes + 255 + 49")
    cases.append("return target_reference <= terms_left // 50")
    cases.append("return target_reference <= terms_left // 49")
    cases.append("if _wide_point_order(point, incumbent, query) < 0:")
    cases.append("if _wide_point_order(point, incumbent, query) <= 0:")
    cases.append("work.charge(0, point_work, node_cost)")
    cases.append("work.charge(0, 0, node_cost)")
    var index = 0
    while index < len(cases):
        var before = cases[index]
        var after = cases[index + 1]
        if _count(text, before) != 1:
            raise Error("winner/sign source contract: " + before)
        var changed = _replace_first(text, before, after)
        assert_true(token_sha256(changed) != token_sha256(text))
        var refused = False
        try:
            _contains(changed, before, "fee changed")
        except error:
            refused = True
            assert_true(String(error).find("fee changed") >= 0)
        assert_true(refused)
        index += 2
    var guard = "    _require_sum2_environment()\n"
    var helpers = List[String]()
    helpers.append("_seed_reference_domain")
    helpers.append("_try_winner_seed")
    var replacements = List[String]()
    replacements.append("")
    replacements.append("    var cached = True\n")
    for name in helpers:
        for replacement in replacements:
            var changed = _replace_function(text, name, guard, replacement)
            var refused = False
            try:
                _fresh(changed, name)
            except error:
                refused = True
                assert_true(String(error).find("first operation") >= 0)
            assert_true(refused)
    var comment = False
    try:
        _contains("# work._step(60)\n", "work._step(60)", "missing fee")
    except error:
        comment = True
        assert_true(String(error).find("missing fee") >= 0)
    assert_true(comment)
    var raw = Path(_RECORD).read_bytes()
    raw.append(UInt8(32))
    var record = False
    try:
        if sha256_hex(raw) != _RECORD_SHA256:
            raise Error(
                "winner/sign source contract: unreviewed migration record"
            )
    except error:
        record = True
        assert_true(String(error).find("unreviewed migration") >= 0)
    assert_true(record)


def main() raises:
    """Run the winner and sign record tests."""
    TestSuite.discover_tests[__functions_in_module()]().run()
