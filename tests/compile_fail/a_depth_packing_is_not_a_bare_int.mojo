# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""A bare integer must not stand in for a depth packing: say which of the
four it is with `RGBA_DEPTH_PACKING` and the rest."""

from materials.material import depth_material


def main() raises:
    var packed = depth_material(depth_packing=3201)
    print(packed.kind.value)
