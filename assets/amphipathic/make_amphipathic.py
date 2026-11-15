# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Write the hydrophobic moments of four peptides with peptides.

    python3 make_amphipathic.py > amphipathic_expected.txt

Run it with peptides 0.5.0, a Python port of the R package Peptides. The
scale is the normalized consensus scale of Eisenberg and others (1984).
The first line, `scale`, holds each of the twenty amino acids and its
value from `peptides.tables`. Each other line holds a sequence, then:

- the mean hydrophobicity, from `Peptide.hydrophobicity("Eisenberg")`;
- the moment of the whole sequence at 100 degrees a residue, from
  `Peptide.hydrophobic_moment` with a window of the whole length;
- the largest moment of a window of 11 residues at 100 degrees;
- the moment of the whole sequence at 160 degrees, for a strand.

The test builds the direction of each moment and the first window of the
largest moment from the scale.
"""

import peptides

SEQUENCES = [
    "GIGAVLKVLTTGLPALISWIKRKRQQ",  # Melittin.
    "GIGKFLHSAKKFGKAFVGEIMNS",  # Magainin 2.
    "LLGDFFRKSKEKIGKEFKRIVQRIKDFLRNLVPRTES",  # LL-37.
    "LKKLLKLLKKLLKLLKKLLKL",  # A designed amphipathic helix.
]
scale = peptides.tables.HYDROPHOBICITY["Eisenberg"]
print("scale", " ".join(a + " " + repr(float(scale[a])) for a in sorted(scale)))
for sequence in SEQUENCES:
    peptide = peptides.Peptide(sequence)
    print(
        sequence,
        " ".join(
            repr(float(v))
            for v in [
                peptide.hydrophobicity("Eisenberg"),
                peptide.hydrophobic_moment(angle=100, window=len(sequence)),
                peptide.hydrophobic_moment(angle=100, window=11),
                peptide.hydrophobic_moment(angle=160, window=len(sequence)),
            ]
        ),
    )
