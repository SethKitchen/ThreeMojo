# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""A construction kit must be a `KitKind`, not a bare integer."""

from extensions.building.kits import KitKind


def main():
    var kind: KitKind = 0
    _ = kind.is_valid()
