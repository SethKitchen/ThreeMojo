# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""A flow scheme must be a `ConvectionScheme`, not a bare integer."""

from extensions.cfd.kinds import ConvectionScheme


def main():
    var scheme: ConvectionScheme = 0
    _ = scheme.is_valid()
