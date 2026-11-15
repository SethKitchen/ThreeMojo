# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""The parameters of a protein sequence: charge, isoelectric point, mass,
extinction, hydropathy and aliphatic index, as ProtParam gives them.

- `net_charge(sequence, ph)` sums the charges of the ionizable groups at a
  pH, by the equation of Henderson and Hasselbalch with the pK values of
  EMBOSS: N terminus 8.6, C terminus 3.6, K 10.8, R 12.5, H 6.5, D 3.9,
  E 4.1, C 8.5 and Y 10.1.
- `isoelectric_point(sequence)` finds the pH of no net charge by bisection.
- `average_mass(sequence)` sums the average masses of the amino acids, less
  one water for each peptide bond, as Biopython does.
- `extinction_coefficients(sequence)` gives the molar extinction at 280 nm,
  `5500 W + 1490 Y`, and that plus 125 for each pair of cysteines as a
  cystine, after Pace and others (1995).
- `gravy(sequence)` gives the mean hydropathy of Kyte and Doolittle.
- `aromaticity(sequence)` gives the share of F, W and Y.
- `aliphatic_index(sequence)` gives `100 (x_A + 2.9 x_V + 3.9 (x_I + x_L))`
  of the shares x, after Ikai (1980).
"""

from extensions.chemistry.quantities import (
    GRAM_PER_MOLE,
    Molar,
    MolarMass64,
    MolarUnit,
)
from extensions.molecule.coloring import kyte_doolittle
from extensions.molecule.peptide import three_letter
from std.math import isfinite
from extensions.numerics.elementary import precise_power10
from extensions.numerics.search import bisect

comptime MolarArea64 = Molar[2, 0, 0, 0]
"""An area for each mole: the unit of a molar extinction coefficient."""
comptime MolarAreaUnit = MolarUnit[2, 0, 0, 0]
"""A unit of a molar area."""
comptime PER_MOLAR_CENTIMETER = MolarAreaUnit(0.1, "M^-1 cm^-1")
"""The liter for each mole and centimeter, the unit of a molar extinction
coefficient."""

comptime _CODES = "ACDEFGHIKLMNPQRSTVWY"
comptime _WATER = 18.0153
comptime _BISECTIONS = 200


def _codes(sequence: String) raises -> List[Int]:
    """Return the index of each code in `_CODES`, refusing an empty sequence
    or another code."""
    if sequence.byte_length() == 0:
        raise Error("A sequence needs one residue or more")
    var codes = String(_CODES)
    var out = List[Int]()
    for code in sequence.codepoint_slices():  # pragma: no branch
        var at = codes.find(String(code))
        if at < 0:
            raise Error("A sequence holds only the twenty one-letter codes")
        out.append(at)
    return out^


def _charge(codes: List[Int], ph: Float64) -> Float64:
    """Return the net charge of the residues and the ends at a pH."""
    # The pK of each code in `_CODES`, with 0 for a code that has none, and
    # +1 for a base, -1 for an acid.
    var pk: List[Float64] = [
        0.0,
        8.5,
        3.9,
        4.1,
        0.0,
        0.0,
        6.5,
        0.0,
        10.8,
        0.0,
        0.0,
        0.0,
        0.0,
        0.0,
        12.5,
        0.0,
        0.0,
        0.0,
        0.0,
        10.1,
    ]
    var sign: List[Float64] = [
        0.0,
        -1.0,
        -1.0,
        -1.0,
        0.0,
        0.0,
        1.0,
        0.0,
        1.0,
        0.0,
        0.0,
        0.0,
        0.0,
        0.0,
        1.0,
        0.0,
        0.0,
        0.0,
        0.0,
        -1.0,
    ]
    var total = 1.0 / (1.0 + precise_power10(ph - 8.6)) - 1.0 / (
        1.0 + precise_power10(3.6 - ph)
    )
    for k in codes:  # pragma: no branch
        var s = sign[k]
        total += s / (1.0 + precise_power10(s * (ph - pk[k])))
    return total


def net_charge(sequence: String, ph: Float64) raises -> Float64:
    """Return the net charge of a protein at a pH.

    Args:
        sequence: The one-letter codes, in capitals.
        ph: The pH, finite.

    Returns:
        The sum of the charges of the ends and of the ionizable side chains,
        with the pK values of EMBOSS. A residue without one adds nothing.

    Raises:
        Error: If the sequence is empty or holds another code, or the pH is
            not finite.
    """
    var codes = _codes(sequence)
    if not isfinite(ph):
        raise Error("A pH must be finite")
    return _charge(codes, ph)


def isoelectric_point(sequence: String) raises -> Float64:
    """Return the pH at which a protein has no net charge.

    The charge falls as the pH rises, so 200 bisections from pH 0 to 14
    find the point to the last place.

    Args:
        sequence: The one-letter codes, in capitals.

    Returns:
        The isoelectric point.

    Raises:
        Error: If the sequence is empty or holds another code.
    """
    var codes = _codes(sequence)

    def charged(ph: Float64) raises capturing -> Bool:
        return _charge(codes, ph) > 0

    return bisect[charged](0.0, 14.0, _BISECTIONS)


def average_mass(sequence: String) raises -> MolarMass64:
    """Return the average molecular mass of a protein.

    Args:
        sequence: The one-letter codes, in capitals.

    Returns:
        The sum of the average masses of the free amino acids, less 18.0153
        g/mol of water for each peptide bond.

    Raises:
        Error: If the sequence is empty or holds another code.
    """
    var codes = _codes(sequence)
    var masses: List[Float64] = [
        89.0932,
        121.1582,
        133.1027,
        147.1293,
        165.1891,
        75.0666,
        155.1546,
        131.1729,
        146.1876,
        131.1729,
        149.2113,
        132.1179,
        115.1305,
        146.1445,
        174.201,
        105.0926,
        119.1192,
        117.1463,
        204.2252,
        181.1885,
    ]
    var total = 0.0
    for k in codes:  # pragma: no branch
        total += masses[k]
    total -= Float64(len(codes) - 1) * _WATER
    return MolarMass64(total, GRAM_PER_MOLE)


def _count(codes: List[Int], code: String) -> Int:
    """Return how many residues hold one code."""
    var at = String(_CODES).find(code)
    var out = 0
    for k in codes:  # pragma: no branch
        if k == at:
            out += 1
    return out


def extinction_coefficients(
    sequence: String,
) raises -> Tuple[MolarArea64, MolarArea64]:
    """Return the molar extinction coefficients of a protein at 280 nm.

    Args:
        sequence: The one-letter codes, in capitals.

    Returns:
        `5500 W + 1490 Y` with the cysteines reduced, and that plus 125 for
        each pair of cysteines as a cystine, in M^-1 cm^-1.

    Raises:
        Error: If the sequence is empty or holds another code.
    """
    var codes = _codes(sequence)
    var reduced = Float64(5500 * _count(codes, "W") + 1490 * _count(codes, "Y"))
    var cystines = reduced + Float64(125 * (_count(codes, "C") // 2))
    return (
        MolarArea64(reduced, PER_MOLAR_CENTIMETER),
        MolarArea64(cystines, PER_MOLAR_CENTIMETER),
    )


def gravy(sequence: String) raises -> Float64:
    """Return the grand average of hydropathy of a protein.

    Args:
        sequence: The one-letter codes, in capitals.

    Returns:
        The mean hydropathy of the residues on the scale of Kyte and
        Doolittle. Above 0 for a hydrophobic protein.

    Raises:
        Error: If the sequence is empty or holds another code.
    """
    var codes = _codes(sequence)
    var total = 0.0
    for k in codes:  # pragma: no branch
        var code = String(String(_CODES)[byte = k : k + 1])
        total += kyte_doolittle(three_letter(code))[1]
    return total / Float64(len(codes))


def aromaticity(sequence: String) raises -> Float64:
    """Return the share of aromatic residues of a protein.

    Args:
        sequence: The one-letter codes, in capitals.

    Returns:
        The share of F, W and Y.

    Raises:
        Error: If the sequence is empty or holds another code.
    """
    var codes = _codes(sequence)
    var count = _count(codes, "F") + _count(codes, "W") + _count(codes, "Y")
    return Float64(count) / Float64(len(codes))


def aliphatic_index(sequence: String) raises -> Float64:
    """Return the aliphatic index of a protein, after Ikai (1980).

    Args:
        sequence: The one-letter codes, in capitals.

    Returns:
        `100 (x_A + 2.9 x_V + 3.9 (x_I + x_L))`, with x the share of each
        residue. A higher index means a protein more stable to heat.

    Raises:
        Error: If the sequence is empty or holds another code.
    """
    var codes = _codes(sequence)
    var n = Float64(len(codes))
    var ala = Float64(_count(codes, "A")) / n
    var val = Float64(_count(codes, "V")) / n
    var leu = Float64(_count(codes, "L")) / n
    var ile = Float64(_count(codes, "I")) / n
    return (ala + 2.9 * val + 3.9 * (leu + ile)) * 100.0
