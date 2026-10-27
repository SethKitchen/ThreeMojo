# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md

"""The Sum2 result keeps its counts and the nested check records."""

from std.testing import TestSuite, assert_equal, assert_raises

from tools._sum2_result import sum2_result


def test_the_sum2_result_keeps_historical_order() raises:
    """Nested records are copied, and the fixed counts stay in order."""
    var payload = String(
        '{"projection":{"helper_projections":5,"flags":[1,true,false,null]},'
        + '"environment_guard":{"status":"PASS"}}'
    )
    assert_equal(
        sum2_result(payload),
        '{"status":"PASS","recurrence_operations":6,"correction_additions":1,'
        + '"scalar_axes":2,"initialization":"positive zero",'
        + '"term_count":"5 * pieces",'
        + '"bound":"E + (u + gamma_(n-1)^2) M",'
        + '"arithmetic_premises":"nearest rounding, gradual underflow, '
        + 'rounded terms, no reassociation or intermediate overflow",'
        + '"ideal_projection":{"helper_projections":5,"flags":[1,true,false,null]},'
        + '"environment_guard":{"status":"PASS"},'
        + '"native_codegen_qualified":false}',
    )


def test_a_missing_sum2_record_is_a_key_error() raises:
    """The result is not built without the environment guard."""
    with assert_raises(contains="KeyError: 'environment_guard'"):
        _ = sum2_result('{"projection":{}}')


def main() raises:
    """Run the Sum2 result tests."""
    TestSuite.discover_tests[__functions_in_module()]().run()
