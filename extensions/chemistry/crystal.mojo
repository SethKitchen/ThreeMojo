# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Read crystal structures from CIF text, and place their atoms.

A CIF file (the Crystallographic Information File of the IUCr) gives a
crystal as a unit cell, the symmetry operations of its space group and the
atoms of the asymmetric unit. `read_cif` reads the first data block. It
applies each operation to each atom site and keeps each different position
in the cell once. The result is the full contents of one unit cell.
The tokens and tables come from `parse_cif` of `chemistry.cif`, which also
reads the mmCIF files of macromolecules.

The reader takes these items:

- `_cell_length_a`, `_b` and `_c` in angstroms, and `_cell_angle_alpha`,
  `_beta` and `_gamma` in degrees.
- The operations in `_space_group_symop_operation_xyz` or
  `_symmetry_equiv_pos_as_xyz`, such as `-y,x-y,z+1/2`. Without them, the
  identity is the only operation.
- `_atom_site_fract_x`, `_y` and `_z`. The element comes from
  `_atom_site_type_symbol`, or from the leading letters of
  `_atom_site_label`, so `Ti1` is titanium and `O2-` is oxygen.

A number can carry its uncertainty in parentheses, as in `3.5668(2)`. The
reader ignores the uncertainty. It ignores the occupancy too, so a site
that is partly full counts as full. Two sites at one position both stay.

`Crystal.block` places the atoms of a block of cells in Cartesian space,
with the atoms on the far faces, so a picture of the block is whole.
`bonds` finds the pairs of atoms in a range of distance.
"""

from std.math import cos, floor, isfinite, pi, sin, sqrt
from extensions.chemistry.cif import CifBlock, CifTable, parse_cif
from extensions.chemistry.elements import Element, element_from_symbol
from extensions.chemistry.quantities import ANGSTROM
from units.si import (
    Angle64,
    DEGREE64,
    Density64,
    Length64,
    Volume64,
)

# The most cells along one edge of a block.
comptime MAX_CELLS = 20
# Fractional positions closer than this are the same.
comptime _SAME = 1e-4
# Avogadro's constant, per mole.
comptime _AVOGADRO = 6.02214076e23


@fieldwise_init
struct Atom(ImplicitlyCopyable):
    """An atom at a fractional position in a unit cell."""

    var element: Element
    # The fractions of the cell edges a, b and c, from 0 up to 1.
    var u: Float64
    var v: Float64
    var w: Float64


@fieldwise_init
struct Position(ImplicitlyCopyable):
    """An atom at a Cartesian position."""

    var element: Element
    var x: Length64
    var y: Length64
    var z: Length64

    def distance(self, other: Position) -> Length64:
        """Return the distance to another position.

        Args:
            other: The other position.

        Returns:
            The straight distance between the two.
        """
        var dx = self.x.value - other.x.value
        var dy = self.y.value - other.y.value
        var dz = self.z.value - other.z.value
        return Length64(sqrt(dx * dx + dy * dy + dz * dz))


@fieldwise_init
struct Bond(ImplicitlyCopyable):
    """Two atoms of a list of positions, and the distance between them."""

    var first: Int
    var second: Int
    var length: Length64


def _wrap(value: Float64) -> Float64:
    """Return a fraction moved into the cell, from 0 up to 1."""
    var r = value - floor(value)
    if 1 - r < _SAME:
        return 0
    return r


struct Crystal(Copyable, Movable):
    """A unit cell and the atoms in it."""

    var name: String
    var a: Length64
    var b: Length64
    var c: Length64
    var alpha: Angle64
    var beta: Angle64
    var gamma: Angle64
    var atoms: List[Atom]

    def __init__(
        out self,
        name: String,
        a: Length64,
        b: Length64,
        c: Length64,
        alpha: Angle64,
        beta: Angle64,
        gamma: Angle64,
        var atoms: List[Atom],
    ) raises:
        """Make a crystal from its cell and its atoms.

        Args:
            name: The crystal's name.
            a: The length of the first edge.
            b: The length of the second edge.
            c: The length of the third edge.
            alpha: The angle between b and c.
            beta: The angle between a and c.
            gamma: The angle between a and b.
            atoms: The atoms of one cell, one or more.

        Raises:
            Error: If an edge is not positive, an angle is not between 0
                and 180 degrees, the angles make no cell, there is no atom,
                or an atom is not valid.
        """
        for edge in [a.value, b.value, c.value]:
            if not (isfinite(edge) and edge > 0):
                raise Error("A cell edge must be finite and positive")
        for angle in [alpha.value, beta.value, gamma.value]:
            if not (angle > 0 and angle < pi):
                raise Error("A cell angle must lie between 0 and 180 degrees")
        if len(atoms) == 0:
            raise Error("A crystal needs an atom")
        for atom in atoms:  # pragma: no branch
            if not atom.element.is_valid():
                raise Error("An atom must be an element of the table")
            for f in [atom.u, atom.v, atom.w]:
                if not (f >= 0 and f < 1):
                    raise Error("An atom's fractions must be from 0 up to 1")
        self.name = name
        self.a = a
        self.b = b
        self.c = c
        self.alpha = alpha
        self.beta = beta
        self.gamma = gamma
        self.atoms = atoms^
        if not (self._height() > 0):
            raise Error("The cell angles make no cell")

    def _height(self) -> Float64:
        """Return the third edge's height over the a-b plane, per unit c."""
        var cb = cos(self.beta.value)
        var cy = self._c_y()
        var square = 1 - cb * cb - cy * cy
        if square <= 0:
            return 0
        return sqrt(square)

    def _c_y(self) -> Float64:
        """Return the third edge's y component, per unit c."""
        var ca = cos(self.alpha.value)
        var cb = cos(self.beta.value)
        var cg = cos(self.gamma.value)
        return (ca - cb * cg) / sin(self.gamma.value)

    def volume(self) -> Volume64:
        """Return the volume of the cell.

        Returns:
            The product of the three edges, sin(gamma) and the third
            edge's height per unit c.
        """
        return Volume64(
            self.a.value
            * self.b.value
            * self.c.value
            * sin(self.gamma.value)
            * self._height()
        )

    def density(self) raises -> Density64:
        """Return the density of the crystal.

        Returns:
            The mass of the cell's atoms over its volume.

        Raises:
            Error: If an element has no standard atomic weight.
        """
        var mass = Float64(0)
        for atom in self.atoms:  # pragma: no branch
            mass += atom.element.atomic_weight().value
        return Density64(mass / _AVOGADRO / self.volume().value)

    def place(
        self, u: Float64, v: Float64, w: Float64
    ) -> Tuple[Length64, Length64, Length64]:
        """Return the Cartesian point of a fractional position.

        Edge a lies along x and edge b in the x-y plane.

        Args:
            u: The fraction of edge a.
            v: The fraction of edge b.
            w: The fraction of edge c.

        Returns:
            The x, y and z coordinates.
        """
        var a = self.a.value
        var b = self.b.value
        var c = self.c.value
        var cg = cos(self.gamma.value)
        var x = a * u + b * cg * v + c * cos(self.beta.value) * w
        var y = b * sin(self.gamma.value) * v + c * self._c_y() * w
        var z = c * self._height() * w
        return (Length64(x), Length64(y), Length64(z))

    def block(
        self, cells_a: Int, cells_b: Int, cells_c: Int
    ) raises -> List[Position]:
        """Return the atoms of a block of cells, with those on its far faces.

        An atom at a fraction of 0 is also placed on the block's far face,
        so a block of one cell shows all eight corners of the cell.

        Args:
            cells_a: The cells along edge a, from 1 to MAX_CELLS.
            cells_b: The cells along edge b.
            cells_c: The cells along edge c.

        Returns:
            The positions.

        Raises:
            Error: If a count is not from 1 to MAX_CELLS.
        """
        for count in [cells_a, cells_b, cells_c]:
            if count < 1 or count > MAX_CELLS:
                raise Error("A block needs 1 to 20 cells along each edge")
        var out = List[Position]()
        var far_a = Float64(cells_a) + _SAME
        var far_b = Float64(cells_b) + _SAME
        var far_c = Float64(cells_c) + _SAME
        # A crystal has an atom, and each range holds two counts at least.
        for atom in self.atoms:  # pragma: no branch
            for i in range(cells_a + 1):  # pragma: no branch
                for j in range(cells_b + 1):  # pragma: no branch
                    for k in range(cells_c + 1):  # pragma: no branch
                        var u = atom.u + Float64(i)
                        var v = atom.v + Float64(j)
                        var w = atom.w + Float64(k)
                        if u > far_a or v > far_b or w > far_c:
                            continue
                        var p = self.place(u, v, w)
                        out.append(Position(atom.element, p[0], p[1], p[2]))
        return out^


def bonds(
    positions: List[Position], shortest: Length64, longest: Length64
) raises -> List[Bond]:
    """Return the pairs of positions in a range of distance.

    Args:
        positions: The positions, as `Crystal.block` gives them.
        shortest: The shortest distance of a bond, zero or more.
        longest: The longest, more than the shortest.

    Returns:
        Each pair once, the lower index first.

    Raises:
        Error: If the range is not valid.
    """
    if not (
        shortest.value >= 0
        and longest.value > shortest.value
        and isfinite(longest.value)
    ):
        raise Error("A bond's range must be finite and ascend from zero")
    var out = List[Bond]()
    for i in range(len(positions)):
        for j in range(i + 1, len(positions)):
            var d = positions[i].distance(positions[j])
            if d.value >= shortest.value and d.value <= longest.value:
                out.append(Bond(i, j, d))
    return out^


# --- reading ------------------------------------------------------------------


def _number(table: CifTable, at: Int) raises -> Float64:
    """Read the number of a value, without the uncertainty in
    parentheses."""
    var text = table.values[at]
    var open = text.find("(")
    if open >= 0:
        text = String(table.values[at][byte=:open])
    try:
        return atof(text)
    except:
        raise Error(
            String(
                "Line ",
                table.lines[at],
                ": '",
                table.values[at],
                "' is not a number",
            )
        )


def _single(block: CifBlock, tag: String) raises -> Float64:
    """Return the number of a name that the file must hold."""
    var at = block.find(tag)
    if at[0] < 0:
        raise Error(String("A CIF file needs ", tag))
    return _number(block.tables[at[0]], at[1])


def _is_digit(byte: UInt8) -> Bool:
    """Return whether a byte is a decimal digit."""
    return byte >= 48 and byte <= 57


def _axis(byte: UInt8) -> Int:
    """Return 0, 1 or 2 for x, y or z, and -1 for any other byte."""
    if byte == 120:
        return 0
    if byte == 121:
        return 1
    if byte == 122:
        return 2
    return -1


def _component(text: String, number: Int) raises -> List[Float64]:
    """Return one part of an operation as x, y and z factors and a shift."""
    var out: List[Float64] = [0, 0, 0, 0]
    var s = text.replace(" ", "").lower()
    var bytes = s.as_bytes()
    var n = len(bytes)
    var bad = String("Line ", number, ": '", text, "' is not an operation")
    if n == 0:
        raise Error(bad)
    var k = 0
    while k < n:
        var sign = Float64(1)
        if bytes[k] == 43:
            k += 1
        elif bytes[k] == 45:
            sign = -1
            k += 1
        elif k > 0:
            raise Error(bad)
        var start = k
        while k < n and (_is_digit(bytes[k]) or bytes[k] == 46):
            k += 1
        var value = Float64(1)
        var has_number = k > start
        if has_number:
            try:
                value = atof(String(s[byte=start:k]))
            except:
                raise Error(bad)
            if k < n and bytes[k] == 47:
                k += 1
                var low = k
                while k < n and _is_digit(bytes[k]):
                    k += 1
                var denominator = Float64(0)
                if k > low:
                    denominator = atof(String(s[byte=low:k]))
                if denominator == 0:
                    raise Error(bad)
                value /= denominator
        var axis = -1
        if k < n:
            axis = _axis(bytes[k])
        if axis >= 0:
            out[axis] += sign * value
            k += 1
        elif has_number:
            out[3] += sign * value
        else:
            raise Error(bad)
    return out^


def _operation(text: String, line: Int) raises -> List[Float64]:
    """Return an operation as three rows of x, y and z factors and a shift."""
    var parts = text.split(",")
    if len(parts) != 3:
        raise Error(
            String("Line ", line, ": '", text, "' is not")
            + " an operation of three parts"
        )
    var out = List[Float64]()
    for part in parts:  # pragma: no branch
        out.extend(_component(String(part), line))
    return out^


def _is_letter(byte: UInt8) -> Bool:
    """Return whether a byte is an ASCII letter."""
    # Setting bit 5 turns A to Z into a to z, and no other byte into them.
    var lower = byte | 32
    return lower >= 97 and lower <= 122


def _symbol(text: String, line: Int) raises -> Element:
    """Return the element that a symbol or a label starts with."""
    var bytes = text.as_bytes()
    var k = 0
    while k < len(bytes) and _is_letter(bytes[k]):
        k += 1
    if k == 0:
        raise Error(String("Line ", line, ": '", text, "' names no element"))
    return element_from_symbol(String(text[byte=:k]))


def _close(a: Float64, b: Float64) -> Bool:
    """Return whether two fractions are the same position in the cell."""
    var d = abs(a - b)
    return min(d, 1 - d) < _SAME


def _holds(atoms: List[Atom], atom: Atom) -> Bool:
    """Return whether a list holds an atom at the same position."""
    for seen in atoms:
        if _close(seen.u, atom.u) and _close(seen.v, atom.v):
            if _close(seen.w, atom.w):
                return True
    return False


def read_cif(text: String) raises -> Crystal:
    """Read the crystal of the first data block of a CIF file.

    Args:
        text: The file's text.

    Returns:
        The crystal, with every atom of its unit cell.

    Raises:
        Error: With the line number where it can, if the file has no data
            block, a value or a text field has no end, a loop does not
            fill its rows, an item has no value, a number or an operation
            cannot be read, an element is not in the table, or a cell item
            or an atom position is missing.
    """
    var block = parse_cif(text)
    var a = Length64(_single(block, "_cell_length_a"), ANGSTROM)
    var b = Length64(_single(block, "_cell_length_b"), ANGSTROM)
    var c = Length64(_single(block, "_cell_length_c"), ANGSTROM)
    var alpha = Angle64(_single(block, "_cell_angle_alpha"), DEGREE64)
    var beta = Angle64(_single(block, "_cell_angle_beta"), DEGREE64)
    var gamma = Angle64(_single(block, "_cell_angle_gamma"), DEGREE64)
    var operations = List[List[Float64]]()
    var at = block.find("_space_group_symop_operation_xyz")
    if at[0] < 0:
        at = block.find("_symmetry_equiv_pos_as_xyz")
    if at[0] < 0:
        operations.append([1.0, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0])
    else:
        ref table = block.tables[at[0]]
        var width = len(table.tags)
        for row in range(table.rows()):
            var k = row * width + at[1]
            operations.append(_operation(table.values[k], table.lines[k]))
    var xs = block.find("_atom_site_fract_x")
    var ys = block.find("_atom_site_fract_y")
    var zs = block.find("_atom_site_fract_z")
    if xs[0] < 0 or ys[0] != xs[0] or zs[0] != xs[0]:
        raise Error("A CIF file needs the atom positions in one loop")
    var kind = block.find("_atom_site_type_symbol")
    if kind[0] != xs[0]:
        kind = block.find("_atom_site_label")
    if kind[0] != xs[0]:
        raise Error("A CIF file needs the atom types or labels")
    ref sites = block.tables[xs[0]]
    var width = len(sites.tags)
    var atoms = List[Atom]()
    for row in range(sites.rows()):
        var first = row * width
        var element = _symbol(
            sites.values[first + kind[1]], sites.lines[first + kind[1]]
        )
        var u = _number(sites, first + xs[1])
        var v = _number(sites, first + ys[1])
        var w = _number(sites, first + zs[1])
        var images = List[Atom]()
        for op in operations:
            var image = Atom(
                element,
                _wrap(op[0] * u + op[1] * v + op[2] * w + op[3]),
                _wrap(op[4] * u + op[5] * v + op[6] * w + op[7]),
                _wrap(op[8] * u + op[9] * v + op[10] * w + op[11]),
            )
            if not _holds(images, image):
                images.append(image)
        atoms.extend(images^)
    return Crystal(block.name, a, b, c, alpha, beta, gamma, atoms^)
