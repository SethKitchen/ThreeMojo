# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""A requirement check must be a `Check`, not a bare integer."""

from extensions.chemistry.kinds import Check


def main():
    var check: Check = 0
    _ = check.is_valid()
