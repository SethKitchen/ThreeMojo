# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""A MODFLOW `LinearAcceleration` is a type, not a bare integer."""

from extensions.groundwater.kinds import LinearAcceleration


def main():
    var kind: LinearAcceleration = 0
    _ = kind.is_valid()
