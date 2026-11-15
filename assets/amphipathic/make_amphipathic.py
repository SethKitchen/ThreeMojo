# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Write the hydrophobic moments of four peptides with peptides and numpy.

    python3 make_amphipathic.py > amphipathic_expected.txt

Run it with numpy 2.5.4 and peptides 0.5.0, a Python port of the R
package Peptides. The scale is the normalized consensus scale of
Eisenberg and others (1984). Each line holds a sequence, then:

- the mean hydrophobicity, from `Peptide.hydrophobicity("Eisenberg")`;
- the moment of the whole sequence at 100 degrees a residue, from
  `Peptide.hydrophobic_moment` with a window of the whole length, and its
  direction in degrees from numpy, `atan2(sum h sin, sum h cos)`;
- the largest moment of a window of 11 residues at 100 degrees, from
  peptides, and the first window that gives it, from numpy;
- the moment of the whole sequence at 160 degrees, for a strand.
"""

import math

import numpy
import peptides

SEQUENCES = [
    "GIGAVLKVLTTGLPALISWIKRKRQQ",  # Melittin.
    "GIGKFLHSAKKFGKAFVGEIMNS",  # Magainin 2.
    "LLGDFFRKSKEKIGKEFKRIVQRIKDFLRNLVPRTES",  # LL-37.
    "LKKLLKLLKKLLKLLKKLLKL",  # A designed amphipathic helix.
]
scale = peptides.tables.HYDROPHOBICITY["Eisenberg"]


def window_moments(values, angle, window):
    n = numpy.arange(window)
    s = numpy.sin(numpy.radians(angle * n))
    c = numpy.cos(numpy.radians(angle * n))
    best = -1.0
    start = 0
    for i in range(len(values) - window + 1):
        part = values[i : i + window]
        norm = numpy.sum(part * s) ** 2 + numpy.sum(part * c) ** 2
        if norm > best:
            best = norm
            start = i
    return start


for sequence in SEQUENCES:
    peptide = peptides.Peptide(sequence)
    values = numpy.array([scale[a] for a in sequence])
    n = numpy.arange(len(sequence))
    angles = numpy.radians(100.0 * n)
    direction = math.degrees(
        math.atan2(numpy.sum(values * numpy.sin(angles)), numpy.sum(values * numpy.cos(angles)))
    )
    print(
        sequence,
        " ".join(
            repr(float(v))
            for v in [
                peptide.hydrophobicity("Eisenberg"),
                peptide.hydrophobic_moment(angle=100, window=len(sequence)),
                direction,
                peptide.hydrophobic_moment(angle=100, window=11),
                window_moments(values, 100.0, 11),
                peptide.hydrophobic_moment(angle=160, window=len(sequence)),
            ]
        ),
    )
