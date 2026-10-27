# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md

"""Build the lane-search fragment checks.

The fresh producer, the two expansion memos, and the search predicates stay
in their historical order. The caller supplies the run source and its name.
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
):
    """Append one fragment check.

    Args:
        doc: The document that owns the list.
        items: The list node.
        source: The run declaration.
        name: The run function name.
        kind: The fragment kind.
        fragment: The reviewed source fragment.
        label: The failure label.
    """
    var item = doc.new_dict()
    doc.set(item, "source", doc.new_str(source))
    doc.set(item, "name", doc.new_str(name))
    doc.set(item, "kind", doc.new_str(kind))
    doc.set(item, "fragment", doc.new_str(fragment))
    doc.set(item, "label", doc.new_str(label))
    doc.set(item, "expected", doc.new_int(1))
    doc.append(items, item)


def search_edge_payload(
    source: String, name: String, mode: String
) raises -> String:
    """Return the fresh or search fragment checks.

    Args:
        source: The run declaration.
        name: The run function name.
        mode: `fresh` or `search`.

    Returns:
        A JSON list of fragment checks.

    Raises:
        Error: `mode` is not `fresh` or `search`.
    """
    if mode != "fresh" and mode != "search":
        raise Error("runtime search edge mode changed")
    var search = mode == "search"
    var doc = PyJson()
    var items = doc.new_list()
    _add(
        doc,
        items,
        source,
        name,
        "fresh",
        (
            '\nif certificate.terms > max_terms - work:\n    raise Error("Lane'
            " refinement exhausted its quadrature work"
            ' limit")\ncertificate.terms += work\nvar point_domain: Tuple[_Jet,'
            " _Jet, _Jet]\nif frozen:\n    point_domain ="
            " _frozen_arc_center(frozen.value(), lo, hi, Vector3(0, 0,"
            " 0))\nelse:\n    point_domain = _lane_jet_with_proof(road,"
            " section, lane, lo, hi, low, high, spiral_proof)\nvar natural ="
            " _scaled_point_distance_box(point_domain, location, scale).low\n"
        ),
        "fresh",
    )
    _add(
        doc,
        items,
        source,
        name,
        "contains",
        "var cached_fast: Optional[Tuple[UInt64, UInt64, _Jet]] = None",
        "exact expansion memo lifetime is one search invocation",
    )
    _add(
        doc,
        items,
        source,
        name,
        "contains",
        "var cached_expansion: Optional[Tuple[UInt64, UInt64, _Jet]] = None",
        "exact expansion memo lifetime is one search invocation",
    )
    _add(
        doc,
        items,
        source,
        name,
        "sequence",
        (
            "var station_word = bitcast[DType.uint64](center_s)\nvar scale_word"
            " = bitcast[DType.uint64](scale)\n\nif external_witness and"
            " cached_fast and _same_cache_key(cached_fast.value()[0],"
            " cached_fast.value()[1], station_word, scale_word):\n   "
            " fast_center = cached_fast.value()[2]\nelse:\n    fast_center ="
            " _try_proof_expansion_jet(road, section, lane, center_s, location,"
            " scale, low, high, spiral_proof)\n    if external_witness and"
            " fast_center:\n        cached_fast = (station_word, scale_word,"
            " fast_center.value())\n"
        ),
        "exact station/scale proof expansion memo and fresh fallback",
    )
    _add(
        doc,
        items,
        source,
        name,
        "sequence",
        (
            "var station_word = bitcast[DType.uint64](center_s)\nvar scale_word"
            " = bitcast[DType.uint64](scale)\n\nif external_witness and"
            " cached_expansion and _same_cache_key(cached_expansion.value()[0],"
            " cached_expansion.value()[1], station_word, scale_word):\n   "
            " center = cached_expansion.value()[2]\nelse:\n    if frozen:\n    "
            "    center = _frozen_arc_expansion(frozen.value(), center_s,"
            " location, scale)\n    else:\n        center ="
            " _expansion_distance_jet(road, section, lane, center_s, location,"
            " scale)\n    if external_witness:\n        cached_expansion ="
            " (station_word, scale_word, center)\n"
        ),
        "exact station/scale translated expansion memo and fresh fallback",
    )
    if search:
        _add(
            doc,
            items,
            source,
            name,
            "contains",
            "var sampled_cuts: Optional[Tuple[Float64, Float64, Int]] = None",
            "cut lifetime is one search invocation",
        )
        _add(
            doc,
            items,
            source,
            name,
            "contains",
            "var best = certificate.s",
            "incumbent is the validated actual certificate witness",
        )
        _add(
            doc,
            items,
            source,
            name,
            "contains",
            "var best_point = certificate.point.copy()",
            "retain actual witness point",
        )
        _add(
            doc,
            items,
            source,
            name,
            "expression",
            "_minimizer_support(domain, center, center_s, best, lo, hi)",
            "support receives same ideal and actual witness",
        )
        _add(
            doc,
            items,
            source,
            name,
            "sequence",
            (
                "\ncertificate.terms += work\nvar grouped: Optional[Tuple[_Jet,"
                " _Jet, _Jet]] = None\nif max_nodes - certificate.nodes >= 2:\n"
                "    grouped = _try_grouped_lane_jet(road, section, lane, lo,"
                " hi, certificate.nodes, certificate.terms, max_nodes,"
                " max_terms)\nif grouped:\n    point_domain ="
                " grouped.value()\nelse:\n    point_domain = _lane_jet(road,"
                " section, lane, lo, hi)\n"
            ),
            "grouped caller must retain recheck and prepaid original fallback",
        )
        _add(
            doc,
            items,
            source,
            name,
            "expression",
            (
                "_try_grouped_lane_jet(road, section, lane, lo, hi,"
                " certificate.nodes, certificate.terms, max_nodes, max_terms)"
            ),
            "one guarded grouped caller edge",
        )
        _add(
            doc,
            items,
            source,
            name,
            "setup",
            (
                'if task[2] >= max_depth:\n    raise Error("Lane refinement'
                ' exhausted its numerical accuracy limit")'
            ),
            "depth refusal precedes dispatch setup",
        )
        _add(
            doc,
            items,
            source,
            name,
            "expression",
            (
                "bitcast[DType.float64](bitcast[DType.uint64](split_at) -"
                " UInt64(1))"
            ),
            "split predecessor preserves every stored owner station",
        )
    doc.root = items
    return doc.dumps()
