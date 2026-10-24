# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""A HIDAPI driver must be a `HidDriverKind`, not a bare integer."""

from extensions.gamepad.hidapi import HidDriverKind


def main():
    var value: HidDriverKind = 0
    _ = value.is_valid()
