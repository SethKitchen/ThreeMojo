# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""A sculpt primitive kind must be a `PrimitiveKind`, not a bare integer."""

from extensions.sdf.ids import require_kind


def main() raises:
    require_kind(0)
