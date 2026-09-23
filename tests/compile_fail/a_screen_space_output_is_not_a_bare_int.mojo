# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""A bare integer must not stand in for a screen-space output."""

from postprocessing.screen_space import SsaoSettings


def main() raises:
    var settings = SsaoSettings()
    settings.output = 3
    print(settings.output.value)
