# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""An OpenDRIVE road with no lanes record.

A road can have no `<lanes>` record. Then the lane parser adds no section.
"""

from extensions.carla.opendrive import load_opendrive
from std.testing import TestSuite, assert_equal


def _road(lanes: String) -> String:
    # A straight 10 m road along +x from the origin.
    return (
        '<OpenDRIVE><road id="1" length="10" junction="-1" rule="RHT">'
        + '<planView><geometry s="0" x="0" y="0" hdg="0" length="10">'
        + "<line/></geometry></planView>"
        + lanes
        + "</road></OpenDRIVE>"
    )


def test_road_without_lanes_record_has_no_lanes() raises:
    var map = load_opendrive(_road(""))
    assert_equal(len(map.roads), 1)
    assert_equal(len(map.roads[0].sections), 0)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
