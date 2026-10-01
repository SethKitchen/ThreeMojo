# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""A walker state must be a `WalkerState`, not a bare integer."""

from extensions.carla.navigation import WalkerInfo


def main() raises:
    var info = WalkerInfo()
    info.state = 1
    print(info.state.value)
