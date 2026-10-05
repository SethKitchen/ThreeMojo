# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""An animal quality tier must be a `Quality`, not a bare integer."""

from extensions.animals.options import animal_options


def main() raises:
    _ = animal_options(1, quality=0)
