# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""An atom record group must be an `AtomGroup`, not a bare integer."""

from extensions.molecule.ids import require_group


def main() raises:
    require_group(0)
