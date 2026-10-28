# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Restore the reviewed render-actor ledger endpoint from the live file."""

from std.pathlib import Path

from tools._sha256 import sha256_hex


comptime _MODULE = "extensions/carla/render_actors.mojo"
"""The live render-actor file."""
comptime _LIVE_SHA256 = (
    "c02c21db4d3552636ecd8fdcaec82bbb747f297e52e223ae4b7d8650d88a009e"
)
"""The file digest of the live render-actor module."""
comptime _RESTORED_SHA256 = (
    "0169a2466ef2cfe970e5e53b3311ea8cf81e481d11f668c531c2ca545497cdcc"
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
    """Fill the reviewed render-actor line edits, highest line first.

    Args:
        starts: The 0-based start lines.
        stops: The exclusive end lines.
        befores: The predecessor lines for each span.
    """
    starts.append(1311)
    stops.append(1312)
    befores.append(
        "                assets, box, body_style_of(type_id, box.extent.z *"
        " 2)\n"
    )
    starts.append(1045)
    stops.append(1077)
    befores.append("def stride(speed: Float32) -> Angle:\n")
    starts.append(867)
    stops.append(868)
    befores.append("    var axle = length / 2 - wheel_inset(length)\n")
    starts.append(863)
    stops.append(865)
    befores.append(
        "    var body = body_geometry(length, body_width, height, style)\n   "
        " var cabin = cabin_geometry(length, body_width, height, style)\n"
    )
    starts.append(779)
    stops.append(811)
    befores.append("def wheel_inset(length: Float32) -> Float32:\n")
    starts.append(741)
    stops.append(742)
    befores.append(
        "    var cabin = loft(stations, half, bottom, top, 0.22, BODY_RING)\n"
    )
    starts.append(647)
    stops.append(700)
    befores.append("")
    starts.append(643)
    stops.append(644)
    befores.append(
        "    return loft(stations, half, bottom, top, 0.06, BODY_RING)\n"
    )
    starts.append(619)
    stops.append(620)
    befores.append("    var axle = length / 2 - wheel_inset(length)\n")
    starts.append(547)
    stops.append(598)
    befores.append("")
    starts.append(375)
    stops.append(456)
    befores.append("")
    starts.append(235)
    stops.append(275)
    befores.append(
        "def body_style_of(type_id: String, height: Float32) -> BodyStyle:\n"
    )
    starts.append(33)
    stops.append(40)
    befores.append("")


def restored_render_actors() raises -> String:
    """Return the reviewed render-actor ledger endpoint.

    Returns:
        The live file with the reviewed line edits removed.

    Raises:
        Error: The live file or the restored module changed.
    """
    var live = Path(_MODULE).read_text()
    if sha256_hex(live.as_bytes()) != _LIVE_SHA256:
        raise Error(
            "reviewed consumer successor ledger: live render actors changed"
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
            "reviewed consumer successor ledger: ledger endpoint changed"
        )
    return restored
