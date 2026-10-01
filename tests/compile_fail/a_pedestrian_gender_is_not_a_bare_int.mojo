# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""A pedestrian's gender must be a `PedestrianGender`, not a bare integer."""

from extensions.carla.blueprint import (
    AGE_ADULT,
    GENDER_FEMALE,
    PedestrianParameters,
)


def main() raises:
    var p = PedestrianParameters("1", 1, AGE_ADULT, 1, List[Float32]())
    print(p.id)
