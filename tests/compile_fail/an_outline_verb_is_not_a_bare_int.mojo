# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""A bare integer must not stand in for a glyph outline's command."""

from loaders.font import OutlineStep


def main() raises:
    var bad = OutlineStep(1, [Float32(0), 0])
    print(bad.coordinates[0])
