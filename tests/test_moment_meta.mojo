# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md

"""The stored-moment report meta keeps historical field order."""

from std.testing import TestSuite, assert_equal, assert_raises

from tools._moment_report import moment_meta


def test_the_report_meta_keeps_pin_order() raises:
    """Nested digests follow the pin file, and extra fields stay out."""
    var payload = String(
        '{"payload":{"byte_count":22528.0,"source_sha256":"aa",'
        + '"be64_sha256":"bb","extra":1},"root":"say \\"hi\\"",'
        + '"projection":{"helper_projections":5,"rate_half_commutations":2,'
        + '"projected_ast_sha256":"cc","sum2_auxiliary_declarations":4},'
        + '"dependencies":{"group":"stored_arithmetic","paths":'
        + '["extensions/carla/curve_interval.mojo"]},'
        + '"routing":{"ideal_caller":{"path":"p","sha256":"dd"},'
        + '"trig":{"sha256":"ee"}},'
        + '"blocks":{"ideal_spiral":{"sha256":"ff"}}}'
    )
    assert_equal(
        moment_meta(payload),
        '{"byte_count":22528.0,"source_sha256":"aa","be64_sha256":"bb",'
        + '"root":"say \\"hi\\"","ideal_half_projection":'
        + '{"helper_projections":5,"rate_half_commutations":2,'
        + '"projected_ast_sha256":"cc"},"dependency_scope":'
        + '{"group":"stored_arithmetic","paths":'
        + '["extensions/carla/curve_interval.mojo"]},'
        + '"routing_sha256":{"ideal_caller":"dd","trig":"ee"},'
        + '"source_block_sha256":{"ideal_spiral":"ff"}}',
    )


def test_empty_pin_groups_stay_empty_objects() raises:
    """A report with no routing or block pins still has both objects."""
    var payload = String(
        '{"payload":{"byte_count":1,"source_sha256":"a","be64_sha256":"b"},'
        + '"root":"r","projection":{"helper_projections":5,'
        + '"rate_half_commutations":2,"projected_ast_sha256":"c"},'
        + '"dependencies":{},"routing":{},"blocks":{}}'
    )
    assert_equal(
        moment_meta(payload),
        '{"byte_count":1,"source_sha256":"a","be64_sha256":"b","root":"r",'
        + '"ideal_half_projection":{"helper_projections":5,'
        + '"rate_half_commutations":2,"projected_ast_sha256":"c"},'
        + '"dependency_scope":{},"routing_sha256":{},'
        + '"source_block_sha256":{}}',
    )


def test_a_missing_digest_is_a_key_error() raises:
    """A routing record without `sha256` fails with Python's key text."""
    var payload = String(
        '{"payload":{"byte_count":1,"source_sha256":"a","be64_sha256":"b"},'
        + '"root":"r","projection":{"helper_projections":5,'
        + '"rate_half_commutations":2,"projected_ast_sha256":"c"},'
        + '"dependencies":{},"routing":{"ideal_caller":{}},"blocks":{}}'
    )
    with assert_raises(contains="KeyError: 'sha256'"):
        _ = moment_meta(payload)


def main() raises:
    """Run the report meta tests."""
    TestSuite.discover_tests[__functions_in_module()]().run()
