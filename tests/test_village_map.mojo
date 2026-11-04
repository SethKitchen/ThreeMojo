# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""The map of the village round the player."""

from extensions.vegetation.ground import Ground, Pond
from extensions.village.map import MAP_REACH, MapHouse, MapMarks, draw_map
from math.vector3 import Vector3
from render.framebuffer import Color, Framebuffer
from std.testing import TestSuite, assert_equal, assert_true
from units.si import METER, Length


def test_the_map_shows_the_houses_the_pond_and_the_people() raises:
    var ground = Ground(
        hill_height=Length(0.0, METER),
        pond=Pond(
            Length(20.0, METER),
            Length(0.0, METER),
            Length(6.0, METER),
            Length(1.0, METER),
        ),
    )
    var marks = MapMarks()
    marks.houses.append(MapHouse(-20, 0, 6))
    marks.people.append(Vector3(5, 0, 5))
    marks.people.append(Vector3(500, 0, 5))
    marks.errands.append(Vector3(-5, 0, 5))
    marks.errands.append(Vector3(-500, 0, 5))
    marks.foes.append(Vector3(10, 0, -10))
    marks.foes.append(Vector3(10, 0, -900))
    var frame = Framebuffer(200, 200, Color(0, 0, 0, 255))
    var side = draw_map(frame, ground, marks, Vector3(0, 0, 0), 0.5)
    assert_equal(side, 72)
    var meters = 2 * MAP_REACH / Float32(side)
    # The pond is blue, the house tan, and the foe a red dot.
    var pond = frame.get_pixel(
        8 + Int((20 + MAP_REACH) / meters), 8 + side // 2
    )
    assert_true(pond.b > pond.r)
    var house = frame.get_pixel(
        8 + Int((-20 + MAP_REACH) / meters), 8 + side // 2
    )
    assert_true(house.r > 100)
    var foe = frame.get_pixel(
        8 + Int((10 + MAP_REACH) / meters), 8 + Int((-10 + MAP_REACH) / meters)
    )
    assert_true(foe.r > 200 and foe.g < 100)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
