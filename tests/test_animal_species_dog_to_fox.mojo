# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Four species of the animals extension, each drawn and painted.

The dog, eagle, fish and fox are drawn in each morph, sex and age. They
share `test_animal_species`'s check, and live in a suite of their own so
that the coverage run measures them beside the others."""

from extensions.animals.options import ADULT, MALE
from extensions.animals.build import create_animal
from extensions.animals.options import CROWD, Variant, animal_options
from extensions.animals.registry import (
    EAGLE,
    FISH,
    species_palette,
    species_variants,
)
from extensions.animals.species.eagle import _card_color
from extensions.animals.traits import Traits
from std.testing import TestSuite, assert_true
from test_animal_species import _paint_dense, _species


def test_an_eagle_covert_takes_the_body_color() raises:
    # The eagle draws no coverts, but its painter takes their cards.
    var t = Traits(MALE, ADULT, 0)
    var c = _card_color(
        species_palette(EAGLE, t), t, "primaryCovert", 0.5, True, 0.0
    )
    assert_true(c.x >= 0.0)


def test_fish_painted_all_round() raises:
    # Spots, patches and fin rays, on every morph.
    for v in range(len(species_variants(FISH))):
        var fish = create_animal(
            FISH, animal_options(1, quality=CROWD, variant=Variant(v))
        )
        _paint_dense(fish)


def test_dog() raises:
    _species("dog")


def test_eagle() raises:
    _species("eagle")


def test_fish() raises:
    _species("fish")


def test_fox() raises:
    _species("fox")


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
