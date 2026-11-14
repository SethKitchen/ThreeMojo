# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Backbone dihedral angles of a model, and Ramachandran plots.

Three torsions set the shape of a protein backbone at each residue `i`:

| Angle | Atoms |
|---|---|
| phi | C of `i - 1`, N, CA, C |
| psi | N, CA, C, N of `i + 1` |
| omega | CA, C, N of `i + 1`, CA of `i + 1` |

A torsion has the IUPAC sign: seen along its middle bond, it is positive
when the far bond turns clockwise from the near bond. Its range is from
-180 to 180 degrees.

`backbone_angles` gives the angles of each residue of a model. A residue
needs its N, CA and C. A neighbor counts only in the same chain, with a
peptide bond: its C to N distance is at most 2.5 angstroms, as in DSSP.
The first residue of a chain therefore has no phi, and the last has no
psi or omega.

`ramachandran_image` plots psi against phi, one dot per residue, colored
by the residue's secondary structure. Helices gather near (-60, -45),
and strands near (-120, 130). A trans peptide bond has an omega near
180 degrees, and a cis bond near 0.
"""

from extensions.chemistry.quantities import ANGSTROM
from extensions.molecule.dssp import PEPTIDE_REACH
from extensions.molecule.ids import (
    AtomId,
    HELIX,
    ModelId,
    ResidueId,
    STRAND,
)
from extensions.molecule.structure import Structure
from extensions.sdf.vector import V3, cross, distance, dot, length
from render.framebuffer import Color, Framebuffer
from std.math import atan2
from units.si import Angle64, DEGREE64, Length64, RADIAN

# Two bonds whose cross product is shorter than this, relative to the
# product of their lengths, are in a line.
comptime _IN_LINE = 1.0e-9


def dihedral(a: V3, b: V3, c: V3, d: V3) raises -> Angle64:
    """Return the torsion of four points about the bond from `b` to `c`.

    Args:
        a: The first point.
        b: The second point.
        c: The third point.
        d: The fourth point.

    Returns:
        The torsion, from -180 to 180 degrees, with the IUPAC sign.

    Raises:
        Error: If three of the points in a row are in a line, so that the
            torsion is not defined.
    """
    var b1 = b - a
    var b2 = c - b
    var b3 = d - c
    var n1 = cross(b1, b2)
    var n2 = cross(b2, b3)
    var middle = length(b2)
    if length(n1) <= _IN_LINE * length(b1) * middle or length(
        n2
    ) <= _IN_LINE * middle * length(b3):
        raise Error("A dihedral needs points that are not in a line")
    return Angle64(atan2(middle * dot(b1, n2), dot(n1, n2)), RADIAN)


@fieldwise_init
struct BackboneAngles(Copyable, Movable):
    """The backbone torsions of one residue.

    An angle that a residue does not have is zero, and its flag is false.
    """

    var residue: ResidueId
    """The residue."""
    var phi: Angle64
    """The torsion C of the residue before, N, CA, C."""
    var psi: Angle64
    """The torsion N, CA, C, N of the residue after."""
    var omega: Angle64
    """The torsion CA, C, N and CA of the residue after."""
    var has_phi: Bool
    """Whether the residue has a phi."""
    var has_psi: Bool
    """Whether the residue has a psi."""
    var has_omega: Bool
    """Whether the residue has an omega."""


def _bonded(structure: Structure, c: AtomId, n: AtomId) -> Bool:
    """Return whether a C and an N make a peptide bond."""
    if c.value < 0 or n.value < 0:
        return False
    var reach = PEPTIDE_REACH * Length64(1.0, ANGSTROM).value
    return (
        distance(
            structure.atoms[c.value].position,
            structure.atoms[n.value].position,
        )
        <= reach
    )


def backbone_angles(
    structure: Structure, model: ModelId
) raises -> List[BackboneAngles]:
    """Return the phi, psi and omega of each residue of a model.

    Args:
        structure: The structure.
        model: The model.

    Returns:
        One entry for each residue with an N, a CA and a C, in chain
        order. Of two atoms of one name, the first counts.

    Raises:
        Error: If the model id names no model, or three backbone atoms
            of a torsion are in a line.
    """
    structure.require_model(model)
    ref m = structure.models[model.value]
    var out = List[BackboneAngles]()
    for c in range(
        m.first_chain, m.first_chain + m.chain_count
    ):  # pragma: no branch
        ref chain = structure.chains[c]
        var first = chain.first_residue
        var end = first + chain.residue_count
        for r in range(first, end):  # pragma: no branch
            var id = ResidueId(r)
            var n = structure.find_atom(id, "N")
            var ca = structure.find_atom(id, "CA")
            var cc = structure.find_atom(id, "C")
            if n.value < 0 or ca.value < 0 or cc.value < 0:
                continue
            var p_n = structure.atoms[n.value].position
            var p_ca = structure.atoms[ca.value].position
            var p_c = structure.atoms[cc.value].position
            var angles = BackboneAngles(
                id,
                Angle64(0.0),
                Angle64(0.0),
                Angle64(0.0),
                False,
                False,
                False,
            )
            if r > first:
                var before = structure.find_atom(ResidueId(r - 1), "C")
                if _bonded(structure, before, n):
                    angles.phi = dihedral(
                        structure.atoms[before.value].position,
                        p_n,
                        p_ca,
                        p_c,
                    )
                    angles.has_phi = True
            if r + 1 < end:
                var after = ResidueId(r + 1)
                var next_n = structure.find_atom(after, "N")
                if _bonded(structure, cc, next_n):
                    var p_next = structure.atoms[next_n.value].position
                    angles.psi = dihedral(p_n, p_ca, p_c, p_next)
                    angles.has_psi = True
                    var next_ca = structure.find_atom(after, "CA")
                    if next_ca.value >= 0:
                        angles.omega = dihedral(
                            p_ca,
                            p_c,
                            p_next,
                            structure.atoms[next_ca.value].position,
                        )
                        angles.has_omega = True
            out.append(angles^)
    return out^


def plot_pixel(angle: Angle64, size: Int) -> Int:
    """Return the column of an angle on a plot from -180 to 180 degrees.

    Args:
        angle: The angle, from -180 to 180 degrees.
        size: The width of the plot, in pixels.

    Returns:
        The column, from 0 at -180 degrees to `size - 1` at 180 degrees.
    """
    var t = (angle.to(DEGREE64) + 180.0) / 360.0
    var column = Int(t * Float64(size))
    if column < 0:
        return 0
    if column >= size:
        return size - 1
    return column


def ramachandran_color(structure: Structure, residue: ResidueId) -> Color:
    """Return the dot color of a residue on a Ramachandran plot.

    Args:
        structure: The structure.
        residue: The residue. It must name a residue of the structure.

    Returns:
        Red for a helix, gold for a strand, and dark gray for a coil.
    """
    var kind = structure.residues[residue.value].secondary
    if kind == HELIX:
        return Color(214, 48, 82)
    if kind == STRAND:
        return Color(214, 150, 0)
    return Color(80, 80, 88)


def ramachandran_image(
    structure: Structure, angles: List[BackboneAngles], size: Int
) raises -> Framebuffer:
    """Plot psi against phi, one dot for each residue that has both.

    Phi runs from -180 degrees at the left to 180 at the right, and psi
    from 180 at the top to -180 at the bottom. Gray lines mark zero.

    Args:
        structure: The structure of the angles.
        angles: The angles, such as `backbone_angles` gives.
        size: The width and the height of the image, from 64 to 2048
            pixels.

    Returns:
        A white square image with a dot of 3 by 3 pixels for each
        residue.

    Raises:
        Error: If the size is out of range, or an entry names no residue
            of the structure.
    """
    if size < 64 or size > 2048:
        raise Error("A Ramachandran plot is from 64 to 2048 pixels wide")
    var image = Framebuffer(size, size, Color(255, 255, 255))
    var zero = plot_pixel(Angle64(0.0), size)
    var line = Color(200, 200, 205)
    for k in range(size):  # pragma: no branch
        image.set_pixel(zero, k, line)
        image.set_pixel(k, size - 1 - zero, line)
    var frame = Color(60, 60, 66)
    for k in range(size):  # pragma: no branch
        image.set_pixel(k, 0, frame)
        image.set_pixel(k, size - 1, frame)
        image.set_pixel(0, k, frame)
        image.set_pixel(size - 1, k, frame)
    for entry in angles:
        structure.require_residue(entry.residue)
        if not (entry.has_phi and entry.has_psi):
            continue
        var x = plot_pixel(entry.phi, size)
        var y = size - 1 - plot_pixel(entry.psi, size)
        var color = ramachandran_color(structure, entry.residue)
        for dy in range(-1, 2):  # pragma: no branch
            for dx in range(-1, 2):  # pragma: no branch
                var px = x + dx
                var py = y + dy
                if px >= 0 and px < size and py >= 0 and py < size:
                    image.set_pixel(px, py, color)
    return image^
