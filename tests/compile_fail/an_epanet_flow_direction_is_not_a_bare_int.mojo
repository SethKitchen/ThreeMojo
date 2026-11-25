# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""An EPANET flow direction must be a `FlowDirection`, not a bare integer."""

from extensions.epanet.kinds import FlowDirection


def main():
    var kind: FlowDirection = 0
    _ = kind.is_valid()
