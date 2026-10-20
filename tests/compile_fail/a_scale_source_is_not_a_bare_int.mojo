# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""A scale source must be a `ScaleSource`, not a bare integer."""

from extensions.scan.frame import ScaleSource


def main():
    var kind: ScaleSource = 0
    _ = kind.is_valid()
