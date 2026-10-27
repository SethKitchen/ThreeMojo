# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md

"""The ideal-projection result keeps its counts and requires text."""

from std.testing import TestSuite, assert_equal, assert_raises

from tools._projection_result import projection_result, require_source_text


def test_the_projection_result_keeps_historical_order() raises:
    """The eight fields stay in the order the report reads them."""
    assert_equal(
        projection_result(
            "f0f94e038fd4a783b3ed400ffd32801ca0c3bdc54980e2c408d44f50211b9e06"
        ),
        '{"helper_projections":5,"rate_half_commutations":2,'
        + '"projected_ast_sha256":"f0f94e038fd4a783b3ed400ffd32801ca0c3bdc54980e2c408d44f50211b9e06",'
        + '"sum2_auxiliary_declarations":4,"sum2_term_definitions":2,'
        + '"sum2_auxiliary_updates":4,"sum2_error_writes":2,'
        + '"sum2_environment_guards":1}',
    )
    assert_equal(
        projection_result('say "hi"'),
        '{"helper_projections":5,"rate_half_commutations":2,'
        + '"projected_ast_sha256":"say \\"hi\\"",'
        + '"sum2_auxiliary_declarations":4,"sum2_term_definitions":2,'
        + '"sum2_auxiliary_updates":4,"sum2_error_writes":2,'
        + '"sum2_environment_guards":1}',
    )


def test_only_a_string_is_projection_source_text() raises:
    """A string is accepted, and every other JSON kind is refused."""
    require_source_text(
        '{"text":"","message":"changed ideal generic declaration"}'
    )
    require_source_text(
        '{"text":"def f():\\n","message":"ideal helper declaration or decorator'
        ' changed"}'
    )
    with assert_raises(contains="changed ideal generic declaration"):
        require_source_text(
            '{"text":1,"message":"changed ideal generic declaration"}'
        )
    with assert_raises(
        contains="ideal helper declaration or decorator changed"
    ):
        require_source_text(
            '{"text":null,"message":"ideal helper declaration or decorator'
            ' changed"}'
        )
    with assert_raises(contains="changed ideal generic declaration"):
        require_source_text(
            '{"text":true,"message":"changed ideal generic declaration"}'
        )
    with assert_raises(contains="changed ideal generic declaration"):
        require_source_text(
            '{"text":[],"message":"changed ideal generic declaration"}'
        )


def main() raises:
    """Run the projection result tests."""
    TestSuite.discover_tests[__functions_in_module()]().run()
