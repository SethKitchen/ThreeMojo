# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""A limit state must be a `LimitState`, not a bare integer."""

from extensions.castle.kinds import LimitState


def main():
    var id: LimitState = 0
    _ = id.is_valid()
