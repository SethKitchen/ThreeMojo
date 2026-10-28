# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""A village prop's kind must be a `PropKind`, not a bare integer."""

from extensions.village.props import Prop
from units.si import DEGREE, Angle


def main() raises:
    var prop = Prop(1, 0, 0, Angle(0.0, DEGREE), 1)
    print(prop.length)
