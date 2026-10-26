# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Check the reviewed Map deviation declarations.

The query certificate and the segment builder keep their token digests.
Both declarations stay on Map. A changed query or a changed builder is
refused.
"""

from std.pathlib import Path

from tests._python_tokens import token_sha256
from tools.seed_count_premises import _declaration


comptime _MAP = "extensions/carla/map.mojo"
comptime _QUERY = (
    "1614e264cd2291fc2e81b01eedaa9828d2d36719725f63718b9cfeed07f5db90"
)
comptime _BUILDER = (
    "49d94bf475d0065237818a40aac3172fb999186c78cbfb53c2eee0ec14da259f"
)
comptime _PREFIX = "reviewed Map deviation successor: "


def _fail(message: String) raises:
    """Raise a Map deviation declaration error.

    Args:
        message: The failure text.

    Raises:
        Error: A deviation declaration check failed.
    """
    raise Error(_PREFIX + message)


def _root(root: String) -> String:
    """Return `root` without a trailing slash.

    Args:
        root: The repository root.

    Returns:
        The root used to join paths.
    """
    if root.byte_length() > 1 and root.endswith("/"):
        var end = root.byte_length() - 1
        return String(root[byte=0:end])
    return root


def _declaration_digest(text: String, name: String) raises -> String:
    """Return the token digest of one Map declaration.

    Args:
        text: The Map source.
        name: The method name.

    Returns:
        The hex digest of the declaration tokens.

    Raises:
        Error: The declaration is missing or repeated.
    """
    return token_sha256(_declaration(text, name, "Map", _MAP + ":Map." + name))


def map_deviation_live(root: String) raises:
    """Require the reviewed query and segment-builder digests.

    Args:
        root: The repository root.

    Raises:
        Error: A deviation declaration changed.
    """
    var text = Path(_root(root) + "/" + _MAP).read_text()
    if (
        _declaration_digest(text, "_closest_lane_certificate_with_work")
        != _QUERY
    ):
        _fail("live query/builder changed: _closest_lane_certificate_with_work")
    if _declaration_digest(text, "_subdivide_segment") != _BUILDER:
        _fail("live query/builder changed: _subdivide_segment")


def main() raises:
    """Check the Map deviation declarations of this repository.

    Raises:
        Error: A deviation declaration changed.
    """
    map_deviation_live(".")
