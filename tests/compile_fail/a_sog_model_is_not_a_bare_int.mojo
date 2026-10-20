# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""A SOG model must be a `SogModel`, not a bare integer."""

from extensions.scan.sog import SogModel


def main():
    var kind: SogModel = 0
    _ = kind.is_valid()
