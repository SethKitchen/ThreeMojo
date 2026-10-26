# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""A quality preset must be a `QualityPreset`, not a bare integer."""

from extensions.village.quality import game_quality


def main() raises:
    var quality = game_quality(0)
    print(quality.render_scale)
