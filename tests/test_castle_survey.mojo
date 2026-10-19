# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Tests for `extensions.castle.survey`.

The reference is the round trip: a plan written as JSON and read back is the
same plan, number for number, and its text is the same text. The refusals are
the ways a survey can be wrong: a missing key, a value of the wrong kind, an
unnamed shape and a plan that cannot stand.
"""

from std.testing import (
    TestSuite,
    assert_almost_equal,
    assert_equal,
    assert_raises,
    assert_true,
)
from extensions.castle.plan import Block, Tower, wijnendale
from extensions.castle.survey import plan_from_json, plan_to_json
from units.si import DEGREE64


def test_a_plan_survives_a_round_trip() raises:
    var plan = wijnendale()
    var text = plan_to_json(plan)
    var back = plan_from_json(text)
    assert_equal(back.name, plan.name)
    assert_almost_equal(back.latitude.value, plan.latitude.value, atol=1e-12)
    assert_almost_equal(back.longitude.value, plan.longitude.value, atol=1e-12)
    assert_equal(len(back.towers), len(plan.towers))
    for i in range(len(plan.towers)):
        assert_equal(back.towers[i].name, plan.towers[i].name)
        assert_equal(back.towers[i].shape, plan.towers[i].shape)
        assert_equal(back.towers[i].roof, plan.towers[i].roof)
        assert_almost_equal(
            back.towers[i].radius.value, plan.towers[i].radius.value
        )
        assert_almost_equal(
            back.towers[i].height.value, plan.towers[i].height.value
        )
        assert_almost_equal(
            back.towers[i].center.x.value, plan.towers[i].center.x.value
        )
        assert_almost_equal(
            back.towers[i].center.y.value, plan.towers[i].center.y.value
        )
    assert_equal(len(back.blocks), len(plan.blocks))
    for i in range(len(plan.blocks)):
        assert_equal(back.blocks[i].name, plan.blocks[i].name)
        assert_almost_equal(
            back.blocks[i].length.value, plan.blocks[i].length.value
        )
        assert_almost_equal(
            back.blocks[i].heading.to(DEGREE64),
            plan.blocks[i].heading.to(DEGREE64),
            atol=1e-9,
        )
    assert_almost_equal(back.moat.semi_x.value, plan.moat.semi_x.value)
    assert_almost_equal(
        back.moat.island_semi_y.value, plan.moat.island_semi_y.value
    )
    assert_equal(back.bridge.spans, plan.bridge.spans)
    assert_almost_equal(back.bridge.span.value, plan.bridge.span.value)
    assert_almost_equal(
        back.bridge.heading.to(DEGREE64),
        plan.bridge.heading.to(DEGREE64),
        atol=1e-9,
    )


def test_the_text_of_a_plan_is_stable() raises:
    var text = plan_to_json(wijnendale())
    assert_equal(plan_to_json(plan_from_json(text)), text)
    assert_true(text.startswith("{"))
    assert_true('"name": "Wijnendale Castle"' in text)
    assert_true('"shape": "round"' in text)
    assert_true('"roof": "gable"' in text)


def test_a_plan_without_blocks_is_written_and_read() raises:
    var plan = wijnendale()
    plan.blocks = List[Block]()
    var text = plan_to_json(plan)
    var back = plan_from_json(text)
    assert_equal(len(back.blocks), 0)
    assert_equal(len(back.towers), len(plan.towers))


def test_a_plan_without_towers_is_refused() raises:
    var plan = wijnendale()
    plan.towers = List[Tower]()
    var text = plan_to_json(plan)
    with assert_raises(contains="A castle must have a tower"):
        _ = plan_from_json(text)


def test_a_square_tower_survives() raises:
    var plan = wijnendale()
    var text = plan_to_json(plan).replace(
        '"shape": "round"', '"shape": "square"'
    )
    var back = plan_from_json(text)
    assert_equal(back.towers[0].shape.name(), "square")


def test_not_json_is_refused() raises:
    with assert_raises(contains="JSON"):
        _ = plan_from_json("this is not a survey")


def test_a_missing_part_is_refused() raises:
    var text = plan_to_json(wijnendale())
    with assert_raises(contains="A survey must list its towers"):
        _ = plan_from_json(text.replace('"towers"', '"turrets"'))
    with assert_raises(contains="A survey must list its blocks"):
        _ = plan_from_json(text.replace('"blocks"', '"ranges"'))
    with assert_raises(contains="A survey must give the moat"):
        _ = plan_from_json(text.replace('"moat"', '"water"'))
    with assert_raises(contains="A survey must give the bridge"):
        _ = plan_from_json(text.replace('"bridge"', '"crossing"'))
    with assert_raises(contains="A survey must give the text name"):
        _ = plan_from_json(
            text.replace('"name": "Wijnendale Castle"', '"title": "x"')
        )
    with assert_raises(contains="A survey must give the number latitude"):
        _ = plan_from_json(text.replace('"latitude"', '"lat"'))


def test_a_missing_number_names_the_key() raises:
    var text = plan_to_json(wijnendale())
    with assert_raises(contains="A survey must give the number radius"):
        _ = plan_from_json(text.replace('"radius": 3.6', '"r": 3.6'))
    with assert_raises(contains="A survey must give the number spans"):
        _ = plan_from_json(text.replace('"spans"', '"arches"'))


def test_a_value_of_the_wrong_kind_is_refused() raises:
    var text = plan_to_json(wijnendale())
    with assert_raises(contains="expected a number"):
        _ = plan_from_json(text.replace('"radius": 3.6', '"radius": "wide"'))
    with assert_raises(contains="expected a string"):
        _ = plan_from_json(text.replace('"shape": "round"', '"shape": 3'))


def test_a_fractional_count_of_spans_is_refused() raises:
    var text = plan_to_json(wijnendale())
    with assert_raises(contains="whole number"):
        _ = plan_from_json(text.replace('"spans": 3.0', '"spans": 2.5'))


def test_an_unnamed_shape_or_roof_is_refused() raises:
    var text = plan_to_json(wijnendale())
    with assert_raises(contains="round or square, not hexagon"):
        _ = plan_from_json(
            text.replace('"shape": "round"', '"shape": "hexagon"')
        )
    with assert_raises(contains="cone, gable or parapet, not dome"):
        _ = plan_from_json(text.replace('"roof": "cone"', '"roof": "dome"'))


def test_a_plan_that_cannot_stand_is_refused() raises:
    var text = plan_to_json(wijnendale())
    with assert_raises(contains="A tower radius must be positive"):
        _ = plan_from_json(text.replace('"radius": 3.6', '"radius": 0.0'))
    with assert_raises(contains="at least one span"):
        _ = plan_from_json(text.replace('"spans": 3.0', '"spans": 0.0'))


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
