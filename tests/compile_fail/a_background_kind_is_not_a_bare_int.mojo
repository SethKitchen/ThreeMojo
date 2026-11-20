# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""A background kind must be a `BackgroundKind`, not a bare integer."""

from core.background import BackgroundKind


def main():
    var value: BackgroundKind = 0
    _ = value.is_valid()
