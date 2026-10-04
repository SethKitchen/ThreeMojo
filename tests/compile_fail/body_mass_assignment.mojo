# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""A body mass-state accessor cannot be assigned directly."""

from extensions.physics.body import DYNAMIC, RigidBody
from math.matrix3 import Matrix3


def reject(mut body: RigidBody):
    body.mass = 0


def main():
    pass
