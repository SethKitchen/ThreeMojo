# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Tests for frills along cuffs, collars and hems."""

from core.buffer_attribute import BufferAttribute
from core.buffer_geometry import POSITION, BufferGeometry
from extensions.attire.kinds import (
    COLLAR_RUFFLE,
    CUFF_RUFFLES,
    HEM_RUFFLE,
    NO_RUFFLES,
    RUFFLES_COUNT,
    Ruffles,
    require_ruffles,
    ruffles_label,
    ruffles_named,
)
from extensions.attire.mesh_ops import COVER, cut
from objects.skinned_mesh import SKIN_INDEX, SKIN_WEIGHT
from extensions.attire.ruffle import (
    RUFFLE_COVER,
    ruffle_mesh,
    ruffle_place,
    ruffle_shape,
)
from extensions.humanoid.rig.joints import (
    CHEST,
    HIPS,
    LEFT_UPPER_ARM,
    NECK,
    RIGHT_FOREARM,
    RIGHT_UPPER_ARM,
    SPINE,
    HumanoidRig,
)
from math.vector3 import Vector3
from std.testing import (
    TestSuite,
    assert_almost_equal,
    assert_equal,
    assert_false,
    assert_raises,
    assert_true,
)
from tests._attire_fixtures import standing_rig, tube


def _rig() raises -> HumanoidRig:
    """Return a standing rig: its neck at 0.5 m, its chest at 0.3 m, its
    shoulders 0.4 m apart and its right forearm hanging at minus x."""
    var rig = standing_rig()
    rig.joints[NECK.value] = Vector3(0, 0.5, 0)
    rig.joints[SPINE.value] = Vector3(0, 0.15, 0)
    rig.joints[CHEST.value] = Vector3(0, 0.3, 0)
    rig.joints[RIGHT_UPPER_ARM.value] = Vector3(-0.2, 0.45, 0)
    rig.ends[RIGHT_UPPER_ARM.value] = Vector3(-0.22, 0.17, 0)
    rig.joints[LEFT_UPPER_ARM.value] = Vector3(0.2, 0.45, 0)
    rig.ends[LEFT_UPPER_ARM.value] = Vector3(0.22, 0.17, 0)
    rig.joints[RIGHT_FOREARM.value] = Vector3(-0.22, 0.17, 0)
    rig.ends[RIGHT_FOREARM.value] = Vector3(-0.24, -0.1, 0)
    return rig^


def test_ruffles_are_named_sets_of_places() raises:
    for k in range(RUFFLES_COUNT):
        assert_equal(ruffles_named(ruffles_label(Ruffles(k))), Ruffles(k))
    assert_equal(ruffles_label(NO_RUFFLES), "none")
    assert_equal(ruffles_label(CUFF_RUFFLES | COLLAR_RUFFLE), "cuffs+collar")
    assert_equal(
        ruffles_label(CUFF_RUFFLES | COLLAR_RUFFLE | HEM_RUFFLE),
        "cuffs+collar+hem",
    )
    assert_equal(ruffles_label(Ruffles(8)), "ruffles")
    assert_false(Ruffles(-1).is_valid())
    var both = CUFF_RUFFLES | HEM_RUFFLE
    assert_true(both.has(CUFF_RUFFLES) and both.has(HEM_RUFFLE))
    assert_false(both.has(COLLAR_RUFFLE) or both.has(NO_RUFFLES))
    require_ruffles(both)
    with assert_raises(contains="Ruffles must"):
        require_ruffles(Ruffles(9))
    with assert_raises(contains="No ruffles"):
        _ = ruffles_named("jabot")


def test_each_place_has_a_shape() raises:
    var cuff = ruffle_shape(CUFF_RUFFLES)
    var hem = ruffle_shape(HEM_RUFFLE)
    assert_almost_equal(cuff.width, 0.045)
    assert_true(hem.width > ruffle_shape(COLLAR_RUFFLE).width)
    assert_true(hem.wave > cuff.wave)
    with assert_raises(contains="one place"):
        _ = ruffle_shape(NO_RUFFLES)
    with assert_raises(contains="one place"):
        _ = ruffle_shape(CUFF_RUFFLES | HEM_RUFFLE)


def test_an_open_edge_is_a_cuff_a_collar_or_a_hem() raises:
    var rig = _rig()
    var arm = RIGHT_FOREARM.value
    # Across the forearm, a cuff; along it, a seam that is none.
    assert_equal(
        ruffle_place(
            rig, Vector3(-0.25, 0, 0), Vector3(-0.2, 0, 0.01), arm, -0.3
        ),
        CUFF_RUFFLES,
    )
    assert_equal(
        ruffle_place(
            rig, Vector3(-0.25, 0, 0), Vector3(-0.25, -0.05, 0), arm, -0.3
        ),
        NO_RUFFLES,
    )
    # Level and close to the neck, above the waist: a collar.
    var trunk = CHEST.value
    assert_equal(
        ruffle_place(
            rig,
            Vector3(-0.02, 0.45, 0.07),
            Vector3(0.02, 0.45, 0.07),
            trunk,
            -0.3,
        ),
        COLLAR_RUFFLE,
    )
    # Out at the shoulder, or down at the waist, it is none.
    assert_equal(
        ruffle_place(
            rig, Vector3(0.18, 0.45, 0), Vector3(0.18, 0.45, 0.04), trunk, -0.3
        ),
        NO_RUFFLES,
    )
    assert_equal(
        ruffle_place(
            rig, Vector3(0, 0.1, 0.1), Vector3(0.04, 0.1, 0.1), trunk, -0.3
        ),
        NO_RUFFLES,
    )
    # Level, below the hips and low on the garment: a hem. Higher on it,
    # a skirt's top; upright there, the front of a coat.
    assert_equal(
        ruffle_place(
            rig, Vector3(0, -0.2, 0.2), Vector3(0.05, -0.2, 0.2), trunk, -0.3
        ),
        NO_RUFFLES,
    )
    assert_equal(
        ruffle_place(
            rig, Vector3(0, -0.5, 0.2), Vector3(0.05, -0.5, 0.2), trunk, -0.3
        ),
        HEM_RUFFLE,
    )
    assert_equal(
        ruffle_place(
            rig, Vector3(0, -0.5, 0.2), Vector3(0, -0.4, 0.2), trunk, -0.3
        ),
        NO_RUFFLES,
    )
    assert_equal(
        ruffle_place(
            rig, Vector3(0, -0.5, 0.2), Vector3(0, -0.5, 0.2), trunk, -0.3
        ),
        NO_RUFFLES,
    )


def _covered(var mesh: BufferGeometry) raises -> BufferGeometry:
    """Return a mesh with a `cover` value of one at each vertex."""
    mesh.set_attribute(
        String(COVER),
        BufferAttribute(List[Float32](length=mesh.vertex_count(), fill=1), 1),
    )
    return mesh^


def _covers(frill: BufferGeometry) raises -> Bool:
    """Return whether every vertex of a frill takes the trim's cover."""
    ref covers = frill.attribute_view(String(COVER))
    for v in range(covers.count()):
        if abs(covers.component(v, 0) - RUFFLE_COVER) > 1e-6:
            return False
    return True


def test_a_sleeve_grows_a_frill_at_each_open_end() raises:
    var rig = _rig()
    var sleeve = _covered(
        tube(-0.23, 0, 0.04, 0.1, -0.05, RIGHT_FOREARM, 3, 12)
    )
    var frill = ruffle_mesh(sleeve, sleeve, rig, CUFF_RUFFLES)
    assert_true(frill.triangle_count() > 0)
    assert_true(_covers(frill))
    assert_equal(frill.names, sleeve.names)
    # It grows down the forearm, past the cuff, and stands out round it.
    ref placed = frill.attribute_view(String(POSITION))
    var lowest = Float32(1)
    var widest = Float32(0)
    for v in range(placed.count()):
        var p = placed.vector3(v)
        lowest = min(lowest, p.y)
        widest = max(widest, Vector3(p.x + 0.23, 0, p.z).length())
    assert_true(lowest < -0.08)
    assert_true(widest > 0.04 + 0.015)
    # Nothing to grow, or an edge cut where another garment hides it.
    assert_equal(
        ruffle_mesh(sleeve, sleeve, rig, NO_RUFFLES).triangle_count(), 0
    )
    assert_equal(
        ruffle_mesh(sleeve, sleeve, rig, HEM_RUFFLE).triangle_count(), 0
    )
    var longer = tube(-0.23, 0, 0.04, 0.12, -0.07, RIGHT_FOREARM, 3, 12)
    assert_equal(
        ruffle_mesh(sleeve, longer, rig, CUFF_RUFFLES).triangle_count(), 0
    )
    with assert_raises(contains="Ruffles must"):
        _ = ruffle_mesh(sleeve, sleeve, rig, Ruffles(12))


def _heavier_second(
    var mesh: BufferGeometry, joint: Int
) raises -> BufferGeometry:
    """Return a mesh whose second bone, `joint`, weighs most."""
    var bones = List[Float32]()
    var weights = List[Float32]()
    for _ in range(mesh.vertex_count()):
        bones.append(Float32(HIPS.value))
        bones.append(Float32(joint))
        bones.append(0)
        bones.append(0)
        weights.append(0.2)
        weights.append(0.8)
        weights.append(0)
        weights.append(0)
    mesh.set_attribute(String(SKIN_INDEX), BufferAttribute(bones^, 4))
    mesh.set_attribute(String(SKIN_WEIGHT), BufferAttribute(weights^, 4))
    return mesh^


def test_a_frill_reads_the_heaviest_bone_and_the_edges_shown() raises:
    var rig = _rig()
    var sleeve = _covered(
        tube(-0.23, 0, 0.04, 0.1, -0.05, RIGHT_FOREARM, 3, 12)
    )
    var full = ruffle_mesh(sleeve, sleeve, rig, CUFF_RUFFLES).triangle_count()
    # The forearm weighs most though it is the second bone.
    var second = _heavier_second(sleeve.clone(), RIGHT_FOREARM.value)
    assert_equal(
        ruffle_mesh(second, second, rig, CUFF_RUFFLES).triangle_count(), full
    )
    # Half the sleeve shown: the frill grows along that half alone.
    ref placed = sleeve.attribute_view(String(POSITION))
    var side = List[Float32]()
    for v in range(placed.count()):
        side.append(placed.vector3(v).x + 0.23)
    var half = cut(sleeve, side, 0)
    var part = ruffle_mesh(half, sleeve, rig, CUFF_RUFFLES).triangle_count()
    assert_true(part > 0 and part < full)
    # A closed garment has no open edge to grow from.
    var closed = BufferGeometry()
    closed.set_attribute(
        String(POSITION),
        BufferAttribute([Float32(-0.2), 0, 0, -0.25, 0, 0, -0.22, 0, 0.05], 3),
    )
    closed.set_attribute(
        String(SKIN_INDEX),
        BufferAttribute(
            List[Float32](length=12, fill=Float32(RIGHT_FOREARM.value)), 4
        ),
    )
    closed.set_attribute(
        String(SKIN_WEIGHT),
        BufferAttribute([Float32(1), 0, 0, 0, 1, 0, 0, 0, 1, 0, 0, 0], 4),
    )
    closed.set_index([0, 1, 2, 0, 2, 1])
    assert_equal(
        ruffle_mesh(closed, closed, rig, CUFF_RUFFLES).triangle_count(), 0
    )


def test_a_hem_s_flutes_close_round_it() raises:
    var rig = _rig()
    var skirt = tube(0, 0, 0.2, -0.1, -0.5, HIPS, 4, 24)
    var frill = ruffle_mesh(skirt, skirt, rig, HEM_RUFFLE)
    assert_true(frill.triangle_count() > 0)
    # The edge of the flounce, 7 cm below the hem, rises and falls in
    # and out: its flutes.
    ref placed = frill.attribute_view(String(POSITION))
    var near = Float32(1)
    var far = Float32(0)
    for v in range(placed.count()):
        var p = placed.vector3(v)
        if abs(p.y + 0.57) < 1e-3:
            var r = Vector3(p.x, 0, p.z).length()
            near = min(near, r)
            far = max(far, r)
    assert_true(far - near > 0.02)
    # A collar round the neck falls out and down over the shoulders.
    var collar = _covered(tube(0, 0, 0.07, 0.48, 0.4, CHEST, 2, 16))
    var falling = ruffle_mesh(collar, collar, rig, COLLAR_RUFFLE)
    assert_true(falling.triangle_count() > 0)
    ref fallen = falling.attribute_view(String(POSITION))
    var widest = Float32(0)
    for v in range(fallen.count()):
        var p = fallen.vector3(v)
        widest = max(widest, Vector3(p.x, 0, p.z).length())
        assert_true(p.y <= 0.48 + 1e-4)
    assert_true(widest > 0.07 + 0.03)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
