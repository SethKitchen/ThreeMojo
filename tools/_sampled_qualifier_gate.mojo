# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Check the sampled lexical qualifier pins.

The trig and interval pins match the live modules. The bounds pin matches
the count-loop source. The lane pin matches the winner source.
"""

from tests._python_tokens import _tokenize
from tools._sha256 import sha256_hex


comptime _NAME = 1
comptime _BOUNDS = (
    "c56bab2db6acb9b6636f750e53163cb590da2a219ceced9956ed9333ba309870"
)
comptime _TRIG = (
    "6515efcba47ffa89fc169e70bd5cac27afd83fbf7535d643dc72da965a6ca069"
)
comptime _INTERVAL = (
    "91aad599895b0f02dac4126780e766df3f5c0322596821844c22d41c2239dd00"
)
comptime _LANE = (
    "04b5267f6f5954d3ccb23ac9023f8e3fd77986dd5541238a57d3ca052a6d6b00"
)


def _fail(message: String) raises:
    """Raise a sampled-qualifier error.

    Args:
        message: The failure text.

    Raises:
        Error: The qualifier check failed.
    """
    raise Error("sampled qualifier: " + message)


def _qualifier(name: String) -> Bool:
    """Return whether `name` is a lexical qualifier.

    Args:
        name: One identifier.

    Returns:
        True for `var`, `mut`, `out`, `ref`, `comptime`, or `raises`.
    """
    if name == "var":
        return True
    if name == "mut":
        return True
    if name == "out":
        return True
    if name == "ref":
        return True
    if name == "comptime":
        return True
    return name == "raises"


def _digest(source: String) raises -> String:
    """Return the qualifier digest of `source`.

    Args:
        source: One module.

    Returns:
        The SHA-256 of each qualifier and its name ordinal.

    Raises:
        Error: The source cannot be tokenized.
    """
    var kinds = List[Int]()
    var texts = List[String]()
    _tokenize(source, kinds, texts)
    var payload = String("[")
    var first = True
    var ordinal = 0
    var index = 0
    while index < len(kinds):
        if kinds[index] == _NAME:
            var name = texts[index]
            if _qualifier(name):
                if not first:
                    payload += ","
                first = False
                payload += "[" + String(ordinal) + ',"' + name + '"]'
            ordinal += 1
        index += 1
    payload += "]"
    return sha256_hex(payload.as_bytes())


def _check(source: String, pin: String, filename: String) raises:
    """Require the qualifier digest of `source` to equal `pin`.

    Args:
        source: One module.
        pin: The reviewed digest.
        filename: The module name in the failure text.

    Raises:
        Error: The source cannot be tokenized, or the digest changed.
    """
    if _digest(source) != pin:
        _fail("lexical qualifier/specialization changed: " + filename)


def sampled_qualifier_gate(
    bounds: String, trig: String, interval: String, lane: String
) raises:
    """Require the four sampled qualifier pins.

    Args:
        bounds: The count-loop `curve_bounds` source.
        trig: The live `curve_trig` module.
        interval: The live `curve_interval` module.
        lane: The winner `lane_value_bounds` source.

    Raises:
        Error: A source cannot be tokenized, or a qualifier pin changed.
    """
    _check(bounds, _BOUNDS, "curve_bounds.mojo")
    _check(trig, _TRIG, "curve_trig.mojo")
    _check(interval, _INTERVAL, "curve_interval.mojo")
    _check(lane, _LANE, "lane_value_bounds.mojo")
