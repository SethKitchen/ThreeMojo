# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""A boss phase must be a `BossPhase`, not a bare integer."""

from extensions.village.boss import phase_pace


def main() raises:
    print(phase_pace(1))
