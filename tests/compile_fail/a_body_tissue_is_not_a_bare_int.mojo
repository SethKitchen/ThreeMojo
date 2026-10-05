# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""A tissue must be a `BodyTissue`, not a bare integer."""

from extensions.animals.anatomy.density import tissue_density


def main() raises:
    print(tissue_density(2).value)
