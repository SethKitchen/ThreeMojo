# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""A bare integer must not stand in for a Super Resolution preset."""

from extensions.streamline.kinds import MODE_BALANCED
from extensions.streamline.options import SuperResolutionOptions


def main() raises:
    var options = SuperResolutionOptions(MODE_BALANCED, 1920, 1080)
    options.quality_preset = 13
    print(options.output_width)
