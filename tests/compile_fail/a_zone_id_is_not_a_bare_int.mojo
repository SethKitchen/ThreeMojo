# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""A zone id must be a `ZoneId`, not a bare integer."""

from extensions.energy.ids import ZoneId


def main():
    var id: ZoneId = 0
    _ = id.is_valid()
