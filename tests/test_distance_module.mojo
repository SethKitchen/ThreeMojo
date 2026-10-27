# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md

"""The spiral-domain proof path stays reviewed."""

from std.testing import TestSuite, assert_equal

from tools.carla_distance_gate import distance_module


def test_the_spiral_domain_proof_path_stays_reviewed() raises:
    """The distance check reads the spiral-domain proof."""
    assert_equal(distance_module(), "extensions/carla/spiral_domain_proof.mojo")


def main() raises:
    """Run the distance-module test."""
    TestSuite.discover_tests[__functions_in_module()]().run()
