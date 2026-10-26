# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Map a live Sum2 module back to the bytes that its pins review.

The #792 work limits changed `extensions/carla/lane_geometry.mojo` and
`extensions/carla/map.mojo`. The PR780 successor table admits those edits.
The Sum2 pins in `tools/carla_lane_oracle` hold the two modules before them.
`reviewed_source` undoes the edits of the exact admitted bytes, so a Sum2
check reads the reviewed module. Other bytes come back unchanged, and the
check refuses them.
"""

from tools._sha256 import sha256_hex

comptime _LANE = "extensions/carla/lane_geometry.mojo"
comptime _LANE_LIVE = (
    "f0a4900cc046cf42e925ed912b6557db494eeab3f342a71d72387fe49c667be5"
)
"""The admitted bytes of `extensions/carla/lane_geometry.mojo`."""
comptime _LANE_REVIEWED = (
    "c43bf5bff2304e580beb59d1d10b125f04b1c5e7bc7897784bed54e2dd93d49b"
)
"""The bytes that the Sum2 pins review."""

comptime _MAP = "extensions/carla/map.mojo"
comptime _MAP_LIVE = (
    "4ac668239112e81ac0b2bc84eaed32d1efbee1f70e61d1d97ca02324f914f35c"
)
"""The admitted bytes of `extensions/carla/map.mojo`."""
comptime _MAP_REVIEWED = (
    "288d0e5d3a5bc2e5a6b9542868de6566dc6cb4de6eae39192c0289d76a8c99fa"
)
"""The bytes that the Sum2 pins review."""


def _undo(text: String, after: String, before: String) raises -> String:
    """Replace the one `after` in `text` with `before`.

    Args:
        text: The module.
        after: The admitted lines, with one line of context on each side.
        before: The reviewed lines, with the same context.

    Returns:
        The module with the edit undone.

    Raises:
        Error: `after` is absent.
    """
    var at = text.find(after)
    if at < 0:
        raise Error("Sum2 successor edit is missing")
    var head = String(text[byte=0:at])
    var tail = String(text[byte = at + after.byte_length() :])
    return head + before + tail


def _lane_geometry(text: String) raises -> String:
    """Undo the admitted edits of the lane geometry.

    Args:
        text: The admitted module.

    Returns:
        The reviewed module.

    Raises:
        Error: An edit is missing.
    """
    var reviewed = text
    reviewed = _undo(
        reviewed,
        (
            "refusals before unsafe indexing or integer conversion. They do not"
            " replace\nscalar witnesses with an ideal trigonometric or moment"
            " approximation. A\nspiral derivative also refuses a piece count"
            ' past the query work limit.\n"""\n'
        ),
        (
            "refusals before unsafe indexing or integer conversion. They do not"
            " replace\nscalar witnesses with an ideal trigonometric or moment"
            ' approximation.\n"""\n'
        ),
    )
    reviewed = _undo(
        reviewed,
        (
            "    Raises:\n        Error: If a SPIRAL uses an unsupported"
            " arithmetic mode, or its\n            piece count passes the query"
            ' work limit.\n    """\n'
        ),
        (
            "    Raises:\n"
            "        Error: If a SPIRAL uses an unsupported arithmetic mode.\n"
            '    """\n'
        ),
    )
    reviewed = _undo(
        reviewed,
        (
            "    var reach = max(abs(k0), abs(k0 + rate * d))\n    # The public"
            " geometry query refuses this estimate before `Int` conversion.\n  "
            "  var work = ceil(d * (1.0 + reach))\n    if not isfinite(work) or"
            " work >= 9223372036854775807.0 or work >= 4194304.0:\n       "
            ' raise Error("Geometry query exceeds its spiral work limit")\n   '
            " var pieces = 1 + Int(work)\n    var step = d / Float64(pieces)\n"
        ),
        (
            "    var reach = max(abs(k0), abs(k0 + rate * d))\n"
            "    var pieces = 1 + Int(ceil(d * (1.0 + reach)))\n"
            "    var step = d / Float64(pieces)\n"
        ),
    )
    reviewed = _undo(
        reviewed,
        (
            '            raise Error("Spiral derivative work is not'
            ' representable")\n        # A finite count past the query budget'
            " does not finish this loop.\n        if work >= 4194304.0:\n      "
            '      raise Error("Spiral derivative work exceeds its spiral work'
            ' limit")\n        var pieces = 1 + Int(work)\n'
        ),
        (
            '            raise Error("Spiral derivative work is not'
            ' representable")\n        var pieces = 1 + Int(work)\n'
        ),
    )
    return reviewed^


def _map(text: String) raises -> String:
    """Undo the admitted edits of the map.

    Args:
        text: The admitted module.

    Returns:
        The reviewed module.

    Raises:
        Error: An edit is missing.
    """
    var reviewed = text
    reviewed = _undo(
        reviewed,
        (
            "        Raises:\n            Error: If the distance is not"
            " positive, or a road needs more\n                waypoints than"
            ' this port walks.\n        """\n'
        ),
        (
            "        Raises:\n"
            "            Error: If the distance is not positive.\n"
            '        """\n'
        ),
    )
    reviewed = _undo(
        reviewed,
        (
            "        for road in self.roads:\n            if not (road.length /"
            " distance < Float64(16777216)):\n                raise Error(\n   "
            '                 "A generated waypoint count is larger than this'
            ' port walks"\n                )\n            var s = EPSILON\n'
        ),
        "        for road in self.roads:\n            var s = EPSILON\n",
    )
    return reviewed^


def reviewed_source(path: String, text: String) raises -> String:
    """Return the module that the Sum2 pins review.

    Args:
        path: The module path, relative to the repository root.
        text: The live module.

    Returns:
        The module before the admitted edits when `text` is the exact
        admitted module. Any other text unchanged.

    Raises:
        Error: The admitted module does not restore the reviewed bytes.
    """
    var digest = sha256_hex(text.as_bytes())
    var reviewed: String
    var expected: String
    if path == _LANE and digest == _LANE_LIVE:
        reviewed = _lane_geometry(text)
        expected = _LANE_REVIEWED
    elif path == _MAP and digest == _MAP_LIVE:
        reviewed = _map(text)
        expected = _MAP_REVIEWED
    else:
        return text
    if sha256_hex(reviewed.as_bytes()) != expected:
        raise Error(
            "Sum2 successor does not restore its reviewed bytes: " + path
        )
    return reviewed^
