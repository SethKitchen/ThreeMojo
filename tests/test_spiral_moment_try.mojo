# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""The lane proof keeps its try-only reuse refusal."""

from std.pathlib import Path
from std.testing import TestSuite, assert_raises

from tools._spiral_moment_try import try_only_refusal


def _source() raises -> String:
    """Return the live curve-bounds module.

    Returns:
        The module text.

    Raises:
        Error: The file is unreadable.
    """
    return Path("extensions/carla/curve_bounds.mojo").read_text()


def _refuse(source: String, message: String) raises:
    """Require `source` to fail with `message`.

    Args:
        source: The module under test.
        message: The expected failure text.

    Raises:
        Error: The failure text differs.
    """
    with assert_raises(contains=message):
        try_only_refusal(source)


def test_the_live_proof_keeps_the_try_only_refusal() raises:
    """The live proof keeps the parameter, the refusal, and one use."""
    var source = _source()
    try_only_refusal(source)
    var comment = source.replace(
        "    elif require_reuse:\n",
        "    elif require_reuse:\n        # require_reuse stays a comment\n",
    )
    try_only_refusal(comment)
    var later = source.replace(
        "    else:\n        point = _reference_jet_capture[capture](\n",
        "    elif other:\n        point = _reference_jet_capture[capture](\n",
    )
    try_only_refusal(later)


def test_a_changed_try_only_refusal_is_refused() raises:
    """A changed parameter, refusal, or extra use is refused."""
    var source = _source()
    _refuse(
        source.replace(
            "def _lane_jet_model_proof[", "def _lane_jet_model_other["
        ),
        "missing or ambiguous function",
    )
    _refuse(
        source.replace(
            "require_reuse: Bool = False", "require_reuse: Int = False"
        ),
        "try-only parameter changed",
    )
    _refuse(
        source.replace(
            "require_reuse: Bool = False", "require_reuse: Bool = True"
        ),
        "try-only default must preserve historical callers",
    )
    _refuse(
        source.replace("    elif require_reuse:\n", "    if require_reuse:\n"),
        "try-only refusal missing",
    )
    _refuse(
        source.replace(
            "    if reused:\n",
            "    if reused:\n        return _unknown_point()\n    if reused:\n",
        ),
        "try-only refusal missing",
    )
    _refuse(
        source.replace("    elif require_reuse:\n", "    elif other:\n"),
        "try-only refusal changed",
    )
    _refuse(
        source.replace(
            (
                "        # Optional callers separately reserve their one"
                " original fallback.\n        return _unknown_point()\n"
            ),
            (
                "        # Optional callers separately reserve their one"
                " original fallback.\n        return _other()\n"
            ),
        ),
        "try-only refusal changed",
    )
    _refuse(
        source.replace(
            "    else:\n        point = _reference_jet_capture[capture](\n",
            "    if False:\n        point = _reference_jet_capture[capture](\n",
        ),
        "try-only refusal changed",
    )
    _refuse(
        source.replace(
            "    var geometry_at = info_index(road.info.geometries, low)\n",
            (
                "    var extra = require_reuse\n    var geometry_at ="
                " info_index(road.info.geometries, low)\n"
            ),
        ),
        "try-only flag has an unreviewed use",
    )
    _refuse(
        (
            "def _lane_jet_model_proof[\n    capture: Bool\n]() -> None:\n   "
            " return 0\n  return 1\n"
        ),
        "unsupported ideal source syntax",
    )


def main() raises:
    """Run the try-only refusal tests."""
    TestSuite.discover_tests[__functions_in_module()]().run()
