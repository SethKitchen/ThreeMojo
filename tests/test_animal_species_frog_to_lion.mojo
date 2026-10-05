# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Four species of the animals extension, each drawn and painted.

The frog, goat, horse and lion are drawn in each morph, sex and age. They
share `test_animal_species`'s check, and live in a suite of their own so
that the coverage run measures them beside the others."""

from extensions.animals.coat import KERATIN, CoatSample
from extensions.animals.kit import eye_frame_of
from extensions.animals.options import ADULT, FEMALE, JUVENILE, MALE
from extensions.animals.parts import LIMB
from extensions.animals.registry import HORSE, species_palette
from extensions.animals.species.horse import _paint_body
from extensions.animals.species.lion import HEAD_O, _paint_face, lion_eye
from extensions.animals.build import create_animal
from extensions.animals.options import CROWD, Variant, animal_options
from extensions.animals.registry import FROG, species_variants
from extensions.animals.species.goat import _horn_t, _skin
from extensions.sdf.field import SdfModel
from extensions.sdf.ids import BoneId
from extensions.animals.traits import Traits
from extensions.sdf.vector import V3
from std.testing import TestSuite, assert_true
from test_animal_species import _paint_dense, _species


def test_a_polled_goat_has_no_horn_to_measure() raises:
    var t = Traits(FEMALE, ADULT, 0)
    assert_true(_horn_t(t, V3(0.02, 0.5, 0.1)) == 0.0)


def test_horse_chestnuts_and_a_cub_eye_ring() raises:
    # The chestnut: a horny callosity inside the forearm, above the knee.
    var mare = Traits(FEMALE, ADULT, 0)
    var s = CoatSample(
        V3(0.1, 0.62, 0.63), V3(-1, 0, 0), V3(0, 0, 0), 0, 0, LIMB
    )
    var nut = _paint_body(
        species_palette(HORSE, mare), mare, "leg", "radiusL", s, False, 0.0
    )
    assert_true(nut.surface == KERATIN)
    # A cub's eyes are ringed; its painter is asked about the lids.
    var cub = Traits(MALE, JUVENILE, 0)
    var colors = List[V3](length=40, fill=V3(0.5, 0.4, 0.3))
    var e = lion_eye(cub)
    var ef = eye_frame_of(e, HEAD_O, 1.0)
    for i in range(-6, 7):
        for j in range(-6, 7):
            var p = ef.at(
                e.big_r * 0.25 * Float64(i), e.big_r * 0.25 * Float64(j), 0.0
            )
            var paint = _paint_face(
                colors, cub, "head", "head", p, ef.z, True, 1.0, False
            )
            assert_true(paint.surface.is_valid())


def test_frogs_painted_all_round() raises:
    # Bands, their gaps and the mottle under them, inside and outside
    # each limb, on every morph.
    for v in range(len(species_variants(FROG))):
        for seed in range(1, 3):
            var frog = create_animal(
                FROG, animal_options(seed, quality=CROWD, variant=Variant(v))
            )
            _paint_dense(frog)


def test_skin_march_stops_deep_inside() raises:
    # From deep inside a big ball the march gives up after 25 cm.
    var m = SdfModel()
    _ = m.sphere("ball", BoneId(0), V3(0, 0, 0), 1.0, k=0.0)
    var q = _skin(m, [0], V3(0, 0, 0), V3(0, 0, 1))
    assert_true(abs(q.z - (0.25 - 0.012)) < 0.003)


def test_frog() raises:
    _species("frog")


def test_goat() raises:
    _species("goat")


def test_horse() raises:
    _species("horse")


def test_lion() raises:
    _species("lion")


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
