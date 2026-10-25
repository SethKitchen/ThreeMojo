# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Restore the reviewed Map score endpoint from the live file."""

from std.pathlib import Path

from tools._sha256 import sha256_hex


comptime _MODULE = "extensions/carla/map.mojo"
"""The live Map module."""
comptime _LIVE_SHA256 = (
    "288d0e5d3a5bc2e5a6b9542868de6566dc6cb4de6eae39192c0289d76a8c99fa"
)
"""The file digest of the live Map module."""
comptime _MID_SHA256 = (
    "b3862a55a54927b2a1e50186af82f64bdf145adbef5cef9f31ab19d9585749df"
)
"""The file digest after the first reviewed Map edit is removed."""
comptime _DEVIATION_SHA256 = (
    "0e2d282fcd6c70217e7413b7febe40619af070f7adbeaefa3fd56d95562c404b"
)
"""The file digest of the deviation endpoint."""
comptime _STATION_SHA256 = (
    "96611c1a85a89720cf739404924005aad4408e6868e1058f724675a6ad58630e"
)
"""The file digest of the station endpoint."""
comptime _SCORE_SHA256 = (
    "70ec94630e2530e9389fdb6388ff4c139bb268f5549f1a9f06602b6dfebecb94"
)
"""The file digest of the score endpoint."""


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


def _count(text: String, needle: String) -> Int:
    """Return how many times `needle` occurs.

    Args:
        text: The source.
        needle: The fragment.

    Returns:
        The number of matches.
    """
    var count = 0
    var rest = text
    while True:
        var at = rest.find(needle)
        if at < 0:
            return count
        count += 1
        var tail = String(rest[byte = at + needle.byte_length() :])
        rest = tail


def _replace_first(text: String, before: String, after: String) -> String:
    """Replace the first occurrence of `before`.

    Args:
        text: The source.
        before: The original fragment.
        after: The replacement.

    Returns:
        The changed source.
    """
    var at = text.find(before)
    var head = String(text[byte=:at])
    var tail = String(text[byte = at + before.byte_length() :])
    return head + after + tail


def _live_edits(
    mut starts: List[Int], mut stops: List[Int], mut befores: List[String]
):
    """Fill the first reviewed Map line edit.

    Args:
        starts: The 0-based start lines.
        stops: The exclusive end lines.
        befores: The predecessor lines for each span.
    """
    starts.append(189)
    stops.append(190)
    befores.append("from std.hashlib import Hasher\n")


def _typed_edits(
    mut starts: List[Int], mut stops: List[Int], mut befores: List[String]
):
    """Fill the reviewed typed Map line edits, highest line first.

    Args:
        starts: The 0-based start lines.
        stops: The exclusive end lines.
        befores: The predecessor lines for each span.
    """
    starts.append(5232)
    stops.append(5235)
    befores.append(
        "            var lane_end = lane_start +"
        " self.roads[at[0]].section_length(at[1])\n"
    )
    starts.append(5218)
    stops.append(5219)
    befores.append("                        Waypoint(\n")
    starts.append(4974)
    stops.append(4975)
    befores.append(
        "        return self.roads[at[0]].lane_transform(at[1], at[2],"
        " waypoint.s)\n"
    )
    starts.append(4947)
    stops.append(4948)
    befores.append(
        "        var length = self.roads[at[0]].section_length(at[1])\n"
    )
    starts.append(4879)
    stops.append(4880)
    befores.append(
        "                out.append(Landmark(None, reference, 0.0))\n"
    )
    starts.append(4859)
    stops.append(4860)
    befores.append(
        "                out.append(Landmark(None, reference, 0.0))\n"
    )
    starts.append(4839)
    stops.append(4840)
    befores.append("            out.append(Landmark(None, reference, 0.0))\n")
    starts.append(4825)
    stops.append(4828)
    befores.append(
        "                    Landmark(data.waypoint, data.signal,"
        " data.accumulated_s)\n"
    )
    starts.append(4820)
    stops.append(4821)
    befores.append("        for data in self.signals_in_distance(\n")
    starts.append(4802)
    stops.append(4803)
    befores.append('        """Return the landmarks of one type ahead.\n')
    starts.append(4771)
    stops.append(4796)
    befores.append("")
    starts.append(4763)
    stops.append(4768)
    befores.append(
        "            out.append(Landmark(data.waypoint, data.signal,"
        " data.accumulated_s))\n"
    )
    starts.append(4754)
    stops.append(4755)
    befores.append("        for data in self.signals_in_distance(\n")
    starts.append(4738)
    stops.append(4739)
    befores.append(
        '        """Return the landmarks ahead, `GetAllLandmarksInDistance`.\n'
    )
    starts.append(4712)
    stops.append(4735)
    befores.append("")
    starts.append(4667)
    stops.append(4668)
    befores.append("            return LaneMarking(mark.value())\n")
    starts.append(4642)
    stops.append(4643)
    befores.append("            return LaneMarking(mark.value())\n")
    starts.append(4571)
    stops.append(4572)
    befores.append(
        "        if not isfinite(s) or s < section_start or s > section_end:\n"
    )
    starts.append(4569)
    stops.append(4570)
    befores.append(
        "        var section_end = section_start +"
        " road.section_length(initial[1])\n"
    )
    starts.append(4564)
    stops.append(4566)
    befores.append("")
    starts.append(4538)
    stops.append(4539)
    befores.append(
        '        """Return waypoints every `distance` back to the lane\'s'
        " start.\n"
    )
    starts.append(4519)
    stops.append(4536)
    befores.append("")
    starts.append(4497)
    stops.append(4498)
    befores.append(
        '        """Return waypoints every `distance` to the lane\'s end.\n'
    )
    starts.append(4478)
    stops.append(4495)
    befores.append("")
    starts.append(4453)
    stops.append(4454)
    befores.append(
        "                        base = road.lane_transform(index, lane,"
        " crosswalk.s)\n"
    )
    starts.append(4450)
    stops.append(4451)
    befores.append(
        "                for index in road.sections_at(crosswalk.s):\n"
    )
    starts.append(4420)
    stops.append(4421)
    befores.append("            out.append(LaneMarking(mark.value()))\n")
    starts.append(4347)
    stops.append(4349)
    befores.append(
        "                start.s = s + next_road.section_length(c[1])\n        "
        "    var found = self.signals_in_distance(\n"
    )
    starts.append(4329)
    stops.append(4333)
    befores.append(
        "                    SignalSearchData(\n                        signal,"
        " self.next(waypoint, to_signal)[0], to_signal\n"
    )
    starts.append(4324)
    stops.append(4327)
    befores.append(
        "                out.append(SignalSearchData(signal, waypoint,"
        " to_signal))\n"
    )
    starts.append(4305)
    stops.append(4306)
    befores.append(
        "            road.section_length(at[1]) - relative if forward else"
        " relative\n"
    )
    starts.append(4298)
    stops.append(4300)
    befores.append("")
    starts.append(4280)
    stops.append(4281)
    befores.append(
        '        """Return the signals within a distance ahead,'
        " `GetSignalsInDistance`.\n"
    )
    starts.append(4254)
    stops.append(4277)
    befores.append("")
    starts.append(4235)
    stops.append(4238)
    befores.append(
        "                    segment_distance_2d(one.start, one.end, two.start,"
        " two.end)\n"
    )
    starts.append(4164)
    stops.append(4165)
    befores.append("                    var start = Waypoint(\n")
    starts.append(4130)
    stops.append(4131)
    befores.append("                    var start = Waypoint(\n")
    starts.append(4088)
    stops.append(4089)
    befores.append("                        var last = Waypoint(\n")
    starts.append(4080)
    stops.append(4081)
    befores.append("                    var w = Waypoint(\n")
    starts.append(3999)
    stops.append(4000)
    befores.append("                        Waypoint(\n")
    starts.append(3993)
    stops.append(3994)
    befores.append("        for index in road.sections_at(road.length):\n")
    starts.append(3989)
    stops.append(3992)
    befores.append(
        "                        Waypoint(road.id, road.sections[index].id,"
        " lane.id, 0.0)\n"
    )
    starts.append(3983)
    stops.append(3984)
    befores.append("        for index in road.sections_at(0.0):\n")
    starts.append(3972)
    stops.append(3978)
    befores.append("                s += distance\n")
    starts.append(3968)
    stops.append(3969)
    befores.append("                                Waypoint(\n")
    starts.append(3962)
    stops.append(3963)
    befores.append("                for index in road.sections_at(s):\n")
    starts.append(3956)
    stops.append(3957)
    befores.append("        if not (distance > 0.0):\n")
    starts.append(3925)
    stops.append(3943)
    befores.append(
        "    def generate_waypoints(self, distance: Float64) raises ->"
        ' List[Waypoint]:\n        """Return waypoints every `distance` on'
        " every driving lane.\n"
    )
    starts.append(3839)
    stops.append(3840)
    befores.append("        var length = road.section_length(at[1])\n")
    starts.append(3831)
    stops.append(3832)
    befores.append("")
    starts.append(3829)
    stops.append(3830)
    befores.append("        if not (distance > 0.0):\n")
    starts.append(3811)
    stops.append(3812)
    befores.append(
        '        """Return the waypoints a distance behind,'
        " `Map::GetPrevious`.\n"
    )
    starts.append(3792)
    stops.append(3809)
    befores.append("")
    starts.append(3771)
    stops.append(3772)
    befores.append(
        '        """Return the waypoints a distance ahead, `Map::GetNext`.\n'
    )
    starts.append(3752)
    stops.append(3769)
    befores.append("")
    starts.append(3742)
    stops.append(3743)
    befores.append("                Waypoint(\n")
    starts.append(3713)
    stops.append(3714)
    befores.append("                Waypoint(\n")
    starts.append(3672)
    stops.append(3690)
    befores.append("")
    starts.append(3668)
    stops.append(3671)
    befores.append(
        "                return Waypoint(road_id, road.sections[index].id,"
        " lane_id, at)\n"
    )
    starts.append(3666)
    stops.append(3667)
    befores.append("        for index in road.sections_at(at):\n")
    starts.append(3663)
    stops.append(3664)
    befores.append("        var at = Float64(s.value)\n")
    starts.append(3643)
    stops.append(3645)
    befores.append(
        "        CARLA takes s as a `float`, as `Length` holds it.\n"
    )
    starts.append(3639)
    stops.append(3640)
    befores.append(
        "        self, road_id: RoadId, lane_id: LaneId, s: Length\n"
    )
    starts.append(3636)
    stops.append(3637)
    befores.append(
        "        _ = self.roads[at[0]].lane_transform(at[1], at[2],"
        " waypoint.s)\n"
    )
    starts.append(3558)
    stops.append(3559)
    befores.append("                var length = road.section_length(at[1])\n")
    starts.append(3499)
    stops.append(3502)
    befores.append(
        "                Waypoint(key.road_id, key.section_id, key.lane_id,"
        " station)\n"
    )
    starts.append(3486)
    stops.append(3490)
    befores.append(
        "                Waypoint(key.road_id, key.section_id, key.lane_id,"
        " 0.0), work\n"
    )
    starts.append(3429)
    stops.append(3430)
    befores.append("        var length = road.section_length(at[1])\n")
    starts.append(3126)
    stops.append(3127)
    befores.append("                for _ in range(10):\n")
    starts.append(3117)
    stops.append(3118)
    befores.append("                for _ in range(4):\n")
    starts.append(3108)
    stops.append(3109)
    befores.append("                for candidate in certificates:\n")
    starts.append(3103)
    stops.append(3104)
    befores.append("                for value in metadata:\n")
    starts.append(3031)
    stops.append(3032)
    befores.append("            for i in range(len(indices)):\n")
    starts.append(3009)
    stops.append(3010)
    befores.append("            for i in range(len(indices)):\n")
    starts.append(3002)
    stops.append(3003)
    befores.append("        for certificate in certificates:\n")
    starts.append(2816)
    stops.append(2817)
    befores.append("        return self.next(start, delta)[0]\n")
    starts.append(2685)
    stops.append(2688)
    befores.append(
        "        return width.value().polynomial.evaluate(waypoint.s)\n"
    )
    starts.append(2660)
    stops.append(2663)
    befores.append(
        "        var at = self._locate(waypoint)\n        ref road ="
        " self.roads[at[0]]\n        if waypoint.s > road.length:\n           "
        ' raise Error("s is past the end of the road")\n        var width ='
        " info_at(\n            road.sections[at[1]].lanes[at[2]].info.widths,"
        " waypoint.s\n        )\n        if not Bool(width):\n            raise"
        ' Error("The lane has no width record at s")\n        return Length(\n '
        "           Float32(width.value().polynomial.evaluate(waypoint.s)),"
        " METER\n        )\n"
    )
    starts.append(2630)
    stops.append(2648)
    befores.append(
        "    def lane_width(self, waypoint: Waypoint) raises -> Length:\n"
    )
    starts.append(2611)
    stops.append(2616)
    befores.append(
        "        if (\n            not isfinite(waypoint.s)\n            or"
        " waypoint.s < 0\n            or waypoint.s > road.length\n        ):\n"
    )
    starts.append(2605)
    stops.append(2609)
    befores.append("")
    starts.append(2574)
    stops.append(2575)
    befores.append(
        "        return self.roads[at[0]].lane_transform(at[1], at[2],"
        " waypoint.s)\n"
    )
    starts.append(2555)
    stops.append(2556)
    befores.append("        return s + r.section_length(section) - inset\n")
    starts.append(2552)
    stops.append(2553)
    befores.append(
        "        var inset = min(10.0 * EPSILON, r.section_length(section) /"
        " 4.0)\n"
    )
    starts.append(2546)
    stops.append(2547)
    befores.append("        return s + r.section_length(section) - inset\n")
    starts.append(2543)
    stops.append(2544)
    befores.append(
        "        var inset = min(10.0 * EPSILON, r.section_length(section) /"
        " 4.0)\n"
    )
    starts.append(2439)
    stops.append(2440)
    befores.append(
        "            Waypoint(key.road_id, key.section_id, key.lane_id, 0.0)\n"
    )
    starts.append(2402)
    stops.append(2403)
    befores.append("")
    starts.append(2204)
    stops.append(2205)
    befores.append("        for at in range(1 << level):\n")
    starts.append(1847)
    stops.append(1850)
    befores.append("")
    starts.append(1730)
    stops.append(1773)
    befores.append("")
    starts.append(1478)
    stops.append(1489)
    befores.append("")
    starts.append(1459)
    stops.append(1475)
    befores.append("")
    starts.append(1429)
    stops.append(1453)
    befores.append('    ):\n        """Create a landmark.\n')
    starts.append(1407)
    stops.append(1428)
    befores.append("")
    starts.append(1378)
    stops.append(1389)
    befores.append("")
    starts.append(1359)
    stops.append(1375)
    befores.append("")
    starts.append(1329)
    stops.append(1353)
    befores.append('    ):\n        """Create a result.\n')
    starts.append(1307)
    stops.append(1328)
    befores.append("")
    starts.append(1052)
    stops.append(1151)
    befores.append("")
    starts.append(894)
    stops.append(982)
    befores.append("")
    starts.append(807)
    stops.append(808)
    befores.append("")
    starts.append(549)
    stops.append(785)
    befores.append("")
    starts.append(334)
    stops.append(345)
    befores.append("")
    starts.append(219)
    stops.append(285)
    befores.append("")
    starts.append(211)
    stops.append(211)
    befores.append("@fieldwise_init\n")
    starts.append(192)
    stops.append(201)
    befores.append(
        "from units.si import DEGREE, Angle, Length, METER, Velocity64\n"
    )
    starts.append(175)
    stops.append(178)
    befores.append("    info_at,\n    info_index,\n    infos_in_range,\n")


def _deviation_spans(
    mut names: List[String], mut befores: List[String], mut afters: List[String]
):
    """Fill the reviewed deviation spans in forward order.

    Args:
        names: The span names.
        befores: The predecessor fragments.
        afters: The successor fragments.
    """
    names.append("deviation_span_1")
    befores.append(
        "struct _Segment(ImplicitlyCopyable):\n    var start: Vector3\n    var"
        " end: Vector3\n    var first: Waypoint\n    var second: Waypoint\n   "
        " var bounds: Tuple[_Interval, _Interval, _Interval]\n    # -1 means"
        " the optional construction proof is absent.\n    var cover_index:"
        " Int\n\n\n@fieldwise_init\nstruct _CarlaSegment"
    )
    afters.append(
        "struct _Segment(ImplicitlyCopyable):\n    var start: Vector3\n    var"
        " end: Vector3\n    var first: Waypoint\n    var second: Waypoint\n   "
        " var bounds: Tuple[_Interval, _Interval, _Interval]\n    # -1 means"
        " the optional construction proof is absent.\n    var cover_index:"
        " Int\n    # This segment's certified full-curve distance to its stored"
        " chord. The\n    # map's `_curve_deviation` is the maximum over every"
        " segment (#685).\n    var deviation:"
        " Float64\n\n\n@fieldwise_init\nstruct _CarlaSegment"
    )
    names.append("deviation_span_2")
    befores.append(
        "            ref segment = self._segments[index]\n            if best"
        " >= 0:\n                var lower = _indexed_curve_lower(\n           "
        "         _segment_distance2(segment.start, segment.end, location),\n  "
        "                  self._curve_deviation,\n                )\n         "
        "       if lower > best_radius:\n                    break\n"
    )
    afters.append(
        "            ref segment = self._segments[index]\n            if best"
        " >= 0:\n                var key = _segment_distance2(\n               "
        "     segment.start, segment.end, location\n                )\n        "
        "        var lower = _indexed_curve_lower(key, self._curve_deviation)\n"
        "                if lower > best_radius:\n                    break\n  "
        "              # The index orders keys only, so the walk keeps the"
        " global\n                # stop. This candidate's own deviation can"
        " still exclude it.\n                if _indexed_curve_lower(key,"
        " segment.deviation) > best_radius:\n                    continue\n"
    )
    names.append("deviation_span_3")
    befores.append(
        "                certificate[1],\n                cover_index,\n       "
        "     )\n        )\n        self._curve_deviation ="
        " max(self._curve_deviation, certificate[0])\n"
    )
    afters.append(
        "                certificate[1],\n                cover_index,\n       "
        "         certificate[0],\n            )\n        )\n       "
        " self._curve_deviation = max(self._curve_deviation, certificate[0])\n"
    )


def _station_spans(
    mut names: List[String], mut befores: List[String], mut afters: List[String]
):
    """Fill the reviewed station spans in forward order.

    Args:
        names: The span names.
        befores: The predecessor fragments.
        afters: The successor fragments.
    """
    names.append("station_span_1")
    befores.append(
        "the sign check at load use it with CARLA's algorithm: the nearest"
        " segment,\nthen a step along the lane to the point's foot. These"
        " queries do not use\nthe certified search budget. Input validation,"
        " lane stepping and canonical\npose evaluation can still raise errors."
        " They keep CARLA's approximations:\nthe step treats distance along the"
        " segment chord as road s.\n\n**The certified index.**"
        " `certified_closest_waypoint_on_road` and\n`certified_waypoint` use a"
        " second index. It starts with CARLA's partition\n"
    )
    afters.append(
        "the sign check at load use it with CARLA's algorithm: the nearest"
        " segment,\nthen a step along the lane to the point's foot. These"
        " queries do not use\nthe certified search budget. Input validation,"
        " lane stepping and canonical\npose evaluation can still raise errors."
        " They keep CARLA's partition, but\nthey correct one CARLA"
        " approximation. CARLA steps by the plan distance along\nthe segment"
        " chord, as if it were road s. A lane offset, a lane width or a\ncurve"
        " can make the chord longer or shorter than its road-s span. A"
        " sloped\nlane then misses points on its center. This port steps by the"
        " foot's plan\nfraction of the chord times the chord's road-s span"
        " (#302).\n\n**The certified index.**"
        " `certified_closest_waypoint_on_road` and\n`certified_waypoint` use a"
        " second index. It starts with CARLA's partition\n"
    )
    names.append("station_span_2")
    befores.append(
        "The public `segment_count` and `segment` methods expose this"
        " accuracy-driven\nindex. Its partition and count can change when the"
        " geometry requires more\nsubdivision. Lane order and index tie rules"
        " remain deterministic. The\ncertified queries correct curved lane"
        " offsets and the treatment of lane\ndistance as road s. They cost more"
        " and can raise where CARLA's query\nanswers, so they are not the"
        " default.\n\nThe R-tree, full-center bounds, and optional"
        " sampled-curve box covers belong\nto the same construction snapshot."
        " Queries do not update these proofs.\n"
    )
    afters.append(
        "The public `segment_count` and `segment` methods expose this"
        " accuracy-driven\nindex. Its partition and count can change when the"
        " geometry requires more\nsubdivision. Lane order and index tie rules"
        " remain deterministic. The\ncertified queries also correct the chord"
        " error of curved lane offsets.\nThey cost more and can raise where"
        " CARLA's query answers, so they are not\nthe default.\n\nThe R-tree,"
        " full-center bounds, and optional sampled-curve box covers belong\nto"
        " the same construction snapshot. Queries do not update these proofs.\n"
    )
    names.append("station_span_3")
    befores.append(
        ")\nfrom extensions.carla.speed_limits import opendrive_speed,"
        " NUMERIC_SPEED_LIMIT\nfrom extensions.carla.math import (\n   "
        " distance_segment_to_point,\n    make_unit_vector,\n   "
        " vector_angle,\n)\n"
    )
    afters.append(
        ")\nfrom extensions.carla.speed_limits import opendrive_speed,"
        " NUMERIC_SPEED_LIMIT\nfrom extensions.carla.math import (\n   "
        " make_unit_vector,\n    vector_angle,\n)\n"
    )
    names.append("station_span_4")
    befores.append(
        "    )\n\n\n# --- the map"
        " ------------------------------------------------------------------\n\n\n"
    )
    afters.append(
        "    )\n\n\ndef _chord_station_delta(\n    location: Vector3, start:"
        " Vector3, end: Vector3, span: Float64\n) -> Float64:\n    # The"
        " default query's step along the lane, in road s. CARLA steps by the\n "
        "   # plan distance along the chord (`Math::DistanceSegmentToPoint`)."
        " That\n    # distance is not road s when a lane offset, a lane width"
        " or a curve\n    # changes the lane's plan speed (#302). This uses the"
        " foot's plan\n    # fraction of the chord times the chord's road-s"
        " span instead. Float64\n    # holds the square of any finite Float32"
        " chord. A nonfinite chord gives\n    # NaN, which the callers refuse"
        " or return as before.\n    var dx = Float64(end.x) -"
        " Float64(start.x)\n    var dy = Float64(end.y) - Float64(start.y)\n   "
        " var l2 = dx * dx + dy * dy\n    if l2 == 0.0:\n        return 0.0\n  "
        "  var px = Float64(location.x) - Float64(start.x)\n    var py ="
        " Float64(location.y) - Float64(start.y)\n    var t = (px * dx + py *"
        " dy) / l2\n    # Clamp without min and max, so that a NaN fraction"
        " stays NaN.\n    if t < 0.0:\n        t = 0.0\n    elif t > 1.0:\n    "
        "    t = 1.0\n    return t * span\n\n\n# --- the map"
        " ------------------------------------------------------------------\n\n\n"
    )
    names.append("station_span_5")
    befores.append(
        '        """Return the waypoint nearest a point,'
        " `GetClosestWaypointOnRoad`.\n\n        CARLA finds the nearest"
        " segment of a lane of the given types, then\n        steps from the"
        " segment's start by the distance along it to the\n        point's"
        " foot. The segments are CARLA's heading and length partition.\n       "
        " For the certified nearest center, use\n       "
        " `certified_closest_waypoint_on_road`.\n\n"
    )
    afters.append(
        '        """Return the waypoint nearest a point,'
        " `GetClosestWaypointOnRoad`.\n\n        CARLA finds the nearest"
        " segment of a lane of the given types, then\n        steps from the"
        " segment's start toward the point's foot. The step is\n        the"
        " foot's plan fraction of the segment times the segment's road-s\n     "
        "   span. CARLA steps by the plan distance itself; that is not road s\n"
        "        on a lane with a sloped or curved offset (#302). The segments"
        " are\n        CARLA's heading and length partition.\n        For the"
        " certified nearest center, use\n       "
        " `certified_closest_waypoint_on_road`.\n\n"
    )
    names.append("station_span_6")
    befores.append(
        "        if len(found) == 0:\n            return None\n        ref"
        " segment = self._carla_segments[found[0].start_value]\n        var"
        " along = distance_segment_to_point(\n            location,"
        " segment.start, segment.end\n        )\n        var start ="
        " segment.first\n        var end = segment.second\n        var delta ="
        " Float64(along[0].value)\n        var forward ="
        " self.is_positive_direction(start)\n        var final_s = start.s +"
        " delta if forward else start.s - delta\n        var past = final_s >="
        " end.s if forward else final_s <= end.s\n"
    )
    afters.append(
        "        if len(found) == 0:\n            return None\n        ref"
        " segment = self._carla_segments[found[0].start_value]\n        var"
        " start = segment.first\n        var end = segment.second\n        var"
        " delta = _chord_station_delta(\n            location, segment.start,"
        " segment.end, abs(end.s - start.s)\n        )\n        var forward ="
        " self.is_positive_direction(start)\n        var final_s = start.s +"
        " delta if forward else start.s - delta\n        var past = final_s >="
        " end.s if forward else final_s <= end.s\n"
    )
    names.append("station_span_7")
    befores.append(
        '            raise Error(\n                "CARLA query segment must'
        ' stay in one finite lane section"\n            )\n        var along ='
        " distance_segment_to_point(\n            location, segment.start,"
        " segment.end\n        )\n        var delta = Float64(along[0].value)\n"
        "        # The default query resolves this metadata twice (direction"
        " and\n        # next). Reuse the same checked location and preserve"
        " its arithmetic.\n        var at = self._locate_with_work(start,"
        " work)\n"
    )
    afters.append(
        '            raise Error(\n                "CARLA query segment must'
        ' stay in one finite lane section"\n            )\n        var delta ='
        " _chord_station_delta(\n            location, segment.start,"
        " segment.end, abs(end.s - start.s)\n        )\n        # The default"
        " query resolves this metadata twice (direction and\n        # next)."
        " Reuse the same checked location and preserve its arithmetic.\n       "
        " var at = self._locate_with_work(start, work)\n"
    )


def restored_deviation_map() raises -> String:
    """Return the reviewed Map deviation endpoint.

    Returns:
        The live Map module with the reviewed line edits removed.

    Raises:
        Error: The live file or the restored module changed.
    """
    var live = Path(_MODULE).read_text()
    if sha256_hex(live.as_bytes()) != _LIVE_SHA256:
        raise Error("reviewed Map deviation successor: live map changed")
    var starts = List[Int]()
    var stops = List[Int]()
    var befores = List[String]()
    _live_edits(starts, stops, befores)
    var middle = _apply(live, starts, stops, befores)
    if sha256_hex(middle.as_bytes()) != _MID_SHA256:
        raise Error("reviewed Map deviation successor: map midpoint changed")
    starts.clear()
    stops.clear()
    befores.clear()
    _typed_edits(starts, stops, befores)
    var restored = _apply(middle, starts, stops, befores)
    if sha256_hex(restored.as_bytes()) != _DEVIATION_SHA256:
        raise Error(
            "reviewed Map deviation successor: deviation endpoint changed"
        )
    return restored


def _reverse_spans(
    text: String,
    names: List[String],
    befores: List[String],
    afters: List[String],
    input_sha: String,
    output_sha: String,
    unknown: String,
    missing: String,
    failed: String,
) raises -> String:
    """Reverse unique spans from the last span to the first.

    Args:
        text: The successor source.
        names: The span names, in forward order.
        befores: The predecessor fragments.
        afters: The successor fragments.
        input_sha: The required successor digest.
        output_sha: The required predecessor digest.
        unknown: The refusal for a different successor.
        missing: The refusal prefix for a missing span.
        failed: The refusal when the predecessor digest differs.

    Returns:
        The predecessor source.

    Raises:
        Error: The source, a span, or the reconstructed bytes differ.
    """
    if sha256_hex(text.as_bytes()) != input_sha:
        raise Error(unknown)
    var current = text
    var index = len(names)
    while index > 0:
        index -= 1
        if _count(current, afters[index]) != 1:
            raise Error(missing + names[index])
        current = _replace_first(current, afters[index], befores[index])
    if sha256_hex(current.as_bytes()) != output_sha:
        raise Error(failed)
    return current


def station_endpoint(text: String) raises -> String:
    """Reverse the three deviation spans.

    Args:
        text: The deviation endpoint.

    Returns:
        The station endpoint.

    Raises:
        Error: The source, a span, or the station bytes differ.
    """
    var names = List[String]()
    var befores = List[String]()
    var afters = List[String]()
    _deviation_spans(names, befores, afters)
    return _reverse_spans(
        text,
        names,
        befores,
        afters,
        _DEVIATION_SHA256,
        _STATION_SHA256,
        "reviewed Map deviation successor: unknown complete deviation endpoint",
        (
            "reviewed Map deviation successor: missing or ambiguous deviation"
            " inverse: "
        ),
        (
            "reviewed Map deviation successor: deviation inverse does not"
            " reconstruct the station endpoint"
        ),
    )


def score_endpoint(text: String) raises -> String:
    """Reverse the seven station spans.

    Args:
        text: The station endpoint.

    Returns:
        The score endpoint.

    Raises:
        Error: The source, a span, or the score bytes differ.
    """
    var names = List[String]()
    var befores = List[String]()
    var afters = List[String]()
    _station_spans(names, befores, afters)
    return _reverse_spans(
        text,
        names,
        befores,
        afters,
        _STATION_SHA256,
        _SCORE_SHA256,
        "reviewed Map station successor: unknown complete station endpoint",
        (
            "reviewed Map station successor: missing or ambiguous station"
            " inverse: "
        ),
        (
            "reviewed Map station successor: station inverse does not"
            " reconstruct fifth seed endpoint"
        ),
    )
