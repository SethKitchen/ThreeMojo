# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Tests for the plan of Wijnendale Castle.

The plan is checked against the data it was built from. The surveyed building
has 99 corners and an area of 1151.7 m^2 (1151.55 with the corners rounded to
a centimeter). The water of the moat has 158 corners after a simplification
by 0.25 m, and an area of 7360.3 m^2 against 7382.1 m^2 before it. The solids
cover 96 percent of the surveyed building. The heights are those of the 1 m
laser scan, in meters above TAW.
"""

from extensions.castle.kinds import CONE, ESTIMATED, FLAT, MEASURED, SURVEYED
from extensions.castle.wijnendale import (
    latitude,
    longitude,
    moat_outline,
    surveyed_footprint,
    wijnendale_plan,
)
from std.testing import (
    TestSuite,
    assert_almost_equal,
    assert_equal,
    assert_true,
)
from units.si import DEGREE64, Length64


def test_the_plan_is_consistent() raises:
    var plan = wijnendale_plan()
    plan.check()
    assert_equal(plan.name, "Wijnendale Castle")
    assert_equal(len(plan.towers), 12)
    assert_equal(len(plan.wings), 2)


def test_the_site_is_where_the_record_puts_it() raises:
    assert_almost_equal(latitude().to(DEGREE64), 51.078925, atol=1e-9)
    assert_almost_equal(longitude().to(DEGREE64), 3.059483, atol=1e-9)


def test_the_surveyed_tables_have_the_corners_of_the_survey() raises:
    assert_equal(len(surveyed_footprint()), 99)
    assert_equal(len(moat_outline()), 158)
    var plan = wijnendale_plan()
    assert_almost_equal(plan.footprint_area().value, 1151.7, atol=0.5)
    assert_almost_equal(plan.moat.area().value, 7360.3, atol=1.0)


def test_the_solids_cover_the_surveyed_building() raises:
    var overlap = wijnendale_plan().footprint_overlap(Length64(0.25))
    assert_true(overlap > 0.95)
    assert_true(overlap < 0.98)


def test_the_levels_are_those_of_the_scan() raises:
    var plan = wijnendale_plan()
    assert_almost_equal(plan.moat.water_level.value, 34.31, atol=1e-9)
    assert_almost_equal(plan.moat.depth.value, 1.5, atol=1e-9)
    assert_almost_equal(plan.moat.bed().value, 32.81, atol=1e-9)
    assert_almost_equal(plan.island_level.value, 37.9, atol=1e-9)
    assert_almost_equal(plan.ground_level.value, 36.6, atol=1e-9)


def test_the_towers_reach_the_heights_of_the_scan() raises:
    var plan = wijnendale_plan()
    # The tips of the spires and the parapets, in m above TAW. The scan's
    # highest return over each tower.
    var names = [
        "Donjon",
        "North turret",
        "Courtyard turret",
        "Inner south turret",
        "South-west tower",
        "South turret",
        "South-east turret",
        "North-east turret",
    ]
    var tops = [63.59, 52.80, 55.53, 55.34, 55.21, 51.01, 53.35, 52.31]
    var radii = [3.43, 1.84, 2.22, 2.20, 2.48, 1.92, 1.91, 1.76]
    for at in range(8):
        assert_equal(plan.towers[at].name, names[at])
        assert_almost_equal(plan.towers[at].top().value, tops[at], atol=1e-9)
        assert_almost_equal(plan.towers[at].radius.value, radii[at], atol=1e-9)
        assert_equal(plan.towers[at].provenance, MEASURED)
    # The donjon is the tallest, 29 m above the water.
    assert_almost_equal(plan.towers[0].top().value - 34.31, 29.28, atol=1e-9)
    assert_equal(plan.towers[0].roof, FLAT)
    assert_equal(plan.towers[1].roof, CONE)
    assert_equal(plan.towers[4].roof, FLAT)
    # A spire rises 2.4 radii above the wall.
    assert_almost_equal(plan.towers[1].roof_height.value, 2.4 * 1.84, atol=1e-9)
    # The four towers of the courtyard wall are low.
    for at in range(8, 12):
        assert_almost_equal(plan.towers[at].radius.value, 1.45, atol=1e-9)
        assert_almost_equal(plan.towers[at].top().value, 39.2, atol=1e-9)


def test_the_wings_and_the_gate_have_the_measured_sizes() raises:
    var plan = wijnendale_plan()
    assert_almost_equal(plan.wings[0].width.value, 12.6, atol=1e-9)
    assert_almost_equal(
        plan.wings[0].base.value + plan.wings[0].eave_height.value,
        45.9,
        atol=1e-9,
    )
    assert_almost_equal(
        plan.wings[0].base.value + plan.wings[0].ridge_height.value,
        51.4,
        atol=1e-9,
    )
    assert_almost_equal(plan.wings[1].width.value, 11.1, atol=1e-9)
    assert_almost_equal(
        plan.wings[1].base.value + plan.wings[1].eave_height.value,
        46.4,
        atol=1e-9,
    )
    assert_almost_equal(
        plan.wings[1].base.value + plan.wings[1].ridge_height.value,
        50.4,
        atol=1e-9,
    )
    assert_almost_equal(plan.gate.length.value, 17.2, atol=1e-9)
    assert_almost_equal(plan.gate.width.value, 14.1, atol=1e-9)
    assert_almost_equal(plan.gate.heading.to(DEGREE64), 62.2, atol=1e-9)
    assert_almost_equal(
        plan.gate.base.value + plan.gate.height.value, 51.5, atol=1e-9
    )
    assert_equal(plan.gate.provenance, MEASURED)


def test_the_bridge_and_the_wall_are_not_passed_off_as_surveyed() raises:
    var plan = wijnendale_plan()
    # What no survey gives is an estimate, and says so.
    assert_equal(plan.bridge.provenance, ESTIMATED)
    assert_equal(plan.quay.provenance, ESTIMATED)
    assert_equal(plan.moat.provenance, SURVEYED)
    assert_equal(plan.bridge.spans, 3)
    assert_almost_equal(plan.bridge.pitch.value, 7.19, atol=1e-9)
    assert_almost_equal(plan.bridge.clear_span().value, 5.19, atol=1e-9)
    assert_almost_equal(plan.bridge.rise().value, 2.595, atol=1e-9)
    assert_almost_equal(plan.bridge.length().value, 21.57, atol=1e-9)
    assert_almost_equal(plan.bridge.width.value, 9.3, atol=1e-9)
    assert_almost_equal(
        plan.bridge.deck.value - plan.moat.water_level.value, 3.19, atol=1e-9
    )
    assert_almost_equal(plan.quay.height().value, 38.6 - 32.81, atol=1e-9)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
