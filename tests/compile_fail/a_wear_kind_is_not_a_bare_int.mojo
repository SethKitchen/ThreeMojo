# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""A wear kind must be a `WearKind`, not a bare integer."""

from extensions.attire.kinds import require_wear_kind


def main() raises:
    require_wear_kind(1)
