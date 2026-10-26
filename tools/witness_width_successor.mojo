# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Check the reviewed width-overflow witness successor.

The live witness keeps its file digest and its token digest. Two
formatting edits restore the historical witness. A changed witness or a
missing edit is refused.
"""

from std.pathlib import Path

from tests._python_tokens import token_sha256
from tools._sha256 import sha256_hex


comptime _PATH = "tests/test_carla_width_overflow_admission.mojo"
comptime _AFTER_SHA = (
    "f90e73f4ccb3581a112e0f38e6a4a39fc9fadac0c3688fb97087b576bddd0a42"
)
comptime _AFTER_TOKEN = (
    "498b3bfd881603a6315e0c508f2448eae08120ba8d4fe679ec182c72fa54c725"
)
comptime _BEFORE_SHA = (
    "0e96b3b91614bb4266c35372e17ce0da2a42d83e17fa413f6fa3a2e1f8eaec2a"
)
comptime _BEFORE_TOKEN = (
    "2d60ab6b1c157b4b3fa04e1d88886a41c0021015e3755114b1ec3823bce1560b"
)
comptime _BEFORE_1 = (
    "from extensions.carla.map_validation import _preflight_road_records\nfrom"
    " math.vector3 import Vector3\nfrom std.math import isfinite\nfrom"
    " std.testing import TestSuite, assert_equal, assert_false, assert_raises,"
    " assert_true\nfrom tests._lazy_taylor_controls import"
    " _whole_certificate\nfrom tests.test_carla_cross_candidate_certificates"
    " import _road\n\n"
)
comptime _AFTER_1 = (
    "from extensions.carla.map_validation import _preflight_road_records\nfrom"
    " math.vector3 import Vector3\nfrom std.math import isfinite\nfrom"
    " std.testing import (\n    TestSuite,\n    assert_equal,\n   "
    " assert_false,\n    assert_raises,\n    assert_true,\n)\nfrom"
    " tests._lazy_taylor_controls import _whole_certificate\nfrom"
    " tests.test_carla_cross_candidate_certificates import _road\n\n"
)
comptime _BEFORE_2 = (
    "    # One cell and depth zero rule out recursive search or a large"
    ' workload.\n    with assert_raises(contains="numerical accuracy limit"):\n'
    "        _run_lane_search(\n            road, 0, 0, low, high, location,"
    " certificate, pending^,\n            _ClosedIntervals(),"
    " List[_ClosedInterval](),\n            (Float64(0.0), Float64(1.0)), 1, 6,"
    " 0,\n        )\n    assert_equal(certificate.nodes, 1)\n    # One initial"
    " incumbent, three edge/center samples, one whole enclosure,\n"
)
comptime _AFTER_2 = (
    "    # One cell and depth zero rule out recursive search or a large"
    ' workload.\n    with assert_raises(contains="numerical accuracy limit"):\n'
    "        _run_lane_search(\n            road,\n            0,\n           "
    " 0,\n            low,\n            high,\n            location,\n         "
    "   certificate,\n            pending^,\n            _ClosedIntervals(),\n "
    "           List[_ClosedInterval](),\n            (Float64(0.0),"
    " Float64(1.0)),\n            1,\n            6,\n            0,\n       "
    " )\n    assert_equal(certificate.nodes, 1)\n    # One initial incumbent,"
    " three edge/center samples, one whole enclosure,\n"
)
comptime _PREFIX = "reviewed witness-format successor: "


def _fail(message: String) raises:
    """Raise a width-overflow witness error.

    Args:
        message: The failure text.

    Raises:
        Error: A witness check failed.
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


def _replace_one(
    text: String, after: String, before: String, name: String
) raises -> String:
    """Replace one exact formatting span.

    Args:
        text: The witness source.
        after: The formatted span.
        before: The historical span.
        name: The edit name.

    Returns:
        The source with that span restored.

    Raises:
        Error: The span is missing or repeated.
    """
    if _count(text, after) != 1:
        _fail("missing or ambiguous inverse: " + _PATH + ":" + name)
    return text.replace(after, before)


def witness_width_successor(root: String) raises:
    """Require the reviewed width-overflow witness and its inverse.

    Args:
        root: The repository root.

    Raises:
        Error: The witness endpoint or a formatting edit changed.
    """
    var text = Path(_root(root) + "/" + _PATH).read_text()
    if (
        sha256_hex(text.as_bytes()) != _AFTER_SHA
        or token_sha256(text) != _AFTER_TOKEN
    ):
        _fail("unknown exact formatted witness: " + _PATH)
    text = _replace_one(text, _AFTER_2, _BEFORE_2, "2")
    text = _replace_one(text, _AFTER_1, _BEFORE_1, "1")
    if (
        sha256_hex(text.as_bytes()) != _BEFORE_SHA
        or token_sha256(text) != _BEFORE_TOKEN
    ):
        _fail("historical witness endpoint changed: " + _PATH)


def main() raises:
    """Check the width-overflow witness of this repository.

    Raises:
        Error: The width-overflow witness changed.
    """
    witness_width_successor(".")
