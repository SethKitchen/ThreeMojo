# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Three species of the animals extension, each drawn and painted.

The snake, spider and wolf are drawn in each morph, sex and age. They share
`test_animal_species`'s check, and live in a suite of their own so that the
coverage run measures them beside the others."""

from extensions.animals.build import create_animal
from extensions.animals.options import MEDIUM, Variant, animal_options
from extensions.animals.registry import SNAKE
from extensions.animals.species.snake import RATTLESNAKE, _pchip_slopes
from std.testing import TestSuite, assert_true
from test_animal_species import _check, _paint_all, _species


def test_a_rattlesnake_shows_its_fangs_above_the_crowd_tier() raises:
    # The tongue and the fangs are sculpted from the medium tier up.
    var viper = create_animal(
        SNAKE, animal_options(2, quality=MEDIUM, variant=Variant(RATTLESNAKE))
    )
    _check(viper)
    _paint_all(viper)


def test_monotone_slopes_flatten_on_a_level_stretch() raises:
    # A level stretch keeps the curve level; two points have no middle.
    var x: List[Float64] = [0.0, 1.0, 2.0]
    var y: List[Float64] = [1.0, 1.0, 2.0]
    var m = _pchip_slopes(x, y)
    assert_true(m[0] == 0.0 and m[1] == 0.0)
    var x2: List[Float64] = [0.0, 1.0]
    var y2: List[Float64] = [0.0, 2.0]
    var m2 = _pchip_slopes(x2, y2)
    assert_true(m2[0] == 2.0 and m2[1] == 2.0)


def test_snake() raises:
    _species("snake")


def test_spider() raises:
    _species("spider")


def test_wolf() raises:
    _species("wolf")


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
