# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""A bare integer must not stand in for a Draco encoding."""

from loaders.draco import DRACO_SEQUENTIAL


def main() raises:
    var encoding = DRACO_SEQUENTIAL
    encoding = 1
    print(encoding.is_valid())
