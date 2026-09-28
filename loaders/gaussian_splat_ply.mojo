# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Gaussian splat PLY files, as the GraphDECO and INRIA 3D Gaussian
Splatting code writes them, from three.js
`examples/jsm/loaders/GaussianSplatPLYLoader.js`.

A splat PLY is a point cloud whose vertices carry the splat's fields:

- `x`, `y` and `z`: the center.
- `scale_0` to `scale_2`: the scale's logarithm, so the scale is
  `exp(scale_i)`.
- `rot_0` to `rot_3`: the rotation's w, x, y and z.
- `f_dc_0` to `f_dc_2`: the zeroth band of the spherical harmonics, read
  as a color by `write_color_bytes_from_sh0`.
- `opacity`: the opacity's logit, so the opacity is `sigmoid(opacity)`.
- `f_rest_0` and on: the higher bands, 0, 9, 24 or 45 of them for degree
  0 to 3, each channel's coefficients together. They are reordered into
  each band's coefficient-by-coefficient bytes, `value * 128 + 128`,
  clamped.

`parse_gaussian_splat_ply` reads the header first, as three.js does: the
text between a leading `ply` and the first `end_header`. Every
`property type name` line of any element is a property, and the
`f_rest_N` ones are counted. The file is then read by `loaders.ply` with
the fields as custom attributes, three.js's `setCustomPropertyNameMapping`.

A file with no header, without one of the fields above, or with a count
of `f_rest` properties that is not 0, 9, 24 or 45 is refused, as is
anything `loaders.ply.parse_ply` refuses.
"""

from core.buffer_geometry import POSITION
from core.gaussian_splat_utils import (
    GaussianSplatGeometry,
    clamped_byte,
    create_gaussian_splat_geometry,
    packed_band,
    sh_band_components,
    sh_band_words,
    sigmoid,
    write_color_bytes_from_sh0,
    write_covariance,
)
from loaders.ply import PlyOptions, parse_ply
from std.math import exp
from std.pathlib import Path

# The most bytes the header is looked for in, as three.js's scan.
comptime PLY_HEADER_SCAN = 1024 * 1024


def _names(prefix: String, count: Int) -> List[String]:
    """Return numbered property names.

    Args:
        prefix: The name before the number, such as `scale_`.
        count: How many.

    Returns:
        `prefix0` up to `prefix{count - 1}`.
    """
    var out = List[String]()
    for index in range(count):  # pragma: no branch
        out.append(prefix + String(index))
    return out^


def _required() -> List[String]:
    """Return the properties a splat PLY must declare, three.js's
    `REQUIRED_PLY_PROPERTIES`.

    Returns:
        The names.
    """
    var out: List[String] = ["x", "y", "z"]
    out.extend(_names("scale_", 3))
    out.extend(_names("rot_", 4))
    out.extend(_names("f_dc_", 3))
    out.append("opacity")
    return out^


def _find(bytes: List[UInt8], word: String, start: Int, end: Int) -> Int:
    """Return where a word first starts in a range of bytes.

    Args:
        bytes: The data.
        word: The word, ASCII.
        start: The first place it can start.
        end: One past the last byte it can take.

    Returns:
        Its first place, or -1.
    """
    var letters = word.as_bytes()
    var n = len(letters)
    for at in range(start, end - n + 1):
        var found = 0
        for k in range(n):  # pragma: no branch
            if bytes[at + k] != letters[k]:
                break
            found += 1
        if found == n:
            return at
    return -1


def _is_rest(name: String) -> Bool:
    """Return whether a property is one of the higher bands, three.js's
    `/^f_rest_\\d+$/`.

    Args:
        name: The property's name.

    Returns:
        True for `f_rest_` followed by one or more digits and nothing else.
    """
    if not name.startswith("f_rest_"):
        return False
    var digits = name.as_bytes()[7:]
    if len(digits) == 0:
        return False
    for byte in digits:  # pragma: no branch
        if byte < 48 or byte > 57:
            return False
    return True


def _header_lines(bytes: List[UInt8]) raises -> List[String]:
    """Return the lines of the header's text, three.js's
    `_headerPattern`.

    Args:
        bytes: The file.

    Returns:
        The lines between the leading `ply` and the first `end_header`.

    Raises:
        Error: If the file does not start with `ply` or has no
            `end_header` after it within the scanned bytes.
    """
    var scan = min(len(bytes), PLY_HEADER_SCAN)
    var end = _find(bytes, "end_header", 3, scan)
    if _find(bytes, "ply", 0, 3) != 0 or end < 0:
        raise Error("Gaussian splat PLY: missing PLY header")
    var lines = List[String]()
    var line = List[UInt8]()
    for at in range(3, end):
        var byte = bytes[at]
        if byte == 10 or byte == 13:
            lines.append(String(unsafe_from_utf8=line))
            line = List[UInt8]()
        else:
            line.append(byte)
    lines.append(String(unsafe_from_utf8=line))
    return lines^


def detect_spherical_harmonics_degree(bytes: List[UInt8]) raises -> Int:
    """Return the degree a splat PLY's header declares, three.js's
    `detectSphericalHarmonicsDegree`.

    Args:
        bytes: The file.

    Returns:
        0 to 3, from the count of `f_rest_N` properties.

    Raises:
        Error: If the header is missing, a required property is not
            declared, or the count of `f_rest` properties is not 0, 9,
            24 or 45.
    """
    var names = List[String]()
    var rest = 0
    for line in _header_lines(bytes):  # pragma: no branch
        var fields = line.split()
        if len(fields) != 3 or String(fields[0]) != "property":
            continue
        var name = String(fields[2])
        names.append(name)
        if _is_rest(name):
            rest += 1
    for required in _required():  # pragma: no branch
        if required not in names:
            raise Error(
                "Gaussian splat PLY: the file requires position, scale,"
                " rotation, f_dc and opacity properties"
            )
    var totals: List[Int] = [0, 9, 24, 45]
    for degree in range(4):  # pragma: no branch
        if totals[degree] == rest:
            return degree
    raise Error(
        "Gaussian splat PLY: unsupported number of f_rest spherical"
        " harmonics coefficients ("
        + String(rest)
        + ")"
    )


def parse_gaussian_splat_ply(
    bytes: List[UInt8],
) raises -> GaussianSplatGeometry:
    """Read a splat PLY file's bytes, three.js's
    `GaussianSplatPLYLoader.parse`.

    Args:
        bytes: The whole file, ASCII or binary.

    Returns:
        The splats; see the module docstring.

    Raises:
        Error: Everything `detect_spherical_harmonics_degree` and
            `loaders.ply.parse_ply` raise, and if the file has no vertices.
    """
    var degree = detect_spherical_harmonics_degree(bytes)
    var rest = [0, 9, 24, 45][degree]
    var options = PlyOptions()
    options.set_custom_attribute("scale", _names("scale_", 3))
    options.set_custom_attribute("rotation", _names("rot_", 4))
    options.set_custom_attribute("f_dc", _names("f_dc_", 3))
    options.set_custom_attribute("opacity", ["opacity"])
    if rest > 0:
        options.set_custom_attribute("f_rest", _names("f_rest_", rest))
    var geometry = parse_ply(bytes, options)
    var needed: List[String] = [
        String(POSITION),
        "scale",
        "rotation",
        "f_dc",
        "opacity",
    ]
    for name in needed:  # pragma: no branch
        if not geometry.has_attribute(name):
            raise Error(
                "Gaussian splat PLY: the file requires position, scale,"
                " rotation, f_dc and opacity properties"
            )
    ref position = geometry.attribute_view(String(POSITION))
    ref scale = geometry.attribute_view("scale")
    ref rotation = geometry.attribute_view("rotation")
    ref sh0 = geometry.attribute_view("f_dc")
    ref opacity = geometry.attribute_view("opacity")
    var count = position.count()
    var centers = position.packed()
    var covariances = List[Float32](length=count * 6, fill=0)
    var colors = List[UInt8](length=count * 4, fill=0)
    for index in range(count):  # pragma: no branch
        write_covariance(
            covariances,
            index * 6,
            exp(Float64(scale.data[index * 3])),
            exp(Float64(scale.data[index * 3 + 1])),
            exp(Float64(scale.data[index * 3 + 2])),
            Float64(rotation.data[index * 4 + 1]),
            Float64(rotation.data[index * 4 + 2]),
            Float64(rotation.data[index * 4 + 3]),
            Float64(rotation.data[index * 4]),
        )
        write_color_bytes_from_sh0(
            colors,
            index * 4,
            Float64(sh0.data[index * 3]),
            Float64(sh0.data[index * 3 + 1]),
            Float64(sh0.data[index * 3 + 2]),
            sigmoid(Float64(opacity.data[index])),
        )
    var bands = List[List[UInt8]]()
    for band in range(1, 4):  # pragma: no branch
        if band <= degree:
            bands.append(
                _band(geometry.attribute_view("f_rest").data, rest, count, band)
            )
        else:
            bands.append(List[UInt8]())
    return create_gaussian_splat_geometry(
        centers^,
        covariances^,
        colors^,
        bands[0].copy(),
        bands[1].copy(),
        bands[2].copy(),
    )


def _band(
    source: List[Float32], rest: Int, count: Int, degree: Int
) raises -> List[UInt8]:
    """Return one band's bytes from the `f_rest` values, three.js's
    `writeSphericalHarmonicsFromRest`.

    Args:
        source: The `f_rest` values, `rest` a splat.
        rest: How many a splat has.
        count: How many splats.
        degree: The band, 1 through 3.

    Returns:
        The band's bytes.

    Raises:
        Error: Never, for a degree of 1 through 3.
    """
    var band = packed_band(count, degree)
    var stride = rest // 3
    # The coefficients of the bands below come first in each channel.
    var offset = degree * degree - 1
    var words = sh_band_words(degree) * 4
    for index in range(count):  # pragma: no branch
        for component in range(sh_band_components(degree)):  # pragma: no branch
            var value = source[
                index * rest
                + offset
                + component // 3
                + (component % 3) * stride
            ]
            band[index * words + component] = clamped_byte(
                Float64(value) * 128 + 128
            )
    return band^


def read_gaussian_splat_ply(path: String) raises -> GaussianSplatGeometry:
    """Read a splat PLY file.

    Args:
        path: The file.

    Returns:
        Its splats; see `parse_gaussian_splat_ply`.

    Raises:
        Error: If the file cannot be read, or anything
            `parse_gaussian_splat_ply` raises.
    """
    return parse_gaussian_splat_ply(Path(path).read_bytes())
