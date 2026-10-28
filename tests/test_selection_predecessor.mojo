# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md

"""One selection predecessor restores its reviewed function."""

from std.testing import TestSuite, assert_equal, assert_raises

from tests._python_tokens import token_sha256
from tools._selection_predecessor import selection_predecessor
from tools.carla_selection_predecessor import (
    selection_predecessor_then_grouped,
)


def test_a_matching_function_is_restored() raises:
    """The live function is replaced by the recorded one."""
    var before = String("def f():\n    return 2\n")
    var payload = String(
        '{"path":"extensions/carla/curve_roundoff.mojo","names":["extensions/carla/curve_roundoff.mojo"],'
        + '"record_names":["extensions/carla/curve_roundoff.mojo"],'
        + '"message":"unlisted","body_message":"body changed",'
        + '"name":"f","text":"def f():\\n    return 1\\n",'
        + '"after":"def f():\\n    return 1\\n","before":"def f():\\n    return'
        ' 2\\n",'
        + '"token":"'
        + token_sha256(before)
        + '"}'
    )
    assert_equal(selection_predecessor(payload), before)


def test_an_unlisted_module_fails_before_the_grouped_table() raises:
    """The producer guard fails before the grouped table reads the geometry."""
    with assert_raises(contains="unlisted"):
        _ = selection_predecessor_then_grouped(
            '{"path":"other.mojo","names":["extensions/carla/curve_roundoff.mojo"],'
            + '"record_names":["extensions/carla/curve_roundoff.mojo"],'
            + '"message":"unlisted","body_message":"body changed","name":"f",'
            + '"text":"def f():\\n    return 1\\n","after":"def f():\\n   '
            ' return 1\\n",'
            + '"before":"def f():\\n    return 2\\n","token":"00"}',
            "nope",
        )


def test_an_unlisted_selection_module_is_refused() raises:
    """A path outside the producer set keeps the guard message."""
    with assert_raises(contains="unlisted"):
        _ = selection_predecessor(
            '{"path":"other.mojo","names":["extensions/carla/curve_roundoff.mojo"],'
            + '"record_names":["extensions/carla/curve_roundoff.mojo"],'
            + '"message":"unlisted","body_message":"body changed","name":"f",'
            + '"text":"def f():\\n    return 1\\n","after":"def f():\\n   '
            ' return 1\\n",'
            + '"before":"def f():\\n    return 2\\n","token":"00"}'
        )


def test_a_missing_name_uses_the_roundoff_envelope() raises:
    """The path chooses the envelope name when the payload omits it."""
    var before = String("def _try_spiral_roundoff_envelope():\n    return 2\n")
    var payload = String(
        '{"path":"extensions/carla/curve_roundoff.mojo","names":["extensions/carla/curve_roundoff.mojo"],'
        + '"record_names":["extensions/carla/curve_roundoff.mojo"],'
        + '"message":"unlisted","body_message":"body changed",'
        + '"text":"def _try_spiral_roundoff_envelope():\\n    return 1\\n",'
        + '"after":"def _try_spiral_roundoff_envelope():\\n    return 1\\n",'
        + '"before":"def _try_spiral_roundoff_envelope():\\n    return 2\\n",'
        + '"token":"'
        + token_sha256(before)
        + '"}'
    )
    assert_equal(selection_predecessor(payload), before)


def test_a_grouped_path_uses_the_grouped_envelope() raises:
    """A grouped proof path chooses the grouped envelope name."""
    var before = String(
        "def _try_spiral_grouped_roundoff_envelope():\n    return 2\n"
    )
    var payload = String(
        '{"path":"extensions/carla/spiral_grouped_roundoff_proof.mojo",'
        + '"names":["extensions/carla/spiral_grouped_roundoff_proof.mojo"],'
        + '"record_names":["extensions/carla/spiral_grouped_roundoff_proof.mojo"],'
        + '"message":"unlisted","body_message":"body changed",'
        + '"text":"def _try_spiral_grouped_roundoff_envelope():\\n    return'
        ' 1\\n",'
        + '"after":"def _try_spiral_grouped_roundoff_envelope():\\n    return'
        ' 1\\n",'
        + '"before":"def _try_spiral_grouped_roundoff_envelope():\\n    return'
        ' 2\\n",'
        + '"token":"'
        + token_sha256(before)
        + '"}'
    )
    assert_equal(selection_predecessor(payload), before)


def main() raises:
    """Run the selection predecessor tests."""
    TestSuite.discover_tests[__functions_in_module()]().run()
