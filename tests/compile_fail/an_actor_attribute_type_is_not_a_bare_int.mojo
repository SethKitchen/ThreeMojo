# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""An attribute type must be an `ActorAttributeType`, not a bare integer."""

from extensions.carla.blueprint import ATTRIBUTE_FLOAT, ActorAttribute


def main() raises:
    var a = ActorAttribute("fov", 2, ["90.0"])
    print(a.value)
