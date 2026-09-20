# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""A vessel part must be a `VesselPart`, not a bare integer."""

from extensions.humanoid.sex import MALE
from extensions.humanoid.spec import HumanoidSpec
from extensions.humanoid.skeleton.leg.vessels.geometry import vessel_mesh
from units.si import FOOT, Length


def main() raises:
    var person = HumanoidSpec(Length(6.0, FOOT), MALE)
    var mesh = vessel_mesh(person, 0)
    print(mesh.vertex_count())
