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

    The color is a pale blue, like wet hyaline cartilage. The surface is
    double-sided and partly transparent so the condyles stay visible.

    Returns:
        A `PHONG` material.

    Raises:
        Error: If the Phong constructor refuses the values.
    """
    return phong_material(
        Color(170, 214, 228),
        specular=Color(214, 232, 240),
        shininess=44.0,
        side=DOUBLE_SIDE,
        opacity=0.78,
        transparent=True,
    )


def meniscus_phong() raises -> Material:
    """Return a Phong material for a meniscus.

    The color is cream fibrocartilage. Shininess is low.

    Returns:
        A `PHONG` material.

    Raises:
        Error: If the Phong constructor refuses the values.
    """
    return phong_material(
        Color(228, 208, 168),
        specular=Color(96, 86, 70),
        shininess=16.0,
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
        Color(236, 226, 210),
        specular=Color(88, 80, 70),
        shininess=11.0,
    )
