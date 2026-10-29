# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""SOG files, PlayCanvas's compressed Gaussian splats, read as
`readSog` in `@playcanvas/splat-transform` 3.10.1 reads them.

SuperSplat publishes its scenes in this format. A SOG scene is a
`meta.json` text and lossless WebP images. The images are files beside
the text, or members of one ZIP file, a `.sog` bundle. Each texel of an
image holds one splat, in reading order from the top left.

- **Centers.** `means_l` and `means_u` hold the low and high bytes of a
  16-bit number for x, y and z. The number places `sign(v) * ln(|v| + 1)`
  between the `mins` and `maxs` of the text. A range of zero counts as one.
- **Rotations.** `quats` holds the three smallest components of the unit
  quaternion w, x, y, z, each `byte / 255 * 2 - 1` divided by the square
  root of two. The fourth byte, 252 to 255, names the largest component,
  which is positive. Another fourth byte gives no rotation.
- **Scales.** `scales` holds three bytes. Each is an index into the 256
  logarithms of the scales `codebook`.
- **Colors.** `sh0` holds three indexes into the zeroth-band `codebook`,
  and the opacity, `sigmoid(opacity) * 255`, in its fourth byte.
- **Harmonics.** `shN`, when there is one, has a palette of `count`
  entries of 3, 8 or 15 coefficients for 1, 2 or 3 bands. `shN_labels`
  holds a 16-bit palette index for each splat. `shN_centroids` is 64
  entries wide, one texel for each coefficient, and its red, green and
  blue bytes are indexes into the harmonics `codebook`. An index past the
  palette gives zero coefficients.

The reader makes the numbers that splat-transform makes, in the same
order and rounded to `Float32` at the same places. It then builds the
splats as `loaders.gaussian_splat_ply` builds them from a PLY file. So a
SOG scene and the PLY file that splat-transform writes from it give the
same splats.

**What is refused.** Version 1 files, which have no `version`. A version
other than 2. A count that is not at least one. A `model` other than
`default`, `antialiased` or `2dgs`. A codebook that is not 256 finite
numbers. An image that splat-transform refuses: one with fewer texels
than splats, or harmonics centroids that are not 64 entries wide. A file
name with a folder in it, so a downloaded text cannot read outside its
folder. A missing file, and anything that `render.webp.decode` and
`loaders.zip.unzip` refuse.

ThreeMojo draws every model as a 3D Gaussian. The model is kept so that a
caller can tell an antialiased or a 2D Gaussian scene apart.
"""

from core.gaussian_splat_utils import (
    clamped_byte,
    create_gaussian_splat_geometry,
    packed_band,
    sh_band_components,
    sh_band_words,
    sigmoid,
    write_color_bytes_from_sh0,
    write_covariance,
)
from extensions.scan.scene import (
    SPLAT_DEFAULT,
    ScanScene,
    splat_model,
)
from loaders.json import JsonDocument, NO_NODE, parse_json
from loaders.zip import unzip
from render.png import DecodedImage
from render.webp import decode
from loaders.file_path import path_directory
from std.math import exp, log, sqrt
from std.pathlib import Path

comptime SOG_META = "meta.json"
"""The name of the text in a folder or a bundle."""
comptime SOG_CODEBOOK_ENTRIES = 256
"""How many entries a codebook has: one for each value of a byte."""
comptime SOG_CENTROIDS_PER_ROW = 64
"""How many palette entries a row of `shN_centroids` holds."""
comptime SOG_QUAT_TAG = 252
"""The fourth `quats` byte for a largest component of w; x, y and z follow."""


@fieldwise_init
struct SogFile(Copyable, Movable):
    """One file of a SOG scene: its name and its bytes."""

    var name: String
    """The name that `meta.json` gives it."""
    var data: List[UInt8]
    """The whole file."""


def _require_file_name(name: String) raises:
    """Refuse a file name that is empty or names a folder.

    Args:
        name: The name from `meta.json`.

    Raises:
        Error: If the name is empty, `.`, `..`, or has a `/` or a `\\`.
    """
    if name == "" or name == "." or name == "..":
        raise Error("SOG: '" + name + "' is not a file name")
    if "/" in name or "\\" in name:
        raise Error("SOG: the file name '" + name + "' names a folder")


def _files(
    document: JsonDocument, section: Int, count: Int, label: String
) raises -> List[String]:
    """Return a section's `files`, which must be `count` file names.

    Args:
        document: The text.
        section: The section's node.
        count: How many files it names.
        label: The section's key, for the error.

    Returns:
        The names, in order.

    Raises:
        Error: If the section has no `files` array of `count` file names.
    """
    var files = document.get(section, "files")
    if files == NO_NODE:
        raise Error("SOG: " + label + " has no files")
    if document.length(files) != count:
        raise Error(
            "SOG: "
            + label
            + " names "
            + String(count)
            + " files, not "
            + String(document.length(files))
        )
    var names = List[String]()
    for index in range(count):  # pragma: no branch
        var name = document.string(document.at(files, index))
        _require_file_name(name)
        names.append(name)
    return names^


def _section(document: JsonDocument, key: String) raises -> Int:
    """Return a section of the text, which must be there.

    Args:
        document: The text.
        key: The section's key.

    Returns:
        The section's node.

    Raises:
        Error: If the section is missing.
    """
    var section = document.get(document.root(), key)
    if section == NO_NODE:
        raise Error("SOG: meta.json has no " + key)
    return section


def _codebook(
    document: JsonDocument, section: Int, label: String
) raises -> List[Float32]:
    """Return a section's codebook, as the `Float32Array` that holds it.

    Args:
        document: The text.
        section: The section's node.
        label: The section's key, for the error.

    Returns:
        The 256 entries.

    Raises:
        Error: If the codebook is missing, is not 256 entries, or has an
            entry that is not a finite number.
    """
    var codebook = document.get(section, "codebook")
    if codebook == NO_NODE:
        raise Error("SOG: " + label + " has no codebook")
    if document.length(codebook) != SOG_CODEBOOK_ENTRIES:
        raise Error(
            "SOG: the "
            + label
            + " codebook is not "
            + String(SOG_CODEBOOK_ENTRIES)
            + " entries"
        )
    return document.finite_numbers(
        codebook, "SOG: the " + label + " codebook must be finite"
    )


def _range(
    document: JsonDocument, section: Int, key: String
) raises -> List[Float64]:
    """Return the three numbers of `means.mins` or `means.maxs`.

    Args:
        document: The text.
        section: The `means` node.
        key: `mins` or `maxs`.

    Returns:
        The x, y and z numbers.

    Raises:
        Error: If the array is missing, is not three entries, or has an
            entry that is not a number. A JSON number is always finite.
    """
    var array = document.get(section, key)
    if array == NO_NODE:
        raise Error("SOG: means has no " + key)
    if document.length(array) != 3:
        raise Error("SOG: means " + key + " is not three numbers")
    var values = List[Float64]()
    for axis in range(3):
        values.append(document.number(document.at(array, axis)))
    return values^


def _image(
    files: List[SogFile], name: String, count: Int
) raises -> DecodedImage:
    """Decode a named image, which must have a texel for each splat.

    Args:
        files: The scene's files.
        name: The image's name.
        count: How many splats.

    Returns:
        The image, eight-bit RGBA.

    Raises:
        Error: If the file is missing, is not a WebP image, or has fewer
            texels than splats.
    """
    for file in files:
        if file.name == name:
            var image = decode(file.data)
            if image.width * image.height < count:
                raise Error("SOG: " + name + " has fewer texels than splats")
            return image^
    raise Error("SOG: the scene has no file " + name)


def _inverse_log(value: Float64) -> Float64:
    """Return x for `sign(x) * ln(|x| + 1)`, splat-transform's
    `invLogTransform`.

    Args:
        value: The stored number.

    Returns:
        The coordinate.
    """
    var magnitude = exp(abs(value)) - 1
    if value < 0:
        return -magnitude
    return magnitude


def _logit(fraction: Float64) -> Float64:
    """Return the opacity logit of a fraction, splat-transform's
    `sigmoidInv`, which first keeps the fraction one millionth from 0
    and 1.

    Args:
        fraction: The opacity, 0 through 1.

    Returns:
        `ln(e / (1 - e))` of the kept fraction `e`.
    """
    var kept = min(1 - 1e-6, max(1e-6, fraction))
    return log(kept / (1 - kept))


def _quaternion(
    pixels: List[UInt8], at: Int
) -> Tuple[Float32, Float32, Float32, Float32]:
    """Return one texel's rotation, splat-transform's `unpackQuat`.

    Args:
        pixels: The `quats` image.
        at: The texel's first byte.

    Returns:
        The w, x, y and z components. A tag below 252 gives no rotation.
    """
    var tag = Int(pixels[at + 3])
    if tag < SOG_QUAT_TAG:
        return (Float32(1), Float32(0), Float32(0), Float32(0))
    var largest = tag - SOG_QUAT_TAG
    var root_two = sqrt(Float64(2))
    var a = (Float64(pixels[at]) / 255 * 2 - 1) / root_two
    var b = (Float64(pixels[at + 1]) / 255 * 2 - 1) / root_two
    var c = (Float64(pixels[at + 2]) / 255 * 2 - 1) / root_two
    var rest = sqrt(max(Float64(0), 1 - (a * a + b * b + c * c)))
    var components = List[Float32](length=4, fill=0)
    var others = List[Float64]()
    others.append(a)
    others.append(b)
    others.append(c)
    var next = 0
    for component in range(4):
        if component == largest:
            components[component] = Float32(rest)
        else:
            components[component] = Float32(others[next])
            next += 1
    return (components[0], components[1], components[2], components[3])


struct _Rest(Movable):
    """The higher bands of every splat, as a PLY file holds them."""

    var degree: Int
    """How many bands, 0 to 3."""
    var values: List[Float32]
    """`count * coefficients * 3` numbers, each channel's coefficients together."""

    def __init__(out self, degree: Int, var values: List[Float32]):
        self.degree = degree
        self.values = values^


def _harmonics(
    document: JsonDocument,
    files: List[SogFile],
    count: Int,
) raises -> _Rest:
    """Return the bands and every splat's `f_rest` numbers.

    Args:
        document: The text.
        files: The scene's files.
        count: How many splats.

    Returns:
        The degree, 0 to 3, and the numbers.

    Raises:
        Error: If `shN` is not as the module docstring says.
    """
    var section = document.get(document.root(), "shN")
    if section == NO_NODE:
        return _Rest(0, List[Float32]())
    var bands = document.integer(
        document.required(section, "bands", "SOG: shN has no bands")
    )
    if bands < 0 or bands > 3:
        raise Error("SOG: shN has " + String(bands) + " bands, not 0 to 3")
    if bands == 0:
        return _Rest(0, List[Float32]())
    var coefficients = [0, 3, 8, 15][bands]
    var palette = document.integer(
        document.required(section, "count", "SOG: shN has no count")
    )
    var codebook = _codebook(document, section, "shN")
    var names = _files(document, section, 2, "shN")
    var centroids = _image(files, names[0], 0)
    var labels = _image(files, names[1], count)
    if centroids.width != SOG_CENTROIDS_PER_ROW * coefficients:
        raise Error(
            "SOG: shN centroids are "
            + String(centroids.width)
            + " texels wide, not "
            + String(SOG_CENTROIDS_PER_ROW * coefficients)
        )
    var rest = coefficients * 3
    var values = List[Float32](length=count * rest, fill=0)
    for index in range(count):  # pragma: no branch
        var at = index * 4
        var label = Int(labels.pixels[at]) | (Int(labels.pixels[at + 1]) << 8)
        if label >= palette:
            continue
        var row = label // SOG_CENTROIDS_PER_ROW
        var column = (label % SOG_CENTROIDS_PER_ROW) * coefficients
        for coefficient in range(coefficients):  # pragma: no branch
            var texel = (row * centroids.width + column + coefficient) * 4
            # The centroid image can end before the palette does; past its
            # end the entry is index zero of the codebook.
            var red = 0
            var green = 0
            var blue = 0
            if row < centroids.height:
                red = Int(centroids.pixels[texel])
                green = Int(centroids.pixels[texel + 1])
                blue = Int(centroids.pixels[texel + 2])
            var base = index * rest + coefficient
            values[base] = codebook[red]
            values[base + coefficients] = codebook[green]
            values[base + coefficients * 2] = codebook[blue]
    return _Rest(bands, values^)


def _band(
    values: List[Float32], rest: Int, count: Int, degree: Int
) raises -> List[UInt8]:
    """Return one band's bytes from the `f_rest` numbers, as
    `loaders.gaussian_splat_ply` makes them.

    Args:
        values: The `f_rest` numbers, `rest` a splat.
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
    var offset = degree * degree - 1
    var words = sh_band_words(degree) * 4
    for index in range(count):  # pragma: no branch
        for component in range(sh_band_components(degree)):  # pragma: no branch
            var value = values[
                index * rest
                + offset
                + component // 3
                + (component % 3) * stride
            ]
            band[index * words + component] = clamped_byte(
                Float64(value) * 128 + 128
            )
    return band^


def sog_file_names(meta: String) raises -> List[String]:
    """Return the names of the images that a `meta.json` text needs.

    Args:
        meta: The text.

    Returns:
        The `means`, `scales`, `quats`, `sh0` and, when there is one,
        `shN` file names, in that order.

    Raises:
        Error: If the text is not JSON, a section is missing, or a name is
            not a file name.
    """
    var document = parse_json(meta)
    var names = _files(document, _section(document, "means"), 2, "means")
    names.extend(_files(document, _section(document, "scales"), 1, "scales"))
    names.extend(_files(document, _section(document, "quats"), 1, "quats"))
    names.extend(_files(document, _section(document, "sh0"), 1, "sh0"))
    var harmonics = document.get(document.root(), "shN")
    if harmonics != NO_NODE:
        names.extend(_files(document, harmonics, 2, "shN"))
    return names^


def parse_sog(meta: String, files: List[SogFile]) raises -> ScanScene:
    """Read a SOG scene from its text and its images.

    Args:
        meta: The `meta.json` text.
        files: The images, by the names that the text gives.

    Returns:
        The scene; see the module docstring.

    Raises:
        Error: Everything that the module docstring lists.
    """
    var document = parse_json(meta)
    var root = document.root()
    var version = document.get(root, "version")
    if version == NO_NODE:
        raise Error("SOG: version 1 files, with no version, are not read")
    if document.integer(version) != 2:
        raise Error(
            "SOG: version "
            + String(document.integer(version))
            + " is not read; version 2 is"
        )
    var model = SPLAT_DEFAULT
    var model_node = document.get(root, "model")
    if model_node != NO_NODE:
        model = splat_model(document.string(model_node))
    var count = document.integer(
        document.required(root, "count", "SOG: meta.json has no count")
    )
    if count < 1:
        raise Error("SOG: a scene has at least one splat")

    var means = _section(document, "means")
    var mins = _range(document, means, "mins")
    var maxs = _range(document, means, "maxs")
    var mean_names = _files(document, means, 2, "means")
    var low = _image(files, mean_names[0], count)
    var high = _image(files, mean_names[1], count)
    var spans = List[Float64]()
    for axis in range(3):
        var span = maxs[axis] - mins[axis]
        if span == 0:
            span = 1
        spans.append(span)

    var scales = _section(document, "scales")
    var scale_codebook = _codebook(document, scales, "scales")
    var scale_image = _image(
        files, _files(document, scales, 1, "scales")[0], count
    )
    var quats = _image(
        files,
        _files(document, _section(document, "quats"), 1, "quats")[0],
        count,
    )
    var colors_section = _section(document, "sh0")
    var color_codebook = _codebook(document, colors_section, "sh0")
    var color_image = _image(
        files, _files(document, colors_section, 1, "sh0")[0], count
    )
    var harmonics = _harmonics(document, files, count)

    var centers = List[Float32](capacity=count * 3)
    var covariances = List[Float32](length=count * 6, fill=0)
    var colors = List[UInt8](length=count * 4, fill=0)
    for index in range(count):  # pragma: no branch
        var at = index * 4
        for axis in range(3):
            var word = Int(low.pixels[at + axis]) | (
                Int(high.pixels[at + axis]) << 8
            )
            centers.append(
                Float32(
                    _inverse_log(
                        mins[axis] + spans[axis] * (Float64(word) / 65535)
                    )
                )
            )
        var w: Float32
        var x: Float32
        var y: Float32
        var z: Float32
        w, x, y, z = _quaternion(quats.pixels, at)
        write_covariance(
            covariances,
            index * 6,
            exp(Float64(scale_codebook[Int(scale_image.pixels[at])])),
            exp(Float64(scale_codebook[Int(scale_image.pixels[at + 1])])),
            exp(Float64(scale_codebook[Int(scale_image.pixels[at + 2])])),
            Float64(x),
            Float64(y),
            Float64(z),
            Float64(w),
        )
        var opacity = Float32(_logit(Float64(color_image.pixels[at + 3]) / 255))
        write_color_bytes_from_sh0(
            colors,
            index * 4,
            Float64(color_codebook[Int(color_image.pixels[at])]),
            Float64(color_codebook[Int(color_image.pixels[at + 1])]),
            Float64(color_codebook[Int(color_image.pixels[at + 2])]),
            sigmoid(Float64(opacity)),
        )
    var rest = [0, 9, 24, 45][harmonics.degree]
    var bands = List[List[UInt8]]()
    for band in range(1, 4):
        if band <= harmonics.degree:
            bands.append(_band(harmonics.values, rest, count, band))
        else:
            bands.append(List[UInt8]())
    var geometry = create_gaussian_splat_geometry(
        centers^,
        covariances^,
        colors^,
        bands[0].copy(),
        bands[1].copy(),
        bands[2].copy(),
    )
    return ScanScene(geometry^, model)


def _text(bytes: List[UInt8]) raises -> String:
    """Return a file's bytes as UTF-8 text.

    Args:
        bytes: The file.

    Returns:
        The text.

    Raises:
        Error: If the bytes are not UTF-8.
    """
    return String(from_utf8=Span(bytes))


def parse_sog_bundle(bytes: List[UInt8]) raises -> ScanScene:
    """Read a `.sog` bundle: a ZIP file of `meta.json` and its images.

    Args:
        bytes: The whole file.

    Returns:
        The scene; see `parse_sog`.

    Raises:
        Error: If the file is not a ZIP file, has no `meta.json`, or
            anything that `parse_sog` raises.
    """
    var entries = unzip(bytes)
    var files = List[SogFile]()
    var meta = Optional[String]()
    for entry in entries:
        if entry.name == SOG_META:
            meta = _text(entry.data)
        else:
            files.append(SogFile(entry.name, entry.data.copy()))
    if not meta:
        raise Error("SOG: the bundle has no meta.json")
    return parse_sog(meta.value(), files)


def read_sog(path: String) raises -> ScanScene:
    """Read a SOG scene from a `.sog` bundle or a `meta.json` file.

    A path that ends in `.sog` is a bundle. Any other path is the text,
    and the images are the files beside it.

    Args:
        path: The bundle or the text.

    Returns:
        The scene; see `parse_sog`.

    Raises:
        Error: If a file cannot be read, or anything that `parse_sog` and
            `parse_sog_bundle` raise.
    """
    if path.endswith(".sog"):
        return parse_sog_bundle(Path(path).read_bytes())
    var meta = Path(path).read_text()
    var folder = path_directory(path)
    var files = List[SogFile]()
    for name in sog_file_names(meta):  # pragma: no branch
        files.append(SogFile(name, Path(folder + name).read_bytes()))
    return parse_sog(meta, files)
