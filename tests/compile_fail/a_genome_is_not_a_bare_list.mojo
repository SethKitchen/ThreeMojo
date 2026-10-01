# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""A spec's genome must be a `Genome`, not a bare list of floats."""

from extensions.humanoid.athleticism import TONED
from extensions.humanoid.sex import MALE
from extensions.humanoid.spec import HumanoidSpec
from units.si import FOOT, Length


def main() raises:
    var genes: List[Float32] = [0.5, 0.2]
    var bad = HumanoidSpec(Length(6.0, FOOT), MALE, TONED, genes)
    print(bad.stature.value)
