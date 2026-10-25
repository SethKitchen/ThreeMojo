# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""The sampled value imports and field gate stay checked."""

from std.pathlib import Path
from std.testing import TestSuite, assert_raises

from tools.sampled_value_gate import sampled_value_gate


def _source() raises -> String:
    """Return the live lane-value module.

    Returns:
        The module text.

    Raises:
        Error: The file is unreadable.
    """
    return Path("extensions/carla/lane_value_bounds.mojo").read_text()


def _refuse(source: String, message: String) raises:
    """Require `source` to fail with `message`.

    Args:
        source: The module under test.
        message: The expected failure text.

    Raises:
        Error: The failure text differs.
    """
    with assert_raises(contains=message):
        sampled_value_gate(source)


def test_the_live_value_gate_holds() raises:
    """The live imports and the value graph keep the gate."""
    var source = _source()
    sampled_value_gate(source)
    sampled_value_gate(
        source.replace(
            "from std.math import isfinite\n",
            "from std.math import isfinite\n# value.first stays a comment\n",
        )
    )


def test_a_changed_value_gate_is_refused() raises:
    """An import edit, a derivative read, or a square-root read is refused."""
    var source = _source()
    _refuse(
        source.replace("    _stored_half,\n", "    _stored_other,\n"),
        "sampled graph imports changed",
    )
    _refuse(
        source.replace(
            (
                "from extensions.carla.road_info import _info_index_si as"
                " info_index"
            ),
            "from extensions.carla.road_info import info_index",
        ),
        "sampled graph imports changed",
    )
    _refuse(
        source.replace(
            "var first = _sample_value(geometry, d, low, translation)",
            "var first = _sample_value(geometry.sqrt, d, low, translation)",
        ),
        "derivative-field/flag read or sqrt",
    )
    _refuse(
        source.replace(
            "_without_derivatives(full[0])",
            "_without_derivatives(full[0].first)",
        ),
        "derivative-field/flag read or sqrt",
    )
    _refuse(
        source.replace(
            "_without_derivatives(full[1])",
            "_without_derivatives(full[1].second)",
        ),
        "derivative-field/flag read or sqrt",
    )
    _refuse(
        source.replace(
            "_without_derivatives(full[2])",
            "_without_derivatives(full[2].derivatives)",
        ),
        "derivative-field/flag read or sqrt",
    )
    _refuse(
        "from std.math import isfinite\ndef f():\n    return 0\n  return 1\n",
        "unsupported ideal source syntax",
    )


def main() raises:
    """Run the sampled value gate tests."""
    TestSuite.discover_tests[__functions_in_module()]().run()
