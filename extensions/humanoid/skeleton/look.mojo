# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Phong stand-ins for cartilage, meniscus, ligament, muscle and tendon.

The maps are visual approximations. MeshStandardMaterial is not ported,
so these surfaces are what the current renderer can draw.

    var paint = cartilage_phong()
"""

from materials.material import DOUBLE_SIDE, Material, phong_material
from render.framebuffer import Color


def cartilage_phong() raises -> Material:
    """Return a Phong material for articular cartilage.

    The color is pearlescent glistening white/ivory, like wet hyaline cartilage.
    The surface is double-sided and opaque so it reads as tissue instead of colored glass.

    Returns:
        A `PHONG` material.

    Raises:
        Error: If the Phong constructor refuses the values.
    """
    return phong_material(
        Color(240, 242, 245),
        specular=Color(255, 255, 255),
        shininess=36.0,
        side=DOUBLE_SIDE,
    )


def meniscus_phong() raises -> Material:
    """Return a Phong material for a meniscus.

    The color is natural fibrocartilaginous off-white / light cream. Shininess is low.

    Returns:
        A `PHONG` material.

    Raises:
        Error: If the Phong constructor refuses the values.
    """
    return phong_material(
        Color(230, 226, 215),
        specular=Color(140, 135, 125),
        shininess=12.0,
    )


def ligament_phong() raises -> Material:
    """Return a Phong material for a collateral ligament.

    The color is pale fibrous silvery-tan connective tissue. Shininess is low.

    Returns:
        A `PHONG` material.

    Raises:
        Error: If the Phong constructor refuses the values.
    """
    return phong_material(
        Color(228, 222, 206),
        specular=Color(160, 155, 140),
        shininess=16.0,
    )


def muscle_phong() raises -> Material:
    """Return a Phong material for skeletal muscle.

    The color is red muscle belly, like dissected skeletal muscle.

    Returns:
        A `PHONG` material.

    Raises:
        Error: If the Phong constructor refuses the values.
    """
    return phong_material(
        Color(168, 58, 48),
        specular=Color(96, 42, 36),
        shininess=10.0,
    )


def tendon_phong() raises -> Material:
    """Return a Phong material for tendon and fascia.

    The color is pale fibrous connective tissue.

    Returns:
        A `PHONG` material.

    Raises:
        Error: If the Phong constructor refuses the values.
    """
    return phong_material(
        Color(214, 200, 176),
        specular=Color(150, 140, 124),
        shininess=18.0,
    )
