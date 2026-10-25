# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""A dye pattern must be a `DyePattern`, not a bare integer."""

from extensions.attire.kinds import require_dye_pattern


def main() raises:
    require_dye_pattern(1)
