# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md

"""A changed runtime-view record fails the gate."""

from std.testing import TestSuite, assert_raises

from tools.carla_runtime_view_gate import runtime_view


def test_a_changed_record_is_refused() raises:
    """Bytes that are not the reviewed record fail closed."""
    var empty = String("").as_bytes()
    with assert_raises(
        contains="reviewed runtime view successor: unreviewed exact step"
    ):
        _ = runtime_view(empty, empty, empty, empty, empty, empty)


def main() raises:
    """Run the runtime-view gate tests."""
    TestSuite.discover_tests[__functions_in_module()]().run()
