# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""A controller id must be a `ControllerId`, not a bare string."""

from extensions.carla.map import Controller


def main() raises:
    var controller = Controller(String("1"), "ctrl", 0)
    print(controller.name)
