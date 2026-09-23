# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""A bare integer must not stand in for a blend equation."""

from materials.material import custom_blending
from render.blend import ONE_FACTOR


def main() raises:
    var bad = custom_blending(ONE_FACTOR, ONE_FACTOR, 2)
    print(bad.value)
