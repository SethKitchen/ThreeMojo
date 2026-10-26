# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Check the try-only reuse refusal in the lane proof.

The last parameter is `require_reuse` with default False. The reuse edge
returns the unknown point, and that flag has one use.
"""

from tests._python_tokens import _tokenize


comptime _NAME = 1
comptime _NEWLINE = 4
comptime _INDENT = 5
comptime _DEDENT = 6
comptime _OP = 55


def _fail(message: String) raises:
    """Raise a try-only refusal error.

    Args:
        message: The failure text.

    Raises:
        Error: The refusal check failed.
    """
    raise Error("spiral moment try: " + message)


def _bad() raises:
    """Raise a syntax error for the lane proof.

    Raises:
        Error: The source cannot be tokenized.
    """
    _fail("unsupported ideal source syntax")


def _load(source: String, mut kinds: List[Int], mut texts: List[String]) raises:
    """Tokenize `source` into `kinds` and `texts`.

    Args:
        source: Module source.
        kinds: The token kinds, replaced by this call.
        texts: The token texts, replaced by this call.

    Raises:
        Error: The source cannot be tokenized.
    """
    var failed = False
    try:
        _tokenize(source, kinds, texts)
    except error:
        failed = True
    if failed:
        _bad()


def _is_open(kind: Int, text: String) -> Bool:
    """Return whether the token opens a bracket.

    Args:
        kind: The token kind.
        text: The token text.

    Returns:
        True for `(`, `[`, or `{`.
    """
    if kind != _OP:
        return False
    if text == "(":
        return True
    if text == "[":
        return True
    return text == "{"


def _is_close(kind: Int, text: String) -> Bool:
    """Return whether the token closes a bracket.

    Args:
        kind: The token kind.
        text: The token text.

    Returns:
        True for `)`, `]`, or `}`.
    """
    if kind != _OP:
        return False
    if text == ")":
        return True
    if text == "]":
        return True
    return text == "}"


def _locate(
    kinds: List[Int], texts: List[String]
) raises -> Tuple[Int, Int, Int, Int]:
    """Find the lane proof signature and body.

    Args:
        kinds: The token kinds.
        texts: The token texts.

    Returns:
        The parameter open, parameter close, body start, and body end.

    Raises:
        Error: The function is missing or its signature is unsupported.
    """
    var depth = 0
    var fresh = True
    var found = 0
    var name_at = -1
    var index = 0
    while index < len(kinds):
        var kind = kinds[index]
        if kind == _INDENT:
            depth += 1
            fresh = True
            index += 1
            continue
        if kind == _DEDENT:
            depth -= 1
            fresh = True
            index += 1
            continue
        if kind == _NEWLINE:
            if depth == 0:
                fresh = True
            index += 1
            continue
        if depth == 0 and fresh and texts[index] == "def":
            if (
                index + 1 < len(kinds)
                and texts[index + 1] == "_lane_jet_model_proof"
            ):
                found += 1
                name_at = index + 1
        fresh = False
        index += 1
    if found != 1:
        _fail("missing or ambiguous function: _lane_jet_model_proof")
    var cursor = name_at + 1
    if cursor < len(kinds) and _is_open(kinds[cursor], texts[cursor]):
        var brackets = 1
        cursor += 1
        while cursor < len(kinds) and brackets > 0:
            if _is_open(kinds[cursor], texts[cursor]):
                brackets += 1
            elif _is_close(kinds[cursor], texts[cursor]):
                brackets -= 1
            cursor += 1
    if cursor >= len(kinds) or texts[cursor] != "(":
        _fail("try-only parameter changed")
    var param_open = cursor + 1
    var parens = 1
    cursor += 1
    while cursor < len(kinds) and parens > 0:
        if _is_open(kinds[cursor], texts[cursor]):
            parens += 1
        elif _is_close(kinds[cursor], texts[cursor]):
            parens -= 1
        cursor += 1
    var param_close = cursor - 1
    var signature = 0
    while cursor < len(kinds):
        if _is_open(kinds[cursor], texts[cursor]):
            signature += 1
        elif _is_close(kinds[cursor], texts[cursor]):
            signature -= 1
        elif kinds[cursor] == _OP and texts[cursor] == ":" and signature == 0:
            break
        cursor += 1
    if cursor >= len(kinds):
        _fail("unsupported ideal source syntax")
    cursor += 1
    while cursor < len(kinds) and kinds[cursor] == _NEWLINE:
        cursor += 1
    if cursor >= len(kinds) or kinds[cursor] != _INDENT:
        _fail("unsupported ideal source syntax")
    var body_start = cursor + 1
    var indent = 1
    cursor = body_start
    var body_end = len(kinds)
    while cursor < len(kinds):
        if kinds[cursor] == _INDENT:
            indent += 1
        elif kinds[cursor] == _DEDENT:
            indent -= 1
            if indent == 0:
                body_end = cursor
                break
        cursor += 1
    return (param_open, param_close, body_start, body_end)


def _parameter(
    kinds: List[Int], texts: List[String], start: Int, end: Int
) raises:
    """Require the last parameter to be `require_reuse: Bool = False`.

    Args:
        kinds: The token kinds.
        texts: The token texts.
        start: The first parameter token.
        end: The closing parenthesis.

    Raises:
        Error: The parameter or its default changed.
    """
    var segment = start
    var last = start
    var last_end = start
    var depth = 0
    var index = start
    while index < end:
        if _is_open(kinds[index], texts[index]):
            depth += 1
        elif _is_close(kinds[index], texts[index]):
            depth -= 1
        elif kinds[index] == _OP and texts[index] == "," and depth == 0:
            if index > segment:
                last = segment
                last_end = index
            segment = index + 1
        index += 1
    if end > segment:
        last = segment
        last_end = end
    var words = List[String]()
    index = last
    while index < last_end:
        if kinds[index] != _NEWLINE and kinds[index] != _INDENT:
            words.append(texts[index])
        index += 1
    var named = len(words) >= 3
    if named:
        named = words[0] == "require_reuse"
    if named:
        named = words[1] == ":"
    if named:
        named = words[2] == "Bool"
    if not named:
        _fail("try-only parameter changed")
    var kept = len(words) == 5
    if kept:
        kept = words[3] == "="
    if kept:
        kept = words[4] == "False"
    if not kept:
        _fail("try-only default must preserve historical callers")


def _single_name(
    kinds: List[Int], texts: List[String], mut index: Int, end: Int
) -> String:
    """Read a test that is one name, and move past its colon.

    Args:
        kinds: The token kinds.
        texts: The token texts.
        index: The first test token. Updated past the colon.
        end: The limit.

    Returns:
        The name, or empty when the test is not one name.
    """
    var name = String("")
    var extra = False
    var depth = 0
    while index < end:
        var kind = kinds[index]
        var text = texts[index]
        if _is_open(kind, text):
            depth += 1
            extra = True
        elif _is_close(kind, text):
            depth -= 1
            extra = True
        elif kind == _OP and text == ":" and depth == 0:
            index += 1
            break
        elif kind == _NAME and name.byte_length() == 0:
            name = text
        elif kind != _NEWLINE:
            extra = True
        index += 1
    if extra:
        return ""
    return name


def _suite(
    kinds: List[Int],
    texts: List[String],
    index: Int,
    end: Int,
    mut statements: List[String],
) -> Int:
    """Read one suite and return the index after it.

    Args:
        kinds: The token kinds.
        texts: The token texts.
        index: The token after the colon.
        end: The limit.
        statements: One string per direct statement, in order.

    Returns:
        The first token after the suite.
    """
    var cursor = index
    while cursor < end and kinds[cursor] == _NEWLINE:
        cursor += 1
    if cursor >= end or kinds[cursor] != _INDENT:
        return cursor
    var depth = 1
    var bracket = 0
    var current = String("")
    var saw = False
    cursor += 1
    while cursor < end and depth > 0:
        var kind = kinds[cursor]
        if kind == _INDENT:
            depth += 1
        elif kind == _DEDENT:
            depth -= 1
            if depth == 0 and saw:
                statements.append(current)
                current = ""
                saw = False
        elif kind == _NEWLINE and depth == 1 and bracket == 0:
            if saw:
                statements.append(current)
                current = ""
                saw = False
        elif depth == 1 and kind != _NEWLINE:
            if _is_open(kind, texts[cursor]):
                bracket += 1
            elif _is_close(kind, texts[cursor]):
                bracket -= 1
            if saw:
                current += " "
            current += texts[cursor]
            saw = True
        cursor += 1
    return cursor


def _skip_lines(kinds: List[Int], index: Int, end: Int) -> Int:
    """Skip newlines.

    Args:
        kinds: The token kinds.
        index: The first token.
        end: The limit.

    Returns:
        The first token that is not a newline.
    """
    var cursor = index
    while cursor < end and kinds[cursor] == _NEWLINE:
        cursor += 1
    return cursor


def _refusal(
    kinds: List[Int], texts: List[String], start: Int, end: Int
) raises:
    """Require one top-level `if reused` with the reviewed elif.

    Args:
        kinds: The token kinds.
        texts: The token texts.
        start: The first body token.
        end: The body end.

    Raises:
        Error: The refusal moved or changed.
    """
    var depth = 1
    var fresh = True
    var reused = 0
    var missing = False
    var changed = False
    var index = start
    while index < end:
        var kind = kinds[index]
        if kind == _INDENT:
            depth += 1
            fresh = True
            index += 1
            continue
        if kind == _DEDENT:
            depth -= 1
            fresh = True
            index += 1
            continue
        if kind == _NEWLINE:
            if depth == 1:
                fresh = True
            index += 1
            continue
        if depth == 1 and fresh and texts[index] == "if":
            index += 1
            var test = _single_name(kinds, texts, index, end)
            var body = List[String]()
            index = _suite(kinds, texts, index, end, body)
            index = _skip_lines(kinds, index, end)
            var orelse_if = False
            var branch_ok = False
            if index < end and texts[index] == "elif":
                orelse_if = True
                index += 1
                var elif_test = _single_name(kinds, texts, index, end)
                var branch = List[String]()
                index = _suite(kinds, texts, index, end, branch)
                index = _skip_lines(kinds, index, end)
                var followed = False
                if index < end and texts[index] == "elif":
                    followed = True
                if index < end and texts[index] == "else":
                    followed = True
                var body_ok = len(branch) == 1
                if body_ok:
                    body_ok = branch[0] == "return _unknown_point ( )"
                branch_ok = (
                    elif_test == "require_reuse" and body_ok and followed
                )
            while index < end and (
                texts[index] == "elif" or texts[index] == "else"
            ):
                if texts[index] == "else":
                    index += 1
                    if index < end and texts[index] == ":":
                        index += 1
                else:
                    index += 1
                    _ = _single_name(kinds, texts, index, end)
                var rest = List[String]()
                index = _suite(kinds, texts, index, end, rest)
                index = _skip_lines(kinds, index, end)
            if test == "reused":
                reused += 1
                if not orelse_if:
                    missing = True
                elif not branch_ok:
                    changed = True
            fresh = True
            continue
        fresh = False
        index += 1
    var bad_count = reused != 1
    if bad_count:
        missing = True
    if missing:
        _fail("try-only refusal missing from reuse/fallback edge")
    if changed:
        _fail("try-only refusal changed")


def _uses(kinds: List[Int], texts: List[String], start: Int, end: Int) raises:
    """Require one body use of `require_reuse`.

    Args:
        kinds: The token kinds.
        texts: The token texts.
        start: The first body token.
        end: The body end.

    Raises:
        Error: The flag is missing or used again.
    """
    var count = 0
    var index = start
    while index < end:
        if kinds[index] == _NAME and texts[index] == "require_reuse":
            var dotted = False
            if (
                index > 0
                and kinds[index - 1] == _OP
                and texts[index - 1] == "."
            ):
                dotted = True
            if not dotted:
                count += 1
        index += 1
    if count != 1:
        _fail("try-only flag has an unreviewed use")


def try_only_refusal(source: String) raises:
    """Require the reviewed try-only reuse refusal.

    Args:
        source: The module that defines `_lane_jet_model_proof`.

    Raises:
        Error: The parameter, the refusal, or a flag use changed.
    """
    var kinds = List[Int]()
    var texts = List[String]()
    _load(source, kinds, texts)
    var place = _locate(kinds, texts)
    _parameter(kinds, texts, place[0], place[1])
    _refusal(kinds, texts, place[2], place[3])
    _uses(kinds, texts, place[2], place[3])
