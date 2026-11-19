# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Write the synthetic protein alignment of the conservation tests.

Run it from the repository root: `mojo run -I . tools/make_conservation.mojo`.
It writes `assets/conservation/conservation_msa.fasta`: 12 sequences of
48 columns, from one root sequence by random changes. Columns 0 to 11
are held, columns 12 to 35 change at a rate that rises, and columns 36
to 47 are free. From column 20 on, a residue of a sequence after the
first is a gap with a chance of 0.12. Column 30 holds gaps only, but in
the first sequence, and the second sequence has a gap at column 5. Each
sequence is on two lines of 30 and 18 residues.
`assets/conservation/make_conservation.py` then writes the scores of
scipy and Biopython.
"""

from extensions.numerics.noise import Xorshift64
from tools._fixtures import SEED, write_text

comptime ORDER = "ARNDCQEGHILKMFPSTWYV"
comptime ROWS = 12
comptime COLUMNS = 48


def _residue(mut noise: Xorshift64) -> String:
    """Return one of the 20 residues, each as likely."""
    var at = Int(noise.uniform() * 20.0)
    return String(ORDER[byte = at : at + 1])


def main() raises:
    """Write the alignment.

    Raises:
        Error: If the file cannot be written.
    """
    var noise = Xorshift64(SEED)
    var root = List[String]()
    for _ in range(COLUMNS):
        root.append(_residue(noise))
    var rows = List[List[String]]()
    for r in range(ROWS):
        var row = root.copy()
        for c in range(COLUMNS):
            var rate = 0.0
            if c >= 36:
                rate = 0.9
            elif c >= 12:
                rate = 0.03 * Float64(c - 11)
            if noise.uniform() < rate:
                row[c] = _residue(noise)
            if r > 0 and c >= 20 and noise.uniform() < 0.12:
                row[c] = "-"
        rows.append(row^)
    for r in range(1, ROWS):
        rows[r][30] = "-"
    rows[1][5] = "-"
    var text = String()
    for r in range(ROWS):
        var head = String()
        var tail = String()
        for c in range(COLUMNS):
            if c < 30:
                head += rows[r][c]
            else:
                tail += rows[r][c]
        text += String(">seq", r, " synthetic\n", head, "\n", tail, "\n")
    write_text("assets/conservation/conservation_msa.fasta", text)
