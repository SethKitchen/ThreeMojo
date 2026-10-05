# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Scalar validation contracts without models, workers or indexed storage."""

from extensions.animals.anatomy.mass import (
    _require_finite_distance,
    _require_nonnegative_candidate,
)
from std.math import inf, nan
from std.testing import TestSuite, assert_equal, assert_raises


def test_finite_distance_validator_accepts_finite_and_refuses_nonfinite() raises:
    var accepted = 0
    for value in [
        Float64(-1),
        Float64(-0.0),
        Float64(0),
        Float64(1),
        Float64(-1e300),
        Float64(1e300),
    ]:
        _require_finite_distance(value)
        accepted += 1
    assert_equal(accepted, 6)
    for value in [
        inf[DType.float64](),
        -inf[DType.float64](),
        nan[DType.float64](),
    ]:
        with assert_raises(
            contains="A sampled field must have finite valid distances"
        ):
            _require_finite_distance(value)


def test_candidate_validator_accepts_nonnegative_and_refuses_absent() raises:
    var accepted = 0
    for candidate in [0, 1]:
        _require_nonnegative_candidate(candidate)
        accepted += 1
    assert_equal(accepted, 2)
    with assert_raises(
        contains="A sampled field must have finite valid distances"
    ):
        _require_nonnegative_candidate(-1)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
