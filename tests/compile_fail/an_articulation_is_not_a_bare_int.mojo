# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""An articulation must be an `Articulation`, not a bare integer."""

from extensions.attire.kinds import require_articulation


def main() raises:
    require_articulation(1)
