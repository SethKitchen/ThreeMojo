# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Tests for a garment's dyes, its patterns and its wear."""

from core.buffer_attribute import BufferAttribute
from core.buffer_geometry import COLOR, POSITION, BufferGeometry
from extensions.attire.dye import (
    DYE,
    TRIM_LEVEL,
    WEAR,
    dye_pattern,
    paint,
    pattern_values,
    soil,
    stain,
    worn_color,
)
from extensions.attire.kinds import (
    ACCENT_DYE,
    BLOOD,
    DIRT,
    PARTY,
    PRIMARY_DYE,
    QUARTERLY,
    SECONDARY_DYE,
    SOLID,
    STRIPES,
    TRIM_DYE,
    WET,
    BANDED_SLEEVES,
    BEND,
    CHECKY,
    FRONT_PANEL,
    SLEEVES,
    CHEVRON,
    CROSS,
    PALY,
    SALTIRE,
    DyePattern,
    WearKind,
)
from extensions.attire.mesh_ops import ACCENT
from extensions.attire.shell import COVER
from extensions.humanoid.rig.joints import HIPS, RIGHT_UPPER_ARM
from math.vector3 import Vector3
from render.framebuffer import Color
from std.math import nan
from std.testing import (
    TestSuite,
    assert_almost_equal,
    assert_equal,
    assert_raises,
    assert_true,
)
from tests._attire_fixtures import empty_mesh, line_rig, strip, tube
from units.si import Length, METER


def _sheet() raises -> BufferGeometry:
    """Return a strip from x = -0.5 to 0.5, y = 0 to -1, fully covered."""
    var mesh = strip(0, 4, HIPS)
    mesh.set_attribute(
        String(COVER), BufferAttribute(List[Float32](length=10, fill=1), 1)
    )
    return mesh^


def test_patterns_sign_each_vertex() raises:
    var rig = line_rig()
    var mesh = _sheet()
    # Vertex 0 is at x = -0.5, vertex 1 at x = 0.5; the line rig's right
    # arm stands at plus x.
    var solid = pattern_values(mesh, rig, SOLID)
    assert_equal(solid[0], 1)
    var party = pattern_values(mesh, rig, PARTY)
    assert_true(party[0] < 0 and party[1] > 0)
    # Mirror the rig: the right arm at minus x. The wearer's right still
    # takes the primary dye.
    var mirrored = rig.copy()
    mirrored.joints[RIGHT_UPPER_ARM.value] = Vector3(-5, 0, 0)
    var flipped = pattern_values(mesh, mirrored, PARTY)
    assert_true(flipped[0] > 0 and flipped[1] < 0)
    var quarters = pattern_values(mesh, rig, QUARTERLY)
    assert_true(quarters[2] > 0 and quarters[3] < 0)
    var stripes = pattern_values(mesh, rig, STRIPES)
    assert_equal(len(stripes), 10)
    with assert_raises(contains="named pattern"):
        _ = pattern_values(mesh, rig, DyePattern(40))


def test_charges_lie_on_the_chest() raises:
    # The line rig's chest stands at the origin, its waist too, and its
    # right arm at plus x: across is x, up from the chest is y.
    var rig = line_rig()
    var at: List[Vector3] = [
        Vector3(0, 0, 0),
        Vector3(0.3, -0.3, 0),
        Vector3(0.3, 0.3, 0),
        Vector3(0.3, 0, 0),
        Vector3(0.5, -0.44, 0),
        Vector3(0, -0.3, 0),
        Vector3(0.045, 0.045, 0),
        Vector3(-0.045, 0.045, 0),
        Vector3(0.045, -0.045, 0),
    ]
    var flat = List[Float32]()
    for p in at:
        flat.append(p.x)
        flat.append(p.y)
        flat.append(p.z)
    var mesh = BufferGeometry()
    mesh.set_attribute(String(POSITION), BufferAttribute(flat^, 3))
    # A cross: on its arms, the secondary dye; between them, the field.
    var cross = pattern_values(mesh, rig, CROSS)
    assert_true(cross[0] < 0 and cross[3] < 0 and cross[1] > 0)
    # A saltire: on its diagonals, not across the middle.
    var saltire = pattern_values(mesh, rig, SALTIRE)
    assert_true(saltire[1] < 0 and saltire[2] < 0 and saltire[3] > 0)
    # A bend: from the right shoulder down to the left hip.
    var bend = pattern_values(mesh, rig, BEND)
    assert_true(bend[2] < 0 and bend[0] < 0 and bend[1] > 0)
    # A chevron: its point over the chest, its arms falling away.
    var chevron = pattern_values(mesh, rig, CHEVRON)
    assert_true(chevron[0] < 0 and chevron[4] < 0 and chevron[5] > 0)
    # Paly and checky: bands up and down, and squares.
    var paly = pattern_values(mesh, rig, PALY)
    assert_true(paly[6] > 0 and paly[7] < 0)
    var checky = pattern_values(mesh, rig, CHECKY)
    assert_true(checky[6] > 0 and checky[7] < 0 and checky[8] < 0)


def test_a_front_panel_and_sleeves_take_the_second_dye() raises:
    var rig = line_rig()
    var at: List[Vector3] = [
        Vector3(0, 0.1, 0.1),
        Vector3(0.4, 0.1, 0.1),
        Vector3(0.15, -0.5, 0.1),
        Vector3(0, 0.1, -0.1),
    ]
    var flat = List[Float32]()
    for p in at:
        flat.append(p.x)
        flat.append(p.y)
        flat.append(p.z)
    var mesh = BufferGeometry()
    mesh.set_attribute(String(POSITION), BufferAttribute(flat^, 3))
    # A panel down the middle of the front, wider down a skirt, and none
    # behind.
    var panel = pattern_values(mesh, rig, FRONT_PANEL)
    assert_true(panel[0] < 0 and panel[1] > 0)
    assert_true(panel[2] < 0 and panel[3] > 0)
    # A mesh with no skin weights has no sleeves.
    for value in pattern_values(mesh, rig, SLEEVES):
        assert_true(value > 0)
    # The arm's skin takes the second dye; the trunk's does not.
    var arm = tube(0, 0, 0.05, 0, -0.4, RIGHT_UPPER_ARM, 8, 6)
    for value in pattern_values(arm, rig, SLEEVES):
        assert_true(value < 0)
    var trunk = tube(0, 0, 0.15, 0, -0.4, HIPS, 8, 6)
    for value in pattern_values(trunk, rig, SLEEVES):
        assert_true(value > 0)
    # Banded sleeves: both dyes down the arm, the trunk plain.
    var low = Float32(1)
    var high = Float32(-1)
    for value in pattern_values(arm, rig, BANDED_SLEEVES):
        low = min(low, value)
        high = max(high, value)
    assert_true(low < 0 and high > 0)
    for value in pattern_values(trunk, rig, BANDED_SLEEVES):
        assert_true(value >= 0)


def test_a_pattern_cuts_crisp_boundaries_and_trims_hems() raises:
    var rig = line_rig()
    var mesh = _sheet()
    # The lowest rung is on the hem.
    var covered = mesh.clone_attribute(String(COVER))
    covered.set_component(8, 0, TRIM_LEVEL - 0.3)
    covered.set_component(9, 0, TRIM_LEVEL - 0.3)
    mesh.set_attribute(String(COVER), covered^)
    var dyed = dye_pattern(mesh, rig, PARTY)
    ref weights = dyed.attribute_view(String(DYE))
    var channels = List[Int](length=4, fill=0)
    for v in range(weights.count()):
        var total = Float32(0)
        for c in range(4):
            total += weights.component(v, c)
            if weights.component(v, c) == 1:
                channels[c] += 1
        assert_equal(total, 1)
    assert_true(channels[PRIMARY_DYE.value] > 0)
    assert_true(channels[SECONDARY_DYE.value] > 0)
    assert_true(channels[TRIM_DYE.value] > 0)
    # Every pattern makes a mesh; a stripe's boundary splits the sheet.
    for pattern in [SOLID, STRIPES, QUARTERLY]:
        assert_true(dye_pattern(_sheet(), rig, pattern).triangle_count() > 0)
    with assert_raises(contains="named pattern"):
        _ = dye_pattern(mesh, rig, DyePattern(-2))
    # A vertex marked as an accent takes the accent dye.
    var marked = _sheet()
    var marks = List[Float32](length=marked.vertex_count(), fill=0)
    marks[0] = 1
    marks[1] = 1
    marked.set_attribute(String(ACCENT), BufferAttribute(marks^, 1))
    var accented = dye_pattern(marked, rig, SOLID)
    ref accent_weights = accented.attribute_view(String(DYE))
    ref accent_marks = accented.attribute_view(String(ACCENT))
    var accents = 0
    for v in range(accent_weights.count()):
        if accent_marks.component(v, 0) >= 0.5:
            assert_equal(accent_weights.component(v, ACCENT_DYE.value), 1)
            accents += 1
        else:
            assert_equal(accent_weights.component(v, ACCENT_DYE.value), 0)
    assert_true(accents >= 2)


def test_stains_and_dirt_add_wear() raises:
    var mesh = _sheet()
    stain(mesh, BLOOD, Vector3(0.5, 0, 0), Length(0.3, METER), 0.8)
    ref wear = mesh.attribute_view(String(WEAR))
    assert_almost_equal(wear.component(1, BLOOD.value), 0.8)
    assert_equal(wear.component(0, BLOOD.value), 0)
    # A second stain adds, and no channel passes one.
    stain(mesh, BLOOD, Vector3(0.5, 0, 0), Length(0.3, METER), 0.8)
    assert_equal(mesh.attribute_view(String(WEAR)).component(1, 1), 1)
    soil(mesh, Length(0.5, METER), 0.6)
    ref soiled = mesh.attribute_view(String(WEAR))
    # The lowest rung is dirtiest; above the reach there is no dirt.
    assert_almost_equal(soiled.component(8, DIRT.value), 0.6)
    assert_equal(soiled.component(0, DIRT.value), 0)
    soil(mesh, Length(0.5, METER), 0.6)
    assert_equal(mesh.attribute_view(String(WEAR)).component(8, 0), 1)
    # A fresh garment gets wear from dirt alone.
    var fresh = _sheet()
    soil(fresh, Length(2, METER), 0.1)
    assert_true(fresh.has_attribute(String(WEAR)))
    var spot = Vector3(0, 0, 0)
    with assert_raises(contains="named channel"):
        stain(mesh, WearKind(9), spot, Length(1, METER), 0.5)
    with assert_raises(contains="positive radius"):
        stain(mesh, DIRT, spot, Length(0, METER), 0.5)
    with assert_raises(contains="positive radius"):
        stain(mesh, DIRT, spot, Length(nan[DType.float32](), METER), 0.5)
    with assert_raises(contains="zero through one"):
        stain(mesh, DIRT, spot, Length(1, METER), -0.1)
    with assert_raises(contains="zero through one"):
        stain(mesh, DIRT, spot, Length(1, METER), 1.1)
    with assert_raises(contains="positive reach"):
        soil(mesh, Length(-1, METER), 0.5)
    with assert_raises(contains="zero through one"):
        soil(mesh, Length(1, METER), -0.5)
    with assert_raises(contains="zero through one"):
        soil(mesh, Length(1, METER), 2)


def test_wear_darkens_reddens_and_scorches() raises:
    var white = Vector3(1, 1, 1)
    var clean = worn_color(white, [0, 0, 0, 0])
    assert_equal(clean.x, 1)
    var bloody = worn_color(white, [0, 1, 0, 0])
    assert_true(bloody.x > bloody.y)
    var wet = worn_color(white, [0, 0, 1, 0])
    assert_almost_equal(wet.y, 0.6)
    var dirty = worn_color(white, [1, 0, 0, 0])
    assert_true(dirty.x < 0.5 and dirty.x > dirty.z)
    var burnt = worn_color(white, [0, 0, 0, 1])
    assert_true(burnt.x < 0.5)


def test_paint_mixes_dyes_then_wear() raises:
    var rig = line_rig()
    var dyed = dye_pattern(_sheet(), rig, SOLID)
    var dyes = List[Color](length=4, fill=Color(255, 255, 255))
    dyes[0] = Color(255, 0, 0)
    paint(dyed, dyes)
    ref colors = dyed.attribute_view(String(COLOR))
    assert_almost_equal(colors.component(0, 0), 1)
    assert_almost_equal(colors.component(0, 1), 0)
    stain(dyed, WET, Vector3(0, 0, 0), Length(5, METER), 1)
    paint(dyed, dyes)
    assert_true(dyed.attribute_view(String(COLOR)).component(0, 0) < 1)
    with assert_raises(contains="four dyes"):
        paint(dyed, [Color(0, 0, 0)])


def test_an_empty_garment_dyes_and_wears_nothing() raises:
    var rig = line_rig()
    var empty = empty_mesh()
    empty.set_attribute(String(COVER), BufferAttribute(List[Float32](), 1))
    assert_equal(len(pattern_values(empty, rig, QUARTERLY)), 0)
    var piece = dye_pattern(empty, rig, PARTY)
    assert_equal(piece.vertex_count(), 0)
    stain(piece, BLOOD, Vector3(0, 0, 0), Length(0.1, METER), 1)
    soil(piece, Length(0.3, METER), 0.5)
    paint(
        piece,
        [Color(1, 2, 3), Color(4, 5, 6), Color(7, 8, 9), Color(10, 11, 12)],
    )
    assert_equal(piece.attribute_view(String(COLOR)).count(), 0)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
