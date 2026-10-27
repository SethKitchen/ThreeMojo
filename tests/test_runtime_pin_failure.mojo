# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md

"""A frozen runtime-pin failure is relabeled only for the reviewed cause."""

from std.testing import TestSuite, assert_equal, assert_raises

from tools._runtime_pin_failure import runtime_pin_relabel


def test_the_error_stage_stops_before_the_cause() raises:
    """An owned operation, a subclass, or different arguments stay raised."""
    assert_equal(
        runtime_pin_relabel(
            '{"stage":"error","operation":true,"exact_value_error":true,'
            + '"error_args":["unreviewed complete successor: pins"],'
            + '"expected_error":"unreviewed complete successor: pins"}'
        ),
        "raise",
    )
    assert_equal(
        runtime_pin_relabel(
            '{"stage":"error","operation":false,"exact_value_error":false,'
            + '"error_args":["unreviewed complete successor: pins"],'
            + '"expected_error":"unreviewed complete successor: pins"}'
        ),
        "raise",
    )
    assert_equal(
        runtime_pin_relabel(
            '{"stage":"error","operation":false,"exact_value_error":true,'
            + '"error_args":["other"],'
            + '"expected_error":"unreviewed complete successor: pins"}'
        ),
        "raise",
    )
    assert_equal(
        runtime_pin_relabel(
            '{"stage":"error","operation":0,"exact_value_error":true,'
            + '"error_args":["unreviewed complete successor: pins"],'
            + '"expected_error":"unreviewed complete successor: pins"}'
        ),
        "cause",
    )
    assert_equal(
        runtime_pin_relabel(
            '{"stage":"error","operation":false,"exact_value_error":true,'
            + '"error_args":[],'
            + '"expected_error":"unreviewed complete successor: pins"}'
        ),
        "raise",
    )
    assert_equal(
        runtime_pin_relabel(
            '{"stage":"error","operation":false,"exact_value_error":true,'
            + '"error_args":["one","two"],'
            + '"expected_error":"unreviewed complete successor: pins"}'
        ),
        "raise",
    )
    assert_equal(
        runtime_pin_relabel(
            '{"stage":"error","operation":false,"exact_value_error":true,'
            + '"error_args":[1],'
            + '"expected_error":"unreviewed complete successor: pins"}'
        ),
        "raise",
    )


def test_the_cause_stage_relabels_only_the_reviewed_contract() raises:
    """The cause must be the contract error with the same message."""
    assert_equal(
        runtime_pin_relabel(
            '{"stage":"cause","exact_contract_error":false,'
            + '"cause_args":["pins"],"expected_cause":"pins"}'
        ),
        "raise",
    )
    assert_equal(
        runtime_pin_relabel(
            '{"stage":"cause","exact_contract_error":true,'
            + '"cause_args":null,"expected_cause":"pins"}'
        ),
        "raise",
    )
    assert_equal(
        runtime_pin_relabel(
            '{"stage":"cause","exact_contract_error":true,'
            + '"cause_args":["other"],"expected_cause":"pins"}'
        ),
        "raise",
    )
    assert_equal(
        runtime_pin_relabel(
            '{"stage":"cause","exact_contract_error":true,'
            + '"cause_args":["pins"],"expected_cause":"pins"}'
        ),
        "relabel",
    )
    with assert_raises(contains="unreviewed runtime pin stage"):
        _ = runtime_pin_relabel('{"stage":"nope"}')


def main() raises:
    """Run the runtime-pin failure tests."""
    TestSuite.discover_tests[__functions_in_module()]().run()
