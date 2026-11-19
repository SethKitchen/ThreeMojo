# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""A slab mode must be a `SlabMode`, not a bare integer."""

from extensions.imaging.ids import require_slab_mode


def main() raises:
    require_slab_mode(0)
