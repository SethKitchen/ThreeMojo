# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""A bare integer must not stand in for a halftone blending mode."""

from postprocessing.effects import HalftoneSettings


def main() raises:
    var settings = HalftoneSettings()
    settings.blending_mode = 3
    print(settings.blending_mode.value)
