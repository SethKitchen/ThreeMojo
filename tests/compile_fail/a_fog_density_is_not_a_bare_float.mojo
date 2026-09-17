# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""A bare float must not stand in for a fog density, which is a quantity
per meter."""

from core.fog import exp2_fog
from render.framebuffer import Color


def main() raises:
    var bad = exp2_fog(Color(200, 200, 200), 0.05)
    print(bad.color.r)
