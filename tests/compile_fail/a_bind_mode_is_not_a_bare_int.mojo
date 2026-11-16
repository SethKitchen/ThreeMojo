# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""A skin bind mode must be a `BindMode`, not a bare integer."""

from objects.skinned_mesh import BindMode


def main():
    var value: BindMode = 0
    _ = value.is_valid()
