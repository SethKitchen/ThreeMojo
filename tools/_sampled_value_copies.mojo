# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Check the sampled value copies of the jet helpers.

Nine helpers match their renamed jet sources. The blend copy also drops
the two derivative intersections. The constant heading copy replaces zero
derivatives with an unknown interval. The sampled reference keeps the
guard and the sampled tail. The lane bound drops the proof refusal and
keeps the sampled call.
"""

from tests._python_tokens import _tokenize
from tools._sampled_value_gate import sampled_identifier


comptime _NAME = 1
comptime _NEWLINE = 4
comptime _INDENT = 5
comptime _DEDENT = 6
comptime _OP = 55


def _fail(message: String) raises:
    """Raise a sampled-copy error.

    Args:
        message: The failure text.

    Raises:
        Error: The copy check failed.
    """
    raise Error("sampled value copy: " + message)


def _bad() raises:
    """Raise a syntax error for a sampled module.

    Raises:
        Error: The source cannot be tokenized.
    """
    _fail("unsupported ideal source syntax")


def _load(source: String, mut kinds: List[Int], mut texts: List[String]) raises:
    """Tokenize `source`.

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


def _opens(text: String) -> Bool:
    """Return whether `text` opens a bracket.

    Args:
        text: The token text.

    Returns:
        True for `(`, `[`, or `{`.
    """
    if text == "(":
        return True
    if text == "[":
        return True
    return text == "{"


def _closes(text: String) -> Bool:
    """Return whether `text` closes a bracket.

    Args:
        text: The token text.

    Returns:
        True for `)`, `]`, or `}`.
    """
    if text == ")":
        return True
    if text == "]":
        return True
    return text == "}"


def _rename(text: String) -> String:
    """Return the sampled name for a jet name.

    Args:
        text: One identifier.

    Returns:
        The value-graph name, or `text` when it is not renamed.
    """
    return sampled_identifier(text)


def _dropped(kind: Int, text: String) -> Bool:
    """Return whether normalization drops the token.

    Args:
        kind: The token kind.
        text: The token text.

    Returns:
        True for layout tokens and Mojo keywords Python strips.
    """
    if kind == _NEWLINE or kind == _INDENT or kind == _DEDENT:
        return True
    if kind != _NAME:
        return False
    if text == "var":
        return True
    if text == "mut":
        return True
    if text == "out":
        return True
    if text == "ref":
        return True
    if text == "comptime":
        return True
    return text == "raises"


def _normalize(
    kinds: List[Int],
    texts: List[String],
    start: Int,
    end: Int,
    rename: Bool,
) -> String:
    """Return the comparable text of one token span.

    Args:
        kinds: The token kinds.
        texts: The token texts.
        start: The first token.
        end: The token after the span.
        rename: True when jet names become value names.

    Returns:
        The tokens, separated by spaces, without layout or trailing commas.
    """
    var kept = List[String]()
    var index = start
    while index < end:
        if not _dropped(kinds[index], texts[index]):
            var text = texts[index]
            if rename and kinds[index] == _NAME:
                text = _rename(text)
            kept.append(text)
        index += 1
    var out = String("")
    var saw = False
    index = 0
    while index < len(kept):
        var skip = False
        if kept[index] == "," and index + 1 < len(kept):
            var nxt = kept[index + 1]
            if nxt == ")" or nxt == "]":
                skip = True
        if not skip:
            if saw:
                out += " "
            out += kept[index]
            saw = True
        index += 1
    return out


def _span(
    kinds: List[Int], texts: List[String], name: String
) raises -> Tuple[Int, Int]:
    """Return the token span of top-level `name`, including `def`.

    Args:
        kinds: The token kinds.
        texts: The token texts.
        name: The function name.

    Returns:
        The `def` token and the token after the body.

    Raises:
        Error: The function is missing, repeated, or has no body.
    """
    var depth = 0
    var fresh = True
    var found = 0
    var at = -1
    var index = 0
    while index < len(kinds):
        var kind = kinds[index]
        if kind == _INDENT:
            depth += 1
            fresh = True
        elif kind == _DEDENT:
            depth -= 1
            fresh = True
        elif kind == _NEWLINE:
            if depth == 0:
                fresh = True
        else:
            if depth == 0 and fresh and texts[index] == "def":
                if index + 1 < len(kinds) and texts[index + 1] == name:
                    found += 1
                    at = index
            fresh = False
        index += 1
    if found != 1:
        _fail("missing or ambiguous function: " + name)
    var cursor = at + 2
    if cursor < len(kinds) and _opens(texts[cursor]):
        var brackets = 1
        cursor += 1
        while cursor < len(kinds) and brackets > 0:
            if _opens(texts[cursor]):
                brackets += 1
            elif _closes(texts[cursor]):
                brackets -= 1
            cursor += 1
    var signature = 0
    var colon = -1
    while cursor < len(kinds):
        if _opens(texts[cursor]):
            signature += 1
        elif _closes(texts[cursor]):
            signature -= 1
        elif kinds[cursor] == _OP and texts[cursor] == ":" and signature == 0:
            colon = cursor
            break
        cursor += 1
    if colon < 0:
        _fail("unsupported ideal source syntax")
    cursor = colon + 1
    while cursor < len(kinds) and kinds[cursor] == _NEWLINE:
        cursor += 1
    if cursor >= len(kinds) or kinds[cursor] != _INDENT:
        _fail("unsupported ideal source syntax")
    var indent = 1
    cursor += 1
    var stop = len(kinds)
    while cursor < len(kinds):
        if kinds[cursor] == _INDENT:
            indent += 1
        elif kinds[cursor] == _DEDENT:
            indent -= 1
            if indent == 0:
                stop = cursor
                break
        cursor += 1
    return (at, stop)


def _body_statements(
    kinds: List[Int], texts: List[String], name: String, rename: Bool
) raises -> List[String]:
    """Return the normalized top-level statements of `name`.

    Args:
        kinds: The token kinds.
        texts: The token texts.
        name: The function name.
        rename: True when jet names become value names.

    Returns:
        Each direct body statement, without layout tokens.

    Raises:
        Error: The function is missing or has no body.
    """
    var span = _span(kinds, texts, name)
    var cursor = span[0] + 2
    if cursor < len(kinds) and _opens(texts[cursor]):
        var brackets = 1
        cursor += 1
        while cursor < len(kinds) and brackets > 0:
            if _opens(texts[cursor]):
                brackets += 1
            elif _closes(texts[cursor]):
                brackets -= 1
            cursor += 1
    var signature = 0
    while cursor < len(kinds):
        if _opens(texts[cursor]):
            signature += 1
        elif _closes(texts[cursor]):
            signature -= 1
        elif kinds[cursor] == _OP and texts[cursor] == ":" and signature == 0:
            break
        cursor += 1
    cursor += 1
    while cursor < len(kinds) and kinds[cursor] == _NEWLINE:
        cursor += 1
    if cursor < len(kinds) and kinds[cursor] == _INDENT:
        cursor += 1
    var depth = 1
    var bracket = 0
    var row_kinds = List[Int]()
    var row_texts = List[String]()
    var rows = List[String]()
    var index = cursor
    while index < span[1]:
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
        row_kinds.append(kind)
        row_texts.append(text)
        var done = False
        if kind == _DEDENT and depth == 1:
            done = True
        if kind == _NEWLINE and depth == 1 and bracket == 0:
            var nxt = index + 1
            if nxt >= span[1] or kinds[nxt] != _INDENT:
                done = True
        if done:
            rows.append(
                _normalize(row_kinds, row_texts, 0, len(row_kinds), rename)
            )
            row_kinds = List[Int]()
            row_texts = List[String]()
        index += 1
    if len(row_texts) > 0:
        rows.append(_normalize(row_kinds, row_texts, 0, len(row_texts), rename))
    return rows^


def _once(text: String, needle: String, message: String) raises -> String:
    """Remove the one occurrence of `needle`.

    Args:
        text: The normalized helper.
        needle: The text to remove.
        message: The failure text when the count is not one.

    Returns:
        The text without that occurrence.

    Raises:
        Error: The text is missing or repeated.
    """
    var at = text.find(needle)
    if at < 0:
        _fail(message)
    var tail = text[byte = at + needle.byte_length() :]
    if tail.find(needle) >= 0:
        _fail(message)
    var head = text[byte=0:at]
    return String(head) + String(tail)


def _compare(
    origin_kinds: List[Int],
    origin_texts: List[String],
    value_kinds: List[Int],
    value_texts: List[String],
    jet: String,
    blend: Bool,
) raises:
    """Require the value helper to match the renamed jet helper.

    Args:
        origin_kinds: The jet module token kinds.
        origin_texts: The jet module token texts.
        value_kinds: The value module token kinds.
        value_texts: The value module token texts.
        jet: The jet function name.
        blend: True when the two derivative intersections are removed.

    Raises:
        Error: The helper is missing or the copy diverged.
    """
    var origin = _span(origin_kinds, origin_texts, jet)
    var copied = _normalize(
        origin_kinds, origin_texts, origin[0], origin[1], True
    )
    if blend:
        copied = _once(
            copied,
            (
                " result . first = _intersect_ideal_bounds ( result . first ,"
                " ideal . first )"
            ),
            "derivative intersection shape changed",
        )
        copied = _once(
            copied,
            (
                " result . second = _intersect_ideal_bounds ( result . second ,"
                " ideal . second )"
            ),
            "derivative intersection shape changed",
        )
    var value_name = _rename(jet)
    var live = _span(value_kinds, value_texts, value_name)
    var actual = _normalize(value_kinds, value_texts, live[0], live[1], False)
    if copied != actual:
        _fail("sampled helper diverged: " + value_name)


def sampled_value_copies(bounds: String, trig: String, value: String) raises:
    """Require the ten sampled helpers to match their jet sources.

    Args:
        bounds: The `curve_bounds` module.
        trig: The `curve_trig` module.
        value: The `lane_value_bounds` module.

    Raises:
        Error: A helper is missing, the blend intersections changed, or a
        copy diverged.
    """
    var bound_kinds = List[Int]()
    var bound_texts = List[String]()
    var trig_kinds = List[Int]()
    var trig_texts = List[String]()
    var value_kinds = List[Int]()
    var value_texts = List[String]()
    _load(bounds, bound_kinds, bound_texts)
    _load(trig, trig_kinds, trig_texts)
    _load(value, value_kinds, value_texts)
    _compare(
        trig_kinds, trig_texts, value_kinds, value_texts, "_atan_branch", False
    )
    _compare(
        trig_kinds, trig_texts, value_kinds, value_texts, "_atan_jet", False
    )
    _compare(
        trig_kinds, trig_texts, value_kinds, value_texts, "_atan2_jet", False
    )
    _compare(
        trig_kinds, trig_texts, value_kinds, value_texts, "_sinc_jet", False
    )
    _compare(
        bound_kinds,
        bound_texts,
        value_kinds,
        value_texts,
        "_polynomial_jet",
        False,
    )
    _compare(
        bound_kinds,
        bound_texts,
        value_kinds,
        value_texts,
        "_unknown_point",
        False,
    )
    _compare(
        bound_kinds,
        bound_texts,
        value_kinds,
        value_texts,
        "_geometry_distance",
        False,
    )
    _compare(
        bound_kinds, bound_texts, value_kinds, value_texts, "_sample_jet", False
    )
    _compare(
        bound_kinds,
        bound_texts,
        value_kinds,
        value_texts,
        "_arc_offset_jet",
        False,
    )
    _compare(
        bound_kinds,
        bound_texts,
        value_kinds,
        value_texts,
        "_sample_blend_jet",
        True,
    )


def sampled_constant_heading(trig: String, value: String) raises:
    """Require the constant heading projection.

    The jet helper keeps its layout and its zero derivative slots. The
    value helper replaces that zero with an unknown interval.

    Args:
        trig: The `curve_trig` module.
        value: The `lane_value_bounds` module.

    Raises:
        Error: The layout, the zero constructor, the field projection, or
        the value helper changed.
    """
    var trig_kinds = List[Int]()
    var trig_texts = List[String]()
    var value_kinds = List[Int]()
    var value_texts = List[String]()
    _load(trig, trig_kinds, trig_texts)
    _load(value, value_kinds, value_texts)
    var origin = _span(trig_kinds, trig_texts, "_constant_sincos_jet")
    var copied = _normalize(trig_kinds, trig_texts, origin[0], origin[1], True)
    var guard = "if not isfinite ( heading ) or abs ( heading ) > _PHASE_LIMIT"
    if copied.find(guard) < 0:
        _fail("constant heading layout changed")
    var guard_tail = copied[byte = copied.find(guard) + guard.byte_length() :]
    if guard_tail.find(guard) >= 0:
        _fail("constant heading layout changed")
    var zero = "zero = _Interval . point ( 0.0 )"
    if copied.find(zero) < 0:
        _fail("constant heading derivative constructor changed")
    var zero_tail = copied[byte = copied.find(zero) + zero.byte_length() :]
    if zero_tail.find(zero) >= 0:
        _fail("constant heading derivative constructor changed")
    copied = copied.replace(zero, "unknown = _Interval . whole ( )")
    var slots = ", zero , zero ,"
    if copied.find(slots) < 0:
        _fail("constant heading field projection changed")
    var first = copied.find(slots)
    var after = copied[byte = first + slots.byte_length() :]
    if after.find(slots) < 0:
        _fail("constant heading field projection changed")
    var second = after.find(slots)
    var rest = after[byte = second + slots.byte_length() :]
    if rest.find(slots) >= 0:
        _fail("constant heading field projection changed")
    copied = copied.replace(slots, ", unknown , unknown ,")
    var live = _span(value_kinds, value_texts, "_constant_sincos_value")
    var actual = _normalize(value_kinds, value_texts, live[0], live[1], False)
    if copied != actual:
        _fail("sampled helper diverged: _constant_sincos_value")


def _prefix(text: String, prefix: String) -> Bool:
    """Return whether `text` starts with `prefix`.

    Args:
        text: The statement.
        prefix: The required start.

    Returns:
        True when `prefix` is the start of `text`.
    """
    if text.byte_length() < prefix.byte_length():
        return False
    return text[byte = 0 : prefix.byte_length()] == prefix


def sampled_reference_projection(bounds: String, value: String) raises:
    """Require the union body and the sampled reference tail.

    Args:
        bounds: The `curve_bounds` module.
        value: The `lane_value_bounds` module.

    Raises:
        Error: The dispatcher layout changed, the union body changed, or a
        sampled helper diverged.
    """
    var bound_kinds = List[Int]()
    var bound_texts = List[String]()
    var value_kinds = List[Int]()
    var value_texts = List[String]()
    _load(bounds, bound_kinds, bound_texts)
    _load(value, value_kinds, value_texts)
    var union_jet = _body_statements(
        bound_kinds, bound_texts, "_union_points", True
    )
    var union_ok = len(union_jet) == 1
    if union_ok:
        union_ok = _prefix(union_jet[0], "return")
    if not union_ok:
        _fail("union complete body shape changed")
    var union_value = _body_statements(
        value_kinds, value_texts, "_union_value_points", False
    )
    var union_same = len(union_value) == 1
    if union_same:
        union_same = union_value[0] == union_jet[0]
    if not union_same:
        _fail("sampled helper diverged: _union_value_points")
    var jet = _body_statements(
        bound_kinds, bound_texts, "_reference_jet_capture", True
    )
    var heads = List[String]()
    heads.append("d =")
    heads.append("if geometry . kind == LINE")
    heads.append("if geometry . kind == ARC")
    heads.append("if geometry . kind == SPIRAL")
    heads.append("if len ( geometry . samples ) < 2")
    heads.append("domain =")
    heads.append("low =")
    heads.append("high =")
    heads.append("if high - low > 1")
    heads.append("first =")
    heads.append("if low == high")
    heads.append("return")
    var layout = len(jet) == len(heads)
    var index = 0
    while layout and index < len(heads):
        if not _prefix(jet[index], heads[index]):
            layout = False
        index += 1
    if not layout:
        _fail("complete reference dispatcher layout changed")
    var sampled = _body_statements(
        value_kinds, value_texts, "_reference_sampled_value", False
    )
    var guard = (
        "if geometry . kind != POLY3 and geometry . kind != PARAM_POLY3 :"
        " return _unknown_value_point ( )"
    )
    var same = len(sampled) == 10
    if same:
        same = sampled[0] == guard
    if same:
        same = sampled[1] == jet[0]
    index = 2
    while same and index < 10:
        if sampled[index] != jet[index + 2]:
            same = False
        index += 1
    if not same:
        _fail("sampled helper diverged: _reference_sampled_value")


def _decorated(kinds: List[Int], texts: List[String], at: Int) -> Bool:
    """Return whether a decorator precedes the `def` at `at`.

    Args:
        kinds: The token kinds.
        texts: The token texts.
        at: The `def` token.

    Returns:
        True when an `@` decorator is attached to that function.
    """
    var index = at - 1
    while index >= 0:
        if kinds[index] == _DEDENT:
            return False
        if texts[index] == "@":
            return True
        index -= 1
    return False


def _lane_heads() -> List[String]:
    """Return the lane dispatcher statement prefixes.

    Returns:
        The prefixes after the cached-proof refusal, in order.
    """
    var heads = List[String]()
    heads.append("geometry_at =")
    heads.append("elevation_at =")
    heads.append("offset_at =")
    heads.append("if geometry_at < 0 or elevation_at < 0 or offset_at < 0")
    heads.append("if (")
    heads.append("s =")
    heads.append("offset =")
    heads.append("lanes =")
    heads.append("lane_id =")
    heads.append("negative =")
    heads.append("sign =")
    heads.append("if lane_id . value != 0")
    heads.append("offset =")
    heads.append("record =")
    heads.append("if capture")
    heads.append("if record . geometry . kind == ARC")
    heads.append("if record . geometry . kind == LINE")
    heads.append("reused :")
    heads.append("if not capture")
    heads.append("point :")
    heads.append("if reused")
    heads.append("elif require_reuse")
    heads.append("else :")
    heads.append("trig =")
    heads.append("return")
    return heads^


def sampled_lane_projection(bounds: String, value: String) raises:
    """Require the lane bound projection from the jet proof.

    The cached-proof refusal is removed. Arc and line move under the
    geometry flag. The proof dispatch becomes one sampled call.

    Args:
        bounds: The `curve_bounds` module.
        value: The `lane_value_bounds` module.

    Raises:
        Error: The refusal moved, the dispatcher changed, the capture
        bookkeeping changed, or the value helper diverged.
    """
    var bound_kinds = List[Int]()
    var bound_texts = List[String]()
    var value_kinds = List[Int]()
    var value_texts = List[String]()
    _load(bounds, bound_kinds, bound_texts)
    _load(value, value_kinds, value_texts)
    var jet = _body_statements(
        bound_kinds, bound_texts, "_lane_jet_model_proof", True
    )
    var refusal = (
        "if proof and not _sum2_supported_environment ( ) : return "
        "_unknown_value_point ( )"
    )
    if jet[0] != refusal:
        _fail("cached-proof environment refusal changed or moved")
    var heads = _lane_heads()
    var layout = len(jet) == len(heads) + 1
    var index = 0
    while layout and index < len(heads):
        if not _prefix(jet[index + 1], heads[index]):
            layout = False
        index += 1
    if not layout:
        _fail("complete lane dispatcher layout changed")
    var capture = (
        "if capture : captured . record_at = geometry_at captured . low = "
        "low captured . high = high"
    )
    if jet[15] != capture:
        _fail("capture bookkeeping projection changed")
    var live = _body_statements(
        value_kinds, value_texts, "_lane_value_bound_impl", False
    )
    var span = _span(value_kinds, value_texts, "_lane_value_bound_impl")
    var signature = (
        "def _lane_value_bound_impl [ all_geometry : Bool ] ( road : Road "
        ", section : Int , lane : Int , low : Float64 , high : Float64 ) "
        "-> Tuple [ _ValueJet , _ValueJet , _ValueJet ] :"
    )
    var whole = _normalize(value_kinds, value_texts, span[0], span[1], False)
    var point = (
        "point = _reference_sampled_value ( record . geometry , "
        "_stored_difference ( s , _ValueJet . constant ( record . s ) ) , "
        "translation )"
    )
    var translation = "translation = Vector3 ( 0 , 0 , 0 )"
    var same = not _decorated(value_kinds, value_texts, span[0])
    if same:
        same = _prefix(whole, signature)
    if same:
        same = len(live) == 19
    if same:
        same = live[0] == translation
    index = 1
    while same and index <= 14:
        if live[index] != jet[index]:
            same = False
        index += 1
    if same:
        var wrapped = "if all_geometry : " + jet[16] + " " + jet[17]
        same = live[15] == wrapped
    if same:
        same = live[16] == point
    if same:
        same = live[17] == jet[24]
    if same:
        same = live[18] == jet[25]
    if not same:
        _fail("sampled helper diverged: _lane_value_bound_impl")
