# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""A bare float must not stand in for where a fog starts or ends: meters
and any other unit would be indistinguishable."""

from core.fog import linear_fog
from render.framebuffer import Color


def main() raises:
    var bad = linear_fog(Color(200, 200, 200), 1.0, 10.0)
    print(bad.color.r)
