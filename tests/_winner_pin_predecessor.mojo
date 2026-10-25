# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Restore reviewed winner pins from the live consumer files."""

from std.pathlib import Path

from tools._sha256 import sha256_hex


def _split(text: String) -> List[String]:
    """Split `text` into lines that keep their newlines.

    Args:
        text: The source.

    Returns:
        Each line, including an unfinished last line.
    """
    var lines = List[String]()
    if text.byte_length() == 0:
        return lines^
    var rest = text
    while True:
        var at = rest.find("\n")
        if at < 0:
            lines.append(rest)
            return lines^
        var line = String(rest[byte = : at + 1])
        var tail = String(rest[byte = at + 1 :])
        lines.append(line)
        rest = tail


def _join(lines: List[String]) -> String:
    """Join lines that already carry their separators.

    Args:
        lines: The lines.

    Returns:
        The source.
    """
    var text = String()
    for line in lines:
        text += line
    return text


def _apply(
    text: String,
    starts: List[Int],
    stops: List[Int],
    befores: List[String],
) -> String:
    """Replace each span with its predecessor lines.

    Args:
        text: The source.
        starts: The 0-based start lines, highest line first.
        stops: The exclusive end lines.
        befores: The predecessor lines for each span.

    Returns:
        The source with those spans replaced.
    """
    var lines = _split(text)
    for index in range(len(starts)):
        var start = starts[index]
        var stop = stops[index]
        var before = _split(befores[index])
        var next = List[String]()
        for slot in range(start):
            next.append(lines[slot])
        for line in before:
            next.append(line)
        for slot in range(stop, len(lines)):
            next.append(lines[slot])
        lines = next^
    return _join(lines)


def _replace_once(
    text: String, before: String, after: String, path: String
) raises -> String:
    """Replace one exact successor span.

    Args:
        text: The source.
        before: The predecessor span.
        after: The successor span.
        path: The consumer path.

    Returns:
        The source with that span replaced.

    Raises:
        Error: The span is missing or repeated.
    """
    var at = text.find(after)
    if at < 0:
        raise Error(
            "winner/sign source contract: unreviewed canonical dependency: "
            + path
        )
    var tail = String(text[byte = at + after.byte_length() :])
    if tail.find(after) >= 0:
        raise Error(
            "winner/sign source contract: unreviewed canonical dependency: "
            + path
        )
    var head = String(text[byte=:at])
    return head + before + tail


def _replace_spans(
    text: String,
    befores: List[String],
    afters: List[String],
    path: String,
) raises -> String:
    """Replace each successor span in table order.

    Args:
        text: The source.
        befores: The predecessor spans.
        afters: The successor spans.
        path: The consumer path.

    Returns:
        The source with those spans replaced.

    Raises:
        Error: A span is missing or repeated.
    """
    var current = text
    for index in range(len(befores)):
        current = _replace_once(current, befores[index], afters[index], path)
    return current


def _require(text: String, expected: String, path: String) raises:
    """Require one file digest.

    Args:
        text: The source.
        expected: The required digest.
        path: The consumer path.

    Raises:
        Error: The digest changed.
    """
    if sha256_hex(text.as_bytes()) != expected:
        raise Error(
            "winner/sign source contract: unreviewed canonical dependency: "
            + path
        )


def _lines_0(
    mut starts: List[Int], mut stops: List[Int], mut befores: List[String]
):
    """Fill one reviewed line-edit table, highest line first.

    Args:
        starts: The 0-based start lines.
        stops: The exclusive end lines.
        befores: The predecessor lines for each span.
    """
    starts.append(1488)
    stops.append(1489)
    befores.append("        scene.add_mesh(mesh^)\n")


def _lines_1(
    mut starts: List[Int], mut stops: List[Int], mut befores: List[String]
):
    """Fill one reviewed line-edit table, highest line first.

    Args:
        starts: The 0-based start lines.
        stops: The exclusive end lines.
        befores: The predecessor lines for each span.
    """
    starts.append(72)
    stops.append(74)
    befores.append(
        "        + local * (_Jet.constant(polynomial.c) + local * _Jet.consta"
        "nt(polynomial.d))\n"
    )
    starts.append(61)
    stops.append(62)
    befores.append("from extensions.carla.road_info import info_index\n")


def _spans_2(mut befores: List[String], mut afters: List[String]):
    """Fill one reviewed span-edit table, last edit first.

    Args:
        befores: The predecessor spans.
        afters: The successor spans.
    """
    befores.append(
        "def _polynomial_jet(\n    polynomial: CubicPolynomial, s: _Jet, shif"
        "t: Float64 = 0.0\n) -> _Jet:\n    return (_Jet.constant(polynomial.a"
        ") - _Jet.constant(shift)) + s * (\n        _Jet.constant(polynomial."
        "b)\n        + s * (_Jet.constant(polynomial.c) + s * _Jet.constant(p"
        "olynomial.d))\n    )\n\n\n"
    )
    afters.append(
        "def _polynomial_jet(\n    polynomial: CubicPolynomial, s: _Jet, shif"
        "t: Float64 = 0.0\n) -> _Jet:\n    var local = s - _Jet.constant(poly"
        "nomial.s)\n    return (_Jet.constant(polynomial.a) - _Jet.constant(s"
        "hift)) + local * (\n        _Jet.constant(polynomial.b)\n        + l"
        "ocal * (_Jet.constant(polynomial.c) + local * _Jet.constant(polynomi"
        "al.d))\n    )\n\n\n"
    )


def _spans_3(mut befores: List[String], mut afters: List[String]):
    """Fill one reviewed span-edit table, last edit first.

    Args:
        befores: The predecessor spans.
        afters: The successor spans.
    """
    befores.append("    if isfinite(coupled_error) and coupled_error >= 0.0:\n")
    afters.append(
        "    # The concrete producer returns a nonnegative allowance or infin"
        "ity.\n    # Keep the finite fallback; a finite negative result is no"
        "t produced.\n    if isfinite(coupled_error):\n"
    )


def _spans_4(mut befores: List[String], mut afters: List[String]):
    """Fill one reviewed span-edit table, last edit first.

    Args:
        befores: The predecessor spans.
        afters: The successor spans.
    """
    befores.append(
        "def _try_lane_envelope_capture(\n    road: Road,\n    section: Int,"
        "\n    lane: Int,\n    low: Float64,\n    high: Float64,\n    mut cap"
        "tured: _SpiralRootCapture,\n    mut terms: Int,\n    max_terms: Int,"
        "\n) raises -> Optional[Tuple[_Jet, _Jet, _Jet]]:\n    # Eligibility "
        "does no GL traversal. Original quadrature work is already\n    # res"
        "erved by the caller. The fixed optional charge covers both count\n  "
        "  # envelopes, moment reconstruction, and the finite proof checks.\n"
        "    if terms < 0 or terms > max_terms or 1024 > max_terms - terms:\n"
        "        return None\n    var at = info_index(road.info.geometries, l"
        "ow)\n    if at < 0 or info_index(road.info.geometries, high) != at:"
        "\n        return None\n    ref geometry = road.info.geometries[at].g"
        "eometry\n    if (\n        geometry.kind != SPIRAL\n        or geome"
        "try.heading != 0.0\n        or geometry.curvature_start != 0.0\n    "
        "):\n        return None\n    var d = _geometry_distance(\n        ge"
        "ometry,\n        _stored_difference(\n            _Jet.variable(low,"
        " high), _Jet.constant(road.info.geometries[at].s)\n        ),\n    )"
        "\n    var counts = _spiral_counts(geometry, d)\n    if (\n        co"
        "unts[0] < 1\n        or counts[1] > 64\n        or counts[1] < count"
        "s[0]\n        or counts[1] - counts[0] > 1\n    ):\n        return N"
        "one\n    var branches = 1 if counts[0] == counts[1] else 2\n    var "
        "optional_work = 1024 * branches\n    if terms < 0 or terms > max_ter"
        "ms or optional_work > max_terms - terms:\n        return None\n    #"
        " Debit before attempting either error envelope, including failures."
        "\n    terms += optional_work\n    var first = _try_spiral_roundoff_e"
        "nvelope(geometry, d, counts[0])\n    if not first:\n        return N"
        "one\n    var last = first\n    if counts[1] != counts[0]:\n        l"
        "ast = _try_spiral_roundoff_envelope(geometry, d, counts[1])\n       "
        " if not last:\n            return None\n    var proof = _SpiralDomai"
        "nProof(\n        0,\n        at,\n        d.rounded_value(),\n      "
        "  counts[0],\n        counts[1],\n        first.value()[0],\n       "
        " first.value()[1],\n        last.value()[0],\n        last.value()[1"
        "],\n    )\n    if not _spiral_proof_matches(\n        proof, geometr"
        "y, at, low, high, low, high, d, counts\n    ):\n        return None"
        "\n    # Use the one canonical lane graph. If a reordered moment bran"
        "ch is\n    # nonfinite, that graph executes the original GL fallback"
        " once under its\n    # existing reservation. Do not run another fall"
        "back after this call.\n    var point = _lane_jet_with_proof(\n      "
        "  road, section, lane, low, high, low, high, proof\n    )\n    captu"
        "red.record_at = at\n    captured.low = low\n    captured.high = high"
        "\n    captured.d = d\n    captured.first_count = counts[0]\n    capt"
        "ured.last_count = counts[1]\n    captured.first_x_error = first.valu"
        "e()[0]\n    captured.first_y_error = first.value()[1]\n    captured."
        "last_x_error = last.value()[0]\n    captured.last_y_error = last.val"
        "ue()[1]\n    return point\n\n\n"
    )
    afters.append(
        "def _try_lane_envelope_capture(\n    road: Road,\n    section: Int,"
        "\n    lane: Int,\n    low: Float64,\n    high: Float64,\n    mut cap"
        "tured: _SpiralRootCapture,\n    mut terms: Int,\n    max_terms: Int,"
        "\n) raises -> Optional[Tuple[_Jet, _Jet, _Jet]]:\n    # Eligibility "
        "does no GL traversal. Original quadrature work is already\n    # res"
        "erved by the caller. The fixed optional charge covers both count\n  "
        "  # envelopes, moment reconstruction, and the finite proof checks.\n"
        "    if terms < 0 or terms > max_terms or 1024 > max_terms - terms:\n"
        "        return None\n    var at = info_index(road.info.geometries, l"
        "ow)\n    if at < 0 or info_index(road.info.geometries, high) != at:"
        "\n        return None\n    ref geometry = road.info.geometries[at].g"
        "eometry\n    if (\n        geometry.kind != SPIRAL\n        or geome"
        "try.heading != 0.0\n        or geometry.curvature_start != 0.0\n    "
        "):\n        return None\n    var d = _geometry_distance(\n        ge"
        "ometry,\n        _stored_difference(\n            _Jet.variable(low,"
        " high), _Jet.constant(road.info.geometries[at].s)\n        ),\n    )"
        "\n    var counts = _spiral_counts(geometry, d)\n    if (\n        co"
        "unts[0] < 1\n        or counts[1] > 64\n        or counts[1] < count"
        "s[0]\n        or counts[1] - counts[0] > 1\n    ):\n        return N"
        "one\n    var branches = 1 if counts[0] == counts[1] else 2\n    var "
        "optional_work = 1024 * branches\n    # The entry check established 0"
        " <= terms <= max_terms. No intervening\n    # operation receives eit"
        "her counter by mutable reference or changes it.\n    if optional_wor"
        "k > max_terms - terms:\n        return None\n    # Debit before atte"
        "mpting either error envelope, including failures.\n    terms += opti"
        "onal_work\n    var first = _try_spiral_roundoff_envelope(geometry, d"
        ", counts[0])\n    if not first:\n        return None\n    var last ="
        " first\n    if counts[1] != counts[0]:\n        last = _try_spiral_r"
        "oundoff_envelope(geometry, d, counts[1])\n        if not last:\n    "
        "        return None\n    var proof = _SpiralDomainProof(\n        0,"
        "\n        at,\n        d.rounded_value(),\n        counts[0],\n     "
        "   counts[1],\n        first.value()[0],\n        first.value()[1],"
        "\n        last.value()[0],\n        last.value()[1],\n    )\n    if "
        "not _spiral_proof_matches(\n        proof, geometry, at, low, high, "
        "low, high, d, counts\n    ):\n        return None\n    # Use the one"
        " canonical lane graph. If a reordered moment branch is\n    # nonfin"
        "ite, that graph executes the original GL fallback once under its\n  "
        "  # existing reservation. Do not run another fallback after this cal"
        "l.\n    var point = _lane_jet_with_proof(\n        road, section, la"
        "ne, low, high, low, high, proof\n    )\n    captured.record_at = at"
        "\n    captured.low = low\n    captured.high = high\n    captured.d ="
        " d\n    captured.first_count = counts[0]\n    captured.last_count = "
        "counts[1]\n    captured.first_x_error = first.value()[0]\n    captur"
        "ed.first_y_error = first.value()[1]\n    captured.last_x_error = las"
        "t.value()[0]\n    captured.last_y_error = last.value()[1]\n    retur"
        "n point\n\n\n"
    )


def _spans_5(mut befores: List[String], mut afters: List[String]):
    """Fill one reviewed span-edit table, last edit first.

    Args:
        befores: The predecessor spans.
        afters: The successor spans.
    """
    befores.append(
        '"""\n\nfrom std.math import inf, isfinite, isnan, sqrt\nfrom std.'
        "memory import bitcast\n\n\ndef _next_up(value: Float64) -> Float64:"
        "\n    # Observe the rounded bits before any following arithmetic. Un"
        "like an\n    # epsilon multiplier, this also handles zero and subnor"
        "mal results.\n    if isnan(value) or value == inf[DType.float64]():"
        "\n        return value\n    if value == 0.0:\n        return bitcast"
        "[DType.float64](UInt64(1))\n    var bits = bitcast[DType.uint64](val"
        "ue)\n    if value < 0.0:\n        return bitcast[DType.float64](bits"
        " - 1)\n    return bitcast[DType.float64](bits + 1)\n\n\ndef _next_do"
        "wn(value: Float64) -> Float64:\n    return -_next_up(-value)\n\n\n"
    )
    afters.append(
        '"""\n\nfrom extensions.carla.curve_interval import _next_down, _n'
        "ext_up\nfrom std.math import inf, isfinite, isnan, sqrt\nfrom std.me"
        "mory import bitcast\n\n\n"
    )


def _lines_6(
    mut starts: List[Int], mut stops: List[Int], mut befores: List[String]
):
    """Fill one reviewed line-edit table, highest line first.

    Args:
        starts: The 0-based start lines.
        stops: The exclusive end lines.
        befores: The predecessor lines for each span.
    """
    starts.append(104)
    stops.append(106)
    befores.append(
        "    # Defensive arithmetic refusal preserves the original conservati"
        "ve cover.\n    if not _ordered_finite(result) or not result.contains"
        "(best):\n        return _Interval(low, high)\n"
    )
    starts.append(99)
    stops.append(100)
    befores.append(
        "            if _ordered_finite(negative) and negative.high >= 0.0:\n"
    )
    starts.append(94)
    stops.append(95)
    befores.append(
        "            if _ordered_finite(positive) and positive.high >= 0.0:\n"
    )
    starts.append(72)
    stops.append(73)
    befores.append(
        "            if _ordered_finite(radius) and radius.high >= 0.0:\n"
    )
    starts.append(67)
    stops.append(68)
    befores.append(
        "            if _ordered_finite(radius) and radius.high >= 0.0:\n"
    )


def _lines_7(
    mut starts: List[Int], mut stops: List[Int], mut befores: List[String]
):
    """Fill one reviewed line-edit table, highest line first.

    Args:
        starts: The 0-based start lines.
        stops: The exclusive end lines.
        befores: The predecessor lines for each span.
    """
    starts.append(847)
    stops.append(848)
    befores.append(
        "                point, query, road.lane_width(section, lane, cell.lo"
        "w)\n"
    )
    starts.append(817)
    stops.append(820)
    befores.append(
        "        certificate.point, query, road.lane_width(section, lane, cer"
        "tificate.s)\n"
    )
    starts.append(803)
    stops.append(804)
    befores.append(
        "            road.lane_width(section, lane, certificate.s),\n"
    )
    starts.append(436)
    stops.append(437)
    befores.append(
        "    var width = abs(road.lane_width(section, lane, best))\n"
    )
    starts.append(65)
    stops.append(66)
    befores.append("from extensions.carla.road_info import info_index\n")


def _spans_8(mut befores: List[String], mut afters: List[String]):
    """Fill one reviewed span-edit table, last edit first.

    Args:
        befores: The predecessor spans.
        afters: The successor spans.
    """
    befores.append(
        "            # A clamped singleton endpoint can have a different jet "
        "from\n            # the interior branch. Taylor bounds need that sam"
        "e branch.\n            var center_s = _expansion_center(lo, hi, best"
        ")\n            var center_work = _reference_work(road, center_s, cen"
        "ter_s)\n            if center_work >= 0:\n                if certifi"
        "cate.terms > max_terms - center_work:\n                    raise Err"
        'or(\n                        "Lane refinement exhausted its quadrat'
        'ure work limit"\n                    )\n                certificate'
        ".terms += center_work\n                var fast_center: Optional[_Je"
        "t] = None\n                # The original full-domain second derivat"
        "ive and scalar\n                # error also apply to this ideal mom"
        "ent-backed expansion.\n                # Retain headroom for the unc"
        "hanged translated fallback.\n                if (\n                 "
        "   spiral_proof\n                    and domain.second.is_finite()\n"
        "                    and center_work <= max_terms - certificate.terms"
        "\n                ):\n                    var station_word = bitcast"
        "[DType.uint64](center_s)\n                    var scale_word = bitca"
        "st[DType.uint64](scale)\n                    if (\n                 "
        "       external_witness\n                        and cached_fast\n  "
        "                      and _same_cache_key(\n                        "
        "    cached_fast.value()[0],\n                            cached_fast"
        ".value()[1],\n                            station_word,\n           "
        "                 scale_word,\n                        )\n           "
        "         ):\n                        fast_center = cached_fast.value"
        "()[2]\n                    else:\n                        fast_cente"
        "r = _try_proof_expansion_jet(\n                            road,\n  "
        "                          section,\n                            lane"
        ",\n                            center_s,\n                          "
        "  location,\n                            scale,\n                   "
        "         low,\n                            high,\n                  "
        "          spiral_proof,\n                        )\n                "
        "        if external_witness and fast_center:\n                      "
        "      cached_fast = (\n                                station_word,"
        "\n                                scale_word,\n                     "
        "           fast_center.value(),\n                            )\n    "
        "                if fast_center:\n                        var fast_de"
        "lta = _Interval(lo, hi) - _Interval.point(\n                        "
        "    center_s\n                        )\n                        var"
        " fast_lower = max(\n                            natural,\n          "
        "                  _global_lower(\n                                do"
        "main, fast_center.value(), fast_delta\n                            )"
        ",\n                        )\n                        if fast_lower "
        "> best_upper:\n                            continue\n               "
        "         if (\n                            _goal_excludes(fast_lower"
        ", scale, goal)\n                            or _next_up(best_upper -"
        " fast_lower) <= tolerance\n                        ):\n             "
        "               closed.add(\n                                _ClosedI"
        "nterval(\n                                    lo, hi, task[2], fast_"
        "lower, scale\n                                )\n                   "
        "         )\n                            continue\n                  "
        "      # A failed optional attempt is charged before the\n           "
        "             # original traversal; neither work cap is enlarged.\n  "
        "                      certificate.terms += center_work\n            "
        "    # Only a failed cached proof needs the expensive local GL\n     "
        "           # error traversal. It is still charged before execution."
        "\n                if spiral_proof and domain.error > tolerance * 0.2"
        "5:\n                    if certificate.terms > max_terms - work:\n  "
        '                      raise Error(\n                            "La'
        'ne refinement exhausted its quadrature work"\n                     '
        '       " limit"\n                        )\n                    ce'
        "rtificate.terms += work\n                    # Original F is prepaid"
        "; the optional model owns its node\n                    # and whole-"
        "union C. A decline retains all actual debits.\n                    v"
        "ar grouped: Optional[Tuple[_Jet, _Jet, _Jet]] = None\n              "
        "      # Keep the original closed-cell recheck available after\n     "
        "               # this optional producer. The original F is already p"
        "aid.\n                    if max_nodes - certificate.nodes >= 2:\n  "
        "                      grouped = _try_grouped_lane_jet(\n            "
        "                road,\n                            section,\n       "
        "                     lane,\n                            lo,\n       "
        "                     hi,\n                            certificate.no"
        "des,\n                            certificate.terms,\n              "
        "              max_nodes,\n                            max_terms,\n  "
        "                      )\n                    if grouped:\n          "
        "              point_domain = grouped.value()\n                    el"
        "se:\n                        point_domain = _lane_jet(road, section,"
        " lane, lo, hi)\n                    natural = max(\n                "
        "        natural,\n                        _scaled_point_distance_box"
        "(\n                            point_domain, location, scale\n      "
        "                  ).low,\n                    )\n                   "
        " if natural > best_upper:\n                        continue\n       "
        "             if _goal_excludes(natural, scale, goal):\n             "
        "           closed.add(\n                            _ClosedInterval("
        "lo, hi, task[2], natural, scale)\n                        )\n       "
        "                 continue\n                    domain = _scaled_poin"
        "t_distance_jet(\n                        point_domain, location, sca"
        "le\n                    )\n                    if fast_center:\n    "
        "                    var tightened_delta = _Interval(\n              "
        "              lo, hi\n                        ) - _Interval.point(ce"
        "nter_s)\n                        var tightened_lower = max(\n       "
        "                     natural,\n                            _global_l"
        "ower(\n                                domain, fast_center.value(), "
        "tightened_delta\n                            ),\n                   "
        "     )\n                        if tightened_lower > best_upper:\n  "
        "                          continue\n                        if (\n  "
        "                          _goal_excludes(tightened_lower, scale, goa"
        "l)\n                            or _next_up(best_upper - tightened_l"
        "ower)\n                            <= tolerance\n                   "
        "     ):\n                            closed.add(\n                  "
        "              _ClosedInterval(\n                                    "
        "lo, hi, task[2], tightened_lower, scale\n                           "
        "     )\n                            )\n                            c"
        "ontinue\n                # A nonfinite second derivative makes _glob"
        "al_lower ignore\n                # its expansion argument. A finite "
        "rounded domain value also\n                # establishes that this i"
        "s an evaluated expression enclosure,\n                # rather than "
        "an unvalidated whole/unknown record domain.\n                # Retai"
        "n the original work reservation above. Only skip the\n              "
        "  # unused traversal; no bound, tolerance, or cap changes.\n        "
        "        var center = _Jet.constant(0.0)\n                if (\n     "
        "               domain.second.is_finite()\n                    or not"
        " domain.rounded_value().is_finite()\n                ):\n           "
        "         var station_word = bitcast[DType.uint64](center_s)\n       "
        "             var scale_word = bitcast[DType.uint64](scale)\n        "
        "            if (\n                        external_witness\n        "
        "                and cached_expansion\n                        and _s"
        "ame_cache_key(\n                            cached_expansion.value()"
        "[0],\n                            cached_expansion.value()[1],\n    "
        "                        station_word,\n                            s"
        "cale_word,\n                        )\n                    ):\n     "
        "                   center = cached_expansion.value()[2]\n           "
        "         else:\n                        if frozen:\n                "
        "            center = _frozen_arc_expansion(\n                       "
        "         frozen.value(), center_s, location, scale\n                "
        "            )\n                        else:\n                      "
        "      center = _expansion_distance_jet(\n                           "
        "     road, section, lane, center_s, location, scale\n               "
        "             )\n                        if external_witness:\n      "
        "                      cached_expansion = (\n                        "
        "        station_word,\n                                scale_word,\n"
        "                                center,\n                           "
        " )\n                var delta = _Interval(lo, hi) - _Interval.point("
        "center_s)\n                var lower = max(natural, _global_lower(do"
        "main, center, delta))\n                var support = _Interval(lo, h"
        "i)\n                if external_witness:\n                    suppor"
        "t = _minimizer_support(\n                        domain, center, cen"
        "ter_s, best, lo, hi\n                    )\n                if lower"
        " > best_upper:\n                    continue\n                if (\n"
        "                    _goal_excludes(lower, scale, goal)\n            "
        "        or _next_up(best_upper - lower) <= tolerance\n              "
        "  ):\n                    closed.add(\n                        _Clos"
        "edInterval(\n                            support.low, support.high, "
        "task[2], lower, scale\n                        )\n                  "
        "  )\n                    continue\n                if support.low > "
        "lo or support.high < hi:\n                    if task[2] >= max_dept"
        "h:\n                        raise Error(\n                          "
        '  "Lane refinement exhausted its numerical accuracy"\n            '
        '                " limit"\n                        )\n             '
        "       pending.append((support.low, support.high, task[2] + 1))\n   "
        "                 continue\n"
    )
    afters.append(
        "            var proposal = _try_lane_center_bound(\n                "
        "road,\n                expansion_context,\n                _Interval"
        "(lo, hi),\n                best,\n                domain,\n         "
        "       natural,\n                work,\n                _LaneBoundPo"
        "licy(best_upper, scale, tolerance, goal),\n                certifica"
        "te.nodes,\n                certificate.terms,\n                max_n"
        "odes,\n                max_terms,\n            )\n            if pro"
        "posal:\n                ref bound = proposal.value()\n              "
        "  if bound.isa[_LaneBoundDiscard]():\n                    continue\n"
        "                if bound.isa[_LaneBoundClose]():\n                  "
        "  var close = bound[_LaneBoundClose]\n                    closed.add"
        "(\n                        _ClosedInterval(\n                       "
        "     close.support.low,\n                            close.support.h"
        "igh,\n                            task[2],\n                        "
        "    close.lower,\n                            scale,\n              "
        "          )\n                    )\n                    continue\n  "
        "              var support = bound[_LaneBoundContract].support\n     "
        "           if task[2] >= max_depth:\n                    raise Error"
        '(\n                        "Lane refinement exhausted its numerical'
        ' accuracy limit"\n                    )\n                pending.ap'
        "pend((support.low, support.high, task[2] + 1))\n                cont"
        "inue\n"
    )
    befores.append("    while len(pending) > 0 or closed.needs_validation():\n")
    afters.append(
        "    var expansion_context = _LaneExpansionContext(\n        section,"
        "\n        lane,\n        _Interval(low, high),\n        location,\n "
        "       spiral_proof,\n        frozen,\n        external_witness.copy"
        "(),\n        None,\n        None,\n    )\n    while len(pending) > 0"
        " or closed.needs_validation():\n"
    )
    befores.append(
        "    var cached_fast: Optional[Tuple[UInt64, UInt64, _Jet]] = None\n "
        "   var cached_expansion: Optional[Tuple[UInt64, UInt64, _Jet]] = Non"
        "e\n    var best = certificate.s\n"
    )
    afters.append("    var best = certificate.s\n")
    befores.append("def _run_lane_search(")
    afters.append(
        "@fieldwise_init\nstruct _LaneExpansionContext(Copyable, Movable):\n "
        "   # One search invocation only. The Road argument must remain uncha"
        "nged.\n    # Exact station/scale words are meaningful only for this "
        "owner and query.\n    var section: Int\n    var lane: Int\n    var r"
        "oot: _Interval\n    var location: Vector3\n    var spiral_proof: Opt"
        "ional[_SpiralDomainProof]\n    var frozen: Optional[_RoundedArc]\n  "
        "  var external_witness: Optional[Array[Float64, 3]]\n    var cached_"
        "fast: Optional[Tuple[UInt64, UInt64, _Jet]]\n    var cached_expansio"
        "n: Optional[Tuple[UInt64, UInt64, _Jet]]\n\n\n@fieldwise_init\nstruc"
        "t _LaneBoundPolicy(ImplicitlyCopyable):\n    # Already-computed stop"
        "ping criteria for this cell and incumbent.\n    var upper: Float64\n"
        "    var scale: Float64\n    var tolerance: Float64\n    var goal: Op"
        "tional[_LaneExclusionGoal]\n\n\n@fieldwise_init\nstruct _LaneBoundDi"
        "scard(ImplicitlyCopyable):\n    var lower: Float64\n    var support:"
        " _Interval\n\n\n@fieldwise_init\nstruct _LaneBoundClose(ImplicitlyCo"
        "pyable):\n    var lower: Float64\n    var support: _Interval\n\n\n@f"
        "ieldwise_init\nstruct _LaneBoundContract(ImplicitlyCopyable):\n    v"
        "ar lower: Float64\n    var support: _Interval\n\n\n# Named alternati"
        "ves carry the exact bound/support from their decision site.\n# No nu"
        "meric tag protocol or re-evaluation of acceptance in the caller.\nco"
        "mptime _LaneBoundProposal = Variant[\n    _LaneBoundDiscard, _LaneBo"
        "undClose, _LaneBoundContract\n]\n\n\ndef _try_lane_center_bound(\n  "
        "  road: Road,\n    mut context: _LaneExpansionContext,\n    cell: _I"
        "nterval,\n    best: Float64,\n    var domain: _Jet,\n    var natural"
        ": Float64,\n    whole_work: Int,\n    policy: _LaneBoundPolicy,\n   "
        " mut nodes: Int,\n    mut terms: Int,\n    max_nodes: Int,\n    max_"
        "terms: Int,\n) raises -> Optional[_LaneBoundProposal]:\n    # The ca"
        "ller supplies a real incumbent and the already-paid whole-cell\n    "
        "# enclosure. An unknown enclosure is valid. This optional phase owns"
        " no\n    # traversal state. None retains all work/cache effects of a"
        "n inconclusive\n    # admitted attempt; count refusal returns before"
        " either kind of effect.\n    # A clamped singleton endpoint can have"
        " a different jet from\n    # the interior branch. Taylor bounds need"
        " that same branch.\n    var center_s = _expansion_center(cell.low, c"
        "ell.high, best)\n    var center_work = _reference_work(road, center_"
        "s, center_s)\n    if center_work >= 0:\n        if terms > max_terms"
        ' - center_work:\n            raise Error("Lane refinement exhausted'
        ' its quadrature work limit")\n        terms += center_work\n       '
        " var fast_center: Optional[_Jet] = None\n        # The original full"
        "-domain second derivative and scalar\n        # error also apply to "
        "this ideal moment-backed expansion.\n        # Retain headroom for t"
        "he unchanged translated fallback.\n        if (\n            context"
        ".spiral_proof\n            and domain.second.is_finite()\n          "
        "  and center_work <= max_terms - terms\n        ):\n            var "
        "station_word = bitcast[DType.uint64](center_s)\n            var scal"
        "e_word = bitcast[DType.uint64](policy.scale)\n            if (\n    "
        "            context.external_witness\n                and context.ca"
        "ched_fast\n                and _same_cache_key(\n                   "
        " context.cached_fast.value()[0],\n                    context.cached"
        "_fast.value()[1],\n                    station_word,\n              "
        "      scale_word,\n                )\n            ):\n              "
        "  fast_center = context.cached_fast.value()[2]\n            else:\n "
        "               fast_center = _try_proof_expansion_jet(\n            "
        "        road,\n                    context.section,\n               "
        "     context.lane,\n                    center_s,\n                 "
        "   context.location,\n                    policy.scale,\n           "
        "         context.root.low,\n                    context.root.high,\n"
        "                    context.spiral_proof,\n                )\n      "
        "          if context.external_witness and fast_center:\n            "
        "        context.cached_fast = (\n                        station_wor"
        "d,\n                        scale_word,\n                        fas"
        "t_center.value(),\n                    )\n            if fast_center"
        ":\n                var fast_delta = _Interval(\n                    "
        "cell.low, cell.high\n                ) - _Interval.point(center_s)\n"
        "                var fast_lower = max(\n                    natural,"
        "\n                    _global_lower(domain, fast_center.value(), fas"
        "t_delta),\n                )\n                if fast_lower > policy"
        ".upper:\n                    return _LaneBoundProposal(\n           "
        "             _LaneBoundDiscard(fast_lower, cell)\n                  "
        "  )\n                if (\n                    _goal_excludes(fast_l"
        "ower, policy.scale, policy.goal)\n                    or _next_up(po"
        "licy.upper - fast_lower) <= policy.tolerance\n                ):\n  "
        "                  return _LaneBoundProposal(_LaneBoundClose(fast_low"
        "er, cell))\n                # A failed optional attempt is charged b"
        "efore the\n                # original traversal; neither work cap is"
        " enlarged.\n                terms += center_work\n        # Only a f"
        "ailed cached proof needs the expensive local GL\n        # error tra"
        "versal. It is still charged before execution.\n        if context.sp"
        "iral_proof and domain.error > policy.tolerance * 0.25:\n            "
        "if terms > max_terms - whole_work:\n                raise Error(\n  "
        '                  "Lane refinement exhausted its quadrature work li'
        'mit"\n                )\n            terms += whole_work\n         '
        "   # Original F is prepaid; the optional model owns its node\n      "
        "      # and whole-union C. A decline retains all actual debits.\n   "
        "         var grouped: Optional[Tuple[_Jet, _Jet, _Jet]] = None\n    "
        "        # Keep the original closed-cell recheck available after\n   "
        "         # this optional producer. The original F is already paid.\n"
        "            if max_nodes - nodes >= 2:\n                grouped = _t"
        "ry_grouped_lane_jet(\n                    road,\n                   "
        " context.section,\n                    context.lane,\n              "
        "      cell.low,\n                    cell.high,\n                   "
        " nodes,\n                    terms,\n                    max_nodes,"
        "\n                    max_terms,\n                )\n            var"
        " point_domain: Tuple[_Jet, _Jet, _Jet]\n            if grouped:\n   "
        "             point_domain = grouped.value()\n            else:\n    "
        "            point_domain = _lane_jet(\n                    road, con"
        "text.section, context.lane, cell.low, cell.high\n                )\n"
        "            natural = max(\n                natural,\n              "
        "  _scaled_point_distance_box(\n                    point_domain, con"
        "text.location, policy.scale\n                ).low,\n            )\n"
        "            if natural > policy.upper:\n                return _Lane"
        "BoundProposal(_LaneBoundDiscard(natural, cell))\n            if _goa"
        "l_excludes(natural, policy.scale, policy.goal):\n                ret"
        "urn _LaneBoundProposal(_LaneBoundClose(natural, cell))\n            "
        "domain = _scaled_point_distance_jet(\n                point_domain, "
        "context.location, policy.scale\n            )\n            if fast_c"
        "enter:\n                var tightened_delta = _Interval(\n          "
        "          cell.low, cell.high\n                ) - _Interval.point(c"
        "enter_s)\n                var tightened_lower = max(\n              "
        "      natural,\n                    _global_lower(domain, fast_cente"
        "r.value(), tightened_delta),\n                )\n                if "
        "tightened_lower > policy.upper:\n                    return _LaneBou"
        "ndProposal(\n                        _LaneBoundDiscard(tightened_low"
        "er, cell)\n                    )\n                if (\n            "
        "        _goal_excludes(tightened_lower, policy.scale, policy.goal)\n"
        "                    or _next_up(policy.upper - tightened_lower)\n   "
        "                 <= policy.tolerance\n                ):\n          "
        "          return _LaneBoundProposal(\n                        _LaneB"
        "oundClose(tightened_lower, cell)\n                    )\n        # A"
        " nonfinite second derivative makes _global_lower ignore\n        # i"
        "ts expansion argument. A finite rounded domain value also\n        #"
        " establishes that this is an evaluated expression enclosure,\n      "
        "  # rather than an unvalidated whole/unknown record domain.\n       "
        " # Retain the original work reservation above. Only skip the\n      "
        "  # unused traversal; no bound, tolerance, or cap changes.\n        "
        "var center = _Jet.constant(0.0)\n        if domain.second.is_finite("
        ") or not domain.rounded_value().is_finite():\n            var statio"
        "n_word = bitcast[DType.uint64](center_s)\n            var scale_word"
        " = bitcast[DType.uint64](policy.scale)\n            if (\n          "
        "      context.external_witness\n                and context.cached_e"
        "xpansion\n                and _same_cache_key(\n                    "
        "context.cached_expansion.value()[0],\n                    context.ca"
        "ched_expansion.value()[1],\n                    station_word,\n     "
        "               scale_word,\n                )\n            ):\n     "
        "           center = context.cached_expansion.value()[2]\n           "
        " else:\n                if context.frozen:\n                    cent"
        "er = _frozen_arc_expansion(\n                        context.frozen."
        "value(),\n                        center_s,\n                       "
        " context.location,\n                        policy.scale,\n         "
        "           )\n                else:\n                    center = _e"
        "xpansion_distance_jet(\n                        road,\n             "
        "           context.section,\n                        context.lane,\n"
        "                        center_s,\n                        context.l"
        "ocation,\n                        policy.scale,\n                   "
        " )\n                if context.external_witness:\n                  "
        "  context.cached_expansion = (\n                        station_word"
        ",\n                        scale_word,\n                        cent"
        "er,\n                    )\n        var delta = _Interval(cell.low, "
        "cell.high) - _Interval.point(center_s)\n        var lower = max(natu"
        "ral, _global_lower(domain, center, delta))\n        var support = _I"
        "nterval(cell.low, cell.high)\n        if context.external_witness:\n"
        "            support = _minimizer_support(\n                domain, c"
        "enter, center_s, best, cell.low, cell.high\n            )\n        i"
        "f lower > policy.upper:\n            return _LaneBoundProposal(_Lane"
        "BoundDiscard(lower, support))\n        if (\n            _goal_exclu"
        "des(lower, policy.scale, policy.goal)\n            or _next_up(polic"
        "y.upper - lower) <= policy.tolerance\n        ):\n            return"
        " _LaneBoundProposal(_LaneBoundClose(lower, support))\n        if sup"
        "port.low > cell.low or support.high < cell.high:\n            return"
        " _LaneBoundProposal(_LaneBoundContract(lower, support))\n    return "
        "None\n\n\ndef _run_lane_search("
    )
    befores.append("from std.memory import bitcast\n")
    afters.append(
        "from std.memory import bitcast\nfrom std.utils import Variant\n"
    )
    befores.append(
        "    var derivative = _length_up(\n        point[0].second.magnitude("
        "),\n        point[1].second.magnitude(),\n        point[2].second.ma"
        "gnitude(),\n    )\n    if not isfinite(derivative):\n        return "
        "(natural, box, spent)\n    var first_work = _reference_work(road, lo"
        "w, low)\n    var last_work = _reference_work(road, high, high)\n    "
        "if first_work < 0 or last_work < 0:\n        return (natural, box, s"
        "pent)\n"
    )
    afters.append(
        "    # Endpoint admission and a finite second derivative are independ"
        "ent\n    # requirements for the optional smooth certificate. Check t"
        "he counts\n    # first, including when the original coarse box is al"
        "ready unbounded.\n    # Either refusal retains the same natural boun"
        "d and spent-work ledger.\n    var first_work = _reference_work(road,"
        " low, low)\n    var last_work = _reference_work(road, high, high)\n "
        "   if first_work < 0 or last_work < 0:\n        return (natural, box"
        ", spent)\n    var derivative = _length_up(\n        point[0].second."
        "magnitude(),\n        point[1].second.magnitude(),\n        point[2]"
        ".second.magnitude(),\n    )\n    if not isfinite(derivative):\n     "
        "   return (natural, box, spent)\n"
    )
    befores.append(
        "                if natural > best_upper:\n                    contin"
        "ue\n                if _goal_excludes(natural, scale, goal):\n"
    )
    afters.append(
        "                # An unchanged seed repeats the admitted bound exact"
        "ly.\n                # An improved seed is an actual in-cell witness"
        ", so its\n                # upper distance cannot fall below this na"
        "tural enclosure.\n                if _goal_excludes(natural, scale, "
        "goal):\n"
    )
    befores.append(
        "            if (\n                domain.second.low > 0.0\n         "
        "       and domain.first.contains(0.0)\n                and isfinite("
        "hi - lo)\n            ):\n"
    )
    afters.append(
        "            # Admit finite interpolation width before the derivative"
        " tests.\n            # All three predicates are retained. The earlie"
        "r midpoint already\n            # evaluated this same subtraction, i"
        "ncluding an overflowing span.\n            if (\n                isf"
        "inite(hi - lo)\n                and domain.second.low > 0.0\n       "
        "         and domain.first.contains(0.0)\n            ):\n"
    )
    befores.append(
        "    if isfinite(seed):\n        seed = min(max(seed, lo), hi)\n     "
        "   var point = _checked_center(road, section, lane, seed, terms, max"
        "_terms)\n        if point[axis] == query[axis]:\n            return "
        "(seed, _legacy_square(point, query), point^, nodes, terms)\n        "
        "if direction * point[axis] < target:\n            lo = seed\n       "
        "     left = point^\n        else:\n            hi = seed\n          "
        "  right = point^\n"
    )
    afters.append(
        "    # The accepted rounded context bounds coordinates and nonzero sl"
        "ope\n    # to 2^-400..2^400. This inverse cannot overflow Float64.\n"
        "    seed = min(max(seed, lo), hi)\n    var seed_point = _checked_cen"
        "ter(\n        road, section, lane, seed, terms, max_terms\n    )\n  "
        "  if seed_point[axis] == query[axis]:\n        return (\n           "
        " seed,\n            _legacy_square(seed_point, query),\n            "
        "seed_point^,\n            nodes,\n            terms,\n        )\n   "
        " if direction * seed_point[axis] < target:\n        lo = seed\n     "
        "   left = seed_point^\n    else:\n        hi = seed\n        right ="
        " seed_point^\n"
    )


def _spans_9(mut befores: List[String], mut afters: List[String]):
    """Fill one reviewed span-edit table, last edit first.

    Args:
        befores: The predecessor spans.
        afters: The successor spans.
    """
    befores.append("")
    afters.append(
        "def _same_cache_key(\n    station: UInt64, scale: UInt64, other_stat"
        "ion: UInt64, other_scale: UInt64\n) -> Bool:\n    # A cached expansi"
        "on is keyed by its exact station and scale words. The\n    # pair is"
        " one key; compare it as one vector.\n    return SIMD[DType.uint64, 2"
        "](station, scale) == SIMD[DType.uint64, 2](\n        other_station, "
        "other_scale\n    )\n\n\n"
    )
    befores.append(
        "                        and cached_fast.value()[0] == station_word\n"
        "                        and cached_fast.value()[1] == scale_word\n"
    )
    afters.append(
        "                        and _same_cache_key(\n                      "
        "      cached_fast.value()[0],\n                            cached_fa"
        "st.value()[1],\n                            station_word,\n         "
        "                   scale_word,\n                        )\n"
    )
    befores.append(
        "                        and cached_expansion.value()[0] == station_w"
        "ord\n                        and cached_expansion.value()[1] == scal"
        "e_word\n"
    )
    afters.append(
        "                        and _same_cache_key(\n                      "
        "      cached_expansion.value()[0],\n                            cach"
        "ed_expansion.value()[1],\n                            station_word,"
        "\n                            scale_word,\n                        )"
        "\n"
    )


def _lines_10(
    mut starts: List[Int], mut stops: List[Int], mut befores: List[String]
):
    """Fill one reviewed line-edit table, highest line first.

    Args:
        starts: The 0-based start lines.
        stops: The exclusive end lines.
        befores: The predecessor lines for each span.
    """
    starts.append(1436)
    stops.append(1439)
    befores.append("        if lo > 0.0 and isfinite(hi) and hi >= lo:\n")


def _lines_11(
    mut starts: List[Int], mut stops: List[Int], mut befores: List[String]
):
    """Fill one reviewed line-edit table, highest line first.

    Args:
        starts: The 0-based start lines.
        stops: The exclusive end lines.
        befores: The predecessor lines for each span.
    """
    starts.append(1945)
    stops.append(1954)
    befores.append(
        "                if before >= lo:\n                    if external_wi"
        "tness and best >= split_at:\n                        pending.append("
        "(lo, before, task[2] + 1))\n                        pending.append(("
        "split_at, hi, task[2] + 1))\n                    else:\n            "
        "            pending.append((split_at, hi, task[2] + 1))\n           "
        "             pending.append((lo, before, task[2] + 1))\n            "
        "        continue\n"
    )
    starts.append(1931)
    stops.append(1932)
    befores.append("        if sampled_cuts and task[2] < max_depth:\n")
    starts.append(1919)
    stops.append(1921)
    befores.append("        if not sampled_checked and task[2] < max_depth:\n")
    starts.append(383)
    stops.append(386)
    befores.append("        if interior > low and interior < high:\n")
    starts.append(376)
    stops.append(379)
    befores.append("        if interior > low and interior < high:\n")


def _lines_12(
    mut starts: List[Int], mut stops: List[Int], mut befores: List[String]
):
    """Fill one reviewed line-edit table, highest line first.

    Args:
        starts: The 0-based start lines.
        stops: The exclusive end lines.
        befores: The predecessor lines for each span.
    """
    starts.append(52)
    stops.append(53)
    befores.append("from extensions.carla.road_info import info_index\n")


def _spans_13(mut befores: List[String], mut afters: List[String]):
    """Fill one reviewed span-edit table, last edit first.

    Args:
        befores: The predecessor spans.
        afters: The successor spans.
    """
    befores.append(
        "def _polynomial_value(\n    polynomial: CubicPolynomial, s: _ValueJe"
        "t, shift: Float64 = 0.0\n) -> _ValueJet:\n    return (\n        _Val"
        "ueJet.constant(polynomial.a) - _ValueJet.constant(shift)\n    ) + s "
        "* (\n        _ValueJet.constant(polynomial.b)\n        + s\n        "
        "* (\n            _ValueJet.constant(polynomial.c)\n            + s *"
        " _ValueJet.constant(polynomial.d)\n        )\n    )\n\n"
    )
    afters.append(
        "def _polynomial_value(\n    polynomial: CubicPolynomial, s: _ValueJe"
        "t, shift: Float64 = 0.0\n) -> _ValueJet:\n    var local = s - _Value"
        "Jet.constant(polynomial.s)\n    return (\n        _ValueJet.constant"
        "(polynomial.a) - _ValueJet.constant(shift)\n    ) + local * (\n     "
        "   _ValueJet.constant(polynomial.b)\n        + local\n        * (\n "
        "           _ValueJet.constant(polynomial.c)\n            + local * _"
        "ValueJet.constant(polynomial.d)\n        )\n    )\n\n"
    )


def _spans_14(mut befores: List[String], mut afters: List[String]):
    """Fill one reviewed span-edit table, last edit first.

    Args:
        befores: The predecessor spans.
        afters: The successor spans.
    """
    befores.append("    if isfinite(coupled_error) and coupled_error >= 0.0:\n")
    afters.append(
        "    # The concrete producer returns a nonnegative allowance or infin"
        "ity.\n    # Keep the finite fallback; a finite negative result is no"
        "t produced.\n    if isfinite(coupled_error):\n"
    )


def _lines_15(
    mut starts: List[Int], mut stops: List[Int], mut befores: List[String]
):
    """Fill one reviewed line-edit table, highest line first.

    Args:
        starts: The 0-based start lines.
        stops: The exclusive end lines.
        befores: The predecessor lines for each span.
    """
    starts.append(246)
    stops.append(247)
    befores.append("            scene.add_mesh(mesh^)\n")


def _lines_16(
    mut starts: List[Int], mut stops: List[Int], mut befores: List[String]
):
    """Fill one reviewed line-edit table, highest line first.

    Args:
        starts: The 0-based start lines.
        stops: The exclusive end lines.
        befores: The predecessor lines for each span.
    """
    starts.append(227)
    stops.append(281)
    befores.append("")
    starts.append(212)
    stops.append(225)
    befores.append("")
    starts.append(207)
    stops.append(211)
    befores.append("")
    starts.append(199)
    stops.append(200)
    befores.append("    def tangent(self, x: Float64) -> Float64:\n")
    starts.append(191)
    stops.append(198)
    befores.append(
        "        var local = x - self.s\n        return self.a + local * (sel"
        "f.b + local * (self.c + local * self.d))\n"
    )
    starts.append(186)
    stops.append(190)
    befores.append("")
    starts.append(178)
    stops.append(179)
    befores.append("    def evaluate(self, x: Float64) -> Float64:\n")
    starts.append(176)
    stops.append(177)
    befores.append("        return CubicPolynomial(value, 0, 0, 0, 0)\n")
    starts.append(172)
    stops.append(175)
    befores.append("")
    starts.append(85)
    stops.append(165)
    befores.append("    def constant(value: Float64) -> CubicPolynomial:\n")
    starts.append(57)
    stops.append(84)
    befores.append("")
    starts.append(50)
    stops.append(51)
    befores.append(
        "            s: Where the record starts along the road, in meters.\n "
        '       """\n'
    )
    starts.append(45)
    stops.append(46)
    befores.append("")
    starts.append(30)
    stops.append(37)
    befores.append(
        "        out self, a: Float64, b: Float64, c: Float64, d: Float64, s:"
        " Float64\n"
    )
    starts.append(15)
    stops.append(19)
    befores.append("")


def _spans_17(mut befores: List[String], mut afters: List[String]):
    """Fill one reviewed span-edit table, last edit first.

    Args:
        befores: The predecessor spans.
        afters: The successor spans.
    """
    befores.append(
        '        Returns:\n            The slope of the cubic.\n        ""'
        '"\n        return self.b + x * (2 * self.c + x * 3 * self.d)\n'
    )
    afters.append(
        '        Returns:\n            The slope of the cubic.\n        ""'
        '"\n        var local = x - self.s\n        return self.b + local * '
        "(2 * self.c + local * 3 * self.d)\n"
    )
    befores.append(
        '        Returns:\n            The value of the cubic.\n        ""'
        '"\n        return self.a + x * (self.b + x * (self.c + x * self.d))'
        '\n\n    def tangent(self, x: Float64) -> Float64:\n        """Ret'
        "urn df/dx, `CubicPolynomial::Tangent`.\n"
    )
    afters.append(
        '        Returns:\n            The value of the cubic.\n        ""'
        '"\n        var local = x - self.s\n        return self.a + local * '
        "(self.b + local * (self.c + local * self.d))\n\n    def tangent(self"
        ', x: Float64) -> Float64:\n        """Return df/dx, `CubicPolynom'
        "ial::Tangent`.\n"
    )
    befores.append(
        "            d: The cubic term, per square meter.\n            s: Whe"
        're the record starts along the road, in meters.\n        """\n   '
        "     self.a = a - b * s + c * s * s - d * s * s * s\n        self.b "
        "= b - 2 * c * s + 3 * d * s * s\n        self.c = c - 3 * d * s\n   "
        "     self.d = d\n        self.s = s\n\n"
    )
    afters.append(
        "            d: The cubic term, per square meter.\n            s: Whe"
        're the record starts along the road, in meters.\n        """\n   '
        "     self.a = a\n        self.b = b\n        self.c = c\n        sel"
        "f.d = d\n        self.s = s\n\n"
    )
    befores.append(
        '    ):\n        """Create the cubic of a record that starts at `s'
        "`.\n\n        The coefficients are re-expanded about zero, as CARLA "
        "does, so\n        `evaluate(x)` equals the record's cubic at `x - s`"
        ".\n\n        Args:\n            a: The constant term, in meters.\n"
    )
    afters.append(
        '    ):\n        """Create the cubic of a record that starts at `s'
        "`.\n\n        The original coefficients are stored unchanged. Unlike"
        " CARLA\n        1360bb9, evaluation forms the local coordinate `x - "
        "s` first.\n        This is a numerical correction, not bit-identical"
        " legacy behavior.\n\n        Args:\n            a: The constant term"
        ", in meters.\n"
    )
    befores.append(
        '"""CARLA\'s `geom::CubicPolynomial`: f(x) = a + b x + c x^2 + d x^'
        "3.\n\nOpenDRIVE writes lane widths, elevations and lane offsets as c"
        "ubics in a\ndistance ds from the start of their record. CARLA shifts"
        " each one to the\nroad's own s, so a caller evaluates every record a"
        "t the same s. The\ncoefficients carry mixed units: a is in meters, b"
        " has none, c is per\nmeter and d is per square meter. They stay plai"
        'n numbers for that reason.\n"""\n\n\nstruct CubicPolynomial(Impli'
        'citlyCopyable):\n    """A cubic in s, shifted so that it reads th'
        'e road\'s s directly."""\n\n    var a: Float64\n    var b: Float64'
        "\n"
    )
    afters.append(
        '"""CARLA\'s `geom::CubicPolynomial`: f(x) = a + b x + c x^2 + d x^'
        "3.\n\nOpenDRIVE writes lane widths, elevations and lane offsets as c"
        "ubics in a\ndistance ds from the start of their record. The record r"
        "etains its local coefficients and subtracts the record start\nbefore"
        " Horner evaluation. This avoids cancellation at a large road station"
        ".\nThe coefficients carry mixed units: a is in meters, b has none, c"
        " is per\nmeter and d is per square meter. They stay plain numbers fo"
        'r that reason.\n"""\n\n\nstruct CubicPolynomial(ImplicitlyCopyabl'
        'e):\n    """A local cubic evaluated at a road station or an expli'
        'cit parameter."""\n\n    var a: Float64\n    var b: Float64\n'
    )


def _spans_18(mut befores: List[String], mut afters: List[String]):
    """Fill one reviewed span-edit table, last edit first.

    Args:
        befores: The predecessor spans.
        afters: The successor spans.
    """
    befores.append(
        "                    data[at] * gain, data[at + 1] * gain, data[at + "
        "2] * gain\n                )\n                var seen = _mix(ground"
        ", sky, above)\n                data[at] = seen.r\n                da"
        "ta[at + 1] = seen.g\n                data[at + 2] = seen.b\n    retu"
        "rn _lighting(assets, cube^)\n\n\ndef _mix(a: FloatColor, b: FloatCol"
        'or, t: Float32) -> FloatColor:\n    """Return `a` moved toward `b'
        '` by `t`."""\n    return FloatColor(\n        a.r + (b.r - a.r) *'
        " t, a.g + (b.g - a.g) * t, a.b + (b.b - a.b) * t\n    )\n"
    )
    afters.append(
        "                    data[at] * gain, data[at + 1] * gain, data[at + "
        "2] * gain\n                )\n                var seen = mix_opaque("
        "ground, sky, above)\n                data[at] = seen.r\n            "
        "    data[at + 1] = seen.g\n                data[at + 2] = seen.b\n  "
        "  return _lighting(assets, cube^)\n"
    )
    befores.append(
        "        shade + light.b * silver * day + light.b * Float32(0.05) * d"
        "ay,\n    )\n    var colored = _mix(overcast, lit, cloud)\n    return"
        " _mix(\n        _ground_color(ground),\n        colored,\n"
    )
    afters.append(
        "        shade + light.b * silver * day + light.b * Float32(0.05) * d"
        "ay,\n    )\n    var colored = mix_opaque(overcast, lit, cloud)\n    "
        "return mix_opaque(\n        _ground_color(ground),\n        colored,"
        "\n"
    )
    befores.append(
        "    # Overcast: the whole sky goes gray as the cover grows.\n    var"
        " gray = (clear.r + clear.g + clear.b) / 3\n    var overcast = _mix("
        "\n        clear,\n        FloatColor(gray, gray * 1.02, gray * 1.06)"
        ",\n"
    )
    afters.append(
        "    # Overcast: the whole sky goes gray as the cover grows.\n    var"
        " gray = (clear.r + clear.g + clear.b) / 3\n    var overcast = mix_op"
        "aque(\n        clear,\n        FloatColor(gray, gray * 1.02, gray * "
        "1.06),\n"
    )
    befores.append(
        '    """\n    var up = max(direction.y, 0)\n    var night = _mix(N'
        "IGHT_HORIZON, NIGHT_ZENITH, sqrt(up))\n    var clear = FloatColor(\n"
        "        sky.r * gain * day + night.r,\n"
    )
    afters.append(
        '    """\n    var up = max(direction.y, 0)\n    var night = mix_op'
        "aque(NIGHT_HORIZON, NIGHT_ZENITH, sqrt(up))\n    var clear = FloatCo"
        "lor(\n        sky.r * gain * day + night.r,\n"
    )
    befores.append(
        '"""\n\nfrom core.assets import Assets\nfrom core.object3d import '
        "Object3D\n"
    )
    afters.append(
        '"""\n\nfrom render.color_math import mix_opaque\nfrom core.assets'
        " import Assets\nfrom core.object3d import Object3D\n"
    )


def _spans_19(mut befores: List[String], mut afters: List[String]):
    """Fill one reviewed span-edit table, last edit first.

    Args:
        befores: The predecessor spans.
        afters: The successor spans.
    """
    befores.append(
        "        Float32(0.3) + Float32(0.3) * rain,\n    )\n\n\ndef _mix(a: "
        'FloatColor, b: FloatColor, t: Float32) -> FloatColor:\n    """Ret'
        'urn `a` moved toward `b` by `t`."""\n    return FloatColor(\n    '
        "    a.r + (b.r - a.r) * t, a.g + (b.g - a.g) * t, a.b + (b.b - a.b) "
        "* t\n    )\n"
    )
    afters.append("        Float32(0.3) + Float32(0.3) * rain,\n    )\n")
    befores.append(
        "    var warm = kelvin_color(Temperature(kelvin, KELVIN))\n    var gr"
        "ay = _percent(weather.cloudiness) * Float32(0.6)\n    return _mix(wa"
        "rm, FloatColor(0.9, 0.92, 1.0), gray)\n\n\n"
    )
    afters.append(
        "    var warm = kelvin_color(Temperature(kelvin, KELVIN))\n    var gr"
        "ay = _percent(weather.cloudiness) * Float32(0.6)\n    return mix_opa"
        "que(warm, FloatColor(0.9, 0.92, 1.0), gray)\n\n\n"
    )
    befores.append(
        '"""\n\nfrom extensions.carla.weather import WeatherParameters\nfr'
        "om math.smoothstep import smoothstep\n"
    )
    afters.append(
        '"""\n\nfrom render.color_math import mix_opaque\nfrom extensions.'
        "carla.weather import WeatherParameters\nfrom math.smoothstep import "
        "smoothstep\n"
    )


def _lines_20(
    mut starts: List[Int], mut stops: List[Int], mut befores: List[String]
):
    """Fill one reviewed line-edit table, highest line first.

    Args:
        starts: The 0-based start lines.
        stops: The exclusive end lines.
        befores: The predecessor lines for each span.
    """
    starts.append(2282)
    stops.append(2293)
    befores.append("")
    starts.append(2273)
    stops.append(2274)
    befores.append(
        "        var half = Float32(self.lane_width(section, lane, at)) / 2.0\n"
    )
    starts.append(2178)
    stops.append(2242)
    befores.append("")
    starts.append(2163)
    stops.append(2164)
    befores.append("        var right = self.directed_point(at)\n")
    starts.append(2161)
    stops.append(2162)
    befores.append(
        "        var offsets = self.lane_edge_offsets(section, lane, s, extra"
        "_width)\n"
    )
    starts.append(2071)
    stops.append(2138)
    befores.append("")
    starts.append(1989)
    stops.append(1991)
    befores.append(
        "        offset -= lane_offset.value().polynomial.evaluate(s)\n      "
        "  slope -= lane_offset.value().polynomial.tangent(s)\n"
    )
    starts.append(1897)
    stops.append(1952)
    befores.append("")
    starts.append(1864)
    stops.append(1868)
    befores.append(
        "            elevation.tangent(low) * span,\n            (elevation.c"
        " + 3.0 * (low - elevation.s) * elevation.d) * span * span,\n"
    )
    starts.append(1850)
    stops.append(1851)
    befores.append("        var elevation = self.elevation_on(low)\n")
    starts.append(1839)
    stops.append(1840)
    befores.append("                q1 += factor * width.tangent(low)\n")
    starts.append(1813)
    stops.append(1814)
    befores.append("        var q1 = -offset.tangent(low)\n")
    starts.append(1761)
    stops.append(1764)
    befores.append(
        "        var elevation = self.elevation_on(s)\n        point.z = elev"
        "ation.evaluate(s)\n        point.pitch = elevation.tangent(s)\n"
    )
    starts.append(1743)
    stops.append(1744)
    befores.append(
        "        offset -= lane_offset.value().polynomial.evaluate(s)\n"
    )
    starts.append(1683)
    stops.append(1685)
    befores.append(
        "            var w = width.value().polynomial.evaluate(s)\n          "
        "  var t = width.value().polynomial.tangent(s)\n"
    )
    starts.append(1641)
    stops.append(1642)
    befores.append("            start + self.section_length(section)\n")
    starts.append(1612)
    stops.append(1613)
    befores.append("            return width.value().polynomial.evaluate(s)\n")
    starts.append(1552)
    stops.append(1594)
    befores.append(
        "    def lane_width(self, section: Int, lane: Int, s: Float64) raises"
        " -> Float64:\n"
    )
    starts.append(1550)
    stops.append(1551)
    befores.append("        return self.section_length(section)\n")
    starts.append(1513)
    stops.append(1542)
    befores.append("    def lane_length(self, section: Int) -> Float64:\n")
    starts.append(1466)
    stops.append(1467)
    befores.append(
        "                var w = width.value().polynomial.evaluate(s)\n"
    )
    starts.append(1447)
    stops.append(1448)
    befores.append("        zero.z = self.elevation_on(s).evaluate(s)\n")
    starts.append(1442)
    stops.append(1443)
    befores.append(
        "            offset = lane_offset.value().polynomial.evaluate(clamped"
        ")\n"
    )
    starts.append(1434)
    stops.append(1435)
    befores.append("        var lanes = self.lanes_at(s)\n")
    starts.append(1340)
    stops.append(1399)
    befores.append("")
    starts.append(1330)
    stops.append(1331)
    befores.append(
        "            var d = self.info.geometries[i].geometry.distance_to(loc"
        "ation)\n"
    )
    starts.append(1270)
    stops.append(1313)
    befores.append(
        "    def nearest_point(self, location: Vector3) -> Tuple[Float64, Flo"
        "at64]:\n"
    )
    starts.append(1265)
    stops.append(1268)
    befores.append(
        "        var elevation = self.elevation_on(s)\n        point.z = Floa"
        "t64(Float32(elevation.evaluate(s)))\n        point.pitch = elevation"
        ".tangent(s)\n"
    )
    starts.append(1260)
    stops.append(1261)
    befores.append("        return record.geometry.pos_at(s - record.s)\n")
    starts.append(1199)
    stops.append(1241)
    befores.append(
        "    def directed_point_no_lane_offset(self, s: Float64) raises -> Di"
        "rectedPoint:\n"
    )
    starts.append(1192)
    stops.append(1195)
    befores.append(
        "            offset = Float32(lane_offset.value().polynomial.evaluate"
        "(clamped))\n"
    )
    starts.append(1129)
    stops.append(1173)
    befores.append(
        "    def directed_point(self, s: Float64) raises -> DirectedPoint:\n"
    )
    starts.append(1083)
    stops.append(1113)
    befores.append(
        "    def elevation_on(self, s: Float64) raises -> CubicPolynomial:\n"
    )
    starts.append(997)
    stops.append(1034)
    befores.append("")
    starts.append(940)
    stops.append(977)
    befores.append("")
    starts.append(924)
    stops.append(925)
    befores.append("        for index in self.sections_at(s):\n")
    starts.append(876)
    stops.append(912)
    befores.append(
        "    def lanes_at(self, s: Float64) -> List[Tuple[Int, Int]]:\n"
    )
    starts.append(871)
    stops.append(872)
    befores.append("        for index in self.sections_at(s):\n")
    starts.append(830)
    stops.append(862)
    befores.append(
        "    def lanes_by_distance(self, s: Float64) -> List[Tuple[Int, Int]]"
        ":\n"
    )
    starts.append(824)
    stops.append(825)
    befores.append("        for index in self.sections_at(s):\n")
    starts.append(775)
    stops.append(810)
    befores.append("")
    starts.append(712)
    stops.append(748)
    befores.append("    def sections_at(self, s: Float64) -> List[Int]:\n")
    starts.append(669)
    stops.append(699)
    befores.append("    def upper_bound(self, s: Float64) -> Float64:\n")
    starts.append(667)
    stops.append(668)
    befores.append("        return self.upper_bound(s) - s\n")
    starts.append(626)
    stops.append(657)
    befores.append("    def section_length(self, index: Int) -> Float64:\n")
    starts.append(602)
    stops.append(603)
    befores.append("        var section = LaneSection(id, s)\n")
    starts.append(558)
    stops.append(590)
    befores.append(
        "    def add_section(mut self, id: SectionId, s: Float64) raises -> I"
        "nt:\n"
    )
    starts.append(524)
    stops.append(525)
    befores.append("")
    starts.append(409)
    stops.append(515)
    befores.append("")
    starts.append(370)
    stops.append(381)
    befores.append("")
    starts.append(348)
    stops.append(349)
    befores.append("        self.lanes.insert(at, Lane(id, self.id, self.s))\n")
    starts.append(291)
    stops.append(292)
    befores.append("")
    starts.append(242)
    stops.append(288)
    befores.append(
        "    def __init__(out self, id: SectionId, s: Float64) raises:\n"
    )
    starts.append(221)
    stops.append(232)
    befores.append("")
    starts.append(194)
    stops.append(210)
    befores.append("")
    starts.append(148)
    stops.append(188)
    befores.append(
        "        out self, id: LaneId, section_id: SectionId, distance: Float"
        '64\n    ):\n        """Create a lane with no type, no links and n'
        "o records.\n"
    )
    starts.append(88)
    stops.append(96)
    befores.append(
        "from units.si import DEGREE, Angle, Length, METER, RADIAN\n"
    )
    starts.append(82)
    stops.append(84)
    befores.append("    info_at,\n    info_index,\n")
    starts.append(52)
    stops.append(58)
    befores.append(
        "from extensions.carla.geometry import ARC, DirectedPoint, LINE\n"
    )


def _spans_21(mut befores: List[String], mut afters: List[String]):
    """Fill one reviewed span-edit table, last edit first.

    Args:
        befores: The predecessor spans.
        afters: The successor spans.
    """
    befores.append(
        "            -q3 * span * span * span * c,\n            point.z - Flo"
        "at64(location.z),\n            elevation.tangent(low) * span,\n     "
        "       (elevation.c + 3.0 * low * elevation.d) * span * span,\n     "
        "       elevation.d * span * span * span,\n        ]\n        var sca"
        "le = span\n"
    )
    afters.append(
        "            -q3 * span * span * span * c,\n            point.z - Flo"
        "at64(location.z),\n            elevation.tangent(low) * span,\n     "
        "       (elevation.c + 3.0 * (low - elevation.s) * elevation.d) * spa"
        "n * span,\n            elevation.d * span * span * span,\n        ]"
        "\n        var scale = span\n"
    )
    befores.append(
        "                var width = widths[width_at].polynomial\n           "
        "     var factor = sign * (0.5 if lanes[i].id == id else 1.0)\n      "
        "          q1 += factor * width.tangent(low)\n                q2 += f"
        "actor * (width.c + 3.0 * low * width.d)\n                q3 += facto"
        "r * width.d\n                done = lanes[i].id == id\n        var p"
        "oint = self._lane_point(section, lane, low)\n"
    )
    afters.append(
        "                var width = widths[width_at].polynomial\n           "
        "     var factor = sign * (0.5 if lanes[i].id == id else 1.0)\n      "
        "          q1 += factor * width.tangent(low)\n                q2 += f"
        "actor * (width.c + 3.0 * (low - width.s) * width.d)\n               "
        " q3 += factor * width.d\n                done = lanes[i].id == id\n "
        "       var point = self._lane_point(section, lane, low)\n"
    )
    befores.append(
        "            return List[Float64]()\n        var offset = info_at(sel"
        "f.info.lane_offsets, low).value().polynomial\n        var q1 = -offs"
        "et.tangent(low)\n        var q2 = -(offset.c + 3.0 * low * offset.d)"
        "\n        var q3 = -offset.d\n        ref lanes = self.sections[sect"
        "ion].lanes\n        var id = lanes[lane].id\n"
    )
    afters.append(
        "            return List[Float64]()\n        var offset = info_at(sel"
        "f.info.lane_offsets, low).value().polynomial\n        var q1 = -offs"
        "et.tangent(low)\n        var q2 = -(offset.c + 3.0 * (low - offset.s"
        ") * offset.d)\n        var q3 = -offset.d\n        ref lanes = self."
        "sections[section].lanes\n        var id = lanes[lane].id\n"
    )


def _lines_22(
    mut starts: List[Int], mut stops: List[Int], mut befores: List[String]
):
    """Fill one reviewed line-edit table, highest line first.

    Args:
        starts: The 0-based start lines.
        stops: The exclusive end lines.
        befores: The predecessor lines for each span.
    """
    starts.append(101)
    stops.append(103)
    befores.append("]  # fmt: skip\n")
    starts.append(69)
    stops.append(70)
    befores.append("")


def _lines_23(
    mut starts: List[Int], mut stops: List[Int], mut befores: List[String]
):
    """Fill one reviewed line-edit table, highest line first.

    Args:
        starts: The 0-based start lines.
        stops: The exclusive end lines.
        befores: The predecessor lines for each span.
    """
    starts.append(145)
    stops.append(146)
    befores.append(
        "    var value: Float64\n    try:\n        value = Float64(number)\n "
        '   except:\n        raise Error("OpenDRIVE speed needs a numeric ma'
        'x value")\n'
    )


def _lines_24(
    mut starts: List[Int], mut stops: List[Int], mut befores: List[String]
):
    """Fill one reviewed line-edit table, highest line first.

    Args:
        starts: The 0-based start lines.
        stops: The exclusive end lines.
        befores: The predecessor lines for each span.
    """
    starts.append(156)
    stops.append(158)
    befores.append("            if byte >= 49 and byte <= 57:\n")
    starts.append(142)
    stops.append(145)
    befores.append("")
    starts.append(93)
    stops.append(126)
    befores.append("")


def _lines_25(
    mut starts: List[Int], mut stops: List[Int], mut befores: List[String]
):
    """Fill one reviewed line-edit table, highest line first.

    Args:
        starts: The 0-based start lines.
        stops: The exclusive end lines.
        befores: The predecessor lines for each span.
    """
    starts.append(236)
    stops.append(239)
    befores.append(
        "            if not _grouped_term(y, copies, y_ideal, y_magnitude, y_"
        "inherited):\n                return None\n"
    )


def _spans_26(mut befores: List[String], mut afters: List[String]):
    """Fill one reviewed span-edit table, last edit first.

    Args:
        befores: The predecessor spans.
        afters: The successor spans.
    """
    befores.append(
        "def _try_spiral_grouped_roundoff_envelope(\n    geometry: RoadGeomet"
        "ry,\n    d: _Jet,\n    pieces: Int,\n) -> Optional[Tuple[Float64, Fl"
        "oat64]]:\n    # PRECONDITION: the caller reserved this complete atte"
        "mpt separately from\n    # any fallback. The metered adapter below s"
        "upplies that admission policy.\n    # The original caller also owns "
        "clamping and the complete count union; this\n    # helper must not s"
        "ilently replace that union with one selected count.\n    if not _sum"
        "2_supported_environment():\n        return None\n    var rate = _spi"
        "ral_grouped_domain_rate(geometry, d, pieces)\n    if not rate:\n    "
        "    return None\n    var rate_value = rate.value()\n    var nodes = "
        "materialize[_GL_NODES]()\n    var weights = materialize[_GL_WEIGHTS]"
        "()\n    # Materialized copies come only from these immutable compile"
        "-time tables.\n    # Reject an incompatible table at compilation, be"
        "fore this helper can run.\n    # The stored pair multiplicities rema"
        "in 2,2,1; no ideal weight sum is used.\n    comptime assert _GL_WEIG"
        "HTS[0] == _GL_WEIGHTS[4]\n    comptime assert _GL_WEIGHTS[1] == _GL_"
        "WEIGHTS[3]\n    comptime assert _GL_WEIGHTS[0] > 0.0 and _GL_WEIGHTS"
        "[0] <= 1.0\n    comptime assert _GL_NODES[0] > -1.0 and _GL_NODES[0]"
        " < 1.0\n    comptime assert _GL_WEIGHTS[1] > 0.0 and _GL_WEIGHTS[1] "
        "<= 1.0\n    comptime assert _GL_NODES[1] > -1.0 and _GL_NODES[1] < 1"
        ".0\n    comptime assert _GL_WEIGHTS[2] > 0.0 and _GL_WEIGHTS[2] <= 1"
        ".0\n    comptime assert _GL_NODES[2] > -1.0 and _GL_NODES[2] < 1.0\n"
        "    comptime assert _GL_WEIGHTS[3] > 0.0 and _GL_WEIGHTS[3] <= 1.0\n"
        "    comptime assert _GL_NODES[3] > -1.0 and _GL_NODES[3] < 1.0\n    "
        "comptime assert _GL_WEIGHTS[4] > 0.0 and _GL_WEIGHTS[4] <= 1.0\n    "
        "comptime assert _GL_NODES[4] > -1.0 and _GL_NODES[4] < 1.0\n    var "
        "node_low = inf[DType.float64]()\n    var node_high = -inf[DType.floa"
        "t64]()\n    for i in range(5):\n        var node = 1.0 + nodes[i]\n "
        "       node_low = min(node_low, node)\n        node_high = max(node_"
        "high, node)\n    var distance = _ValueJet(\n        d.value, _Interv"
        "al.whole(), _Interval.whole(), d.error\n    )\n    var step = distan"
        "ce / _ValueJet.constant(Float64(pieces))\n    var half_step = _store"
        "d_half(step)\n    var half_rate = _stored_half(_ValueJet.constant(ra"
        "te_value))\n    var node_range = _grouped_constant(node_low, node_hi"
        "gh)\n    var phases = Array[_ValueJet, 4](fill=_ValueJet.constant(0."
        "0))\n    # Establish every group's original rounded phase branch bef"
        "ore the first\n    # polynomial evaluation. An ineligible later grou"
        "p cannot waste trig work.\n    for group in range(4):\n        var l"
        "ow = group * pieces // 4\n        var high = (group + 1) * pieces //"
        " 4\n        if low == high:\n            continue\n        var start"
        " = step * _grouped_constant(Float64(low), Float64(high - 1))\n      "
        "  var t = start + half_step * node_range\n        var theta = _Value"
        "Jet.constant(geometry.heading) + t * (\n            _ValueJet.consta"
        "nt(geometry.curvature_start) + half_rate * t\n        )\n        var"
        " phase = theta.rounded_value()\n        if not phase.is_finite() or "
        "phase.magnitude() > _PHASE_LIMIT:\n            return None\n        "
        "var selection = (\n            theta * _ValueJet.constant(_INV_HALF_"
        "PI) + _ValueJet.constant(0.5)\n        ).rounded_value()\n        if"
        " (\n            not selection.is_finite()\n            or floor(sele"
        "ction.low) != 0.0\n            or floor(selection.high) != 0.0\n    "
        "    ):\n            return None\n        phases[group] = theta\n    "
        "var factors = Array[_ValueJet, 3](fill=_ValueJet.constant(0.0))\n   "
        " for weight in range(3):\n        factors[weight] = half_step * _Val"
        "ueJet.constant(weights[weight])\n    var x_ideal = _Interval.point(0"
        ".0)\n    var y_ideal = _Interval.point(0.0)\n    var x_magnitude = _"
        "Interval.point(0.0)\n    var y_magnitude = _Interval.point(0.0)\n   "
        " var x_inherited = _Interval.point(0.0)\n    var y_inherited = _Inte"
        "rval.point(0.0)\n    for group in range(4):\n        var low = group"
        " * pieces // 4\n        var high = (group + 1) * pieces // 4\n      "
        "  if low == high:\n            continue\n        var trig = _sincos_"
        "expression(phases[group])\n        for weight in range(3):\n        "
        "    var multiplicity = 1 if weight == 2 else 2\n            var copi"
        "es = (high - low) * multiplicity\n            var x = factors[weight"
        "] * trig[1]\n            var y = factors[weight] * trig[0]\n        "
        "    if not _grouped_term(x, copies, x_ideal, x_magnitude, x_inherite"
        "d):\n                return None\n            if not _grouped_term(y"
        ", copies, y_ideal, y_magnitude, y_inherited):\n                retur"
        "n None\n    var x_error = _grouped_origin_error(\n        x_ideal, x"
        "_magnitude, x_inherited, 5 * pieces, geometry.x\n    )\n    var y_er"
        "ror = _grouped_origin_error(\n        y_ideal, y_magnitude, y_inheri"
        "ted, 5 * pieces, geometry.y\n    )\n    if not isfinite(x_error) or "
        "not isfinite(y_error):\n        return None\n    return (x_error, y_"
        "error)\n\n\n"
    )
    afters.append(
        "def _try_spiral_grouped_roundoff_envelope(\n    geometry: RoadGeomet"
        "ry,\n    d: _Jet,\n    pieces: Int,\n) -> Optional[Tuple[Float64, Fl"
        "oat64]]:\n    # PRECONDITION: the caller reserved this complete atte"
        "mpt separately from\n    # any fallback. The metered adapter below s"
        "upplies that admission policy.\n    # The original caller also owns "
        "clamping and the complete count union; this\n    # helper must not s"
        "ilently replace that union with one selected count.\n    if not _sum"
        "2_supported_environment():\n        return None\n    var rate = _spi"
        "ral_grouped_domain_rate(geometry, d, pieces)\n    if not rate:\n    "
        "    return None\n    var rate_value = rate.value()\n    var nodes = "
        "materialize[_GL_NODES]()\n    var weights = materialize[_GL_WEIGHTS]"
        "()\n    # Materialized copies come only from these immutable compile"
        "-time tables.\n    # Reject an incompatible table at compilation, be"
        "fore this helper can run.\n    # The stored pair multiplicities rema"
        "in 2,2,1; no ideal weight sum is used.\n    comptime assert _GL_WEIG"
        "HTS[0] == _GL_WEIGHTS[4]\n    comptime assert _GL_WEIGHTS[1] == _GL_"
        "WEIGHTS[3]\n    comptime assert _GL_WEIGHTS[0] > 0.0 and _GL_WEIGHTS"
        "[0] <= 1.0\n    comptime assert _GL_NODES[0] > -1.0 and _GL_NODES[0]"
        " < 1.0\n    comptime assert _GL_WEIGHTS[1] > 0.0 and _GL_WEIGHTS[1] "
        "<= 1.0\n    comptime assert _GL_NODES[1] > -1.0 and _GL_NODES[1] < 1"
        ".0\n    comptime assert _GL_WEIGHTS[2] > 0.0 and _GL_WEIGHTS[2] <= 1"
        ".0\n    comptime assert _GL_NODES[2] > -1.0 and _GL_NODES[2] < 1.0\n"
        "    comptime assert _GL_WEIGHTS[3] > 0.0 and _GL_WEIGHTS[3] <= 1.0\n"
        "    comptime assert _GL_NODES[3] > -1.0 and _GL_NODES[3] < 1.0\n    "
        "comptime assert _GL_WEIGHTS[4] > 0.0 and _GL_WEIGHTS[4] <= 1.0\n    "
        "comptime assert _GL_NODES[4] > -1.0 and _GL_NODES[4] < 1.0\n    var "
        "node_low = inf[DType.float64]()\n    var node_high = -inf[DType.floa"
        "t64]()\n    for i in range(5):\n        var node = 1.0 + nodes[i]\n "
        "       node_low = min(node_low, node)\n        node_high = max(node_"
        "high, node)\n    var distance = _ValueJet(\n        d.value, _Interv"
        "al.whole(), _Interval.whole(), d.error\n    )\n    var step = distan"
        "ce / _ValueJet.constant(Float64(pieces))\n    var half_step = _store"
        "d_half(step)\n    var half_rate = _stored_half(_ValueJet.constant(ra"
        "te_value))\n    var node_range = _grouped_constant(node_low, node_hi"
        "gh)\n    var phases = Array[_ValueJet, 4](fill=_ValueJet.constant(0."
        "0))\n    # Establish every group's original rounded phase branch bef"
        "ore the first\n    # polynomial evaluation. An ineligible later grou"
        "p cannot waste trig work.\n    for group in range(4):\n        var l"
        "ow = group * pieces // 4\n        var high = (group + 1) * pieces //"
        " 4\n        if low == high:\n            continue\n        var start"
        " = step * _grouped_constant(Float64(low), Float64(high - 1))\n      "
        "  var t = start + half_step * node_range\n        var theta = _Value"
        "Jet.constant(geometry.heading) + t * (\n            _ValueJet.consta"
        "nt(geometry.curvature_start) + half_rate * t\n        )\n        var"
        " phase = theta.rounded_value()\n        if not phase.is_finite() or "
        "phase.magnitude() > _PHASE_LIMIT:\n            return None\n        "
        "var selection = (\n            theta * _ValueJet.constant(_INV_HALF_"
        "PI) + _ValueJet.constant(0.5)\n        ).rounded_value()\n        # "
        "The ordered theta and nonnegative error are bounded by the phase gat"
        "e.\n        # Multiplication by k<=1 and addition of 0.5 cannot over"
        "flow this selector.\n        comptime assert _INV_HALF_PI > 0.0 and "
        "_INV_HALF_PI <= 1.0\n        comptime assert _PHASE_LIMIT > 0.0 and "
        "_PHASE_LIMIT <= 1048576.0\n        if floor(selection.low) != 0.0 or"
        " floor(selection.high) != 0.0:\n            return None\n        pha"
        "ses[group] = theta\n    var factors = Array[_ValueJet, 3](fill=_Valu"
        "eJet.constant(0.0))\n    for weight in range(3):\n        factors[we"
        "ight] = half_step * _ValueJet.constant(weights[weight])\n    var x_i"
        "deal = _Interval.point(0.0)\n    var y_ideal = _Interval.point(0.0)"
        "\n    var x_magnitude = _Interval.point(0.0)\n    var y_magnitude = "
        "_Interval.point(0.0)\n    var x_inherited = _Interval.point(0.0)\n  "
        "  var y_inherited = _Interval.point(0.0)\n    for group in range(4):"
        "\n        var low = group * pieces // 4\n        var high = (group +"
        " 1) * pieces // 4\n        if low == high:\n            continue\n  "
        "      var trig = _sincos_expression(phases[group])\n        for weig"
        "ht in range(3):\n            var multiplicity = 1 if weight == 2 els"
        "e 2\n            var copies = (high - low) * multiplicity\n         "
        "   var x = factors[weight] * trig[1]\n            var y = factors[we"
        "ight] * trig[0]\n            if not _grouped_term(x, copies, x_ideal"
        ", x_magnitude, x_inherited):\n                return None\n         "
        "   if not _grouped_term(y, copies, y_ideal, y_magnitude, y_inherited"
        "):\n                return None\n    var x_error = _grouped_origin_e"
        "rror(\n        x_ideal, x_magnitude, x_inherited, 5 * pieces, geomet"
        "ry.x\n    )\n    var y_error = _grouped_origin_error(\n        y_ide"
        "al, y_magnitude, y_inherited, 5 * pieces, geometry.y\n    )\n    if "
        "not isfinite(x_error) or not isfinite(y_error):\n        return None"
        "\n    return (x_error, y_error)\n\n\n"
    )


def _spans_27(mut befores: List[String], mut afters: List[String]):
    """Fill one reviewed span-edit table, last edit first.

    Args:
        befores: The predecessor spans.
        afters: The successor spans.
    """
    befores.append(
        "def _try_spiral_grouped_roundoff_envelope(\n    geometry: RoadGeomet"
        "ry,\n    d: _Jet,\n    pieces: Int,\n) -> Optional[Tuple[Float64, Fl"
        "oat64]]:\n    # PRECONDITION: the caller reserved this complete atte"
        "mpt separately from\n    # any fallback. The metered adapter below s"
        "upplies that admission policy.\n    # The original caller also owns "
        "clamping and the complete count union; this\n    # helper must not s"
        "ilently replace that union with one selected count.\n    if not _sum"
        "2_supported_environment():\n        return None\n    var rate = _spi"
        "ral_grouped_domain_rate(geometry, d, pieces)\n    if not rate:\n    "
        "    return None\n    var rate_value = rate.value()\n    var nodes = "
        "materialize[_GL_NODES]()\n    var weights = materialize[_GL_WEIGHTS]"
        "()\n    # Exactly the stored pairs, with actual multiplicities 2,2,1"
        ". A changed\n    # table must not silently keep a symmetry assumptio"
        "n or ideal weight sum.\n    if weights[0] != weights[4] or weights[1"
        "] != weights[3]:\n        return None\n    var node_low = inf[DType."
        "float64]()\n    var node_high = -inf[DType.float64]()\n    for i in "
        "range(5):\n        if not isfinite(weights[i]) or weights[i] <= 0.0:"
        "\n            return None\n        var node = 1.0 + nodes[i]\n      "
        "  if not isfinite(node):\n            return None\n        node_low "
        "= min(node_low, node)\n        node_high = max(node_high, node)\n   "
        " var distance = _ValueJet(\n        d.value, _Interval.whole(), _Int"
        "erval.whole(), d.error\n    )\n    var step = distance / _ValueJet.c"
        "onstant(Float64(pieces))\n    var half_step = _stored_half(step)\n  "
        "  var half_rate = _stored_half(_ValueJet.constant(rate_value))\n    "
        "var node_range = _grouped_constant(node_low, node_high)\n    var pha"
        "ses = Array[_ValueJet, 4](fill=_ValueJet.constant(0.0))\n    # Estab"
        "lish every group's original rounded phase branch before the first\n "
        "   # polynomial evaluation. An ineligible later group cannot waste t"
        "rig work.\n    for group in range(4):\n        var low = group * pie"
        "ces // 4\n        var high = (group + 1) * pieces // 4\n        if l"
        "ow == high:\n            continue\n        var start = step * _group"
        "ed_constant(Float64(low), Float64(high - 1))\n        var t = start "
        "+ half_step * node_range\n        var theta = _ValueJet.constant(geo"
        "metry.heading) + t * (\n            _ValueJet.constant(geometry.curv"
        "ature_start) + half_rate * t\n        )\n        var phase = theta.r"
        "ounded_value()\n        if not phase.is_finite() or phase.magnitude("
        ") > _PHASE_LIMIT:\n            return None\n        var selection = "
        "(\n            theta * _ValueJet.constant(_INV_HALF_PI) + _ValueJet."
        "constant(0.5)\n        ).rounded_value()\n        if (\n            "
        "not selection.is_finite()\n            or floor(selection.low) != 0."
        "0\n            or floor(selection.high) != 0.0\n        ):\n        "
        "    return None\n        phases[group] = theta\n    var factors = Ar"
        "ray[_ValueJet, 3](fill=_ValueJet.constant(0.0))\n    for weight in r"
        "ange(3):\n        factors[weight] = half_step * _ValueJet.constant(w"
        "eights[weight])\n    var x_ideal = _Interval.point(0.0)\n    var y_i"
        "deal = _Interval.point(0.0)\n    var x_magnitude = _Interval.point(0"
        ".0)\n    var y_magnitude = _Interval.point(0.0)\n    var x_inherited"
        " = _Interval.point(0.0)\n    var y_inherited = _Interval.point(0.0)"
        "\n    for group in range(4):\n        var low = group * pieces // 4"
        "\n        var high = (group + 1) * pieces // 4\n        if low == hi"
        "gh:\n            continue\n        var trig = _sincos_expression(pha"
        "ses[group])\n        for weight in range(3):\n            var multip"
        "licity = 1 if weight == 2 else 2\n            var copies = (high - l"
        "ow) * multiplicity\n            var x = factors[weight] * trig[1]\n "
        "           var y = factors[weight] * trig[0]\n            if not _gr"
        "ouped_term(x, copies, x_ideal, x_magnitude, x_inherited):\n         "
        "       return None\n            if not _grouped_term(y, copies, y_id"
        "eal, y_magnitude, y_inherited):\n                return None\n    va"
        "r x_error = _grouped_origin_error(\n        x_ideal, x_magnitude, x_"
        "inherited, 5 * pieces, geometry.x\n    )\n    var y_error = _grouped"
        "_origin_error(\n        y_ideal, y_magnitude, y_inherited, 5 * piece"
        "s, geometry.y\n    )\n    if not isfinite(x_error) or not isfinite(y"
        "_error):\n        return None\n    return (x_error, y_error)\n\n\n"
    )
    afters.append(
        "def _try_spiral_grouped_roundoff_envelope(\n    geometry: RoadGeomet"
        "ry,\n    d: _Jet,\n    pieces: Int,\n) -> Optional[Tuple[Float64, Fl"
        "oat64]]:\n    # PRECONDITION: the caller reserved this complete atte"
        "mpt separately from\n    # any fallback. The metered adapter below s"
        "upplies that admission policy.\n    # The original caller also owns "
        "clamping and the complete count union; this\n    # helper must not s"
        "ilently replace that union with one selected count.\n    if not _sum"
        "2_supported_environment():\n        return None\n    var rate = _spi"
        "ral_grouped_domain_rate(geometry, d, pieces)\n    if not rate:\n    "
        "    return None\n    var rate_value = rate.value()\n    var nodes = "
        "materialize[_GL_NODES]()\n    var weights = materialize[_GL_WEIGHTS]"
        "()\n    # Materialized copies come only from these immutable compile"
        "-time tables.\n    # Reject an incompatible table at compilation, be"
        "fore this helper can run.\n    # The stored pair multiplicities rema"
        "in 2,2,1; no ideal weight sum is used.\n    comptime assert _GL_WEIG"
        "HTS[0] == _GL_WEIGHTS[4]\n    comptime assert _GL_WEIGHTS[1] == _GL_"
        "WEIGHTS[3]\n    comptime assert _GL_WEIGHTS[0] > 0.0 and _GL_WEIGHTS"
        "[0] <= 1.0\n    comptime assert _GL_NODES[0] > -1.0 and _GL_NODES[0]"
        " < 1.0\n    comptime assert _GL_WEIGHTS[1] > 0.0 and _GL_WEIGHTS[1] "
        "<= 1.0\n    comptime assert _GL_NODES[1] > -1.0 and _GL_NODES[1] < 1"
        ".0\n    comptime assert _GL_WEIGHTS[2] > 0.0 and _GL_WEIGHTS[2] <= 1"
        ".0\n    comptime assert _GL_NODES[2] > -1.0 and _GL_NODES[2] < 1.0\n"
        "    comptime assert _GL_WEIGHTS[3] > 0.0 and _GL_WEIGHTS[3] <= 1.0\n"
        "    comptime assert _GL_NODES[3] > -1.0 and _GL_NODES[3] < 1.0\n    "
        "comptime assert _GL_WEIGHTS[4] > 0.0 and _GL_WEIGHTS[4] <= 1.0\n    "
        "comptime assert _GL_NODES[4] > -1.0 and _GL_NODES[4] < 1.0\n    var "
        "node_low = inf[DType.float64]()\n    var node_high = -inf[DType.floa"
        "t64]()\n    for i in range(5):\n        var node = 1.0 + nodes[i]\n "
        "       node_low = min(node_low, node)\n        node_high = max(node_"
        "high, node)\n    var distance = _ValueJet(\n        d.value, _Interv"
        "al.whole(), _Interval.whole(), d.error\n    )\n    var step = distan"
        "ce / _ValueJet.constant(Float64(pieces))\n    var half_step = _store"
        "d_half(step)\n    var half_rate = _stored_half(_ValueJet.constant(ra"
        "te_value))\n    var node_range = _grouped_constant(node_low, node_hi"
        "gh)\n    var phases = Array[_ValueJet, 4](fill=_ValueJet.constant(0."
        "0))\n    # Establish every group's original rounded phase branch bef"
        "ore the first\n    # polynomial evaluation. An ineligible later grou"
        "p cannot waste trig work.\n    for group in range(4):\n        var l"
        "ow = group * pieces // 4\n        var high = (group + 1) * pieces //"
        " 4\n        if low == high:\n            continue\n        var start"
        " = step * _grouped_constant(Float64(low), Float64(high - 1))\n      "
        "  var t = start + half_step * node_range\n        var theta = _Value"
        "Jet.constant(geometry.heading) + t * (\n            _ValueJet.consta"
        "nt(geometry.curvature_start) + half_rate * t\n        )\n        var"
        " phase = theta.rounded_value()\n        if not phase.is_finite() or "
        "phase.magnitude() > _PHASE_LIMIT:\n            return None\n        "
        "var selection = (\n            theta * _ValueJet.constant(_INV_HALF_"
        "PI) + _ValueJet.constant(0.5)\n        ).rounded_value()\n        if"
        " (\n            not selection.is_finite()\n            or floor(sele"
        "ction.low) != 0.0\n            or floor(selection.high) != 0.0\n    "
        "    ):\n            return None\n        phases[group] = theta\n    "
        "var factors = Array[_ValueJet, 3](fill=_ValueJet.constant(0.0))\n   "
        " for weight in range(3):\n        factors[weight] = half_step * _Val"
        "ueJet.constant(weights[weight])\n    var x_ideal = _Interval.point(0"
        ".0)\n    var y_ideal = _Interval.point(0.0)\n    var x_magnitude = _"
        "Interval.point(0.0)\n    var y_magnitude = _Interval.point(0.0)\n   "
        " var x_inherited = _Interval.point(0.0)\n    var y_inherited = _Inte"
        "rval.point(0.0)\n    for group in range(4):\n        var low = group"
        " * pieces // 4\n        var high = (group + 1) * pieces // 4\n      "
        "  if low == high:\n            continue\n        var trig = _sincos_"
        "expression(phases[group])\n        for weight in range(3):\n        "
        "    var multiplicity = 1 if weight == 2 else 2\n            var copi"
        "es = (high - low) * multiplicity\n            var x = factors[weight"
        "] * trig[1]\n            var y = factors[weight] * trig[0]\n        "
        "    if not _grouped_term(x, copies, x_ideal, x_magnitude, x_inherite"
        "d):\n                return None\n            if not _grouped_term(y"
        ", copies, y_ideal, y_magnitude, y_inherited):\n                retur"
        "n None\n    var x_error = _grouped_origin_error(\n        x_ideal, x"
        "_magnitude, x_inherited, 5 * pieces, geometry.x\n    )\n    var y_er"
        "ror = _grouped_origin_error(\n        y_ideal, y_magnitude, y_inheri"
        "ted, 5 * pieces, geometry.y\n    )\n    if not isfinite(x_error) or "
        "not isfinite(y_error):\n        return None\n    return (x_error, y_"
        "error)\n\n\n"
    )


def _spans_28(mut befores: List[String], mut afters: List[String]):
    """Fill one reviewed span-edit table, last edit first.

    Args:
        befores: The predecessor spans.
        afters: The successor spans.
    """
    befores.append(
        "def _try_build_spiral_moments(\n    pieces: Int, mut proof_terms: In"
        "t, max_proof_terms: Int\n) -> Optional[_SpiralMomentProof]:\n    if "
        "not _sum2_supported_environment():\n        return None\n    # This "
        "is a payload-availability ceiling, never a scalar/search count cap."
        "\n    # A caller must invoke generic evaluation whenever this return"
        "s None.\n    if pieces < 1 or pieces > 64:\n        return None\n   "
        " # Conservatively charge one coefficient-node unit per moment per GL"
        " node.\n    # The complete original chord construction runs first. T"
        "he caller supplies\n    # a separate remaining budget no larger than"
        " original_max - original_spent.\n    # Existing construction/query c"
        "ounters and error boundaries are untouched.\n    var work = 22 * 5 *"
        " pieces\n    if proof_terms < 0 or max_proof_terms < proof_terms:\n "
        "       return None\n    if work > max_proof_terms - proof_terms:\n  "
        "      return None\n    proof_terms += work\n    # No optional arrays"
        ", loops, or persistent side-table insertion before debit.\n    var m"
        "oments = Array[_Interval, 22](fill=_Interval.point(0.0))\n    var no"
        "des = materialize[_GL_NODES]()\n    var weights = materialize[_GL_WE"
        "IGHTS]()\n    var divisor = _Interval.point(Float64(pieces))\n    va"
        "r half = _Interval.point(0.5)\n    var weight_sum = _Interval.point("
        "0.0)\n    for i in range(5):\n        weight_sum = _tight_sum_bound("
        "weight_sum, _Interval.point(weights[i]))\n    # Exact cancellation o"
        "f n copies divided by n. Do not substitute 1.0:\n    # the actual st"
        "ored weights, not ideal GL weights, define this polynomial.\n    mom"
        "ents[0] = _tight_product_bound(half, weight_sum)\n    for piece in r"
        "ange(pieces):\n        for i in range(5):\n            # The scalar-"
        "rounded 1.0 + node is deliberately computed BEFORE\n            # ma"
        "king the interval constant, exactly as curve_bounds:116-118.\n      "
        "      var node_sum = 1.0 + nodes[i]\n            var alpha = _tight_"
        "quotient_bound(\n                _tight_sum_bound(\n                "
        "    _Interval.point(Float64(piece)),\n                    _tight_pro"
        "duct_bound(half, _Interval.point(node_sum)),\n                ),\n  "
        "              divisor,\n            )\n            var alpha2 = _tig"
        "ht_product_bound(alpha, alpha)\n            var power = alpha2\n    "
        "        for j in range(1, 22):\n                moments[j] = _tight_"
        "sum_bound(\n                    moments[j],\n                    _ti"
        "ght_product_bound(_Interval.point(weights[i]), power),\n            "
        "    )\n                if j < 21:\n                    power = _tigh"
        "t_product_bound(power, alpha2)\n    var twice_count = _tight_product"
        "_bound(_Interval.point(2.0), divisor)\n    for j in range(1, 22):\n "
        "       moments[j] = _tight_quotient_bound(moments[j], twice_count)\n"
        "    var cos_coefficients = materialize[_COS_COEFFICIENTS]()\n    var"
        " sin_coefficients = materialize[_SIN_COEFFICIENTS]()\n    var cosine"
        " = Array[_Interval, 11](fill=_Interval.point(0.0))\n    var sine = A"
        "rray[_Interval, 11](fill=_Interval.point(0.0))\n    for j in range(1"
        "1):\n        cosine[j] = _tight_product_bound(\n            _Interva"
        "l.point(cos_coefficients[j]), moments[2 * j]\n        )\n        sin"
        "e[j] = _tight_product_bound(\n            _Interval.point(sin_coeffi"
        "cients[j]), moments[2 * j + 1]\n        )\n        if not cosine[j]."
        "is_finite() or not sine[j].is_finite():\n            return None\n  "
        "  return _SpiralMomentProof(pieces, cosine^, sine^)\n\n\n"
    )
    afters.append(
        "def _try_build_spiral_moments(\n    pieces: Int, mut proof_terms: In"
        "t, max_proof_terms: Int\n) -> Optional[_SpiralMomentProof]:\n    if "
        "not _sum2_supported_environment():\n        return None\n    # This "
        "is a payload-availability ceiling, never a scalar/search count cap."
        "\n    # A caller must invoke generic evaluation whenever this return"
        "s None.\n    if pieces < 1 or pieces > 64:\n        return None\n   "
        " # Conservatively charge one coefficient-node unit per moment per GL"
        " node.\n    # The complete original chord construction runs first. T"
        "he caller supplies\n    # a separate remaining budget no larger than"
        " original_max - original_spent.\n    # Existing construction/query c"
        "ounters and error boundaries are untouched.\n    var work = 22 * 5 *"
        " pieces\n    if proof_terms < 0 or max_proof_terms < proof_terms:\n "
        "       return None\n    if work > max_proof_terms - proof_terms:\n  "
        "      return None\n    proof_terms += work\n    # No runtime arrays,"
        " loops, or insertion before debit. These compile-time\n    # bounds "
        "and the admitted count keep every moment intermediate finite.\n    c"
        "omptime for index in range(5):\n        comptime assert _GL_NODES[in"
        "dex] > -1.0 and _GL_NODES[index] < 1.0\n        comptime assert _GL_"
        "WEIGHTS[index] > 0.0 and _GL_WEIGHTS[index] <= 1.0\n    comptime for"
        " index in range(11):\n        comptime assert (\n            _COS_CO"
        "EFFICIENTS[index] >= -1.0 and _COS_COEFFICIENTS[index] <= 1.0\n     "
        "   )\n        comptime assert (\n            _SIN_COEFFICIENTS[index"
        "] >= -1.0 and _SIN_COEFFICIENTS[index] <= 1.0\n        )\n    var mo"
        "ments = Array[_Interval, 22](fill=_Interval.point(0.0))\n    var nod"
        "es = materialize[_GL_NODES]()\n    var weights = materialize[_GL_WEI"
        "GHTS]()\n    var divisor = _Interval.point(Float64(pieces))\n    var"
        " half = _Interval.point(0.5)\n    var weight_sum = _Interval.point(0"
        ".0)\n    for i in range(5):\n        weight_sum = _tight_sum_bound(w"
        "eight_sum, _Interval.point(weights[i]))\n    # Exact cancellation of"
        " n copies divided by n. Do not substitute 1.0:\n    # the actual sto"
        "red weights, not ideal GL weights, define this polynomial.\n    mome"
        "nts[0] = _tight_product_bound(half, weight_sum)\n    for piece in ra"
        "nge(pieces):\n        for i in range(5):\n            # The scalar-r"
        "ounded 1.0 + node is deliberately computed BEFORE\n            # mak"
        "ing the interval constant, exactly as curve_bounds:116-118.\n       "
        "     var node_sum = 1.0 + nodes[i]\n            var alpha = _tight_q"
        "uotient_bound(\n                _tight_sum_bound(\n                 "
        "   _Interval.point(Float64(piece)),\n                    _tight_prod"
        "uct_bound(half, _Interval.point(node_sum)),\n                ),\n   "
        "             divisor,\n            )\n            var alpha2 = _tigh"
        "t_product_bound(alpha, alpha)\n            var power = alpha2\n     "
        "       for j in range(1, 22):\n                moments[j] = _tight_s"
        "um_bound(\n                    moments[j],\n                    _tig"
        "ht_product_bound(_Interval.point(weights[i]), power),\n             "
        "   )\n                if j < 21:\n                    power = _tight"
        "_product_bound(power, alpha2)\n    var twice_count = _tight_product_"
        "bound(_Interval.point(2.0), divisor)\n    for j in range(1, 22):\n  "
        "      moments[j] = _tight_quotient_bound(moments[j], twice_count)\n "
        "   var cos_coefficients = materialize[_COS_COEFFICIENTS]()\n    var "
        "sin_coefficients = materialize[_SIN_COEFFICIENTS]()\n    var cosine "
        "= Array[_Interval, 11](fill=_Interval.point(0.0))\n    var sine = Ar"
        "ray[_Interval, 11](fill=_Interval.point(0.0))\n    for j in range(11"
        "):\n        cosine[j] = _tight_product_bound(\n            _Interval"
        ".point(cos_coefficients[j]), moments[2 * j]\n        )\n        sine"
        "[j] = _tight_product_bound(\n            _Interval.point(sin_coeffic"
        "ients[j]), moments[2 * j + 1]\n        )\n    return _SpiralMomentPr"
        "oof(pieces, cosine^, sine^)\n\n\n"
    )


def _spans_29(mut befores: List[String], mut afters: List[String]):
    """Fill one reviewed span-edit table, last edit first.

    Args:
        befores: The predecessor spans.
        afters: The successor spans.
    """
    befores.append(
        "def _try_spiral_roundoff_envelope(\n    geometry: RoadGeometry, d: _"
        "Jet, pieces: Int\n) -> Optional[Tuple[Float64, Float64]]:\n    # The"
        " caller supplies the original clamped distance Jet and fixed count."
        "\n    # This does not enlarge the existing moment model's heading/k0"
        " domain.\n    if (\n        geometry.kind != SPIRAL\n        or geom"
        "etry.heading != 0.0\n        or geometry.curvature_start != 0.0\n   "
        " ):\n        return None\n    if (\n        pieces < 1\n        or p"
        "ieces > 64\n        or not isfinite(geometry.length)\n        or geo"
        "metry.length <= 0.0\n    ):\n        return None\n    if (\n        "
        "not isfinite(geometry.x)\n        or not isfinite(geometry.y)\n     "
        "   or not isfinite(geometry.curvature_end)\n    ):\n        return N"
        "one\n    var rate_value = (\n        geometry.curvature_end - geomet"
        "ry.curvature_start\n    ) / geometry.length\n    if not isfinite(rat"
        "e_value):\n        return None\n    var domain = d.rounded_value()\n"
        "    if (\n        not domain.is_finite()\n        or domain.low <= 0"
        ".0\n        or domain.high >= geometry.length\n    ):\n        retur"
        "n None\n    if not d.value.is_finite() or not isfinite(d.error) or d"
        ".error < 0.0:\n        return None\n    var distance = _ValueJet(\n "
        "       d.value, _Interval.whole(), _Interval.whole(), d.error\n    )"
        "\n    var nodes = materialize[_GL_NODES]()\n    var weights = materi"
        "alize[_GL_WEIGHTS]()\n    var node_low = 1.0 + nodes[0]\n    var nod"
        "e_high = node_low\n    var weight_low = weights[0]\n    var weight_h"
        "igh = weight_low\n    for i in range(1, 5):\n        var node = 1.0 "
        "+ nodes[i]\n        node_low = min(node_low, node)\n        node_hig"
        "h = max(node_high, node)\n        weight_low = min(weight_low, weigh"
        "ts[i])\n        weight_high = max(weight_high, weights[i])\n    var "
        "step = distance / _ValueJet.constant(Float64(pieces))\n    var start"
        " = step * _envelope_constant(0.0, Float64(pieces - 1))\n    var t = "
        "start + step * _ValueJet.constant(0.5) * _envelope_constant(\n      "
        "  node_low, node_high\n    )\n    var theta = _ValueJet.constant(geo"
        "metry.heading) + t * (\n        _ValueJet.constant(geometry.curvatur"
        "e_start)\n        + _ValueJet.constant(0.5) * _ValueJet.constant(rat"
        "e_value) * t\n    )\n    # The complete original rounded phase-selec"
        "tion graph must select zero.\n    # No ideal beta*d*d estimate repla"
        "ces the node-specific rounding graph.\n    var phase = theta.rounded"
        "_value()\n    if not phase.is_finite() or phase.magnitude() > _PHASE"
        "_LIMIT:\n        return None\n    var selection = (\n        theta *"
        " _ValueJet.constant(_INV_HALF_PI) + _ValueJet.constant(0.5)\n    ).r"
        "ounded_value()\n    if (\n        not selection.is_finite()\n       "
        " or floor(selection.low) != 0.0\n        or floor(selection.high) !="
        " 0.0\n    ):\n        return None\n    var trig = _sincos_expression"
        "(theta)\n    var factor = (\n        step\n        * _ValueJet.const"
        "ant(0.5)\n        * _envelope_constant(weight_low, weight_high)\n   "
        " )\n    var x = factor * trig[1]\n    var y = factor * trig[0]\n    "
        "var x_error = _sum2_envelope_error(x, 5 * pieces, geometry.x)\n    v"
        "ar y_error = _sum2_envelope_error(y, 5 * pieces, geometry.y)\n    if"
        " not isfinite(x_error) or not isfinite(y_error):\n        return Non"
        "e\n    return (x_error, y_error)\n"
    )
    afters.append(
        "def _try_spiral_roundoff_envelope(\n    geometry: RoadGeometry, d: _"
        "Jet, pieces: Int\n) -> Optional[Tuple[Float64, Float64]]:\n    # The"
        " caller supplies the original clamped distance Jet and fixed count."
        "\n    # This does not enlarge the existing moment model's heading/k0"
        " domain.\n    if (\n        geometry.kind != SPIRAL\n        or geom"
        "etry.heading != 0.0\n        or geometry.curvature_start != 0.0\n   "
        " ):\n        return None\n    if (\n        pieces < 1\n        or p"
        "ieces > 64\n        or not isfinite(geometry.length)\n        or geo"
        "metry.length <= 0.0\n    ):\n        return None\n    if (\n        "
        "not isfinite(geometry.x)\n        or not isfinite(geometry.y)\n     "
        "   or not isfinite(geometry.curvature_end)\n    ):\n        return N"
        "one\n    var rate_value = (\n        geometry.curvature_end - geomet"
        "ry.curvature_start\n    ) / geometry.length\n    if not isfinite(rat"
        "e_value):\n        return None\n    var domain = d.rounded_value()\n"
        "    if (\n        not domain.is_finite()\n        or domain.low <= 0"
        ".0\n        or domain.high >= geometry.length\n    ):\n        retur"
        "n None\n    if not d.value.is_finite() or not isfinite(d.error) or d"
        ".error < 0.0:\n        return None\n    var distance = _ValueJet(\n "
        "       d.value, _Interval.whole(), _Interval.whole(), d.error\n    )"
        "\n    var nodes = materialize[_GL_NODES]()\n    var weights = materi"
        "alize[_GL_WEIGHTS]()\n    var node_low = 1.0 + nodes[0]\n    var nod"
        "e_high = node_low\n    var weight_low = weights[0]\n    var weight_h"
        "igh = weight_low\n    for i in range(1, 5):\n        var node = 1.0 "
        "+ nodes[i]\n        node_low = min(node_low, node)\n        node_hig"
        "h = max(node_high, node)\n        weight_low = min(weight_low, weigh"
        "ts[i])\n        weight_high = max(weight_high, weights[i])\n    var "
        "step = distance / _ValueJet.constant(Float64(pieces))\n    var start"
        " = step * _envelope_constant(0.0, Float64(pieces - 1))\n    var t = "
        "start + step * _ValueJet.constant(0.5) * _envelope_constant(\n      "
        "  node_low, node_high\n    )\n    var theta = _ValueJet.constant(geo"
        "metry.heading) + t * (\n        _ValueJet.constant(geometry.curvatur"
        "e_start)\n        + _ValueJet.constant(0.5) * _ValueJet.constant(rat"
        "e_value) * t\n    )\n    # The complete original rounded phase-selec"
        "tion graph must select zero.\n    # No ideal beta*d*d estimate repla"
        "ces the node-specific rounding graph.\n    var phase = theta.rounded"
        "_value()\n    if not phase.is_finite() or phase.magnitude() > _PHASE"
        "_LIMIT:\n        return None\n    var selection = (\n        theta *"
        " _ValueJet.constant(_INV_HALF_PI) + _ValueJet.constant(0.5)\n    ).r"
        "ounded_value()\n    # The ordered theta and nonnegative error are bo"
        "unded by the phase gate.\n    # Multiplication by k<=1 and addition "
        "of 0.5 cannot overflow this selector.\n    comptime assert _INV_HALF"
        "_PI > 0.0 and _INV_HALF_PI <= 1.0\n    comptime assert _PHASE_LIMIT "
        "> 0.0 and _PHASE_LIMIT <= 1048576.0\n    if floor(selection.low) != "
        "0.0 or floor(selection.high) != 0.0:\n        return None\n    var t"
        "rig = _sincos_expression(theta)\n    var factor = (\n        step\n "
        "       * _ValueJet.constant(0.5)\n        * _envelope_constant(weigh"
        "t_low, weight_high)\n    )\n    var x = factor * trig[1]\n    var y "
        "= factor * trig[0]\n    var x_error = _sum2_envelope_error(x, 5 * pi"
        "eces, geometry.x)\n    var y_error = _sum2_envelope_error(y, 5 * pie"
        "ces, geometry.y)\n    if not isfinite(x_error) or not isfinite(y_err"
        "or):\n        return None\n    return (x_error, y_error)\n"
    )


def _spans_30(mut befores: List[String], mut afters: List[String]):
    """Fill one reviewed span-edit table, last edit first.

    Args:
        befores: The predecessor spans.
        afters: The successor spans.
    """
    befores.append(
        "def _spiral_proof_matches(\n    proof: _SpiralDomainProof,\n    geom"
        "etry: RoadGeometry,\n    record_at: Int,\n    low: Float64,\n    hig"
        "h: Float64,\n    root_low: Float64,\n    root_high: Float64,\n    d:"
        " _Jet,\n    counts: Tuple[Int, Int],\n) -> Bool:\n    if record_at !"
        "= proof.record_at or not _spiral_proof_geometry(geometry):\n        "
        "return False\n    if (\n        not isfinite(low)\n        or not is"
        "finite(high)\n        or not isfinite(root_low)\n        or not isfi"
        "nite(root_high)\n        or high < low\n        or root_high < root_"
        "low\n        or low < root_low\n        or high > root_high\n    ):"
        "\n        return False\n    var domain = d.rounded_value()\n    if ("
        "\n        not domain.is_finite()\n        or domain.low <= 0.0\n    "
        "    or domain.high >= geometry.length\n        or not proof.rounded_"
        "d.is_finite()\n        or proof.rounded_d.low <= 0.0\n        or pro"
        "of.rounded_d.high >= geometry.length\n        or proof.rounded_d.hig"
        "h < proof.rounded_d.low\n        or domain.low < proof.rounded_d.low"
        "\n        or domain.high > proof.rounded_d.high\n        or not d.va"
        "lue.is_finite()\n        or not d.first.is_finite()\n        or not "
        "d.second.is_finite()\n    ):\n        return False\n    if counts[0]"
        " < 1 or counts[1] > 64 or counts[1] < counts[0]:\n        return Fal"
        "se\n    if counts[1] - counts[0] > 1:\n        return False\n    if "
        "proof.first_count < 1 or proof.last_count > 64:\n        return Fals"
        "e\n    if (\n        proof.last_count < proof.first_count\n        o"
        "r proof.last_count - proof.first_count > 1\n    ):\n        return F"
        "alse\n    if (\n        not isfinite(proof.first_x_error)\n        o"
        "r proof.first_x_error < 0.0\n        or not isfinite(proof.first_y_e"
        "rror)\n        or proof.first_y_error < 0.0\n        or not isfinite"
        "(proof.last_x_error)\n        or proof.last_x_error < 0.0\n        o"
        "r not isfinite(proof.last_y_error)\n        or proof.last_y_error < "
        "0.0\n    ):\n        return False\n    return counts[0] >= proof.fir"
        "st_count and counts[1] <= proof.last_count\n\n\n"
    )
    afters.append(
        "def _spiral_proof_matches(\n    proof: _SpiralDomainProof,\n    geom"
        "etry: RoadGeometry,\n    record_at: Int,\n    low: Float64,\n    hig"
        "h: Float64,\n    root_low: Float64,\n    root_high: Float64,\n    d:"
        " _Jet,\n    counts: Tuple[Int, Int],\n) -> Bool:\n    if record_at !"
        "= proof.record_at or not _spiral_proof_geometry(geometry):\n        "
        "return False\n    if (\n        not isfinite(low)\n        or not is"
        "finite(high)\n        or not isfinite(root_low)\n        or not isfi"
        "nite(root_high)\n        or high < low\n        or root_high < root_"
        "low\n        or low < root_low\n        or high > root_high\n    ):"
        "\n        return False\n    # These checks do not reconstruct or aut"
        "henticate the caller's Jet.\n    # They reject malformed numeric rep"
        "resentation before using its bounds.\n    if (\n        not d.value."
        "is_finite()\n        or d.value.low > d.value.high\n        or not d"
        ".first.is_finite()\n        or not d.second.is_finite()\n        or "
        "not isfinite(d.error)\n        or d.error < 0.0\n    ):\n        ret"
        "urn False\n    var domain = d.rounded_value()\n    if (\n        not"
        " domain.is_finite()\n        or domain.low <= 0.0\n        or domain"
        ".high >= geometry.length\n        or not proof.rounded_d.is_finite()"
        "\n        or proof.rounded_d.low <= 0.0\n        or proof.rounded_d."
        "high >= geometry.length\n        or proof.rounded_d.high < proof.rou"
        "nded_d.low\n        or domain.low < proof.rounded_d.low\n        or "
        "domain.high > proof.rounded_d.high\n    ):\n        return False\n  "
        "  if counts[0] < 1 or counts[1] > 64 or counts[1] < counts[0]:\n    "
        "    return False\n    if counts[1] - counts[0] > 1:\n        return "
        "False\n    if proof.first_count < 1 or proof.last_count > 64:\n     "
        "   return False\n    if (\n        proof.last_count < proof.first_co"
        "unt\n        or proof.last_count - proof.first_count > 1\n    ):\n  "
        "      return False\n    if (\n        not isfinite(proof.first_x_err"
        "or)\n        or proof.first_x_error < 0.0\n        or not isfinite(p"
        "roof.first_y_error)\n        or proof.first_y_error < 0.0\n        o"
        "r not isfinite(proof.last_x_error)\n        or proof.last_x_error < "
        "0.0\n        or not isfinite(proof.last_y_error)\n        or proof.l"
        "ast_y_error < 0.0\n    ):\n        return False\n    return counts[0"
        "] >= proof.first_count and counts[1] <= proof.last_count\n\n\n"
    )
    befores.append(
        "def _try_pack_spiral_proof(\n    road: Road,\n    low: Float64,\n   "
        " high: Float64,\n    segment_index: Int,\n    captured: _SpiralRootC"
        "apture,\n    proof_count: Int,\n    mut construction_terms: Int,\n  "
        "  mut proof_units: Int,\n    max_terms: Int = 2000000,\n    max_proo"
        "f_units: Int = 1048576,\n    max_payload_bytes: Int = 1048576,\n) ->"
        " Optional[_SpiralDomainProof]:\n    if not _sum2_supported_environme"
        "nt():\n        return None\n    # Logical payload cap, not an alloca"
        "tor-capacity or RSS claim. Check before\n    # any append can grow t"
        "he sparse List. Map appends only a complete result.\n    if captured"
        ".first_count < 1 or captured.last_count > 64:\n        return None\n"
        "    if captured.last_count < captured.first_count:\n        return N"
        "one\n    if captured.last_count - captured.first_count > 1:\n       "
        " return None\n    if segment_index < 0 or proof_count < 0 or max_pay"
        "load_bytes < 80:\n        return None\n    if proof_count >= max_pay"
        "load_bytes // 80:\n        return None\n    # Fixed optional units c"
        "over one/two constant-size phase envelopes and\n    # validation/pac"
        "king. No new GL traversal and no coefficient construction.\n    # Re"
        "serve before the optional arithmetic, after original chord/cover wor"
        "k.\n    var branches = 1 if captured.first_count == captured.last_co"
        "unt else 2\n    var extra = 16 + 128 * branches\n    if construction"
        "_terms < 0 or construction_terms > max_terms:\n        return None\n"
        "    if proof_units < 0 or proof_units > max_proof_units:\n        re"
        "turn None\n    if extra > max_terms - construction_terms:\n        r"
        "eturn None\n    if extra > max_proof_units - proof_units:\n        r"
        "eturn None\n    construction_terms += extra\n    proof_units += extr"
        "a\n    if not isfinite(low) or not isfinite(high) or low < 0.0 or hi"
        "gh < low:\n        return None\n    if low != captured.low or high !"
        "= captured.high:\n        return None\n    var at = info_index(road."
        "info.geometries, low)\n    if at < 0 or at != captured.record_at:\n "
        "       return None\n    if info_index(road.info.geometries, high) !="
        " at:\n        return None\n    ref geometry = road.info.geometries[a"
        "t].geometry\n    if not _spiral_proof_geometry(geometry):\n        r"
        "eturn None\n    var domain = captured.d.rounded_value()\n    if (\n "
        "       not domain.is_finite()\n        or domain.low <= 0.0\n       "
        " or domain.high >= geometry.length\n    ):\n        return None\n   "
        " if (\n        not captured.d.value.is_finite()\n        or not capt"
        "ured.d.first.is_finite()\n        or not captured.d.second.is_finite"
        "()\n    ):\n        return None\n    if (\n        not isfinite(capt"
        "ured.first_x_error)\n        or captured.first_x_error < 0.0\n      "
        "  or not isfinite(captured.first_y_error)\n        or captured.first"
        "_y_error < 0.0\n        or not isfinite(captured.last_x_error)\n    "
        "    or captured.last_x_error < 0.0\n        or not isfinite(captured"
        ".last_y_error)\n        or captured.last_y_error < 0.0\n    ):\n    "
        "    return None\n    if not _all_spiral_nodes_quadrant_zero(\n      "
        "  geometry, captured.d, captured.first_count\n    ):\n        return"
        " None\n    if captured.last_count != captured.first_count:\n        "
        "if not _all_spiral_nodes_quadrant_zero(\n            geometry, captu"
        "red.d, captured.last_count\n        ):\n            return None\n   "
        " return _SpiralDomainProof(\n        segment_index,\n        at,\n  "
        "      domain,\n        captured.first_count,\n        captured.last_"
        "count,\n        captured.first_x_error,\n        captured.first_y_er"
        "ror,\n        captured.last_x_error,\n        captured.last_y_error,"
        "\n    )\n\n\n"
    )
    afters.append(
        "def _try_pack_spiral_proof(\n    road: Road,\n    low: Float64,\n   "
        " high: Float64,\n    segment_index: Int,\n    captured: _SpiralRootC"
        "apture,\n    proof_count: Int,\n    mut construction_terms: Int,\n  "
        "  mut proof_units: Int,\n    max_terms: Int = 2000000,\n    max_proo"
        "f_units: Int = 1048576,\n    max_payload_bytes: Int = 1048576,\n) ->"
        " Optional[_SpiralDomainProof]:\n    if not _sum2_supported_environme"
        "nt():\n        return None\n    # Logical payload cap, not an alloca"
        "tor-capacity or RSS claim. Check before\n    # any append can grow t"
        "he sparse List. Map appends only a complete result.\n    if captured"
        ".first_count < 1 or captured.last_count > 64:\n        return None\n"
        "    if captured.last_count < captured.first_count:\n        return N"
        "one\n    if captured.last_count - captured.first_count > 1:\n       "
        " return None\n    if segment_index < 0 or proof_count < 0 or max_pay"
        "load_bytes < 80:\n        return None\n    if proof_count >= max_pay"
        "load_bytes // 80:\n        return None\n    # Fixed optional units c"
        "over one/two constant-size phase envelopes and\n    # validation/pac"
        "king. No new GL traversal and no coefficient construction.\n    # Re"
        "serve before the optional arithmetic, after original chord/cover wor"
        "k.\n    var branches = 1 if captured.first_count == captured.last_co"
        "unt else 2\n    var extra = 16 + 128 * branches\n    if construction"
        "_terms < 0 or construction_terms > max_terms:\n        return None\n"
        "    if proof_units < 0 or proof_units > max_proof_units:\n        re"
        "turn None\n    if extra > max_terms - construction_terms:\n        r"
        "eturn None\n    if extra > max_proof_units - proof_units:\n        r"
        "eturn None\n    construction_terms += extra\n    proof_units += extr"
        "a\n    if not isfinite(low) or not isfinite(high) or low < 0.0 or hi"
        "gh < low:\n        return None\n    if low != captured.low or high !"
        "= captured.high:\n        return None\n    var at = info_index(road."
        "info.geometries, low)\n    if at < 0 or at != captured.record_at:\n "
        "       return None\n    if info_index(road.info.geometries, high) !="
        " at:\n        return None\n    ref geometry = road.info.geometries[a"
        "t].geometry\n    if not _spiral_proof_geometry(geometry):\n        r"
        "eturn None\n    # Validate distance representation before interval a"
        "rithmetic. Capture\n    # provenance and association still remain ca"
        "ller-owned preconditions.\n    if (\n        not captured.d.value.is"
        "_finite()\n        or captured.d.value.low > captured.d.value.high\n"
        "        or not captured.d.first.is_finite()\n        or not captured"
        ".d.second.is_finite()\n        or not isfinite(captured.d.error)\n  "
        "      or captured.d.error < 0.0\n    ):\n        return None\n    va"
        "r domain = captured.d.rounded_value()\n    if (\n        not domain."
        "is_finite()\n        or domain.low <= 0.0\n        or domain.high >="
        " geometry.length\n    ):\n        return None\n    if (\n        not"
        " isfinite(captured.first_x_error)\n        or captured.first_x_error"
        " < 0.0\n        or not isfinite(captured.first_y_error)\n        or "
        "captured.first_y_error < 0.0\n        or not isfinite(captured.last_"
        "x_error)\n        or captured.last_x_error < 0.0\n        or not isf"
        "inite(captured.last_y_error)\n        or captured.last_y_error < 0.0"
        "\n    ):\n        return None\n    if not _all_spiral_nodes_quadrant"
        "_zero(\n        geometry, captured.d, captured.first_count\n    ):\n"
        "        return None\n    if captured.last_count != captured.first_co"
        "unt:\n        if not _all_spiral_nodes_quadrant_zero(\n            g"
        "eometry, captured.d, captured.last_count\n        ):\n            re"
        "turn None\n    return _SpiralDomainProof(\n        segment_index,\n "
        "       at,\n        domain,\n        captured.first_count,\n        "
        "captured.last_count,\n        captured.first_x_error,\n        captu"
        "red.first_y_error,\n        captured.last_x_error,\n        captured"
        ".last_y_error,\n    )\n\n\n"
    )


def restored_winner_pins(
    mut paths: List[String], mut texts: List[String]
) raises:
    """Restore each reviewed winner pin from its live file.

    Args:
        paths: The consumer paths.
        texts: The restored source for each path.

    Raises:
        Error: A live file or a restored pin changed.
    """
    var starts = List[Int]()
    var stops = List[Int]()
    var befores = List[String]()
    var afters = List[String]()
    var live_0 = Path("extensions/carla/assets.mojo").read_text()
    _require(
        live_0,
        "b051a911885031a06eee4a609ce030ea8629f0ab09e0f12308d89c009e8bde8d",
        "extensions/carla/assets.mojo",
    )
    starts.clear()
    stops.clear()
    befores.clear()
    _lines_0(starts, stops, befores)
    var text_0_0 = _apply(live_0, starts, stops, befores)
    _require(
        text_0_0,
        "0bb273644a6d6cffaad986236e8aaafe9355549b37a10289cd9b14555f4e1acc",
        "extensions/carla/assets.mojo",
    )
    paths.append("extensions/carla/assets.mojo")
    texts.append(text_0_0)

    var live_1 = Path("extensions/carla/curve_bounds.mojo").read_text()
    _require(
        live_1,
        "17cfb28e3a1f49857173331942e4545030328a0d37eaf41c23b5108fb1422214",
        "extensions/carla/curve_bounds.mojo",
    )
    starts.clear()
    stops.clear()
    befores.clear()
    _lines_1(starts, stops, befores)
    var text_1_0 = _apply(live_1, starts, stops, befores)
    _require(
        text_1_0,
        "48dc6f87cd9ad4da1b16c5781fd7b7994f8394198a0d8c7ab6cdc5e0f142f19b",
        "extensions/carla/curve_bounds.mojo",
    )
    befores.clear()
    afters.clear()
    _spans_2(befores, afters)
    var text_1_1 = _replace_spans(
        text_1_0, befores, afters, "extensions/carla/curve_bounds.mojo"
    )
    _require(
        text_1_1,
        "a5f662df6bc146010b065341143c75223151289dc0cc633590d96b0a199ab8f5",
        "extensions/carla/curve_bounds.mojo",
    )
    befores.clear()
    afters.clear()
    _spans_3(befores, afters)
    var text_1_2 = _replace_spans(
        text_1_1, befores, afters, "extensions/carla/curve_bounds.mojo"
    )
    _require(
        text_1_2,
        "a57a5fa078fc6f36389a0abdce1eaa483a1cb7b7325688689a5602e8680ca3fb",
        "extensions/carla/curve_bounds.mojo",
    )
    befores.clear()
    afters.clear()
    _spans_4(befores, afters)
    var text_1_3 = _replace_spans(
        text_1_2, befores, afters, "extensions/carla/curve_bounds.mojo"
    )
    _require(
        text_1_3,
        "86ed709bdf9f75b0805754ed15f42fa80e13ee399eab56d91a14181679918e6d",
        "extensions/carla/curve_bounds.mojo",
    )
    paths.append("extensions/carla/curve_bounds.mojo")
    texts.append(text_1_3)

    var live_2 = Path("extensions/carla/curve_distance.mojo").read_text()
    _require(
        live_2,
        "e349b4b9f7bdb417d84a9451d769c59f7ce1285a6ac99d887722dbc0ff1466e3",
        "extensions/carla/curve_distance.mojo",
    )
    befores.clear()
    afters.clear()
    _spans_5(befores, afters)
    var text_2_0 = _replace_spans(
        live_2, befores, afters, "extensions/carla/curve_distance.mojo"
    )
    _require(
        text_2_0,
        "46176387129dd37a5887f3aeec7c96bbb386e4980063cb96f09619832cb09a79",
        "extensions/carla/curve_distance.mojo",
    )
    paths.append("extensions/carla/curve_distance.mojo")
    texts.append(text_2_0)

    var live_3 = Path(
        "extensions/carla/curve_minimizer_support.mojo"
    ).read_text()
    _require(
        live_3,
        "bdf79d12f2b3b784574fbd95e2e773ddeb29eb9586cf826c2b6142646341292e",
        "extensions/carla/curve_minimizer_support.mojo",
    )
    starts.clear()
    stops.clear()
    befores.clear()
    _lines_6(starts, stops, befores)
    var text_3_0 = _apply(live_3, starts, stops, befores)
    _require(
        text_3_0,
        "8ba1e7f7964af7bcfa8cad21e857fcb67ee92918c58d44ed36767b843095a260",
        "extensions/carla/curve_minimizer_support.mojo",
    )
    paths.append("extensions/carla/curve_minimizer_support.mojo")
    texts.append(text_3_0)

    var live_4 = Path("extensions/carla/lane_refinement.mojo").read_text()
    _require(
        live_4,
        "deaa26a8d0838a812be85629a1b6066485840166688ed9c38dbbaafc72fc6731",
        "extensions/carla/lane_refinement.mojo",
    )
    starts.clear()
    stops.clear()
    befores.clear()
    _lines_7(starts, stops, befores)
    var text_4_0 = _apply(live_4, starts, stops, befores)
    _require(
        text_4_0,
        "13ae6d4658458a7d243597428eee762f9bbc40f8fe3507a47beac9ebd4ac1737",
        "extensions/carla/lane_refinement.mojo",
    )
    befores.clear()
    afters.clear()
    _spans_8(befores, afters)
    var text_4_1 = _replace_spans(
        text_4_0, befores, afters, "extensions/carla/lane_refinement.mojo"
    )
    _require(
        text_4_1,
        "d6bb8cb266fa350491f71e92295e70bcbfc2566b34db02400b3a6cb5bb5a93ad",
        "extensions/carla/lane_refinement.mojo",
    )
    befores.clear()
    afters.clear()
    _spans_9(befores, afters)
    var text_4_2 = _replace_spans(
        text_4_1, befores, afters, "extensions/carla/lane_refinement.mojo"
    )
    _require(
        text_4_2,
        "13afed281e9df7549d3acb022680e2e20a57ea54411817eed6f45bf9042e5938",
        "extensions/carla/lane_refinement.mojo",
    )
    starts.clear()
    stops.clear()
    befores.clear()
    _lines_10(starts, stops, befores)
    var text_4_3 = _apply(text_4_2, starts, stops, befores)
    _require(
        text_4_3,
        "b607c75982a15122dd8f3de743e48ec66e71f027cb5dd034b459dc46602c5c3e",
        "extensions/carla/lane_refinement.mojo",
    )
    starts.clear()
    stops.clear()
    befores.clear()
    _lines_11(starts, stops, befores)
    var text_4_4 = _apply(text_4_3, starts, stops, befores)
    _require(
        text_4_4,
        "33d33ba0e481e3eca3b17ae0d02457ab53bae906430b0dca58abcfa876756315",
        "extensions/carla/lane_refinement.mojo",
    )
    paths.append("extensions/carla/lane_refinement.mojo")
    texts.append(text_4_4)

    var live_5 = Path("extensions/carla/lane_value_bounds.mojo").read_text()
    _require(
        live_5,
        "de7a981e6bc56a3e22a75cbc4638882d1e51550322bd87e1f9aa93fa56d32f21",
        "extensions/carla/lane_value_bounds.mojo",
    )
    starts.clear()
    stops.clear()
    befores.clear()
    _lines_12(starts, stops, befores)
    var text_5_0 = _apply(live_5, starts, stops, befores)
    _require(
        text_5_0,
        "548ca38dd3bb9ecd8fe8a69cce91f2312c9a2493e4fe7925b609a3d64cb44082",
        "extensions/carla/lane_value_bounds.mojo",
    )
    befores.clear()
    afters.clear()
    _spans_13(befores, afters)
    var text_5_1 = _replace_spans(
        text_5_0, befores, afters, "extensions/carla/lane_value_bounds.mojo"
    )
    _require(
        text_5_1,
        "9028d65fdcb680ec5363f7fc974d8d46532b0f50397d7a348fc16e33821f4121",
        "extensions/carla/lane_value_bounds.mojo",
    )
    befores.clear()
    afters.clear()
    _spans_14(befores, afters)
    var text_5_2 = _replace_spans(
        text_5_1, befores, afters, "extensions/carla/lane_value_bounds.mojo"
    )
    _require(
        text_5_2,
        "08978a7aa665aca4b82d41e1ff8b99451c647c0f8e7d6ee010fc6a6143f7959c",
        "extensions/carla/lane_value_bounds.mojo",
    )
    paths.append("extensions/carla/lane_value_bounds.mojo")
    texts.append(text_5_2)

    var live_6 = Path("extensions/carla/model_cache.mojo").read_text()
    _require(
        live_6,
        "6c95fe4a1e5218f26dac0c9889e2246d53ec620cebb1230166a184bbe8af93a9",
        "extensions/carla/model_cache.mojo",
    )
    starts.clear()
    stops.clear()
    befores.clear()
    _lines_15(starts, stops, befores)
    var text_6_0 = _apply(live_6, starts, stops, befores)
    _require(
        text_6_0,
        "a5832785f758cd6fe99f32cfa04b90399ebfcd4c9ffdf1e286f79c613cb1cd91",
        "extensions/carla/model_cache.mojo",
    )
    paths.append("extensions/carla/model_cache.mojo")
    texts.append(text_6_0)

    var live_7 = Path("extensions/carla/polynomial.mojo").read_text()
    _require(
        live_7,
        "f04c9195616d9aebe3371d0e10daf44856231931af020770916b52221e121d79",
        "extensions/carla/polynomial.mojo",
    )
    starts.clear()
    stops.clear()
    befores.clear()
    _lines_16(starts, stops, befores)
    var text_7_0 = _apply(live_7, starts, stops, befores)
    _require(
        text_7_0,
        "7eadcab8f9148a50644fa9bc9d12affcda8e3361f03151cb4595c6eba257ad07",
        "extensions/carla/polynomial.mojo",
    )
    befores.clear()
    afters.clear()
    _spans_17(befores, afters)
    var text_7_1 = _replace_spans(
        text_7_0, befores, afters, "extensions/carla/polynomial.mojo"
    )
    _require(
        text_7_1,
        "ccbb296800e9b493b0617506b05e51d7ed6ee8ea594b9460bb6c7ff359a0d354",
        "extensions/carla/polynomial.mojo",
    )
    paths.append("extensions/carla/polynomial.mojo")
    texts.append(text_7_1)

    var live_8 = Path("extensions/carla/render_sky.mojo").read_text()
    _require(
        live_8,
        "19e9c8493ffe16a79d24238b480be0904d8ccd490bcee0435554932b5897bff3",
        "extensions/carla/render_sky.mojo",
    )
    befores.clear()
    afters.clear()
    _spans_18(befores, afters)
    var text_8_0 = _replace_spans(
        live_8, befores, afters, "extensions/carla/render_sky.mojo"
    )
    _require(
        text_8_0,
        "4b99faa687940af925a5cedd09d33d7b44dd7e317f892a1be269ccd8deaedaa7",
        "extensions/carla/render_sky.mojo",
    )
    paths.append("extensions/carla/render_sky.mojo")
    texts.append(text_8_0)

    var live_9 = Path("extensions/carla/render_weather.mojo").read_text()
    _require(
        live_9,
        "4f6fbd3dd6597a05900dd64a4dcc799f2e9ffed0b22be63bc96c2d0a6f1822c4",
        "extensions/carla/render_weather.mojo",
    )
    befores.clear()
    afters.clear()
    _spans_19(befores, afters)
    var text_9_0 = _replace_spans(
        live_9, befores, afters, "extensions/carla/render_weather.mojo"
    )
    _require(
        text_9_0,
        "5e2c6ed0db903e2c1dd484d73a100cfb816562655722c69e8461d1079d178460",
        "extensions/carla/render_weather.mojo",
    )
    paths.append("extensions/carla/render_weather.mojo")
    texts.append(text_9_0)

    var live_10 = Path("extensions/carla/road.mojo").read_text()
    _require(
        live_10,
        "a53c48d28b33fb4f5f26316be902e57607a56012edb5f0b025241df1c0092b04",
        "extensions/carla/road.mojo",
    )
    starts.clear()
    stops.clear()
    befores.clear()
    _lines_20(starts, stops, befores)
    var text_10_0 = _apply(live_10, starts, stops, befores)
    _require(
        text_10_0,
        "4e5857371a9de89c6e41f74e3cdc421760be45603446dd2b2a471f22b53dfd0c",
        "extensions/carla/road.mojo",
    )
    befores.clear()
    afters.clear()
    _spans_21(befores, afters)
    var text_10_1 = _replace_spans(
        text_10_0, befores, afters, "extensions/carla/road.mojo"
    )
    _require(
        text_10_1,
        "d9b6f60ae0b0b2fe38ef8dbe797a759f3de5e72dc8fb97bff15ca5dfff251db0",
        "extensions/carla/road.mojo",
    )
    paths.append("extensions/carla/road.mojo")
    texts.append(text_10_1)

    var live_11 = Path("extensions/carla/sensor.mojo").read_text()
    _require(
        live_11,
        "3dab708ddf17d214821eee9aaf40fce3da8583f602c86bd058da5d3f016ea12b",
        "extensions/carla/sensor.mojo",
    )
    starts.clear()
    stops.clear()
    befores.clear()
    _lines_22(starts, stops, befores)
    var text_11_0 = _apply(live_11, starts, stops, befores)
    _require(
        text_11_0,
        "e20a4f8341d36615682dd1820a7a1587ebf32aeabac402b36d0646f277239f75",
        "extensions/carla/sensor.mojo",
    )
    paths.append("extensions/carla/sensor.mojo")
    texts.append(text_11_0)

    var live_12 = Path("extensions/carla/speed_limits.mojo").read_text()
    _require(
        live_12,
        "2d9d5401b3dabf53c1c19f0a8098009275e19edb978f5ae369596fe7ac6557a0",
        "extensions/carla/speed_limits.mojo",
    )
    starts.clear()
    stops.clear()
    befores.clear()
    _lines_23(starts, stops, befores)
    var text_12_0 = _apply(live_12, starts, stops, befores)
    _require(
        text_12_0,
        "1e95ebc085e03a44e4daaef20a94b724dedc4240a2099227e82be54d32b045f6",
        "extensions/carla/speed_limits.mojo",
    )
    starts.clear()
    stops.clear()
    befores.clear()
    _lines_24(starts, stops, befores)
    var text_12_1 = _apply(text_12_0, starts, stops, befores)
    _require(
        text_12_1,
        "5cb2e3393283dcfecd9fba2e795db7ddcfb2e32e123889cf1ea237feafc44fee",
        "extensions/carla/speed_limits.mojo",
    )
    paths.append("extensions/carla/speed_limits.mojo")
    texts.append(text_12_1)

    var live_13 = Path(
        "extensions/carla/spiral_grouped_roundoff_proof.mojo"
    ).read_text()
    _require(
        live_13,
        "ab0016a54e8a0d2d2dc8235e5954c111f1738ce08868d1c6fc30d454811d7a57",
        "extensions/carla/spiral_grouped_roundoff_proof.mojo",
    )
    starts.clear()
    stops.clear()
    befores.clear()
    _lines_25(starts, stops, befores)
    var text_13_0 = _apply(live_13, starts, stops, befores)
    _require(
        text_13_0,
        "cb1ebdc6a6eb7b1967c431cfc94b68a0ddff89bd5b2e37ca97608a0aa3115454",
        "extensions/carla/spiral_grouped_roundoff_proof.mojo",
    )
    befores.clear()
    afters.clear()
    _spans_26(befores, afters)
    var text_13_1 = _replace_spans(
        text_13_0,
        befores,
        afters,
        "extensions/carla/spiral_grouped_roundoff_proof.mojo",
    )
    _require(
        text_13_1,
        "0e42c79e3bbda283c32886e50ad8b1acd614f651f1d258f4ea4b5e4e0e139299",
        "extensions/carla/spiral_grouped_roundoff_proof.mojo",
    )
    befores.clear()
    afters.clear()
    _spans_27(befores, afters)
    var text_13_2 = _replace_spans(
        text_13_1,
        befores,
        afters,
        "extensions/carla/spiral_grouped_roundoff_proof.mojo",
    )
    _require(
        text_13_2,
        "8bb7c5cc0c5c211ae420a3c7329d1a13771f18ef3d89e0d9989b030c0a2b9098",
        "extensions/carla/spiral_grouped_roundoff_proof.mojo",
    )
    paths.append("extensions/carla/spiral_grouped_roundoff_proof.mojo")
    texts.append(text_13_2)

    var live_14 = Path("extensions/carla/spiral_moment_proof.mojo").read_text()
    _require(
        live_14,
        "f42f436b6e616e39bc2cda70491abf2e441aa40d5d8d1aa7f7ecffe3d0b0d5ac",
        "extensions/carla/spiral_moment_proof.mojo",
    )
    befores.clear()
    afters.clear()
    _spans_28(befores, afters)
    var text_14_0 = _replace_spans(
        live_14, befores, afters, "extensions/carla/spiral_moment_proof.mojo"
    )
    _require(
        text_14_0,
        "2771e2f9fc9ee1768707b2f03475309d81a066c6be2d8bd27233001c6d09d1ec",
        "extensions/carla/spiral_moment_proof.mojo",
    )
    paths.append("extensions/carla/spiral_moment_proof.mojo")
    texts.append(text_14_0)

    var live_15 = Path(
        "extensions/carla/spiral_roundoff_proof.mojo"
    ).read_text()
    _require(
        live_15,
        "66903c0cfba3315c46e8f48c9af0b3c118db4194236a7e4fe3e893a986c90b0c",
        "extensions/carla/spiral_roundoff_proof.mojo",
    )
    befores.clear()
    afters.clear()
    _spans_29(befores, afters)
    var text_15_0 = _replace_spans(
        live_15, befores, afters, "extensions/carla/spiral_roundoff_proof.mojo"
    )
    _require(
        text_15_0,
        "380d8130fd2f18dd93768ed0e7ffb17a45e7b1631a81fbd0f68de1f08fe16ec7",
        "extensions/carla/spiral_roundoff_proof.mojo",
    )
    paths.append("extensions/carla/spiral_roundoff_proof.mojo")
    texts.append(text_15_0)


def restored_domain_winner(text: String) raises -> String:
    """Restore the spiral-domain winner pin from its border text.

    Args:
        text: The border pin for `extensions/carla/spiral_domain_proof.mojo`.

    Returns:
        The winner pin source.

    Raises:
        Error: The border text or the restored pin changed.
    """
    _require(
        text,
        "89a8760eee14ff17c682ac69657eb62391e5dfd7e6e1e11fa8a931f8595e9252",
        "extensions/carla/spiral_domain_proof.mojo",
    )
    var befores = List[String]()
    var afters = List[String]()
    _spans_30(befores, afters)
    var restored = _replace_spans(
        text, befores, afters, "extensions/carla/spiral_domain_proof.mojo"
    )
    _require(
        restored,
        "da466aa7bec7e6c87fb1e29472e1f28169e7a369e7a1afbdc841f5994276b8e5",
        "extensions/carla/spiral_domain_proof.mojo",
    )
    return restored


def _lines_31(
    mut starts: List[Int], mut stops: List[Int], mut befores: List[String]
):
    """Fill one reviewed line-edit table, highest line first.

    Args:
        starts: The 0-based start lines.
        stops: The exclusive end lines.
        befores: The predecessor lines for each span.
    """
    starts.append(46)
    stops.append(62)
    befores.append(
        "    var word = bitcast[DType.uint64](start)\n    for i in range(3):"
        "\n        var bits = word + UInt64(i)\n        if bits >= UInt64(0x7"
        "FF0000000000000):\n            return None\n        var cut = bitcas"
        "t[DType.float64](bits)\n        var before = bitcast[DType.float64]("
        "bits - UInt64(1))\n        if _sample_dispatch_predicate(\n         "
        "   origin, length, local, cut\n        ) and not _sample_dispatch_pr"
        "edicate(origin, length, local, before):\n            return cut\n   "
        " return None\n"
    )
    starts.append(7)
    stops.append(10)
    befores.append(
        "A cut is admitted only after its actual stored subtraction/clamp pre"
        "dicate\nis true and its immediate predecessor's predicate is false. "
        "The short probe\nis optional; all unsupported or unbracketed cases r"
        "etain the original solver.\n"
    )


def _lines_32(
    mut starts: List[Int], mut stops: List[Int], mut befores: List[String]
):
    """Fill one reviewed line-edit table, highest line first.

    Args:
        starts: The 0-based start lines.
        stops: The exclusive end lines.
        befores: The predecessor lines for each span.
    """
    starts.append(130)
    stops.append(132)
    befores.append("        if station <= low or station > high:\n")
    starts.append(123)
    stops.append(124)
    befores.append(
        "        if threshold_at < 1 or threshold_at >= len(geometry.samples)"
        " - 1:\n            return None\n"
    )


def restored_dispatch_winner(text: String) raises -> String:
    """Restore the sample-dispatch winner pin from its border text.

    Args:
        text: The border pin for `extensions/carla/curve_sample_dispatch.mojo`.

    Returns:
        The winner pin source.

    Raises:
        Error: The border text or the restored pin changed.
    """
    _require(
        text,
        "91ede65bbc39ac57ca54239513b462d3c71e90cacd085b8bafb2bff514767a86",
        "extensions/carla/curve_sample_dispatch.mojo",
    )
    var starts = List[Int]()
    var stops = List[Int]()
    var befores = List[String]()
    _lines_31(starts, stops, befores)
    var mid = _apply(text, starts, stops, befores)
    _require(
        mid,
        "ee6f220ae3d8f5b2192abc63f993d1f1375528e2b60cec78544de8c9eb11d259",
        "extensions/carla/curve_sample_dispatch.mojo",
    )
    starts.clear()
    stops.clear()
    befores.clear()
    _lines_32(starts, stops, befores)
    var restored = _apply(mid, starts, stops, befores)
    _require(
        restored,
        "2a74be6de0d0a35f2b17f60280747e42f91c083ebb922ded0ae0b13febe55631",
        "extensions/carla/curve_sample_dispatch.mojo",
    )
    return restored


def _lines_33(
    mut starts: List[Int], mut stops: List[Int], mut befores: List[String]
):
    """Fill one reviewed line-edit table, highest line first.

    Args:
        starts: The 0-based start lines.
        stops: The exclusive end lines.
        befores: The predecessor lines for each span.
    """
    starts.append(21)
    stops.append(22)
    befores.append("from extensions.carla.road_info import info_index\n")


def _lines_34(
    mut starts: List[Int], mut stops: List[Int], mut befores: List[String]
):
    """Fill one reviewed line-edit table, highest line first.

    Args:
        starts: The 0-based start lines.
        stops: The exclusive end lines.
        befores: The predecessor lines for each span.
    """
    starts.append(142)
    stops.append(143)
    befores.append(
        "    if y.low == y.high and cosine.low != 0.0:\n"
        "        return _RoundedLineAxis(0, cosine.low)\n"
        "    if x.low == x.high and sine.low != 0.0:\n"
        "        return _RoundedLineAxis(1, -sine.low)\n"
        "    return None\n"
    )
    starts.append(135)
    stops.append(137)
    befores.append(
        "    if not (x.known and y.known and elevation.low =="
        " elevation.high):\n"
    )
    starts.append(126)
    stops.append(127)
    befores.append("    if not d.known:\n        return None\n")
    starts.append(115)
    stops.append(117)
    befores.append("    if not offset.known or offset.low != offset.high:\n")
    starts.append(28)
    stops.append(49)
    befores.append("")


def restored_rounded_line_winner() raises -> String:
    """Restore the rounded-line winner pin from the live file.

    Returns:
        The winner pin source.

    Raises:
        Error: The live file or a restored pin changed.
    """
    var path = "extensions/carla/curve_rounded_line.mojo"
    var live = Path(path).read_text()
    _require(
        live,
        "22b70ec9febc6f3d21a8a4d9f1a74650d676e34782fab2812004a1a3aadeb698",
        path,
    )
    var starts = List[Int]()
    var stops = List[Int]()
    var befores = List[String]()
    _lines_33(starts, stops, befores)
    var border = _apply(live, starts, stops, befores)
    _require(
        border,
        "6741ad9d7434c08070de3c959cb49ac42939ac633d1dcd48c9f5cdfdaa719aed",
        path,
    )
    starts.clear()
    stops.clear()
    befores.clear()
    _lines_34(starts, stops, befores)
    var mid = _apply(border, starts, stops, befores)
    _require(
        mid,
        "aeb7b6722b223493d9a86422a17500be9c68d1b7d3de8bd441795001dc513f35",
        path,
    )
    var restored = _replace_once(
        mid,
        (
            "    if (\n"
            "        info_index(road.info.geometries, low) != 0\n"
            "        or info_index(road.info.geometries, high) != 0\n"
            "    ):\n"
            "        return None\n"
        ),
        (
            "    # One record active at low also covers high: the domain is"
            " ordered.\n"
            "    if info_index(road.info.geometries, low) != 0:\n"
            "        return None\n"
        ),
        path,
    )
    _require(
        restored,
        "af00f76f66323ce85b0f794cbe7162d63e6db864c49a052827f565c2332383ec",
        path,
    )
    return restored


def _lines_35(
    mut starts: List[Int], mut stops: List[Int], mut befores: List[String]
):
    """Fill one reviewed line-edit table, highest line first.

    Args:
        starts: The 0-based start lines.
        stops: The exclusive end lines.
        befores: The predecessor lines for each span.
    """
    starts.append(20)
    stops.append(21)
    befores.append("from extensions.carla.road_info import info_index\n")


def _lines_36(
    mut starts: List[Int], mut stops: List[Int], mut befores: List[String]
):
    """Fill one reviewed line-edit table, highest line first.

    Args:
        starts: The 0-based start lines.
        stops: The exclusive end lines.
        befores: The predecessor lines for each span.
    """
    starts.append(237)
    stops.append(238)
    befores.append(
        "            if info_index(widths, low) != 0 or info_index(widths, hi"
        "gh) != 0:\n"
    )
    starts.append(215)
    stops.append(215)
    befores.append("        or info_index(road.info.elevations, high) != 0\n")
    starts.append(214)
    stops.append(214)
    befores.append("        or info_index(road.info.lane_offsets, high) != 0\n")
    starts.append(209)
    stops.append(209)
    befores.append(
        "        return None\n    if info_index(road.info.geometries, high) !"
        "= 0:\n"
    )
    starts.append(207)
    stops.append(208)
    befores.append("")
    starts.append(179)
    stops.append(180)
    befores.append(
        "        if max(abs(half.low), abs(half.high)) > _QUARTER_PI:\n      "
        "      return [unknown, unknown, unknown]\n"
    )
    starts.append(15)
    stops.append(15)
    befores.append("    _QUARTER_PI,\n")


def restored_rounded_arc_winner() raises -> String:
    """Restore the rounded-arc winner pin from the live file.

    Returns:
        The winner pin source.

    Raises:
        Error: The live file or a restored pin changed.
    """
    var path = "extensions/carla/curve_rounded_arc.mojo"
    var live = Path(path).read_text()
    _require(
        live,
        "f17bf9a6a744971ea6e792a24b27d6157691e70d50c438880abcf88db2a9123d",
        path,
    )
    var starts = List[Int]()
    var stops = List[Int]()
    var befores = List[String]()
    _lines_35(starts, stops, befores)
    var mid = _apply(live, starts, stops, befores)
    _require(
        mid,
        "d6fbdb466f9e1641f8d3317d03035732883775adfdc46a7913a96178feeb85ec",
        path,
    )
    var earlier = (
        "\n\ndef _rounded_constant(polynomial: CubicPolynomial) -> _RoundedBo"
        "x:\n    if polynomial.b != 0.0 or polynomial.c != 0.0 or polynomial."
        "d != 0.0:\n        return _RoundedBox.unknown()\n    # For finite s,"
        " all variable terms are exact zero in either graph.\n    return _Rou"
        "ndedBox.point(polynomial.a)\n\n\n"
    )
    var later = (
        "\n\ndef _rounded_constant(polynomial: CubicPolynomial) -> _RoundedBo"
        "x:\n    if (\n        not _rounded_operand(polynomial.s)\n        or"
        " polynomial.b != 0.0\n        or polynomial.c != 0.0\n        or pol"
        "ynomial.d != 0.0\n    ):\n        return _RoundedBox.unknown()\n    "
        "# The query station and the stored origin must both fit the supporte"
        "d\n    # operand range. Their difference is finite, so every variabl"
        "e term\n    # is exact zero in the conditioned graph.\n    return _R"
        "oundedBox.point(polynomial.a)\n\n\n"
    )
    var reached = _replace_once(mid, earlier, later, path)
    _require(
        reached,
        "7bc84049fed26cb7b14b4fa4603ee36d55cdeb7055c62df50cf10d6a2ce90745",
        path,
    )
    starts.clear()
    stops.clear()
    befores.clear()
    _lines_36(starts, stops, befores)
    var restored = _apply(reached, starts, stops, befores)
    _require(
        restored,
        "83b4f7620b96860af672f18052b2642d4fb3ab553a58cf7ace15a4616eba396e",
        path,
    )
    return restored


def _lines_37(
    mut starts: List[Int], mut stops: List[Int], mut befores: List[String]
):
    """Fill one reviewed line-edit table, highest line first.

    Args:
        starts: The 0-based start lines.
        stops: The exclusive end lines.
        befores: The predecessor lines for each span.
    """
    starts.append(43)
    stops.append(44)
    befores.append(
        "    for coefficient in [\n        model.start,\n        model.cu"
        "rvature,\n        model.speed,\n        model.x,\n        model."
        "y,\n        model.z,\n    ]:\n        if not coefficient.known o"
        "r coefficient.low != coefficient.high:\n            return None"
        "\n"
    )


def _lines_38(
    mut starts: List[Int], mut stops: List[Int], mut befores: List[String]
):
    """Fill one reviewed line-edit table, highest line first.

    Args:
        starts: The 0-based start lines.
        stops: The exclusive end lines.
        befores: The predecessor lines for each span.
    """
    starts.append(193)
    stops.append(194)
    befores.append(
        "        return LaneInvasionEvent(frame, timestamp.value, transfo"
        "rm, crossed^)\n"
    )
    starts.append(105)
    stops.append(127)
    befores.append("")
    starts.append(102)
    stops.append(103)
    befores.append("        self.timestamp = timestamp\n")
    starts.append(97)
    stops.append(100)
    befores.append("")
    starts.append(94)
    stops.append(95)
    befores.append("            timestamp: The snapshot's elapsed seconds.\n")
    starts.append(89)
    stops.append(91)
    befores.append('    ):\n        """Create an event.\n')
    starts.append(86)
    stops.append(87)
    befores.append("        timestamp: Float64,\n")
    starts.append(77)
    stops.append(78)
    befores.append("")
    starts.append(70)
    stops.append(75)
    befores.append(
        '    """The markings a vehicle crossed in one tick, `LaneInvas'
        'ionEvent`."""\n'
    )


def _lines_39(
    mut starts: List[Int], mut stops: List[Int], mut befores: List[String]
):
    """Fill one reviewed line-edit table, highest line first.

    Args:
        starts: The 0-based start lines.
        stops: The exclusive end lines.
        befores: The predecessor lines for each span.
    """
    starts.append(163)
    stops.append(164)
    befores.append(
        "        return LaneInvasionEvent(frame, timestamp, transform, cr"
        "ossed^)\n"
    )
    starts.append(140)
    stops.append(142)
    befores.append("")
    starts.append(137)
    stops.append(139)
    befores.append("            Error: If a map query fails.\n")
    starts.append(130)
    stops.append(131)
    befores.append("            timestamp: The snapshot's elapsed seconds.\n")
    starts.append(122)
    stops.append(123)
    befores.append("        timestamp: Float64,\n")
    starts.append(29)
    stops.append(31)
    befores.append("from std.math import cos, sin\n")


def _lines_40(
    mut starts: List[Int], mut stops: List[Int], mut befores: List[String]
):
    """Fill one reviewed line-edit table, highest line first.

    Args:
        starts: The 0-based start lines.
        stops: The exclusive end lines.
        befores: The predecessor lines for each span.
    """
    starts.append(696)
    stops.append(703)
    befores.append(
        "        if end > start:\n            end = bitcast[DType.float64"
        "](bitcast[DType.uint64](end) - 1)\n            start = _next_up("
        "start)\n            if start <= end:\n                _certify_j"
        "unction_span(\n                    road, section, lane, start, e"
        "nd, out, work\n                )\n"
    )
    starts.append(645)
    stops.append(646)
    befores.append("    var b = min(road.upper_bound(a), road.length)\n")
    starts.append(421)
    stops.append(422)
    befores.append("    var delta = _Interval(low, high) - m\n")
    starts.append(410)
    stops.append(412)
    befores.append("    var m = _Interval.point(_midpoint(low, high))\n")
    starts.append(343)
    stops.append(344)
    befores.append(
        "    return road.lane_transform(section, lane, s).location\n"
    )
    starts.append(271)
    stops.append(272)
    befores.append(
        "        var last = road.directed_point_no_lane_offset(b).to_carl"
        "a().location\n"
    )
    starts.append(267)
    stops.append(270)
    befores.append(
        "        var first = road.directed_point_no_lane_offset(a).to_car"
        "la().location\n"
    )
    starts.append(77)
    stops.append(78)
    befores.append("        _insert_break(values, record.distance())\n")
    starts.append(53)
    stops.append(57)
    befores.append(
        "        max(\n            max(abs(fa), abs(fb)),\n            ma"
        "x(abs(fa + h * da / 3.0), abs(fb - h * db / 3.0)),\n        )\n "
        "       * (1.0 + epsilon)\n        + value_error\n        + h * t"
        "angent_error / 3.0,\n        max(max(abs(da), abs(db)), abs(da +"
        " h * dda / 2.0)) * (1.0 + epsilon)\n        + tangent_error\n   "
        "     + h * second_error / 2.0,\n        max(abs(dda), abs(ddb)) "
        "+ second_error,\n        value_error,\n"
    )
    starts.append(47)
    stops.append(52)
    befores.append(
        "    # Bernstein control values bound a cubic and its first two d"
        "erivatives.\n    var h = b - a\n    var fa = p.evaluate(a)\n    "
        "var fb = p.evaluate(b)\n    var da = p.tangent(a)\n    var db = "
        "p.tangent(b)\n    var dda = 2.0 * p.c + 6.0 * p.d * a\n    var d"
        "db = 2.0 * p.c + 6.0 * p.d * b\n    # Records are re-expanded ab"
        "out road s. Large s can cause cancellation\n    # even for a sma"
        "ll local polynomial. Bound Horner error by absolute\n    # coeff"
        "icient magnitudes, not by the small computed endpoint values.\n "
        "   comptime epsilon = 8.0 * 2.220446049250313e-16\n    var s = m"
        "ax(abs(a), abs(b))\n    var value_error = epsilon * (\n        a"
        "bs(p.a) + s * (abs(p.b) + s * (abs(p.c) + s * abs(p.d)))\n    )"
        "\n    var tangent_error = epsilon * (\n        abs(p.b) + s * (2"
        ".0 * abs(p.c) + s * 3.0 * abs(p.d))\n    )\n    var second_error"
        " = epsilon * (2.0 * abs(p.c) + s * 6.0 * abs(p.d))\n"
    )
    starts.append(33)
    stops.append(34)
    befores.append(
        "from extensions.carla.road_info import RoadInfo, info_index\n"
    )
    starts.append(17)
    stops.append(22)
    befores.append(
        "from extensions.carla.curve_bounds import _lane_jet, _reference_work\n"
    )


def _lines_41(
    mut starts: List[Int], mut stops: List[Int], mut befores: List[String]
):
    """Fill one reviewed line-edit table, highest line first.

    Args:
        starts: The 0-based start lines.
        stops: The exclusive end lines.
        befores: The predecessor lines for each span.
    """
    starts.append(385)
    stops.append(391)
    befores.append(
        "    if (lower and Float64(result) > value) or (\n        not low"
        "er and Float64(result) < value\n    ):\n"
    )


def _lines_42(
    mut starts: List[Int], mut stops: List[Int], mut befores: List[String]
):
    """Fill one reviewed line-edit table, highest line first.

    Args:
        starts: The 0-based start lines.
        stops: The exclusive end lines.
        befores: The predecessor lines for each span.
    """
    starts.append(909)
    stops.append(919)
    befores.append("")
    starts.append(903)
    stops.append(906)
    befores.append(
        "            Error: If the frame's size is not the camera's.\n"
    )
    starts.append(896)
    stops.append(897)
    befores.append(
        "            elapsed_seconds: The simulation time of the frame.\n"
    )
    starts.append(890)
    stops.append(891)
    befores.append(
        "        mut self, image: Framebuffer, elapsed_seconds: Float64\n"
    )
    starts.append(839)
    stops.append(846)
    befores.append("")
    starts.append(105)
    stops.append(106)
    befores.append("")
    starts.append(93)
    stops.append(94)
    befores.append("")


def _lines_43(
    mut starts: List[Int], mut stops: List[Int], mut befores: List[String]
):
    """Fill one reviewed line-edit table, highest line first.

    Args:
        starts: The 0-based start lines.
        stops: The exclusive end lines.
        befores: The predecessor lines for each span.
    """
    starts.append(2056)
    stops.append(2059)
    befores.append(
        "        for landmark in self.map.landmarks_in_distance(waypoint,"
        " distance):\n"
    )
    starts.append(2048)
    stops.append(2055)
    befores.append(
        '            Error: If the lane is not in the map.\n        """\n'
    )
    starts.append(2042)
    stops.append(2043)
    befores.append("            distance: How far ahead, in meters.\n")
    starts.append(2035)
    stops.append(2036)
    befores.append("        self, waypoint: Waypoint, distance: Float64\n")
    starts.append(172)
    stops.append(173)
    befores.append("")


def _lines_44(
    mut starts: List[Int], mut stops: List[Int], mut befores: List[String]
):
    """Fill one reviewed line-edit table, highest line first.

    Args:
        starts: The 0-based start lines.
        stops: The exclusive end lines.
        befores: The predecessor lines for each span.
    """
    starts.append(351)
    stops.append(363)
    befores.append("")
    starts.append(330)
    stops.append(331)
    befores.append("")
    starts.append(323)
    stops.append(325)
    befores.append(
        "            Error: If the sensor is not alive or the kind is not"
        " valid.\n"
    )
    starts.append(280)
    stops.append(285)
    befores.append('    """What one sensor gives on one tick."""\n')
    starts.append(274)
    stops.append(279)
    befores.append("")
    starts.append(161)
    stops.append(162)
    befores.append("")


def _lines_45(
    mut starts: List[Int], mut stops: List[Int], mut befores: List[String]
):
    """Fill one reviewed line-edit table, highest line first.

    Args:
        starts: The 0-based start lines.
        stops: The exclusive end lines.
        befores: The predecessor lines for each span.
    """
    starts.append(791)
    stops.append(792)
    befores.append("                world.elapsed_seconds,\n")
    starts.append(707)
    stops.append(708)
    befores.append("                        image, world.elapsed_seconds\n")
    starts.append(167)
    stops.append(168)
    befores.append("")


def _lines_46(
    mut starts: List[Int], mut stops: List[Int], mut befores: List[String]
):
    """Fill one reviewed line-edit table, highest line first.

    Args:
        starts: The 0-based start lines.
        stops: The exclusive end lines.
        befores: The predecessor lines for each span.
    """
    starts.append(1343)
    stops.append(1352)
    befores.append("")
    starts.append(1273)
    stops.append(1275)
    befores.append(
        "                self._add_walker(world, id, scene, assets, registry)\n"
    )
    starts.append(1270)
    stops.append(1272)
    befores.append(
        "                self._add_vehicle(world, id, scene, assets, regi"
        "stry)\n"
    )
    starts.append(1242)
    stops.append(1245)
    befores.append("        its beam put out.\n")
    starts.append(1218)
    stops.append(1227)
    befores.append(
        "            WalkerVisual(id, node, limbs^, first, len(scene.mesh"
        "es) - first)\n"
    )
    starts.append(1118)
    stops.append(1122)
    befores.append(
        "        var colors = clothing(id)\n        var shirt = assets.ma"
        "terials.add(\n            standard_material(\n                co"
        "lors[0], roughness=0.85, env_map=SCENE_ENVIRONMENT\n            "
        ")\n        )\n        var trousers = assets.materials.add(\n    "
        "        standard_material(\n                colors[1], roughness"
        "=0.85, env_map=SCENE_ENVIRONMENT\n            )\n        )\n    "
        "    var skin = assets.materials.add(\n            standard_mater"
        "ial(\n                colors[2], roughness=0.6, env_map=SCENE_EN"
        "VIRONMENT\n            )\n        )\n"
    )
    starts.append(1113)
    stops.append(1115)
    befores.append("")
    starts.append(1078)
    stops.append(1079)
    befores.append("")
    starts.append(875)
    stops.append(949)
    befores.append("")
    starts.append(740)
    stops.append(746)
    befores.append("")
    starts.append(722)
    stops.append(725)
    befores.append("")


def _lines_47(
    mut starts: List[Int], mut stops: List[Int], mut befores: List[String]
):
    """Fill one reviewed line-edit table, highest line first.

    Args:
        starts: The 0-based start lines.
        stops: The exclusive end lines.
        befores: The predecessor lines for each span.
    """
    starts.append(799)
    stops.append(802)
    befores.append(
        "                        _lane_records(doc, builder, id, s, group)\n"
    )
    starts.append(797)
    stops.append(798)
    befores.append("                    var group = doc.child(section, side)\n")
    starts.append(784)
    stops.append(795)
    befores.append(
        '            for section in doc.children(lanes, "laneSection"):'
        '\n                var s = doc.double(section, "s")\n'
    )
    starts.append(675)
    stops.append(683)
    befores.append("        if len(widths) == 0:\n")
    starts.append(660)
    stops.append(662)
    befores.append("    # `LaneParser`'s `ParseLanes`.\n")
    starts.append(652)
    stops.append(659)
    befores.append(
        "    doc: _Doc, mut builder: MapBuilder, road_id: RoadId, s: Floa"
        "t64, group: Int\n"
    )
    starts.append(415)
    stops.append(651)
    befores.append("")
    starts.append(65)
    stops.append(73)
    befores.append("")
    starts.append(30)
    stops.append(36)
    befores.append("")


def restored_frozen_arc_winner() raises -> String:
    """Restore the frozen-arc winner pin from the live file.

    Returns:
        The winner pin source.

    Raises:
        Error: The live file or a restored pin changed.
    """
    var path = "extensions/carla/curve_frozen_arc.mojo"
    var live = Path(path).read_text()
    _require(
        live,
        "fe4a9b4bca0cd23dc2a128fbcb9ff3b4604a870dc0b2b4ff4f8deeb766d2db50",
        path,
    )
    var starts = List[Int]()
    var stops = List[Int]()
    var befores = List[String]()
    _lines_37(starts, stops, befores)
    var restored = _apply(live, starts, stops, befores)
    _require(
        restored,
        "f7898a57be1c956136f9345675d26c6322c0016243eb095c1d748494fde3c522",
        "extensions/carla/curve_frozen_arc.mojo",
    )
    return restored


def restored_lane_invasion_winner() raises -> String:
    """Restore the lane-invasion winner pin from the live file.

    Returns:
        The winner pin source.

    Raises:
        Error: The live file or a restored pin changed.
    """
    var path = "extensions/carla/lane_invasion.mojo"
    var live = Path(path).read_text()
    _require(
        live,
        "c2dfa4b2e3b17434b25dfb1ad637a7901cc044349b1b2eaa34055ce10aaaa981",
        path,
    )
    var starts = List[Int]()
    var stops = List[Int]()
    var befores = List[String]()
    _lines_38(starts, stops, befores)
    var mid = _apply(live, starts, stops, befores)
    _require(
        mid,
        "3b7262b84e9e170c0e7181e7e013a6763376b34b9e65feddcd98a2c457350850",
        "extensions/carla/lane_invasion.mojo",
    )
    starts.clear()
    stops.clear()
    befores.clear()
    _lines_39(starts, stops, befores)
    var restored = _apply(mid, starts, stops, befores)
    _require(
        restored,
        "3049273d70f2cf83335533d1a92783bb128fd69fe32530a9d04386b8efd3acec",
        "extensions/carla/lane_invasion.mojo",
    )
    return restored


def restored_junction_winner() raises -> String:
    """Restore the junction-bounds winner pin from the live file.

    Returns:
        The winner pin source.

    Raises:
        Error: The live file or a restored pin changed.
    """
    var path = "extensions/carla/junction_bounds.mojo"
    var live = Path(path).read_text()
    _require(
        live,
        "281daed1fdda879c79c34f8ee141685c1df4a358b0efdf96b282b46ff431b19f",
        path,
    )
    var starts = List[Int]()
    var stops = List[Int]()
    var befores = List[String]()
    _lines_40(starts, stops, befores)
    var mid = _apply(live, starts, stops, befores)
    _require(
        mid,
        "c933e03b6bde0bede8fb0745e9c1ef075d9699fde72b74795368943381d1aa74",
        "extensions/carla/junction_bounds.mojo",
    )
    starts.clear()
    stops.clear()
    befores.clear()
    _lines_41(starts, stops, befores)
    var restored = _apply(mid, starts, stops, befores)
    _require(
        restored,
        "98fc27702e365e19c3b226d1a7b525bce5aa82b5b11fb6caff79ce39416024e2",
        "extensions/carla/junction_bounds.mojo",
    )
    return restored


def restored_cameras_winner(text: String) raises -> String:
    """Restore the cameras winner pin from the boundary endpoint.

    Args:
        text: The reviewed endpoint this pin starts from.

    Returns:
        The winner pin source.

    Raises:
        Error: The endpoint or a restored pin changed.
    """
    _require(
        text,
        "dbff553682707e52175a967b7a09618716f1c7c8ba28c17e1fa7f6225725e778",
        "extensions/carla/cameras.mojo",
    )
    var starts = List[Int]()
    var stops = List[Int]()
    var befores = List[String]()
    _lines_42(starts, stops, befores)
    var restored = _apply(text, starts, stops, befores)
    _require(
        restored,
        "59999d17b9e35d25e56d24a1e88f25738378426c0baf9e69332dfcfdbe26d6b5",
        "extensions/carla/cameras.mojo",
    )
    return restored


def restored_world_winner(text: String) raises -> String:
    """Restore the world winner pin from the boundary endpoint.

    Args:
        text: The reviewed endpoint this pin starts from.

    Returns:
        The winner pin source.

    Raises:
        Error: The endpoint or a restored pin changed.
    """
    _require(
        text,
        "0c7a44bfda063270715b20dfee7d21d08390f3db97f60c3bb9ddd959eaa6becd",
        "extensions/carla/world.mojo",
    )
    var starts = List[Int]()
    var stops = List[Int]()
    var befores = List[String]()
    _lines_43(starts, stops, befores)
    var restored = _apply(text, starts, stops, befores)
    _require(
        restored,
        "db35b64842ddac2d5fdea6f4c502e72b19ad892a191ee4614bb33390c4c464eb",
        "extensions/carla/world.mojo",
    )
    return restored


def restored_sensor_winner(text: String) raises -> String:
    """Restore the sensor-manager winner pin from the view endpoint.

    Args:
        text: The reviewed endpoint this pin starts from.

    Returns:
        The winner pin source.

    Raises:
        Error: The endpoint or a restored pin changed.
    """
    _require(
        text,
        "6c8c81d18596601c31b4bb8e510beb814cbadd237dd8494b954c3e0663eeec82",
        "extensions/carla/sensor_manager.mojo",
    )
    var starts = List[Int]()
    var stops = List[Int]()
    var befores = List[String]()
    _lines_44(starts, stops, befores)
    var mid = _apply(text, starts, stops, befores)
    _require(
        mid,
        "cf801d357feeaf3c9d0d49dd3953b332243fd398c0ed1c876e4d9301e9251a7b",
        "extensions/carla/sensor_manager.mojo",
    )
    starts.clear()
    stops.clear()
    befores.clear()
    _lines_45(starts, stops, befores)
    var restored = _apply(mid, starts, stops, befores)
    _require(
        restored,
        "caf4123e0abcbe6cb8ab8dc413b83fb4dced11b3459186b9b21f9e74e86d5d15",
        "extensions/carla/sensor_manager.mojo",
    )
    return restored


def restored_render_actor_winner(text: String) raises -> String:
    """Restore the render-actor winner pin from the ledger endpoint.

    Args:
        text: The reviewed endpoint this pin starts from.

    Returns:
        The winner pin source.

    Raises:
        Error: The endpoint or a restored pin changed.
    """
    _require(
        text,
        "0169a2466ef2cfe970e5e53b3311ea8cf81e481d11f668c531c2ca545497cdcc",
        "extensions/carla/render_actors.mojo",
    )
    var starts = List[Int]()
    var stops = List[Int]()
    var befores = List[String]()
    _lines_46(starts, stops, befores)
    var restored = _apply(text, starts, stops, befores)
    _require(
        restored,
        "ae1f86645cb6c7dac99a741619595be18a61c558c56262c27a50fa9b9bacef3b",
        "extensions/carla/render_actors.mojo",
    )
    return restored


def restored_opendrive_winner(text: String) raises -> String:
    """Restore the OpenDRIVE winner pin from the border endpoint.

    Args:
        text: The reviewed endpoint this pin starts from.

    Returns:
        The winner pin source.

    Raises:
        Error: The endpoint or a restored pin changed.
    """
    _require(
        text,
        "9ff9b750af2c1c1a92fe3f3dfe1e49566e9d6f8c39a3576e0d4cf542bc8cdc28",
        "extensions/carla/opendrive.mojo",
    )
    var starts = List[Int]()
    var stops = List[Int]()
    var befores = List[String]()
    _lines_47(starts, stops, befores)
    var restored = _apply(text, starts, stops, befores)
    _require(
        restored,
        "4c7ac574196b83d025b84cf6c88261d5e3f3b9ce69923262fcf3cb935e9bf1e5",
        "extensions/carla/opendrive.mojo",
    )
    return restored
