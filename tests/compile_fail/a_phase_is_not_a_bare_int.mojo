# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""A phase must be a `Phase`, not a bare integer."""

from extensions.chemistry.kinds import Phase


def main():
    var phase: Phase = 0
    _ = phase.is_valid()
