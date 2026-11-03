# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Tests for the CIF reader of `extensions.chemistry`.

Diamond is the face-centered translations on a basis of two carbon atoms:
eight atoms, with bonds of a sqrt(3) / 4. Graphite is space group
P6_3/mmc with all 24 operations: four atoms, with bonds of a / sqrt(3) in
a layer and layers c / 2 apart. The densities must match the handbook
values of 3.51 and 2.26 g/cm^3.
"""

from std.math import inf, nan, sqrt
from std.testing import (
    TestSuite,
    assert_almost_equal,
    assert_equal,
    assert_raises,
    assert_true,
)
from extensions.chemistry.crystal import (
    Atom,
    Crystal,
    Position,
    bonds,
    read_cif,
)
from extensions.chemistry.elements import (
    CARBON,
    CHLORINE,
    Element,
    OXYGEN,
    SODIUM,
    TITANIUM,
)
from extensions.chemistry.quantities import ANGSTROM
from units.si import (
    Angle64,
    DEGREE64,
    GRAM_PER_CUBIC_CENTIMETER,
    Length64,
)

comptime DIAMOND = """# Diamond: the F translations on a basis of two atoms.
data_diamond
_cell_length_a 3.5668(2)
_cell_length_b 3.5668
_cell_length_c 3.5668
_cell_angle_alpha 90
_cell_angle_beta  90
_cell_angle_gamma 90
loop_
_symmetry_equiv_pos_as_xyz
'x,y,z' 'x,y+1/2,z+1/2' "x+1/2,y,z+1/2" 1/2+x,1/2+y,z
loop_
_atom_site_label
_atom_site_fract_x
_atom_site_fract_y
_atom_site_fract_z
C1 0 0 0
C2 0.25 0.25 0.25
"""

comptime GRAPHITE = """data_graphite
_cell_length_a 2.464
_cell_length_b 2.464
_cell_length_c 6.711
_cell_angle_alpha 90
_cell_angle_beta 90
_cell_angle_gamma 120
_symmetry_space_group_name_H-M 'P 63/m m c'
loop_
_space_group_symop_id
_space_group_symop_operation_xyz
1 x,y,z
2 -y,x-y,z
3 -x+y,-x,z
4 -x,-y,z+1/2
5 y,-x+y,z+1/2
6 x-y,x,z+1/2
7 y,x,-z
8 x-y,-y,-z
9 -x,-x+y,-z
10 -y,-x,-z+1/2
11 -x+y,y,-z+1/2
12 x,x-y,-z+1/2
13 -x,-y,-z
14 y,-x+y,-z
15 x-y,x,-z
16 x,y,-z+1/2
17 -y,x-y,-z+1/2
18 -x+y,-x,-z+1/2
19 -y,-x,z
20 -x+y,y,z
21 x,x-y,z
22 y,x,z+1/2
23 x-y,-y,z+1/2
24 -x,-x+y,z+1/2
loop_
_atom_site_label
_atom_site_type_symbol
_atom_site_fract_x
_atom_site_fract_y
_atom_site_fract_z
_atom_site_occupancy
C1 C 0 0 0.25 1
C2 C 0.333333 0.666667 0.25 1.0
"""

# The cell and an atom at the origin, before any loop of operations.
comptime _CELL = """data_x
_cell_length_a 4
_cell_length_b 4
_cell_length_c 4
_cell_angle_alpha 90
_cell_angle_beta 90
_cell_angle_gamma 90
"""

comptime _ORIGIN = """loop_
_atom_site_label
_atom_site_fract_x
_atom_site_fract_y
_atom_site_fract_z
O1 0 0 0
"""


def _with_ops(ops: String) raises -> Crystal:
    """Return the test cell with one operation loop and an atom at 0.5."""
    var text = String(_CELL, "loop_\n_symmetry_equiv_pos_as_xyz\n", ops)
    text += "\nloop_\n_atom_site_label\n_atom_site_fract_x\n"
    text += "_atom_site_fract_y\n_atom_site_fract_z\nO1 0.5 0.25 0.125\n"
    return read_cif(text)


def _a(value: Float64) -> Length64:
    return Length64(value, ANGSTROM)


def _deg(value: Float64) -> Angle64:
    return Angle64(value, DEGREE64)


def _one() -> List[Atom]:
    return [Atom(CARBON, 0, 0, 0)]


def test_diamond() raises:
    var diamond = read_cif(DIAMOND)
    assert_equal(diamond.name, "diamond")
    assert_equal(len(diamond.atoms), 8)
    assert_almost_equal(diamond.a.to(ANGSTROM), 3.5668, atol=1e-12)
    assert_almost_equal(
        diamond.density().to(GRAM_PER_CUBIC_CENTIMETER), 3.515, atol=0.002
    )
    var cell = diamond.block(1, 1, 1)
    # 8 corners, 6 face centers and 4 atoms inside.
    assert_equal(len(cell), 18)
    var a = 3.5668
    var found = bonds(cell, _a(1.0), _a(2.0))
    assert_equal(len(found), 16)
    for bond in found:
        assert_almost_equal(
            bond.length.to(ANGSTROM), a * sqrt(3.0) / 4, atol=1e-9
        )
    # The second neighbors, a / sqrt(2) apart, lie past the bonds.
    var second = bonds(cell, _a(2.0), _a(2.6))
    assert_true(len(second) > 0)
    for bond in second:
        assert_almost_equal(bond.length.to(ANGSTROM), a / sqrt(2.0), atol=1e-9)
    assert_true(len(diamond.block(2, 1, 3)) > len(cell))


def test_graphite() raises:
    var graphite = read_cif(GRAPHITE)
    assert_equal(len(graphite.atoms), 4)
    for atom in graphite.atoms:
        assert_equal(atom.element, CARBON)
    assert_almost_equal(
        graphite.density().to(GRAM_PER_CUBIC_CENTIMETER), 2.26, atol=0.005
    )
    var volume = sqrt(3.0) / 2 * 2.464 * 2.464 * 6.711 * 1e-30
    assert_almost_equal(graphite.volume().value, volume, atol=1e-36)
    var block = graphite.block(2, 2, 1)
    var layer = bonds(block, _a(1.0), _a(1.5))
    assert_true(len(layer) > 0)
    for bond in layer:
        assert_almost_equal(
            bond.length.to(ANGSTROM), 2.464 / sqrt(3.0), atol=2e-5
        )
    # The layers lie c / 2 apart.
    var spacing = graphite.place(0, 0, 0.75)[2].value
    spacing -= graphite.place(0, 0, 0.25)[2].value
    assert_almost_equal(spacing, 6.711e-10 / 2, atol=1e-20)


def test_rock_salt() raises:
    var text = String(
        "data_NaCl\n",
        "_cell_length_a 5.64\n_cell_length_b 5.64\n_cell_length_c 5.64\n",
        "_cell_angle_alpha 90\n_cell_angle_beta 90\n_cell_angle_gamma 90\n",
        "loop_\n_space_group_symop_operation_xyz\n",
        "x,y,z\nx,0.5+y,0.5+z\n0.5+x,y,0.5+z\n0.5+x,0.5+y,z\n",
        "loop_\n_atom_site_type_symbol\n_atom_site_fract_x\n",
        "_atom_site_fract_y\n_atom_site_fract_z\n",
        "Na1+ 0 0 0\nCl1- 0.5 0 0\n",
        "data_second\n_cell_length_a 1\n",
    )
    var salt = read_cif(text)
    assert_equal(salt.name, "NaCl")
    assert_equal(len(salt.atoms), 8)
    var count_na = 0
    for atom in salt.atoms:
        if atom.element == SODIUM:
            count_na += 1
    assert_equal(count_na, 4)
    var cell = salt.block(1, 1, 1)
    var near = bonds(cell, _a(0), _a(3.0))
    for bond in near:
        assert_almost_equal(bond.length.to(ANGSTROM), 2.82, atol=1e-9)
        assert_true(cell[bond.first].element != cell[bond.second].element)
    assert_true(cell[0].element == SODIUM or cell[0].element == CHLORINE)


def test_operations() raises:
    # A shift as a decimal and as a fraction, and a factor before an axis.
    var one = _with_ops("'-x+0.5,-y+1/2,2z'")
    assert_almost_equal(one.atoms[0].u, 0.0, atol=1e-12)
    assert_almost_equal(one.atoms[0].v, 0.25, atol=1e-12)
    assert_almost_equal(one.atoms[0].w, 0.25, atol=1e-12)
    var spaced = _with_ops("'x + 1/2, y, -z'")
    assert_almost_equal(spaced.atoms[0].u, 0.0, atol=1e-12)
    assert_almost_equal(spaced.atoms[0].w, 0.875, atol=1e-12)
    # A plus sign before the first term.
    var plus = _with_ops("+x,+y,+z")
    assert_almost_equal(plus.atoms[0].u, 0.5, atol=1e-12)
    for bad in [
        "x,y",
        "x,y,",
        "x,y,zx",
        "x,y,z+",
        "x,y,z+1/0",
        "x,y,z+1/w",
        "x,y,w",
        "x,y,.",
        "x,y,z+1/2w",
    ]:
        with assert_raises(contains="operation"):
            _ = _with_ops(String("'", bad, "'"))


def test_positions_wrap() raises:
    # A position a hair below 0 wraps to 0, not to just under 1.
    var text = String(
        _CELL,
        "loop_\n_atom_site_label\n_atom_site_fract_x\n",
        "_atom_site_fract_y\n_atom_site_fract_z\n",
        "Ti -0.0000001 1.25 0.5\n",
    )
    var crystal = read_cif(text)
    assert_equal(crystal.atoms[0].element, TITANIUM)
    assert_almost_equal(crystal.atoms[0].u, 0.0, atol=0)
    assert_almost_equal(crystal.atoms[0].v, 0.25, atol=1e-12)
    # The identity alone, with no loop of operations.
    assert_equal(len(read_cif(String(_CELL, _ORIGIN)).atoms), 1)


def test_tokens() raises:
    # A tab, comments, a text field, and quotes that hold a quote.
    var text = String(
        "# a comment\n",
        "data_tokens\n",
        "_cell_length_a\t4 # four\n",
        "_cell_length_b 4\n_cell_length_c 4\n",
        "_cell_angle_alpha 90\n_cell_angle_beta 90\n_cell_angle_gamma 90\n",
        "_publ_section_title\n;\nA title\non two lines\n;\n",
        "_chemical_name_common 'it's'\n",
        "_chemical_name_mineral 'a' \n",
        '_journal_name_full "x"\t\n',
        _ORIGIN,
    )
    assert_equal(read_cif(text).name, "tokens")
    with assert_raises(contains="Line 2: a quoted value has no end"):
        _ = read_cif(String("data_x\n_a 'open\n"))
    with assert_raises(contains="Line 2: a text field has no end"):
        _ = read_cif(String("data_x\n;\nnever closed\n"))
    with assert_raises(contains="needs a data block"):
        _ = read_cif(String("_cell_length_a 4\n'data_quoted'\n"))
    with assert_raises(contains="needs a data block"):
        _ = read_cif(String())
    with assert_raises(contains="Line 2: 'stray' is not a name"):
        _ = read_cif(String("data_x\nstray\n"))
    with assert_raises(contains="Line 2: a loop has no name"):
        _ = read_cif(String("data_x\nloop_\n"))
    with assert_raises(contains="Line 2: a loop has no name"):
        _ = read_cif(String("data_x\nloop_\n1 2\n"))
    with assert_raises(contains="Line 2: a loop has no name"):
        _ = read_cif(String("data_x\nloop_\nloop_\n"))
    with assert_raises(contains="do not fill its rows"):
        _ = read_cif(String("data_x\nloop_\n_a\n_b\n1 2 3\n"))
    with assert_raises(contains="Line 2: _a has no value"):
        _ = read_cif(String("data_x\n_a\n"))
    with assert_raises(contains="Line 2: _a has no value"):
        _ = read_cif(String("data_x\n_a\n_b 1\n"))


def test_missing_items() raises:
    with assert_raises(contains="needs _cell_length_a"):
        _ = read_cif(String("data_x\n_cell_length_b 1\n"))
    with assert_raises(contains="needs _cell_length_a"):
        _ = read_cif(String("data_x\n"))
    # A loop of no operation, and a loop of no atom, leave the cell empty.
    var no_ops = String(_CELL, "loop_\n_symmetry_equiv_pos_as_xyz\n", _ORIGIN)
    with assert_raises(contains="needs an atom"):
        _ = read_cif(no_ops)
    var no_atoms = String(
        _CELL,
        "loop_\n_atom_site_label\n_atom_site_fract_x\n",
        "_atom_site_fract_y\n_atom_site_fract_z\n",
    )
    with assert_raises(contains="needs an atom"):
        _ = read_cif(no_atoms)
    with assert_raises(contains="Line 2: '?' is not a number"):
        _ = read_cif(String("data_x\n_cell_length_a ?\n"))
    with assert_raises(contains="atom positions in one loop"):
        _ = read_cif(_CELL)
    var y_apart = String(
        _CELL,
        "loop_\n_atom_site_label\n_atom_site_fract_x\n_atom_site_fract_z\n",
        "O 0 0\n_atom_site_fract_y 0\n",
    )
    with assert_raises(contains="atom positions in one loop"):
        _ = read_cif(y_apart)
    var no_z = String(
        _CELL,
        "loop_\n_atom_site_label\n_atom_site_fract_x\n_atom_site_fract_y\n",
        "O 0 0\n",
    )
    with assert_raises(contains="atom positions in one loop"):
        _ = read_cif(no_z)
    var nameless = String(
        _CELL,
        "loop_\n_atom_site_fract_x\n_atom_site_fract_y\n_atom_site_fract_z\n",
        "0 0 0\n",
    )
    with assert_raises(contains="atom types or labels"):
        _ = read_cif(nameless)
    for label in ["1C", "O_2x"]:
        var text = String(
            _CELL,
            "loop_\n_atom_site_label\n_atom_site_fract_x\n",
            "_atom_site_fract_y\n_atom_site_fract_z\n",
            label,
            " 0 0 0\n",
        )
        if label == "1C":
            with assert_raises(contains="'1C' names no element"):
                _ = read_cif(text)
        else:
            assert_equal(read_cif(text).atoms[0].element, OXYGEN)


def test_crystal_checks() raises:
    var right = _deg(90)
    for edge in [0.0, inf[DType.float64](), nan[DType.float64]()]:
        with assert_raises(contains="cell edge"):
            _ = Crystal(
                "x", _a(edge), _a(1), _a(1), right, right, right, _one()
            )
    for angle in [0.0, 180.0]:
        with assert_raises(contains="cell angle"):
            _ = Crystal(
                "x", _a(1), _a(1), _a(1), _deg(angle), right, right, _one()
            )
    with assert_raises(contains="needs an atom"):
        _ = Crystal("x", _a(1), _a(1), _a(1), right, right, right, List[Atom]())
    with assert_raises(contains="element of the table"):
        _ = Crystal(
            "x",
            _a(1),
            _a(1),
            _a(1),
            right,
            right,
            right,
            [Atom(Element(0), 0, 0, 0)],
        )
    for f in [-0.1, 1.0]:
        with assert_raises(contains="from 0 up to 1"):
            _ = Crystal(
                "x",
                _a(1),
                _a(1),
                _a(1),
                right,
                right,
                right,
                [Atom(CARBON, 0, 0, f)],
            )
    # Edges b and c each 10 degrees from a cannot be 90 degrees apart.
    var narrow = _deg(10)
    with assert_raises(contains="make no cell"):
        _ = Crystal("x", _a(1), _a(1), _a(1), right, narrow, narrow, _one())
    # A triclinic cell keeps its volume formula.
    var tri = Crystal(
        "t", _a(3), _a(4), _a(5), _deg(80), _deg(85), _deg(95), _one()
    )
    var ca = 0.17364817766693041
    var cb = 0.087155742747658166
    var cg = -0.087155742747658166
    var expected = 60e-30 * sqrt(
        1 - ca * ca - cb * cb - cg * cg + 2 * ca * cb * cg
    )
    assert_almost_equal(tri.volume().value, expected, atol=1e-40)
    var crystal = Crystal("x", _a(1), _a(1), _a(1), right, right, right, _one())
    for count in [0, 21]:
        with assert_raises(contains="1 to 20 cells"):
            _ = crystal.block(count, 1, 1)
    var cell = crystal.block(1, 1, 1)
    assert_equal(len(cell), 8)
    with assert_raises(contains="bond's range"):
        _ = bonds(cell, _a(-1), _a(1))
    with assert_raises(contains="bond's range"):
        _ = bonds(cell, _a(1), _a(1))
    with assert_raises(contains="bond's range"):
        _ = bonds(cell, _a(1), _a(inf[DType.float64]()))
    assert_equal(len(bonds(List[Position](), _a(0), _a(1))), 0)
    var p = Position(CARBON, _a(0), _a(0), _a(0))
    var q = Position(CARBON, _a(3), _a(4), _a(0))
    assert_almost_equal(p.distance(q).to(ANGSTROM), 5.0, atol=1e-12)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
