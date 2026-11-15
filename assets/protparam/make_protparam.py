# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Write the parameters of protein sequences with Biopython and peptides.

    python3 make_protparam.py > protparam_expected.txt

Run it with Biopython 1.88 and peptides 0.5.0. Each line holds a sequence,
then:

- the net charge at pH 7 and at pH 7.4, and the isoelectric point, from
  peptides with the pK values of EMBOSS;
- the average molecular mass in g/mol, the molar extinction coefficients
  at 280 nm with the cysteines reduced and as cystines, the GRAVY and the
  aromaticity, from Biopython's `ProteinAnalysis`;
- the aliphatic index, from peptides.
"""

import peptides
from Bio.SeqUtils.ProtParam import ProteinAnalysis

SEQUENCES = [
    "MQIFVKTLTGKTITLEVEPSDTIENVKAKIQDKEGIPPDQQRLIFAGKQLEDGRTLSDYNIQKESTLHLVLRLRGG",
    "GIGKFLHSAKKFGKAFVGEIMNS",
    "GIGAVLKVLTTGLPALISWIKRKRQQ",
    "LLGDFFRKSKEKIGKEFKRIVQRIKDFLRNLVPRTES",
    "CWYCCWDDEEHHKKRR",
]
for sequence in SEQUENCES:
    peptide = peptides.Peptide(sequence)
    analysis = ProteinAnalysis(sequence)
    extinction = analysis.molar_extinction_coefficient()
    values = [
        peptide.charge(pH=7.0, pKscale="EMBOSS"),
        peptide.charge(pH=7.4, pKscale="EMBOSS"),
        peptide.isoelectric_point(pKscale="EMBOSS"),
        analysis.molecular_weight(),
        extinction[0],
        extinction[1],
        analysis.gravy(),
        analysis.aromaticity(),
        peptide.aliphatic_index(),
    ]
    print(sequence, " ".join(repr(float(v)) for v in values))
