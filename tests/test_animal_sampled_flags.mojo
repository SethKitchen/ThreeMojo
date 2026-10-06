# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Bounded post-join scalar flag validation, without geometry or workers."""

from extensions.animals.anatomy.mass import (
    INVALID_FIELD,
    STATS,
    _check_sampled_fields,
)
from std.testing import TestSuite, assert_equal, assert_raises


def test_completed_zero_flags_are_accepted_without_mutation() raises:
    var stats = List[Float64](length=2 * STATS, fill=3.0)
    stats[INVALID_FIELD] = 0.0
    stats[STATS + INVALID_FIELD] = 0.0
    var before = stats.copy()
    _check_sampled_fields(stats, 2)
    for i in range(len(stats)):
        assert_equal(stats[i], before[i])


def test_each_completed_worker_failure_raises_without_mutation() raises:
    for task in range(2):
        var stats = List[Float64](length=2 * STATS, fill=0.0)
        stats[task * STATS + INVALID_FIELD] = 1.0
        var before = stats.copy()
        with assert_raises(
            contains="A sampled field must have finite valid distances"
        ):
            _check_sampled_fields(stats, 2)
        for i in range(len(stats)):
            assert_equal(stats[i], before[i])


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
