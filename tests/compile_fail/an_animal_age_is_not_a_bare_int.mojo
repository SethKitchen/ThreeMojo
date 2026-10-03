# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""An animal age must be an `Age`, not a bare integer."""

from extensions.animals.traits import pick_age


def main() raises:
    _ = pick_age(0)
