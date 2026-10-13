# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Refusals of pedestrian, road mark and lane transform records.

Each test changes one field of a valid record to a value that its guard
must refuse, and makes sure that the valid record stays accepted.
"""

from extensions.carla.blueprint import (
    AGE_ADULT,
    GENDER_OTHER,
    PedestrianAge,
    PedestrianGender,
    PedestrianParameters,
    make_pedestrian_definition,
)
from extensions.carla.road import Road
from extensions.carla.road_info import (
    LaneId,
    LaneMarking,
    MARK_CHANGE_BOTH,
    MarkLaneChange,
    NO_JUNCTION,
    RoadId,
    RoadInfoMarkRecord,
    SectionId,
)
from std.math import inf, nan
from std.testing import TestSuite, assert_equal, assert_raises
from units.si import Velocity


def _pedestrian() raises -> PedestrianParameters:
    return PedestrianParameters(
        "0001", GENDER_OTHER, AGE_ADULT, 1, [Velocity(0), Velocity(1.5)]
    )


def _mark(lane_change: MarkLaneChange) raises -> RoadInfoMarkRecord:
    return RoadInfoMarkRecord.from_si(
        0.0,
        0,
        "solid",
        "standard",
        "white",
        "standard",
        0.12,
        lane_change,
        0.0,
        "",
        0.0,
        True,
    )


def test_pedestrian_definition_refuses_a_changed_gender_or_age() raises:
    var valid = make_pedestrian_definition(_pedestrian())
    assert_equal(valid.id, "walker.pedestrian.0001")
    var gender = _pedestrian()
    gender.gender = PedestrianGender(3)
    with assert_raises(contains="gender or age is not valid"):
        _ = make_pedestrian_definition(gender)
    var age = _pedestrian()
    age.age = PedestrianAge(4)
    with assert_raises(contains="gender or age is not valid"):
        _ = make_pedestrian_definition(age)


def test_road_mark_record_refuses_an_invalid_lane_change() raises:
    with assert_raises(contains="Mark lane change is not valid"):
        _ = _mark(MarkLaneChange(4))


def test_lane_marking_reads_a_valid_record() raises:
    var marking = LaneMarking.from_si(_mark(MARK_CHANGE_BOTH))
    assert_equal(marking.width, 0.12)


def test_lane_transform_refuses_a_nonfinite_station() raises:
    var road = Road._from_si(
        RoadId(1), "plain", 10.0, NO_JUNCTION, RoadId(0), RoadId(0), True
    )
    _ = road.add_section_meters(SectionId(0), 0.0)
    _ = road.sections[0].add_lane(LaneId(-1))
    for bad in [nan[DType.float64](), inf[DType.float64]()]:
        with assert_raises(contains="s is off the road or nonfinite"):
            _ = road._lane_transform_si(0, 0, bad)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
