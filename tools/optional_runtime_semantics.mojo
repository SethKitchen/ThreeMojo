# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Check the optional runtime source edges.

Fresh helpers keep the environment guard. The grouped debit, the dispatch
reserve, and the model rooms stay in the reviewed order.
"""

from tests._python_tokens import _tokenize
from tools.sampled_value_copies import _body_statements, _normalize, _span


def _fail(message: String) raises:
    """Raise an optional-runtime error.

    Args:
        message: The failure text.

    Raises:
        Error: An optional runtime edge changed.
    """
    raise Error("optional runtime contract: " + message)


def _extract(source: String, name: String) raises -> String:
    """Return the top-level function `name`.

    Args:
        source: The module source.
        name: The function name.

    Returns:
        The function text through the line before the next top-level line.

    Raises:
        Error: The function is missing or repeated.
    """
    var needle = String("def " + name + "(")
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
        _fail("missing or ambiguous function: " + name)
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


def _rows(source: String, name: String) raises -> List[String]:
    """Return the normalized statements of `name`.

    Args:
        source: The module source.
        name: The function name.

    Returns:
        Each direct body statement.

    Raises:
        Error: The function is missing or has no body.
    """
    var kinds = List[Int]()
    var texts = List[String]()
    _tokenize(_extract(source, name), kinds, texts)
    return _body_statements(kinds, texts, name, False)


def _function(source: String, name: String) raises -> String:
    """Return the normalized text of `name`.

    Args:
        source: The module source.
        name: The function name.

    Returns:
        The function from `def` through the body.

    Raises:
        Error: The function is missing or has no body.
    """
    var kinds = List[Int]()
    var texts = List[String]()
    _tokenize(_extract(source, name), kinds, texts)
    var span = _span(kinds, texts, name)
    return _normalize(kinds, texts, span[0], span[1], False)


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


def _snippet(text: String) raises -> String:
    """Return the normalized text of a statement fragment.

    Args:
        text: One or more statements.

    Returns:
        The normalized statements.

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
            var next = String(rest[byte = nl + 1 :])
            rest = next
        else:
            reading = False
        if line.byte_length() > 0:
            source += "    "
            source += line
            source += "\n"
    return _join(_rows(source, "_snippet"))


def _once(body: String, text: String, message: String) raises:
    """Require `text` once inside `body`.

    Args:
        body: The normalized function body.
        text: The required fragment.
        message: The failure text.

    Raises:
        Error: The fragment is missing or repeated.
    """
    if _count(body, _snippet(text)) != 1:
        _fail(message)


def _guard(rows: List[String], name: String) raises:
    """Require the fresh environment guard at the start of `name`.

    Args:
        rows: The normalized body statements.
        name: The function name.

    Raises:
        Error: The guard is missing or moved.
    """
    var guard = "if not _sum2_supported_environment ( ) : return None"
    if len(rows) == 0 or rows[0] != guard:
        _fail("fresh invocation guard missing or moved: " + name)


def _run(rows: List[String], wanted: List[String]) -> Int:
    """Return how many times `wanted` occurs as adjacent statements.

    Args:
        rows: The function statements.
        wanted: The required sequence.

    Returns:
        The number of matches.
    """
    if len(wanted) == 0 or len(rows) < len(wanted):
        return 0
    var matches = 0
    var index = 0
    while index + len(wanted) <= len(rows):
        var same = True
        var cursor = 0
        while same and cursor < len(wanted):
            if rows[index + cursor] != wanted[cursor]:
                same = False
            cursor += 1
        if same:
            matches += 1
        index += 1
    return matches


def optional_runtime_semantics(
    refinement: String,
    model: String,
    dispatch: String,
    lane: String,
    roundoff: String,
    support: String,
    map_source: String,
) raises:
    """Require the reviewed optional runtime edges.

    Args:
        refinement: The `lane_refinement` module.
        model: The `curve_objective_model` module.
        dispatch: The `curve_sample_dispatch` module.
        lane: The `spiral_grouped_lane` module.
        roundoff: The `spiral_grouped_roundoff_proof` module.
        support: The `curve_minimizer_support` module.
        map_source: The `map` module.

    Raises:
        Error: A guard, edge, room, or fee changed.
    """
    var key = _rows(refinement, "_same_cache_key")
    if len(key) != 1 or key[0] != _snippet(
        "return SIMD[DType.uint64, 2](station, scale) == SIMD[DType.uint64,"
        " 2](other_station, other_scale)"
    ):
        _fail("exact UInt64 pair helper comparison")
    var model_rows = _rows(model, "_try_objective_model")
    var restrict_rows = _rows(model, "_restrict_objective_model")
    var cut_rows = _rows(dispatch, "_sample_dispatch_cut")
    var cuts = _rows(dispatch, "_try_sample_dispatch_cuts")
    var lane_rows = _rows(lane, "_try_grouped_lane_jet")
    var raw_rows = _rows(roundoff, "_try_spiral_grouped_roundoff_envelope")
    var metered_rows = _rows(
        roundoff, "_try_spiral_grouped_roundoff_envelope_metered"
    )
    _guard(model_rows, "_try_objective_model")
    _guard(restrict_rows, "_restrict_objective_model")
    _guard(cut_rows, "_sample_dispatch_cut")
    _guard(cuts, "_try_sample_dispatch_cuts")
    _guard(lane_rows, "_try_grouped_lane_jet")
    _guard(raw_rows, "_try_spiral_grouped_roundoff_envelope")
    _guard(metered_rows, "_try_spiral_grouped_roundoff_envelope_metered")
    var origin = _join(_rows(roundoff, "_grouped_origin_error"))
    _once(
        origin,
        (
            "var error = _sum2_error_checked(magnitude.high, inherited.high,"
            " count)"
        ),
        "grouped origin must use the canonical checked error arguments",
    )
    var raw = _join(raw_rows)
    _once(
        raw,
        (
            "var x_error = _grouped_origin_error(x_ideal, x_magnitude,"
            " x_inherited, 5 * pieces, geometry.x)"
        ),
        "complete X stored-term count and origin",
    )
    _once(
        raw,
        (
            "var y_error = _grouped_origin_error(y_ideal, y_magnitude,"
            " y_inherited, 5 * pieces, geometry.y)"
        ),
        "complete Y stored-term count and origin",
    )
    _once(
        raw,
        (
            "var distance = _ValueJet(d.value, _Interval.whole(),"
            " _Interval.whole(), d.error)"
        ),
        "retain original ideal distance and uniform scalar error",
    )
    _once(
        raw,
        "var copies = (high - low) * multiplicity",
        "actual group multiplicity",
    )
    _once(
        raw,
        "var multiplicity = 1 if weight == 2 else 2",
        "stored symmetric weight multiplicity",
    )
    _once(
        _join(_rows(roundoff, "_spiral_grouped_roundoff_work")),
        "return 3 * min(4, pieces)",
        "whole count work bound",
    )
    var lane_body = _join(lane_rows)
    _once(
        lane_body,
        (
            "if (\n    nodes < 0\n    or nodes >= max_nodes\n    or terms < 0\n"
            "    or terms > max_terms\n    or max_terms - terms < 24\n):\n"
            "    return None"
        ),
        "whole optional union admission",
    )
    _once(
        lane_body,
        (
            "if (\n    counts[0] < 1\n    or counts[1] > 64\n    or counts[1] <"
            " counts[0]\n    or counts[1] - counts[0] > 1\n):\n    return None"
        ),
        "complete at-most-two count domain",
    )
    _once(
        lane_body,
        "var extra = _spiral_grouped_roundoff_work(counts[0])",
        "first count debit",
    )
    _once(
        lane_body,
        (
            "if counts[1] != counts[0]:\n    extra +="
            " _spiral_grouped_roundoff_work(counts[1])"
        ),
        "second count debit",
    )
    _once(
        lane_body,
        (
            "_lane_jet_model_proof[False](road, section, lane, low, high,"
            " Vector3(0, 0, 0), proof, low, high, captured, require_reuse=True)"
        ),
        "try-only reconstruction cannot invoke hidden GL",
    )
    var debit = -1
    var calls = 0
    var index = 0
    while index < len(lane_rows):
        if lane_rows[index] == "terms += extra":
            debit = index
        if (
            lane_rows[index].find("_try_spiral_grouped_roundoff_envelope (")
            >= 0
        ):
            if debit < 0 or index <= debit:
                calls = -1
            else:
                calls += 1
        index += 1
    if debit < 0 or calls != 2:
        _fail("atomic whole-count debit must precede both raw envelopes")
    var metered = _join(metered_rows)
    _once(
        metered,
        "if work + fallback_work > max_terms - terms:\n    return None",
        "standalone adapter preserves independent fallback reservation",
    )
    var model_body = _join(model_rows)
    _once(model_body, "low >= high", "model ordered owner")
    _once(model_body, "center_s < low", "model center inside owner low")
    _once(model_body, "center_s > high", "model center inside owner high")
    _once(
        model_body,
        "not _model_interval(domain.value)",
        "model finite whole-owner value",
    )
    _once(
        model_body,
        "not _model_interval(domain.first)",
        "model finite whole-owner first",
    )
    _once(
        model_body,
        "not _model_interval(domain.second)",
        "model finite whole-owner second",
    )
    _once(
        model_body, "not isfinite(domain.error)", "model uniform error finite"
    )
    _once(model_body, "domain.error < 0.0", "model uniform error nonnegative")
    var restrict = _join(restrict_rows)
    _once(restrict, "low < model.low", "restriction cannot widen owner low")
    _once(restrict, "high > model.high", "restriction cannot widen owner high")
    _once(
        restrict,
        "bitcast[DType.uint64](scale) != model.scale_word",
        "exact normalization scale word",
    )
    _once(
        restrict,
        "return _Jet(value, first, model.domain.second, model.domain.error)",
        "restriction retains whole-owner curvature and error",
    )
    _once(
        restrict,
        (
            "var value = (\n    model.center.value\n    + model.center.first"
            " * delta\n    + _Interval.point(0.5) * model.domain.second *"
            " delta.square()\n)"
        ),
        "same-ideal Taylor value restriction",
    )
    var support_body = _join(_rows(support, "_minimizer_support"))
    _once(support_body, "best < low", "actual witness lower containment")
    _once(support_body, "best > high", "actual witness upper containment")
    _once(support_body, "not isfinite(best)", "actual witness finite station")
    _once(
        support_body,
        (
            "var twice_error = _Interval.point(2.0) *"
            " _Interval.point(domain.error)"
        ),
        "support uses uniform whole-domain error",
    )
    _once(
        support_body,
        "var four_error = _Interval.point(4.0) * _Interval.point(domain.error)",
        "convex support uses uniform whole-domain error",
    )
    if support_body.find("center . error") >= 0:
        _fail("translated center error cannot replace world error")
    var predicate = _rows(dispatch, "_sample_dispatch_predicate")
    if len(predicate) != 1 or predicate[0] != _snippet(
        "return min(max(station - origin, 0.0), length) > local"
    ):
        _fail("exact stored subtraction/clamp dispatch predicate")
    var cut_body = _join(cuts)
    _once(
        cut_body,
        (
            "var before_index = _sample_index(geometry, min(max(before -"
            " record.s, 0.0), geometry.length))"
        ),
        "actual predecessor sample index",
    )
    _once(
        cut_body,
        (
            "var after_index = _sample_index(geometry, min(max(station -"
            " record.s, 0.0), geometry.length))"
        ),
        "actual cut sample index",
    )
    _once(
        cut_body,
        (
            "if before_index != threshold_at - 1 or after_index !="
            " threshold_at:\n    return None"
        ),
        "both actual indices must match original owners",
    )
    _once(
        cut_body,
        "var node_reserve = 3 * count + 2",
        "dispatch node reserve includes descendants and rechecks",
    )
    _once(
        cut_body,
        "var term_reserve = 16 * count",
        "dispatch probe and descendant term reserve",
    )
    _once(
        cut_body,
        (
            "if (\n    max_nodes < node_reserve\n    or max_terms < 0\n    or"
            " nodes < 0\n    or nodes > max_nodes - node_reserve\n    or terms"
            " < 0\n    or terms > max_terms\n    or term_reserve > max_terms -"
            " terms\n):\n    return None"
        ),
        "complete dispatch followup reserve before optional work",
    )
    _once(cut_body, "var extra = 8 * count", "complete optional dispatch debit")
    _once(
        cut_body,
        "if count < 1 or count > 2:\n    return None",
        "at most two invocation-local cuts",
    )
    var admission = _rows(
        (
            "def _snippet():\n    if count < 1 or count > 2:\n        return"
            " None\n    var extra = 8 * count\n    var node_reserve = 3 * count"
            " + 2\n    var term_reserve = 16 * count\n    if (\n       "
            " max_nodes < node_reserve\n        or max_terms < 0\n        or"
            " nodes < 0\n        or nodes > max_nodes - node_reserve\n       "
            " or terms < 0\n        or terms > max_terms\n        or"
            " term_reserve > max_terms - terms\n    ):\n        return None\n  "
            "  nodes += 1\n    terms += extra\n"
        ),
        "_snippet",
    )
    if _run(cuts, admission) != 1:
        _fail("bounded count and complete reserve must precede dispatch debit")
    var loop = -1
    var node_debit = -1
    var term_debit = -1
    index = 0
    while index < len(cuts):
        if cuts[index].find("for ") == 0:
            if loop < 0:
                loop = index
        if cuts[index] == "nodes += 1":
            node_debit = index
        if cuts[index] == "terms += extra":
            term_debit = index
        index += 1
    if (
        loop < 0
        or node_debit < 0
        or term_debit < 0
        or node_debit >= loop
        or term_debit >= loop
    ):
        _fail("dispatch debit must precede optional attempts")
    var followup = """
def _objective_followup_room(
    nodes: Int, terms: Int, max_nodes: Int, max_terms: Int,
    reference_work: Int, center_work: Int,
) -> Bool:
    if (
        nodes < 0
        or nodes > max_nodes
        or terms < 0
        or terms > max_terms
        or reference_work < 0
        or center_work < 0
    ):
        return False
    var remaining = max_terms - terms
    return (
        max_nodes - nodes >= 4
        and center_work <= remaining
        and reference_work <= (remaining - center_work) // 8
    )
"""
    if _function(model, "_objective_followup_room") != _function(
        followup, "_objective_followup_room"
    ):
        _fail("complete overflow-safe integer followup admission")
    var recheck = """
def _objective_recheck_room(nodes: Int, max_nodes: Int) -> Bool:
    return nodes >= 0 and nodes < max_nodes
"""
    if _function(model, "_objective_recheck_room") != _function(
        recheck, "_objective_recheck_room"
    ):
        _fail("complete integer cached-closure recheck admission")
    var fee = _join(_rows(map_source, "_query_node_step_cost"))
    _once(fee, "var fixed = 26 if goal else 20", "reviewed goal node fee")
    _once(fee, "fixed += 16", "stored dispatch logical fee")
    _once(
        fee,
        "if witness:\n    fixed += 14",
        "retained containing-model logical fee",
    )
    _once(fee, "if witness:\n    fixed += 26", "witness frontier logical fee")
    _once(
        fee,
        "return 100 * lanes + fixed",
        "original profile record work convention",
    )
