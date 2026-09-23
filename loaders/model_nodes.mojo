# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""What the Collada and FBX loaders share: a node set from a matrix, a
color read as authored, and a texture read from an image file.

Both formats describe a node's transform as a matrix, one built from a
list of steps. three.js keeps the matrix and splits it into a position,
a rotation and a scale with `Matrix4.decompose`, and a node here holds
the same three, so `decompose_onto` is that split. `compose` is the other
way, three.js's `Matrix4.compose`: what the node's matrix is once the
split is put back together, which drops any shear the matrix had.
"""

from core.object3d import Object3D
from loaders.gltf import decode_image
from math.matrix4 import Matrix4
from math.quaternion import Quaternion
from math.vector3 import Vector3
from render.framebuffer import Color, FloatColor
from render.srgb import ColorSpace
from render.texture import Alpha, BILINEAR, Texture, Wrap, texture_from
from std.math import isfinite, sqrt
from std.pathlib import Path


def _column_length(matrix: Matrix4, start: Int) -> Float32:
    """Return the length of a column's first three entries."""
    ref e = matrix.elements
    return sqrt(
        e[start] * e[start]
        + e[start + 1] * e[start + 1]
        + e[start + 2] * e[start + 2]
    )


def decompose_onto(mut node: Object3D, matrix: Matrix4, what: String) raises:
    """Set a node's position, rotation and scale from a matrix, as
    three.js's `Matrix4.decompose` splits it.

    The scale is each column's length, the first negated when the
    determinant is negative. The rotation is what is left once each
    column is divided by its scale. The position is the last column.

    Args:
        node: The node to set.
        matrix: The transform relative to the node's parent.
        what: The format, to begin the error with.

    Raises:
        Error: If an entry is not finite, or the matrix flattens an axis,
            where three.js would divide by zero.
    """
    if not matrix.is_finite():
        raise Error(what + ": a node matrix that is not finite")
    var sx = _column_length(matrix, 0)
    var sy = _column_length(matrix, 4)
    var sz = _column_length(matrix, 8)
    if matrix.determinant() < 0:
        sx = -sx
    if sx == 0 or sy == 0 or sz == 0:
        raise Error(what + ": a node matrix that flattens an axis")
    ref e = matrix.elements
    var rotation = Matrix4()
    for row in range(3):  # pragma: no branch
        rotation.elements[row] = e[row] / sx
        rotation.elements[4 + row] = e[4 + row] / sy
        rotation.elements[8 + row] = e[8 + row] / sz
    node.set_position(e[12], e[13], e[14])
    node.set_quaternion(Quaternion.from_matrix(rotation))
    node.set_scale(sx, sy, sz)


def compose(node: Object3D) -> Matrix4:
    """Return the matrix a node's position, rotation and scale make,
    three.js's `Matrix4.compose`.

    Args:
        node: The node.

    Returns:
        Translation times rotation times scale.
    """
    var matrix = node.quaternion.to_matrix()
    ref e = matrix.elements
    for row in range(3):  # pragma: no branch
        e[row] *= node.scale.x
        e[4 + row] *= node.scale.y
        e[8 + row] *= node.scale.z
    e[12] = node.position.x
    e[13] = node.position.y
    e[14] = node.position.z
    return matrix^


def authored_color(
    r: Float64, g: Float64, b: Float64, what: String
) raises -> Color:
    """Return the eight-bit color three numbers name, as authored in sRGB.

    Both formats write a color as numbers from zero to one in sRGB, and
    three.js reads them with `ColorManagement.colorSpaceToWorking` from
    sRGB. A `Color` here holds a color as authored, so the numbers are
    rounded to bytes and not decoded.

    Args:
        r: Red, from zero to one.
        g: Green, from zero to one.
        b: Blue, from zero to one.
        what: The format, to begin the error with.

    Returns:
        The nearest eight-bit color.

    Raises:
        Error: If a number is not finite or is outside zero to one.
    """
    for channel in [r, g, b]:  # pragma: no branch
        if not isfinite(channel) or channel < 0 or channel > 1:
            raise Error(
                what
                + ": a color channel must be from zero to one, not "
                + String(channel)
            )
    return FloatColor(Float32(r), Float32(g), Float32(b), 1).quantize()


def texture_from_bytes(
    bytes: List[UInt8], space: ColorSpace, wrap: Wrap, alpha: Alpha
) raises -> Texture:
    """Return a texture decoded from a PNG, a JPEG or a TGA file's bytes.

    The texture repeats or clamps as asked, filters bilinearly and reads
    a mipmap chain, which is what three.js's `TextureLoader` gives.

    Args:
        bytes: The image file.
        space: `SRGB` for a color map, `LINEAR` for a data map.
        wrap: How coordinates outside the unit square are resolved.
        alpha: `COVERAGE` for a color map whose alpha cuts the surface,
            `IGNORED` for any other.

    Returns:
        The texture.

    Raises:
        Error: If the bytes are not an image `decode_image` reads.
    """
    return texture_from(decode_image(bytes), wrap, BILINEAR, space, True, alpha)


def texture_from_file(
    path: String, space: ColorSpace, wrap: Wrap, alpha: Alpha
) raises -> Texture:
    """Return a texture read from an image file.

    Args:
        path: The file.
        space: `SRGB` for a color map, `LINEAR` for a data map.
        wrap: How coordinates outside the unit square are resolved.
        alpha: `COVERAGE` for a color map whose alpha cuts the surface,
            `IGNORED` for any other.

    Returns:
        The texture.

    Raises:
        Error: If the file cannot be read or is not an image
            `decode_image` reads.
    """
    return texture_from_bytes(Path(path).read_bytes(), space, wrap, alpha)
