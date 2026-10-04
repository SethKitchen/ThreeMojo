# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""The sheep of the animals extension, drawn and painted.

A wooled sheep carries a thousand locks, so it is slow to build: it has a
suite of its own, and it is drawn as a few chosen individuals rather than
a sweep. They share `test_animal_species`'s check."""

from extensions.animals.build import create_animal
from extensions.animals.options import (
    ADULT,
    CROWD,
    FEMALE,
    JUVENILE,
    MALE,
    Variant,
    animal_options,
)
from extensions.animals.registry import SHEEP
from extensions.animals.species.sheep import _horn_t, _locks
from extensions.animals.traits import Traits
from extensions.sdf.field import SdfModel
from extensions.sdf.ids import BoneId
from extensions.sdf.vector import V3
from std.testing import TestSuite, assert_true
from test_animal_species import _check, _paint_all, _paint_dense, _species

# The morphs, in `sheep_variant_names` order.
comptime MERINO = 2
comptime SHORN = 4


def test_sheep() raises:
    _species("sheep", 1)


def test_rams_grow_horns_and_shorn_sheep_no_locks() raises:
    # A merino ram is horned nineteen times in twenty, and a merino ram
    # lamb grows horn buds as often. A shorn sheep's fleece is too short
    # for locks.
    var horned = 0
    for age in [ADULT, JUVENILE]:
        var ram = create_animal(
            SHEEP,
            animal_options(
                3, quality=CROWD, sex=MALE, age=age, variant=Variant(MERINO)
            ),
        )
        horned += Int(ram.traits.get("hornTurns") > 0.0)
        _check(ram)
        _paint_all(ram)
    assert_true(horned == 2)
    var shorn = create_animal(
        SHEEP, animal_options(3, quality=CROWD, variant=Variant(SHORN))
    )
    assert_true(shorn.traits.get("fleece") < 0.016)
    _check(shorn)
    _paint_all(shorn)
    _paint_dense(shorn)


def test_a_polled_ewe_has_no_horn_to_measure() raises:
    assert_true(_horn_t(Traits(FEMALE, ADULT, 0), V3(0.02, 0.5, 0.1)) == 0.0)


def test_wool_too_low_to_lock_grows_none() raises:
    # Locks grow only above 10 cm: a fleece lying below that keeps none.
    var m = SdfModel()
    _ = m.ell("fleece", BoneId(0), V3(0, 0.03, 0), V3(0.1, 0.02, 0.1))
    var count = len(m.prims)
    var fleece: List[Int] = [0]
    var groups: List[Bool] = [False]
    _locks(m, Traits(MALE, ADULT, 0), fleece, groups, 0.03, False)
    assert_true(len(m.prims) == count)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
