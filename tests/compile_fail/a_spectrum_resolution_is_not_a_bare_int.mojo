# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""A spectrum resolution must be a `SpectrumResolution`, not a bare integer."""

from extensions.water.resolution import require_resolution


def main() raises:
    require_resolution(4)
