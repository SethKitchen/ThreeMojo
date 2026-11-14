# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Build the ideal backbone of a peptide from its sequence and its shape.

Each residue gets the atoms N, CA, C and O, and CB when it is not
glycine. The bond lengths and angles are the ideal values of Engh and
Huber. Each new atom is placed from the three before it by the natural
extension reference frame (NeRF): a bond length, a bond angle and a
torsion. CB is placed by the ideal formula of trRosetta, which gives an
L-amino acid.

The secondary structure of each residue sets its backbone torsions:

| Kind | phi | psi |
|---|---|---|
| `HELIX` | -57 | -47 |
| `STRAND` | -139 | 135 |
| `COIL` | -75 | 145 |

Each peptide bond is trans: omega is 180 degrees. The torsions make
ideal shapes. They do not fold a sequence: a real protein's shape comes
from experiment or from a structure prediction.
"""

from extensions.chemistry.quantities import ANGSTROM
from extensions.molecule.ids import (
    ATOM_RECORD,
    ChainId,
    HELIX,
    ModelId,
    ResidueId,
    STRAND,
    SecondaryKind,
    require_secondary,
)
from extensions.molecule.structure import (
    Atom,
    Chain,
    Model,
    Residue,
    SQUARE_ANGSTROM,
    Structure,
)
from extensions.sdf.vector import V3, cross, normalize, v3
from std.math import cos, pi, sin
from units.si import Area64, Length64

comptime _N_CA = 1.458
comptime _CA_C = 1.525
comptime _C_N = 1.329
comptime _C_O = 1.231
comptime _N_CA_C = 111.2
comptime _CA_C_N = 116.2
comptime _C_N_CA = 121.7
comptime _CA_C_O = 120.5


def three_letter(code: String) raises -> String:
    """Return the residue name of a one-letter amino acid code.

    Args:
        code: One of the twenty standard codes, such as `A` or `W`.

    Returns:
        The three-letter name, such as `ALA` or `TRP`.

    Raises:
        Error: If the code is not a standard amino acid.
    """
    var codes = "ACDEFGHIKLMNPQRSTVWY"
    var names: List[String] = [
        "ALA",
        "CYS",
        "ASP",
        "GLU",
        "PHE",
        "GLY",
        "HIS",
        "ILE",
        "LYS",
        "LEU",
        "MET",
        "ASN",
        "PRO",
        "GLN",
        "ARG",
        "SER",
        "THR",
        "VAL",
        "TRP",
        "TYR",
    ]
    var at = codes.find(code)
    if code.byte_length() != 1 or at < 0:
        raise Error("'" + code + "' is not a standard amino acid code")
    return names[at]


def place_atom(
    a: V3, b: V3, c: V3, bond: Float64, angle: Float64, torsion: Float64
) -> V3:
    """Return the atom bonded to `c` that a bond, an angle and a torsion give.

    Args:
        a: The atom two before `c`.
        b: The atom before `c`.
        c: The atom the new one bonds to.
        bond: The length of the new bond.
        angle: The angle from `b` through `c` to the new atom, in radians.
        torsion: The torsion from `a`, `b` and `c` to the new atom, in
            radians.

    Returns:
        The new atom, in the units of the inputs.
    """
    var bc = normalize(c - b)
    var n = normalize(cross(b - a, bc))
    var m = cross(n, bc)
    var along = -bond * cos(angle)
    var across = bond * sin(angle)
    return (
        c
        + bc * along
        + m * (across * cos(torsion))
        + n * (across * sin(torsion))
    )


def _torsions(kind: SecondaryKind) -> Tuple[Float64, Float64]:
    """Return the phi and the psi of a secondary structure, in degrees."""
    if kind == HELIX:
        return (-57.0, -47.0)
    if kind == STRAND:
        return (-139.0, 135.0)
    return (-75.0, 145.0)


def _radians(degrees: Float64) -> Float64:
    """Return an angle in radians."""
    return degrees * pi / 180.0


def _meters(p: V3) -> V3:
    """Return a point in angstroms as a point in meters."""
    var scale = Length64(1.0, ANGSTROM).value
    return p * scale


def build_peptide(
    sequence: String, kinds: List[SecondaryKind]
) raises -> Structure:
    """Return one chain of ideal backbone for a sequence.

    The first N is at the origin. The structure has one model and one
    chain named `A`. Each residue's secondary structure is its kind.

    Args:
        sequence: One-letter amino acid codes, such as `MKTAYIAK`.
        kinds: The secondary structure of each residue.

    Returns:
        The structure, in meters.

    Raises:
        Error: If the sequence is empty, the two lengths differ, a code is
            not a standard amino acid, or a kind is not valid.
    """
    var count = sequence.byte_length()
    if count == 0:
        raise Error("A peptide needs at least one residue")
    if len(kinds) != count:
        raise Error("A peptide needs one secondary structure for each residue")
    var out = Structure("PEPTIDE")
    out.models.append(Model(1, 0, 1))
    out.chains.append(Chain("A", "A", ModelId(0), 0, count))
    var n_at = v3(0, 0, 0)
    var ca_at = v3(_N_CA, 0, 0)
    var turn = _radians(_N_CA_C)
    var c_at = ca_at + v3(-_CA_C * cos(turn), _CA_C * sin(turn), 0)
    for index in range(count):  # pragma: no branch
        var code = String(sequence[byte = index : index + 1])
        var name = three_letter(code)
        var kind = kinds[index]
        require_secondary(kind)
        if index > 0:
            var before = _torsions(kinds[index - 1])
            var phi = _torsions(kind)[0]
            var n_next = place_atom(
                n_at,
                ca_at,
                c_at,
                _C_N,
                _radians(_CA_C_N),
                _radians(before[1]),
            )
            var ca_next = place_atom(
                ca_at, c_at, n_next, _N_CA, _radians(_C_N_CA), pi
            )
            var c_next = place_atom(
                c_at, n_next, ca_next, _CA_C, _radians(_N_CA_C), _radians(phi)
            )
            n_at = n_next
            ca_at = ca_next
            c_at = c_next
        var psi = _torsions(kind)[1]
        var o_at = place_atom(
            n_at, ca_at, c_at, _C_O, _radians(_CA_C_O), _radians(psi + 180.0)
        )
        var residue = ResidueId(index)
        var first = len(out.atoms)
        _add(out, "N", "N", n_at, residue)
        _add(out, "CA", "C", ca_at, residue)
        _add(out, "C", "C", c_at, residue)
        _add(out, "O", "O", o_at, residue)
        if name != "GLY":
            var b = ca_at - n_at
            var c = c_at - ca_at
            var a = cross(b, c)
            var cb = a * -0.58273431 + b * 0.56802827 + c * -0.54067466 + ca_at
            _add(out, "CB", "C", cb, residue)
        out.residues.append(
            Residue(
                name,
                index + 1,
                index + 1,
                "?",
                ChainId(0),
                first,
                len(out.atoms) - first,
                kind,
            )
        )
    return out^


def _add(
    mut out: Structure,
    name: String,
    element: String,
    at: V3,
    residue: ResidueId,
):
    """Append one atom, given in angstroms."""
    out.atoms.append(
        Atom(
            name,
            element,
            len(out.atoms) + 1,
            ATOM_RECORD,
            ".",
            _meters(at),
            1.0,
            Area64(0.0, SQUARE_ANGSTROM),
            residue,
        )
    )
