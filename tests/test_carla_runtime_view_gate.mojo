# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md

"""A changed runtime-view record fails the gate."""

from std.pathlib import Path
from std.testing import TestSuite, assert_raises

from tools.carla_runtime_view_gate import runtime_view


def test_a_changed_record_is_refused() raises:
    """Bytes that are not the reviewed record fail closed."""
    var empty = String("").as_bytes()
    with assert_raises(
        contains="reviewed runtime view successor: unreviewed exact step"
    ):
        _ = runtime_view(empty, empty, empty, empty, empty, empty)
    with assert_raises(
        contains="reviewed runtime view successor: unreviewed exact step"
    ):
        _ = runtime_view(
            String('{"a":1,"a":2}').as_bytes(),
            empty,
            empty,
            empty,
            empty,
            empty,
        )


def test_the_reviewed_runtime_view_record_passes() raises:
    """The reviewed record passes the digest and the repeated-key check."""
    _ = runtime_view(
        Path("tools/carla_lane_oracle/runtime-view-successor.json").read_bytes(),
        Path("tests/test_carla_event_time_quantity.mojo").read_bytes(),
        Path(
            "tests/compile_fail/carla_lane_invasion_event_time_rejects_float32_duration.mojo"
        ).read_bytes(),
        Path(
            "tests/compile_fail/carla_lane_invasion_event_time_rejects_length.mojo"
        ).read_bytes(),
        Path(
            "tests/compile_fail/carla_lane_invasion_event_time_rejects_raw_float64.mojo"
        ).read_bytes(),
        Path(
            "tests/compile_fail/carla_measurement_time_is_not_a_raw_float64.mojo"
        ).read_bytes(),
    )


def main() raises:
    """Run the runtime-view gate tests."""
    TestSuite.discover_tests[__functions_in_module()]().run()
