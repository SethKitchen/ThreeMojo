# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Distance maps and contact maps of residues."""

from extensions.chemistry.quantities import ANGSTROM
from extensions.molecule.contacts import DistanceMap, distance_map, map_image
from extensions.molecule.ids import (
    ALL_LOCATIONS,
    HELIX,
    ModelId,
    STRAND,
    SecondaryKind,
)
from extensions.molecule.peptide import build_peptide
from extensions.molecule.structure import parse_pdb_structure
from std.math import inf
from std.testing import (
    TestSuite,
    assert_almost_equal,
    assert_equal,
    assert_raises,
    assert_true,
)
from units.si import Length64, METER


def _a(value: Float64) -> Length64:
    return Length64(value, ANGSTROM)


def _kinds(kind: SecondaryKind, count: Int) -> List[SecondaryKind]:
    var out = List[SecondaryKind]()
    for _ in range(count):
        out.append(kind)
    return out^


def test_helix_contacts() raises:
    var helix = build_peptide("AAAAAAAAAAAAAA", _kinds(HELIX, 14))
    var map = distance_map(helix, ModelId(0), "CA")
    assert_equal(map.count(), 14)
    var angstrom = _a(1).to(METER)
    for i in range(13):
        # Neighbor CA atoms are 3.8 angstroms apart in a trans peptide.
        var step = map.distance(i, i + 1).to(METER) / angstrom
        assert_true(step > 3.75 and step < 3.85)
        assert_equal(map.distance(i, i).to(METER), 0)
        assert_equal(
            map.distance(i, i + 1).to(METER), map.distance(i + 1, i).to(METER)
        )
    # An alpha helix brings i + 3 and i + 4 within 8 angstroms, and not
    # i + 5, which is about 8.6 angstroms away.
    var contacts = map.contacts(_a(8), 3)
    assert_equal(len(contacts), 11 + 10)
    for pair in contacts:
        var gap = pair[1] - pair[0]
        assert_true(gap == 3 or gap == 4)
    assert_equal(len(map.contacts(_a(8), 6)), 0)


def test_a_strand_has_no_contacts() raises:
    var strand = build_peptide("VVVVVVVVVV", _kinds(STRAND, 10))
    var map = distance_map(strand, ModelId(0), "CA")
    assert_equal(len(map.contacts(_a(8), 3)), 0)
    # Every second CA of a strand is more than 6 angstroms away.
    assert_true(map.distance(0, 2).to(METER) > _a(6).to(METER))


comptime TWO_CHAINS = (
    "ATOM      1  CA  ALA A   1       0.000   0.000   0.000  1.00 10.00   "
    "        C\n"
    "ATOM      2  CA  ALA A   2       3.800   0.000   0.000  1.00 10.00   "
    "        C\n"
    "ATOM      3  CA  ALA B   1       0.000   5.000   0.000  1.00 10.00   "
    "        C\n"
    "HETATM    4  O   HOH W   1       0.000   0.000   9.000  1.00 10.00   "
    "        O\n"
)


def test_chains_and_missing_atoms() raises:
    var s = parse_pdb_structure(String(TWO_CHAINS), ALL_LOCATIONS)
    var map = distance_map(s, ModelId(0), "CA")
    # The water has no CA, so it has no row.
    assert_equal(map.count(), 3)
    assert_almost_equal(map.distance(0, 2).to(METER), _a(5).to(METER))
    # Residues of two chains are always far enough apart in sequence.
    var contacts = map.contacts(_a(8), 6)
    assert_equal(len(contacts), 2)
    assert_equal(contacts[0][0], 0)
    assert_equal(contacts[0][1], 2)
    assert_equal(contacts[1][0], 1)
    with assert_raises(contains="atom named CB"):
        _ = distance_map(s, ModelId(0), "CB")
    with assert_raises(contains="model"):
        _ = distance_map(s, ModelId(2), "CA")
    with assert_raises(contains="outside the map"):
        _ = map.distance(3, 0)
    with assert_raises(contains="outside the map"):
        _ = map.distance(0, -1)
    with assert_raises(contains="outside the map"):
        _ = map.distance(-1, 0)
    with assert_raises(contains="outside the map"):
        _ = map.distance(0, 3)
    with assert_raises(contains="cutoff"):
        _ = map.contacts(_a(0), 6)
    with assert_raises(contains="cutoff"):
        _ = map.contacts(Length64(inf[DType.float64](), METER), 6)
    with assert_raises(contains="separation"):
        _ = map.contacts(_a(8), 0)
    assert_equal(len(DistanceMap().contacts(_a(8), 1)), 0)


def test_map_image() raises:
    var helix = build_peptide("AAAAAAAA", _kinds(HELIX, 8))
    var map = distance_map(helix, ModelId(0), "CA")
    var image = map_image(map, _a(20))
    assert_equal(image.width, 8)
    assert_equal(image.height, 8)
    # The diagonal is dark blue, and far pairs are lighter.
    var diagonal = image.get_pixel(3, 3)
    assert_equal(diagonal.r, 20)
    assert_equal(diagonal.b, 110)
    assert_true(image.get_pixel(7, 0).b > image.get_pixel(1, 0).b)
    var white = map_image(map, _a(1)).get_pixel(7, 0)
    assert_equal(white.g, 255)
    with assert_raises(contains="far distance"):
        _ = map_image(map, _a(0))
    with assert_raises(contains="far distance"):
        _ = map_image(map, Length64(inf[DType.float64](), METER))
    with assert_raises(contains="empty"):
        _ = map_image(DistanceMap(), _a(20))


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
