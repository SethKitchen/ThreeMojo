# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""A pedestrian's age must be a `PedestrianAge`, not a bare integer."""

from extensions.carla.blueprint import (
    AGE_ADULT,
    GENDER_FEMALE,
    PedestrianParameters,
)


def main() raises:
    var p = PedestrianParameters("1", GENDER_FEMALE, 2, 1, List[Float32]())
    print(p.id)
