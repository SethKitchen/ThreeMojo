# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""A degree of freedom axis must be a `DofAxis`, not a bare integer."""

from extensions.fem.ids import require_dof_axis


def main() raises:
    require_dof_axis(0)
