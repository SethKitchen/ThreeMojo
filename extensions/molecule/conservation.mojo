# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""The conservation of each column of a protein alignment, and its map onto
a chain.

A residue that evolution keeps the same across a protein family often
matters to the fold or the function. A missense variant at such a site is
more often harmful, so variant studies read the conservation of each site.

- `parse_fasta(text)` reads the names and sequences of a FASTA text. The
  rows of an alignment hold the twenty one-letter codes and `-` or `.`
  for a gap.
- `henikoff_weights(rows)` gives the weights of Henikoff and Henikoff
  (1994). Near copies of one sequence share their weight, so a family
  with many of them does not look more conserved than it is.
- `column_conservation(rows, weights, background)` gives, for each column,
  the weighted share of gaps, the Shannon entropy and the relative entropy
  to a background, and the Jensen-Shannon divergence to the background.
  The score is the divergence times one less the share of gaps, after
  Capra and Singh (2007).
- `conservation_b_factors(structure, chain, row, values)` writes a value
  of each column into the B-factors of the residues of a chain, for the
  colors of `coloring`.

Entropies and divergences are in bits. The order of a background is
`ORDER` of `sequence`: ARNDCQEGHILKMFPSTWYV.
"""

from extensions.molecule.ids import ChainId
from extensions.molecule.sequence import ORDER, chain_sequence, one_letter
from extensions.molecule.structure import SQUARE_ANGSTROM, Structure
from std.math import isfinite, log
from units.si import Area64
from extensions.numerics.elementary import INVERSE_LN2

# The gap codes, and the largest error of a background's sum.
comptime _GAPS = "-."
comptime _SUM_SLACK = 1e-6


struct FastaRecords(Copyable, Movable):
    """The names and the sequences of a FASTA text."""

    var names: List[String]
    """The text after each `>`, to the end of its line."""
    var sequences: List[String]
    """Each sequence, its lines joined, without white space."""

    def __init__(out self):
        """Create an empty set of records."""
        self.names = List[String]()
        self.sequences = List[String]()


def parse_fasta(text: String) raises -> FastaRecords:
    """Read the records of a FASTA text.

    Args:
        text: The text: a line `>name` before each sequence, whose lines
            follow. Blank lines are skipped.

    Returns:
        The names and the sequences, in order.

    Raises:
        Error: If there is no record, a sequence line comes before the
            first name, or a record has no sequence.
    """
    var out = FastaRecords()
    for line in text.splitlines():  # pragma: no branch
        var stripped = String(line.strip())
        if stripped.byte_length() == 0:
            continue
        if stripped.startswith(">"):
            out.names.append(String(stripped[byte=1:].strip()))
            out.sequences.append(String(""))
            continue
        if len(out.names) == 0:
            raise Error("A FASTA text needs a name line before a sequence")
        out.sequences[len(out.sequences) - 1] += stripped
    if len(out.names) == 0:
        raise Error("A FASTA text needs one record or more")
    for s in out.sequences:  # pragma: no branch
        if s.byte_length() == 0:
            raise Error("A FASTA record needs a sequence")
    return out^


def _codes(rows: List[String]) raises -> List[List[Int]]:
    """Return the index in `ORDER` of each code of each row, -1 for a gap.

    Refuses no rows, rows of two lengths, an empty row, or another code.
    """
    if len(rows) == 0:
        raise Error("An alignment needs one row or more")
    var width = rows[0].byte_length()
    if width == 0:
        raise Error("An alignment needs one column or more")
    var order = String(ORDER)
    var gaps = String(_GAPS)
    var out = List[List[Int]]()
    for row in rows:  # pragma: no branch
        if row.byte_length() != width:
            raise Error("The rows of an alignment must have one length")
        var codes = List[Int]()
        for code in row.codepoint_slices():  # pragma: no branch
            var text = String(code)
            var at = order.find(text)
            if at < 0 and gaps.find(text) < 0:
                raise Error(
                    "An alignment holds the twenty one-letter codes and gaps"
                )
            codes.append(at)
        out.append(codes^)
    return out^


def henikoff_weights(rows: List[String]) raises -> List[Float64]:
    """Return the position-based weights of the rows of an alignment.

    In each column, each row with a residue gets `1 / (r n)`, with r the
    count of residue types in the column and n the count of its own type.
    A gap gets nothing. The weights are then scaled to sum to 1.

    Args:
        rows: The rows of the alignment, of one length.

    Returns:
        The weight of each row, after Henikoff and Henikoff (1994).

    Raises:
        Error: If the rows are not an alignment, or hold gaps only.
    """
    var codes = _codes(rows)
    var width = len(codes[0])
    var out = List[Float64](length=len(rows), fill=0.0)
    for c in range(width):  # pragma: no branch
        var counts = List[Int](length=20, fill=0)
        for r in range(len(rows)):  # pragma: no branch
            if codes[r][c] >= 0:
                counts[codes[r][c]] += 1
        var kinds = 0
        for n in counts:  # pragma: no branch
            if n > 0:
                kinds += 1
        for r in range(len(rows)):  # pragma: no branch
            var k = codes[r][c]
            if k >= 0:
                out[r] += 1.0 / Float64(kinds * counts[k])
    var total = 0.0
    for w in out:  # pragma: no branch
        total += w
    if not (total > 0):
        raise Error("An alignment of gaps only has no weights")
    for r in range(len(out)):  # pragma: no branch
        out[r] /= total
    return out^


def uniform_background() -> List[Float64]:
    """Return the background of equal shares of the twenty amino acids.

    Returns:
        Twenty values of 1/20.
    """
    return List[Float64](length=20, fill=0.05)


struct ColumnConservation(Copyable, Movable):
    """The conservation of one column of an alignment."""

    var gaps: Float64
    """The weighted share of the rows with a gap."""
    var entropy: Float64
    """The Shannon entropy of the shares of the residues, in bits. 0 when
    one residue fills the column; at most `log2(20)`, or 4.32."""
    var relative_entropy: Float64
    """The relative entropy of the shares to the background, in bits."""
    var divergence: Float64
    """The Jensen-Shannon divergence of the shares and the background, in
    bits, from 0 to 1."""
    var score: Float64
    """The divergence times one less the share of gaps."""

    def __init__(
        out self,
        gaps: Float64,
        entropy: Float64,
        relative_entropy: Float64,
        divergence: Float64,
    ):
        """Create the conservation of a column.

        Args:
            gaps: The weighted share of gaps.
            entropy: The Shannon entropy.
            relative_entropy: The relative entropy to the background.
            divergence: The Jensen-Shannon divergence to the background.
        """
        self.gaps = gaps
        self.entropy = entropy
        self.relative_entropy = relative_entropy
        self.divergence = divergence
        self.score = divergence * (1.0 - gaps)


def _plogq(p: Float64, q: Float64) -> Float64:
    """Return `p log2(p / q)`, 0 when p is 0."""
    if p == 0:
        return 0.0
    return p * log(p / q) * INVERSE_LN2


def column_conservation(
    rows: List[String], weights: List[Float64], background: List[Float64]
) raises -> List[ColumnConservation]:
    """Return the conservation of each column of an alignment.

    Args:
        rows: The rows of the alignment, of one length.
        weights: The weight of each row, 0 or more and finite, with a sum
            above 0, such as `henikoff_weights`. They are scaled to sum to
            1.
        background: The share of each amino acid in the order `ORDER`,
            each above 0, with a sum of 1. Such as `uniform_background()`
            or the mean composition of the family.

    Returns:
        The conservation of each column. A column of gaps only has 0 for
        each value but the share of gaps.

    Raises:
        Error: If the rows are not an alignment, the weights are not one
            for each row, 0 or more, finite and with a sum above 0, or the
            background is not twenty shares above 0 that sum to 1.
    """
    var codes = _codes(rows)
    if len(weights) != len(rows):
        raise Error("An alignment needs one weight for each row")
    var total = 0.0
    for w in weights:  # pragma: no branch
        if not (w >= 0) or not isfinite(w):
            raise Error("A row weight must be 0 or more, and finite")
        total += w
    if not (total > 0):
        raise Error("The row weights need a sum above 0")
    if len(background) != 20:
        raise Error("A background needs one share for each amino acid")
    var sum = 0.0
    for b in background:  # pragma: no branch
        if not (b > 0) or not isfinite(b):
            raise Error("A background share must be above 0, and finite")
        sum += b
    if abs(sum - 1.0) > _SUM_SLACK:
        raise Error("The shares of a background must sum to 1")
    var out = List[ColumnConservation]()
    for c in range(len(codes[0])):  # pragma: no branch
        var shares = List[Float64](length=20, fill=0.0)
        var gaps = 0.0
        for r in range(len(rows)):  # pragma: no branch
            var w = weights[r] / total
            if codes[r][c] < 0:
                gaps += w
            else:
                shares[codes[r][c]] += w
        var filled = 1.0 - gaps
        if not (filled > 0):
            out.append(ColumnConservation(gaps, 0.0, 0.0, 0.0))
            continue
        var entropy = 0.0
        var relative = 0.0
        var divergence = 0.0
        for k in range(20):  # pragma: no branch
            var p = shares[k] / filled
            var q = background[k]
            var m = (p + q) / 2.0
            entropy -= _plogq(p, 1.0)
            relative += _plogq(p, q)
            divergence += (_plogq(p, m) + _plogq(q, m)) / 2.0
        out.append(ColumnConservation(gaps, entropy, relative, divergence))
    return out^


def conservation_b_factors(
    mut structure: Structure,
    chain: ChainId,
    row: String,
    values: List[Float64],
) raises:
    """Write a value of each column into the B-factors of a chain.

    The residues of the row, without its gaps, must be the sequence of the
    chain. Each residue of the chain gets the value of its column, in
    square angstroms, on every atom. A score from 0 to 1 is best scaled by
    100 first, as `lddt_b_factors` writes its scores.

    Args:
        structure: The structure.
        chain: The chain.
        row: The row of the chain in the alignment.
        values: One value for each column, finite.

    Raises:
        Error: If the chain id names no chain, the row is not of the
            chain's sequence or holds another code, or the values are not
            one finite value for each column.
    """
    var sequence = chain_sequence(structure, chain)
    var one = List[String]()
    one.append(row)
    var codes = _codes(one)
    if len(values) != len(codes[0]):
        raise Error("A conservation map needs one value for each column")
    var order = String(ORDER)
    var residues = String("")
    for k in codes[0]:  # pragma: no branch
        if k >= 0:
            residues += String(order[byte = k : k + 1])
    if residues != sequence:
        raise Error("The row without its gaps must be the chain's sequence")
    for v in values:  # pragma: no branch
        if not isfinite(v):
            raise Error("A conservation value must be finite")
    ref c = structure.chains[chain.value]
    var column = 0
    for r in range(
        c.first_residue, c.first_residue + c.residue_count
    ):  # pragma: no branch
        if one_letter(structure.residues[r].name).byte_length() == 0:
            continue
        while codes[0][column] < 0:
            column += 1
        var first = structure.residues[r].first_atom
        var end = first + structure.residues[r].atom_count
        for a in range(first, end):  # pragma: no branch
            structure.atoms[a].b_factor = Area64(
                values[column], SQUARE_ANGSTROM
            )
        column += 1
