# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Phong stand-ins for knee cartilage, meniscus and ligament.

The maps are visual approximations. MeshStandardMaterial is not ported,
so these surfaces are what the current renderer can draw.

    var paint = cartilage_phong()
"""

from materials.material import DOUBLE_SIDE, Material, phong_material
from render.framebuffer import Color


def cartilage_phong() raises -> Material:
    """Return a Phong material for articular cartilage.

    The color is a warm ivory, like wet hyaline cartilage. The surface is
    double-sided and opaque so it reads as tissue instead of colored glass.

    Returns:
        A `PHONG` material.

    Raises:
        Error: If the Phong constructor refuses the values.
    """
    return phong_material(
        Color(228, 225, 210),
        specular=Color(238, 235, 220),
        shininess=26.0,
        side=DOUBLE_SIDE,
    )


def meniscus_phong() raises -> Material:
    """Return a Phong material for a meniscus.

    The color is natural off-white fibrocartilage. Shininess is low.

    Returns:
        A `PHONG` material.

    Raises:
        Error: If the Phong constructor refuses the values.
    """
    return phong_material(
        Color(205, 199, 181),
        specular=Color(128, 122, 110),
        shininess=10.0,
    )


def ligament_phong() raises -> Material:
    """Return a Phong material for a collateral ligament.

    The color is pale fibrous connective tissue. Shininess is low.

    Returns:
        A `PHONG` material.

    Raises:
        Error: If the Phong constructor refuses the values.
    """
    return phong_material(
        Color(226, 214, 180),
        specular=Color(110, 102, 86),
        shininess=8.0,
    )
