# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""A pixel representation must be a `PixelRepresentation`, not a bare integer."""

from extensions.imaging.ids import require_representation


def main() raises:
    require_representation(0)
