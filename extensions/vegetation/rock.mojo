# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""A boulder: a sphere pushed in and out by noise, with moss on top.

The boulder starts as an icosahedron cut toward a sphere. Each vertex
moves along its direction by two octaves of simplex noise, and the lower
part is squashed flat, so the stone sits on the ground. The geometry has
no index, so each face is lit by its own normal and the stone looks cut.

The color is gray stone, with moss where a face looks up and dark where
it is low, near the ground the stone sits in.
"""

from core.buffer_attribute import BufferAttribute
from core.buffer_geometry import COLOR, POSITION, BufferGeometry
from extensions.vegetation.checks import (
    require_between,
    require_count_between,
)
from geometries.polyhedron import icosahedron
from math.noise import SimplexNoise
from math.utils import SeededRandom
from units.si import METER, Length

# How far the noise moves a vertex, as a fraction of the radius.
comptime ROUGHNESS = Float32(0.32)
# The fraction of the radius below the middle where the stone is cut flat.
comptime FOOT = Float32(0.35)


def boulder(radius: Length, detail: Int, seed: Int) raises -> BufferGeometry:
    """Return a boulder that sits on y equals zero.

    Args:
        radius: How big the stone is, from 1 centimeter to 100 meters.
        detail: How finely the sphere is cut, from 1 to 5.
        seed: Which stone to grow.

    Returns:
        A geometry with no index, with `position`, `normal` and `color`.

    Raises:
        Error: If `radius` or `detail` is out of range.
    """
    require_between(
        radius.to(METER),
        0.01,
        100,
        "A boulder must be from 1 centimeter to 100 meters across",
    )
    require_count_between(
        detail, 1, 5, "A boulder's detail must be from 1 to 5"
    )
    var size = radius.to(METER)
    var shape = icosahedron(Length(1.0, METER), detail).to_non_indexed()
    var random = SeededRandom(seed)
    var noise = SimplexNoise(random)
    ref sphere = shape.attribute_view(String(POSITION))
    var count = sphere.count()
    var positions = List[Float32]()
    positions.reserve(3 * count)
    for v in range(count):  # pragma: no branch
        var p = sphere.vector3(v)
        var push = (
            noise.noise3d(
                Float64(p.x) * 1.3, Float64(p.y) * 1.3, Float64(p.z) * 1.3
            )
            * 0.7
            + noise.noise3d(
                Float64(p.x) * 3.1, Float64(p.y) * 3.1, Float64(p.z) * 3.1
            )
            * 0.3
        )
        var scale = size * (1 + ROUGHNESS * Float32(push))
        var y = max(p.y * scale * 0.72, -FOOT * size)
        positions.append(p.x * scale)
        positions.append(y + FOOT * size)
        positions.append(p.z * scale)
    var rock = BufferGeometry()
    rock.set_attribute(POSITION, BufferAttribute(positions^, 3))
    rock.compute_vertex_normals()
    ref normals = rock.attribute_view(String("normal"))
    ref placed = rock.attribute_view(String(POSITION))
    var colors = List[Float32]()
    colors.reserve(3 * count)
    for v in range(count):  # pragma: no branch
        var up = normals.vector3(v).y
        var low = min(Float32(1), placed.vector3(v).y / (size * 0.6))
        var moss = max(Float32(0), up - 0.55) * 1.6
        var dark = 0.45 + 0.55 * low
        colors.append((0.16 - 0.08 * moss) * dark)
        colors.append((0.15 + 0.02 * moss) * dark)
        colors.append((0.13 - 0.08 * moss) * dark)
    rock.set_attribute(COLOR, BufferAttribute(colors^, 3))
    return rock^
