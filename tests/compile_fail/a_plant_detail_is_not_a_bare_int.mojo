# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""A plant detail must be a `PlantDetail`, not a bare integer."""

from extensions.village.quality import planted
from extensions.village.village import VillageParameters


def main() raises:
    var parameters = planted(VillageParameters(), 1)
    print(parameters.meadow.litter)
