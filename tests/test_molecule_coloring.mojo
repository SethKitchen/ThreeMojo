# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Molecular surfaces colored by a property of the nearest atom."""

from core.buffer_attribute import BufferAttribute
from core.buffer_geometry import COLOR, POSITION, BufferGeometry
from extensions.molecule.coloring import (
    atom_color,
    color_surface,
    kyte_doolittle,
)
from extensions.molecule.ids import (
    ALL_LOCATIONS,
    COLOR_BY_B_FACTOR,
    COLOR_BY_CHAIN,
    COLOR_BY_ELEMENT,
    COLOR_BY_HYDROPATHY,
    ModelId,
    SurfaceColoring,
    require_surface_coloring,
)
from extensions.molecule.ribbon import chain_color
from extensions.molecule.structure import Structure, parse_pdb_structure
from extensions.molecule.surface import excluded_surface
from extensions.chemistry.quantities import ANGSTROM
from render.srgb import srgb_to_linear
from std.testing import (
    TestSuite,
    assert_almost_equal,
    assert_equal,
    assert_false,
    assert_raises,
    assert_true,
)
from units.si import Length64

comptime THREE_ATOMS = (
    "ATOM      1  C   ILE A   1       0.000   0.000   0.000  1.00 10.00   "
    "        C\n"
    "ATOM      2  N   ARG B   1      10.000   0.000   0.000  1.00 30.00   "
    "        N\n"
    "HETATM    3  O   HOH C   1       0.000  10.000   0.000  1.00 20.00   "
    "        O\n"
    "END\n"
)


def _three() raises -> Structure:
    return parse_pdb_structure(String(THREE_ATOMS), ALL_LOCATIONS)


def test_kyte_doolittle() raises:
    assert_equal(kyte_doolittle("ILE")[1], 4.5)
    assert_equal(kyte_doolittle("ARG")[1], -4.5)
    assert_equal(kyte_doolittle("GLY")[1], -0.4)
    assert_true(kyte_doolittle("TRP")[0])
    assert_false(kyte_doolittle("HOH")[0])
    assert_equal(kyte_doolittle("HOH")[1], 0)


def test_atom_colors() raises:
    var s = _three()
    var model = ModelId(0)
    # Carbon is CPK gray, about 144/255.
    var carbon = atom_color(s, model, 0, COLOR_BY_ELEMENT)
    assert_almost_equal(carbon.x, 144.0 / 255.0, atol=1e-9)
    # The least B-factor is blue, the middle white, the largest red.
    var low = atom_color(s, model, 0, COLOR_BY_B_FACTOR)
    var middle = atom_color(s, model, 2, COLOR_BY_B_FACTOR)
    var high = atom_color(s, model, 1, COLOR_BY_B_FACTOR)
    assert_true(low.z > low.x)
    assert_almost_equal(middle.x, 0.96)
    assert_almost_equal(middle.z, 0.96)
    assert_true(high.x > high.z)
    # Chains take the ribbon palette, from the model's first chain.
    var second = atom_color(s, model, 1, COLOR_BY_CHAIN)
    assert_equal(second.x, chain_color(1).x)
    # Isoleucine is orange, arginine blue, and water gray.
    var oily = atom_color(s, model, 0, COLOR_BY_HYDROPATHY)
    var charged = atom_color(s, model, 1, COLOR_BY_HYDROPATHY)
    var water = atom_color(s, model, 2, COLOR_BY_HYDROPATHY)
    assert_almost_equal(oily.x, 0.95)
    assert_almost_equal(charged.z, 0.85)
    assert_almost_equal(water.x, 0.78)
    assert_equal(water.x, water.z)
    with assert_raises(contains="not in the model"):
        _ = atom_color(s, model, 3, COLOR_BY_ELEMENT)
    with assert_raises(contains="not in the model"):
        _ = atom_color(s, model, -1, COLOR_BY_ELEMENT)
    with assert_raises(contains="surface coloring"):
        _ = atom_color(s, model, 0, SurfaceColoring(4))


def test_unknown_element_and_one_b_factor() raises:
    var text = String(
        "ATOM      1  X   ALA A   1       0.000   0.000   0.000  1.00  5.00   "
        "        XX\n"
    )
    var s = parse_pdb_structure(text, ALL_LOCATIONS)
    var gray = atom_color(s, ModelId(0), 0, COLOR_BY_ELEMENT)
    assert_almost_equal(gray.y, 0.78)
    # One B-factor in the model: white.
    var flat = atom_color(s, ModelId(0), 0, COLOR_BY_B_FACTOR)
    assert_almost_equal(flat.y, 0.96)


def _points(values: List[Float32]) raises -> BufferGeometry:
    var geometry = BufferGeometry()
    geometry.set_attribute(POSITION, BufferAttribute(values.copy(), 3))
    return geometry^


def test_color_surface_takes_the_nearest_sphere() raises:
    var s = _three()
    var a = Float32(Length64(1.0, ANGSTROM).value)
    # Near the carbon, near the nitrogen, and far from every atom.
    var geometry = _points([1.5 * a, 0, 0, 8.6 * a, 0, 0, 200 * a, 200 * a, 0])
    color_surface(geometry, s, ModelId(0), COLOR_BY_CHAIN)
    ref colors = geometry.attribute_view(COLOR)
    assert_equal(colors.count(), 3)
    var first = chain_color(0)
    var second = chain_color(1)
    assert_almost_equal(
        colors.component(0, 0), srgb_to_linear(Float32(first.x)), atol=1e-6
    )
    assert_almost_equal(
        colors.component(1, 0), srgb_to_linear(Float32(second.x)), atol=1e-6
    )
    # No atom is in the cells around the far point, so every atom is
    # searched. The nitrogen and the oxygen are equally far, and the
    # nitrogen's sphere is the larger, so it is the nearest sphere.
    assert_almost_equal(
        colors.component(2, 0), srgb_to_linear(Float32(second.x)), atol=1e-6
    )
    # A mesh without vertices gets an empty color attribute.
    var empty = _points(List[Float32]())
    color_surface(empty, s, ModelId(0), COLOR_BY_ELEMENT)
    assert_equal(empty.attribute_view(COLOR).count(), 0)
    with assert_raises(contains="surface coloring"):
        color_surface(geometry, s, ModelId(0), SurfaceColoring(7))
    var no_points = BufferGeometry()
    with assert_raises(contains="position"):
        color_surface(no_points, s, ModelId(0), COLOR_BY_ELEMENT)


def test_color_a_real_surface() raises:
    var s = _three()
    var surface = excluded_surface(
        s,
        ModelId(0),
        Length64(1.4, ANGSTROM),
        Length64(0.5, ANGSTROM),
    )
    color_surface(surface, s, ModelId(0), COLOR_BY_HYDROPATHY)
    ref colors = surface.attribute_view(COLOR)
    var orange = 0
    var blue = 0
    for v in range(colors.count()):
        if colors.component(v, 0) > colors.component(v, 2) + 0.3:
            orange += 1
        if colors.component(v, 2) > colors.component(v, 0) + 0.3:
            blue += 1
    # Each of the two residues colors its own sphere.
    assert_true(orange > 0)
    assert_true(blue > 0)


def test_require() raises:
    require_surface_coloring(COLOR_BY_HYDROPATHY)
    with assert_raises(contains="from 0 to 3"):
        require_surface_coloring(SurfaceColoring(-1))


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
