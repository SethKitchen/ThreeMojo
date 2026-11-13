# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""A bare integer must not stand in for a denoiser's mode."""

from postprocessing.temporal_denoise import TemporalDenoiseSettings


def main() raises:
    var settings = TemporalDenoiseSettings()
    settings.mode = 1
    print(settings.max_frames)
