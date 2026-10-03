# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""An anatomy mode must be an `AnatomyMode`, not a bare integer."""

from extensions.anatomy.mode import require_mode


def main() raises:
    require_mode(1)
