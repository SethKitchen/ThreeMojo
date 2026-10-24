# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""A gamepad mapping kind must be a `MappingKind`, not a bare integer."""

from extensions.gamepad.mapping import MappingKind


def main():
    var value: MappingKind = 0
    _ = value.is_valid()
