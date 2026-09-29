# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""What stands at a signal must be a `PropKind`, not a bare integer."""

from extensions.carla.props import PropKind


def main():
    var kind: PropKind = 2
    print(kind.is_valid())
