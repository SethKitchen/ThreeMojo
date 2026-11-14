# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""A molecule atom id must be an `AtomId`, not a bare integer."""

from extensions.molecule.structure import Structure


def main() raises:
    Structure("X").require_atom(0)
