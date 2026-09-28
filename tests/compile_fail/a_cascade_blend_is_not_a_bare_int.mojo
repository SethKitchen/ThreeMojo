# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""A bare integer must not stand in for how a sun's cascades blend: name
`CSM_BLEND` or `SUN_BLEND`."""

from lights.shadow import ShadowCascade


def main() raises:
    var band = ShadowCascade.none()
    band.blend = 1
    print(band.blend.value)
