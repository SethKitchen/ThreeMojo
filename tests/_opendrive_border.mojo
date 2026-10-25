# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Restore the reviewed OpenDRIVE border module from the live file."""

from std.pathlib import Path

from tools._sha256 import sha256_hex


comptime _MODULE = "extensions/carla/opendrive.mojo"
"""The live OpenDRIVE file."""
comptime _LIVE_SHA256 = (
    "e65a10e92e980304186755e08988a541c1069aef988d3ba45cf3cd3f1eb19a81"
)
"""The file digest of the live OpenDRIVE module."""
comptime _RESTORED_SHA256 = (
    "9ff9b750af2c1c1a92fe3f3dfe1e49566e9d6f8c39a3576e0d4cf542bc8cdc28"
)
"""The file digest after the reviewed line edits are removed."""


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


def _load_edits(
    mut starts: List[Int], mut stops: List[Int], mut befores: List[String]
):
    """Fill the reviewed OpenDRIVE line edits, highest line first.

    Args:
        starts: The 0-based start lines.
        stops: The exclusive end lines.
        befores: The predecessor lines for each span.
    """
    starts.append(960)
    stops.append(961)
    befores.append("                _ = builder.add_signal(\n")
    starts.append(938)
    stops.append(939)
    befores.append("                _ = builder.add_signal(\n")
    starts.append(919)
    stops.append(920)
    befores.append("                builder.add_road_object_crosswalk(\n")
    starts.append(913)
    stops.append(914)
    befores.append("                            CrosswalkPoint(\n")
    starts.append(888)
    stops.append(889)
    befores.append(
        "            var reference = builder.add_signal_reference(\n"
    )
    starts.append(878)
    stops.append(879)
    befores.append("                builder.add_signal_position_inertial(\n")
    starts.append(850)
    stops.append(851)
    befores.append("            var reference = builder.add_signal(\n")
    starts.append(822)
    stops.append(823)
    befores.append(
        "            builder.add_road_elevation_profile(road, 0.0, 0.0, 0.0,"
        " 0.0, 0.0)\n"
    )
    starts.append(813)
    stops.append(814)
    befores.append("            builder.add_road_elevation_profile(\n")
    starts.append(774)
    stops.append(775)
    befores.append("            builder.create_lane_rule(\n")
    starts.append(767)
    stops.append(768)
    befores.append("            builder.create_lane_height(\n")
    starts.append(761)
    stops.append(762)
    befores.append("            builder.create_lane_access(\n")
    starts.append(754)
    stops.append(755)
    befores.append("            builder.create_lane_speed(\n")
    starts.append(742)
    stops.append(743)
    befores.append("            builder.create_lane_visibility(\n")
    starts.append(734)
    stops.append(735)
    befores.append("            builder.create_lane_material(\n")
    starts.append(722)
    stops.append(723)
    befores.append("                builder.create_road_mark_type_line(\n")
    starts.append(706)
    stops.append(707)
    befores.append("            builder.create_road_mark(\n")
    starts.append(694)
    stops.append(695)
    befores.append("            builder.create_lane_border(\n")
    starts.append(683)
    stops.append(684)
    befores.append(
        "            builder.create_lane_width(lane, s, 0.0, 0.0, 0.0, 0.0)\n"
    )
    starts.append(678)
    stops.append(679)
    befores.append("                builder.create_lane_width(\n")
    starts.append(667)
    stops.append(668)
    befores.append("            builder.create_lane_width(\n")
    starts.append(664)
    stops.append(665)
    befores.append("        var lane = builder.lane(road_id, lane_id, s)\n")
    starts.append(625)
    stops.append(626)
    befores.append(
        "        # endpoint can leave this list empty before builder"
        " validation.\n"
    )
    starts.append(404)
    stops.append(405)
    befores.append("                    CubicPolynomial(\n")
    starts.append(397)
    stops.append(398)
    befores.append("                    CubicPolynomial(\n")
    starts.append(390)
    stops.append(391)
    befores.append("                builder.add_road_geometry_param_poly3(\n")
    starts.append(377)
    stops.append(378)
    befores.append("                builder.add_road_geometry_poly3(\n")
    starts.append(366)
    stops.append(367)
    befores.append("                builder.add_road_geometry_spiral(\n")
    starts.append(362)
    stops.append(363)
    befores.append("                builder.add_road_geometry_arc(\n")
    starts.append(360)
    stops.append(361)
    befores.append(
        "                builder.add_road_geometry_line(road, s, x, y, hdg,"
        " length)\n"
    )
    starts.append(288)
    stops.append(289)
    befores.append("            var section = builder.add_road_section(\n")
    starts.append(285)
    stops.append(286)
    befores.append(
        "            builder.create_section_offset(road, 0.0, 0.0, 0.0, 0.0,"
        " 0.0)\n"
    )
    starts.append(276)
    stops.append(277)
    befores.append("            builder.create_section_offset(\n")
    starts.append(270)
    stops.append(271)
    befores.append("            builder.create_road_speed(\n")
    starts.append(248)
    stops.append(249)
    befores.append("        var road = builder.add_road(\n")


def restored_opendrive() raises -> String:
    """Return the reviewed OpenDRIVE border module.

    Returns:
        The live file with the reviewed line edits removed.

    Raises:
        Error: The live file or the restored module changed.
    """
    var live = Path(_MODULE).read_text()
    if sha256_hex(live.as_bytes()) != _LIVE_SHA256:
        raise Error(
            "reviewed border parser successor: live OpenDRIVE bytes changed"
        )
    var lines = _split(live)
    var starts = List[Int]()
    var stops = List[Int]()
    var befores = List[String]()
    _load_edits(starts, stops, befores)
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
    var restored = _join(lines)
    if sha256_hex(restored.as_bytes()) != _RESTORED_SHA256:
        raise Error(
            "reviewed border parser successor: border after bytes changed"
        )
    return restored
