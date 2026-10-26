# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""A scan format must be a `ScanFormat`, not a bare integer."""

from extensions.scan.files import ScanFormat


def main():
    var kind: ScanFormat = 0
    _ = kind.is_valid()
