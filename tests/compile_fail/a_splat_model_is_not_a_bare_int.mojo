# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""A splat model must be a `SplatModel`, not a bare integer."""

from extensions.scan.scene import SplatModel


def main():
    var kind: SplatModel = 0
    _ = kind.is_valid()
