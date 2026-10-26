# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Check the live lane-refinement inventory.

Fourteen reviewed spans restore the cache-key successor. Three cache-key
edits restore the predecessor. That predecessor keeps the pinned use digest.
"""

from std.pathlib import Path

from tools._python_json import PY_STR, PyJson
from tools._sha256 import sha256_hex
from tools._sum2_guard_inventory import _digest


comptime _PINS = "tools/carla_lane_oracle/sum2-guard-pins.json"
comptime _MIGRATION = "tools/carla_lane_oracle/cache-key-migration.json"
comptime _LANE = "extensions/carla/lane_refinement.mojo"
comptime _MIGRATION_SHA = (
    "06f0aefb02a1f897563f4e7d25e0a26f3fc56f1bef5f3fcb8eb68b5cd1188d5b"
)
comptime _SPANS = 14
comptime _MESSAGE = (
    "global protected-helper use/import inventory changed: lane_refinement"
)

comptime _LIVE_0 = (
    "from extensions.carla.curve_rounded_line import _rounded_line_axis_c"
    "ontext\nfrom extensions.carla.polynomial import CubicPolynomial\nfro"
    "m extensions.carla.road import Road\nfrom extensions.carla.road_info"
    " import _info_index_si as info_index\nfrom math.vector3 import Vecto"
    "r3\nfrom std.math import inf, isfinite, sqrt\nfrom std.memory import"
    " bitcast\nfrom std.utils import Variant\n\n\ndef _legacy_square(\n"
)

comptime _OLD_0 = (
    "from extensions.carla.curve_rounded_line import _rounded_line_axis_c"
    "ontext\nfrom extensions.carla.polynomial import CubicPolynomial\nfro"
    "m extensions.carla.road import Road\nfrom extensions.carla.road_info"
    " import info_index\nfrom math.vector3 import Vector3\nfrom std.math "
    "import inf, isfinite, sqrt\nfrom std.memory import bitcast\n\n\ndef "
    "_legacy_square(\n"
)

comptime _LIVE_1 = (
    "    # An inverse is a seed only. A hit of the actual stored coordina"
    "te is\n    # the exact minimum because the proof fixes both other co"
    "ordinates.\n    var seed = lo + (query[axis] - left[axis]) / model.s"
    "lope\n    # The accepted rounded context bounds coordinates and nonz"
    "ero slope\n    # to 2^-400..2^400. This inverse cannot overflow Floa"
    "t64.\n    seed = min(max(seed, lo), hi)\n    var seed_point = _check"
    "ed_center(\n        road, section, lane, seed, terms, max_terms\n   "
    " )\n    if seed_point[axis] == query[axis]:\n        return (\n     "
    "       seed,\n            _legacy_square(seed_point, query),\n      "
    "      seed_point^,\n            nodes,\n            terms,\n        "
    ")\n    if direction * seed_point[axis] < target:\n        lo = seed"
    "\n        left = seed_point^\n    else:\n        hi = seed\n        "
    "right = seed_point^\n    var lo_bits = bitcast[DType.uint64](lo)\n  "
    "  var hi_bits = bitcast[DType.uint64](hi)\n    while hi_bits - lo_bi"
    "ts > UInt64(1):\n"
)

comptime _OLD_1 = (
    "    # An inverse is a seed only. A hit of the actual stored coordina"
    "te is\n    # the exact minimum because the proof fixes both other co"
    "ordinates.\n    var seed = lo + (query[axis] - left[axis]) / model.s"
    "lope\n    if isfinite(seed):\n        seed = min(max(seed, lo), hi)"
    "\n        var point = _checked_center(road, section, lane, seed, ter"
    "ms, max_terms)\n        if point[axis] == query[axis]:\n            "
    "return (seed, _legacy_square(point, query), point^, nodes, terms)\n "
    "       if direction * point[axis] < target:\n            lo = seed\n"
    "            left = point^\n        else:\n            hi = seed\n   "
    "         right = point^\n    var lo_bits = bitcast[DType.uint64](lo)"
    "\n    var hi_bits = bitcast[DType.uint64](hi)\n    while hi_bits - l"
    "o_bits > UInt64(1):\n"
)

comptime _LIVE_2 = (
    ") raises -> Float64:\n    # The spatial target is unchanged. Divisio"
    "n precedes the square.\n    var spatial_scale = high - low\n    var "
    "width = abs(road._lane_width_si(section, lane, best))\n    if width "
    "> 0.0:\n        spatial_scale = min(spatial_scale, width)\n    var s"
    "patial = (\n"
)

comptime _OLD_2 = (
    ") raises -> Float64:\n    # The spatial target is unchanged. Divisio"
    "n precedes the square.\n    var spatial_scale = high - low\n    var "
    "width = abs(road.lane_width(section, lane, best))\n    if width > 0."
    "0:\n        spatial_scale = min(spatial_scale, width)\n    var spati"
    "al = (\n"
)

comptime _LIVE_3 = (
    "        return _wide_plan_contains(\n            certificate.point,"
    "\n            query,\n            road._lane_width_si(section, lane,"
    " certificate.s),\n        )\n    if len(certificate.cells) == 0:\n  "
    '      raise Error("Lane classification needs possible minimizing ce'
    'lls")\n'
)

comptime _OLD_3 = (
    "        return _wide_plan_contains(\n            certificate.point,"
    "\n            query,\n            road.lane_width(section, lane, cer"
    "tificate.s),\n        )\n    if len(certificate.cells) == 0:\n      "
    '  raise Error("Lane classification needs possible minimizing cells'
    '")\n'
)

comptime _LIVE_4 = (
    "    # The approximate returned waypoint must agree with every possib"
    "le\n    # minimizing cell. Cell consensus alone does not classify th"
    "is sample.\n    var result = _wide_plan_contains(\n        certifica"
    "te.point,\n        query,\n        road._lane_width_si(section, lane"
    ", certificate.s),\n    )\n    if len(certificate.cells) > max_nodes "
    '- certificate.nodes:\n        raise Error("Lane classification exha'
    'usted its interval work limit")\n'
)

comptime _OLD_4 = (
    "    # The approximate returned waypoint must agree with every possib"
    "le\n    # minimizing cell. Cell consensus alone does not classify th"
    "is sample.\n    var result = _wide_plan_contains(\n        certifica"
    "te.point, query, road.lane_width(section, lane, certificate.s)\n    "
    ")\n    if len(certificate.cells) > max_nodes - certificate.nodes:\n "
    '       raise Error("Lane classification exhausted its interval work'
    ' limit")\n'
)

comptime _LIVE_5 = (
    "                road, section, lane, cell.low, certificate.terms, ma"
    "x_terms\n            )\n            resolved = _wide_plan_contains("
    "\n                point, query, road._lane_width_si(section, lane, c"
    "ell.low)\n            )\n        else:\n            var work = _refe"
    "rence_work(road, cell.low, cell.high)\n"
)

comptime _OLD_5 = (
    "                road, section, lane, cell.low, certificate.terms, ma"
    "x_terms\n            )\n            resolved = _wide_plan_contains("
    "\n                point, query, road.lane_width(section, lane, cell."
    "low)\n            )\n        else:\n            var work = _referenc"
    "e_work(road, cell.low, cell.high)\n"
)

comptime _LIVE_6 = (
    "    )\n\n\n@fieldwise_init\nstruct _LaneExpansionContext(Copyable, M"
    "ovable):\n    # One search invocation only. The Road argument must r"
    "emain unchanged.\n    # Exact station/scale words are meaningful onl"
    "y for this owner and query.\n    var section: Int\n    var lane: Int"
    "\n    var root: _Interval\n    var location: Vector3\n    var spiral"
    "_proof: Optional[_SpiralDomainProof]\n    var frozen: Optional[_Roun"
    "dedArc]\n    var external_witness: Optional[Array[Float64, 3]]\n    "
    "var cached_fast: Optional[Tuple[UInt64, UInt64, _Jet]]\n    var cach"
    "ed_expansion: Optional[Tuple[UInt64, UInt64, _Jet]]\n\n\n@fieldwise_"
    "init\nstruct _LaneBoundPolicy(ImplicitlyCopyable):\n    # Already-co"
    "mputed stopping criteria for this cell and incumbent.\n    var upper"
    ": Float64\n    var scale: Float64\n    var tolerance: Float64\n    v"
    "ar goal: Optional[_LaneExclusionGoal]\n\n\n@fieldwise_init\nstruct _"
    "LaneBoundDiscard(ImplicitlyCopyable):\n    var lower: Float64\n    v"
    "ar support: _Interval\n\n\n@fieldwise_init\nstruct _LaneBoundClose(I"
    "mplicitlyCopyable):\n    var lower: Float64\n    var support: _Inter"
    "val\n\n\n@fieldwise_init\nstruct _LaneBoundContract(ImplicitlyCopyab"
    "le):\n    var lower: Float64\n    var support: _Interval\n\n\n# Name"
    "d alternatives carry the exact bound/support from their decision sit"
    "e.\n# No numeric tag protocol or re-evaluation of acceptance in the "
    "caller.\ncomptime _LaneBoundProposal = Variant[\n    _LaneBoundDisca"
    "rd, _LaneBoundClose, _LaneBoundContract\n]\n\n\ndef _try_lane_center"
    "_bound(\n    road: Road,\n    mut context: _LaneExpansionContext,\n "
    "   cell: _Interval,\n    best: Float64,\n    var domain: _Jet,\n    "
    "var natural: Float64,\n    whole_work: Int,\n    policy: _LaneBoundP"
    "olicy,\n    mut nodes: Int,\n    mut terms: Int,\n    max_nodes: Int"
    ",\n    max_terms: Int,\n) raises -> Optional[_LaneBoundProposal]:\n "
    "   # The caller supplies a real incumbent and the already-paid whole"
    "-cell\n    # enclosure. An unknown enclosure is valid. This optional"
    " phase owns no\n    # traversal state. None retains all work/cache e"
    "ffects of an inconclusive\n    # admitted attempt; count refusal ret"
    "urns before either kind of effect.\n    # A clamped singleton endpoi"
    "nt can have a different jet from\n    # the interior branch. Taylor "
    "bounds need that same branch.\n    var center_s = _expansion_center("
    "cell.low, cell.high, best)\n    var center_work = _reference_work(ro"
    "ad, center_s, center_s)\n    if center_work >= 0:\n        if terms "
    '> max_terms - center_work:\n            raise Error("Lane refinemen'
    't exhausted its quadrature work limit")\n        terms += center_wo'
    "rk\n        var fast_center: Optional[_Jet] = None\n        # The or"
    "iginal full-domain second derivative and scalar\n        # error als"
    "o apply to this ideal moment-backed expansion.\n        # Retain hea"
    "droom for the unchanged translated fallback.\n        if (\n        "
    "    context.spiral_proof\n            and domain.second.is_finite()"
    "\n            and center_work <= max_terms - terms\n        ):\n    "
    "        var station_word = bitcast[DType.uint64](center_s)\n        "
    "    var scale_word = bitcast[DType.uint64](policy.scale)\n          "
    "  if (\n                context.external_witness\n                an"
    "d context.cached_fast\n                and _same_cache_key(\n       "
    "             context.cached_fast.value()[0],\n                    co"
    "ntext.cached_fast.value()[1],\n                    station_word,\n  "
    "                  scale_word,\n                )\n            ):\n  "
    "              fast_center = context.cached_fast.value()[2]\n        "
    "    else:\n                fast_center = _try_proof_expansion_jet(\n"
    "                    road,\n                    context.section,\n   "
    "                 context.lane,\n                    center_s,\n     "
    "               context.location,\n                    policy.scale,"
    "\n                    context.root.low,\n                    context"
    ".root.high,\n                    context.spiral_proof,\n            "
    "    )\n                if context.external_witness and fast_center:"
    "\n                    context.cached_fast = (\n                     "
    "   station_word,\n                        scale_word,\n             "
    "           fast_center.value(),\n                    )\n            "
    "if fast_center:\n                var fast_delta = _Interval(\n      "
    "              cell.low, cell.high\n                ) - _Interval.poi"
    "nt(center_s)\n                var fast_lower = max(\n               "
    "     natural,\n                    _global_lower(domain, fast_center"
    ".value(), fast_delta),\n                )\n                if fast_l"
    "ower > policy.upper:\n                    return _LaneBoundProposal("
    "\n                        _LaneBoundDiscard(fast_lower, cell)\n     "
    "               )\n                if (\n                    _goal_ex"
    "cludes(fast_lower, policy.scale, policy.goal)\n                    o"
    "r _next_up(policy.upper - fast_lower) <= policy.tolerance\n         "
    "       ):\n                    return _LaneBoundProposal(_LaneBoundC"
    "lose(fast_lower, cell))\n                # A failed optional attempt"
    " is charged before the\n                # original traversal; neithe"
    "r work cap is enlarged.\n                terms += center_work\n     "
    "   # Only a failed cached proof needs the expensive local GL\n      "
    "  # error traversal. It is still charged before execution.\n        "
    "if context.spiral_proof and domain.error > policy.tolerance * 0.25:"
    "\n            if terms > max_terms - whole_work:\n                ra"
    'ise Error(\n                    "Lane refinement exhausted its quad'
    'rature work limit"\n                )\n            terms += whole_w'
    "ork\n            # Original F is prepaid; the optional model owns it"
    "s node\n            # and whole-union C. A decline retains all actua"
    "l debits.\n            var grouped: Optional[Tuple[_Jet, _Jet, _Jet]"
    "] = None\n            # Keep the original closed-cell recheck availa"
    "ble after\n            # this optional producer. The original F is a"
    "lready paid.\n            if max_nodes - nodes >= 2:\n              "
    "  grouped = _try_grouped_lane_jet(\n                    road,\n     "
    "               context.section,\n                    context.lane,\n"
    "                    cell.low,\n                    cell.high,\n     "
    "               nodes,\n                    terms,\n                 "
    "   max_nodes,\n                    max_terms,\n                )\n  "
    "          var point_domain: Tuple[_Jet, _Jet, _Jet]\n            if "
    "grouped:\n                point_domain = grouped.value()\n          "
    "  else:\n                point_domain = _lane_jet(\n                "
    "    road, context.section, context.lane, cell.low, cell.high\n      "
    "          )\n            natural = max(\n                natural,\n "
    "               _scaled_point_distance_box(\n                    poin"
    "t_domain, context.location, policy.scale\n                ).low,\n  "
    "          )\n            if natural > policy.upper:\n               "
    " return _LaneBoundProposal(_LaneBoundDiscard(natural, cell))\n      "
    "      if _goal_excludes(natural, policy.scale, policy.goal):\n      "
    "          return _LaneBoundProposal(_LaneBoundClose(natural, cell))"
    "\n            domain = _scaled_point_distance_jet(\n                "
    "point_domain, context.location, policy.scale\n            )\n       "
    "     if fast_center:\n                var tightened_delta = _Interva"
    "l(\n                    cell.low, cell.high\n                ) - _In"
    "terval.point(center_s)\n                var tightened_lower = max(\n"
    "                    natural,\n                    _global_lower(doma"
    "in, fast_center.value(), tightened_delta),\n                )\n     "
    "           if tightened_lower > policy.upper:\n                    r"
    "eturn _LaneBoundProposal(\n                        _LaneBoundDiscard"
    "(tightened_lower, cell)\n                    )\n                if ("
    "\n                    _goal_excludes(tightened_lower, policy.scale, "
    "policy.goal)\n                    or _next_up(policy.upper - tighten"
    "ed_lower)\n                    <= policy.tolerance\n                "
    "):\n                    return _LaneBoundProposal(\n                "
    "        _LaneBoundClose(tightened_lower, cell)\n                    "
    ")\n        # A nonfinite second derivative makes _global_lower ignor"
    "e\n        # its expansion argument. A finite rounded domain value a"
    "lso\n        # establishes that this is an evaluated expression encl"
    "osure,\n        # rather than an unvalidated whole/unknown record do"
    "main.\n        # Retain the original work reservation above. Only sk"
    "ip the\n        # unused traversal; no bound, tolerance, or cap chan"
    "ges.\n        var center = _Jet.constant(0.0)\n        if domain.sec"
    "ond.is_finite() or not domain.rounded_value().is_finite():\n        "
    "    var station_word = bitcast[DType.uint64](center_s)\n            "
    "var scale_word = bitcast[DType.uint64](policy.scale)\n            if"
    " (\n                context.external_witness\n                and co"
    "ntext.cached_expansion\n                and _same_cache_key(\n      "
    "              context.cached_expansion.value()[0],\n                "
    "    context.cached_expansion.value()[1],\n                    statio"
    "n_word,\n                    scale_word,\n                )\n       "
    "     ):\n                center = context.cached_expansion.value()[2"
    "]\n            else:\n                if context.frozen:\n          "
    "          center = _frozen_arc_expansion(\n                        c"
    "ontext.frozen.value(),\n                        center_s,\n         "
    "               context.location,\n                        policy.sca"
    "le,\n                    )\n                else:\n                 "
    "   center = _expansion_distance_jet(\n                        road,"
    "\n                        context.section,\n                        "
    "context.lane,\n                        center_s,\n                  "
    "      context.location,\n                        policy.scale,\n    "
    "                )\n                if context.external_witness:\n   "
    "                 context.cached_expansion = (\n                     "
    "   station_word,\n                        scale_word,\n             "
    "           center,\n                    )\n        var delta = _Inte"
    "rval(cell.low, cell.high) - _Interval.point(center_s)\n        var l"
    "ower = max(natural, _global_lower(domain, center, delta))\n        v"
    "ar support = _Interval(cell.low, cell.high)\n        if context.exte"
    "rnal_witness:\n            support = _minimizer_support(\n          "
    "      domain, center, center_s, best, cell.low, cell.high\n         "
    "   )\n        if lower > policy.upper:\n            return _LaneBoun"
    "dProposal(_LaneBoundDiscard(lower, support))\n        if (\n        "
    "    _goal_excludes(lower, policy.scale, policy.goal)\n            or"
    " _next_up(policy.upper - lower) <= policy.tolerance\n        ):\n   "
    "         return _LaneBoundProposal(_LaneBoundClose(lower, support))"
    "\n        if support.low > cell.low or support.high < cell.high:\n  "
    "          return _LaneBoundProposal(_LaneBoundContract(lower, suppor"
    "t))\n    return None\n\n\ndef _run_lane_search(\n    road: Road,\n  "
    "  section: Int,\n"
)

comptime _OLD_6 = (
    "    )\n\n\ndef _run_lane_search(\n    road: Road,\n    section: Int,\n"
)

comptime _LIVE_7 = (
    "    # Exact station/scale words retain branch and normalization iden"
    "tity.\n    var sampled_checked = False\n    var sampled_cuts: Option"
    "al[Tuple[Float64, Float64, Int]] = None\n    var best = certificate."
    "s\n    var best_point = certificate.point.copy()\n    var query: Arr"
    "ay[Float64, 3] = [\n"
)

comptime _OLD_7 = (
    "    # Exact station/scale words retain branch and normalization iden"
    "tity.\n    var sampled_checked = False\n    var sampled_cuts: Option"
    "al[Tuple[Float64, Float64, Int]] = None\n    var cached_fast: Option"
    "al[Tuple[UInt64, UInt64, _Jet]] = None\n    var cached_expansion: Op"
    "tional[Tuple[UInt64, UInt64, _Jet]] = None\n    var best = certifica"
    "te.s\n    var best_point = certificate.point.copy()\n    var query: "
    "Array[Float64, 3] = [\n"
)

comptime _LIVE_8 = (
    "        certificate.nodes += 1\n        certificate.terms += 1\n    "
    "    frozen = _frozen_arc_context(road, section, lane, low, high)\n  "
    "  var expansion_context = _LaneExpansionContext(\n        section,\n"
    "        lane,\n        _Interval(low, high),\n        location,\n   "
    "     spiral_proof,\n        frozen,\n        external_witness.copy()"
    ",\n        None,\n        None,\n    )\n    while len(pending) > 0 o"
    "r closed.needs_validation():\n        if certificate.nodes >= max_no"
    'des:\n            raise Error("Lane refinement exhausted its interv'
    'al work limit")\n'
)

comptime _OLD_8 = (
    "        certificate.nodes += 1\n        certificate.terms += 1\n    "
    "    frozen = _frozen_arc_context(road, section, lane, low, high)\n  "
    "  while len(pending) > 0 or closed.needs_validation():\n        if c"
    'ertificate.nodes >= max_nodes:\n            raise Error("Lane refin'
    'ement exhausted its interval work limit")\n'
)

comptime _LIVE_9 = (
    "            var domain = _scaled_point_distance_jet(\n              "
    "  point_domain, location, scale\n            )\n            # Admit "
    "finite interpolation width before the derivative tests.\n           "
    " # All three predicates are retained. The earlier midpoint already\n"
    "            # evaluated this same subtraction, including an overflow"
    "ing span.\n            if (\n                isfinite(hi - lo)\n    "
    "            and domain.second.low > 0.0\n                and domain."
    "first.contains(0.0)\n            ):\n                var local = _lo"
    "cal_seed(\n                    road,\n"
)

comptime _OLD_9 = (
    "            var domain = _scaled_point_distance_jet(\n              "
    "  point_domain, location, scale\n            )\n            if (\n  "
    "              domain.second.low > 0.0\n                and domain.fi"
    "rst.contains(0.0)\n                and isfinite(hi - lo)\n          "
    "  ):\n                var local = _local_seed(\n                    "
    "road,\n"
)

comptime _LIVE_10 = (
    "                natural = _scaled_point_distance_box(\n             "
    "       point_domain, location, scale\n                ).low\n       "
    "         # An unchanged seed repeats the admitted bound exactly.\n  "
    "              # An improved seed is an actual in-cell witness, so it"
    "s\n                # upper distance cannot fall below this natural e"
    "nclosure.\n                if _goal_excludes(natural, scale, goal):"
    "\n                    closed.add(_ClosedInterval(lo, hi, task[2], na"
    "tural, scale))\n                    continue\n"
)

comptime _OLD_10 = (
    "                natural = _scaled_point_distance_box(\n             "
    "       point_domain, location, scale\n                ).low\n       "
    "         if natural > best_upper:\n                    continue\n   "
    "             if _goal_excludes(natural, scale, goal):\n             "
    "       closed.add(_ClosedInterval(lo, hi, task[2], natural, scale))"
    "\n                    continue\n"
)

comptime _LIVE_11 = (
    "                scale,\n                requested_gap,\n            "
    ")\n            var proposal = _try_lane_center_bound(\n             "
    "   road,\n                expansion_context,\n                _Inter"
    "val(lo, hi),\n                best,\n                domain,\n      "
    "          natural,\n                work,\n                _LaneBoun"
    "dPolicy(best_upper, scale, tolerance, goal),\n                certif"
    "icate.nodes,\n                certificate.terms,\n                ma"
    "x_nodes,\n                max_terms,\n            )\n            if "
    "proposal:\n                ref bound = proposal.value()\n           "
    "     if bound.isa[_LaneBoundDiscard]():\n                    continu"
    "e\n                if bound.isa[_LaneBoundClose]():\n               "
    "     var close = bound[_LaneBoundClose]\n                    closed."
    "add(\n                        _ClosedInterval(\n                    "
    "        close.support.low,\n                            close.suppor"
    "t.high,\n                            task[2],\n                     "
    "       close.lower,\n                            scale,\n           "
    "             )\n                    )\n                    continue"
    "\n                var support = bound[_LaneBoundContract].support\n "
    "               if task[2] >= max_depth:\n                    raise E"
    'rror(\n                        "Lane refinement exhausted its numer'
    'ical accuracy limit"\n                    )\n                pendin'
    "g.append((support.low, support.high, task[2] + 1))\n                "
    "continue\n        if task[2] >= max_depth:\n            raise Error("
    '\n                "Lane refinement exhausted its numerical accuracy'
    ' limit"\n'
)

comptime _OLD_11 = (
    "                scale,\n                requested_gap,\n            "
    ")\n            # A clamped singleton endpoint can have a different j"
    "et from\n            # the interior branch. Taylor bounds need that "
    "same branch.\n            var center_s = _expansion_center(lo, hi, b"
    "est)\n            var center_work = _reference_work(road, center_s, "
    "center_s)\n            if center_work >= 0:\n                if cert"
    "ificate.terms > max_terms - center_work:\n                    raise "
    'Error(\n                        "Lane refinement exhausted its quad'
    'rature work limit"\n                    )\n                certific'
    "ate.terms += center_work\n                var fast_center: Optional["
    "_Jet] = None\n                # The original full-domain second deri"
    "vative and scalar\n                # error also apply to this ideal "
    "moment-backed expansion.\n                # Retain headroom for the "
    "unchanged translated fallback.\n                if (\n              "
    "      spiral_proof\n                    and domain.second.is_finite("
    ")\n                    and center_work <= max_terms - certificate.te"
    "rms\n                ):\n                    var station_word = bitc"
    "ast[DType.uint64](center_s)\n                    var scale_word = bi"
    "tcast[DType.uint64](scale)\n                    if (\n              "
    "          external_witness\n                        and cached_fast"
    "\n                        and _same_cache_key(\n                    "
    "        cached_fast.value()[0],\n                            cached_"
    "fast.value()[1],\n                            station_word,\n       "
    "                     scale_word,\n                        )\n       "
    "             ):\n                        fast_center = cached_fast.v"
    "alue()[2]\n                    else:\n                        fast_c"
    "enter = _try_proof_expansion_jet(\n                            road,"
    "\n                            section,\n                            "
    "lane,\n                            center_s,\n                      "
    "      location,\n                            scale,\n               "
    "             low,\n                            high,\n              "
    "              spiral_proof,\n                        )\n            "
    "            if external_witness and fast_center:\n                  "
    "          cached_fast = (\n                                station_w"
    "ord,\n                                scale_word,\n                 "
    "               fast_center.value(),\n                            )\n"
    "                    if fast_center:\n                        var fas"
    "t_delta = _Interval(lo, hi) - _Interval.point(\n                    "
    "        center_s\n                        )\n                       "
    " var fast_lower = max(\n                            natural,\n      "
    "                      _global_lower(\n                              "
    "  domain, fast_center.value(), fast_delta\n                         "
    "   ),\n                        )\n                        if fast_lo"
    "wer > best_upper:\n                            continue\n           "
    "             if (\n                            _goal_excludes(fast_l"
    "ower, scale, goal)\n                            or _next_up(best_upp"
    "er - fast_lower) <= tolerance\n                        ):\n         "
    "                   closed.add(\n                                _Clo"
    "sedInterval(\n                                    lo, hi, task[2], f"
    "ast_lower, scale\n                                )\n               "
    "             )\n                            continue\n              "
    "          # A failed optional attempt is charged before the\n       "
    "                 # original traversal; neither work cap is enlarged."
    "\n                        certificate.terms += center_work\n        "
    "        # Only a failed cached proof needs the expensive local GL\n "
    "               # error traversal. It is still charged before executi"
    "on.\n                if spiral_proof and domain.error > tolerance * "
    "0.25:\n                    if certificate.terms > max_terms - work:"
    "\n                        raise Error(\n                            "
    '"Lane refinement exhausted its quadrature work"\n                 '
    '           " limit"\n                        )\n                  '
    "  certificate.terms += work\n                    # Original F is pre"
    "paid; the optional model owns its node\n                    # and wh"
    "ole-union C. A decline retains all actual debits.\n                 "
    "   var grouped: Optional[Tuple[_Jet, _Jet, _Jet]] = None\n          "
    "          # Keep the original closed-cell recheck available after\n "
    "                   # this optional producer. The original F is alrea"
    "dy paid.\n                    if max_nodes - certificate.nodes >= 2:"
    "\n                        grouped = _try_grouped_lane_jet(\n        "
    "                    road,\n                            section,\n   "
    "                         lane,\n                            lo,\n   "
    "                         hi,\n                            certificat"
    "e.nodes,\n                            certificate.terms,\n          "
    "                  max_nodes,\n                            max_terms,"
    "\n                        )\n                    if grouped:\n      "
    "                  point_domain = grouped.value()\n                  "
    "  else:\n                        point_domain = _lane_jet(road, sect"
    "ion, lane, lo, hi)\n                    natural = max(\n            "
    "            natural,\n                        _scaled_point_distance"
    "_box(\n                            point_domain, location, scale\n  "
    "                      ).low,\n                    )\n               "
    "     if natural > best_upper:\n                        continue\n   "
    "                 if _goal_excludes(natural, scale, goal):\n         "
    "               closed.add(\n                            _ClosedInter"
    "val(lo, hi, task[2], natural, scale)\n                        )\n   "
    "                     continue\n                    domain = _scaled_"
    "point_distance_jet(\n                        point_domain, location,"
    " scale\n                    )\n                    if fast_center:\n"
    "                        var tightened_delta = _Interval(\n          "
    "                  lo, hi\n                        ) - _Interval.poin"
    "t(center_s)\n                        var tightened_lower = max(\n   "
    "                         natural,\n                            _glob"
    "al_lower(\n                                domain, fast_center.value"
    "(), tightened_delta\n                            ),\n               "
    "         )\n                        if tightened_lower > best_upper:"
    "\n                            continue\n                        if ("
    "\n                            _goal_excludes(tightened_lower, scale,"
    " goal)\n                            or _next_up(best_upper - tighten"
    "ed_lower)\n                            <= tolerance\n               "
    "         ):\n                            closed.add(\n              "
    "                  _ClosedInterval(\n                                "
    "    lo, hi, task[2], tightened_lower, scale\n                       "
    "         )\n                            )\n                         "
    "   continue\n                # A nonfinite second derivative makes _"
    "global_lower ignore\n                # its expansion argument. A fin"
    "ite rounded domain value also\n                # establishes that th"
    "is is an evaluated expression enclosure,\n                # rather t"
    "han an unvalidated whole/unknown record domain.\n                # R"
    "etain the original work reservation above. Only skip the\n          "
    "      # unused traversal; no bound, tolerance, or cap changes.\n    "
    "            var center = _Jet.constant(0.0)\n                if (\n "
    "                   domain.second.is_finite()\n                    or"
    " not domain.rounded_value().is_finite()\n                ):\n       "
    "             var station_word = bitcast[DType.uint64](center_s)\n   "
    "                 var scale_word = bitcast[DType.uint64](scale)\n    "
    "                if (\n                        external_witness\n    "
    "                    and cached_expansion\n                        an"
    "d _same_cache_key(\n                            cached_expansion.val"
    "ue()[0],\n                            cached_expansion.value()[1],\n"
    "                            station_word,\n                         "
    "   scale_word,\n                        )\n                    ):\n "
    "                       center = cached_expansion.value()[2]\n       "
    "             else:\n                        if frozen:\n            "
    "                center = _frozen_arc_expansion(\n                   "
    "             frozen.value(), center_s, location, scale\n            "
    "                )\n                        else:\n                  "
    "          center = _expansion_distance_jet(\n                       "
    "         road, section, lane, center_s, location, scale\n           "
    "                 )\n                        if external_witness:\n  "
    "                          cached_expansion = (\n                    "
    "            station_word,\n                                scale_wor"
    "d,\n                                center,\n                       "
    "     )\n                var delta = _Interval(lo, hi) - _Interval.po"
    "int(center_s)\n                var lower = max(natural, _global_lowe"
    "r(domain, center, delta))\n                var support = _Interval(l"
    "o, hi)\n                if external_witness:\n                    su"
    "pport = _minimizer_support(\n                        domain, center,"
    " center_s, best, lo, hi\n                    )\n                if l"
    "ower > best_upper:\n                    continue\n                if"
    " (\n                    _goal_excludes(lower, scale, goal)\n        "
    "            or _next_up(best_upper - lower) <= tolerance\n          "
    "      ):\n                    closed.add(\n                        _"
    "ClosedInterval(\n                            support.low, support.hi"
    "gh, task[2], lower, scale\n                        )\n              "
    "      )\n                    continue\n                if support.lo"
    "w > lo or support.high < hi:\n                    if task[2] >= max_"
    "depth:\n                        raise Error(\n                      "
    '      "Lane refinement exhausted its numerical accuracy"\n        '
    '                    " limit"\n                        )\n         '
    "           pending.append((support.low, support.high, task[2] + 1))"
    "\n                    continue\n        if task[2] >= max_depth:\n  "
    '          raise Error(\n                "Lane refinement exhausted '
    'its numerical accuracy limit"\n'
)

comptime _LIVE_12 = (
    "        max(Float64(start.z), Float64(end.z)),\n    )\n    var natur"
    "al = _length_up(x.magnitude(), y.magnitude(), z.magnitude())\n    # "
    "Endpoint admission and a finite second derivative are independent\n "
    "   # requirements for the optional smooth certificate. Check the cou"
    "nts\n    # first, including when the original coarse box is already "
    "unbounded.\n    # Either refusal retains the same natural bound and "
    "spent-work ledger.\n    var first_work = _reference_work(road, low, "
    "low)\n    var last_work = _reference_work(road, high, high)\n    if "
    "first_work < 0 or last_work < 0:\n        return (natural, box, spen"
    "t)\n    var derivative = _length_up(\n        point[0].second.magnit"
    "ude(),\n        point[1].second.magnitude(),\n"
)

comptime _OLD_12 = (
    "        max(Float64(start.z), Float64(end.z)),\n    )\n    var natur"
    "al = _length_up(x.magnitude(), y.magnitude(), z.magnitude())\n    va"
    "r derivative = _length_up(\n        point[0].second.magnitude(),\n  "
    "      point[1].second.magnitude(),\n"
)

comptime _LIVE_13 = (
    "    )\n    if not isfinite(derivative):\n        return (natural, bo"
    "x, spent)\n    if first_work > max_terms - spent:\n        return (n"
    "atural, box, spent)\n    if last_work > max_terms - spent - first_wo"
    "rk:\n"
)

comptime _OLD_13 = (
    "    )\n    if not isfinite(derivative):\n        return (natural, bo"
    "x, spent)\n    var first_work = _reference_work(road, low, low)\n   "
    " var last_work = _reference_work(road, high, high)\n    if first_wor"
    "k < 0 or last_work < 0:\n        return (natural, box, spent)\n    i"
    "f first_work > max_terms - spent:\n        return (natural, box, spe"
    "nt)\n    if last_work > max_terms - spent - first_work:\n"
)


def _live(index: Int) -> String:
    """Return one live lane-refinement span.

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
    if index == 10:
        return _LIVE_10
    if index == 11:
        return _LIVE_11
    if index == 12:
        return _LIVE_12
    return _LIVE_13


def _old(index: Int) -> String:
    """Return one successor lane-refinement span.

    Args:
        index: The span number.

    Returns:
        The successor text.
    """
    if index == 0:
        return _OLD_0
    if index == 1:
        return _OLD_1
    if index == 2:
        return _OLD_2
    if index == 3:
        return _OLD_3
    if index == 4:
        return _OLD_4
    if index == 5:
        return _OLD_5
    if index == 6:
        return _OLD_6
    if index == 7:
        return _OLD_7
    if index == 8:
        return _OLD_8
    if index == 9:
        return _OLD_9
    if index == 10:
        return _OLD_10
    if index == 11:
        return _OLD_11
    if index == 12:
        return _OLD_12
    return _OLD_13


def _fail(message: String) raises:
    """Raise a lane-inventory error.

    Args:
        message: The failure text.

    Raises:
        Error: The live lane-refinement inventory changed.
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


def _restore(source: String) raises -> String:
    """Restore the cache-key successor.

    Args:
        source: The live lane-refinement module.

    Returns:
        The successor source.

    Raises:
        Error: A reviewed span moved.
    """
    var current = source
    var index = 0
    while index < _SPANS:
        var span = _live(index)
        if _count(current, span) != 1:
            _fail(_MESSAGE)
        current = current.replace(span, _old(index))
        index += 1
    return current


def _edits(doc: PyJson, record: Int, source: String) raises -> String:
    """Apply the three cache-key edits.

    Args:
        doc: The migration document.
        record: The migration object.
        source: The cache-key successor.

    Returns:
        The predecessor source.

    Raises:
        Error: An edit field is missing.
    """
    var edits = doc.at(record, "edits")
    var current = source
    var index = 0
    while index < 3:
        var edit = doc.item(edits, index)
        var fragment = doc.text(doc.at(edit, "after"))
        var prior = doc.text(doc.at(edit, "before"))
        current = current.replace(fragment, prior)
        index += 1
    return current


def sum2_lane_inventory(root: String) raises:
    """Require the live lane-refinement inventory.

    Args:
        root: The repository root.

    Raises:
        Error: A reviewed span, edit, or pinned use digest changed.
    """
    var base = root
    if base.byte_length() > 1 and base.endswith("/"):
        var end = base.byte_length() - 1
        var trimmed = String(base[byte=0:end])
        base = trimmed
    var migration = base + "/" + _MIGRATION
    if sha256_hex(Path(migration).read_bytes()) != _MIGRATION_SHA:
        _fail("migration record changed")
    var mig = PyJson.parse(Path(migration).read_text())
    var successor = doc_text(mig)
    var restored = _restore(Path(base + "/" + _LANE).read_text())
    if restored != successor:
        _fail(_MESSAGE)
    var predecessor = _edits(mig, mig.root, restored)
    var pins = PyJson.parse(Path(base + "/" + _PINS).read_text())
    var inventory = pins.at(pins.root, "protected_inventory")
    var pinned = pins.at(inventory, _LANE)
    if pins.kind(pinned) != PY_STR or _digest(predecessor) != pins.text(pinned):
        _fail(_MESSAGE)


def doc_text(doc: PyJson) raises -> String:
    """Return the migration successor text.

    Args:
        doc: The migration document.

    Returns:
        The successor source.

    Raises:
        Error: The successor field is missing.
    """
    return doc.text(doc.at(doc.root, "after"))
