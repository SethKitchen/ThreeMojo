# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""A sex must be a `Sex`, not a bare integer."""

from extensions.humanoid.spec import HumanoidSpec
from units.si import FOOT, Length


def main() raises:
    var bad = HumanoidSpec(Length(6.0, FOOT), 0)
    print(bad.stature.value)
