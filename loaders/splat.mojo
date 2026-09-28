# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""`.splat` files, from three.js `examples/jsm/loaders/SPLATLoader.js`.

The plain Gaussian splat format: no header, and one 32-byte row a splat.

| Bytes | What |
|---|---|
| 0 to 11 | The center, three little-endian floats. |
| 12 to 23 | The scale, three floats. |
| 24 to 27 | Red, green, blue and opacity, one byte each. |
| 28 to 31 | The rotation's w, x, y and z, each `(byte - 128) / 128`. |

`parse_splat` makes a `GaussianSplatGeometry`, the covariance from the
scale and the rotation as `write_covariance` makes it. A file whose length
is not whole rows is refused.

The little-endian readers here are shared by the other splat loaders.
"""

from core.gaussian_splat_utils import (
    GaussianSplatGeometry,
    create_gaussian_splat_geometry,
    write_covariance,
)
from std.memory import bitcast
from std.pathlib import Path

# How many bytes a `.splat` row takes.
comptime SPLAT_ROW_BYTES = 32


def le_u16(bytes: List[UInt8], at: Int) -> Int:
    """Return a little-endian 16-bit unsigned integer.

    Args:
        bytes: The data.
        at: Where the integer starts. The caller checks it is inside.

    Returns:
        The integer.
    """
    return Int(bytes[at]) | (Int(bytes[at + 1]) << 8)


def le_u32(bytes: List[UInt8], at: Int) -> Int:
    """Return a little-endian 32-bit unsigned integer.

    Args:
        bytes: The data.
        at: Where the integer starts. The caller checks it is inside.

    Returns:
        The integer.
    """
    return le_u16(bytes, at) | (le_u16(bytes, at + 2) << 16)


def le_f32(bytes: List[UInt8], at: Int) -> Float32:
    """Return a little-endian 32-bit float.

    Args:
        bytes: The data.
        at: Where the float starts. The caller checks it is inside.

    Returns:
        The float.
    """
    return bitcast[DType.float32](UInt32(le_u32(bytes, at)))


def parse_splat(bytes: List[UInt8]) raises -> GaussianSplatGeometry:
    """Read a `.splat` file's bytes, three.js's `SPLATLoader.parse`.

    Args:
        bytes: The whole file.

    Returns:
        The splats.

    Raises:
        Error: If the length is not a whole number of 32-byte rows.
    """
    if len(bytes) % SPLAT_ROW_BYTES != 0:
        raise Error("SPLAT: invalid .splat byte length")
    var count = len(bytes) // SPLAT_ROW_BYTES
    var centers = List[Float32](capacity=count * 3)
    var covariances = List[Float32](length=count * 6, fill=0)
    var colors = List[UInt8](capacity=count * 4)
    for index in range(count):
        var row = index * SPLAT_ROW_BYTES
        for lane in range(3):  # pragma: no branch
            centers.append(le_f32(bytes, row + lane * 4))
        for lane in range(4):  # pragma: no branch
            colors.append(bytes[row + 24 + lane])
        write_covariance(
            covariances,
            index * 6,
            Float64(le_f32(bytes, row + 12)),
            Float64(le_f32(bytes, row + 16)),
            Float64(le_f32(bytes, row + 20)),
            _unit(bytes[row + 29]),
            _unit(bytes[row + 30]),
            _unit(bytes[row + 31]),
            _unit(bytes[row + 28]),
        )
    return create_gaussian_splat_geometry(centers^, covariances^, colors^)


def _unit(byte: UInt8) -> Float64:
    """Return a rotation byte as the number it stands for.

    Args:
        byte: The byte.

    Returns:
        `(byte - 128) / 128`.
    """
    return (Float64(byte) - 128) / 128


def read_splat(path: String) raises -> GaussianSplatGeometry:
    """Read a `.splat` file.

    Args:
        path: The file.

    Returns:
        Its splats; see `parse_splat`.

    Raises:
        Error: If the file cannot be read, or anything `parse_splat`
            raises.
    """
    return parse_splat(Path(path).read_bytes())
