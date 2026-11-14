# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""The sequences of chains, FASTA files and global alignments.

`chain_sequence` reads the one-letter sequence of a chain from its
residues. A residue that is not one of the twenty standard amino acids,
such as a water or a ligand, is left out. `encode_fasta` writes the
sequence of each chain of a model as a FASTA file.

`align_sequences` aligns two sequences end to end by the method of
Needleman and Wunsch, with the affine gaps of Gotoh. A pair of residues
scores its BLOSUM62 value. A gap of length `L` scores
`open + (L - 1) * extend`, at the ends too. The identity of an alignment
is the share of its paired columns that hold the same residue. Use it to
check that two models are of one protein before a superposition.
"""

from extensions.molecule.ids import ChainId, ModelId
from extensions.molecule.structure import Structure
from std.math import inf, isfinite

# The order of the rows and columns of BLOSUM62.
comptime ORDER = "ARNDCQEGHILKMFPSTWYV"


# BLOSUM62 for the twenty standard residues, one row per line, in the
# order of ORDER.
comptime _BLOSUM62 = (
    "4 -1 -2 -2 0 -1 -1 0 -2 -1 -1 -1 -1 -2 -1 1 0 -3 -2 0\n"
    "-1 5 0 -2 -3 1 0 -2 0 -3 -2 2 -1 -3 -2 -1 -1 -3 -2 -3\n"
    "-2 0 6 1 -3 0 0 0 1 -3 -3 0 -2 -3 -2 1 0 -4 -2 -3\n"
    "-2 -2 1 6 -3 0 2 -1 -1 -3 -4 -1 -3 -3 -1 0 -1 -4 -3 -3\n"
    "0 -3 -3 -3 9 -3 -4 -3 -3 -1 -1 -3 -1 -2 -3 -1 -1 -2 -2 -1\n"
    "-1 1 0 0 -3 5 2 -2 0 -3 -2 1 0 -3 -1 0 -1 -2 -1 -2\n"
    "-1 0 0 2 -4 2 5 -2 0 -3 -3 1 -2 -3 -1 0 -1 -3 -2 -2\n"
    "0 -2 0 -1 -3 -2 -2 6 -2 -4 -4 -2 -3 -3 -2 0 -2 -2 -3 -3\n"
    "-2 0 1 -1 -3 0 0 -2 8 -3 -3 -1 -2 -1 -2 -1 -2 -2 2 -3\n"
    "-1 -3 -3 -3 -1 -3 -3 -4 -3 4 2 -3 1 0 -3 -2 -1 -3 -1 3\n"
    "-1 -2 -3 -4 -1 -2 -3 -4 -3 2 4 -2 2 0 -3 -2 -1 -2 -1 1\n"
    "-1 2 0 -1 -3 1 1 -2 -1 -3 -2 5 -1 -3 -1 0 -1 -3 -2 -2\n"
    "-1 -1 -2 -3 -1 0 -2 -3 -2 1 2 -1 5 0 -2 -1 -1 -1 -1 1\n"
    "-2 -3 -3 -3 -2 -3 -3 -3 -1 0 0 -3 0 6 -4 -2 -2 1 3 -1\n"
    "-1 -2 -2 -1 -3 -1 -1 -2 -2 -3 -3 -1 -2 -4 7 -1 -1 -4 -3 -2\n"
    "1 -1 1 0 -1 0 0 0 -1 -2 -2 0 -1 -2 -1 4 1 -3 -2 -2\n"
    "0 -1 0 -1 -1 -1 -1 -2 -2 -1 -1 -1 -1 -2 -1 1 5 -2 -2 0\n"
    "-3 -3 -4 -4 -2 -2 -3 -2 -2 -3 -2 -3 -1 1 -4 -3 -2 11 2 -3\n"
    "-2 -2 -2 -3 -2 -1 -2 -3 2 -1 -1 -2 -1 3 -3 -2 -2 2 7 -1\n"
    "0 -3 -3 -3 -1 -2 -2 -3 -3 3 1 -2 1 -1 -2 -2 0 -3 -1 4\n"
)


def _blosum() raises -> List[Int]:
    """Return BLOSUM62 for the twenty standard residues, row by row."""
    var out = List[Int]()
    for token in String(_BLOSUM62).split():  # pragma: no branch
        out.append(atol(token))
    return out^


def _index(code: UInt8) raises -> Int:
    """Return the BLOSUM62 row of a one-letter code."""
    var order = String(ORDER).as_bytes()
    for k in range(len(order)):  # pragma: no branch
        if order[k] == code:
            return k
    raise Error("A sequence holds a code that is not a standard amino acid")


def blosum62(a: String, b: String) raises -> Int:
    """Return the BLOSUM62 score of two one-letter codes.

    Args:
        a: The first code, such as `W`.
        b: The second code.

    Returns:
        The score, from -4 to 11.

    Raises:
        Error: If a code is not one of the twenty standard codes.
    """
    if a.byte_length() != 1 or b.byte_length() != 1:
        raise Error("A BLOSUM62 score needs two one-letter codes")
    var table = _blosum()
    return table[20 * _index(a.as_bytes()[0]) + _index(b.as_bytes()[0])]


def one_letter(name: String) -> String:
    """Return the one-letter code of a standard residue name.

    Args:
        name: The residue name, such as `TRP`.

    Returns:
        The code, such as `W`, or an empty string for any other name.
    """
    var names: List[String] = [
        "ALA",
        "ARG",
        "ASN",
        "ASP",
        "CYS",
        "GLN",
        "GLU",
        "GLY",
        "HIS",
        "ILE",
        "LEU",
        "LYS",
        "MET",
        "PHE",
        "PRO",
        "SER",
        "THR",
        "TRP",
        "TYR",
        "VAL",
    ]
    var codes = String(ORDER)
    for k in range(20):  # pragma: no branch
        if names[k] == name:
            return String(codes[byte = k : k + 1])
    return String("")


def chain_sequence(structure: Structure, chain: ChainId) raises -> String:
    """Return the one-letter sequence of a chain.

    Args:
        structure: The structure.
        chain: The chain.

    Returns:
        One code for each standard amino acid of the chain, in order.

    Raises:
        Error: If the chain id names no chain.
    """
    structure.require_chain(chain)
    ref c = structure.chains[chain.value]
    var out = String("")
    for r in range(c.first_residue, c.first_residue + c.residue_count):
        out += one_letter(structure.residues[r].name)
    return out^


def encode_fasta(structure: Structure, model: ModelId) raises -> String:
    """Return the sequence of each chain of a model as a FASTA file.

    Each record is `>NAME:CHAIN`, with the structure's name and the
    chain's author id, and the sequence in lines of 80 codes. A chain
    without a standard amino acid has no record.

    Args:
        structure: The structure.
        model: The model.

    Returns:
        The text.

    Raises:
        Error: If the model id names no model.
    """
    structure.require_model(model)
    ref m = structure.models[model.value]
    var out = String("")
    for c in range(
        m.first_chain, m.first_chain + m.chain_count
    ):  # pragma: no branch
        var sequence = chain_sequence(structure, ChainId(c))
        var size = sequence.byte_length()
        if size == 0:
            continue
        out += ">" + structure.name + ":" + structure.chains[c].author + "\n"
        var at = 0
        while at < size:
            var end = min(at + 80, size)
            out += String(sequence[byte=at:end]) + "\n"
            at = end
    return out^


struct SequenceAlignment(Copyable, Movable):
    """Two sequences aligned end to end."""

    var first: String
    """The first sequence, with `-` for each gap."""
    var second: String
    """The second sequence, with `-` for each gap."""
    var score: Float64
    """The score: the BLOSUM62 values of the pairs and the gap scores."""
    var identical: Int
    """The paired columns that hold the same residue."""
    var paired: Int
    """The columns that hold a residue of each sequence."""

    def __init__(out self):
        """Create an empty alignment."""
        self.first = String("")
        self.second = String("")
        self.score = 0
        self.identical = 0
        self.paired = 0

    def identity(self) raises -> Float64:
        """Return the share of paired columns with the same residue.

        Returns:
            From 0 to 1.

        Raises:
            Error: If no column pairs two residues.
        """
        if self.paired == 0:
            raise Error("An alignment without paired columns has no identity")
        return Float64(self.identical) / Float64(self.paired)


def align_sequences(
    first: String, second: String, open: Float64, extend: Float64
) raises -> SequenceAlignment:
    """Align two sequences end to end, with BLOSUM62 and affine gaps.

    Args:
        first: The first sequence of one-letter codes. Not empty.
        second: The second sequence. Not empty.
        open: The score of the first position of a gap, such as -10.
            Zero or less, and finite.
        extend: The score of each further position, such as -0.5. Zero
            or less, and finite.

    Returns:
        The best alignment. Where two paths tie, the trace takes a pair
        first, then a gap in the second sequence, then a gap in the
        first. A gap that goes on comes before a new one.

    Raises:
        Error: If a sequence is empty or holds a code that is not one of
            the twenty standard codes, or a gap score is positive or not
            finite.
    """
    if not (open <= 0) or not isfinite(open):
        raise Error("A gap opening score must be zero or less, and finite")
    if not (extend <= 0) or not isfinite(extend):
        raise Error("A gap extension score must be zero or less, and finite")
    var a = first.as_bytes()
    var b = second.as_bytes()
    var n = len(a)
    var m = len(b)
    if n == 0 or m == 0:
        raise Error("An alignment needs two sequences that are not empty")
    var ra = List[Int]()
    for k in range(n):  # pragma: no branch
        ra.append(_index(a[k]))
    var rb = List[Int]()
    for k in range(m):  # pragma: no branch
        rb.append(_index(b[k]))
    var table = _blosum()
    var width = m + 1
    var low = -inf[DType.float64]()
    # The best score ending in a pair, in a gap of the second sequence (a
    # residue of the first against a gap), or in a gap of the first.
    var match_ = List[Float64](length=(n + 1) * width, fill=low)
    var down = List[Float64](length=(n + 1) * width, fill=low)
    var across = List[Float64](length=(n + 1) * width, fill=low)
    match_[0] = 0
    for i in range(1, n + 1):  # pragma: no branch
        down[i * width] = open + Float64(i - 1) * extend
    for j in range(1, m + 1):  # pragma: no branch
        across[j] = open + Float64(j - 1) * extend
    for i in range(1, n + 1):  # pragma: no branch
        for j in range(1, m + 1):  # pragma: no branch
            var at = i * width + j
            var diagonal = (i - 1) * width + j - 1
            var best = max(
                match_[diagonal], max(down[diagonal], across[diagonal])
            )
            match_[at] = best + Float64(table[20 * ra[i - 1] + rb[j - 1]])
            var up = (i - 1) * width + j
            down[at] = max(
                max(match_[up], across[up]) + open, down[up] + extend
            )
            var left = i * width + j - 1
            across[at] = max(
                max(match_[left], down[left]) + open, across[left] + extend
            )
    var out = SequenceAlignment()
    var end = n * width + m
    out.score = max(match_[end], max(down[end], across[end]))
    # Trace back from the end, in the state of the best score.
    var state = 0
    if match_[end] < out.score:
        state = 1 if down[end] == out.score else 2
    var i = n
    var j = m
    var top = List[UInt8]()
    var bottom = List[UInt8]()
    while i > 0 or j > 0:
        var at = i * width + j
        if state == 0:
            var diagonal = (i - 1) * width + j - 1
            var pair = Float64(table[20 * ra[i - 1] + rb[j - 1]])
            top.append(a[i - 1])
            bottom.append(b[j - 1])
            out.paired += 1
            if a[i - 1] == b[j - 1]:
                out.identical += 1
            i -= 1
            j -= 1
            # The sums repeat the forward pass, so they compare exactly.
            if match_[diagonal] + pair == match_[at]:
                state = 0
            elif down[diagonal] + pair == match_[at]:
                state = 1
            else:
                state = 2
        elif state == 1:
            var up = (i - 1) * width + j
            top.append(a[i - 1])
            bottom.append(45)
            var extended = down[up] + extend == down[at]
            i -= 1
            if i > 0 and not extended:
                state = 0 if match_[up] + open == down[at] else 2
            elif i == 0:
                state = 2
        else:
            var left = i * width + j - 1
            top.append(45)
            bottom.append(b[j - 1])
            var extended = across[left] + extend == across[at]
            j -= 1
            if j > 0 and not extended:
                state = 0 if match_[left] + open == across[at] else 1
            elif j == 0:
                state = 1
    top.reverse()
    bottom.reverse()
    out.first = String(from_utf8_lossy=top)
    out.second = String(from_utf8_lossy=bottom)
    return out^
