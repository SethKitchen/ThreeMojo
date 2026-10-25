# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Premise order for the three reviewed cleanup successors."""

from tests._python_tokens import (
    _DEDENT,
    _INDENT,
    _NAME,
    _NEWLINE,
    _OP,
    _tokenize,
)


def _slot(mut items: List[Int], depth: Int) -> Int:
    """Return the decorator token at `depth`, or -1.

    Args:
        items: Decorator token indexes, one slot per scope depth.
        depth: The scope depth.

    Returns:
        The token index, or -1 when that depth has no decorator.
    """
    if depth < 0 or depth >= len(items):
        return -1
    return items[depth]


def _put(mut items: List[Int], depth: Int, value: Int):
    """Store one decorator token index.

    Args:
        items: Decorator token indexes, one slot per scope depth.
        depth: The scope depth.
        value: The token index, or -1 to clear it.
    """
    while len(items) <= depth:
        items.append(-1)
    items[depth] = value


def _body_end(kinds: List[Int], newline: Int, name: String) raises -> Int:
    """Return the token just after the function body.

    Args:
        kinds: The token kinds.
        newline: The newline that closes the signature.
        name: The function name.

    Returns:
        The exclusive end token.

    Raises:
        Error: The body is missing or unclosed.
    """
    var body = newline + 1
    if body >= len(kinds) or kinds[body] != _INDENT:
        raise Error(
            "reviewed cleanup source contract: unsupported guard function"
            " body: "
            + name
        )
    var depth = 1
    var end = body + 1
    while end < len(kinds) and depth > 0:
        if kinds[end] == _INDENT:
            depth += 1
        elif kinds[end] == _DEDENT:
            depth -= 1
        end += 1
    if depth != 0:
        raise Error(
            "reviewed cleanup source contract: unclosed guard function body: "
            + name
        )
    return end


def _keep(kind: Int) -> Bool:
    """Return whether `kind` is a word token.

    Args:
        kind: The token kind.

    Returns:
        True for a name, number, string, or operator.
    """
    return kind != _NEWLINE and kind != _INDENT and kind != _DEDENT


def declaration_words(
    text: String, name: String, owner: String
) raises -> List[String]:
    """Return the words of one function, including its decorator.

    Args:
        text: The module source.
        name: The function name.
        owner: The enclosing struct name, or empty for a module function.

    Returns:
        The function words, in order.

    Raises:
        Error: The function is missing, repeated, or owned by another scope.
    """
    var kinds = List[Int]()
    var texts = List[String]()
    _tokenize(text, kinds, texts)
    var scope_kind = List[String]()
    var scope_name = List[String]()
    var statement = List[Int]()
    var decorators = List[Int]()
    var pending_kind = String()
    var pending_name = String()
    var have_pending = False
    var hits = 0
    var hit_start = 0
    var hit_newline = 0
    var hit_owner = String()
    for index in range(len(kinds)):
        var kind = kinds[index]
        if kind == _INDENT:
            if have_pending:
                scope_kind.append(pending_kind)
                scope_name.append(pending_name)
            else:
                scope_kind.append("block")
                scope_name.append("")
            have_pending = False
            _put(decorators, len(scope_kind), -1)
        elif kind == _DEDENT:
            if len(scope_kind) == 0:
                raise Error(
                    "reviewed cleanup source contract: unmatched source scope"
                )
            _put(decorators, len(scope_kind), -1)
            _ = scope_kind.pop()
            _ = scope_name.pop()
            have_pending = False
        elif kind == _NEWLINE:
            if len(statement) > 0:
                var depth = len(scope_kind)
                var first_kind = kinds[statement[0]]
                var first = texts[statement[0]]
                if first_kind == _OP and first == "@":
                    if _slot(decorators, depth) < 0:
                        _put(decorators, depth, statement[0])
                else:
                    var decorated = _slot(decorators, depth)
                    _put(decorators, depth, -1)
                    if (
                        len(statement) >= 2
                        and first_kind == _NAME
                        and first == "def"
                        and texts[statement[1]] == name
                    ):
                        hits += 1
                        hit_newline = index
                        if decorated >= 0:
                            hit_start = decorated
                        else:
                            hit_start = statement[0]
                        if len(scope_kind) == 0:
                            hit_owner = ""
                        elif len(scope_kind) == 1 and scope_kind[0] == "struct":
                            hit_owner = scope_name[0]
                        else:
                            hit_owner = "?"
                    var last = texts[statement[len(statement) - 1]]
                    if last == ":":
                        if (
                            first_kind == _NAME
                            and len(statement) >= 2
                            and (
                                first == "def"
                                or first == "struct"
                                or first == "trait"
                                or first == "class"
                            )
                        ):
                            pending_kind = first
                            pending_name = texts[statement[1]]
                        else:
                            pending_kind = "block"
                            pending_name = ""
                        have_pending = True
                    else:
                        have_pending = False
            statement.clear()
        else:
            statement.append(index)
    if hits != 1:
        raise Error(
            "reviewed cleanup source contract: missing or ambiguous actual"
            " guard declaration: "
            + name
        )
    if hit_owner != owner:
        raise Error(
            "reviewed cleanup source contract: guard caller owner/scope"
            " changed: "
            + name
        )
    var end = _body_end(kinds, hit_newline, name)
    var words = List[String]()
    for index in range(hit_start, end):
        if _keep(kinds[index]):
            words.append(texts[index])
    return words^


def _fragment_words(text: String) raises -> List[String]:
    """Return the words of one premise fragment.

    Args:
        text: The fragment.

    Returns:
        The fragment words.

    Raises:
        Error: The fragment cannot be tokenized.
    """
    var kinds = List[Int]()
    var texts = List[String]()
    _tokenize(text, kinds, texts)
    var words = List[String]()
    for index in range(len(kinds)):
        if _keep(kinds[index]):
            words.append(texts[index])
    return words^


def ordered_fragments(
    words: List[String], fragments: List[String], label: String
) raises:
    """Require each fragment once, in order.

    Args:
        words: The function words.
        fragments: The premise fragments.
        label: The premise name.

    Raises:
        Error: A fragment is missing, repeated, or out of order.
    """
    var previous = -1
    for slot in range(len(fragments)):
        var expected = _fragment_words(fragments[slot])
        var found = 0
        var at = -1
        var last = len(words) - len(expected)
        var start = 0
        while start <= last:
            var same = True
            var offset = 0
            while offset < len(expected):
                if words[start + offset] != expected[offset]:
                    same = False
                    break
                offset += 1
            if same:
                found += 1
                if found == 1:
                    at = start
            start += 1
        if found != 1 or at <= previous:
            raise Error("reviewed cleanup source contract: " + label)
        previous = at


def ordered_text(text: String, fragments: List[String], label: String) raises:
    """Require each fragment once in `text`, in order.

    Args:
        text: The source.
        fragments: The premise fragments.
        label: The premise name.

    Raises:
        Error: A fragment is missing, repeated, or out of order.
    """
    var words = _fragment_words(text)
    ordered_fragments(words, fragments, label)


def _line_premises() -> List[String]:
    """Return the rounded-line premise fragments.

    Returns:
        The fragments, in order.
    """
    var fragments = List[String]()
    fragments.append("road._check_lane(section, lane)")
    fragments.append("if len(road.info.geometries) != 1: return None")
    fragments.append("not _RoundedBox.bounds(low, high).known")
    fragments.append(
        "if info_index(road.info.geometries, low) != 0: return None"
    )
    fragments.append("or info_index(road.info.lane_offsets, high) != offset_at")
    fragments.append(
        "or info_index(road.info.elevations, high) != elevation_at"
    )
    fragments.append(
        "if width_at < 0 or info_index(widths, high) != width_at: return None"
    )
    return fragments^


def _arc_premises() -> List[String]:
    """Return the rounded-arc context premise fragments.

    Returns:
        The fragments, in order.
    """
    var fragments = List[String]()
    fragments.append("road._check_lane(section, lane)")
    fragments.append("if len(road.info.geometries) != 1: return None")
    fragments.append(
        "if not _RoundedBox.bounds(low, high).known or high > road.length:"
        " return None"
    )
    fragments.append(
        "if info_index(road.info.geometries, low) != 0: return None"
    )
    fragments.append(
        "if len(road.info.lane_offsets) != 1 or len(road.info.elevations) != 1:"
        " return None"
    )
    fragments.append("info_index(road.info.lane_offsets, low) != 0")
    fragments.append("or info_index(road.info.elevations, low) != 0")
    fragments.append("if len(widths) != 1: return None")
    fragments.append("if info_index(widths, low) != 0: return None")
    return fragments^


def _bounds_premises() -> List[String]:
    """Return the ordered-domain premise fragments.

    Returns:
        The fragments, in order.
    """
    var fragments = List[String]()
    fragments.append("_rounded_operand(low)")
    fragments.append("_rounded_operand(high)")
    fragments.append("and low <= high")
    return fragments^


def _center_premises() -> List[String]:
    """Return the selector-hull premise fragments.

    Returns:
        The fragments, in order.
    """
    var fragments = List[String]()
    fragments.append("if not half.known: return [unknown, unknown, unknown]")
    fragments.append(
        "var selector = _rounded_madd(half, _RoundedBox.point(_INV_HALF_PI),"
        " _RoundedBox.point(0.5))"
    )
    fragments.append(
        "if not selector.known or selector.low < 0.0 or selector.high >= 1.0:"
        " return [unknown, unknown, unknown]"
    )
    fragments.append("var square = half * half")
    return fragments^


def _outward_premises() -> List[String]:
    """Return the outward-float premise fragments.

    Returns:
        The fragments, in order.
    """
    var fragments = List[String]()
    fragments.append("var result = Float32(value)")
    fragments.append("var outside: Bool")
    fragments.append("if lower: outside = Float64(result) > value")
    fragments.append("else: outside = Float64(result) < value")
    fragments.append("if outside:")
    fragments.append("UInt32(0x80000001) if lower else UInt32(1)")
    fragments.append("if (result > 0.0) == lower: bits -= 1 else: bits += 1")
    fragments.append("result = bitcast[DType.float32](bits)")
    return fragments^


def require_cleanup_premises(
    line: String, arc: String, junction: String
) raises:
    """Require the three cleanup successors to keep their premise order.

    Args:
        line: The rounded-line successor.
        arc: The rounded-arc successor.
        junction: The junction successor.

    Raises:
        Error: A declaration or a premise fragment changed.
    """
    var line_words = declaration_words(line, "_rounded_line_axis_context", "")
    var line_premises = _line_premises()
    ordered_fragments(
        line_words,
        line_premises,
        "LINE singleton/domain/low lookup and multi-record profile premises",
    )
    var arc_words = declaration_words(arc, "_rounded_arc_context", "")
    var arc_premises = _arc_premises()
    ordered_fragments(
        arc_words, arc_premises, "ARC singleton/domain/low lookup premises"
    )
    var bounds = declaration_words(arc, "bounds", "_RoundedBox")
    var bounds_premises = _bounds_premises()
    ordered_fragments(bounds, bounds_premises, "ordered finite domain premise")
    var center = declaration_words(arc, "center", "_RoundedArc")
    var center_premises = _center_premises()
    ordered_fragments(
        center,
        center_premises,
        "quarter implication requires the same accepted selector hull",
    )
    var outward = declaration_words(junction, "_outward_float", "")
    var outward_premises = _outward_premises()
    ordered_fragments(
        outward,
        outward_premises,
        "outward conversion direction and adjacent-word premises",
    )
