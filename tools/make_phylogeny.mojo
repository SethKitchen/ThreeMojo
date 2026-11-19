# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Write the synthetic sequences of the tree tests.

Run it from the repository root: `mojo run -I . tools/make_phylogeny.mojo`.
It writes `assets/phylogeny/sequences.txt`: eight protein sequences of 120
residues, one a line with its name. They evolve from one random root down
the tree `((A:0.05,B:0.08):0.1,(C:0.06,(D:0.04,E:0.07):0.05):0.08,
((F:0.1,G:0.03):0.06,H:0.12):0.09)`: along a branch of length b, each
site changes with a chance of b to one of the 19 other residues.
`assets/phylogeny/make_phylogeny.py` then writes the trees of Biopython
and scipy.
"""

from extensions.numerics.noise import Xorshift64
from tools._fixtures import SEED, write_text

comptime AMINO = "ARNDCQEGHILKMFPSTWYV"
comptime LENGTH = 120


def _evolve(
    mut noise: Xorshift64, sequence: List[Int], branch: Float64
) -> List[Int]:
    """Return a sequence changed along a branch."""
    var out = sequence.copy()
    for site in range(LENGTH):
        if noise.uniform() < branch:
            out[site] = (out[site] + 1 + Int(noise.uniform() * 19.0)) % 20
    return out^


def _text(sequence: List[Int]) -> String:
    """Return a sequence as one-letter codes."""
    var out = String()
    for k in sequence:
        out += String(AMINO[byte = k : k + 1])
    return out^


def main() raises:
    """Write the sequences.

    Raises:
        Error: If the file cannot be written.
    """
    var noise = Xorshift64(SEED)
    var root = List[Int]()
    for _ in range(LENGTH):
        root.append(Int(noise.uniform() * 20.0))
    var ab = _evolve(noise, root, 0.10)
    var cde = _evolve(noise, root, 0.08)
    var de = _evolve(noise, cde, 0.05)
    var fgh = _evolve(noise, root, 0.09)
    var fg = _evolve(noise, fgh, 0.06)
    var text = String()
    text += "A " + _text(_evolve(noise, ab, 0.05)) + "\n"
    text += "B " + _text(_evolve(noise, ab, 0.08)) + "\n"
    text += "C " + _text(_evolve(noise, cde, 0.06)) + "\n"
    text += "D " + _text(_evolve(noise, de, 0.04)) + "\n"
    text += "E " + _text(_evolve(noise, de, 0.07)) + "\n"
    text += "F " + _text(_evolve(noise, fg, 0.10)) + "\n"
    text += "G " + _text(_evolve(noise, fg, 0.03)) + "\n"
    text += "H " + _text(_evolve(noise, fgh, 0.12)) + "\n"
    write_text("assets/phylogeny/sequences.txt", text)
