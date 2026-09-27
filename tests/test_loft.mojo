# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Tests for `geometries.loft` and `objects.wireframe_geometry2`.

The expected numbers are what three.js r186's `LoftGeometry` gives for the
same sections, rounded to six places.
"""

from core.buffer_attribute import BufferAttribute
from core.buffer_geometry import BufferGeometry, NORMAL, POSITION, UV
from geometries.box import cube
from geometries.edges import wireframe_geometry
from geometries.loft import loft
from math.vector3 import Vector3
from objects.wireframe_geometry2 import wireframe_geometry2
from std.math import inf, nan
from std.testing import (
    TestSuite,
    assert_almost_equal,
    assert_equal,
    assert_raises,
    assert_true,
)
from units.si import Length, METER


def loft_closed_position() -> List[Float32]:
    """Return three.js r186 position for this loft."""
    return [
        Float32(1),
        0,
        1,
        1,
        0,
        -1,
        -1,
        0,
        -1,
        -1,
        0,
        1,
        1,
        0,
        1,
        0.5,
        1,
        0.5,
        0.5,
        1,
        -0.5,
        -0.5,
        1,
        -0.5,
        -0.5,
        1,
        0.5,
        0.5,
        1,
        0.5,
        0.5,
        3,
        0.5,
        0.5,
        3,
        -0.5,
        -0.5,
        3,
        -0.5,
        -0.5,
        3,
        0.5,
        0.5,
        3,
        0.5,
        -1,
        0,
        1,
        -1,
        0,
        -1,
        1,
        0,
        -1,
        1,
        0,
        1,
        0.5,
        3,
        0.5,
        0.5,
        3,
        -0.5,
        -0.5,
        3,
        -0.5,
        -0.5,
        3,
        0.5,
    ]


def loft_closed_normal() -> List[Float32]:
    """Return three.js r186 normal for this loft."""
    return [
        Float32(0.57735),
        0.57735,
        0.57735,
        0.683763,
        0.569803,
        -0.455842,
        -0.455842,
        0.569803,
        -0.683763,
        -0.683763,
        0.569803,
        0.455842,
        0.57735,
        0.57735,
        0.57735,
        0.667806,
        0.269717,
        0.69375,
        0.680414,
        0.272166,
        -0.680414,
        -0.680414,
        0.272166,
        -0.680414,
        -0.680414,
        0.272166,
        0.680414,
        0.667806,
        0.269717,
        0.69375,
        0.707107,
        0,
        0.707107,
        0.447214,
        0,
        -0.894427,
        -0.894427,
        0,
        -0.447214,
        -0.447214,
        0,
        0.894427,
        0.707107,
        0,
        0.707107,
        0,
        -1,
        0,
        0,
        -1,
        0,
        0,
        -1,
        0,
        0,
        -1,
        0,
        0,
        1,
        0,
        0,
        1,
        0,
        0,
        1,
        0,
        0,
        1,
        0,
    ]


def loft_closed_uv() -> List[Float32]:
    """Return three.js r186 uv for this loft."""
    return [
        Float32(0),
        0,
        0,
        0.25,
        0,
        0.5,
        0,
        0.75,
        0,
        1,
        0.379796,
        0,
        0.379796,
        0.25,
        0.379796,
        0.5,
        0.379796,
        0.75,
        0.379796,
        1,
        1,
        0,
        1,
        0.25,
        1,
        0.5,
        1,
        0.75,
        1,
        1,
        0,
        1,
        0,
        0,
        1,
        0,
        1,
        1,
        1,
        0,
        1,
        1,
        0,
        1,
        0,
        0,
    ]


def loft_closed_index() -> List[Int]:
    """Return three.js r186 index for this loft."""
    return [
        0,
        1,
        5,
        1,
        6,
        5,
        1,
        2,
        6,
        2,
        7,
        6,
        2,
        3,
        7,
        3,
        8,
        7,
        3,
        4,
        8,
        4,
        9,
        8,
        5,
        6,
        10,
        6,
        11,
        10,
        6,
        7,
        11,
        7,
        12,
        11,
        7,
        8,
        12,
        8,
        13,
        12,
        8,
        9,
        13,
        9,
        14,
        13,
        17,
        18,
        15,
        15,
        16,
        17,
        21,
        22,
        19,
        19,
        20,
        21,
    ]


def loft_x_position() -> List[Float32]:
    """Return three.js r186 position for this loft."""
    return [
        Float32(0),
        0,
        0,
        0,
        1,
        0,
        0,
        1,
        1,
        0,
        0,
        1,
        0,
        0,
        0,
        2,
        0,
        0,
        2,
        1,
        0,
        2,
        1,
        1,
        2,
        0,
        1,
        2,
        0,
        0,
        0,
        0,
        1,
        0,
        1,
        1,
        0,
        1,
        0,
        0,
        0,
        0,
        2,
        0,
        0,
        2,
        1,
        0,
        2,
        1,
        1,
        2,
        0,
        1,
    ]


def loft_x_normal() -> List[Float32]:
    """Return three.js r186 normal for this loft."""
    return [
        Float32(0),
        -0.707107,
        -0.707107,
        0,
        0.447214,
        -0.894427,
        0,
        0.894427,
        0.447214,
        0,
        -0.447214,
        0.894427,
        0,
        -0.707107,
        -0.707107,
        0,
        -0.707107,
        -0.707107,
        0,
        0.894427,
        -0.447214,
        0,
        0.447214,
        0.894427,
        0,
        -0.894427,
        0.447214,
        0,
        -0.707107,
        -0.707107,
        -1,
        0,
        0,
        -1,
        0,
        0,
        -1,
        0,
        0,
        -1,
        0,
        0,
        1,
        0,
        0,
        1,
        0,
        0,
        1,
        0,
        0,
        1,
        0,
        0,
    ]


def loft_x_uv() -> List[Float32]:
    """Return three.js r186 uv for this loft."""
    return [
        Float32(0),
        0,
        0,
        0.25,
        0,
        0.5,
        0,
        0.75,
        0,
        1,
        1,
        0,
        1,
        0.25,
        1,
        0.5,
        1,
        0.75,
        1,
        1,
        0,
        0,
        1,
        0,
        1,
        1,
        0,
        1,
        0,
        0,
        1,
        0,
        1,
        1,
        0,
        1,
    ]


def loft_x_index() -> List[Int]:
    """Return three.js r186 index for this loft."""
    return [
        0,
        1,
        5,
        1,
        6,
        5,
        1,
        2,
        6,
        2,
        7,
        6,
        2,
        3,
        7,
        3,
        8,
        7,
        3,
        4,
        8,
        4,
        9,
        8,
        12,
        13,
        10,
        10,
        11,
        12,
        16,
        17,
        14,
        14,
        15,
        16,
    ]


def loft_open_position() -> List[Float32]:
    """Return three.js r186 position for this loft."""
    return [Float32(0), 0, 0, 1, 0, 0, 3, 0, 0, 0, 0, 2, 1, 1, 2, 3, 0, 2]


def loft_open_normal() -> List[Float32]:
    """Return three.js r186 normal for this loft."""
    return [
        Float32(0),
        -1,
        0,
        0.227921,
        -0.911685,
        0.341882,
        -0.235702,
        -0.942809,
        0.235702,
        0.436436,
        -0.872872,
        0.218218,
        0,
        -0.957826,
        0.287348,
        -0.447214,
        -0.894427,
        0,
    ]


def loft_open_uv() -> List[Float32]:
    """Return three.js r186 uv for this loft."""
    return [Float32(0), 0, 0, 0.333333, 0, 1, 1, 0, 1, 0.387426, 1, 1]


def loft_open_index() -> List[Int]:
    """Return three.js r186 index for this loft."""
    return [0, 1, 3, 1, 4, 3, 1, 2, 4, 2, 5, 4]


def square(y: Float32, half: Float32) -> List[Vector3]:
    """Return a square section across the y axis, three.js's test's."""
    return [
        Vector3(half, y, half),
        Vector3(half, y, -half),
        Vector3(-half, y, -half),
        Vector3(-half, y, half),
    ]


def ring(x: Float32) -> List[Vector3]:
    """Return a square section across the x axis."""
    return [
        Vector3(x, 0, 0),
        Vector3(x, 1, 0),
        Vector3(x, 1, 1),
        Vector3(x, 0, 1),
    ]


def assert_floats(
    geometry: BufferGeometry, name: String, expected: List[Float32]
) raises:
    """Assert that an attribute holds three.js's numbers, to six places."""
    ref got = geometry.attribute_view(name)
    assert_equal(len(got.data), len(expected), name)
    for index in range(len(expected)):
        assert_almost_equal(got.data[index], expected[index], atol=2e-5)


def assert_matches(
    geometry: BufferGeometry,
    position: List[Float32],
    normal: List[Float32],
    uv: List[Float32],
    index: List[Int],
) raises:
    """Assert that a geometry is three.js's, attribute by attribute."""
    assert_floats(geometry, POSITION, position)
    assert_floats(geometry, NORMAL, normal)
    assert_floats(geometry, UV, uv)
    assert_equal(len(geometry.index), len(index))
    for at in range(len(index)):
        assert_equal(geometry.index[at], index[at])


def test_a_closed_tapering_loft_with_both_caps_is_threes() raises:
    var geometry = loft(
        [square(0, 1), square(1, 0.5), square(3, 0.5)],
        cap_start=True,
        cap_end=True,
    )
    assert_matches(
        geometry,
        loft_closed_position(),
        loft_closed_normal(),
        loft_closed_uv(),
        loft_closed_index(),
    )


def test_a_loft_along_x_lays_its_caps_on_another_tangent() raises:
    # The caps face along x, so the tangent three.js starts from is y.
    var geometry = loft([ring(0), ring(2)], cap_start=True, cap_end=True)
    assert_matches(
        geometry,
        loft_x_position(),
        loft_x_normal(),
        loft_x_uv(),
        loft_x_index(),
    )


def test_an_open_loft_is_a_strip() raises:
    var geometry = loft(
        [
            [Vector3(0, 0, 0), Vector3(1, 0, 0), Vector3(3, 0, 0)],
            [Vector3(0, 0, 2), Vector3(1, 1, 2), Vector3(3, 0, 2)],
        ],
        closed=False,
    )
    assert_matches(
        geometry,
        loft_open_position(),
        loft_open_normal(),
        loft_open_uv(),
        loft_open_index(),
    )


def test_sections_of_no_length_fall_back_to_even_texture_coordinates() raises:
    # Every section is the same point twice: no distance along the loft
    # and none around a section, so u and v step evenly, as three.js's
    # `i / ( rows - 1 )` and `j / ( pointsPerRow - 1 )`.
    var point = Vector3(1, 2, 3)
    var geometry = loft(
        [[point, point], [point, point], [point, point]], closed=False
    )
    ref uv = geometry.attribute_view(UV)
    assert_almost_equal(uv.data[0], 0)
    assert_almost_equal(uv.data[1], 0)
    assert_almost_equal(uv.data[3], 1)
    assert_almost_equal(uv.data[4], 0.5)
    assert_almost_equal(uv.data[10], 1)


def test_a_cap_of_two_points_has_no_triangle() raises:
    # Two points enclose nothing: the cap adds its vertices and no face.
    var geometry = loft(
        [
            [Vector3(0, 0, 0), Vector3(1, 0, 0)],
            [Vector3(0, 1, 0), Vector3(1, 1, 0)],
        ],
        closed=False,
        cap_start=True,
    )
    assert_equal(geometry.attribute_view(POSITION).count(), 6)
    assert_equal(len(geometry.index), 6)


def test_a_loft_refuses_sections_it_cannot_join() raises:
    with assert_raises(contains="two sections"):
        _ = loft([square(0, 1)])
    with assert_raises(contains="two points"):
        _ = loft([[Vector3(0, 0, 0)], [Vector3(0, 1, 0)]])
    with assert_raises(contains="same number"):
        var three: List[Vector3] = [
            Vector3(1, 1, 1),
            Vector3(1, 1, 0),
            Vector3(0, 1, 0),
        ]
        _ = loft([square(0, 1), three^])
    var bad = square(1, 1)
    bad[2] = Vector3(nan[DType.float32](), 1, 0)
    with assert_raises(contains="finite"):
        _ = loft([square(0, 1), bad.copy()])
    bad[2] = Vector3(0, inf[DType.float32](), 0)
    with assert_raises(contains="finite"):
        _ = loft([square(0, 1), bad.copy()])
    bad[2] = Vector3(0, 1, -inf[DType.float32]())
    with assert_raises(contains="finite"):
        _ = loft([square(0, 1), bad.copy()])


def test_a_wireframe2_holds_every_edge_of_a_box_once() raises:
    # three.js's `WireframeGeometry2` of a unit `BoxGeometry` holds 18
    # segments: twelve edges and a diagonal across each face.
    var box = cube(Length(1.0, METER))
    var wide = wireframe_geometry2(box)
    ref points = wide.attribute_view(POSITION)
    assert_equal(points.count(), 36)
    var plain = wireframe_geometry(box)
    ref expected = plain.attribute_view(POSITION)
    for index in range(len(expected.data)):
        assert_almost_equal(points.data[index], expected.data[index])


def test_a_wireframe2_of_nothing_is_empty() raises:
    var empty = BufferGeometry()
    empty.set_attribute(POSITION, BufferAttribute(List[Float32](), 3))
    var wide = wireframe_geometry2(empty)
    assert_equal(wide.attribute_view(POSITION).count(), 0)
    with assert_raises():
        _ = wireframe_geometry2(BufferGeometry())


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Tests for the lofted skin, the one skin of a limb, and the physical
tissue looks."""

from core.assets import Assets
from core.buffer_geometry import NORMAL, POSITION, UV
from core.object3d import Object3D
from core.scene import Scene
from extensions.humanoid.sex import MALE
from extensions.humanoid.side import LEFT, RIGHT
from extensions.humanoid.spec import HumanoidSpec
from extensions.humanoid.skeleton.bone import bone_physical
from extensions.humanoid.skeleton.leg.assembly import assemble_leg
from extensions.humanoid.skeleton.limb.skin import (
    LimbSkinField,
    add_limb_skin,
    limb_skin_mesh,
)
from extensions.humanoid.skeleton.loft import (
    AXIS_Y,
    AXIS_Z,
    LOFT_RAYS,
    LoftSample,
    fit_loft,
    loft_distance,
)
from extensions.humanoid.skeleton.look import (
    cartilage_physical,
    ligament_physical,
    muscle_physical,
    skin_physical,
    tendon_physical,
)
from materials.material import PHYSICAL
from math.vector3 import Vector3
from render.framebuffer import Color
from render.texture_store import NO_TEXTURE, TextureId
from std.testing import (
    TestSuite,
    assert_almost_equal,
    assert_equal,
    assert_false,
    assert_raises,
    assert_true,
)
from units.si import FOOT, Length


def _covers(count: Int, cover: Float32) -> List[Float32]:
    """Return one cover per section."""
    return List[Float32](length=count, fill=cover)


def _rod(a: Vector3, b: Vector3, radius: Float32) -> List[LoftSample]:
    """Return one round segment from `a` to `b`."""
    var samples = List[LoftSample]()
    samples.append(LoftSample(a, radius, radius, 0, False))
    samples.append(LoftSample(b, radius, radius, 0, True))
    return samples^


def test_a_loft_refuses_what_it_cannot_fit() raises:
    var rod = _rod(Vector3(0, 0, 0), Vector3(0, 1, 0), 0.1)
    with assert_raises(contains="AXIS_Y or AXIS_Z"):
        _ = fit_loft(rod, 0, 0, 1, 4, _covers(4, 0.01))
    with assert_raises(contains="two sections"):
        _ = fit_loft(rod, AXIS_Y, 0, 1, 1, _covers(1, 0.01))
    with assert_raises(contains="past its start"):
        _ = fit_loft(rod, AXIS_Y, 1, 1, 4, _covers(4, 0.01))
    with assert_raises(contains="one cover per section"):
        _ = fit_loft(rod, AXIS_Y, 0, 1, 4, _covers(3, 0.01))


def test_a_loft_around_an_upright_rod_is_the_rod_and_its_cover() raises:
    var loft = fit_loft(
        _rod(Vector3(0, 0, 0), Vector3(0, 1, 0), 0.1),
        AXIS_Y,
        0.2,
        0.8,
        7,
        _covers(7, 0.02),
    )
    assert_equal(loft.count, 7)
    # Every ray of a round section reaches the rod and its cover, and
    # the polygon of tangents exceeds the circle by under half a percent.
    for ray in range(LOFT_RAYS):
        var r = loft.section_radius(3, ray)
        assert_true(r >= Float32(0.12) - Float32(1.0e-4))
        assert_true(r <= Float32(0.1206))
    assert_almost_equal(
        loft_distance(loft, Vector3(0.2, 0.5, 0)), 0.08, atol=0.002
    )
    assert_almost_equal(
        loft_distance(loft, Vector3(0, 0.5, 0)), -0.12, atol=0.002
    )
    # Past either end the loft is cut flat.
    assert_almost_equal(
        loft_distance(loft, Vector3(0, 0.9, 0)), 0.1, atol=0.002
    )
    assert_almost_equal(
        loft_distance(loft, Vector3(0.2, 0.1, 0)), 0.1281, atol=0.002
    )
    assert_true(loft.low.y < Float32(0.2))
    assert_true(loft.high.y > Float32(0.8))


def test_a_rod_along_the_sections_cuts_a_strip() raises:
    # A tendon that runs along a foot's section, as one over the ankle
    # does, is sliced lengthwise into a long strip.
    var loft = fit_loft(
        _rod(Vector3(0, -0.3, 0), Vector3(0, 0.3, 0), 0.02),
        AXIS_Z,
        -0.1,
        0.1,
        5,
        _covers(5, 0.0),
    )
    var middle = 2
    var up = LOFT_RAYS // 4
    assert_true(loft.section_radius(middle, up) > Float32(0.30))
    assert_true(loft.section_radius(middle, 0) < Float32(0.03))
    # A slanted rod crosses every section once.
    var slant = fit_loft(
        _rod(Vector3(0, 0, -0.2), Vector3(0.1, 0.05, 0.2), 0.02),
        AXIS_Z,
        -0.15,
        0.15,
        7,
        _covers(7, 0.005),
    )
    assert_true(loft_distance(slant, Vector3(0.05, 0.025, 0)) < 0)
    assert_true(loft_distance(slant, Vector3(0.05, 0.2, 0)) > 0)


def test_empty_sections_taper_to_their_cover() raises:
    # A lone ellipsoid in the middle: the sections either side of it
    # hold nothing, take its center, and shrink to the cover.
    var samples = List[LoftSample]()
    samples.append(LoftSample(Vector3(0, 0.5, 0), 0.1, 0.05, 0.1, False))
    var loft = fit_loft(samples, AXIS_Y, 0, 1, 11, _covers(11, 0.01), 2)
    assert_almost_equal(loft.section_radius(0, 0), 0.01, atol=1.0e-4)
    assert_almost_equal(loft.center_u[0], loft.center_u[5], atol=1.0e-5)
    assert_true(loft.section_radius(5, 0) > Float32(0.10))
    # A loft that holds nothing at all keeps every center at the origin.
    var far = List[LoftSample]()
    far.append(LoftSample(Vector3(0, 9, 0), 0.1, 0.1, 0, False))
    var empty = fit_loft(far, AXIS_Y, 0, 1, 4, _covers(4, 0.01))
    assert_almost_equal(empty.center_u[2], 0, atol=1.0e-6)
    assert_almost_equal(empty.section_radius(2, 0), 0.01, atol=1.0e-4)


def test_a_section_keeps_its_own_center_when_smoothing_leaves_it() raises:
    # A thin rod that jumps sideways: smoothing would move the centers
    # beside the jump off the rod, so those sections keep their own, and
    # the rod stays inside at every section.
    var samples = _rod(Vector3(0, 0, 0), Vector3(0, 0.5, 0), 0.01)
    for sample in _rod(Vector3(0.3, 0.5, 0), Vector3(0.3, 1.0, 0), 0.01):
        samples.append(sample)
    var loft = fit_loft(samples, AXIS_Y, 0.05, 0.95, 10, _covers(10, 0.002))
    assert_almost_equal(loft.center_u[3], 0, atol=1.0e-5)
    assert_almost_equal(loft.center_u[6], 0.3, atol=1.0e-5)
    assert_true(loft_distance(loft, Vector3(0, 0.35, 0)) < 0)
    assert_true(loft_distance(loft, Vector3(0.3, 0.65, 0)) < 0)


def test_one_skin_covers_a_limb_and_its_foot() raises:
    var person = HumanoidSpec(Length(6.0, FOOT), MALE)
    var skin = LimbSkinField(person, RIGHT)
    var pose = assemble_leg(person, RIGHT)
    # The knee, the ankle and the foot's middle are inside; far away is
    # not.
    assert_true(skin.distance(pose.tibia_origin) < 0)
    assert_true(skin.distance(pose.ankle_center()) < 0)
    var arch = pose.ankle_center() + Vector3(0, -0.04, 0.06)
    assert_true(skin.distance(arch) < 0)
    assert_true(skin.distance(Vector3(10, 0, 0)) > 0)
    var n = skin.gradient(Vector3(10, 0, 0))
    assert_true(n.length() > Float32(0.5))
    assert_true(skin.low.y < pose.ankle_center().y)
    assert_true(skin.high.y > pose.hip_center().y)
    var left = LimbSkinField(person, LEFT)
    assert_true(
        left.distance(
            Vector3(
                -pose.tibia_origin.x, pose.tibia_origin.y, pose.tibia_origin.z
            )
        )
        < 0
    )


def test_one_skin_meshes_and_attaches() raises:
    var person = HumanoidSpec(Length(6.0, FOOT), MALE)
    var mesh = limb_skin_mesh(person, RIGHT, 8)
    assert_true(mesh.has_attribute(String(POSITION)))
    assert_true(mesh.has_attribute(String(NORMAL)))
    assert_true(mesh.has_attribute(String(UV)))
    assert_true(mesh.triangle_count() > 0)
    with assert_raises(contains="at least eight"):
        _ = limb_skin_mesh(person, RIGHT, 7)
    var scene = Scene()
    var assets = Assets()
    var paint = assets.materials.add(skin_physical())
    var root = scene.add(Object3D())
    var node = add_limb_skin(scene, assets, root, person, paint, RIGHT, 8)
    assert_equal(len(scene.meshes), 1)
    assert_true(scene.meshes[0].node == node)


def test_physical_looks_are_physical() raises:
    var map = TextureId(0)
    for look in [
        skin_physical(),
        skin_physical(map),
        muscle_physical(),
        muscle_physical(map),
        bone_physical(),
        bone_physical(map),
        tendon_physical(),
        ligament_physical(),
        cartilage_physical(),
    ]:
        assert_true(look.kind == PHYSICAL)
        assert_true(look.roughness > 0)
        assert_true(look.ior > Float32(1.3))
    # A map arrives unshifted; the bare looks carry their own color.
    assert_equal(skin_physical(map).color.r, 255)
    assert_true(skin_physical().color.r < 255)
    assert_equal(muscle_physical(map).color.r, 255)
    assert_equal(bone_physical(map).color.r, 255)
    assert_true(skin_physical().sheen > 0)
    assert_true(tendon_physical().sheen > 0)
    assert_true(muscle_physical().clearcoat > 0)
    assert_true(cartilage_physical().clearcoat > 0)
    assert_equal(skin_physical().map, NO_TEXTURE)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
