# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Tests for `extensions.building.kits`, the reusable construction kits.

Each kit must pass `assemble`'s own checks, keep the construction set's
order, and be refused when it is changed into one that `assemble` would
refuse.
"""

from extensions.building.construction import Construction, Layer
from extensions.building.ids import MaterialId
from extensions.building.kinds import LIVING
from extensions.building.kits import (
    CONCRETE_KIT,
    MASONRY_KIT,
    STONE_KIT,
    TIMBER_KIT,
    KitKind,
    construction_kit,
    kit_kind,
    stone_masonry,
)
from extensions.building.model import Site, SpacePlan, StoreyPlan, assemble
from extensions.topology.arrangement import Point2
from std.testing import (
    TestSuite,
    assert_almost_equal,
    assert_equal,
    assert_false,
    assert_raises,
    assert_true,
)
from units.si import (
    Angle64,
    DEGREE64,
    GIGAPASCAL,
    KILOGRAM_PER_CUBIC_METER,
    Length64,
    MEGAPASCAL,
    METER,
)


def test_the_kits_have_names() raises:
    """Each kit reads back from its name, and no other name is one."""
    var names: List[String] = ["masonry", "stone", "concrete", "timber"]
    for value in range(4):
        assert_equal(KitKind(value).name(), names[value])
        assert_true(kit_kind(names[value]) == KitKind(value))
    assert_equal(KitKind(4).name(), "unknown")
    assert_false(KitKind(-1).is_valid())
    with assert_raises(contains="'adobe' is not a construction kit"):
        _ = kit_kind("adobe")


def test_stone_masonry_is_heavy_and_weak() raises:
    """Historic masonry: dense, and far weaker than the stone in it."""
    var stone = stone_masonry()
    stone.check()
    assert_almost_equal(stone.density.to(KILOGRAM_PER_CUBIC_METER), 2200)
    assert_almost_equal(stone.strength.to(MEGAPASCAL), 3)
    assert_almost_equal(stone.elastic_modulus.to(GIGAPASCAL), 3)


def test_every_kit_has_five_valid_constructions() raises:
    """The walls are thickest in stone and thinnest in timber."""
    var walls = List[Float64]()
    for kind in [MASONRY_KIT, STONE_KIT, CONCRETE_KIT, TIMBER_KIT]:
        var kit = construction_kit(kind)
        assert_true(kit.kind == kind)
        assert_equal(len(kit.constructions), 5)
        assert_equal(kit.defaults.exterior_wall.value, 0)
        assert_equal(kit.defaults.roof.value, 4)
        walls.append(kit.constructions[0].thickness().to(METER))
    assert_almost_equal(walls[0], 0.38)
    assert_almost_equal(walls[1], 1.2)
    assert_almost_equal(walls[2], 0.3325)
    assert_almost_equal(walls[3], 0.1745)


def test_a_kit_that_assemble_would_refuse_is_refused() raises:
    """A kind, a count, a material or a layer that is wrong."""
    with assert_raises(contains="a kit kind is 0 to 3"):
        _ = construction_kit(KitKind(9))
    var kit = construction_kit(MASONRY_KIT)
    kit.kind = KitKind(-1)
    with assert_raises(contains="a kit kind is 0 to 3"):
        kit.check()
    kit = construction_kit(MASONRY_KIT)
    _ = kit.constructions.pop()
    with assert_raises(contains="a kit has five constructions"):
        kit.check()
    kit = construction_kit(MASONRY_KIT)
    kit.materials[0].poisson_ratio = 0.7
    with assert_raises(contains="Poisson's ratio"):
        kit.check()
    kit = construction_kit(MASONRY_KIT)
    kit.materials.clear()
    with assert_raises(contains="material id is out of range"):
        kit.check()
    kit = construction_kit(MASONRY_KIT)
    kit.constructions[1] = Construction(
        "loose", [Layer(MaterialId(12), Length64(0.1, METER))]
    )
    with assert_raises(contains="material id is out of range"):
        kit.check()


def test_a_kit_assembles_a_building() raises:
    """A kit's lists and set go straight to `assemble`."""
    var kit = construction_kit(STONE_KIT)
    var outline: List[Point2] = [
        Point2(0, 0),
        Point2(6, 0),
        Point2(6, 8),
        Point2(0, 8),
    ]
    var spaces = List[SpacePlan]()
    spaces.append(SpacePlan("nave", LIVING, outline^))
    var plans = List[StoreyPlan]()
    plans.append(StoreyPlan("ground", Length64(9, METER), spaces^))
    var building = assemble(
        "chapel",
        Site(
            Angle64(51.1, DEGREE64),
            Angle64(17.0, DEGREE64),
            Length64(120, METER),
            Angle64(0, DEGREE64),
        ),
        Length64(0, METER),
        plans,
        kit.materials.copy(),
        kit.constructions.copy(),
        kit.defaults,
        Length64(1e-6, METER),
    )
    building.validate()
    assert_equal(building.constructions[0].name, "stone wall")


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
