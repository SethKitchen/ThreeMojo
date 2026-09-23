# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Tests for `math.obb`, three.js's `OBB`.

The expected values were calculated by three.js 0.180, by node on
`examples/jsm/math/OBB.js`. The box pairs were found by a seeded search:
each pair is separated first by the axis its test names, by the widest
margin the search found, so `Float32` cannot turn the answer.
"""

from math.bounds import Box3, Plane, Sphere
from math.matrix3 import Matrix3
from math.matrix4 import Matrix4, rotation_z, scaling, translation
from math.obb import OBB
from math.ray import Ray
from math.vector3 import Vector3
from units.si import DEGREE, Angle
from std.testing import (
    TestSuite,
    assert_almost_equal,
    assert_equal,
    assert_false,
    assert_raises,
    assert_true,
)

comptime TOLERANCE = Float64(2e-6)


def m3(
    e0: Float32,
    e1: Float32,
    e2: Float32,
    e3: Float32,
    e4: Float32,
    e5: Float32,
    e6: Float32,
    e7: Float32,
    e8: Float32,
) -> Matrix3:
    """Return a matrix from its nine elements in memory order, as three.js's
    `elements` array lists them."""
    var m = Matrix3()
    m.elements[0] = e0
    m.elements[1] = e1
    m.elements[2] = e2
    m.elements[3] = e3
    m.elements[4] = e4
    m.elements[5] = e5
    m.elements[6] = e6
    m.elements[7] = e7
    m.elements[8] = e8
    return m


def assert_vector(v: Vector3, x: Float32, y: Float32, z: Float32) raises:
    """Assert a vector's components, within the tolerance."""
    assert_almost_equal(v.x, x, atol=TOLERANCE)
    assert_almost_equal(v.y, y, atol=TOLERANCE)
    assert_almost_equal(v.z, z, atol=TOLERANCE)


def turned() raises -> OBB:
    """Return the turned box of the point, sphere and ray tests: three.js's
    rotation from the Euler angles 0.5, -0.25 and 1.0."""
    return OBB(
        Vector3(1, 2, 3),
        Vector3(1, 0.5, 2),
        m3(
            0.523505628,
            0.674374044,
            0.520731688,
            -0.815311670,
            0.573968232,
            0.0763367340,
            -0.247403964,
            -0.464521348,
            0.850300670,
        ),
    )


def test_default_box_is_a_point() raises:
    """The default is three.js's: a box of no size at the origin."""
    var box = OBB()
    assert_vector(box.center, 0, 0, 0)
    assert_vector(box.size(), 0, 0, 0)
    assert_true(box.rotation == Matrix3())
    assert_true(box.contains_point(Vector3(0, 0, 0)))


def test_constructor_refuses_a_bad_half_size() raises:
    """A negative or infinite half size is not a box."""
    with assert_raises(contains="half size"):
        _ = OBB(Vector3(0, 0, 0), Vector3(-1, 1, 1), Matrix3())
    with assert_raises(contains="half size"):
        _ = OBB(Vector3(0, 0, 0), Vector3(1, -1, 1), Matrix3())
    with assert_raises(contains="half size"):
        _ = OBB(Vector3(0, 0, 0), Vector3(1, 1, -1), Matrix3())
    var huge = Float32(1e38) * 10
    with assert_raises(contains="half size"):
        _ = OBB(Vector3(0, 0, 0), Vector3(huge, 1, 1), Matrix3())
    with assert_raises(contains="half size"):
        _ = OBB(Vector3(0, 0, 0), Vector3(1, huge, 1), Matrix3())
    with assert_raises(contains="half size"):
        _ = OBB(Vector3(0, 0, 0), Vector3(1, 1, huge), Matrix3())


def test_from_box3() raises:
    """An axis-aligned box keeps its center and half its size."""
    var box = OBB.from_box3(Box3(Vector3(-1, 0, 2), Vector3(3, 1, 4)))
    assert_vector(box.center, 1, 0.5, 3)
    assert_vector(box.half_size, 2, 0.5, 1)
    assert_vector(box.size(), 4, 1, 2)
    assert_true(box.rotation == Matrix3())
    with assert_raises(contains="empty"):
        _ = OBB.from_box3(Box3.empty())


def test_axis() raises:
    """The axes are the rotation's columns."""
    var box = turned()
    assert_vector(box.axis(0), 0.523505628, 0.674374044, 0.520731688)
    assert_vector(box.axis(1), -0.815311670, 0.573968232, 0.0763367340)
    assert_vector(box.axis(2), -0.247403964, -0.464521348, 0.850300670)
    with assert_raises(contains="three axes"):
        _ = box.axis(-1)
    with assert_raises(contains="three axes"):
        _ = box.axis(3)


def test_equality() raises:
    """Equal is every part equal, as three.js's `equals`."""
    var box = turned()
    var same = turned()
    assert_true(box == same)
    assert_false(box != same)
    var moved = turned()
    moved.center.x += 1
    assert_true(box != moved)
    var grown = turned()
    grown.half_size.z += 1
    assert_true(box != grown)
    assert_true(box != OBB(box.center, box.half_size, Matrix3()))


def test_clamp_and_contain_point() raises:
    """The nearest point and containment, as three.js gives them."""
    var box = turned()
    assert_vector(
        box.clamp_point(Vector3(3, 3, 3)), 2.16850328, 2.83301878, 2.66684508
    )
    assert_false(box.contains_point(Vector3(3, 3, 3)))
    assert_vector(
        box.clamp_point(Vector3(1.2, 2.1, 3.3)), 1.20000005, 2.09999990, 3.3
    )
    assert_true(box.contains_point(Vector3(1.2, 2.1, 3.3)))
    assert_vector(
        box.clamp_point(Vector3(-2, 0, 5)),
        -0.425969392,
        0.683567405,
        4.21803808,
    )
    assert_false(box.contains_point(Vector3(-2, 0, 5)))


def test_contain_point_on_each_axis() raises:
    """A point past one face alone is outside."""
    var box = OBB(Vector3(0, 0, 0), Vector3(1, 2, 3), Matrix3())
    assert_true(box.contains_point(Vector3(1, 2, 3)))
    assert_false(box.contains_point(Vector3(1.5, 0, 0)))
    assert_false(box.contains_point(Vector3(0, 2.5, 0)))
    assert_false(box.contains_point(Vector3(0, 0, 3.5)))


def test_intersects_sphere() raises:
    """A sphere meets the box if the nearest point is within its radius."""
    var box = turned()
    assert_true(box.intersects_sphere(Sphere(Vector3(3, 3, 3), 1)))
    assert_false(box.intersects_sphere(Sphere(Vector3(3, 3, 3), 0.2)))
    assert_false(box.intersects_sphere(Sphere(Vector3(1, 2, 3), -1)))


def test_intersects_box3() raises:
    """An axis-aligned box, as three.js tests it; an empty one meets
    nothing."""
    var box = turned()
    assert_true(box.intersects_box3(Box3(Vector3(1.5, 2, 3), Vector3(4, 4, 4))))
    assert_false(box.intersects_box3(Box3(Vector3(5, 5, 5), Vector3(6, 6, 6))))
    assert_false(box.intersects_box3(Box3.empty()))


def pair(
    a: Tuple[Vector3, Vector3, Matrix3], b: Tuple[Vector3, Vector3, Matrix3]
) raises -> Tuple[OBB, OBB]:
    """Return two boxes from their parts."""
    return (OBB(a[0], a[1], a[2]), OBB(b[0], b[1], b[2]))


def test_intersects_obb_overlap() raises:
    """Two boxes that no axis separates meet, both ways round."""
    var boxes = pair(
        (
            Vector3(-1.95840049, 0.316033065, 0.0986353233),
            Vector3(1.56516731, 1.51773548, 0.278292120),
            m3(
                0.230228767,
                0.721391797,
                -0.653137505,
                -0.830941260,
                -0.203591526,
                -0.517771244,
                -0.506489217,
                0.661924779,
                0.552561581,
            ),
        ),
        (
            Vector3(-1.50430048, 0.459341526, -0.232745320),
            Vector3(1.36905813, 1.32105649, 0.287325740),
            m3(
                0.182123616,
                0.550122082,
                0.814982653,
                0.584129393,
                -0.727268636,
                0.360379219,
                0.790963888,
                0.410421729,
                -0.453795254,
            ),
        ),
    )
    assert_true(boxes[0].intersects_obb(boxes[1]))
    assert_true(boxes[1].intersects_obb(boxes[0]))
    assert_true(boxes[0].intersects_obb(boxes[0]))


def test_intersects_obb_face_axes() raises:
    """Each of the six face axes separates one pair."""
    var a0 = pair(
        (
            Vector3(1.32246804, -0.751366675, 1.91296768),
            Vector3(0.168853015, 0.579934120, 0.0372568145),
            m3(
                -0.622335494,
                0.396783501,
                -0.674730599,
                0.329124182,
                0.914742172,
                0.234358653,
                0.710194170,
                -0.0762204453,
                -0.699867606,
            ),
        ),
        (
            Vector3(-1.93311965, 0.459533870, -1.96050358),
            Vector3(0.670577407, 0.211125180, 0.253672659),
            m3(
                0.371500045,
                -0.262284458,
                -0.890614748,
                -0.515376091,
                -0.856158078,
                0.0371593907,
                -0.772253335,
                0.445196837,
                -0.453237891,
            ),
        ),
    )
    assert_false(a0[0].intersects_obb(a0[1]))
    var a1 = pair(
        (
            Vector3(1.01242626, 1.24144089, 1.99283671),
            Vector3(1.49353564, 0.393612474, 0.234079227),
            m3(
                -0.0696829110,
                0.833090007,
                -0.548730612,
                -0.357778311,
                -0.534344018,
                -0.765814066,
                -0.931202948,
                0.142959759,
                0.335296184,
            ),
        ),
        (
            Vector3(-1.58706403, -1.16254377, -1.47369230),
            Vector3(1.04508328, 1.43414080, 0.297024012),
            m3(
                -0.0844876841,
                0.968739986,
                0.233247966,
                0.399242699,
                0.247384921,
                -0.882839739,
                -0.912944198,
                0.0185334627,
                -0.407663345,
            ),
        ),
    )
    assert_false(a1[0].intersects_obb(a1[1]))
    var a2 = pair(
        (
            Vector3(1.93939543, -0.301464945, 0.254279941),
            Vector3(1.52317953, 1.38553298, 0.293136358),
            m3(
                0.0156174581,
                0.506832302,
                -0.861903191,
                -0.107705310,
                0.857845426,
                0.502494574,
                0.994060218,
                0.0849838629,
                0.0679858997,
            ),
        ),
        (
            Vector3(-1.53794944, -0.276973605, 0.306420624),
            Vector3(1.30130851, 1.49911344, 0.0434782580),
            m3(
                -0.0685215220,
                0.996550679,
                -0.0468137488,
                0.0147116119,
                0.0479282588,
                0.998742461,
                0.997541189,
                0.0677466467,
                -0.0179449841,
            ),
        ),
    )
    assert_false(a2[0].intersects_obb(a2[1]))
    var b0 = pair(
        (
            Vector3(1.25300038, 1.72583985, -1.94127929),
            Vector3(0.869094253, 0.608299613, 0.231979504),
            m3(
                -0.996151805,
                -0.0499441139,
                0.0720223710,
                0.0625440925,
                0.170593023,
                0.983354568,
                -0.0613992885,
                0.984075010,
                -0.166812837,
            ),
        ),
        (
            Vector3(-0.401338995, 0.837402701, -0.558923304),
            Vector3(0.688859701, 1.53085017, 0.276796669),
            m3(
                -0.666941702,
                -0.428673029,
                0.609449089,
                -0.724394023,
                0.564562500,
                -0.395629227,
                -0.174476534,
                -0.705342889,
                -0.687058449,
            ),
        ),
    )
    assert_false(b0[0].intersects_obb(b0[1]))
    var b1 = pair(
        (
            Vector3(-0.543026030, -1.03635061, 0.152836159),
            Vector3(1.16965270, 0.958092213, 0.0753198788),
            m3(
                -0.615952611,
                -0.357320368,
                -0.702085853,
                0.116952300,
                -0.922817647,
                0.367055476,
                -0.779053628,
                0.143978223,
                0.610201359,
            ),
        ),
        (
            Vector3(0.492840946, 1.31962144, 0.967339098),
            Vector3(1.46829665, 0.629457593, 0.0787765086),
            m3(
                0.315995604,
                -0.152055532,
                0.936496615,
                -0.197837591,
                -0.975935757,
                -0.0917041525,
                0.927904665,
                -0.156296134,
                -0.338473707,
            ),
        ),
    )
    assert_false(b1[0].intersects_obb(b1[1]))
    var b2 = pair(
        (
            Vector3(1.16446173, 1.16810393, 1.96610689),
            Vector3(1.52274442, 0.400674999, 0.248810738),
            m3(
                0.0109415166,
                0.876146436,
                0.481920868,
                -0.0934768096,
                0.480735421,
                -0.871868968,
                -0.995561361,
                -0.0355088562,
                0.0871593505,
            ),
        ),
        (
            Vector3(0.724322081, -1.60920858, 1.88589048),
            Vector3(1.54955029, 1.23621571, 0.144278660),
            m3(
                0.264270037,
                0.131096870,
                0.955497205,
                -0.696652234,
                0.711075485,
                0.0951175392,
                -0.666961014,
                -0.690786004,
                0.279244870,
            ),
        ),
    )
    assert_false(b2[0].intersects_obb(b2[1]))


def test_intersects_obb_edge_axes_of_a0() raises:
    """A0 x B0, A0 x B1 and A0 x B2 each separate one pair."""
    var c00 = pair(
        (
            Vector3(-1.13469958, 0.348064810, 1.83858156),
            Vector3(1.59446752, 0.397804558, 0.294977903),
            m3(
                -0.958669901,
                -0.136856213,
                0.249444127,
                0.250283062,
                -0.822597027,
                0.510580599,
                0.135315865,
                0.551909924,
                0.822851777,
            ),
        ),
        (
            Vector3(-1.67045891, -1.49796033, 1.84309328),
            Vector3(1.57183635, 0.937328517, 0.0442298241),
            m3(
                0.304966062,
                -0.285348266,
                0.908609986,
                0.714334309,
                0.699516594,
                -0.0200766567,
                -0.629858911,
                0.655173957,
                0.417162865,
            ),
        ),
    )
    assert_false(c00[0].intersects_obb(c00[1]))
    var c01 = pair(
        (
            Vector3(0.348800510, -0.557068288, -1.32821286),
            Vector3(1.46580768, 0.812693477, 0.0754333586),
            m3(
                -0.650364995,
                -0.200984493,
                0.732550740,
                -0.497871876,
                0.841130853,
                -0.211240217,
                -0.573715091,
                -0.502099693,
                -0.647106588,
            ),
        ),
        (
            Vector3(1.84190512, -1.72309804, -0.116070785),
            Vector3(1.09114194, 1.18293369, 0.235045522),
            m3(
                0.354215533,
                -0.312190384,
                0.881514907,
                -0.134674132,
                0.915776312,
                0.378439695,
                -0.925415695,
                -0.252766460,
                0.282338232,
            ),
        ),
    )
    assert_false(c01[0].intersects_obb(c01[1]))
    var c02 = pair(
        (
            Vector3(-1.06321442, -0.0771834776, 0.0812494904),
            Vector3(1.55685234, 0.786108017, 0.164865628),
            m3(
                0.264240474,
                0.307053030,
                -0.914273143,
                0.741324186,
                -0.671055079,
                -0.0111144586,
                -0.616940379,
                -0.674835920,
                -0.404945761,
            ),
        ),
        (
            Vector3(-1.75177813, 0.919763029, 1.88106191),
            Vector3(0.493641108, 0.745595038, 0.248671621),
            m3(
                0.0375570096,
                -0.987778604,
                0.151270986,
                0.146308422,
                0.155181929,
                0.976991534,
                -0.988525808,
                -0.0145606594,
                0.150348499,
            ),
        ),
    )
    assert_false(c02[0].intersects_obb(c02[1]))


def test_intersects_obb_edge_axes_of_a1() raises:
    """A1 x B0, A1 x B1 and A1 x B2 each separate one pair."""
    var c10 = pair(
        (
            Vector3(1.06013596, 0.232996657, 1.28434289),
            Vector3(1.45340633, 1.54448652, 0.0591539107),
            m3(
                0.508360624,
                0.855194867,
                -0.101050429,
                -0.639986873,
                0.296680421,
                -0.708800077,
                -0.576182485,
                0.424997002,
                0.698134124,
            ),
        ),
        (
            Vector3(-1.35696101, -1.10699773, 1.94921696),
            Vector3(1.56014419, 1.28586102, 0.149864838),
            m3(
                -0.293831497,
                -0.621033549,
                -0.726622581,
                0.955520868,
                -0.211005211,
                -0.206050292,
                -0.0253570005,
                -0.754847050,
                0.655410469,
            ),
        ),
    )
    assert_false(c10[0].intersects_obb(c10[1]))
    var c11 = pair(
        (
            Vector3(-0.276920170, 0.513762236, -0.287052244),
            Vector3(1.03336060, 1.13559222, 0.271339506),
            m3(
                0.760965168,
                -0.244999751,
                -0.600755513,
                -0.648386776,
                -0.254427254,
                -0.717538416,
                0.0229481589,
                0.935543656,
                -0.352464855,
            ),
        ),
        (
            Vector3(0.696857154, -0.682556093, -0.874537170),
            Vector3(0.306479037, 1.34157789, 0.0299559887),
            m3(
                -0.0220984705,
                0.846854210,
                0.531365812,
                -0.539389312,
                -0.457603633,
                0.706864953,
                0.841766477,
                -0.270992398,
                0.466896445,
            ),
        ),
    )
    assert_false(c11[0].intersects_obb(c11[1]))
    var c12 = pair(
        (
            Vector3(-0.115580872, 0.346987486, 0.323801041),
            Vector3(0.546326697, 1.24213052, 0.170370415),
            m3(
                -0.630064666,
                -0.776253104,
                -0.0212040730,
                0.337345690,
                -0.298205227,
                0.892900646,
                -0.699440062,
                0.555432022,
                0.449754238,
            ),
        ),
        (
            Vector3(0.304554880, 1.62294817, 1.63352549),
            Vector3(1.00193727, 0.434556633, 0.188969240),
            m3(
                -0.0113817453,
                -0.457237720,
                -0.889271677,
                0.0207643397,
                0.889029443,
                -0.457378924,
                0.999719620,
                -0.0236709099,
                -0.000624467386,
            ),
        ),
    )
    assert_false(c12[0].intersects_obb(c12[1]))


def test_intersects_obb_edge_axes_of_a2() raises:
    """A2 x B0, A2 x B1 and A2 x B2 each separate one pair."""
    var c20 = pair(
        (
            Vector3(0.587457836, -1.27147400, 0.0296086706),
            Vector3(0.643438578, 0.221559823, 0.263233751),
            m3(
                -0.0162308998,
                -0.990777850,
                0.134520769,
                -0.0148242302,
                -0.134285241,
                -0.990831852,
                0.999758363,
                -0.0180762596,
                -0.0125079481,
            ),
        ),
        (
            Vector3(0.654451609, -0.155510560, -0.406989396),
            Vector3(1.13158703, 0.313990444, 0.277204961),
            m3(
                0.0188004524,
                0.382096499,
                0.923931181,
                -0.690527558,
                -0.663333237,
                0.288375974,
                0.723061681,
                -0.643421531,
                0.251377195,
            ),
        ),
    )
    assert_false(c20[0].intersects_obb(c20[1]))
    var c21 = pair(
        (
            Vector3(-1.10866129, 1.35791671, 1.22271919),
            Vector3(0.569858909, 1.11553454, 0.294799417),
            m3(
                0.160259724,
                0.850988984,
                -0.500134528,
                0.548128843,
                -0.498105168,
                -0.671897292,
                -0.820896804,
                -0.166460082,
                -0.546277821,
            ),
        ),
        (
            Vector3(-0.219046444, 1.61367285, -0.575146794),
            Vector3(0.761434317, 1.27893484, 0.164811969),
            m3(
                0.139767334,
                -0.229357719,
                0.963254988,
                0.112285651,
                0.970199883,
                0.214718804,
                -0.983797252,
                0.0781490356,
                0.161355823,
            ),
        ),
    )
    assert_false(c21[0].intersects_obb(c21[1]))
    var c22 = pair(
        (
            Vector3(0.293602645, 0.690954030, -0.808836222),
            Vector3(1.17075408, 0.653039694, 0.251186520),
            m3(
                0.934865892,
                -0.354883671,
                -0.00913027953,
                0.309823781,
                0.803069651,
                0.509007275,
                -0.173306122,
                -0.478682309,
                0.860713780,
            ),
        ),
        (
            Vector3(1.22146177, -1.20507407, -1.54706478),
            Vector3(0.538156509, 0.858099043, 0.122304924),
            m3(
                0.219668061,
                -0.0601061545,
                -0.973721325,
                0.0962404907,
                0.994566798,
                -0.0396813974,
                0.970816016,
                -0.0849946812,
                0.224259213,
            ),
        ),
    )
    assert_false(c22[0].intersects_obb(c22[1]))


def test_intersects_obb_epsilon_keeps_touching_boxes() raises:
    """Two unturned boxes that share a face touch."""
    var a = OBB(Vector3(0, 0, 0), Vector3(1, 1, 1), Matrix3())
    var b = OBB(Vector3(2, 0, 0), Vector3(1, 1, 1), Matrix3())
    assert_true(a.intersects_obb(b))
    assert_true(a.intersects_obb(b, 0))


def test_intersects_plane() raises:
    """A plane meets the box if the center is within its reach.

    three.js subtracts the constant, and says the plane `y = 2` through the
    center misses the box. The signed distance says it meets it.
    """
    var box = turned()
    assert_true(box.intersects_plane(Plane(Vector3(0, 1, 0), -2)))
    assert_false(box.intersects_plane(Plane(Vector3(0, 1, 0), -10)))
    assert_false(box.intersects_plane(Plane(Vector3(0, 1, 0), 2)))


def test_intersect_ray() raises:
    """A ray is met where three.js meets it, or missed."""
    var box = turned()
    var hit = box.intersect_ray(Ray(Vector3(-5, 2, 3), Vector3(1, 0, 0)))
    assert_true(Bool(hit))
    assert_vector(hit.value(), 0.386737615, 2, 3)
    assert_true(box.intersects_ray(Ray(Vector3(-5, 2, 3), Vector3(1, 0, 0))))
    var miss = Ray(Vector3(-5, 10, 3), Vector3(1, 0, 0))
    assert_false(Bool(box.intersect_ray(miss)))
    assert_false(box.intersects_ray(miss))


def test_intersect_ray_refuses_a_singular_rotation() raises:
    """A rotation of zeros has no inverse to carry the ray through."""
    var flat = Matrix3()
    for index in range(9):
        flat.elements[index] = 0
    var box = OBB(Vector3(0, 0, 0), Vector3(1, 1, 1), flat)
    with assert_raises():
        _ = box.intersect_ray(Ray(Vector3(-5, 0, 0), Vector3(1, 0, 0)))


def test_apply_matrix4_matches_three() raises:
    """A box from a `Box3` through a world matrix, three.js's own use."""
    var box = OBB.from_box3(Box3(Vector3(-1, -2, -3), Vector3(1, 2, 3)))
    var world = Matrix4()
    var values: List[Float32] = [
        1.95034063,
        0.307583988,
        -0.318690151,
        0,
        -0.293530196,
        2.83410740,
        0.938975453,
        0,
        0.794677317,
        -1.15851796,
        3.74517345,
        0,
        4,
        5,
        6,
        1,
    ]
    for index in range(16):
        world.elements[index] = values[index]
    box.apply_matrix4(world)
    assert_vector(box.center, 4, 5, 6)
    assert_vector(box.half_size, 2, 6, 12)
    var expected: List[Float32] = [
        0.975170314,
        0.153791994,
        -0.159345075,
        -0.0978434011,
        0.944702506,
        0.312991828,
        0.198669329,
        -0.289629489,
        0.936293364,
    ]
    for index in range(9):
        assert_almost_equal(
            box.rotation.elements[index], expected[index], atol=TOLERANCE
        )


def test_apply_matrix4_moves_a_turned_box_whole() raises:
    """A box off the origin, already turned, keeps what it held.

    three.js adds only the translation to the center and multiplies the
    rotations in the other order, so the point below leaves its box there.
    """
    var box = turned()
    var inside = Vector3(1.2, 2.1, 3.3)
    var move = translation(1, -2, 0.5)
    move.multiply(rotation_z(Angle(30, DEGREE)))
    move.multiply(scaling(2, 2, 2))
    box.apply_matrix4(move)
    assert_true(box.contains_point(move.transform_point(inside)))
    var center = move.transform_point(Vector3(1, 2, 3))
    assert_vector(box.center, center.x, center.y, center.z)
    assert_vector(box.half_size, 2, 1, 4)


def test_apply_matrix4_through_a_mirror() raises:
    """A mirror keeps the half size positive and the box a rotation."""
    var box = OBB(Vector3(1, 0, 0), Vector3(1, 2, 3), Matrix3())
    box.apply_matrix4(scaling(-1, 1, 1))
    assert_vector(box.center, -1, 0, 0)
    assert_vector(box.half_size, 1, 2, 3)
    assert_almost_equal(box.rotation.determinant(), 1, atol=TOLERANCE)
    assert_true(box.contains_point(Vector3(-1.5, 1, 2)))


def test_apply_matrix4_refusals() raises:
    """A projection, or a matrix that flattens an axis, is refused."""
    var box = OBB()
    var projective = Matrix4()
    projective.elements[3] = 1
    with assert_raises(contains="affine"):
        box.apply_matrix4(projective)
    with assert_raises(contains="flattens"):
        box.apply_matrix4(scaling(0, 1, 1))
    with assert_raises(contains="flattens"):
        box.apply_matrix4(scaling(1, 0, 1))
    with assert_raises(contains="flattens"):
        box.apply_matrix4(scaling(1, 1, 0))


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
