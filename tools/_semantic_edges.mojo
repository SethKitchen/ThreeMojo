# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md

"""Build the optional-runtime semantic fragment checks.

Each group keeps the historical check order. The caller supplies the
declaration text and the function name for every source in that group.
"""

from tools._python_json import PyJson


def _add(
    mut doc: PyJson,
    items: Int,
    source: String,
    name: String,
    kind: String,
    fragment: String,
    label: String,
    message: String = "",
    call: String = "",
):
    """Append one fragment check.

    Args:
        doc: The document that owns the list.
        items: The list node.
        source: The declaration text.
        name: The function name.
        kind: The fragment kind.
        fragment: The reviewed source fragment.
        label: The failure label.
        message: The count-mismatch text, when it differs from `label`.
        call: The callee for a `before-call` check.
    """
    var item = doc.new_dict()
    doc.set(item, "source", doc.new_str(source))
    doc.set(item, "name", doc.new_str(name))
    doc.set(item, "kind", doc.new_str(kind))
    doc.set(item, "fragment", doc.new_str(fragment))
    doc.set(item, "label", doc.new_str(label))
    doc.set(item, "expected", doc.new_int(1))
    if message != "":
        doc.set(item, "message", doc.new_str(message))
    if call != "":
        doc.set(item, "call", doc.new_str(call))
    doc.append(items, item)


def _pair(doc: PyJson, key: String) raises -> Tuple[String, String]:
    """Return one declaration's text and function name.

    Args:
        doc: The group payload.
        key: The declaration key.

    Returns:
        The source text, then the function name.

    Raises:
        Error: The key or one of its fields is missing.
    """
    var node = doc.at(doc.root, key)
    return doc.text(doc.at(node, "source")), doc.text(doc.at(node, "name"))


def semantic_edge_payload(group: String, payload: String) raises -> String:
    """Return one optional-runtime fragment group.

    Args:
        group: `helper`, `guards`, `origin`, `work`, `model`, `support`,
            `dispatch`, `followup`, `recheck`, or `fee`.
        payload: JSON objects with `source` and `name` for that group.

    Returns:
        A JSON list of fragment checks.

    Raises:
        Error: `group` is unknown, or a required declaration is missing.
    """
    var doc = PyJson.parse(payload)
    var items = doc.new_list()
    if group == "helper":
        var source: String
        var name: String
        source, name = _pair(doc, "helper")
        _add(
            doc,
            items,
            source,
            name,
            "body",
            (
                "return SIMD[DType.uint64, 2](station, scale) =="
                " SIMD[DType.uint64, 2](other_station, other_scale)"
            ),
            "exact UInt64 pair helper comparison",
        )
    elif group == "guards":
        var keys = List[String]()
        keys.append("model")
        keys.append("restrict")
        keys.append("cut")
        keys.append("cuts")
        keys.append("lane")
        keys.append("raw")
        keys.append("metered")
        for key in keys:
            var source: String
            var name: String
            source, name = _pair(doc, key)
            _add(
                doc,
                items,
                source,
                name,
                "first",
                "if not _sum2_supported_environment():\n    return None",
                name,
                message="fresh invocation guard missing or moved: " + name,
            )
    elif group == "origin":
        var origin_source: String
        var origin_name: String
        var raw_source: String
        var raw_name: String
        origin_source, origin_name = _pair(doc, "origin")
        raw_source, raw_name = _pair(doc, "raw")
        _add(
            doc,
            items,
            origin_source,
            origin_name,
            "contains",
            (
                "var error = _sum2_error_checked(magnitude.high,"
                " inherited.high, count)"
            ),
            "grouped origin must use the canonical checked error arguments",
        )
        _add(
            doc,
            items,
            raw_source,
            raw_name,
            "contains",
            (
                "var x_error = _grouped_origin_error(x_ideal, x_magnitude,"
                " x_inherited, 5 * pieces, geometry.x)"
            ),
            "complete X stored-term count and origin",
        )
        _add(
            doc,
            items,
            raw_source,
            raw_name,
            "contains",
            (
                "var y_error = _grouped_origin_error(y_ideal, y_magnitude,"
                " y_inherited, 5 * pieces, geometry.y)"
            ),
            "complete Y stored-term count and origin",
        )
        _add(
            doc,
            items,
            raw_source,
            raw_name,
            "contains",
            (
                "var distance = _ValueJet(d.value, _Interval.whole(),"
                " _Interval.whole(), d.error)"
            ),
            "retain original ideal distance and uniform scalar error",
        )
        _add(
            doc,
            items,
            raw_source,
            raw_name,
            "contains",
            "var copies = (high - low) * multiplicity",
            "actual group multiplicity",
        )
        _add(
            doc,
            items,
            raw_source,
            raw_name,
            "contains",
            "var multiplicity = 1 if weight == 2 else 2",
            "stored symmetric weight multiplicity",
        )
    elif group == "work":
        var work_source: String
        var work_name: String
        var lane_source: String
        var lane_name: String
        var metered_source: String
        var metered_name: String
        work_source, work_name = _pair(doc, "work")
        lane_source, lane_name = _pair(doc, "lane")
        metered_source, metered_name = _pair(doc, "metered")
        _add(
            doc,
            items,
            work_source,
            work_name,
            "contains",
            "return 3 * min(4, pieces)",
            "whole count work bound",
        )
        _add(
            doc,
            items,
            lane_source,
            lane_name,
            "contains",
            (
                "if nodes < 0 or nodes >= max_nodes or terms < 0 or terms >"
                " max_terms or max_terms - terms < 24:\n    return None"
            ),
            "whole optional union admission",
        )
        _add(
            doc,
            items,
            lane_source,
            lane_name,
            "contains",
            (
                "if counts[0] < 1 or counts[1] > 64 or counts[1] < counts[0] or"
                " counts[1] - counts[0] > 1:\n    return None"
            ),
            "complete at-most-two count domain",
        )
        _add(
            doc,
            items,
            lane_source,
            lane_name,
            "contains",
            "var extra = _spiral_grouped_roundoff_work(counts[0])",
            "first count debit",
        )
        _add(
            doc,
            items,
            lane_source,
            lane_name,
            "contains",
            (
                "if counts[1] != counts[0]:\n    extra +="
                " _spiral_grouped_roundoff_work(counts[1])"
            ),
            "second count debit",
        )
        _add(
            doc,
            items,
            lane_source,
            lane_name,
            "before-call",
            "terms += extra",
            "atomic whole-count debit must precede both raw envelopes",
            call="_try_spiral_grouped_roundoff_envelope",
        )
        _add(
            doc,
            items,
            lane_source,
            lane_name,
            "expression",
            (
                "_lane_jet_model_proof[False](road, section, lane, low, high,"
                " Vector3(0, 0, 0), proof, low, high, captured,"
                " require_reuse=True)"
            ),
            "try-only reconstruction cannot invoke hidden GL",
        )
        _add(
            doc,
            items,
            metered_source,
            metered_name,
            "contains",
            "if work + fallback_work > max_terms - terms:\n    return None",
            "standalone adapter preserves independent fallback reservation",
        )
    elif group == "model":
        var model_source: String
        var model_name: String
        var restrict_source: String
        var restrict_name: String
        model_source, model_name = _pair(doc, "model")
        restrict_source, restrict_name = _pair(doc, "restrict")
        _add(
            doc,
            items,
            model_source,
            model_name,
            "expression",
            "low >= high",
            "model ordered owner",
        )
        _add(
            doc,
            items,
            model_source,
            model_name,
            "expression",
            "center_s < low",
            "model center inside owner low",
        )
        _add(
            doc,
            items,
            model_source,
            model_name,
            "expression",
            "center_s > high",
            "model center inside owner high",
        )
        var fields = List[String]()
        fields.append("value")
        fields.append("first")
        fields.append("second")
        for field in fields:
            _add(
                doc,
                items,
                model_source,
                model_name,
                "expression",
                "not _model_interval(domain." + field + ")",
                "model finite whole-owner " + field,
            )
        _add(
            doc,
            items,
            model_source,
            model_name,
            "expression",
            "not isfinite(domain.error)",
            "model uniform error finite",
        )
        _add(
            doc,
            items,
            model_source,
            model_name,
            "expression",
            "domain.error < 0.0",
            "model uniform error nonnegative",
        )
        _add(
            doc,
            items,
            restrict_source,
            restrict_name,
            "expression",
            "low < model.low",
            "restriction cannot widen owner low",
        )
        _add(
            doc,
            items,
            restrict_source,
            restrict_name,
            "expression",
            "high > model.high",
            "restriction cannot widen owner high",
        )
        _add(
            doc,
            items,
            restrict_source,
            restrict_name,
            "expression",
            "bitcast[DType.uint64](scale) != model.scale_word",
            "exact normalization scale word",
        )
        _add(
            doc,
            items,
            restrict_source,
            restrict_name,
            "contains",
            (
                "return _Jet(value, first, model.domain.second,"
                " model.domain.error)"
            ),
            "restriction retains whole-owner curvature and error",
        )
        _add(
            doc,
            items,
            restrict_source,
            restrict_name,
            "contains",
            (
                "var value = model.center.value + model.center.first * delta +"
                " _Interval.point(0.5) * model.domain.second * delta.square()"
            ),
            "same-ideal Taylor value restriction",
        )
    elif group == "support":
        var source: String
        var name: String
        source, name = _pair(doc, "support")
        var rows = List[String]()
        rows.append("best < low")
        rows.append("actual witness lower containment")
        rows.append("best > high")
        rows.append("actual witness upper containment")
        rows.append("not isfinite(best)")
        rows.append("actual witness finite station")
        var index = 0
        while index < len(rows):
            _add(
                doc,
                items,
                source,
                name,
                "expression",
                rows[index],
                rows[index + 1],
            )
            index += 2
        _add(
            doc,
            items,
            source,
            name,
            "contains",
            (
                "var twice_error = _Interval.point(2.0) *"
                " _Interval.point(domain.error)"
            ),
            "support uses uniform whole-domain error",
        )
        _add(
            doc,
            items,
            source,
            name,
            "contains",
            (
                "var four_error = _Interval.point(4.0) *"
                " _Interval.point(domain.error)"
            ),
            "convex support uses uniform whole-domain error",
        )
        _add(
            doc,
            items,
            source,
            name,
            "no-attribute",
            "center.error",
            "translated center error cannot replace world error",
        )
    elif group == "dispatch":
        var predicate_source: String
        var predicate_name: String
        var cuts_source: String
        var cuts_name: String
        predicate_source, predicate_name = _pair(doc, "predicate")
        cuts_source, cuts_name = _pair(doc, "cuts")
        _add(
            doc,
            items,
            predicate_source,
            predicate_name,
            "body",
            "return min(max(station - origin, 0.0), length) > local",
            "exact stored subtraction/clamp dispatch predicate",
        )
        _add(
            doc,
            items,
            cuts_source,
            cuts_name,
            "contains",
            (
                "var before_index = _sample_index(geometry, min(max(before -"
                " record.s, 0.0), geometry.length))"
            ),
            "actual predecessor sample index",
        )
        _add(
            doc,
            items,
            cuts_source,
            cuts_name,
            "contains",
            (
                "var after_index = _sample_index(geometry, min(max(station -"
                " record.s, 0.0), geometry.length))"
            ),
            "actual cut sample index",
        )
        _add(
            doc,
            items,
            cuts_source,
            cuts_name,
            "contains",
            (
                "if before_index != threshold_at - 1 or after_index !="
                " threshold_at:\n    return None"
            ),
            "both actual indices must match original owners",
        )
        _add(
            doc,
            items,
            cuts_source,
            cuts_name,
            "contains",
            "var node_reserve = 3 * count + 2",
            "dispatch node reserve includes descendants and rechecks",
        )
        _add(
            doc,
            items,
            cuts_source,
            cuts_name,
            "contains",
            "var term_reserve = 16 * count",
            "dispatch probe and descendant term reserve",
        )
        _add(
            doc,
            items,
            cuts_source,
            cuts_name,
            "contains",
            (
                "if max_nodes < node_reserve or max_terms < 0 or nodes < 0 or"
                " nodes > max_nodes - node_reserve or terms < 0 or terms >"
                " max_terms or term_reserve > max_terms - terms:\n    return"
                " None"
            ),
            "complete dispatch followup reserve before optional work",
        )
        _add(
            doc,
            items,
            cuts_source,
            cuts_name,
            "contains",
            "var extra = 8 * count",
            "complete optional dispatch debit",
        )
        _add(
            doc,
            items,
            cuts_source,
            cuts_name,
            "contains",
            "if count < 1 or count > 2:\n    return None",
            "at most two invocation-local cuts",
        )
        _add(
            doc,
            items,
            cuts_source,
            cuts_name,
            "sequence",
            (
                "\nif count < 1 or count > 2:\n    return None\nvar extra = 8 *"
                " count\nvar node_reserve = 3 * count + 2\nvar term_reserve ="
                " 16 * count\nif max_nodes < node_reserve or max_terms < 0 or"
                " nodes < 0 or nodes > max_nodes - node_reserve or terms < 0 or"
                " terms > max_terms or term_reserve > max_terms - terms:\n   "
                " return None\nnodes += 1\nterms += extra\n"
            ),
            "bounded count and complete reserve must precede dispatch debit",
        )
        _add(
            doc,
            items,
            cuts_source,
            cuts_name,
            "before-loop",
            "nodes += 1",
            "dispatch debit must precede optional attempts",
        )
        _add(
            doc,
            items,
            cuts_source,
            cuts_name,
            "before-loop",
            "terms += extra",
            "dispatch debit must precede optional attempts",
        )
    elif group == "followup":
        var follow_source: String
        var follow_name: String
        follow_source, follow_name = _pair(doc, "room")
        _add(
            doc,
            items,
            follow_source,
            follow_name,
            "equal",
            (
                "\ndef _objective_followup_room(\n    nodes: Int, terms: Int,"
                " max_nodes: Int, max_terms: Int,\n    reference_work: Int,"
                " center_work: Int,\n) -> Bool:\n    if nodes < 0 or nodes >"
                " max_nodes or terms < 0 or terms > max_terms or reference_work"
                " < 0 or center_work < 0:\n        return False\n    var"
                " remaining = max_terms - terms\n    return (\n       "
                " max_nodes - nodes >= 4\n        and center_work <="
                " remaining\n        and reference_work <= (remaining -"
                " center_work) // 8\n    )\n"
            ),
            "complete overflow-safe integer followup admission",
        )
    elif group == "recheck":
        var recheck_source: String
        var recheck_name: String
        recheck_source, recheck_name = _pair(doc, "recheck")
        _add(
            doc,
            items,
            recheck_source,
            recheck_name,
            "equal",
            (
                "\ndef _objective_recheck_room(nodes: Int, max_nodes: Int) ->"
                " Bool:\n    return nodes >= 0 and nodes < max_nodes\n"
            ),
            "complete integer cached-closure recheck admission",
        )
    elif group == "fee":
        var fee_source: String
        var fee_name: String
        fee_source, fee_name = _pair(doc, "fee")
        _add(
            doc,
            items,
            fee_source,
            fee_name,
            "contains",
            "var fixed = 26 if goal else 20",
            "reviewed goal node fee",
        )
        _add(
            doc,
            items,
            fee_source,
            fee_name,
            "contains",
            "fixed += 16",
            "stored dispatch logical fee",
        )
        _add(
            doc,
            items,
            fee_source,
            fee_name,
            "contains",
            "if witness:\n    fixed += 14",
            "retained containing-model logical fee",
        )
        _add(
            doc,
            items,
            fee_source,
            fee_name,
            "contains",
            "if witness:\n    fixed += 26",
            "witness frontier logical fee",
        )
        _add(
            doc,
            items,
            fee_source,
            fee_name,
            "contains",
            "return 100 * lanes + fixed",
            "original profile record work convention",
        )
    else:
        raise Error("optional runtime edge group changed")
    doc.root = items
    return doc.dumps()
