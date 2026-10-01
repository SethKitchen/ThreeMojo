# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""A gene's expression must be an `Expression`, not a bare float."""

from extensions.humanoid.genome import MELANIN, Genome


def main() raises:
    var genome = Genome().with_gene(MELANIN, Float32(0.5))
    print(genome.get(MELANIN))
