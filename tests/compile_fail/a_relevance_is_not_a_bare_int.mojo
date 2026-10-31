# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""A relevance must be a `Relevance`, not a bare integer."""

from extensions.village.netcode import heard


def main() raises:
    print(heard(0, 1, 2))
