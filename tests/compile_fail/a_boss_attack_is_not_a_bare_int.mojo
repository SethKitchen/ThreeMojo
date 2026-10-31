# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""A boss attack must be a `BossAttack`, not a bare integer."""

from extensions.village.boss import attack_name


def main() raises:
    print(attack_name(0))
