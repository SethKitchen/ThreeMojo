# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Tests for `math.space_curve`, `math.curve_extras` and `math.nurbs`.

The expected numbers are what three.js 0.180's `Curve`, `CurveExtras`,
`NURBSUtils`, `NURBSCurve`, `NURBSSurface`, `NURBSVolume` and
`ParametricGeometry` give under node."""

from core.buffer_geometry import POSITION
from geometries.parametric import parametric
from math.curve3 import catmull_rom3
from math.curve_extras import (
    CINQUEFOIL_KNOT,
    DECORATED_TORUS_KNOT_5C,
    ExtraCurve,
    ExtraCurveKind,
    GRANNY_KNOT,
    cinquefoil_knot,
    decorated_torus_knot_4a,
    decorated_torus_knot_4b,
    decorated_torus_knot_5a,
    decorated_torus_knot_5c,
    figure_eight_polynomial_knot,
    granny_knot,
    heart_curve,
    helix_curve,
    knot_curve,
    torus_knot,
    trefoil_knot,
    trefoil_polynomial_knot,
    viviani_curve,
)
from math.nurbs import (
    NURBSCurve,
    NURBSSurface,
    NURBSVolume,
    Point4,
    basis_function_derivatives,
    k_over_i,
    nurbs_derivatives,
    rational_curve_derivatives,
)
from math.space_curve import (
    Frames3,
    Point3,
    SpaceCurve3,
    chord_tangent,
    frames3_of,
    frames_of,
    length_of,
    lengths_of,
    point3,
    point_at,
    points_of,
    spaced_points_of,
    tangent_at,
    u_to_t,
)
from math.vector3 import Vector3
from math.vector4 import Vector4
from std.math import inf, nan
from std.testing import TestSuite, assert_equal, assert_raises, assert_true
from units.si import METER


def near(actual: Float64, expected: Float64, tolerance: Float64) raises:
    """Check `actual` is within `tolerance` of `expected`, scaled by the
    size of `expected` when that is more than one."""
    var scale = max(1.0, abs(expected))
    if not (abs(actual - expected) <= tolerance * scale):
        raise Error(
            "expected " + String(expected) + " but got " + String(actual)
        )


def near3(
    actual: Point3, expected: List[Float64], tolerance: Float64 = 1e-12
) raises:
    """Check a point in doubles, coordinate by coordinate."""
    for axis in range(3):
        near(actual[axis], expected[axis], tolerance)


def near_vector(
    actual: Vector3, expected: List[Float64], tolerance: Float64 = 1e-6
) raises:
    """Check a point in floats, coordinate by coordinate."""
    near(Float64(actual.x), expected[0], tolerance)
    near(Float64(actual.y), expected[1], tolerance)
    near(Float64(actual.z), expected[2], tolerance)


def test_every_named_curve_matches_three() raises:
    var curves: List[ExtraCurve] = [
        granny_knot(),
        heart_curve(),
        viviani_curve(),
        knot_curve(),
        helix_curve(),
        trefoil_knot(),
        torus_knot(),
        cinquefoil_knot(),
        trefoil_polynomial_knot(),
        figure_eight_polynomial_knot(),
        decorated_torus_knot_4a(),
        decorated_torus_knot_4b(),
        decorated_torus_knot_5a(),
        decorated_torus_knot_5c(),
    ]
    var points: List[List[Float64]] = [
        [-20.937271656643116, 15.890323458294265, 16.02851993958905],
        [68.8190960235587, -9.4959346906221, 0],
        [6.684405196876839, -20.572483830236557, 66.57395614066075],
        [47.55282581475768, 1.6844051968768385, -5.184066144360289],
        [-30, 1.1021821192326178e-14, 45],
        [-22.725424859373685, -16.51098762732523, -5.877852522924734],
        [18.680339887498953, -13.572061365862872, 9.510565162951535],
        [-8.090169943749475, -5.87785252292473, 3.673940397442059e-15],
        [18.880000000000003, -21.504000000000005, 15.34464],
        [-21.141504, -26.726399999999998, 14.006845439999998],
        [-27.50657780874821, -19.984698577944084, 5.1435165564188825e-15],
        [-40.14183272437241, -29.164748626333846, -7.608452130361227],
        [38.83281572999747, -28.21369211003872, -1.175660927181459e-14],
        [8.652475842498536, 26.629582456264295, 1.543054966925665e-14],
    ]
    var tangents: List[List[Float64]] = [
        [-0.9581362735668313, -0.2588673825124175, 0.1223215416295755],
        [-0.5983816633283503, -0.80121119874375, 0],
        [0.5615832827055923, -0.7729530771548412, -0.2952418620427543],
        [-0.3071969700462998, 0.39523223348025427, -0.8656913440785824],
        [0, -0.9875704520191088, 0.15717697763595456],
        [0.29449780877148646, -0.8763835133675681, 0.3810813274437763],
        [0.12425810714643026, 0.9801433939705042, 0.15452782941712156],
        [0.2182991510967673, -0.3004630048238041, -0.9284758819499198],
        [-0.2270006012258513, 0.914728376544087, -0.334279410356248],
        [-0.25364701146347174, 0.5753421190269572, 0.7775889914660701],
        [0.4095591723702559, -0.563709840213565, -0.7172813258225729],
        [-0.3967219703194903, -0.9109628242765005, -0.11295313653017015],
        [0.39321167376690586, 0.541209438691033, 0.7432879139910493],
        [-0.44755416704221623, 0.14541916400313584, -0.882353973359772],
    ]
    var ends: List[List[Float64]] = [
        [-13.199999999999983, 5.599999999999994, 14.000000000000005],
        [0, 25, 0],
        [70, 0, 0],
        [0, 60, 0],
        [30, 0, 150],
        [30, 0, 0],
        [30, 0, 0],
        [30, 0, 0],
        [20, 0, 24.000000000000004],
        [86.4, 48, 134.40000000000003],
        [82, 0, 0],
        [74, 0, 0],
        [72, 0, 0],
        [68, 0, 0],
    ]
    for index in range(len(curves)):
        near3(curves[index].point3(0.3), points[index], 1e-12)
        near3(curves[index].tangent3(0.3), tangents[index], 1e-9)
        near3(curves[index].point3(1), ends[index], 1e-12)
    near3(
        trefoil_knot(3).point3(0.7),
        [-6.8176274578121046, 4.953296288197572, 1.763355756877418],
    )


def test_a_named_curve_needs_a_kind_and_a_finite_scale() raises:
    with assert_raises():
        _ = ExtraCurve(ExtraCurveKind(-1))
    with assert_raises():
        _ = ExtraCurve(ExtraCurveKind(14))
    with assert_raises():
        _ = heart_curve(inf[DType.float64]())
    with assert_raises():
        _ = heart_curve(nan[DType.float64]())
    assert_true(GRANNY_KNOT.is_valid())
    assert_true(DECORATED_TORUS_KNOT_5C.is_valid())
    var copied = trefoil_knot(3).copy()
    near3(
        copied.point3(0.7),
        [-6.8176274578121046, 4.953296288197572, 1.763355756877418],
    )
    assert_true(CINQUEFOIL_KNOT == cinquefoil_knot().kind)


def test_arc_lengths_and_spaced_points_match_three() raises:
    var heart = heart_curve(2)
    near(Float64(length_of(heart).value), 204.30982501423958, 1e-7)
    near(Float64(length_of(heart, 50).value), 203.9326945407862, 1e-7)
    near_vector(
        point_at(heart, 0.4), [12.439729432139504, -18.230133338605842, 0]
    )
    near_vector(
        point_at(heart, 0.4, 50), [12.37614716001233, -18.285223648453957, 0]
    )
    near_vector(
        tangent_at(heart, 0.4), [-0.7559021429672294, -0.6546846189254413, 0]
    )
    var spaced = spaced_points_of(heart, 4)
    assert_equal(len(spaced), 5)
    near_vector(spaced[1], [31.686533017367886, 4.908246337615083, 0])
    near_vector(spaced[2], [0, -34, 0])
    near_vector(spaced[4], [0, 10, 0])
    var plain = points_of(heart, 3)
    assert_equal(len(plain), 4)
    near_vector(plain[1], [20.78460969082653, -10.999999999999991, 0])
    var table = lengths_of(heart)
    assert_equal(len(table), 201)
    near(u_to_t(table, 0), 0, 1e-15)
    near(u_to_t(table, 1), 1, 1e-15)
    near(u_to_t(table, 0.5), 0.49999999999999944, 1e-12)


def test_a_curve_refuses_counts_and_shares_it_cannot_use() raises:
    var heart = heart_curve()
    with assert_raises():
        _ = lengths_of(heart, 0)
    with assert_raises():
        _ = points_of(heart, 0)
    with assert_raises():
        _ = spaced_points_of(heart, 0)
    with assert_raises():
        _ = point_at(heart, -0.1)
    with assert_raises():
        _ = point_at(heart, 1.1)
    with assert_raises():
        _ = tangent_at(heart, nan[DType.float64]())
    with assert_raises():
        _ = frames_of(heart, 0)


def test_the_chord_tangent_is_held_to_the_curve() raises:
    var heart = heart_curve()
    # At either end the chord runs from the end itself.
    near3(
        chord_tangent(heart, 0),
        [0.0004903949858848247, 0.9999998797563716, 0],
        1e-9,
    )
    near3(
        heart.tangent3(1), [0.0004903949858857226, -0.9999998797563716, 0], 1e-9
    )


def check_frames(
    frames: Frames3,
    normals: List[List[Float64]],
    binormals: List[List[Float64]],
    tolerance: Float64 = 1e-9,
) raises:
    """Check a set of frames' normals and binormals."""
    for index in range(len(normals)):
        near3(frames.normals[index], normals[index], tolerance)
    for index in range(len(binormals)):
        near3(frames.binormals[index], binormals[index], tolerance)


def test_frames_along_a_torus_knot_match_three() raises:
    var knot = torus_knot(10)
    var open = frames3_of(knot, 6, False)
    near3(open.tangents[3], [0, -0.9138114593603738, 0.4061386668881254], 1e-9)
    check_frames(
        open,
        [
            [
                -0.9999990593355053,
                -0.0012533976369408532,
                -0.0005570659462992058,
            ],
            [0.25019842715634355, 0.022381530607848695, -0.9679358522836842],
            [0.35101818536537355, 0.022381530607852446, -0.9361011166698016],
            [-0.9930261995758627, 0.04788126328238232, 0.10773277858851255],
            [0.1400388208178906, 0.0693782134181954, 0.9877124035704085],
            [0.4525596588407404, 0.06937821341823777, 0.8890311685721967],
            [-0.9722011515718403, 0.09631325358925735, -0.21342136272041448],
        ],
        [
            [0, -0.4061386668879657, 0.913811459360445],
            [0.8939658780059524, -0.38923828146225986, 0.22207784492234617],
            [-0.859395413958681, -0.38923828146232753, -0.33156158207946923],
        ],
    )
    var closed = frames3_of(knot, 6, True)
    check_frames(
        closed,
        [
            [
                -0.9999990593355053,
                -0.0012533976369408532,
                -0.0005570659462992058,
            ],
            [0.2852104807299085, 0.007035191704595484, -0.9584390892276328],
            [0.28229248638156634, -0.00832206259773741, -0.9592922888289219],
            [
                -0.9999999999694913,
                -0.0000031724838146548052,
                -0.000007138084355956531,
            ],
        ],
        [
            [0, -0.4061386668879657, 0.913811459360445],
            [0.8834190543973317, -0.38981775068065216, 0.26002479801357664],
        ],
    )
    var floats = frames_of(knot, 6, True)
    assert_equal(floats.count(), 7)
    near_vector(
        floats.normals[1],
        [0.2852104807299085, 0.007035191704595484, -0.9584390892276328],
    )


def test_a_closed_helix_twists_the_other_way() raises:
    var frames = frames3_of(helix_curve(), 3, True)
    near3(
        frames.normals[1],
        [0.4999694290613508, 0.8660430248263254, 0.0002217064185373041],
        1e-9,
    )
    near3(
        frames.normals[3],
        [-0.9999987967777169, 0.0015319706772158603, 0.0002439445919522176],
        1e-9,
    )
    near3(
        frames.binormals[2],
        [0.1362314395274235, 0.07839417250931127, 0.9875704271599403],
        1e-9,
    )


def test_frames_along_a_helix_match_three() raises:
    var frames = frames3_of(helix_curve(), 3)
    check_frames(
        frames,
        [
            [-0.9999987967777237, -0.001531989844923088, -0.000243824157660561],
            [0.36175032564437926, 0.7861009481707655, 0.5011806073475005],
            [0.3617503256443195, -0.3517501407479904, 0.863370453733505],
            [0.0253300806249257, -0.15716535150183256, 0.9872474053158313],
        ],
        [],
    )


def test_a_catmull_rom_curve_serves_as_a_space_curve() raises:
    var curve = SpaceCurve3(
        catmull_rom3(
            [
                Vector3(0, 0, 0),
                Vector3(1, 2, 0),
                Vector3(3, 1, 1),
                Vector3(4, -1, 2),
            ]
        )
    )
    near(Float64(length_of(curve).value), 7.272791562855228, 1e-6)
    var spaced = spaced_points_of(curve, 4)
    near_vector(
        spaced[1],
        [0.6754517980365531, 1.683650213726243, -0.06654932353062742],
        1e-5,
    )
    near_vector(
        spaced[3],
        [3.343232449472941, 0.5296083313353372, 1.2712080393792013],
        1e-5,
    )
    near3(
        curve.tangent3(0.3),
        [0.749993436075019, 0.6386168765972622, 0.1722739991105552],
        1e-4,
    )
    var frames = frames3_of(curve, 3)
    check_frames(
        frames,
        [
            [0, 0, -1],
            [0.3170018275308813, 0.22820435635030337, -0.9205610317001396],
            [0.6379424996895703, 0.11415154155870119, -0.7615765179216039],
        ],
        [],
        1e-4,
    )


def nurbs_points() -> List[Vector4]:
    """Return the seven control points the NURBS curve tests use."""
    return [
        Vector4(0, 0, 0, 1),
        Vector4(1, 2, 0, 0.5),
        Vector4(2, -1, 1, 2),
        Vector4(3, 1, -1, 1),
        Vector4(4, 0, 2, 1.5),
        Vector4(5, 2, 0, 1),
        Vector4(6, 0, 0, 1),
    ]


def nurbs_knots() -> List[Float64]:
    """Return the knots the NURBS curve tests use."""
    return [0, 0, 0, 0, 0.25, 0.5, 0.75, 1, 1, 1, 1]


def test_a_nurbs_curve_matches_three() raises:
    var curve = NURBSCurve(3, nurbs_knots(), nurbs_points())
    near3(curve.point3(0), [0, 0, 0])
    near3(curve.tangent3(0), [0.447213595499958, 0.894427190999916, 0])
    near3(
        curve.point3(0.37),
        [2.3427085919533464, -0.31122838238732026, 0.37269552579072035],
    )
    near3(
        curve.tangent3(0.37),
        [0.5441700384961783, 0.6294065544194327, -0.5547308883205669],
    )
    near3(
        curve.point3(0.5),
        [2.9333333333333336, 0.26666666666666666, 0.13333333333333336],
    )
    near3(
        curve.tangent3(0.5),
        [0.8238415256818212, 0.5069794004195823, 0.25348970020979117],
    )
    near3(curve.point3(1), [6, 0, 0])
    near3(curve.tangent3(1), [0.447213595499958, -0.894427190999916, 0])
    near(Float64(length_of(curve).value), 8.731083152052864, 1e-6)
    near_vector(
        point_at(curve, 0.6),
        [3.725945347141941, 0.39444323248512214, 0.9771884087140503],
    )
    check_frames(
        frames3_of(curve, 4),
        [
            [0, 0, -1.0000000000000002],
            [0.4512840832108287, 0.06844992892210634, -0.889751248086296],
            [0.6814854116451161, -0.025694634536990446, -0.7313804888502962],
            [-0.4586450027665461, -0.4920727659829609, -0.7399386153020763],
            [-0.7305667279061504, -0.36528336395307537, -0.5769231492110772],
        ],
        [],
    )


def test_a_nurbs_curve_can_run_between_two_knots() raises:
    var curve = NURBSCurve(3, nurbs_knots(), nurbs_points(), 3, 7)
    near3(
        curve.point3(0.2),
        [1.8918918918918919, -0.3742203742203743, 0.6985446985446986],
    )
    # three.js maps a tangent onto every knot, not the two given.
    near3(
        curve.tangent3(0.2),
        [0.6104050961806476, -0.7825706361290347, 0.12242882840774218],
    )
    var copied = curve.copy()
    assert_equal(copied.start_knot, 3)
    assert_equal(copied.end_knot, 7)


def test_a_nurbs_curve_of_unit_weights_and_of_degree_zero() raises:
    var arch = NURBSCurve(
        2,
        [0, 0, 0, 1, 1, 1],
        [Vector4(0, 0, 0, 1), Vector4(1, 1, 0, 1), Vector4(2, 0, 0, 1)],
    )
    near3(arch.point3(0.25), [0.5, 0.375, 0])
    near3(arch.tangent3(0.25), [0.8944271909999159, 0.4472135954999579, 0])
    var steps = NURBSCurve(
        0, [0, 0.5, 1], [Vector4(1, 2, 3, 1), Vector4(4, 5, 6, 2)]
    )
    near3(steps.point3(0.25), [1, 2, 3])
    near3(steps.point3(0.75), [4, 5, 6])
    near3(
        steps.tangent3(0.25),
        [-0.2672612419124244, -0.5345224838248488, -0.8017837257372732],
    )
    # The first tangent leans along x and y alike, so z is least.
    var frames = frames3_of(arch, 2)
    for index in range(3):
        near3(frames.normals[index], [0, 0, -1], 1e-12)


def test_a_straight_nurbs_curve_has_frames_that_do_not_turn() raises:
    var line = NURBSCurve(
        1, [0, 0, 1, 1], [Vector4(0, 0, 0, 1), Vector4(0.6, 0, 0.8, 1)]
    )
    for closed in [False, True]:
        var frames = frames3_of(line, 3, closed)
        for index in range(4):
            near3(frames.normals[index], [0, -1, 0], 1e-12)
    # A first tangent that leans least along y takes y as its axis.
    var first = frames3_of(line, 1)
    near3(first.normals[0], [0, -1, 0], 1e-12)


def test_nurbs_derivatives_match_three() raises:
    var arch: List[Point4] = [
        Point4(0, 0, 0, 1),
        Point4(1, 1, 0, 1),
        Point4(2, 0, 0, 1),
    ]
    var ders = nurbs_derivatives(2, [0, 0, 0, 1, 1, 1], arch, 0.4, 3)
    assert_equal(len(ders), 5)
    near3(ders[0], [0.8, 0.48, 0])
    near3(ders[1], [2, 0.3999999999999999, 0])
    near3(ders[2], [0, -4, 0])
    near3(ders[3], [-0.8, -0.48, 0])
    near3(ders[4], [-8.8, -2.0799999999999996, 0])
    var basis = basis_function_derivatives(4, 0.37, 3, 3, nurbs_knots())
    var expected: List[List[Float64]] = [
        [
            0.035152,
            0.4798453333333334,
            0.4665706666666667,
            0.018431999999999997,
        ],
        [-0.8112000000000001, -2.1872000000000003, 2.5376000000000003, 0.4608],
        [12.48, -13.12, -7.039999999999997, 7.679999999999999],
        [-96, 223.99999999999997, -192, 64],
    ]
    for row in range(4):
        for column in range(4):
            near(basis[row][column], expected[row][column], 1e-12)
    assert_equal(len(rational_curve_derivatives([])), 0)
    near(k_over_i(5, 2), 10, 0)
    near(k_over_i(3, 0), 1, 0)
    near(k_over_i(1, 1), 1, 0)


def test_a_nurbs_curve_refuses_knots_and_points_that_do_not_fit() raises:
    var points = nurbs_points()
    with assert_raises():
        _ = NURBSCurve(-1, nurbs_knots(), points)
    with assert_raises():
        _ = NURBSCurve(3, nurbs_knots(), [])
    with assert_raises():
        _ = NURBSCurve(2, nurbs_knots(), points)
    var bad = nurbs_knots()
    bad[5] = inf[DType.float64]()
    with assert_raises():
        _ = NURBSCurve(3, bad, points)
    var falling = nurbs_knots()
    falling[5] = 0.1
    with assert_raises():
        _ = NURBSCurve(3, falling, points)
    var odd = nurbs_points()
    odd[2] = Vector4(nan[DType.float32](), 0, 0, 1)
    with assert_raises():
        _ = NURBSCurve(3, nurbs_knots(), odd)
    with assert_raises():
        _ = NURBSCurve(3, nurbs_knots(), points, -1)
    with assert_raises():
        _ = NURBSCurve(3, nurbs_knots(), points, 11)
    with assert_raises():
        _ = NURBSCurve(3, nurbs_knots(), points, 0, -1)
    with assert_raises():
        _ = NURBSCurve(3, nurbs_knots(), points, 0, 11)


def surface_points() -> List[List[Vector4]]:
    """Return the control points of three.js's NURBS example surface."""
    return [
        [
            Vector4(-200, -200, 100, 1),
            Vector4(-200, -100, -200, 1),
            Vector4(-200, 100, 250, 1),
            Vector4(-200, 200, -100, 1),
        ],
        [
            Vector4(0, -200, 0, 1),
            Vector4(0, -100, -100, 5),
            Vector4(0, 100, 150, 5),
            Vector4(0, 200, 0, 1),
        ],
        [
            Vector4(200, -200, -100, 1),
            Vector4(200, -100, 200, 1),
            Vector4(200, 100, -250, 1),
            Vector4(200, 200, 100, 1),
        ],
    ]


def example_surface() raises -> NURBSSurface:
    """Return three.js's NURBS example surface."""
    return NURBSSurface(
        2, 3, [0, 0, 0, 1, 1, 1], [0, 0, 0, 0, 1, 1, 1, 1], surface_points()
    )


def test_a_nurbs_surface_matches_three() raises:
    var surface = example_surface()
    near3(surface.point64(0, 0), [-200, -200, 100])
    near3(
        surface.point64(0.3, 0.6),
        [-36.205648081100655, 31.2237509051412, 40.58653149891382],
    )
    near3(surface.point64(1, 1), [200, 200, 100])
    near3(
        surface.point64(0.5, 0.25), [0, -77.94117647058823, -24.816176470588236]
    )
    var copied = surface.copy()
    near_vector(
        copied.point(0.5, 0.25), [0, -77.94117647058823, -24.816176470588236]
    )


def test_a_nurbs_surface_makes_a_parametric_geometry_as_three_does() raises:
    var mesh = parametric(example_surface(), 4, 4)
    ref positions = mesh.attribute_view(String(POSITION))
    assert_equal(positions.count(), 25)
    near_vector(positions.vector3(0), [-200, -200, 100])
    near_vector(
        positions.vector3(7), [0, -77.94117736816406, -24.816177368164062]
    )
    near_vector(positions.vector3(12), [0, 0, 18.75])
    near_vector(positions.vector3(24), [200, 200, 100])


def test_a_nurbs_surface_refuses_rows_that_do_not_fit() raises:
    var ragged = surface_points()
    _ = ragged[1].pop()
    with assert_raises():
        _ = NURBSSurface(
            2, 3, [0, 0, 0, 1, 1, 1], [0, 0, 0, 0, 1, 1, 1, 1], ragged
        )
    with assert_raises():
        _ = NURBSSurface(
            2, 3, [0, 0, 0, 1, 1], [0, 0, 0, 0, 1, 1, 1, 1], surface_points()
        )
    with assert_raises():
        _ = NURBSSurface(
            2, 3, [0, 0, 0, 1, 1, 1], [0, 0, 0, 1, 1, 1, 1], surface_points()
        )
    with assert_raises():
        _ = NURBSSurface(2, 3, [0, 0, 0, 1, 1, 1], [0, 0, 0, 0, 1, 1, 1, 1], [])


def volume_points() -> List[List[List[Vector4]]]:
    """Return a box of two by three by two control points."""
    var out = List[List[List[Vector4]]]()
    for i in range(2):
        var plane = List[List[Vector4]]()
        for j in range(3):
            var row = List[Vector4]()
            for k in range(2):
                row.append(
                    Vector4(
                        Float32(i * 2) + Float32(j) * 0.5,
                        Float32(j - k),
                        Float32(k * 3 + i),
                        1 + Float32(i) + Float32(k) * 0.5,
                    )
                )
            plane.append(row^)
        out.append(plane^)
    return out^


def example_volume() raises -> NURBSVolume:
    """Return a volume of degrees one, two and one."""
    return NURBSVolume(
        1, 2, 1, [0, 0, 1, 1], [0, 0, 0, 1, 1, 1], [0, 0, 1, 1], volume_points()
    )


def test_a_nurbs_volume_matches_three() raises:
    var volume = example_volume()
    near3(volume.point64(0, 0, 0), [0, 0, 0])
    near3(
        volume.point64(0.25, 0.5, 0.75),
        [1.2307692307692308, 0.19230769230769232, 2.7884615384615388],
    )
    near_vector(volume.point(1, 1, 1), [3, 1, 4])
    var copied = volume.copy()
    near_vector(copied.point(1, 1, 1), [3, 1, 4])


def test_a_nurbs_volume_refuses_points_that_do_not_fill_a_box() raises:
    var short_plane = volume_points()
    _ = short_plane[1].pop()
    with assert_raises():
        _ = NURBSVolume(
            1, 2, 1, [0, 0, 1, 1], [0, 0, 0, 1, 1, 1], [0, 0, 1, 1], short_plane
        )
    var short_row = volume_points()
    _ = short_row[1][2].pop()
    with assert_raises():
        _ = NURBSVolume(
            1, 2, 1, [0, 0, 1, 1], [0, 0, 0, 1, 1, 1], [0, 0, 1, 1], short_row
        )
    with assert_raises():
        _ = NURBSVolume(
            1,
            2,
            1,
            [0, 1, 1],
            [0, 0, 0, 1, 1, 1],
            [0, 0, 1, 1],
            volume_points(),
        )
    with assert_raises():
        _ = NURBSVolume(
            1,
            2,
            1,
            [0, 0, 1, 1],
            [0, 0, 1, 1, 1],
            [0, 0, 1, 1],
            volume_points(),
        )
    with assert_raises():
        _ = NURBSVolume(
            1,
            2,
            1,
            [0, 0, 1, 1],
            [0, 0, 0, 1, 1, 1],
            [0, 1, 1],
            volume_points(),
        )


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
