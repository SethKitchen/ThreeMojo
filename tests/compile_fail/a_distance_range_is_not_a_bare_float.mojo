# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""A bare float must not stand in for a distance material's far distance:
it is a `Length`, so say its unit."""

from materials.material import distance_material


def main() raises:
    var measured = distance_material(far_distance=Float32(20))
    print(measured.kind.value)
