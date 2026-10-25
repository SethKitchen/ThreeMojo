# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Restore the reviewed runtime-boundary cameras and world modules."""

from std.pathlib import Path

from tools._sha256 import sha256_hex


comptime _CAMERAS = "extensions/carla/cameras.mojo"
"""The live cameras module."""
comptime _CAMERAS_LIVE_SHA256 = (
    "f4c1bd63d6a68df99b23db9f668f8de29a50260c587c97f65d0f5e5ab80f7dd0"
)
"""The file digest of the live cameras module."""
comptime _CAMERAS_RESTORED_SHA256 = (
    "dbff553682707e52175a967b7a09618716f1c7c8ba28c17e1fa7f6225725e778"
)
"""The file digest after the reviewed cameras line edits are removed."""
comptime _WORLD = "extensions/carla/world.mojo"
"""The live world module."""
comptime _WORLD_LIVE_SHA256 = (
    "e1c17354267d5ba6f49378cb8c04bf3e60ad61b2e07c50044d3eceee2261a16e"
)
"""The file digest of the live world module."""
comptime _WORLD_MID_SHA256 = (
    "f8d8f6583eef3ea409f0c057263d9c55337c8d647806400b711afa398b88a4c1"
)
"""The file digest after the first reviewed world edit is removed."""
comptime _WORLD_RESTORED_SHA256 = (
    "0c7a44bfda063270715b20dfee7d21d08390f3db97f60c3bb9ddd959eaa6becd"
)
"""The file digest of the reviewed world boundary endpoint."""


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


def _camera_edits(
    mut starts: List[Int], mut stops: List[Int], mut befores: List[String]
):
    """Fill the reviewed cameras line edits, highest line first.

    Args:
        starts: The 0-based start lines.
        stops: The exclusive end lines.
        befores: The predecessor lines for each span.
    """
    starts.append(808)
    stops.append(844)
    befores.append("")
    starts.append(457)
    stops.append(484)
    befores.append("")
    starts.append(357)
    stops.append(358)
    befores.append("    # In degrees.\n")
    starts.append(330)
    stops.append(331)
    befores.append(
        "    return r / kannala_brandt_polynomial(half, coefficients)\n"
    )
    starts.append(289)
    stops.append(291)
    befores.append(
        "        var n = d - kannala_brandt_polynomial(theta, coefficients)\n  "
        "      var slope = -kannala_brandt_derivative(theta, coefficients)\n"
    )
    starts.append(227)
    stops.append(228)
    befores.append("def kannala_brandt_derivative(\n")
    starts.append(164)
    stops.append(206)
    befores.append("")


def _world_live_edits(
    mut starts: List[Int], mut stops: List[Int], mut befores: List[String]
):
    """Fill the first reviewed world line edit.

    Args:
        starts: The 0-based start lines.
        stops: The exclusive end lines.
        befores: The predecessor lines for each span.
    """
    starts.append(162)
    stops.append(163)
    befores.append("from std.hashlib import Hasher\n")


def _world_boundary_edits(
    mut starts: List[Int], mut stops: List[Int], mut befores: List[String]
):
    """Fill the reviewed world boundary line edits, highest line first.

    Args:
        starts: The 0-based start lines.
        stops: The exclusive end lines.
        befores: The predecessor lines for each span.
    """
    starts.append(2297)
    stops.append(2298)
    befores.append(
        "            self._apply(self.signs[s].tick_timers(dt.value))\n"
    )
    starts.append(2060)
    stops.append(2061)
    befores.append("        for landmark in self.map.landmarks_in_distance(\n")
    starts.append(753)
    stops.append(754)
    befores.append("")
    starts.append(749)
    stops.append(752)
    befores.append("")
    starts.append(744)
    stops.append(745)
    befores.append(
        "    def set_weather(mut self, weather: WeatherParameters):\n"
    )


def restored_cameras() raises -> String:
    """Return the reviewed cameras boundary endpoint.

    Returns:
        The live cameras module with the reviewed line edits removed.

    Raises:
        Error: The live file or the restored module changed.
    """
    var live = Path(_CAMERAS).read_text()
    if sha256_hex(live.as_bytes()) != _CAMERAS_LIVE_SHA256:
        raise Error("reviewed runtime boundary successor: live cameras changed")
    var starts = List[Int]()
    var stops = List[Int]()
    var befores = List[String]()
    _camera_edits(starts, stops, befores)
    var restored = _apply(live, starts, stops, befores)
    if sha256_hex(restored.as_bytes()) != _CAMERAS_RESTORED_SHA256:
        raise Error(
            "reviewed runtime boundary successor: cameras endpoint changed"
        )
    return restored


def restored_world() raises -> String:
    """Return the reviewed world boundary endpoint.

    Returns:
        The live world module with both reviewed edit tables removed.

    Raises:
        Error: The live file or the restored module changed.
    """
    var live = Path(_WORLD).read_text()
    if sha256_hex(live.as_bytes()) != _WORLD_LIVE_SHA256:
        raise Error("reviewed runtime boundary successor: live world changed")
    var starts = List[Int]()
    var stops = List[Int]()
    var befores = List[String]()
    _world_live_edits(starts, stops, befores)
    var middle = _apply(live, starts, stops, befores)
    if sha256_hex(middle.as_bytes()) != _WORLD_MID_SHA256:
        raise Error(
            "reviewed runtime boundary successor: world midpoint changed"
        )
    starts.clear()
    stops.clear()
    befores.clear()
    _world_boundary_edits(starts, stops, befores)
    var restored = _apply(middle, starts, stops, befores)
    if sha256_hex(restored.as_bytes()) != _WORLD_RESTORED_SHA256:
        raise Error(
            "reviewed runtime boundary successor: world endpoint changed"
        )
    return restored
