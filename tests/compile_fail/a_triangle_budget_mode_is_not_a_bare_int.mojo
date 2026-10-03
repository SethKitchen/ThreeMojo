# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""A triangle-budget mode must be a typed value, not a bare integer."""

from core.assets import Assets
from core.scene import Scene
from extensions.humanoid.skeleton.simplify import fit_triangle_budget_result


def main() raises:
    var assets = Assets()
    var scene = Scene()
    _ = fit_triangle_budget_result(scene, assets, 0, 1, mode=0)
