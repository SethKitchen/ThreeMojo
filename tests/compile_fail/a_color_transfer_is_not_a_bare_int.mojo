# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""A bare integer must not stand in for a transfer function."""

from render.color_spaces import SRGB_TRANSFER, ColorTransfer


def main() raises:
    var transfer: ColorTransfer = 1
    print(transfer == SRGB_TRANSFER)
