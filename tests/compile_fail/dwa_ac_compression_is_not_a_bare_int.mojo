# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""DWA AC compression cannot be a bare integer."""

from render.exr import _DwaAcCompression


def main():
    var mode: _DwaAcCompression = 1
    print(mode.value)
