# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""A bare integer must not stand in for a DLSS mode."""

from extensions.streamline.options import SuperResolutionOptions


def main() raises:
    var options = SuperResolutionOptions(3, 1920, 1080)
    print(options.output_width)
