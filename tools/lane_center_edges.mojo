# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Check the live lane-center edges.

The proof memo and the translated memo keep the station and scale words.
The grouped caller keeps the prepaid fallback. The support call keeps the
same ideal and the actual witness.
"""

from tests._python_tokens import _tokenize
from tools.lane_search_edges import _count, _snippet, _spans, _suite
from tools.optional_runtime_semantics import _extract
from tools.sampled_value_copies import _normalize


def _fail(message: String) raises:
    """Raise a lane-center error.

    Args:
        message: The failure text.

    Raises:
        Error: A live lane-center edge changed.
    """
    raise Error("optional runtime contract: " + message)


def _top(source: String, needle: String) raises -> String:
    """Return the top-level declaration that starts with `needle`.

    Args:
        source: The module source.
        needle: The declaration prefix, including its opening parenthesis.

    Returns:
        The declaration through the line before the next top-level line.

    Raises:
        Error: The declaration is missing or repeated.
    """
    var raw = source.as_bytes()
    var wanted = needle.as_bytes()
    var found = 0
    var start = 0
    var line = 0
    var index = 0
    while index < len(raw):
        if line == index:
            var same = index + len(wanted) <= len(raw)
            var cursor = 0
            while same and cursor < len(wanted):
                if raw[index + cursor] != wanted[cursor]:
                    same = False
                cursor += 1
            if same:
                found += 1
                start = index
        if raw[index] == 10:
            line = index + 1
        index += 1
    if found != 1:
        _fail("exact expansion memo lifetime is one search invocation")
    var end = len(raw)
    var cursor = start
    while cursor < len(raw) and raw[cursor] != 10:
        cursor += 1
    if cursor < len(raw):
        cursor += 1
    while cursor < len(raw):
        var mark = raw[cursor]
        if mark == 10 or mark == 41 or mark == 93 or mark == 125:
            cursor += 1
        elif mark == 32 or mark == 9:
            while cursor < len(raw) and raw[cursor] != 10:
                cursor += 1
            if cursor < len(raw):
                cursor += 1
        else:
            end = cursor
            break
    return String(source[byte=start:end])


def _rows(source: String) raises -> List[String]:
    """Return the direct statements of one declaration.

    Args:
        source: A function or struct.

    Returns:
        Each direct body statement.

    Raises:
        Error: The declaration has no body.
    """
    var kinds = List[Int]()
    var texts = List[String]()
    _tokenize(source, kinds, texts)
    var header = _suite(kinds, texts, 0, len(kinds))
    if header[0] < 0:
        _fail("exact expansion memo lifetime is one search invocation")
    var starts = List[Int]()
    var stops = List[Int]()
    var rows = List[String]()
    _spans(kinds, texts, header[0], header[1], starts, stops, rows)
    return rows^


def _one(rows: List[String], message: String) raises -> String:
    """Return the only statement.

    Args:
        rows: The normalized statements.
        message: The failure text.

    Returns:
        The statement.

    Raises:
        Error: The fragment is not one statement.
    """
    if len(rows) != 1:
        _fail(message)
    return rows[0]


def _compact(rows: List[String]) -> List[String]:
    """Drop empty statements.

    Args:
        rows: The statements.

    Returns:
        The statements that contain tokens.
    """
    var kept = List[String]()
    var index = 0
    while index < len(rows):
        if rows[index].byte_length() > 0:
            kept.append(rows[index])
        index += 1
    return kept^


def _match(rows: List[String], wanted: List[String]) -> Bool:
    """Return whether `wanted` occurs as adjacent statements.

    Args:
        rows: The suite statements.
        wanted: The required sequence.

    Returns:
        True when the sequence occurs once or more.
    """
    if len(wanted) == 0 or len(rows) < len(wanted):
        return False
    var index = 0
    while index + len(wanted) <= len(rows):
        var same = True
        var cursor = 0
        while same and cursor < len(wanted):
            if rows[index + cursor] != wanted[cursor]:
                same = False
            cursor += 1
        if same:
            return True
        index += 1
    return False


def _search(
    kinds: List[Int],
    texts: List[String],
    begin: Int,
    end: Int,
    wanted: List[String],
) -> Bool:
    """Return whether any suite contains `wanted`.

    Args:
        kinds: The token kinds.
        texts: The token texts.
        begin: The first token of the suite.
        end: The token that closes the suite.
        wanted: The required statements.

    Returns:
        True when a suite contains the sequence.
    """
    if begin < 0 or end < begin:
        return False
    var starts = List[Int]()
    var stops = List[Int]()
    var rows = List[String]()
    _spans(kinds, texts, begin, end, starts, stops, rows)
    if _match(_compact(rows), wanted):
        return True
    var index = 0
    while index < len(starts):
        var inner = _suite(kinds, texts, starts[index], stops[index])
        if _search(kinds, texts, inner[0], inner[1], wanted):
            return True
        index += 1
    return False


def _require(
    kinds: List[Int],
    texts: List[String],
    begin: Int,
    end: Int,
    text: String,
    message: String,
) raises:
    """Require one statement sequence.

    Args:
        kinds: The token kinds.
        texts: The token texts.
        begin: The first token of the function body.
        end: The token that closes the function body.
        text: The required statements.
        message: The failure text.

    Raises:
        Error: The sequence is missing.
    """
    if not _search(kinds, texts, begin, end, _compact(_snippet(text))):
        _fail(message)


def _lifetime(source: String) raises:
    """Require one invocation-local expansion context.

    Args:
        source: The `lane_refinement` module.

    Raises:
        Error: A cache field or its constructor changed.
    """
    var message = "exact expansion memo lifetime is one search invocation"
    var struct_rows = _rows(_top(source, "struct _LaneExpansionContext("))
    var fast = _one(
        _snippet("var cached_fast: Optional[Tuple[UInt64, UInt64, _Jet]]"),
        message,
    )
    var expansion = _one(
        _snippet("var cached_expansion: Optional[Tuple[UInt64, UInt64, _Jet]]"),
        message,
    )
    var fast_count = 0
    var expansion_count = 0
    var index = 0
    while index < len(struct_rows):
        if struct_rows[index] == fast:
            fast_count += 1
        if struct_rows[index] == expansion:
            expansion_count += 1
        index += 1
    if fast_count != 1 or expansion_count != 1:
        _fail(message)
    var owner = _rows(_extract(source, "_run_lane_search"))
    var built = _one(
        _snippet(
            "var expansion_context = _LaneExpansionContext(\n"
            "    section,\n"
            "    lane,\n"
            "    _Interval(low, high),\n"
            "    location,\n"
            "    spiral_proof,\n"
            "    frozen,\n"
            "    external_witness.copy(),\n"
            "    None,\n"
            "    None,\n"
            ")"
        ),
        message,
    )
    var built_count = 0
    index = 0
    while index < len(owner):
        if owner[index] == built:
            built_count += 1
        index += 1
    if built_count != 1:
        _fail(message)


def lane_center_edges(source: String) raises:
    """Require the reviewed live lane-center edges.

    Args:
        source: The `lane_refinement` module.

    Raises:
        Error: A memo, grouped caller, support call, or cache lifetime changed.
    """
    _lifetime(source)
    var kinds = List[Int]()
    var texts = List[String]()
    _tokenize(_extract(source, "_try_lane_center_bound"), kinds, texts)
    var header = _suite(kinds, texts, 0, len(kinds))
    if header[0] < 0:
        _fail("one guarded grouped caller edge")
    _require(
        kinds,
        texts,
        header[0],
        header[1],
        (
            "var station_word = bitcast[DType.uint64](center_s)\n"
            "var scale_word = bitcast[DType.uint64](policy.scale)\n"
            "if (\n"
            "    context.external_witness\n"
            "    and context.cached_fast\n"
            "    and _same_cache_key(\n"
            "        context.cached_fast.value()[0],\n"
            "        context.cached_fast.value()[1],\n"
            "        station_word,\n"
            "        scale_word,\n"
            "    )\n"
            "):\n"
            "    fast_center = context.cached_fast.value()[2]\n"
            "else:\n"
            "    fast_center = _try_proof_expansion_jet(\n"
            "        road,\n"
            "        context.section,\n"
            "        context.lane,\n"
            "        center_s,\n"
            "        context.location,\n"
            "        policy.scale,\n"
            "        context.root.low,\n"
            "        context.root.high,\n"
            "        context.spiral_proof,\n"
            "    )\n"
            "    if context.external_witness and fast_center:\n"
            "        context.cached_fast = (\n"
            "            station_word,\n"
            "            scale_word,\n"
            "            fast_center.value(),\n"
            "        )"
        ),
        "exact station/scale proof expansion memo and fresh fallback",
    )
    _require(
        kinds,
        texts,
        header[0],
        header[1],
        (
            "var station_word = bitcast[DType.uint64](center_s)\n"
            "var scale_word = bitcast[DType.uint64](policy.scale)\n"
            "if (\n"
            "    context.external_witness\n"
            "    and context.cached_expansion\n"
            "    and _same_cache_key(\n"
            "        context.cached_expansion.value()[0],\n"
            "        context.cached_expansion.value()[1],\n"
            "        station_word,\n"
            "        scale_word,\n"
            "    )\n"
            "):\n"
            "    center = context.cached_expansion.value()[2]\n"
            "else:\n"
            "    if context.frozen:\n"
            "        center = _frozen_arc_expansion(\n"
            "            context.frozen.value(),\n"
            "            center_s,\n"
            "            context.location,\n"
            "            policy.scale,\n"
            "        )\n"
            "    else:\n"
            "        center = _expansion_distance_jet(\n"
            "            road,\n"
            "            context.section,\n"
            "            context.lane,\n"
            "            center_s,\n"
            "            context.location,\n"
            "            policy.scale,\n"
            "        )\n"
            "    if context.external_witness:\n"
            "        context.cached_expansion = (\n"
            "            station_word,\n"
            "            scale_word,\n"
            "            center,\n"
            "        )"
        ),
        "exact station/scale translated expansion memo and fresh fallback",
    )
    _require(
        kinds,
        texts,
        header[0],
        header[1],
        (
            "terms += whole_work\n"
            "var grouped: Optional[Tuple[_Jet, _Jet, _Jet]] = None\n"
            "if max_nodes - nodes >= 2:\n"
            "    grouped = _try_grouped_lane_jet(\n"
            "        road,\n"
            "        context.section,\n"
            "        context.lane,\n"
            "        cell.low,\n"
            "        cell.high,\n"
            "        nodes,\n"
            "        terms,\n"
            "        max_nodes,\n"
            "        max_terms,\n"
            "    )\n"
            "var point_domain: Tuple[_Jet, _Jet, _Jet]\n"
            "if grouped:\n"
            "    point_domain = grouped.value()\n"
            "else:\n"
            "    point_domain = _lane_jet(\n"
            "        road, context.section, context.lane, cell.low, cell.high\n"
            "    )"
        ),
        "grouped caller must retain recheck and prepaid original fallback",
    )
    var whole = _normalize(kinds, texts, 0, len(kinds), False)
    var grouped = _one(
        _snippet(
            "_try_grouped_lane_jet(road, context.section, context.lane,"
            " cell.low, cell.high, nodes, terms, max_nodes, max_terms)"
        ),
        "one guarded grouped caller edge",
    )
    if _count(whole, grouped) != 1:
        _fail("one guarded grouped caller edge")
    var support = _one(
        _snippet(
            "_minimizer_support(domain, center, center_s, best, cell.low,"
            " cell.high)"
        ),
        "support receives same ideal and actual witness",
    )
    if _count(whole, support) != 1:
        _fail("support receives same ideal and actual witness")
