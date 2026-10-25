# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Check the live winner-seed guard and debit statements.

The first operation stays the environment guard. The debit statements match
the pin after the one upper assignment is read as the score high.
"""

from std.pathlib import Path

from tests._python_tokens import _tokenize
from tools._python_json import PY_STR, PyJson
from tools.sum2_guard_callers import _esc, _function_text


comptime _PINS = "tools/carla_lane_oracle/sum2-guard-pins.json"
comptime _MAP = "extensions/carla/map.mojo"
comptime _NAME = "_try_winner_seed"
comptime _LIVE_UPPER = "certificate.upper = update[1]"
comptime _PIN_UPPER = "certificate.upper = score.high"
comptime _NEWLINE = 4
comptime _INDENT = 5
comptime _DEDENT = 6


def _fail(message: String) raises:
    """Raise a winner-seed error.

    Args:
        message: The failure text.

    Raises:
        Error: The live winner seed changed.
    """
    raise Error(message)


def _count(text: String, needle: String) -> Int:
    """Return how many times `needle` occurs in `text`.

    Args:
        text: The source.
        needle: The exact byte sequence.

    Returns:
        The number of non-overlapping matches.
    """
    var count = 0
    var offset = 0
    var size = text.byte_length()
    var step = needle.byte_length()
    while offset < size:
        var rest = String(text[byte=offset:])
        var at = rest.find(needle)
        if at < 0:
            return count
        count += 1
        offset += at + step
    return count


def _debit(texts: List[String]) -> Bool:
    """Return whether a statement is a reviewed debit.

    Args:
        texts: The token texts of one statement.

    Returns:
        True for a work or certificate debit.
    """
    if len(texts) < 3:
        return False
    if texts[0] == "work" and texts[1] == ".":
        return texts[2] == "_step" or texts[2] == "charge"
    if texts[0] != "certificate" or texts[1] != ".":
        return False
    if texts[2] == "nodes" or texts[2] == "terms" or texts[2] == "s":
        return True
    return texts[2] == "point" or texts[2] == "upper"


def _encode(depth: Int, kinds: List[Int], texts: List[String]) -> String:
    """Return one statement as a depth and its tokens.

    Args:
        depth: The indent depth at the statement end.
        kinds: The token kinds.
        texts: The token texts.

    Returns:
        The statement encoding.
    """
    var out = String("[" + String(depth) + ",[")
    var index = 0
    while index < len(kinds):
        if index > 0:
            out += ","
        out += "[" + String(kinds[index]) + "," + _esc(texts[index]) + "]"
        index += 1
    out += "]]"
    return out


def _observables(source: String) raises -> String:
    """Return the fresh guard and the debit statements.

    Args:
        source: One function.

    Returns:
        The guard, then the debit statements.

    Raises:
        Error: The function has no depth-one statement.
    """
    var kinds = List[Int]()
    var texts = List[String]()
    _tokenize(source, kinds, texts)
    var depth = 0
    var statement_kinds = List[Int]()
    var statement_texts = List[String]()
    var first = String("")
    var have_first = False
    var debits = String("[")
    var debit_count = 0
    var index = 0
    while index < len(kinds):
        var kind = kinds[index]
        if kind == _INDENT:
            depth += 1
        elif kind == _DEDENT:
            depth -= 1
        elif kind == _NEWLINE:
            if len(statement_kinds) > 0:
                var encoded = _encode(depth, statement_kinds, statement_texts)
                if depth == 1 and not have_first:
                    first = encoded
                    have_first = True
                if _debit(statement_texts):
                    if debit_count > 0:
                        debits += ","
                    debits += encoded
                    debit_count += 1
                statement_kinds.clear()
                statement_texts.clear()
        else:
            statement_kinds.append(kind)
            statement_texts.append(texts[index])
        index += 1
    if not have_first:
        _fail("Sum2 live winner-seed fresh guard or debit statements changed")
    debits += "]"
    return first + "|" + debits


def sum2_winner_seed(root: String) raises:
    """Require the live winner-seed guard and debit statements.

    Args:
        root: The repository root.

    Raises:
        Error: The guard, a debit, or the upper assignment changed.
    """
    var base = root
    if base.byte_length() > 1 and base.endswith("/"):
        var end = base.byte_length() - 1
        var trimmed = String(base[byte=0:end])
        base = trimmed
    var doc = PyJson.parse(Path(base + "/" + _PINS).read_text())
    var callers = doc.at(doc.root, "callers")
    var record = doc.at(callers, "map")
    var functions = doc.at(record, "functions")
    var pinned = doc.at(functions, _NAME)
    if doc.kind(pinned) != PY_STR:
        _fail("Sum2 live winner-seed fresh guard or debit statements changed")
    var live = _function_text(Path(base + "/" + _MAP).read_text(), _NAME)
    if _count(live, _LIVE_UPPER) != 1:
        _fail("missing unique score upper correspondence")
    var normalized = live.replace(_LIVE_UPPER, _PIN_UPPER)
    if _observables(normalized) != _observables(doc.text(pinned)):
        _fail("Sum2 live winner-seed fresh guard or debit statements changed")
