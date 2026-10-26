# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Check the Sum2 helper use sites.

Each protected helper use stays inside a reviewed caller. Lane refinement
also keeps the grouped and support uses in the center-bound helper.
"""

from std.pathlib import Path

from tests._python_tokens import _tokenize


comptime _NAME = 1
comptime _NEWLINE = 4
comptime _INDENT = 5
comptime _DEDENT = 6


def _fail(message: String) raises:
    """Raise a Sum2 use error.

    Args:
        message: The failure text.

    Raises:
        Error: A protected helper use is outside a reviewed caller.
    """
    raise Error(message)


def _helper(name: String) -> Bool:
    """Return whether `name` is a protected helper.

    Args:
        name: One identifier.

    Returns:
        True for a reviewed helper function.
    """
    if name == "_seed_exact_interval" or name == "_seed_reference_domain":
        return True
    if name == "_winner_seed_room" or name == "_try_winner_seed":
        return True
    if name == "_sum2_update" or name == "_require_sum2_environment":
        return True
    if name == "_sum2_supported_environment" or name == "_sum2_error":
        return True
    if name == "_sum2_error_checked" or name == "_spiral_proof_branch":
        return True
    if (
        name == "_grouped_origin_error"
        or name == "_try_spiral_grouped_roundoff_envelope"
    ):
        return True
    if name == "_try_objective_model" or name == "_restrict_objective_model":
        return True
    if name == "_objective_followup_room" or name == "_objective_recheck_room":
        return True
    if name == "_minimizer_support" or name == "_sample_dispatch_predicate":
        return True
    if name == "_sample_dispatch_cut" or name == "_try_sample_dispatch_cuts":
        return True
    return name == "_try_grouped_lane_jet"


def _wanted(module: String) -> List[String]:
    """Return the reviewed functions of `module`.

    Args:
        module: The caller module.

    Returns:
        The function names whose bodies may use a protected helper.
    """
    var names = List[String]()
    if module == "lane_geometry":
        names.append("_lane_spiral")
    elif module == "curve_bounds":
        names.append("_spiral_expression")
        names.append("_lane_jet_model_proof")
    elif module == "lane_refinement":
        names.append("_lane_certificate_contains")
        names.append("_refine_lane_certificate")
        names.append("_continue_lane_certificate")
        names.append("_run_lane_search")
        names.append("_try_lane_center_bound")
    elif module == "map":
        names.append("_closest_lane_certificate")
        names.append("_closest_lane_certificate_with_work")
        names.append("_create_segments")
        names.append("_seed_exact_interval")
        names.append("_seed_reference_domain")
        names.append("_winner_seed_room")
        names.append("_try_winner_seed")
    elif module == "map_builder":
        names.append("build")
    elif module == "spiral_domain_proof":
        names.append("_try_pack_spiral_proof")
        names.append("_spiral_proof_branch")
    elif module == "spiral_moment_proof":
        names.append("_try_build_spiral_moments")
        names.append("_try_spiral_moment_expansion")
    elif module == "spiral_moment_table":
        names.append("_try_spiral_moment_expansion")
    elif module == "spiral_roundoff_proof":
        names.append("_sum2_envelope_error")
    elif module == "curve_objective_model":
        names.append("_try_objective_model")
        names.append("_restrict_objective_model")
        names.append("_objective_followup_room")
        names.append("_objective_recheck_room")
    elif module == "curve_minimizer_support":
        names.append("_minimizer_support")
    elif module == "curve_sample_dispatch":
        names.append("_sample_dispatch_predicate")
        names.append("_sample_dispatch_cut")
        names.append("_try_sample_dispatch_cuts")
    elif module == "spiral_grouped_lane":
        names.append("_try_grouped_lane_jet")
    elif module == "spiral_grouped_roundoff_proof":
        names.append("_grouped_origin_error")
        names.append("_try_spiral_grouped_roundoff_envelope")
        names.append("_try_spiral_grouped_roundoff_envelope_metered")
    return names^


def _modules() -> List[String]:
    """Return the caller modules.

    Returns:
        The module names.
    """
    var names = List[String]()
    names.append("lane_geometry")
    names.append("curve_bounds")
    names.append("lane_refinement")
    names.append("map")
    names.append("map_builder")
    names.append("spiral_domain_proof")
    names.append("spiral_moment_proof")
    names.append("spiral_moment_table")
    names.append("spiral_roundoff_proof")
    names.append("curve_objective_model")
    names.append("curve_minimizer_support")
    names.append("curve_sample_dispatch")
    names.append("spiral_grouped_lane")
    names.append("spiral_grouped_roundoff_proof")
    return names^


def _has(names: List[String], name: String) -> Bool:
    """Return whether `name` is present.

    Args:
        names: The names.
        name: The name to find.

    Returns:
        True when the name is present.
    """
    var index = 0
    while index < len(names):
        if names[index] == name:
            return True
        index += 1
    return False


def _inside(starts: List[Int], stops: List[Int], index: Int) -> Bool:
    """Return whether `index` lies in a span.

    Args:
        starts: The span starts.
        stops: The span ends.
        index: The token index.

    Returns:
        True when a span contains the index.
    """
    var cursor = 0
    while cursor < len(starts):
        if starts[cursor] <= index and index < stops[cursor]:
            return True
        cursor += 1
    return False


def _spans(
    kinds: List[Int],
    texts: List[String],
    wanted: List[String],
    mut starts: List[Int],
    mut stops: List[Int],
) raises:
    """Record each reviewed function span.

    Args:
        kinds: The token kinds.
        texts: The token texts.
        wanted: The function names.
        starts: The span starts, appended by this call.
        stops: The span ends, appended by this call.

    Raises:
        Error: A reviewed function is missing or has no body.
    """
    var depth = 0
    var deco = List[Int]()
    deco.append(-1)
    var statement = List[Int]()
    var index = 0
    var found = List[String]()
    var sigs = List[Int]()
    var origins = List[Int]()
    while index < len(kinds):
        var kind = kinds[index]
        if kind == _INDENT:
            depth += 1
            deco.append(-1)
        elif kind == _DEDENT:
            if depth == 0:
                _fail("unmatched source scope")
            _ = deco.pop()
            depth -= 1
        elif kind == _NEWLINE:
            if len(statement) > 0:
                var first = texts[statement[0]]
                if first == "@":
                    if deco[depth] < 0:
                        deco[depth] = statement[0]
                else:
                    var origin = statement[0]
                    if deco[depth] >= 0:
                        origin = deco[depth]
                    deco[depth] = -1
                    if (
                        len(statement) >= 2
                        and first == "def"
                        and _has(wanted, texts[statement[1]])
                    ):
                        var name = texts[statement[1]]
                        if _has(found, name):
                            _fail(
                                "missing or ambiguous actual guard"
                                " declaration: "
                                + name
                            )
                        found.append(name)
                        origins.append(origin)
                        sigs.append(index)
                statement.clear()
        else:
            statement.append(index)
        index += 1
    var name_index = 0
    while name_index < len(wanted):
        if not _has(found, wanted[name_index]):
            _fail(
                "missing or ambiguous actual guard declaration: "
                + wanted[name_index]
            )
        name_index += 1
    var span = 0
    while span < len(sigs):
        var body = sigs[span] + 1
        if body >= len(kinds) or kinds[body] != _INDENT:
            _fail("unsupported guard function body")
        var end = body + 1
        var nest = 1
        while end < len(kinds) and nest > 0:
            if kinds[end] == _INDENT:
                nest += 1
            elif kinds[end] == _DEDENT:
                nest -= 1
            end += 1
        if nest != 0:
            _fail("unclosed guard function body")
        starts.append(origins[span])
        stops.append(end)
        span += 1


def _check(module: String, source: String) raises:
    """Require every protected use in `module` to be reviewed.

    Args:
        module: The caller module.
        source: The module source.

    Raises:
        Error: A protected helper is used outside a reviewed function or import.
    """
    var kinds = List[Int]()
    var texts = List[String]()
    _tokenize(source, kinds, texts)
    var starts = List[Int]()
    var stops = List[Int]()
    _spans(kinds, texts, _wanted(module), starts, stops)
    var depth = 0
    var index = 0
    while index < len(kinds):
        var kind = kinds[index]
        if kind == _INDENT:
            depth += 1
        elif kind == _DEDENT:
            depth -= 1
        elif (
            depth == 0
            and kind == _NAME
            and (texts[index] == "from" or texts[index] == "import")
        ):
            var end = index
            while end < len(kinds) and kinds[end] != _NEWLINE:
                end += 1
            starts.append(index)
            stops.append(end)
        index += 1
    index = 0
    while index < len(kinds):
        if kinds[index] == _NAME and _helper(texts[index]):
            if not _inside(starts, stops, index):
                _fail(
                    "unreviewed Sum2 helper binding/use: "
                    + module
                    + ":"
                    + texts[index]
                )
        index += 1


def sum2_guard_uses(root: String) raises:
    """Require the reviewed Sum2 helper use sites.

    Args:
        root: The repository root.

    Raises:
        Error: A protected helper use is outside a reviewed caller.
    """
    var base = root
    if base.byte_length() > 1 and base.endswith("/"):
        var end = base.byte_length() - 1
        var trimmed = String(base[byte=0:end])
        base = trimmed
    var modules = _modules()
    var index = 0
    while index < len(modules):
        var module = modules[index]
        var path = base + "/extensions/carla/" + module + ".mojo"
        _check(module, Path(path).read_text())
        index += 1
