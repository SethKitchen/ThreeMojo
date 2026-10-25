# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""The reviewed sample-dispatch count loop keeps its two sources."""

from std.testing import TestSuite, assert_false, assert_true

from tests._border_pin_predecessor import restored_dispatch_border
from tests._winner_pin_predecessor import restored_count_bounds
from tools._sha256 import sha256_hex


comptime _DISPATCH_SHA256 = (
    "91ede65bbc39ac57ca54239513b462d3c71e90cacd085b8bafb2bff514767a86"
)
"""The reviewed dispatch digest for the count loop."""
comptime _BOUNDS_SHA256 = (
    "a57a5fa078fc6f36389a0abdce1eaa483a1cb7b7325688689a5602e8680ca3fb"
)
"""The reviewed bounds digest for the count loop."""


def _admitted(dispatch: String, bounds: String) -> Bool:
    """Return whether the two sources are the reviewed count-loop pair.

    Args:
        dispatch: The sample-dispatch source.
        bounds: The curve-bounds source.

    Returns:
        True when both digests match the reviewed pins.
    """
    return (
        sha256_hex(dispatch.as_bytes()) == _DISPATCH_SHA256
        and sha256_hex(bounds.as_bytes()) == _BOUNDS_SHA256
    )


def _replace_all(text: String, before: String, after: String) raises -> String:
    """Replace every `before` and require at least one.

    Args:
        text: The source.
        before: The premise text.
        after: The mutated text.

    Returns:
        The source with every premise replaced.

    Raises:
        Error: The premise is absent.
    """
    var out = String()
    var rest = text
    var found = False
    while True:
        var at = rest.find(before)
        if at < 0:
            if not found:
                raise Error("count loop premise missing")
            return out + rest
        found = True
        out += String(rest[byte=:at])
        out += after
        var tail = String(rest[byte = at + before.byte_length() :])
        rest = tail


def test_the_count_loop_keeps_its_reviewed_sources() raises:
    """The dispatch border and the bounds dependency admit the count loop."""
    var dispatch = restored_dispatch_border()
    var bounds = restored_count_bounds()
    assert_true(_admitted(dispatch, bounds))
    assert_false(_admitted(dispatch + "\n", bounds))
    assert_false(_admitted(dispatch, ""))


def test_a_changed_count_loop_source_is_refused() raises:
    """A guard edit, a range shadow, or a bounds edit removes the proof."""
    var dispatch = restored_dispatch_border()
    var bounds = restored_count_bounds()
    var edits = List[String]()
    edits.append("if count < 1 or count > 2:")
    edits.append("var count = last - first")
    edits.append("    var one = 0.0")
    edits.append("for i in range(count):")
    edits.append("        return None\n    var extra = 8 * count")
    for edit in edits:
        var changed = _replace_all(dispatch, edit, "False")
        assert_false(_admitted(changed, bounds))
    var counted = _replace_all(
        dispatch, "    var one = 0.0", "    count = 0\n    var one = 0.0"
    )
    assert_false(_admitted(counted, bounds))
    var mutated = _replace_all(
        dispatch,
        "    var one = 0.0",
        "    _mutate_count(count)\n    var one = 0.0",
    )
    mutated += "\ndef _mutate_count(mut value: Int):\n    value = 0\n"
    assert_false(_admitted(mutated, bounds))
    var ranged = (
        dispatch + "\ndef range(value: Int) -> List[Int]:\n    return []\n"
    )
    assert_false(_admitted(ranged, bounds))
    assert_false(_admitted(dispatch + "\nfrom custom import range\n", bounds))
    assert_false(_admitted(dispatch + "\nfrom custom import *\n", bounds))
    assert_false(_admitted("# for i in range(count):\n", bounds))
    var bounds_changed = _replace_all(
        bounds,
        "def _sample_index(geometry: RoadGeometry, d: Float64) -> Int:",
        "def _sample_index(geometry: RoadGeometry, d: Float64) -> Float64:",
    )
    assert_false(_admitted(dispatch, bounds_changed))


def main() raises:
    """Run the count-loop proof tests."""
    TestSuite.discover_tests[__functions_in_module()]().run()
