# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""A bare integer must not stand in for a VP8L transform."""

from render.webp_lossless import PREDICTOR_TRANSFORM, WebpTransform


def main() raises:
    var chosen: WebpTransform = 1
    print(chosen == PREDICTOR_TRANSFORM)
