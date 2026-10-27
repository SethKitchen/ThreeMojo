# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md

"""A changed render-actor record fails the gate."""

from std.testing import TestSuite, assert_raises

from tools.carla_render_actor_gate import render_actor_record


def test_a_changed_record_is_refused() raises:
    """Bytes that are not the reviewed record fail closed."""
    with assert_raises(
        contains="reviewed render actor reuse successor: unreviewed exact edge"
    ):
        render_actor_record(String("").as_bytes())


def main() raises:
    """Run the render-actor gate tests."""
    TestSuite.discover_tests[__functions_in_module()]().run()
