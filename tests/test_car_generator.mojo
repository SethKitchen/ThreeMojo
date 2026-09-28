# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Tests for `generators.car`, three.js's `CarGenerator`.

The expected numbers follow from three.js r186's
`examples/jsm/generators/city/CarGenerator.js`. A sedan's body lofts
through twenty stations: the eight of its profile and seven round each
axle, less the two that land on a profile station. Its parts count
`11 * 20 + 10 + 10` body vertices, 15 for a bowed pane and 4 for a flat
one, 10 for the roof, 100, 50, 26 and 10 for a tyre, a lip, a hub and a
well, and 24 for a mirror.
"""

from core.buffer_geometry import BufferGeometry, NORMAL, POSITION
from generators.car import (
    BodyType,
    CAR_BODY,
    CAR_FRONT,
    CAR_REAR,
    CAR_SIGN,
    CAR_TRIM,
    CarGenerator,
    CarPlacement,
    CarSpec,
    SEDAN,
    SUV,
    TAXI,
    TAXI_COLOR,
    body_section,
    body_stations,
    body_type_of,
    build_body,
    car_geometry,
    panel,
)
from generators.utils import PART_ID, Vec3d
from math.matrix4 import Matrix4
from std.testing import (
    TestSuite,
    assert_almost_equal,
    assert_equal,
    assert_false,
    assert_raises,
    assert_true,
)


def _count(geometry: BufferGeometry, id: Int) raises -> Int:
    """Return how many vertices carry a part code."""
    ref ids = geometry.attribute_view(String(PART_ID))
    var n = 0
    for i in range(ids.count()):
        n += 1 if Int(ids.component(i, 0)) == id else 0
    return n


def test_body_stations_match_three() raises:
    """A set of stations: the profile's, and the arches', each once."""
    var sedan = body_stations(CarSpec(SEDAN))
    assert_equal(len(sedan), 20)
    assert_equal(sedan[0], 2.25)
    assert_equal(sedan[19], -2.25)
    for i in range(19):
        assert_true(sedan[i] > sedan[i + 1])
    assert_equal(len(body_stations(CarSpec(SUV))), 20)


def test_body_sections_lift_over_the_wheels() raises:
    """The sill sits at 0.28 away from a wheel and rides the arch over
    it; the section is the mirrored left half, then the right half
    backward."""
    var spec = CarSpec(SEDAN)
    var nose = body_section(spec, 2.25)
    assert_equal(len(nose), 10)
    assert_almost_equal(nose[0].x, Float32(-0.79 * 0.82), atol=1e-6)
    assert_almost_equal(nose[0].y, 0.28, atol=1e-6)
    assert_almost_equal(nose[4].x, Float32(-0.79 * 0.52), atol=1e-6)
    assert_almost_equal(nose[5].x, Float32(0.79 * 0.52), atol=1e-6)
    assert_almost_equal(nose[9].x, Float32(0.79 * 0.82), atol=1e-6)
    var axle = body_section(spec, 1.38)
    assert_almost_equal(axle[0].y, Float32(0.35 + 0.405), atol=1e-6)
    # Halfway between two profile rows, the width is halfway too.
    var mid = body_section(spec, (0.75 - 0.45) / 2)
    assert_almost_equal(mid[2].x, -0.92, atol=1e-6)
    # Past the last row the last two rows extrapolate.
    var tail = body_section(spec, -2.25)
    assert_almost_equal(tail[2].x, -0.81, atol=1e-6)


def test_body_caps_are_the_front_and_the_rear() raises:
    """The flat caps at the nose and the tail are tagged apart."""
    var body = build_body(CarSpec(SEDAN))
    assert_equal(body.vertex_count(), 11 * 20 + 20)
    assert_equal(_count(body, CAR_FRONT.value), 10)
    assert_equal(_count(body, CAR_REAR.value), 10)
    assert_equal(_count(body, CAR_BODY.value), 220)


def test_whole_cars_match_three() raises:
    """The sedan, the SUV with its rails, and the taxi with its sign."""
    var sedan = car_geometry(CarSpec(SEDAN))
    var wheels = 4 * (100 + 50 + 26 + 10)
    var common = 240 + 2 * 15 + 2 * 4 + 10 + wheels + 2 * 24
    assert_equal(sedan.vertex_count(), common)
    assert_equal(_count(sedan, CAR_TRIM.value), 4 * 10)
    var suv = car_geometry(CarSpec(SUV))
    assert_equal(suv.vertex_count(), common + 2 * 28)
    assert_equal(_count(suv, CAR_TRIM.value), 4 * 10 + 2 * 28)
    var taxi = car_geometry(CarSpec(TAXI))
    assert_equal(taxi.vertex_count(), common + 18)
    assert_equal(_count(taxi, CAR_SIGN.value), 18)
    var bounds = sedan.bounding_box()
    assert_almost_equal(bounds.min.y, 0, atol=1e-5)
    assert_almost_equal(bounds.max.z, 2.25, atol=1e-5)
    assert_almost_equal(bounds.min.z, -2.25, atol=1e-5)


def test_panels_bow_when_curved() raises:
    """A flat panel is one quad; a curved one bows out at its middle."""
    var corners: List[Vec3d] = [
        Vec3d(0, 0, 0),
        Vec3d(1, 0, 0),
        Vec3d(1, 1, 0),
        Vec3d(0, 1, 0),
    ]
    var flat = panel(corners, CAR_BODY, False)
    assert_equal(flat.vertex_count(), 4)
    assert_equal(len(flat.index), 6)
    var bowed = panel(corners, CAR_BODY, True)
    assert_equal(bowed.vertex_count(), 15)
    assert_equal(len(bowed.index), 48)
    # The middle vertex, u 0.5 and v 0.5: lifted 0.0175, bowed 0.025.
    var middle = bowed.attribute_view(String(POSITION)).vector3(7)
    assert_almost_equal(middle.y, 0.5175, atol=1e-6)
    assert_almost_equal(middle.z, 0.025, atol=1e-6)


def test_bodies_are_dealt_as_three() raises:
    """The taxi's yellow takes the taxi; the rest split by a hash."""
    assert_true(body_type_of(5, TAXI_COLOR) == TAXI)
    assert_true(body_type_of(0, 0x111216) == SUV)
    assert_true(body_type_of(1, 0x111216) == SEDAN)
    assert_true(body_type_of(2, 0x111216) == SUV)
    assert_true(body_type_of(3, 0x111216) == SEDAN)


def test_the_fleet_is_grouped_by_body() raises:
    """One set of instances a body, in first-seen order, with paint."""
    var moved = Matrix4()
    moved.elements[12] = 3
    var cars: List[CarPlacement] = [
        CarPlacement(Matrix4(), TAXI_COLOR),
        CarPlacement(Matrix4(), 0x111216),
        CarPlacement(moved, 0xE9E8E3),
        CarPlacement(Matrix4(), 0xB2B5B8),
    ]
    var groups = CarGenerator().build(cars)
    assert_equal(len(groups), 3)
    assert_equal(groups[0].count(), 1)
    assert_equal(groups[1].count(), 2)
    assert_equal(groups[2].count(), 1)
    assert_equal(groups[0].name, "Car")
    assert_equal(groups[0].item_size, 3)
    assert_almost_equal(groups[0].values[0], 0.913098651791473, atol=1e-6)
    assert_almost_equal(groups[0].values[1], 0.5583403896257968, atol=1e-6)
    assert_almost_equal(groups[0].values[2], 0.009134058699157796, atol=1e-7)
    assert_equal(len(groups[1].values), 6)
    assert_equal(groups[2].matrices[0].elements[12], 3)
    assert_true(groups[1].cast_shadow)
    assert_equal(len(CarGenerator().build(List[CarPlacement]())), 0)


def test_an_unknown_body_is_refused() raises:
    """Only the sedan, the SUV and the taxi are built."""
    assert_false(BodyType(3).is_valid())
    with assert_raises(contains="car body"):
        _ = CarSpec(BodyType(3))
    with assert_raises(contains="car body"):
        _ = CarSpec(BodyType(-1))


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
