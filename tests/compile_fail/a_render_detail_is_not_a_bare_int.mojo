# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""A render detail must be a `RenderDetail`, not a bare integer."""

from extensions.building.views.render import RenderDetail


def main():
    var detail: RenderDetail = 1
    _ = detail.is_valid()
