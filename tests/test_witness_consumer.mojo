# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""The witness consumer restores its typed endpoint and its bound input."""

from std.pathlib import Path
from std.testing import TestSuite, assert_equal, assert_raises

from tests._witness_consumer import (
    restored_witness_bound,
    restored_witness_qualification,
    restored_witness_typed_after,
    witness_endpoint,
)
from tools._sha256 import sha256_hex


comptime _PATH = "tools/carla_lane_oracle/test_witness_format_contracts.py"
"""The witness-format consumer."""
comptime _QUALIFICATION = (
    "82f7e13e72b4f99ccad63d5dfe55fc0a73c898120b43ed8416b0731489ea6f84"
)
"""The qualification endpoint digest."""
comptime _TYPED = (
    "ad002f1255ae4f545a5cbfb3b8abf3f8e883a2637656248a232b297032b178de"
)
"""The typed-boundary after digest."""
comptime _BOUND = (
    "aa279a2131c68601f9e2f3c7347d88b612d7284adab4e2258c90c4e2b432d571"
)
"""The witness bound-input digest."""


def test_the_live_witness_restores_both_endpoints() raises:
    """The live file restores the qualification, typed, and bound texts."""
    var live = Path(_PATH).read_text()
    var qualification = restored_witness_qualification(live)
    var typed = restored_witness_typed_after(live)
    var bound = restored_witness_bound(typed)
    assert_equal(witness_endpoint(qualification), 2)
    assert_equal(witness_endpoint(typed), 1)
    assert_equal(witness_endpoint(bound), 0)
    assert_equal(witness_endpoint(live), 0)
    assert_equal(sha256_hex(qualification.as_bytes()), _QUALIFICATION)
    assert_equal(sha256_hex(typed.as_bytes()), _TYPED)
    assert_equal(sha256_hex(bound.as_bytes()), _BOUND)


def test_the_bound_text_is_not_another_qualification_endpoint() raises:
    """The bound module is refused by both inverse steps."""
    var live = Path(_PATH).read_text()
    var bound = restored_witness_bound(restored_witness_typed_after(live))
    with assert_raises(contains="live module changed"):
        _ = restored_witness_qualification(bound)
    with assert_raises(contains="typed endpoint changed"):
        _ = restored_witness_bound(bound)
    with assert_raises(contains="live module changed"):
        _ = restored_witness_typed_after(live + "\n")


def main() raises:
    """Run the witness consumer tests."""
    TestSuite.discover_tests[__functions_in_module()]().run()
