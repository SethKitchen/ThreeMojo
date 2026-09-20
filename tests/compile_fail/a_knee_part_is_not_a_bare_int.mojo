# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""A knee part must be a `KneePart`, not a bare integer."""

from extensions.humanoid.sex import MALE
from extensions.humanoid.skeleton.leg.knee.geometry import knee_mesh
from extensions.humanoid.spec import HumanoidSpec
from units.si import FOOT, Length


def main() raises:
    var person = HumanoidSpec(Length(6.0, FOOT), MALE)
    var mesh = knee_mesh(person, 0)
    print(mesh.vertex_count())
