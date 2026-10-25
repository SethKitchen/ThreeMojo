# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Admission for the reviewed speed and rtree loop proofs."""

from tools._sha256 import sha256_hex


comptime SPEED = "extensions/carla/speed_limits"
"""The speed module whose byte loop is reviewed."""
comptime RTREE = "extensions/carla/rtree"
"""The rtree module whose frontier loop is reviewed."""
comptime _SPEED_FILE = "extensions/carla/speed_limits.mojo"
"""The speed source."""
comptime _RTREE_FILE = "extensions/carla/rtree.mojo"
"""The rtree source."""
comptime _MAP_FILE = "extensions/carla/map.mojo"
"""The Map source the frontier callers include."""
comptime _SELECTOR_FILE = "tests/_published_seed_selector.mojo"
"""The published seed selector."""
comptime _WITNESS_FILE = "tests/test_small_loop_witnesses.mojo"
"""The small-loop witness."""
comptime _SPEED_SHA256 = (
    "2d9d5401b3dabf53c1c19f0a8098009275e19edb978f5ae369596fe7ac6557a0"
)
"""The reviewed speed digest."""
comptime _RTREE_SHA256 = (
    "be63ea929c25e0a55600d19568e5f8a117e2f712850ea3da0d977c39b002d460"
)
"""The reviewed rtree digest."""
comptime _MAP_SHA256 = (
    "52dd32213d64275be94ba714bc9b6a57c28f5ba1303525ef1a1aac20b4743c07"
)
"""The reviewed historical Map digest."""
comptime _SELECTOR_SHA256 = (
    "fbab95376d7b6c1bc2e04b1e0f3f20ae5c125af8eda403e2a54ea6d8bc3c8a93"
)
"""The reviewed seed-selector digest."""
comptime _WITNESS_SHA256 = (
    "8f768e04ecaebdb132cf359819be03cb039d5a546b823674c22ac06a1b790362"
)
"""The reviewed witness digest."""


def _ident(byte: UInt8) -> Bool:
    """Return whether `byte` can continue an identifier.

    Args:
        byte: One source byte.

    Returns:
        True for an ASCII letter, digit, or underscore.
    """
    return (
        (byte >= 48 and byte <= 57)
        or (byte >= 65 and byte <= 90)
        or (byte >= 97 and byte <= 122)
        or byte == 95
    )


def _has_word(text: String, word: String) -> Bool:
    """Return whether `word` occurs on an identifier boundary.

    Args:
        text: The source.
        word: The identifier.

    Returns:
        True when `word` is not part of a longer identifier.
    """
    var data = text.as_bytes()
    var needle = word.as_bytes()
    var index = 0
    while index + len(needle) <= len(data):
        var matched = True
        var offset = 0
        while offset < len(needle):
            if data[index + offset] != needle[offset]:
                matched = False
                break
            offset += 1
        if matched:
            var before = index == 0 or not _ident(data[index - 1])
            var after_at = index + len(needle)
            var after = after_at == len(data) or not _ident(data[after_at])
            if before and after:
                return True
        index += 1
    return False


def _frontier_caller(text: String) -> Bool:
    """Return whether `text` calls the private rtree frontier.

    Args:
        text: One Mojo source.

    Returns:
        True when the source names `_nearest_begin` or `_nearest_next`.
    """
    return _has_word(text, "_nearest_begin") or _has_word(text, "_nearest_next")


def speed_loop_admitted(text: String) -> Bool:
    """Return whether `text` is the reviewed speed loop source.

    Args:
        text: The speed module.

    Returns:
        True when the digest is the reviewed speed pin.
    """
    return sha256_hex(text.as_bytes()) == _SPEED_SHA256


def rtree_loop_admitted(paths: List[String], texts: List[String]) -> Bool:
    """Return whether these files are the reviewed rtree frontier proof.

    Args:
        paths: Repository-relative Mojo paths.
        texts: The source of each path, in the same order.

    Returns:
        True when the four reviewed digests match and those files are the
        only frontier callers.
    """
    var saw_rtree = False
    var saw_map = False
    var saw_selector = False
    var saw_witness = False
    var callers = 0
    var index = 0
    while index < len(paths):
        var path = paths[index]
        var text = texts[index]
        var digest = sha256_hex(text.as_bytes())
        if path == _RTREE_FILE:
            if digest != _RTREE_SHA256:
                return False
            saw_rtree = True
        elif path == _MAP_FILE:
            if digest != _MAP_SHA256:
                return False
            saw_map = True
        elif path == _SELECTOR_FILE:
            if digest != _SELECTOR_SHA256:
                return False
            saw_selector = True
        elif path == _WITNESS_FILE:
            if digest != _WITNESS_SHA256:
                return False
            saw_witness = True
        if path.endswith(".mojo") and _frontier_caller(text):
            callers += 1
            if (
                path != _RTREE_FILE
                and path != _MAP_FILE
                and path != _SELECTOR_FILE
                and path != _WITNESS_FILE
            ):
                return False
        index += 1
    return (
        saw_rtree and saw_map and saw_selector and saw_witness and callers == 4
    )
