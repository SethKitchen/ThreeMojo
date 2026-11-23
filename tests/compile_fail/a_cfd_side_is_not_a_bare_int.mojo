# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""A flow side must be a `Side`, not a bare integer."""

from extensions.cfd.kinds import Side


def main():
    var side: Side = 0
    _ = side.is_valid()
