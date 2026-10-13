# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""A load kind must be a `LoadKind`, not a bare integer."""

from extensions.geotech.loads import service_i


def main() raises:
    _ = service_i().of(4)
