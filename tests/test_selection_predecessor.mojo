# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md

"""One selection predecessor restores its reviewed function."""

from std.testing import TestSuite, assert_equal, assert_raises

from tests._python_tokens import token_sha256
from tools._selection_predecessor import selection_predecessor


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


def main() raises:
    """Run the selection predecessor tests."""
    TestSuite.discover_tests[__functions_in_module()]().run()
