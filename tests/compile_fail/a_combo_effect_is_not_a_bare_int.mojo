# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""A combo effect must be a `ComboEffect`, not a bare integer."""

from extensions.village.combos import effect_name


def main() raises:
    print(effect_name(3))
