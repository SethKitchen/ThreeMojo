# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""`.ksplat` files, GaussianSplats3D's format, from three.js
`examples/jsm/loaders/KSPLATLoader.js`.

A 4096-byte header, then `max_section_count` section headers of 1024
bytes, then each section's data. The header gives the version, which must
be 0.1 or a later 0.x, the splat count, the compression level and the
range the one-byte spherical harmonics are spread over, -1.5 to 1.5 when
the header gives zero.

**Compression.** `KsplatCompressionLevel` says how a splat is stored:

| Level | Center | Scale and rotation | Harmonics |
|---|---|---|---|
| 0 | Three floats. | Floats. | Floats. |
| 1 | Three 16-bit steps from a bucket's center. | Half floats. | Half floats. |
| 2 | As level 1. | Half floats. | One byte each, across the header's range. |

Every level stores the color as four bytes.

**Sections and buckets.** Each section header gives its splat count, how
many rows it has room for, its spherical harmonics degree, and its
buckets. A compressed center is `(step - range) * block / 2 / range` from
its bucket's center, where `block` is the section's bucket block size and
`range` its scale range, 32767 when the section gives zero. The first
`full_bucket_count` buckets hold `bucket_size` splats each. The partly
filled buckets after them list their lengths before the bucket centers.

**Harmonics.** A section of degree `d` stores `0, 9, 24` or `45` numbers a
splat, band by band and channel by channel. They are reordered into each
band's coefficient-by-coefficient bytes, `value * 128 + 128`, clamped.
Every band up to the highest degree of any section is made, so a splat in
a section of a lower degree keeps zero in the higher bands.

A file that is shorter than its header or its sections, of an unsupported
version, level or degree, of more than `MAX_KSPLAT_SPLATS` splats, whose
sections hold more or fewer splats than the header says, or whose
buckets do not hold a splat, is refused. A section that says it holds more
splats than it has rows for is refused too, where three.js reads on into
the next section.
"""

from core.gaussian_splat_utils import (
    GaussianSplatGeometry,
    clamped_byte,
    create_gaussian_splat_geometry,
    packed_band,
    sh_band_components,
    sh_band_words,
    write_covariance,
)
from loaders.splat import le_f32, le_u16, le_u32
from render.data_utils import from_half_float
from std.pathlib import Path

comptime KSPLAT_HEADER_BYTES = 4096
comptime KSPLAT_SECTION_HEADER_BYTES = 1024
# The most splats a file can hold, three.js's `MAX_SPLATS`.
comptime MAX_KSPLAT_SPLATS = 10000000
# The one-byte harmonics' range when the header gives none.
comptime KSPLAT_DEFAULT_SH_MIN = Float64(-1.5)
comptime KSPLAT_DEFAULT_SH_MAX = Float64(1.5)


@fieldwise_init
struct KsplatCompressionLevel(Equatable, ImplicitlyCopyable, Writable):
    """How a `.ksplat` file stores a splat, as a type rather than a bare
    int. `ksplat_layout` refuses a level that is not 0, 1 or 2."""

    var value: Int

    def is_valid(self) -> Bool:
        """Return True if this is one of the three levels there are."""
        return self.value >= 0 and self.value <= 2


comptime KSPLAT_UNCOMPRESSED = KsplatCompressionLevel(0)
comptime KSPLAT_HALF = KsplatCompressionLevel(1)
comptime KSPLAT_BYTE_HARMONICS = KsplatCompressionLevel(2)


@fieldwise_init
struct KsplatLayout(ImplicitlyCopyable):
    """Where each part of a splat's row is, for one compression level:
    three.js's `COMPRESSION_LEVELS` entry."""

    var bytes_per_center: Int
    var bytes_per_scale: Int
    var bytes_per_rotation: Int
    var bytes_per_color: Int
    var bytes_per_harmonic: Int
    var scale_offset: Int
    var rotation_offset: Int
    var color_offset: Int
    var scale_range: Int


def ksplat_layout(level: KsplatCompressionLevel) raises -> KsplatLayout:
    """Return a compression level's row layout.

    Args:
        level: The level.

    Returns:
        Its layout.

    Raises:
        Error: If the level is not 0, 1 or 2.
    """
    if not level.is_valid():
        raise Error(
            "KSPLAT: unsupported compression level " + String(level.value)
        )
    if level == KSPLAT_UNCOMPRESSED:
        return KsplatLayout(12, 12, 16, 4, 4, 12, 24, 40, 1)
    var harmonic = 2
    if level == KSPLAT_BYTE_HARMONICS:
        harmonic = 1
    return KsplatLayout(6, 6, 8, 4, harmonic, 6, 12, 20, 32767)


def ksplat_components(degree: Int) raises -> Int:
    """Return how many harmonics numbers a splat of a degree stores.

    Args:
        degree: The section's degree.

    Returns:
        0, 9, 24 or 45.

    Raises:
        Error: If the degree is above 3.
    """
    if degree > 3:
        raise Error(
            "KSPLAT: unsupported spherical harmonics degree " + String(degree)
        )
    var totals: List[Int] = [0, 9, 24, 45]
    return totals[degree]


def ksplat_band_index(degree: Int, component: Int) -> Int:
    """Return where a band's number is stored in a splat's harmonics,
    three.js's `SH_BAND_INDEX`.

    A file stores each channel's coefficients together, band by band; a
    band's bytes hold each coefficient's three channels together.

    Args:
        degree: The band, 1 through 3.
        component: The number in the band's bytes: coefficient times
            three plus channel.

    Returns:
        Its index among the splat's stored numbers.
    """
    var coefficients = 2 * degree + 1
    var coefficient = component // 3
    var channel = component % 3
    var before = (degree - 1) * (degree + 1) * 3
    return before + channel * coefficients + coefficient


struct _Header(ImplicitlyCopyable):
    """The file header's fields three.js reads."""

    var major: Int
    var minor: Int
    var max_sections: Int
    var splats: Int
    var level: KsplatCompressionLevel
    var sh_min: Float64
    var sh_max: Float64

    def __init__(out self, bytes: List[UInt8]):
        """Read the header.

        Args:
            bytes: The file, at least a header long.
        """
        self.major = Int(bytes[0])
        self.minor = Int(bytes[1])
        self.max_sections = le_u32(bytes, 4)
        self.splats = le_u32(bytes, 16)
        self.level = KsplatCompressionLevel(le_u16(bytes, 20))
        self.sh_min = _or_default(le_f32(bytes, 36), KSPLAT_DEFAULT_SH_MIN)
        self.sh_max = _or_default(le_f32(bytes, 40), KSPLAT_DEFAULT_SH_MAX)


def _or_default(value: Float32, default: Float64) -> Float64:
    """Return a header number, or a default where JavaScript's `||` takes
    one: for zero and for not a number.

    Args:
        value: The number.
        default: What stands for zero.

    Returns:
        The number, or the default.
    """
    if value == 0 or value != value:
        return default
    return Float64(value)


struct _Section(ImplicitlyCopyable):
    """A section header's fields three.js reads."""

    var splats: Int
    var max_splats: Int
    var bucket_size: Int
    var bucket_count: Int
    var block_size: Float64
    var bucket_bytes: Int
    var scale_range: Int
    var full_buckets: Int
    var partial_buckets: Int
    var degree: Int

    def __init__(out self, bytes: List[UInt8], at: Int, layout: KsplatLayout):
        """Read a section header.

        Args:
            bytes: The file.
            at: Where the section header starts.
            layout: The file's layout, for its default scale range.
        """
        self.splats = le_u32(bytes, at)
        self.max_splats = le_u32(bytes, at + 4)
        self.bucket_size = le_u32(bytes, at + 8)
        self.bucket_count = le_u32(bytes, at + 12)
        self.block_size = Float64(le_f32(bytes, at + 16))
        self.bucket_bytes = le_u16(bytes, at + 20)
        self.scale_range = le_u32(bytes, at + 24)
        if self.scale_range == 0:
            self.scale_range = layout.scale_range
        self.full_buckets = le_u32(bytes, at + 32)
        self.partial_buckets = le_u32(bytes, at + 36)
        self.degree = le_u16(bytes, at + 40)


struct _Splats(Movable):
    """What the sections are read into."""

    var centers: List[Float32]
    var covariances: List[Float32]
    var colors: List[UInt8]
    var bands: List[List[UInt8]]

    def __init__(out self, count: Int):
        """Make room for every splat, with no bands yet.

        Args:
            count: How many splats the header says.
        """
        self.centers = List[Float32](length=count * 3, fill=0)
        self.covariances = List[Float32](length=count * 6, fill=0)
        self.colors = List[UInt8](length=count * 4, fill=0)
        self.bands = List[List[UInt8]]()

    def ensure_bands(mut self, count: Int, degree: Int) raises:
        """Make every band up to a degree that is not made yet, three.js's
        `ensureSphericalHarmonics`.

        Args:
            count: How many splats.
            degree: The highest band needed.

        Raises:
            Error: Never, for a degree of 0 through 3.
        """
        while len(self.bands) < degree:
            self.bands.append(packed_band(count, len(self.bands) + 1))


def parse_ksplat(bytes: List[UInt8]) raises -> GaussianSplatGeometry:
    """Read a `.ksplat` file's bytes, three.js's `KSPLATLoader.parse`.

    Args:
        bytes: The whole file.

    Returns:
        The splats; see the module docstring.

    Raises:
        Error: If the file is refused; see the module docstring.
    """
    if len(bytes) < KSPLAT_HEADER_BYTES:
        raise Error("KSPLAT: invalid KSPLAT header")
    var header = _Header(bytes)
    if header.major != 0 or header.minor < 1:
        raise Error(
            "KSPLAT: unsupported KSPLAT version "
            + String(header.major)
            + "."
            + String(header.minor)
        )
    var layout = ksplat_layout(header.level)
    if header.splats > MAX_KSPLAT_SPLATS:
        raise Error(
            "KSPLAT: the file holds too many splats ("
            + String(header.splats)
            + ")"
        )
    var data_start = (
        KSPLAT_HEADER_BYTES + header.max_sections * KSPLAT_SECTION_HEADER_BYTES
    )
    if len(bytes) < data_start:
        raise Error("KSPLAT: invalid KSPLAT section headers")
    var out = _Splats(header.splats)
    var read = 0
    var base = data_start
    for index in range(header.max_sections):
        var section = _Section(
            bytes,
            KSPLAT_HEADER_BYTES + index * KSPLAT_SECTION_HEADER_BYTES,
            layout,
        )
        var per_splat = (
            layout.bytes_per_center
            + layout.bytes_per_scale
            + layout.bytes_per_rotation
            + layout.bytes_per_color
            + ksplat_components(section.degree) * layout.bytes_per_harmonic
        )
        var meta = section.partial_buckets * 4
        var buckets = section.bucket_bytes * section.bucket_count + meta
        var storage = buckets + per_splat * section.max_splats
        if base + storage > len(bytes):
            raise Error("KSPLAT: invalid KSPLAT byte length")
        if section.splats > section.max_splats:
            raise Error("KSPLAT: a section holds more splats than rows")
        if read + section.splats > header.splats:
            raise Error("KSPLAT: KSPLAT splat count mismatch")
        if section.splats > 0:
            out.ensure_bands(header.splats, section.degree)
            _read_section(
                bytes,
                section,
                layout,
                header,
                base,
                meta,
                buckets,
                per_splat,
                read,
                out,
            )
        read += section.splats
        base += storage
    if read != header.splats:
        raise Error("KSPLAT: KSPLAT splat count mismatch")
    var bands = out.bands.copy()
    while len(bands) < 3:
        bands.append(List[UInt8]())
    return create_gaussian_splat_geometry(
        out.centers.copy(),
        out.covariances.copy(),
        out.colors.copy(),
        bands[0].copy(),
        bands[1].copy(),
        bands[2].copy(),
    )


@fieldwise_init
struct _Cursor(ImplicitlyCopyable):
    """The partly filled bucket the last splat was found in, and the index
    of that bucket's first splat."""

    var bucket: Int
    var first: Int


def _bucket_of(
    bytes: List[UInt8],
    section: _Section,
    base: Int,
    splat: Int,
    mut cursor: _Cursor,
) raises -> Int:
    """Return the bucket a splat's center is stored against, three.js's
    `getBucketIndex`.

    Args:
        bytes: The file.
        section: The section.
        base: Where the section's data starts: its partial bucket lengths.
        splat: The splat's index in the section.
        cursor: Where the search of the partial buckets left off. It moves
            to the bucket found.

    Returns:
        The bucket's index.

    Raises:
        Error: If the splat is past every bucket, or a bucket's length is
            past the end of the file.
    """
    if section.bucket_count == 0:
        return 0
    if splat < section.full_buckets * section.bucket_size:
        return splat // section.bucket_size
    var bucket = cursor.bucket
    var first = cursor.first
    while bucket < section.bucket_count:
        var at = base + (bucket - section.full_buckets) * 4
        if at + 4 > len(bytes):
            break
        var length = le_u32(bytes, at)
        if splat < first + length:
            cursor = _Cursor(bucket, first)
            return bucket
        bucket += 1
        first += length
    raise Error("KSPLAT: invalid KSPLAT bucket data")


def _read_section(
    bytes: List[UInt8],
    section: _Section,
    layout: KsplatLayout,
    header: _Header,
    base: Int,
    meta: Int,
    buckets: Int,
    per_splat: Int,
    first: Int,
    mut out: _Splats,
) raises:
    """Read one section's splats, three.js's `readSection`.

    Args:
        bytes: The file.
        section: The section's header.
        layout: The file's layout.
        header: The file's header, for the harmonics' range.
        base: Where the section's data starts.
        meta: How many bytes the partial bucket lengths take.
        buckets: How many bytes those lengths and the bucket centers take.
        per_splat: How many bytes a row takes.
        first: The index of the section's first splat among all of them.
        out: What the splats are read into.

    Raises:
        Error: If a splat is past every bucket.
    """
    var factor = section.block_size / 2 / Float64(section.scale_range)
    var cursor = _Cursor(
        section.full_buckets, section.full_buckets * section.bucket_size
    )
    for index in range(section.splats):  # pragma: no branch
        var bucket = _bucket_of(bytes, section, base, index, cursor)
        var row = base + buckets + index * per_splat
        var splat = first + index
        _read_center(
            bytes, section, layout, row, base + meta, bucket, factor, splat, out
        )
        _read_shape(bytes, layout, row, splat, out)
        for degree in range(1, section.degree + 1):
            _read_band(
                bytes,
                layout,
                header,
                row + layout.color_offset + layout.bytes_per_color,
                degree,
                splat,
                out,
            )


def _read_center(
    bytes: List[UInt8],
    section: _Section,
    layout: KsplatLayout,
    row: Int,
    centers_at: Int,
    bucket: Int,
    factor: Float64,
    splat: Int,
    mut out: _Splats,
):
    """Read a splat's center, as floats or as steps from its bucket's.

    Args:
        bytes: The file.
        section: The section's header.
        layout: The file's layout.
        row: Where the splat's row starts.
        centers_at: Where the bucket centers start.
        bucket: The splat's bucket.
        factor: The size of one step.
        splat: The splat's index among all of them.
        out: What the splats are read into.
    """
    for lane in range(3):  # pragma: no branch
        if layout.bytes_per_center == 12:
            out.centers[splat * 3 + lane] = le_f32(bytes, row + lane * 4)
        else:
            var step = Float64(le_u16(bytes, row + lane * 2))
            var origin = Float64(
                le_f32(
                    bytes, centers_at + bucket * section.bucket_bytes + lane * 4
                )
            )
            out.centers[splat * 3 + lane] = Float32(
                (step - Float64(section.scale_range)) * factor + origin
            )


def _compressed(bytes: List[UInt8], at: Int, width: Int) -> Float64:
    """Return a scale's or a rotation's number, three.js's
    `readCompressedFloat`.

    Args:
        bytes: The file.
        at: Where the number starts.
        width: How many bytes the whole vector takes: 12 or 16 for floats.

    Returns:
        The number.
    """
    if width == 12 or width == 16:
        return Float64(le_f32(bytes, at))
    return Float64(from_half_float(UInt16(le_u16(bytes, at))))


def _read_shape(
    bytes: List[UInt8],
    layout: KsplatLayout,
    row: Int,
    splat: Int,
    mut out: _Splats,
):
    """Read a splat's scale, rotation and color.

    Args:
        bytes: The file.
        layout: The file's layout.
        row: Where the splat's row starts.
        splat: The splat's index among all of them.
        out: What the splats are read into.
    """
    var scale = row + layout.scale_offset
    var scale_step = layout.bytes_per_scale // 3
    var turn = row + layout.rotation_offset
    var turn_step = layout.bytes_per_rotation // 4
    var width = layout.bytes_per_scale
    var turn_width = layout.bytes_per_rotation
    write_covariance(
        out.covariances,
        splat * 6,
        _compressed(bytes, scale, width),
        _compressed(bytes, scale + scale_step, width),
        _compressed(bytes, scale + scale_step * 2, width),
        _compressed(bytes, turn + turn_step, turn_width),
        _compressed(bytes, turn + turn_step * 2, turn_width),
        _compressed(bytes, turn + turn_step * 3, turn_width),
        _compressed(bytes, turn, turn_width),
    )
    for lane in range(4):  # pragma: no branch
        out.colors[splat * 4 + lane] = bytes[row + layout.color_offset + lane]


def _harmonic(
    bytes: List[UInt8], at: Int, width: Int, header: _Header
) -> Float64:
    """Return one stored harmonics number, three.js's
    `readCompressedSphericalHarmonic`.

    Args:
        bytes: The file.
        at: Where the number starts.
        width: How many bytes it takes: 4, 2 or 1.
        header: The file's header, for a byte's range.

    Returns:
        The number.
    """
    if width == 4:
        return Float64(le_f32(bytes, at))
    if width == 2:
        return Float64(from_half_float(UInt16(le_u16(bytes, at))))
    var t = Float64(bytes[at]) / 255
    return header.sh_min + t * (header.sh_max - header.sh_min)


def _read_band(
    bytes: List[UInt8],
    layout: KsplatLayout,
    header: _Header,
    harmonics: Int,
    degree: Int,
    splat: Int,
    mut out: _Splats,
) raises:
    """Read one band of a splat's harmonics into the band's bytes, three.js's
    `writeKSPLATSphericalHarmonicsBand`.

    Args:
        bytes: The file.
        layout: The file's layout.
        header: The file's header.
        harmonics: Where the splat's harmonics start.
        degree: The band.
        splat: The splat's index among all of them.
        out: What the splats are read into.

    Raises:
        Error: Never, for a degree of 1 through 3.
    """
    var start = splat * sh_band_words(degree) * 4
    var width = layout.bytes_per_harmonic
    for component in range(sh_band_components(degree)):  # pragma: no branch
        var value = _harmonic(
            bytes,
            harmonics + ksplat_band_index(degree, component) * width,
            width,
            header,
        )
        out.bands[degree - 1][start + component] = clamped_byte(
            value * 128 + 128
        )


def read_ksplat(path: String) raises -> GaussianSplatGeometry:
    """Read a `.ksplat` file.

    Args:
        path: The file.

    Returns:
        Its splats; see `parse_ksplat`.

    Raises:
        Error: If the file cannot be read, or anything `parse_ksplat`
            raises.
    """
    return parse_ksplat(Path(path).read_bytes())
