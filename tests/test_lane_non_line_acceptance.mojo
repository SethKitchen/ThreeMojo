# Required acceptance controls for the held broad lane-nearest contract.
# This suite is expected to FAIL until non-LINE all-basin refinement is fixed.
# Do not include its failures in the supported-LINE patch's passing gate.

from extensions.carla.opendrive import load_opendrive
from math.vector3 import Vector3
from std.testing import TestSuite, assert_almost_equal, assert_true


def _required_non_line(geometry: String) raises:
    var map = load_opendrive(
        String(
            (
                '<OpenDRIVE><road id="1" length="0.001001" junction="-1"'
                ' rule="RHT"><planView><geometry s="0" x="0" y="0" hdg="0"'
                ' length="0.001001">'
            ),
            geometry,
            (
                '</geometry></planView><lanes><laneOffset s="0"'
                ' a="0.00039575"'
                ' b="-6.7925" c="18200" d="-13000000"/><laneSection s="0">'
                '<center><lane id="0" type="none"/></center><right><lane'
                ' id="-1"'
                ' type="driving"><width sOffset="0" a="0.0002" b="0" c="0"'
                ' d="0"/>'
                "</lane></right></laneSection></lanes></road></OpenDRIVE>"
            ),
        )
    )
    var point = Vector3(Float32(0.0009), Float32(0.0005525), 0)
    var nearest = map.certified_closest_waypoint_on_road(point).value()
    var under = map.certified_waypoint(point)
    var witness = nearest
    witness.s = 0.0009
    # A directly evaluated curve point is inside the original half-width.
    # Thus None cannot be explained by the query being off the road.
    assert_true(
        map.compute_transform(witness).location.distance_to(point) < 0.0001
    )
    print("REQUIRED_NON_LINE", geometry, nearest.s, Bool(under))
    assert_almost_equal(nearest.s, 0.000900000002294056, atol=2e-4)
    assert_true(Bool(under))


def test_arc_narrow_nonconvex_center_must_return_on_road() raises:
    _required_non_line('<arc curvature="0.001"/>')


def test_spiral_narrow_nonconvex_center_must_return_on_road() raises:
    _required_non_line('<spiral curvStart="0.001" curvEnd="0.001"/>')


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
