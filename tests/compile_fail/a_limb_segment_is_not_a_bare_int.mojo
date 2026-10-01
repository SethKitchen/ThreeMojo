# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""A limb segment must be a `LimbSegment`, not a bare integer."""

from extensions.humanoid.sex import MALE
from extensions.humanoid.spec import HumanoidSpec
from extensions.humanoid.skeleton.limb.inertia import segment_inertia
from units.si import FOOT, Length


def main() raises:
    var bad = segment_inertia(HumanoidSpec(Length(6.0, FOOT), MALE), 0)
    print(bad.mass.value)
