# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md

"""Stored-moment counts, names, and output paths stay checked."""

from std.testing import TestSuite, assert_raises

from tools._moment_guards import (
    require_member,
    require_name_set,
    require_same_count,
    require_separate_output,
)


def test_the_moment_counts_and_names_hold() raises:
    """Equal counts and the same names are accepted."""
    require_same_count('{"left":4,"right":4,"message":"invalid UInt64 word"}')
    require_same_count('{"left":1.0,"right":1,"message":"binary64 overflow"}')
    require_name_set(
        '{"names":["_COS_COEFFICIENTS","_GL_NODES","_GL_NODES","_SIN_COEFFICIENTS","_GL_WEIGHTS"],'
        + '"expected":["_GL_NODES","_GL_WEIGHTS","_COS_COEFFICIENTS","_SIN_COEFFICIENTS"],'
        + '"message":"wrong constant-array set"}'
    )
    require_name_set(
        '{"names":[],"expected":[],"message":"wrong constant-array set"}'
    )


def test_a_changed_moment_count_or_name_is_refused() raises:
    """A different count or name keeps its message."""
    with assert_raises(contains="invalid UInt64 word"):
        require_same_count(
            '{"left":3,"right":4,"message":"invalid UInt64 word"}'
        )
    with assert_raises(contains="binary64 overflow"):
        require_same_count('{"left":1,"right":2,"message":"binary64 overflow"}')
    with assert_raises(contains="wrong constant-array set"):
        require_name_set(
            '{"names":["_GL_NODES","_GL_WEIGHTS","_COS_COEFFICIENTS","_SIN_COEFFICIENTS","_WORDS"],'
            + '"expected":["_GL_NODES","_GL_WEIGHTS","_COS_COEFFICIENTS","_SIN_COEFFICIENTS"],'
            + '"message":"wrong constant-array set"}'
        )
    with assert_raises(contains="wrong constant-array set"):
        require_name_set(
            '{"names":["_GL_NODES","_GL_WEIGHTS","_COS_COEFFICIENTS"],'
            + '"expected":["_GL_NODES","_GL_WEIGHTS","_COS_COEFFICIENTS","_SIN_COEFFICIENTS"],'
            + '"message":"wrong constant-array set"}'
        )


def test_a_listed_name_is_accepted() raises:
    """A name that occurs in the list is accepted."""
    require_member(
        '{"name":"a","names":["b","a","a"],"message":"missing name"}'
    )


def test_an_unlisted_name_is_refused() raises:
    """A name outside the list keeps its message."""
    with assert_raises(contains="missing name"):
        require_member(
            '{"name":"c","names":["a","b"],"message":"missing name"}'
        )
    with assert_raises(contains="missing name"):
        require_member('{"name":"a","names":[],"message":"missing name"}')


def test_separate_output_paths_hold() raises:
    """Output paths outside the protected set are accepted."""
    require_separate_output(
        '{"destinations":["/out/report.json","/out/table.mojo"],'
        + '"protected":["/repo/table.mojo","/repo/pins.json"]}'
    )
    require_separate_output(
        '{"destinations":[],"protected":["/repo/pins.json"]}'
    )


def test_an_output_path_inside_the_repository_is_refused() raises:
    """A destination that matches a protected path is refused."""
    with assert_raises(
        contains=(
            "generation cannot overwrite repository source; use a separate"
            " output directory"
        )
    ):
        require_separate_output(
            '{"destinations":["/out/report.json","/repo/table.mojo"],'
            + '"protected":["/repo/pins.json","/repo/table.mojo"]}'
        )


def main() raises:
    """Run the moment guard tests."""
    TestSuite.discover_tests[__functions_in_module()]().run()
