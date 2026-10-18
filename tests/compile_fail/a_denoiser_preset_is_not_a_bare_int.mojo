# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""A bare integer must not stand in for a Ray Reconstruction preset."""

from extensions.streamline.kinds import MODE_BALANCED
from extensions.streamline.options import RayReconstructionOptions


def main() raises:
    var options = RayReconstructionOptions(MODE_BALANCED, 1920, 1080)
    options.quality_preset = 6
    print(options.output_width)
