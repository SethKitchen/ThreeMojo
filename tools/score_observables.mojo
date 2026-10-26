# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Check the reviewed score observables.

The winner-seed caller keeps one upper assignment. That assignment is read
as the score high. The fresh guard and the ordered debits match the
historical caller. A missing assignment or a changed debit is refused.
"""

from std.pathlib import Path

from tests._map_score_predecessor import (
    restored_deviation,
    score_endpoint,
    station_endpoint,
)
from tests._python_tokens import _tokenize
from tools.count_source import count_source
from tools.frontier_predecessor import frontier_predecessor_source
from tools.optional_predecessor import optional_predecessor_source
from tools.score_operation_graphs import _declaration, score_operation_graphs
from tools.score_predecessor import score_predecessor_source
from tools.support_predecessor import support_predecessor_source


comptime _MAP = "extensions/carla/map.mojo"
comptime _CALLER = "_try_winner_seed"
comptime _NEWLINE = 4
comptime _INDENT = 5
comptime _DEDENT = 6
comptime _UPPER = "certificate.upper = update[1]"
comptime _HIGH = "certificate.upper = score.high"
comptime _MISSING = (
    "reviewed seed-count successor: missing unique score upper correspondence"
)
comptime _DEBITS = (
    "reviewed seed-count successor: live fresh-environment guard or ordered"
    " debits changed"
)


def _fail(message: String) raises:
    """Raise a score-observable error.

    Args:
        message: The failure text.

    Raises:
        Error: The score observable check failed.
    """
    raise Error(message)


def _count(text: String, needle: String) -> Int:
    """Return the number of non-overlapping matches.

    Args:
        text: The source.
        needle: The exact byte sequence.

    Returns:
        The number of matches.
    """
    var count = 0
    var offset = 0
    var size = text.byte_length()
    var step = needle.byte_length()
    if step == 0:
        return 0
    while offset < size:
        var rest = String(text[byte=offset:])
        var at = rest.find(needle)
        if at < 0:
            return count
        count += 1
        offset += at + step
    return count


def require_unique_score_upper(caller: String) raises -> String:
    """Read the one upper assignment as the score high.

    Args:
        caller: The winner-seed caller.

    Returns:
        The caller with that assignment rewritten.

    Raises:
        Error: The assignment is missing or repeated.
    """
    if _count(caller, _UPPER) != 1:
        _fail(_MISSING)
    return caller.replace(_UPPER, _HIGH)


def _debit(words: String) -> Bool:
    """Return whether a statement is an ordered debit.

    Args:
        words: The statement's token texts, separated by spaces.

    Returns:
        True for a guarded step, charge, or certificate write.
    """
    if words.startswith("work . _step") or words.startswith("work . charge"):
        return True
    if words.startswith("certificate . nodes"):
        return True
    if words.startswith("certificate . terms"):
        return True
    if words.startswith("certificate . s ") or words == "certificate . s":
        return True
    if words.startswith("certificate . point"):
        return True
    return words.startswith("certificate . upper")


def score_observable_text(caller: String) raises -> String:
    """Return the fresh guard and the ordered debit statements.

    Args:
        caller: One winner-seed caller.

    Returns:
        The first body statement and each debit statement.

    Raises:
        Error: The caller cannot be tokenized.
    """
    var kinds = List[Int]()
    var texts = List[String]()
    _tokenize(caller, kinds, texts)
    var depth = 0
    var words = ""
    var first = ""
    var debits = ""
    var index = 0
    while index < len(kinds):
        var kind = kinds[index]
        if kind == _INDENT:
            depth += 1
        elif kind == _DEDENT:
            depth -= 1
        elif kind == _NEWLINE:
            if words != "":
                if first == "" and depth == 1:
                    first = words
                if _debit(words):
                    if debits != "":
                        debits += "\n"
                    debits += String(depth) + " " + words
                words = ""
        else:
            if words != "":
                words += " "
            words += texts[index]
        index += 1
    return first + "\n" + debits


def score_observables(root: String) raises:
    """Require the live score guard and the ordered debits.

    Args:
        root: The repository root.

    Raises:
        Error: The caller, the upper assignment, or a debit changed.
    """
    var base = root
    if base.byte_length() > 1 and base.endswith("/"):
        var end = base.byte_length() - 1
        var trimmed = String(base[byte=0:end])
        base = trimmed
    var live = Path(base + "/" + _MAP).read_text()
    score_operation_graphs(live)
    var normalized = require_unique_score_upper(_declaration(live, _CALLER))
    var deviation = restored_deviation(live)
    var station = station_endpoint(deviation)
    var score = score_endpoint(station)
    var frontier = score_predecessor_source(score)
    var support = frontier_predecessor_source(frontier)
    var optional = support_predecessor_source(support)
    var count = optional_predecessor_source(optional)
    var historical = count_source(count)
    var prior = _declaration(historical, _CALLER)
    if score_observable_text(normalized) != score_observable_text(prior):
        _fail(_DEBITS)


def main() raises:
    """Check the score observables of this repository.

    Raises:
        Error: The live Map or the historical caller changed.
    """
    score_observables(".")
