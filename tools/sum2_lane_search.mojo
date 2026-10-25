# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Check the live lane search.

Ten reviewed spans keep the live search body. Restoring those spans
matches the pinned caller.
"""

from std.pathlib import Path

from tests._python_tokens import token_sha256
from tools._python_json import PY_STR, PyJson
from tools.sum2_guard_callers import _function_text


comptime _PINS = "tools/carla_lane_oracle/sum2-guard-pins.json"
comptime _LANE = "extensions/carla/lane_refinement.mojo"
comptime _NAME = "_run_lane_search"
comptime _MESSAGE = (
    "Sum2 complete guarded caller changed: lane_refinement:_run_lane_search"
)
comptime _LIVE_0 = (
    "    var sampled_cuts: Optional[Tuple[Float64, Float64, Int]] = N"
    + "one\n    var best = certificate.s\n"
)
comptime _PIN_0 = (
    "    var sampled_cuts: Optional[Tuple[Float64, Float64, Int]] = N"
    + "one\n    var cached_fast: Optional[Tuple[UInt64, UInt64, _Jet]] "
    + "= None\n    var cached_expansion: Optional[Tuple[UInt64, UInt64,"
    + " _Jet]] = None\n    var best = certificate.s\n"
)
comptime _LIVE_1 = (
    "        frozen = _frozen_arc_context(road, section, lane, low, h"
    + "igh)\n    var expansion_context = _LaneExpansionContext(\n      "
    + "  section,\n        lane,\n        _Interval(low, high),\n      "
    + "  location,\n        spiral_proof,\n        frozen,\n        ext"
    + "ernal_witness.copy(),\n        None,\n        None,\n    )\n    "
    + "while len(pending) > 0 or closed.needs_validation():\n"
)
comptime _PIN_1 = (
    "        frozen = _frozen_arc_context(road, section, lane, low, h"
    + "igh)\n    while len(pending) > 0 or closed.needs_validation():\n"
)
comptime _LIVE_2 = (
    "            )\n            # Admit finite interpolation width be"
    + "fore the derivative tests.\n            # All three predicates a"
    + "re retained. The earlier midpoint already\n            # evaluat"
    + "ed this same subtraction, including an overflowing span.\n      "
    + "      if (\n"
)
comptime _PIN_2 = "            )\n            if (\n"
comptime _LIVE_3 = (
    "            if (\n                isfinite(hi - lo)\n           "
    + "     and domain.second.low > 0.0\n                and domain.fir"
    + "st.contains(0.0)\n"
)
comptime _PIN_3 = (
    "            if (\n                domain.second.low > 0.0\n     "
    + "           and domain.first.contains(0.0)\n"
)
comptime _LIVE_4 = (
    "                and domain.first.contains(0.0)\n            ):\n"
)
comptime _PIN_4 = (
    "                and domain.first.contains(0.0)\n                "
    + "and isfinite(hi - lo)\n            ):\n"
)
comptime _LIVE_5 = (
    "                ).low\n                # An unchanged seed repea"
    + "ts the admitted bound exactly.\n                # An improved se"
    + "ed is an actual in-cell witness, so its\n                # upper"
    + " distance cannot fall below this natural enclosure.\n           "
    + "     if _goal_excludes(natural, scale, goal):\n"
)
comptime _PIN_5 = (
    "                ).low\n                if natural > best_upper:"
    + "\n                    continue\n                if _goal_exclude"
    + "s(natural, scale, goal):\n"
)
comptime _LIVE_6 = (
    "            )\n            var proposal = _try_lane_center_bound"
    + "(\n                road,\n                expansion_context,\n  "
    + "              _Interval(lo, hi),\n                best,\n       "
    + "         domain,\n                natural,\n                work"
    + ",\n                _LaneBoundPolicy(best_upper, scale, tolerance"
    + ", goal),\n                certificate.nodes,\n                ce"
    + "rtificate.terms,\n                max_nodes,\n                ma"
    + "x_terms,\n            )\n            if proposal:\n             "
    + "   ref bound = proposal.value()\n                if bound.isa[_L"
    + "aneBoundDiscard]():\n                    continue\n"
)
comptime _PIN_6 = (
    "            )\n            # A clamped singleton endpoint can ha"
    + "ve a different jet from\n            # the interior branch. Tayl"
    + "or bounds need that same branch.\n            var center_s = _ex"
    + "pansion_center(lo, hi, best)\n            var center_work = _ref"
    + "erence_work(road, center_s, center_s)\n            if center_wor"
    + "k >= 0:\n                if certificate.terms > max_terms - cent"
    + "er_work:\n                    raise Error(\n                    "
    + '    "Lane refinement exhausted its quadrature work limit"\n   '
    + "                 )\n                certificate.terms += center_"
    + "work\n                var fast_center: Optional[_Jet] = None\n  "
    + "              # The original full-domain second derivative and s"
    + "calar\n                # error also apply to this ideal moment-b"
    + "acked expansion.\n                # Retain headroom for the unch"
    + "anged translated fallback.\n                if (\n              "
    + "      spiral_proof\n                    and domain.second.is_fin"
    + "ite()\n                    and center_work <= max_terms - certif"
    + "icate.terms\n                ):\n                    var station"
    + "_word = bitcast[DType.uint64](center_s)\n                    var"
    + " scale_word = bitcast[DType.uint64](scale)\n                    "
    + "if (\n                        external_witness\n                "
    + "        and cached_fast\n                        and cached_fast"
    + ".value()[0] == station_word\n                        and cached_"
    + "fast.value()[1] == scale_word\n                    ):\n         "
    + "               fast_center = cached_fast.value()[2]\n           "
    + "         else:\n                        fast_center = _try_proof"
    + "_expansion_jet(\n                            road,\n            "
    + "                section,\n                            lane,\n   "
    + "                         center_s,\n                            "
    + "location,\n                            scale,\n                 "
    + "           low,\n                            high,\n            "
    + "                spiral_proof,\n                        )\n      "
    + "                  if external_witness and fast_center:\n        "
    + "                    cached_fast = (\n                           "
    + "     station_word,\n                                scale_word,"
    + "\n                                fast_center.value(),\n        "
    + "                    )\n                    if fast_center:\n    "
    + "                    var fast_delta = _Interval(lo, hi) - _Interv"
    + "al.point(\n                            center_s\n               "
    + "         )\n                        var fast_lower = max(\n     "
    + "                       natural,\n                            _gl"
    + "obal_lower(\n                                domain, fast_center"
    + ".value(), fast_delta\n                            ),\n          "
    + "              )\n                        if fast_lower > best_up"
    + "per:\n                            continue\n                    "
    + "    if (\n                            _goal_excludes(fast_lower,"
    + " scale, goal)\n                            or _next_up(best_uppe"
    + "r - fast_lower) <= tolerance\n                        ):\n      "
    + "                      closed.add(\n                             "
    + "   _ClosedInterval(\n                                    lo, hi,"
    + " task[2], fast_lower, scale\n                                )\n"
    + "                            )\n                            conti"
    + "nue\n                        # A failed optional attempt is char"
    + "ged before the\n                        # original traversal; ne"
    + "ither work cap is enlarged.\n                        certificate"
    + ".terms += center_work\n                # Only a failed cached pr"
    + "oof needs the expensive local GL\n                # error traver"
    + "sal. It is still charged before execution.\n                if s"
    + "piral_proof and domain.error > tolerance * 0.25:\n              "
    + "      if certificate.terms > max_terms - work:\n                "
    + '        raise Error(\n                            "Lane refinem'
    + 'ent exhausted its quadrature work"\n                           '
    + ' " limit"\n                        )\n                    cert'
    + "ificate.terms += work\n                    # Original F is prepa"
    + "id; the optional model owns its node\n                    # and "
    + "whole-union C. A decline retains all actual debits.\n           "
    + "         var grouped: Optional[Tuple[_Jet, _Jet, _Jet]] = None\n"
    + "                    # Keep the original closed-cell recheck avai"
    + "lable after\n                    # this optional producer. The o"
    + "riginal F is already paid.\n                    if max_nodes - c"
    + "ertificate.nodes >= 2:\n                        grouped = _try_g"
    + "rouped_lane_jet(\n                            road,\n           "
    + "                 section,\n                            lane,\n  "
    + "                          lo,\n                            hi,\n"
    + "                            certificate.nodes,\n                "
    + "            certificate.terms,\n                            max_"
    + "nodes,\n                            max_terms,\n                "
    + "        )\n                    if grouped:\n                    "
    + "    point_domain = grouped.value()\n                    else:\n "
    + "                       point_domain = _lane_jet(road, section, l"
    + "ane, lo, hi)\n                    natural = max(\n              "
    + "          natural,\n                        _scaled_point_distan"
    + "ce_box(\n                            point_domain, location, sca"
    + "le\n                        ).low,\n                    )\n     "
    + "               if natural > best_upper:\n                       "
    + " continue\n                    if _goal_excludes(natural, scale,"
    + " goal):\n                        closed.add(\n                  "
    + "          _ClosedInterval(lo, hi, task[2], natural, scale)\n    "
    + "                    )\n                        continue\n       "
    + "             domain = _scaled_point_distance_jet(\n             "
    + "           point_domain, location, scale\n                    )"
    + "\n                    if fast_center:\n                        v"
    + "ar tightened_delta = _Interval(\n                            lo,"
    + " hi\n                        ) - _Interval.point(center_s)\n    "
    + "                    var tightened_lower = max(\n                "
    + "            natural,\n                            _global_lower("
    + "\n                                domain, fast_center.value(), t"
    + "ightened_delta\n                            ),\n                "
    + "        )\n                        if tightened_lower > best_upp"
    + "er:\n                            continue\n                     "
    + "   if (\n                            _goal_excludes(tightened_lo"
    + "wer, scale, goal)\n                            or _next_up(best_"
    + "upper - tightened_lower)\n                            <= toleran"
    + "ce\n                        ):\n                            clos"
    + "ed.add(\n                                _ClosedInterval(\n     "
    + "                               lo, hi, task[2], tightened_lower,"
    + " scale\n                                )\n                     "
    + "       )\n                            continue\n                "
    + "# A nonfinite second derivative makes _global_lower ignore\n    "
    + "            # its expansion argument. A finite rounded domain va"
    + "lue also\n                # establishes that this is an evaluate"
    + "d expression enclosure,\n                # rather than an unvali"
    + "dated whole/unknown record domain.\n                # Retain the"
    + " original work reservation above. Only skip the\n               "
    + " # unused traversal; no bound, tolerance, or cap changes.\n     "
    + "           var center = _Jet.constant(0.0)\n                if ("
    + "\n                    domain.second.is_finite()\n               "
    + "     or not domain.rounded_value().is_finite()\n                "
    + "):\n                    var station_word = bitcast[DType.uint64]"
    + "(center_s)\n                    var scale_word = bitcast[DType.u"
    + "int64](scale)\n                    if (\n                       "
    + " external_witness\n                        and cached_expansion"
    + "\n                        and cached_expansion.value()[0] == sta"
    + "tion_word\n                        and cached_expansion.value()["
    + "1] == scale_word\n                    ):\n                      "
    + "  center = cached_expansion.value()[2]\n                    else"
    + ":\n                        if frozen:\n                         "
    + "   center = _frozen_arc_expansion(\n                            "
    + "    frozen.value(), center_s, location, scale\n                 "
    + "           )\n                        else:\n                   "
    + "         center = _expansion_distance_jet(\n                    "
    + "            road, section, lane, center_s, location, scale\n    "
    + "                        )\n                        if external_w"
    + "itness:\n                            cached_expansion = (\n     "
    + "                           station_word,\n                      "
    + "          scale_word,\n                                center,\n"
    + "                            )\n                var delta = _Inte"
    + "rval(lo, hi) - _Interval.point(center_s)\n                var lo"
    + "wer = max(natural, _global_lower(domain, center, delta))\n      "
    + "          var support = _Interval(lo, hi)\n                if ex"
    + "ternal_witness:\n                    support = _minimizer_suppor"
    + "t(\n                        domain, center, center_s, best, lo, "
    + "hi\n                    )\n                if lower > best_upper"
    + ":\n                    continue\n"
)
comptime _LIVE_7 = (
    "                    continue\n                if bound.isa[_Lane"
    + "BoundClose]():\n                    var close = bound[_LaneBound"
    + "Close]\n                    closed.add(\n"
)
comptime _PIN_7 = (
    "                    continue\n                if (\n            "
    + "        _goal_excludes(lower, scale, goal)\n                    "
    + "or _next_up(best_upper - lower) <= tolerance\n                ):"
    + "\n                    closed.add(\n"
)
comptime _LIVE_8 = (
    "                        _ClosedInterval(\n                      "
    + "      close.support.low,\n                            close.supp"
    + "ort.high,\n                            task[2],\n               "
    + "             close.lower,\n                            scale,\n "
    + "                       )\n"
)
comptime _PIN_8 = (
    "                        _ClosedInterval(\n                      "
    + "      support.low, support.high, task[2], lower, scale\n        "
    + "                )\n"
)
comptime _LIVE_9 = (
    "                    continue\n                var support = boun"
    + "d[_LaneBoundContract].support\n                if task[2] >= max"
    + "_depth:\n                    raise Error(\n                     "
    + '   "Lane refinement exhausted its numerical accuracy limit"\n '
    + "                   )\n                pending.append((support.lo"
    + "w, support.high, task[2] + 1))\n                continue\n      "
    + "  if task[2] >= max_depth:\n"
)
comptime _PIN_9 = (
    "                    continue\n                if support.low > l"
    + "o or support.high < hi:\n                    if task[2] >= max_d"
    + "epth:\n                        raise Error(\n                   "
    + '         "Lane refinement exhausted its numerical accuracy"\n '
    + '                           " limit"\n                        )'
    + "\n                    pending.append((support.low, support.high,"
    + " task[2] + 1))\n                    continue\n        if task[2]"
    + " >= max_depth:\n"
)


def _fail(message: String) raises:
    """Raise a lane-search error.

    Args:
        message: The failure text.

    Raises:
        Error: The live lane search changed.
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


def _live(index: Int) -> String:
    """Return one live span.

    Args:
        index: The span number.

    Returns:
        The live text.
    """
    if index == 0:
        return _LIVE_0
    if index == 1:
        return _LIVE_1
    if index == 2:
        return _LIVE_2
    if index == 3:
        return _LIVE_3
    if index == 4:
        return _LIVE_4
    if index == 5:
        return _LIVE_5
    if index == 6:
        return _LIVE_6
    if index == 7:
        return _LIVE_7
    if index == 8:
        return _LIVE_8
    if index == 9:
        return _LIVE_9
    return ""


def _pinned(index: Int) -> String:
    """Return one pinned span.

    Args:
        index: The span number.

    Returns:
        The pinned text.
    """
    if index == 0:
        return _PIN_0
    if index == 1:
        return _PIN_1
    if index == 2:
        return _PIN_2
    if index == 3:
        return _PIN_3
    if index == 4:
        return _PIN_4
    if index == 5:
        return _PIN_5
    if index == 6:
        return _PIN_6
    if index == 7:
        return _PIN_7
    if index == 8:
        return _PIN_8
    if index == 9:
        return _PIN_9
    return ""


def sum2_lane_search(root: String) raises:
    """Require the live lane search.

    Args:
        root: The repository root.

    Raises:
        Error: A reviewed span or the caller body changed.
    """
    var base = root
    if base.byte_length() > 1 and base.endswith("/"):
        var end = base.byte_length() - 1
        var trimmed = String(base[byte=0:end])
        base = trimmed
    var doc = PyJson.parse(Path(base + "/" + _PINS).read_text())
    var callers = doc.at(doc.root, "callers")
    var record = doc.at(callers, "lane_refinement")
    var functions = doc.at(record, "functions")
    var pinned = doc.at(functions, _NAME)
    if doc.kind(pinned) != PY_STR:
        _fail(_MESSAGE)
    var live = _function_text(Path(base + "/" + _LANE).read_text(), _NAME)
    var index = 0
    while index < 10:
        if _count(live, _live(index)) != 1:
            _fail(_MESSAGE)
        index += 1
    var restored = live
    index = 0
    while index < 10:
        restored = restored.replace(_live(index), _pinned(index))
        index += 1
    if token_sha256(restored) != token_sha256(doc.text(pinned)):
        _fail(_MESSAGE)
