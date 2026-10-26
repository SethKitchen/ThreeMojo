# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Check the live lane-search edges.

One frontier loop keeps the current-cell work debit. The fresh producer
follows that debit. Dispatch setup stays after the depth refusal.
"""

from tests._python_tokens import _tokenize
from tools._optional_runtime_semantics import _extract
from tools._sampled_value_copies import _normalize


comptime _NEWLINE = 4
comptime _INDENT = 5
comptime _DEDENT = 6
comptime _OP = 55


def _fail(message: String) raises:
    """Raise a lane-search error.

    Args:
        message: The failure text.

    Raises:
        Error: A live lane-search edge changed.
    """
    raise Error("optional runtime contract: " + message)


def _opens(text: String) -> Bool:
    """Return whether `text` opens a bracket.

    Args:
        text: One token.

    Returns:
        True for `(`, `[`, or `{`.
    """
    return text == "(" or text == "[" or text == "{"


def _closes(text: String) -> Bool:
    """Return whether `text` closes a bracket.

    Args:
        text: One token.

    Returns:
        True for `)`, `]`, or `}`.
    """
    return text == ")" or text == "]" or text == "}"


def _load(source: String, mut kinds: List[Int], mut texts: List[String]) raises:
    """Tokenize `source`.

    Args:
        source: Function source.
        kinds: The token kinds, replaced by this call.
        texts: The token texts, replaced by this call.

    Raises:
        Error: The source cannot be tokenized.
    """
    _tokenize(source, kinds, texts)


def _join(rows: List[String]) -> String:
    """Join statements with spaces.

    Args:
        rows: The statements.

    Returns:
        The joined text.
    """
    var out = String("")
    var index = 0
    while index < len(rows):
        if index > 0:
            out += " "
        out += rows[index]
        index += 1
    return out


def _count(text: String, needle: String) -> Int:
    """Return the number of times `needle` occurs.

    Args:
        text: The text to scan.
        needle: The text to count.

    Returns:
        The number of occurrences.
    """
    var count = 0
    var rest = text
    var at = rest.find(needle)
    while at >= 0:
        count += 1
        var tail = String(rest[byte = at + needle.byte_length() :])
        rest = tail
        at = rest.find(needle)
    return count


def _spans(
    kinds: List[Int],
    texts: List[String],
    begin: Int,
    end: Int,
    mut starts: List[Int],
    mut stops: List[Int],
    mut rows: List[String],
):
    """Record each direct statement in a suite.

    Args:
        kinds: The token kinds.
        texts: The token texts.
        begin: The first token of the suite.
        end: The token that closes the suite.
        starts: Statement starts, appended by this call.
        stops: Statement ends, appended by this call.
        rows: Normalized statements, appended by this call.
    """
    var depth = 1
    var bracket = 0
    var origin = begin
    var index = begin
    while index < end:
        var kind = kinds[index]
        var text = texts[index]
        if kind == _INDENT:
            depth += 1
        elif kind == _DEDENT:
            depth -= 1
        elif kind == _OP and _opens(text):
            bracket += 1
        elif kind == _OP and _closes(text):
            bracket -= 1
        var done = False
        if kind == _DEDENT and depth == 1:
            done = True
        if kind == _NEWLINE and depth == 1 and bracket == 0:
            var nxt = index + 1
            if nxt >= end or kinds[nxt] != _INDENT:
                done = True
        if done:
            starts.append(origin)
            stops.append(index + 1)
            rows.append(_normalize(kinds, texts, origin, index + 1, False))
            origin = index + 1
        index += 1
    if origin < end:
        starts.append(origin)
        stops.append(end)
        rows.append(_normalize(kinds, texts, origin, end, False))


def _suite(
    kinds: List[Int], texts: List[String], start: Int, stop: Int
) -> Tuple[Int, Int]:
    """Return the token span of the first suite in a statement.

    Args:
        kinds: The token kinds.
        texts: The token texts.
        start: The first token of the statement.
        stop: The token after the statement.

    Returns:
        The first body token and the closing dedent. Both are -1 when the
        statement has no suite.
    """
    var bracket = 0
    var cursor = start
    var colon = -1
    while cursor < stop:
        var text = texts[cursor]
        if _opens(text):
            bracket += 1
        elif _closes(text):
            bracket -= 1
        elif kinds[cursor] == _OP and text == ":" and bracket == 0:
            colon = cursor
            break
        cursor += 1
    if colon < 0:
        return (-1, -1)
    cursor = colon + 1
    while cursor < stop and kinds[cursor] == _NEWLINE:
        cursor += 1
    if cursor >= stop or kinds[cursor] != _INDENT:
        return (-1, -1)
    var depth = 1
    cursor += 1
    var body = cursor
    while cursor < stop and depth > 0:
        if kinds[cursor] == _INDENT:
            depth += 1
        elif kinds[cursor] == _DEDENT:
            depth -= 1
            if depth == 0:
                return (body, cursor)
        cursor += 1
    return (body, stop)


def _snippet(text: String) raises -> List[String]:
    """Return the normalized statements of a fragment.

    Args:
        text: One or more statements.

    Returns:
        Each direct statement.

    Raises:
        Error: The fragment cannot be tokenized.
    """
    var source = String("def _snippet():\n")
    var rest = text
    var reading = True
    while reading:
        var nl = rest.find("\n")
        var line = rest
        if nl >= 0:
            line = String(rest[byte=0:nl])
            var nxt = String(rest[byte = nl + 1 :])
            rest = nxt
        else:
            reading = False
        if line.byte_length() > 0:
            source += "    "
            source += line
            source += "\n"
    var kinds = List[Int]()
    var texts = List[String]()
    _load(source, kinds, texts)
    var header = _suite(kinds, texts, 0, len(kinds))
    var starts = List[Int]()
    var stops = List[Int]()
    var rows = List[String]()
    _spans(kinds, texts, header[0], header[1], starts, stops, rows)
    return rows^


def _prefix(rows: List[String], wanted: List[String]) -> Bool:
    """Return whether `rows` starts with `wanted`.

    Args:
        rows: The actual statements.
        wanted: The required prefix.

    Returns:
        True when every required statement matches in order.
    """
    if len(rows) < len(wanted):
        return False
    var index = 0
    while index < len(wanted):
        if rows[index] != wanted[index]:
            return False
        index += 1
    return True


def lane_search_edges(source: String) raises:
    """Require the reviewed live lane-search edges.

    Args:
        source: The `lane_refinement` module.

    Raises:
        Error: A frontier loop, debit, producer, cut, or dispatch edge changed.
    """
    var kinds = List[Int]()
    var texts = List[String]()
    _load(_extract(source, "_run_lane_search"), kinds, texts)
    var header = _suite(kinds, texts, 0, len(kinds))
    if header[0] < 0:
        _fail("one original search frontier loop")
    var starts = List[Int]()
    var stops = List[Int]()
    var rows = List[String]()
    _spans(kinds, texts, header[0], header[1], starts, stops, rows)
    var loops = 0
    var loop_at = -1
    var index = 0
    while index < len(rows):
        if rows[index].startswith("while "):
            loops += 1
            loop_at = index
        index += 1
    if loops != 1 or loop_at < 0:
        _fail("one original search frontier loop")
    var loop_suite = _suite(kinds, texts, starts[loop_at], stops[loop_at])
    var loop_starts = List[Int]()
    var loop_stops = List[Int]()
    var loop_rows = List[String]()
    _spans(
        kinds,
        texts,
        loop_suite[0],
        loop_suite[1],
        loop_starts,
        loop_stops,
        loop_rows,
    )
    var choice = -1
    index = 0
    while index < len(loop_rows):
        if loop_rows[index].startswith("if work >= 0 :"):
            if choice >= 0:
                choice = -2
            else:
                choice = index
        index += 1
    if choice < 1:
        _fail("fresh cell producer must use original reference admission")
    var work = _snippet("var work = _reference_work(road, lo, hi)")
    if len(work) != 1 or loop_rows[choice - 1] != work[0]:
        _fail("fresh cell producer must use current cell work")
    var producer = _snippet(
        'if certificate.terms > max_terms - work:\n    raise Error("Lane'
        ' refinement exhausted its quadrature work limit")\ncertificate.terms'
        " += work\nvar point_domain: Tuple[_Jet, _Jet, _Jet]\nif frozen:\n   "
        " point_domain = _frozen_arc_center(frozen.value(), lo, hi, Vector3(0,"
        " 0, 0))\nelse:\n    point_domain = _lane_jet_with_proof(road, section,"
        " lane, lo, hi, low, high, spiral_proof)\nvar natural ="
        " _scaled_point_distance_box(point_domain, location, scale).low"
    )
    var arm = _suite(kinds, texts, loop_starts[choice], loop_stops[choice])
    var arm_starts = List[Int]()
    var arm_stops = List[Int]()
    var arm_rows = List[String]()
    _spans(kinds, texts, arm[0], arm[1], arm_starts, arm_stops, arm_rows)
    if not _prefix(arm_rows, producer):
        _fail(
            "fresh current-cell producer must immediately follow original debit"
        )
    var cuts = _snippet(
        "var sampled_cuts: Optional[Tuple[Float64, Float64, Int]] = None"
    )
    var best = _snippet("var best = certificate.s")
    var point = _snippet("var best_point = certificate.point.copy()")
    var found_cuts = 0
    var found_best = 0
    var found_point = 0
    index = 0
    while index < len(rows):
        if len(cuts) == 1 and rows[index] == cuts[0]:
            found_cuts += 1
        if len(best) == 1 and rows[index] == best[0]:
            found_best += 1
        if len(point) == 1 and rows[index] == point[0]:
            found_point += 1
        index += 1
    if found_cuts != 1:
        _fail("cut lifetime is one search invocation")
    if found_best != 1:
        _fail("incumbent is the validated actual certificate witness")
    if found_point != 1:
        _fail("retain actual witness point")
    var setup = -1
    index = 0
    while index < len(loop_rows):
        if loop_rows[index].startswith("if not sampled_checked :"):
            if setup >= 0:
                setup = -2
            else:
                setup = index
        index += 1
    if setup < 1:
        _fail("dispatch setup remains deferred in the original node")
    var depth = _snippet(
        'if task[2] >= max_depth:\n    raise Error("Lane refinement exhausted'
        ' its numerical accuracy limit")'
    )
    if len(depth) != 1 or loop_rows[setup - 1] != depth[0]:
        _fail("depth refusal precedes dispatch setup")
    var split = _snippet(
        "bitcast[DType.float64](bitcast[DType.uint64](split_at) - UInt64(1))"
    )
    if len(split) != 1 or _count(_join(rows), split[0]) != 1:
        _fail("split predecessor preserves every stored owner station")
