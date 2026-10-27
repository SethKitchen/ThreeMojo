# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md

"""A differing premise selects the Map seed or the lane predecessor."""

from std.testing import TestSuite, assert_equal

from tools._premise_fallback import premise_fallback


def test_a_matched_premise_selects_no_predecessor() raises:
    """A match stops before the path, the name, and the owner are read."""
    assert_equal(
        premise_fallback(
            '{"matched":true,"path":"extensions/carla/map.mojo",'
            + '"name":"_try_winner_seed","owner":[]}'
        ),
        "none",
    )
    assert_equal(
        premise_fallback(
            '{"matched":0,"path":"extensions/carla/map.mojo",'
            + '"name":"_try_winner_seed","owner":[]}'
        ),
        "seed",
    )


def test_the_map_seed_requires_an_empty_owner() raises:
    """Each part of the Map seed triple can reject the seed fallback."""
    assert_equal(
        premise_fallback(
            '{"matched":false,"path":"extensions/carla/map.mojo",'
            + '"name":"_try_winner_seed","owner":[]}'
        ),
        "seed",
    )
    assert_equal(
        premise_fallback(
            '{"matched":false,"path":"extensions/carla/other.mojo",'
            + '"name":"_try_winner_seed","owner":[]}'
        ),
        "none",
    )
    assert_equal(
        premise_fallback(
            '{"matched":false,"path":"extensions/carla/map.mojo",'
            + '"name":"_other","owner":[]}'
        ),
        "none",
    )
    assert_equal(
        premise_fallback(
            '{"matched":false,"path":"extensions/carla/map.mojo",'
            + '"name":"_try_winner_seed","owner":["Box"]}'
        ),
        "none",
    )
    assert_equal(
        premise_fallback(
            '{"matched":false,"path":"extensions/carla/map.mojo",'
            + '"name":"_try_winner_seed","owner":{}}'
        ),
        "none",
    )


def test_the_lane_module_selects_the_lane_predecessor() raises:
    """The lane path is the only other reviewed predecessor."""
    assert_equal(
        premise_fallback(
            '{"matched":false,"path":"extensions/carla/lane_refinement.mojo",'
            + '"name":"_other","owner":["Box"]}'
        ),
        "lane",
    )
    assert_equal(
        premise_fallback(
            '{"matched":false,"path":"extensions/carla/geometry.mojo",'
            + '"name":"_other","owner":[]}'
        ),
        "none",
    )


def main() raises:
    """Run the premise fallback tests."""
    TestSuite.discover_tests[__functions_in_module()]().run()
