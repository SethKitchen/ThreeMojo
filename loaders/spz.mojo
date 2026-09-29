# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""`.spz` files, Niantic's compressed Gaussian splats, from three.js
`examples/jsm/loaders/SPZLoader.js`.

**Versions 1 to 3** are gzip files. Inside is a 16-byte header -- the magic
`NGSP`, the version, the splat count, the spherical harmonics degree, the
fractional bits of a center and the flags -- and then the splats' fields,
each for every splat in turn: centers, opacities, colors, scales,
rotations and harmonics, and, when the flags have `SPZ_FLAG_LOD`, six
bytes a splat that are skipped.

- A center is three half floats in version 1, and three 24-bit signed
  fixed-point numbers with the header's fractional bits after that.
- An opacity is one byte, kept as the color's fourth byte.
- A color channel is one byte, `(byte / 255 - 0.5) * SH_C0 / 0.15 + 0.5`.
- A scale is one byte, `exp(byte / 16 - 10)`.
- A rotation is three bytes, `x`, `y` and `z` each `byte / 127.5 - 1`
  and `w` what makes it unit length, before version 3. From version 3 it
  is one little-endian word, the smallest three: the top two bits name
  the largest component, and three 10-bit sign-and-magnitude numbers of
  up to `sqrt(1/2)` are the others, the lowest bits the last of them.
- The harmonics are one byte a number, band after band, coefficient by
  coefficient and channel by channel within a band, as a band's bytes
  hold them. Degree 4 is read past; only the bands up to 3 are kept.

The gzip is read by `loaders.nrrd.gunzip`, which is fflate's `gunzipSync`.

**Version 4** is not gzipped. Its header starts `NGSP`, version 4, and
gives the count, the degree, the fractional bits, the flags, the number
of streams and where their table of contents is. Each field above is one
Zstandard stream, read by `render.zstd`; a field with no bytes has none.
Vendor extensions, flag `SPZ_FLAG_EXTENSIONS`, are skipped, as three.js
skips them.

A file with a bad magic, a version or a degree that is not supported, or
a length that is not what its header says is refused. A version 4 file
whose table or streams are past its end, or whose streams do not hold
what the header says, is refused too.
"""

from core.gaussian_splat_utils import (
    GaussianSplatGeometry,
    SH_C0,
    clamped_byte,
    create_gaussian_splat_geometry,
    packed_band,
    sh_band_components,
    sh_band_words,
    write_covariance,
)
from loaders.nrrd import gunzip
from loaders.splat import le_u16, le_u32
from render.data_utils import from_half_float
from render.zstd import zstd_decompress
from std.math import exp, max, min, sqrt
from std.pathlib import Path

# `NGSP`, little-endian.
comptime SPZ_MAGIC = 0x5053474E
comptime SPZ_HEADER_BYTES = 16
# The flag that adds six bytes a splat of levels of detail.
comptime SPZ_FLAG_LOD = 0x80
# The flag that says a version 4 file carries vendor extensions.
comptime SPZ_FLAG_EXTENSIONS = 0x02
# The most splats a file is read with, as `MAX_KSPLAT_SPLATS`.
comptime MAX_SPZ_SPLATS = 10000000


def spz_vectors(degree: Int) raises -> Int:
    """Return how many harmonics coefficients a splat of a degree stores,
    three.js's `SH_DEGREE_TO_VECTORS`.

    Args:
        degree: The header's degree.

    Returns:
        0, 3, 8, 15 or 24.

    Raises:
        Error: If the degree is outside 0 through 4.
    """
    if degree < 0 or degree > 4:
        raise Error(
            "SPZ: unsupported SPZ spherical harmonics degree " + String(degree)
        )
    return (degree + 1) * (degree + 1) - 1


def spz_color(byte: UInt8) -> UInt8:
    """Return the color byte a stored one stands for, three.js's
    `COLOR_LUT`.

    Args:
        byte: The stored byte.

    Returns:
        `((byte / 255 - 0.5) * SH_C0 / 0.15 + 0.5) * 255`, clamped.
    """
    var scale = SH_C0 / 0.15
    return clamped_byte(((Float64(byte) / 255 - 0.5) * scale + 0.5) * 255)


def spz_scale(byte: UInt8) -> Float64:
    """Return the scale a stored byte stands for, three.js's `SCALE_LUT`,
    kept as a 32-bit float as the table keeps it.

    Args:
        byte: The stored byte.

    Returns:
        `exp(byte / 16 - 10)`.
    """
    return Float64(Float32(exp(Float64(byte) / 16 - 10)))


def spz_quaternion_component(code: Int) -> Float64:
    """Return one of the smallest three a 10-bit code stands for, three.js's
    `QUAT_COMPONENT_LUT`.

    Args:
        code: The ten bits: the sign, then nine of magnitude.

    Returns:
        `sqrt(1/2) * magnitude / 511`, negative when the sign bit is set.
    """
    var value = sqrt(Float64(0.5)) * (Float64(code & 511) / 511)
    if (code & 512) != 0:
        return -value
    return value


def smallest_three(packed: Int) -> Tuple[Float64, Float64, Float64, Float64]:
    """Return the rotation a version 3 word stands for, three.js's
    `readSmallestThreeQuaternion`.

    Args:
        packed: The word.

    Returns:
        The quaternion's x, y, z and w.
    """
    var largest = (packed >> 30) & 3
    var a = spz_quaternion_component(packed & 1023)
    var b = spz_quaternion_component((packed >> 10) & 1023)
    var c = spz_quaternion_component((packed >> 20) & 1023)
    var rest = sqrt(max(Float64(0), 1 - (a * a + b * b + c * c)))
    if largest == 0:
        return (rest, c, b, a)
    if largest == 1:
        return (c, rest, b, a)
    if largest == 2:
        return (c, b, rest, a)
    return (c, b, a, rest)


def _int24(bytes: List[UInt8], at: Int) -> Int:
    """Return a little-endian 24-bit signed integer.

    Args:
        bytes: The data.
        at: Where it starts.

    Returns:
        The integer, its top bit its sign.
    """
    var value = (
        Int(bytes[at]) | (Int(bytes[at + 1]) << 8) | (Int(bytes[at + 2]) << 16)
    )
    if value >= 1 << 23:
        return value - (1 << 24)
    return value


@fieldwise_init
struct _Fields(Movable):
    """A file's fields, each for every splat, and what reads them."""

    var positions: List[UInt8]
    var alphas: List[UInt8]
    var colors: List[UInt8]
    var scales: List[UInt8]
    var rotations: List[UInt8]
    var harmonics: List[UInt8]
    var count: Int
    var version: Int
    var fractional_bits: Int
    var degree: Int
    var stored_degree: Int


def parse_spz(bytes: List[UInt8]) raises -> GaussianSplatGeometry:
    """Read a `.spz` file's bytes, three.js's `SPZLoader.parse`.

    Args:
        bytes: The whole file: gzip for versions 1 to 3, or version 4 as
            it is.

    Returns:
        The splats; see the module docstring.

    Raises:
        Error: If the file starts with the magic and is not version 4, the
            gzip is refused, or anything `parse_raw_spz` or
            `parse_raw_spz_v4` raises.
    """
    if len(bytes) >= 8 and le_u32(bytes, 0) == SPZ_MAGIC:
        var version = le_u32(bytes, 4)
        if version != 4:
            raise Error(
                "SPZ: SPZ version " + String(version) + " is not supported"
            )
        return parse_raw_spz_v4(bytes)
    return parse_raw_spz(gunzip(bytes))


def parse_raw_spz(bytes: List[UInt8]) raises -> GaussianSplatGeometry:
    """Read the bytes inside a version 1 to 3 file's gzip, three.js's
    `parseRawSPZ`.

    Args:
        bytes: The decompressed file.

    Returns:
        The splats.

    Raises:
        Error: If the header is short, the magic is not `NGSP`, the version
            is not 1 to 3, the degree is above 4, or the length is not what
            the header says.
    """
    if len(bytes) < SPZ_HEADER_BYTES:
        raise Error("SPZ: invalid SPZ header")
    var version = le_u32(bytes, 4)
    var count = le_u32(bytes, 8)
    var stored = Int(bytes[12])
    if le_u32(bytes, 0) != SPZ_MAGIC:
        raise Error("SPZ: invalid SPZ magic")
    if version < 1 or version > 3:
        raise Error("SPZ: SPZ version " + String(version) + " is not supported")
    if count > MAX_SPZ_SPLATS:
        raise Error("SPZ: the file holds too many splats")
    var vectors = spz_vectors(stored)
    var positions = count * 3 * (2 if version == 1 else 3)
    var rotations = count * (4 if version == 3 else 3)
    var harmonics = count * vectors * 3
    var lod = count * 6 if (Int(bytes[14]) & SPZ_FLAG_LOD) != 0 else 0
    var expected = (
        SPZ_HEADER_BYTES + positions + count * 7 + rotations + harmonics + lod
    )
    if len(bytes) != expected:
        raise Error("SPZ: invalid SPZ byte length")
    var at = SPZ_HEADER_BYTES
    var fields = _Fields(
        _cut(bytes, at, positions),
        _cut(bytes, at + positions, count),
        _cut(bytes, at + positions + count, count * 3),
        _cut(bytes, at + positions + count * 4, count * 3),
        _cut(bytes, at + positions + count * 7, rotations),
        _cut(bytes, at + positions + count * 7 + rotations, harmonics),
        count,
        version,
        Int(bytes[13]),
        min(stored, 3),
        stored,
    )
    return _attributes(fields)


def _cut(bytes: List[UInt8], start: Int, length: Int) -> List[UInt8]:
    """Return a run of bytes.

    Args:
        bytes: The data.
        start: Where the run starts.
        length: How long it is. The caller checks it is inside.

    Returns:
        A copy of the run.
    """
    var out = List[UInt8](capacity=length)
    for at in range(start, start + length):
        out.append(bytes[at])
    return out^


def parse_raw_spz_v4(bytes: List[UInt8]) raises -> GaussianSplatGeometry:
    """Read a version 4 file, three.js's `parseRawSPZV4`.

    Args:
        bytes: The whole file.

    Returns:
        The splats.

    Raises:
        Error: If the header or the table is past the end, the degree is
            above 4, the count is above `MAX_SPZ_SPLATS`, there are fewer
            streams than fields with bytes, a stream is past the end or
            does not decompress to its field's length, or anything
            `render.zstd.zstd_decompress` raises.
    """
    if len(bytes) < 20:
        raise Error("SPZ: invalid SPZ header")
    if le_u32(bytes, 0) != SPZ_MAGIC:
        raise Error("SPZ: invalid SPZ magic")
    if le_u32(bytes, 4) != 4:
        raise Error("SPZ: the raw SPZ parser requires version 4")
    var count = le_u32(bytes, 8)
    var stored = Int(bytes[12])
    var streams = Int(bytes[15])
    var table = le_u32(bytes, 16)
    if count > MAX_SPZ_SPLATS:
        raise Error("SPZ: the file holds too many splats")
    var sizes: List[Int] = [
        count * 9,
        count,
        count * 3,
        count * 3,
        count * 4,
        count * spz_vectors(stored) * 3,
    ]
    if table < 20 or table > len(bytes) or streams * 16 > len(bytes) - table:
        raise Error("SPZ: the SPZ table of contents is past the end")
    var fields = List[List[UInt8]]()
    var start = table + streams * 16
    var used = 0
    for field in range(len(sizes)):  # pragma: no branch
        if sizes[field] == 0:
            fields.append(List[UInt8]())
            continue
        if used >= streams:
            raise Error("SPZ: the file has too few SPZ streams")
        var length = UInt64(le_u32(bytes, table + used * 16)) | (
            UInt64(le_u32(bytes, table + used * 16 + 4)) << 32
        )
        if length > UInt64(len(bytes) - start):
            raise Error("SPZ: an SPZ stream is past the end")
        var stream = zstd_decompress(
            _cut(bytes, start, Int(length)), sizes[field]
        )
        if len(stream) != sizes[field]:
            raise Error("SPZ: an SPZ stream does not hold its field")
        fields.append(stream^)
        start += Int(length)
        used += 1
    var parts = _Fields(
        fields.pop(0),
        fields.pop(0),
        fields.pop(0),
        fields.pop(0),
        fields.pop(0),
        fields.pop(0),
        count,
        4,
        Int(bytes[13]),
        min(stored, 3),
        stored,
    )
    return _attributes(parts)


def _attributes(fields: _Fields) raises -> GaussianSplatGeometry:
    """Make the splats from a file's fields, three.js's
    `parseSPZAttributes`.

    Args:
        fields: The fields.

    Returns:
        The splats.

    Raises:
        Error: Never, for fields of the lengths the header gives.
    """
    var count = fields.count
    var centers = _centers(fields)
    var covariances = List[Float32](length=count * 6, fill=0)
    var colors = List[UInt8](capacity=count * 4)
    for index in range(count):
        var i3 = index * 3
        var turn = _rotation(fields, index)
        write_covariance(
            covariances,
            index * 6,
            spz_scale(fields.scales[i3]),
            spz_scale(fields.scales[i3 + 1]),
            spz_scale(fields.scales[i3 + 2]),
            turn[0],
            turn[1],
            turn[2],
            turn[3],
        )
        colors.append(spz_color(fields.colors[i3]))
        colors.append(spz_color(fields.colors[i3 + 1]))
        colors.append(spz_color(fields.colors[i3 + 2]))
        colors.append(fields.alphas[index])
    var bands = List[List[UInt8]]()
    for degree in range(1, 4):  # pragma: no branch
        if degree <= fields.degree:
            bands.append(_band(fields, degree))
        else:
            bands.append(List[UInt8]())
    return create_gaussian_splat_geometry(
        centers^,
        covariances^,
        colors^,
        bands.pop(0),
        bands.pop(0),
        bands.pop(0),
    )


def _rotation(
    fields: _Fields, index: Int
) -> Tuple[Float64, Float64, Float64, Float64]:
    """Return a splat's rotation.

    Args:
        fields: The fields.
        index: Which splat.

    Returns:
        The quaternion's x, y, z and w.
    """
    if fields.version >= 3:
        return smallest_three(le_u32(fields.rotations, index * 4))
    var at = index * 3
    var x = Float64(fields.rotations[at]) / 127.5 - 1
    var y = Float64(fields.rotations[at + 1]) / 127.5 - 1
    var z = Float64(fields.rotations[at + 2]) / 127.5 - 1
    return (x, y, z, sqrt(max(Float64(0), 1 - x * x - y * y - z * z)))


def _centers(fields: _Fields) -> List[Float32]:
    """Return the splats' centers, three.js's `readCenters`.

    Args:
        fields: The fields.

    Returns:
        Three floats a splat.
    """
    var count = fields.count
    var out = List[Float32](capacity=count * 3)
    if fields.version == 1:
        for at in range(count * 3):
            out.append(
                from_half_float(UInt16(le_u16(fields.positions, at * 2)))
            )
        return out^
    # JavaScript's `1 << bits` is a 32-bit shift by the bits' low five.
    var fixed = 1 / Float64(Int32(1) << Int32(fields.fractional_bits & 31))
    for at in range(count * 3):
        out.append(Float32(Float64(_int24(fields.positions, at * 3)) * fixed))
    return out^


def _band(fields: _Fields, degree: Int) raises -> List[UInt8]:
    """Return one band's bytes, three.js's `readSphericalHarmonics`.

    Args:
        fields: The fields.
        degree: The band, 1 through the fields' degree.

    Returns:
        The band's bytes.

    Raises:
        Error: Never, for a degree of 1 through 3.
    """
    var band = packed_band(fields.count, degree)
    var stride = spz_vectors(fields.stored_degree) * 3
    # The bands below this one come first.
    var skip = spz_vectors(degree - 1) * 3
    var words = sh_band_words(degree) * 4
    for index in range(fields.count):
        var source = index * stride + skip
        for component in range(sh_band_components(degree)):  # pragma: no branch
            band[index * words + component] = fields.harmonics[
                source + component
            ]
    return band^


def read_spz(path: String) raises -> GaussianSplatGeometry:
    """Read a `.spz` file.

    Args:
        path: The file.

    Returns:
        Its splats; see `parse_spz`.

    Raises:
        Error: If the file cannot be read, or anything `parse_spz` raises.
    """
    return parse_spz(Path(path).read_bytes())
