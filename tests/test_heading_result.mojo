# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md

"""The heading result keeps the consumer count and the fixed scope."""

from std.testing import TestSuite, assert_equal, assert_raises

from tests._python_expr import checked_heading_result
from tools._heading_result import _dump, heading_result
from tools._python_json import PyJson


def test_the_heading_result_uses_the_consumer_count() raises:
    """Three consumers produce the historical result."""
    assert_equal(
        heading_result('{"consumers":3}'),
        '{"heading_consumers":3,"fresh_rate_and_heading_match":true,'
        + '"ideal_u_and_original_quadrant_phase_unchanged":true,'
        + '"scope":"Exact fresh/full-Jet heading source graph after k0'
        + " expansion; no change to ideal u, quadrant eligibility or scalar"
        + ' evaluator"}',
    )
    assert_equal(
        heading_result('{"consumers":0}'),
        '{"heading_consumers":0,"fresh_rate_and_heading_match":true,'
        + '"ideal_u_and_original_quadrant_phase_unchanged":true,'
        + '"scope":"Exact fresh/full-Jet heading source graph after k0'
        + " expansion; no change to ideal u, quadrant eligibility or scalar"
        + ' evaluator"}',
    )


def test_a_consumer_count_must_be_an_integer() raises:
    """A float or a boolean is not the map size."""
    with assert_raises(contains="heading consumer count changed"):
        _ = heading_result('{"consumers":3.0}')
    with assert_raises(contains="heading consumer count changed"):
        _ = heading_result('{"consumers":true}')


def test_json_text_keeps_false_and_null() raises:
    """False, null, and a list use Python's JSON spellings."""
    var doc = PyJson.parse('{"ok":false,"items":[1,null]}')
    assert_equal(_dump(doc, doc.root), '{"ok":false,"items":[1,null]}')


def test_a_heading_graph_fails_before_the_result() raises:
    """A changed heading graph is reported before the result is built."""
    var payload = (
        '{"fresh":"def f():\\n    return 1\\n",'
        + '"eligibility":"def g():\\n    return 1\\n",'
        + '"consumers":['
        + '{"file":"a.mojo","name":"a","text":"def a():\\n    return 1\\n"},'
        + '{"file":"b.mojo","name":"b","text":"def b():\\n    return 1\\n"},'
        + '{"file":"c.mojo","name":"c","text":"def c():\\n    return 1\\n"}]}'
    )
    with assert_raises(
        contains="missing or ambiguous function: _spiral_expression"
    ):
        _ = checked_heading_result(payload)


def test_a_missing_heading_consumer_fails_before_the_result() raises:
    """The consumer list is required before the result count is written."""
    with assert_raises(contains="KeyError: 'consumers'"):
        _ = checked_heading_result('{"fresh":"def f():\\n    return 1\\n"}')


def main() raises:
    """Run the heading result tests."""
    TestSuite.discover_tests[__functions_in_module()]().run()
