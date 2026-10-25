# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Restore the reviewed sensor view endpoint from the live file."""

from std.pathlib import Path

from tools._sha256 import sha256_hex


comptime _MODULE = "extensions/carla/sensor_manager.mojo"
"""The live sensor manager."""
comptime _LIVE_SHA256 = (
    "c0b21899dabe7e21c7d8744548845c9ca31a12c2e1598eac37ba3077565a1567"
)
"""The file digest of the live sensor manager."""
comptime _MID_SHA256 = (
    "d87069be62eb405cbc976d0cba12c5d0c5e5db3d520111b788b2e9c9ca18029e"
)
"""The file digest after the first reviewed sensor edits are removed."""
comptime _RESTORED_SHA256 = (
    "6c8c81d18596601c31b4bb8e510beb814cbadd237dd8494b954c3e0663eeec82"
)
"""The file digest of the sensor view endpoint."""


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


def _live_edits(
    mut starts: List[Int], mut stops: List[Int], mut befores: List[String]
):
    """Fill the first reviewed sensor line edits, highest line first.

    Args:
        starts: The 0-based start lines.
        stops: The exclusive end lines.
        befores: The predecessor lines for each span.
    """
    starts.append(238)
    stops.append(240)
    befores.append("]  # fmt: skip\n")
    starts.append(235)
    stops.append(236)
    befores.append("")


def _view_edits(
    mut starts: List[Int], mut stops: List[Int], mut befores: List[String]
):
    """Fill the reviewed sensor view line edits, highest line first.

    Args:
        starts: The 0-based start lines.
        stops: The exclusive end lines.
        befores: The predecessor lines for each span.
    """
    starts.append(652)
    stops.append(654)
    befores.append(
        '                    attribute_float(a, "gen_cam_min", 0.1),\n         '
        '           attribute_float(a, "gen_cam_max", 1.0),\n'
    )
    starts.append(649)
    stops.append(650)
    befores.append("                slot.ca_service = CaService(\n")
    starts.append(499)
    stops.append(502)
    befores.append(
        "        self.slots = List[_Slot]()\n        self.generation_delta0 ="
        " generation_delta0\n"
    )
    starts.append(493)
    stops.append(498)
    befores.append(
        "            generation_delta0: Milliseconds from 2004-01-01 to the"
        " start of\n                the simulation. CARLA reads it from the"
        " wall clock.\n"
    )
    starts.append(474)
    stops.append(491)
    befores.append(
        "    def __init__(out self, generation_delta0: Int = 0):\n       "
        ' """Create a manager with no sensors.\n'
    )
    starts.append(470)
    stops.append(472)
    befores.append(
        "    # Milliseconds from 2004 to the start, for the CAMs' generation"
        " time.\n"
    )
    starts.append(139)
    stops.append(140)
    befores.append("    sensor_header,\n")
    starts.append(136)
    stops.append(137)
    befores.append("    optical_flow_data,\n")
    starts.append(132)
    stops.append(133)
    befores.append("    image_data,\n")
    starts.append(130)
    stops.append(131)
    befores.append("    dvs_data,\n")


def restored_sensor_view() raises -> String:
    """Return the reviewed sensor view endpoint.

    Returns:
        The live sensor manager with the reviewed line edits removed.

    Raises:
        Error: The live file or the restored module changed.
    """
    var live = Path(_MODULE).read_text()
    if sha256_hex(live.as_bytes()) != _LIVE_SHA256:
        raise Error(
            "reviewed runtime view successor: live sensor manager changed"
        )
    var starts = List[Int]()
    var stops = List[Int]()
    var befores = List[String]()
    _live_edits(starts, stops, befores)
    var middle = _apply(live, starts, stops, befores)
    if sha256_hex(middle.as_bytes()) != _MID_SHA256:
        raise Error("reviewed runtime view successor: sensor midpoint changed")
    starts.clear()
    stops.clear()
    befores.clear()
    _view_edits(starts, stops, befores)
    var restored = _apply(middle, starts, stops, befores)
    if sha256_hex(restored.as_bytes()) != _RESTORED_SHA256:
        raise Error(
            "reviewed runtime view successor: sensor view endpoint changed"
        )
    return restored
