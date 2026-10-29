# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""The small things that dress a house's rooms, and the warm light of
their flames."""

from extensions.village.dressing import (
    CANDLE,
    FILL,
    FIRELIGHT,
    FLAME,
    Glow,
    HEARTH,
    LANTERN,
    PATCHES_ALONG,
    PATCHES_DOWN,
    RUG_CELLS,
    RUG_LIFT,
    RUG_ROWS,
    books,
    dye,
    glaze,
    herbs,
    jars,
    lantern,
    patchwork,
    prism,
    rug,
    table_setting,
    warm,
    warmth,
)
from extensions.village.sheet import Sheet
from math.vector3 import Vector3
from std.testing import (
    TestSuite,
    assert_almost_equal,
    assert_equal,
    assert_false,
    assert_true,
)


def _close(a: Vector3, b: Vector3) -> Bool:
    """Return whether two colors are the same to a millionth."""
    return (a - b).length() < 1.0e-6


def test_the_dyes_and_the_glazes_repeat() raises:
    assert_true(_close(dye(0), dye(5)))
    assert_false(_close(dye(0), dye(1)))
    assert_true(_close(glaze(2), glaze(7)))
    assert_false(_close(glaze(2), glaze(3)))


def test_a_glow_is_placed_in_its_storey() raises:
    var glow = CANDLE.placed(Vector3(1, 2, 3), 0.5, 3)
    assert_equal(glow.at.y, 2)
    assert_equal(glow.strength, CANDLE.strength)
    assert_equal(glow.reach, CANDLE.reach)
    assert_equal(glow.low, 0.5)
    assert_equal(glow.high, 3)
    # A fire is stronger and reaches further than a lantern, and a
    # lantern than a candle.
    assert_true(HEARTH.strength > LANTERN.strength)
    assert_true(LANTERN.reach > CANDLE.reach)


def test_a_flame_warms_what_faces_it_and_is_near() raises:
    var glows = List[Glow]()
    var up = Vector3(0, 1, 0)
    # No flame warms nothing.
    assert_equal(warmth(glows, Vector3(0, 0, 0), up), 0)
    glows.append(Glow(Vector3(0, 1, 0), 1, 2, 0, 3))
    # Under the flame, facing it: it warms most when near.
    var near = warmth(glows, Vector3(0, 0.5, 0), up)
    var far = warmth(glows, Vector3(0, 0, 0), up)
    assert_almost_equal(near, 0.5625, atol=1e-5)
    assert_true(far < near)
    # Facing away, or on its side, a surface takes none of it.
    assert_equal(warmth(glows, Vector3(0, 0.5, 0), Vector3(0, -1, 0)), 0)
    assert_equal(warmth(glows, Vector3(0, 0.5, 0), Vector3(1, 0, 0)), 0)
    # At the flame, any surface takes all of it.
    assert_almost_equal(
        warmth(glows, Vector3(0, 1, 0), Vector3(1, 0, 0)), 1, atol=1e-5
    )
    # Out of its reach, below its floor or over its ceiling, none.
    assert_equal(warmth(glows, Vector3(0, 1, 2.5), Vector3(0, 0, -1)), 0)
    assert_equal(warmth(glows, Vector3(0, -0.1, 0), up), 0)
    assert_equal(warmth(glows, Vector3(0, 3.1, 0), Vector3(0, -1, 0)), 0)
    # Two flames add.
    glows.append(Glow(Vector3(0, 1, 0), 1, 2, 0, 3))
    assert_almost_equal(
        warmth(glows, Vector3(0, 0.5, 0), up), 2 * near, atol=1e-5
    )


def test_warm_lights_the_inside_of_a_house_only() raises:
    var sheet = Sheet(1)
    var color = Vector3(0.5, 0.5, 0.5)
    var up = Vector3(0, 1, 0)
    # Inside, outside along x, and outside along z.
    _ = sheet.vertex(Vector3(0, 0.5, 0), up, color, 0, 0)
    _ = sheet.vertex(Vector3(3, 0.5, 0), up, color, 0, 0)
    _ = sheet.vertex(Vector3(0, 0.5, 3), up, color, 0, 0)
    var glows: List[Glow] = [Glow(Vector3(0, 1, 0), 1, 2, 0, 3)]
    warm(sheet, glows, 2, 2, FILL)
    var w = Float32(0.5625)
    assert_almost_equal(
        sheet.colors[0], 0.5 * FILL.x * (1 + FIRELIGHT.x * w), atol=1e-5
    )
    assert_almost_equal(
        sheet.colors[2], 0.5 * FILL.z * (1 + FIRELIGHT.z * w), atol=1e-5
    )
    for k in range(3, 9):
        assert_equal(sheet.colors[k], 0.5)
    # A fill of one and no flame change nothing, and an empty sheet is
    # left empty.
    var plain = Sheet(1)
    _ = plain.vertex(Vector3(0, 0.5, 0), up, color, 0, 0)
    warm(plain, List[Glow](), 2, 2, Vector3(1, 1, 1))
    assert_equal(plain.colors[1], 0.5)
    var empty = Sheet(1)
    warm(empty, glows, 2, 2, FILL)
    assert_equal(len(empty.colors), 0)


def test_a_prism_has_its_sides_and_a_lid() raises:
    var sheet = Sheet(1)
    prism(sheet, Vector3(0, 0, 0), 0.1, 0.05, 0.3, 6, Vector3(1, 1, 1))
    # Six sides of two triangles, and a lid of six.
    assert_equal(sheet.triangles(), 18)
    var top = Float32(0)
    for v in range(len(sheet.positions) // 3):
        top = max(top, sheet.positions[3 * v + 1])
    assert_almost_equal(top, 0.3, atol=1e-6)
    # Fewer than three sides are three.
    var thin = Sheet(1)
    prism(thin, Vector3(0, 0, 0), 0.1, 0.1, 0.1, 1, Vector3(1, 1, 1))
    assert_equal(thin.triangles(), 9)
    # Each side faces out, and the lid faces up.
    for t in range(sheet.triangles()):
        var a = sheet.index[3 * t]
        var n = Vector3(
            sheet.normals[3 * a],
            sheet.normals[3 * a + 1],
            sheet.normals[3 * a + 2],
        )
        var p = Vector3(sheet.positions[3 * a], 0, sheet.positions[3 * a + 2])
        assert_true(n.y > 0.5 or n.dot(p) > 0)


def test_a_rug_has_a_border_a_line_a_field_and_a_medallion() raises:
    var sheet = Sheet(1)
    rug(sheet, -1, 1, -0.6, 0.6, 2, 0)
    # Its cells and two fringes.
    assert_equal(sheet.triangles(), 2 * (RUG_CELLS * RUG_ROWS + 2))
    # It lies on the floor, facing up.
    assert_almost_equal(sheet.positions[1], 2 + RUG_LIFT, atol=1e-6)
    assert_almost_equal(sheet.normals[1], 1, atol=1e-6)
    # Four colors: the border, the cream line and heart, the field, and
    # the medallion.
    var colors = List[Vector3]()
    for v in range(0, len(sheet.colors) // 3, 4):
        var c = Vector3(
            sheet.colors[3 * v],
            sheet.colors[3 * v + 1],
            sheet.colors[3 * v + 2],
        )
        var known = False
        for seen in colors:
            if _close(seen, c):
                known = True
        if not known:
            colors.append(c)
    assert_equal(len(colors), 4)
    # The first cell is the border, and the middle cell is cream.
    assert_true(_close(colors[0], dye(1) * 0.8))
    var middle = 4 * ((RUG_ROWS // 2) * RUG_CELLS + RUG_CELLS // 2)
    assert_almost_equal(sheet.colors[3 * middle], 0.82, atol=1e-6)


def test_a_quilt_is_patched_and_faces_up() raises:
    var sheet = Sheet(1)
    patchwork(
        sheet,
        Vector3(0, 0.5, 0),
        Vector3(1, 0, 0),
        Vector3(0, 0, -1),
        0.7,
        0.9,
        3,
    )
    assert_equal(sheet.triangles(), 2 * PATCHES_ALONG * PATCHES_DOWN)
    for v in range(len(sheet.normals) // 3):
        assert_almost_equal(sheet.normals[3 * v + 1], 1, atol=1e-6)


def _has_flame(sheet: Sheet) -> Bool:
    """Return whether a sheet has a vertex of the flame's color."""
    for v in range(len(sheet.colors) // 3):
        var c = Vector3(
            sheet.colors[3 * v],
            sheet.colors[3 * v + 1],
            sheet.colors[3 * v + 2],
        )
        if _close(c, FLAME):
            return True
    return False


def test_a_table_is_laid_with_a_candle() raises:
    var pottery = Sheet(1)
    var flame = Sheet(1)
    var top = Vector3(0, 0.75, 0)
    var at = table_setting(
        pottery,
        flame,
        top,
        Vector3(1, 0, 0),
        Vector3(0, 0, -1),
        0.8,
        0.45,
        2,
    )
    # The candle's flame burns over the table, near its middle.
    assert_true(at.y > top.y + 0.1)
    assert_true(abs(at.x) < 0.2)
    assert_true(_has_flame(flame))
    # Two places a side on a table 1.6 meters long: four plates and mugs.
    var small = Sheet(1)
    _ = table_setting(
        small,
        flame,
        top,
        Vector3(1, 0, 0),
        Vector3(0, 0, -1),
        0.3,
        0.3,
        2,
    )
    assert_true(pottery.triangles() > small.triangles())


def test_shelves_hold_jars_and_a_desk_books() raises:
    var pottery = Sheet(1)
    jars(pottery, Vector3(0, 1, 0), Vector3(1, 0, 0), 0.5, 0.3, 4)
    # Three jars of eight sides, each with a lid.
    assert_equal(pottery.triangles(), 3 * 24)
    var bound = Sheet(1)
    var flame = Sheet(1)
    var at = books(
        bound,
        flame,
        Vector3(0, 0.75, 0),
        Vector3(1, 0, 0),
        Vector3(0, 0, -1),
        1,
    )
    assert_true(at.y > 0.85)
    assert_true(_has_flame(flame))
    assert_true(bound.triangles() > 4 * 12)


def test_a_lantern_hangs_and_herbs_dry() raises:
    var iron = Sheet(1)
    var glass = Sheet(1)
    var at = lantern(iron, glass, Vector3(0, 2.6, 0), 0.75)
    # The flame is below the ceiling by most of the drop.
    assert_true(at.y < 2.6 - 0.5)
    assert_true(at.y > 2.6 - 0.75)
    assert_true(iron.triangles() > 0)
    assert_true(glass.triangles() > 0)
    var wood = Sheet(1)
    herbs(wood, Vector3(0, 2.3, 0), Vector3(1.2, 2.3, 0), 3)
    # A pole, and five bundles on strings.
    assert_equal(wood.triangles(), 12 + 5 * (12 + 18))
    # Every bundle hangs below the pole.
    for v in range(len(wood.positions) // 3):
        assert_true(wood.positions[3 * v + 1] <= 2.33)
    # A pole too short for two bundles still has one.
    var short = Sheet(1)
    herbs(short, Vector3(0, 2.3, 0), Vector3(0, 2.3, 0), 3)
    assert_equal(short.triangles(), 12 + 30)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
