# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""A body side must be a `BodySide`, not a bare integer."""

from extensions.humanoid.sex import MALE
from extensions.humanoid.spec import HumanoidSpec
from extensions.humanoid.skeleton.leg.femur.geometry import femur
from units.si import FOOT, Length


def main() raises:
    var person = HumanoidSpec(Length(6.0, FOOT), MALE)
    var bone = femur(person, 0)
    print(bone.vertex_count())
