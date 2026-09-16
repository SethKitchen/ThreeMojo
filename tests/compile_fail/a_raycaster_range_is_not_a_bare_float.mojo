# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""A raycaster's range given as bare numbers must not compile: is fifty
meters, or feet, or pixels? three.js's `Raycaster(origin, direction, near,
far)` takes unitless numbers and says nothing."""

from core.raycaster import Raycaster
from math.vector3 import Vector3


def main() raises:
    var caster = Raycaster(Vector3(0, 0, 5), Vector3(0, 0, -1), 0.1, 50.0)
    print(caster.near.value)
