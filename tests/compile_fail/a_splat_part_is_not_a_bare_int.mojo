# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""A bare integer must not stand in for an array of a splat scan."""

from window.splat_app import SplatApp


def ask(app: SplatApp) -> Tuple[Int, Int]:
    return app.part(3)


def main() raises:
    print("unreachable")
