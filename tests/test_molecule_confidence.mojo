# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""The pLDDT confidence of a predicted structure, summed and colored."""

from core.buffer_geometry import COLOR
from extensions.molecule.coloring import atom_color
from extensions.molecule.confidence import confidence_color, confidence_summary
from extensions.molecule.ids import (
    BY_CONFIDENCE,
    COLOR_BY_CONFIDENCE,
    HELIX,
    ModelId,
    ResidueId,
    SecondaryKind,
)
from extensions.molecule.peptide import build_peptide
from extensions.molecule.ribbon import ribbon_geometry
from extensions.molecule.structure import SQUARE_ANGSTROM, Structure
from render.srgb import srgb_to_linear
from std.math import nan
from std.testing import (
    TestSuite,
    assert_almost_equal,
    assert_equal,
    assert_raises,
    assert_true,
)
from units.si import Area64

# The four colors of the AlphaFold Protein Structure Database.
comptime VERY_HIGH = (0, 83, 214)
comptime CONFIDENT = (101, 203, 243)
comptime LOW = (255, 219, 19)
comptime VERY_LOW = (255, 125, 69)


def _same(
    color: Tuple[Float64, Float64, Float64], rgb: Tuple[Int, Int, Int]
) raises:
    assert_almost_equal(color[0], Float64(rgb[0]) / 255.0, atol=1e-12)
    assert_almost_equal(color[1], Float64(rgb[1]) / 255.0, atol=1e-12)
    assert_almost_equal(color[2], Float64(rgb[2]) / 255.0, atol=1e-12)


def _rgb(plddt: Float64) -> Tuple[Float64, Float64, Float64]:
    var c = confidence_color(plddt)
    return (c.x, c.y, c.z)


def test_bands() raises:
    _same(_rgb(100), VERY_HIGH)
    _same(_rgb(90.01), VERY_HIGH)
    _same(_rgb(90), CONFIDENT)
    _same(_rgb(70.5), CONFIDENT)
    _same(_rgb(70), LOW)
    _same(_rgb(50.5), LOW)
    _same(_rgb(50), VERY_LOW)
    _same(_rgb(0), VERY_LOW)


def _predicted(values: List[Float64]) raises -> Structure:
    """Return a helix whose residues carry these pLDDT values."""
    var kinds = List[SecondaryKind]()
    for _ in range(len(values)):
        kinds.append(HELIX)
    var s = build_peptide(
        String(String("MAEKLAGKVL")[byte = 0 : len(values)]), kinds
    )
    for r in range(len(values)):
        var first = s.residues[r].first_atom
        for a in range(first, first + s.residues[r].atom_count):
            s.atoms[a].b_factor = Area64(values[r], SQUARE_ANGSTROM)
    return s^


def test_summary() raises:
    var values: List[Float64] = [95, 91, 90, 75, 70, 55, 50, 10]
    var s = _predicted(values)
    var summary = confidence_summary(s, ModelId(0))
    assert_equal(summary.residues, 8)
    assert_equal(summary.very_high, 2)
    assert_equal(summary.confident, 2)
    assert_equal(summary.low, 2)
    assert_equal(summary.very_low, 2)
    assert_almost_equal(summary.mean, 536.0 / 8.0)
    # A residue without a CA does not count.
    var ca = s.find_atom(ResidueId(0), "CA").value
    s.atoms[ca].name = "CX"
    var fewer = confidence_summary(s, ModelId(0))
    assert_equal(fewer.residues, 7)
    assert_equal(fewer.very_high, 1)
    assert_almost_equal(fewer.mean, 441.0 / 7.0)


def test_surface_and_ribbon_colors() raises:
    var values: List[Float64] = [95, 80, 60, 30]
    var s = _predicted(values)
    for r in range(4):
        var ca = s.find_atom(ResidueId(r), "CA").value
        var color = atom_color(s, ModelId(0), ca, COLOR_BY_CONFIDENCE)
        var bands = [VERY_HIGH, CONFIDENT, LOW, VERY_LOW]
        _same((color.x, color.y, color.z), bands[r])
    # The ribbon's first ring takes residue 0, and its last residue 3.
    var ribbon = ribbon_geometry(s, ModelId(0), BY_CONFIDENCE, 4, 6)
    ref colors = ribbon.attribute_view(COLOR)
    var count = colors.count()
    assert_almost_equal(
        colors.component(0, 2),
        srgb_to_linear(Float32(214.0 / 255.0)),
        atol=1e-6,
    )
    assert_almost_equal(colors.component(0, 0), 0.0, atol=1e-6)
    assert_almost_equal(colors.component(count - 1, 0), 1.0, atol=1e-6)
    assert_almost_equal(
        colors.component(count - 1, 1),
        srgb_to_linear(Float32(125.0 / 255.0)),
        atol=1e-6,
    )
    # Every ring holds one of the four band colors.
    var linear = List[Float32]()
    for band in [VERY_HIGH, CONFIDENT, LOW, VERY_LOW]:
        linear.append(srgb_to_linear(Float32(Float64(band[1]) / 255.0)))
    for v in range(count):
        var g = colors.component(v, 1)
        var known = False
        for value in linear:
            if abs(g - value) < 1e-6:
                known = True
        assert_true(known)


def test_refusals() raises:
    var s = _predicted([80, 85])
    with assert_raises(contains="model"):
        _ = confidence_summary(s, ModelId(3))
    for bad in [101.0, -1.0, nan[DType.float64]()]:
        var t = _predicted([80, bad])
        with assert_raises(contains="0 to 100"):
            _ = confidence_summary(t, ModelId(0))
    for a in range(len(s.atoms)):
        if s.atoms[a].name == "CA":
            s.atoms[a].name = "CX"
    with assert_raises(contains="no CA"):
        _ = confidence_summary(s, ModelId(0))


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
