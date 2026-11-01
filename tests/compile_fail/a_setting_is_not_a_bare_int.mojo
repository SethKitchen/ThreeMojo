# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""A setting must be a `Setting`, not a bare integer."""

from extensions.chemistry.kinds import Setting


def main():
    var setting: Setting = 0
    _ = setting.is_valid()
