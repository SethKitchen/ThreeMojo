# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""A gamepad device change must be a `DeviceChangeKind`, not a bare integer."""

from extensions.gamepad.linux import DeviceChangeKind


def main():
    var value: DeviceChangeKind = 0
    _ = value.is_valid()
