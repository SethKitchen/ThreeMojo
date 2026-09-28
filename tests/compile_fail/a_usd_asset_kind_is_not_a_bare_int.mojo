# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""A bare integer must not stand in for the kind of a file of a USDZ
archive."""

from loaders.usd_composer import UsdAssets
from loaders.usd_specs import UsdLayer


def main() raises:
    var assets = UsdAssets()
    assets.add("a.png", 0, List[UInt8](), UsdLayer())
    print(len(assets.names))
