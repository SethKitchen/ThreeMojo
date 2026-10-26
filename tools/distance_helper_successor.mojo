# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Check the reviewed distance helper successor.

The live module keeps its file digest and its token digest. One import
edit restores the local helpers. Those helpers match the interval module.
A changed module or a changed helper is refused.
"""

from std.pathlib import Path

from tests._python_tokens import token_sha256
from tools._sha256 import sha256_hex
from tools.seed_count_premises import _declaration
from tools.shared_helper_routing import shared_helper_routing


comptime _DISTANCE = "extensions/carla/curve_distance.mojo"
comptime _INTERVAL = "extensions/carla/curve_interval.mojo"
comptime _AFTER_SHA = (
    "e349b4b9f7bdb417d84a9451d769c59f7ce1285a6ac99d887722dbc0ff1466e3"
)
comptime _AFTER_TOKEN = (
    "db3b5ce370465a8f4089838ec11f8a4ec4cca2ec2bd151acc1160cc962159364"
)
comptime _BEFORE_SHA = (
    "46176387129dd37a5887f3aeec7c96bbb386e4980063cb96f09619832cb09a79"
)
comptime _BEFORE_TOKEN = (
    "fcad8481ac4d5a1d088fd2c51917f111791ea32f44c7595997848593d797385b"
)
comptime _BEFORE = (
    '"""\n\nfrom std.math import inf, isfinite, isnan, sqrt\nfrom std.memory'
    " import bitcast\n\n\ndef _next_up(value: Float64) -> Float64:\n    #"
    " Observe the rounded bits before any following arithmetic. Unlike an\n   "
    " # epsilon multiplier, this also handles zero and subnormal results.\n   "
    " if isnan(value) or value == inf[DType.float64]():\n        return value\n"
    "    if value == 0.0:\n        return bitcast[DType.float64](UInt64(1))\n  "
    "  var bits = bitcast[DType.uint64](value)\n    if value < 0.0:\n       "
    " return bitcast[DType.float64](bits - 1)\n    return"
    " bitcast[DType.float64](bits + 1)\n\n\ndef _next_down(value: Float64) ->"
    " Float64:\n    return -_next_up(-value)\n\n\n"
)
comptime _AFTER = (
    '"""\n\nfrom extensions.carla.curve_interval import _next_down,'
    " _next_up\nfrom std.math import inf, isfinite, isnan, sqrt\nfrom"
    " std.memory import bitcast\n\n\n"
)
comptime _PREFIX = "reviewed shared-helper successor: "


def _fail(message: String) raises:
    """Raise a distance helper successor error.

    Args:
        message: The failure text.

    Raises:
        Error: A successor check failed.
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


def _count(text: String, span: String) -> Int:
    """Count non-overlapping copies of `span`.

    Args:
        text: The source.
        span: The exact text.

    Returns:
        The number of copies.
    """
    var count = 0
    var rest = text
    var step = span.byte_length()
    while True:
        var found = rest.find(span)
        if found < 0:
            return count
        count += 1
        var next = found + step
        var tail = String(rest[byte=next:])
        rest = tail^


def _same_helper(restored: String, interval: String, name: String) raises:
    """Require one restored helper to match the interval module.

    Args:
        restored: The distance module before the import edit.
        interval: The live interval module.
        name: The helper name.

    Raises:
        Error: The helper declaration differs.
    """
    var label = _DISTANCE + ":" + name
    var old = token_sha256(_declaration(restored, name, "", label))
    var live = token_sha256(_declaration(interval, name, "", label))
    if old != live:
        _fail("helper implementation differs: " + label)


def distance_helper_successor(root: String) raises:
    """Require the reviewed distance helper endpoint and its inverse.

    Args:
        root: The repository root.

    Raises:
        Error: The routing, the endpoint, the inverse, or a helper changed.
    """
    var base = _root(root)
    shared_helper_routing(base)
    var text = Path(base + "/" + _DISTANCE).read_text()
    if (
        sha256_hex(text.as_bytes()) != _AFTER_SHA
        or token_sha256(text) != _AFTER_TOKEN
    ):
        _fail("unknown exact endpoint: " + _DISTANCE)
    if _count(text, _AFTER) != 1:
        _fail("missing or ambiguous inverse: " + _DISTANCE + ":1")
    var restored = text.replace(_AFTER, _BEFORE)
    if (
        sha256_hex(restored.as_bytes()) != _BEFORE_SHA
        or token_sha256(restored) != _BEFORE_TOKEN
    ):
        _fail("inverse endpoint changed: " + _DISTANCE)
    var interval = Path(base + "/" + _INTERVAL).read_text()
    _same_helper(restored, interval, "_next_up")
    _same_helper(restored, interval, "_next_down")


def main() raises:
    """Check the distance helper successor of this repository.

    Raises:
        Error: The distance helper successor changed.
    """
    distance_helper_successor(".")
