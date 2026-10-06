# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Four species of the animals extension, each drawn and painted.

The pig, rabbit, rat and shark are drawn in each morph, sex and age. They
share `test_animal_species`'s check, and live in a suite of their own so
that the coverage run measures them beside the others."""

from extensions.animals.coat import Palette
from extensions.animals.options import (
    ADULT,
    FEMALE,
    Variant,
    animal_options,
    body_random,
)
from extensions.animals.species.pig import SPOTTED, _markings
from extensions.animals.traits import Traits
from extensions.sdf.vector import V3
from extensions.animals.registry import SHARK, species_traits
from extensions.animals.species.shark import _geo, _lerp_table, _scars
from std.testing import TestSuite, assert_almost_equal, assert_true
from test_animal_species import _species


def test_shark_tables_and_scars() raises:
    # Past its last row a table keeps the last value; one row is flat.
    var tbl: List[Float64] = [0.0, 1.0, 1.0, 2.0]
    assert_almost_equal(_lerp_table(tbl, 5.0), 2.0)
    var one: List[Float64] = [0.0, 3.0]
    assert_almost_equal(_lerp_table(one, 0.5), 3.0)
    # A blacktip scars now and then, never with a white's tooth rake.
    var r = body_random(1)
    var t = species_traits(SHARK, r, animal_options(1, variant=Variant(1)))
    var scarred = 0
    for k in range(200):
        t.set("coatSeed", Float64(k))
        scarred += Int(len(_scars(_geo(t), t)) > 0)
    assert_true(scarred > 0)


def test_a_spotted_pig_with_no_spots_keeps_its_color() raises:
    # Every spot can be crowded out; the painter then leaves the coat.
    var t = Traits(FEMALE, ADULT, SPOTTED)
    var pal = Palette()
    pal.set("spots", V3(0, 0, 0))
    var c = V3(0.8, 0.6, 0.5)
    var o = V3(0, 0, 0)
    var out = _markings(
        pal, t, 0, "body", "spine1", 0.0, o, V3(0, 0.6, 0), c, o
    )
    assert_true(out.x == c.x and out.y == c.y and out.z == c.z)


def test_pig() raises:
    _species("pig")


def test_rabbit() raises:
    _species("rabbit")


def test_rat() raises:
    _species("rat")


def test_shark() raises:
    _species("shark")


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
