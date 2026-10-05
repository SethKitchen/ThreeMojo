# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""A member id must be a `MemberId`, not a bare integer."""

from extensions.structure.ids import MemberId


def main():
    var id: MemberId = 0
    _ = id.is_valid()
