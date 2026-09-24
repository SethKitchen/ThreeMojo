# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""An UltraHDR (JPEG_R) file read as an HDR image: three.js's
`UltraHDRLoader`.

An UltraHDR file is two JPEG files in one. The first is the SDR image.
Its APP2 segment is a Multi-Picture Format (MPF) index that says where
the second, the gain map, starts and how long it is. The gain map's APP1
segment is XMP whose `hdrgm` attributes say how to use it. The HDR image
is the SDR image, made brighter where the gain map says, by three.js's
recovery formula:

    boost    = min * (1 - g) + max * g,      g = gain ^ (1 / gamma)
    hdr      = (sdr + offsetSDR) * 2 ^ (boost * weight) - offsetHDR
    weight   = clamp((log2(sqrt(1.8 ^ capMax)) - capMin) / (capMax - capMin))

`sdr` is the byte, from 0 to 255, and the result goes to linear light
through three.js's table of `SRGBToLinear`, which takes the whole part
of a value below 1024. It is clamped to 0 and 65,504. `parse_ultrahdr`
returns the image and the metadata, and `float_texture_from(image,
mipmapped=True)` makes the texture that three.js makes: `CLAMP`,
`BILINEAR` with a chain, and `LINEAR`.

**The segments.** three.js scans every byte of the file for the markers
of the start of an image and of APP0, APP1 and APP2. This port walks the
segments of each JPEG file by their lengths. It reads the XMP of an APP1
segment that holds XMP, and the MPF entries at the offsets three.js
reads them at: the image sizes and offsets that libultrahdr writes.

**Where this port differs.**

- A browser decodes each JPEG file. This port decodes them with
  `render.jpeg`, which agrees with libjpeg to one level.
- A browser's canvas scales a gain map of another size, with a filter of
  its own. This port scales it bilinearly, from the centers of the
  texels.
- three.js fills each alpha with 255, the value it writes for a half of
  255. This port writes an alpha of one.
- three.js keeps halves by default. This port keeps floats, as three.js's
  `setDataType(FloatType)` does.
- three.js throws a `TypeError` for an APP1 segment that is not XMP,
  such as EXIF data. This port reads past it. A number in the metadata
  that is not finite, or an HDR capacity range of zero, is refused.
  three.js gives an image of `NaN`s.
"""

from loaders.js_number import js_log2, js_parse_float, js_pow
from loaders.xml import XmlDocument, parse_xml
from render.float_image import FloatImage
from render.jpeg import decode as decode_jpeg
from render.png import DecodedImage
from std.math import floor, isfinite, nan, sqrt
from std.pathlib import Path

# The name that starts the XMP of an APP1 segment.
comptime XMP_NAMESPACE = "http://ns.adobe.com/xap/1.0/"
# Where three.js reads the MPF entries, from the segment's length field.
comptime _MPF_ENTRIES = 60
# The largest half, which three.js clamps to.
comptime _HALF_MAX = 65504.0


struct UltraHdrMetadata(Copyable, Movable):
    """The `hdrgm` attributes of the gain map's XMP, as three.js reads
    them."""

    # `hdrgm:Version`. An UltraHDR file must have one.
    var version: String
    # `hdrgm:BaseRenditionIsHDR` is `True`.
    var base_rendition_is_hdr: Bool
    # `hdrgm:GainMapMin` and `GainMapMax`, in stops: 0 and 1 by default.
    var gain_map_min: Float64
    var gain_map_max: Float64
    # `hdrgm:Gamma`: 1 by default.
    var gamma: Float64
    # `hdrgm:OffsetSDR` and `OffsetHDR` times 64, on a scale of 0 to
    # 255: zero when there is none.
    var offset_sdr: Float64
    var offset_hdr: Float64
    # `hdrgm:HDRCapacityMin` and `HDRCapacityMax`, in stops: 0 and 1 by
    # default.
    var hdr_capacity_min: Float64
    var hdr_capacity_max: Float64

    def __init__(out self):
        """Start with no version and three.js's defaults."""
        self.version = String()
        self.base_rendition_is_hdr = False
        self.gain_map_min = 0
        self.gain_map_max = 1
        self.gamma = 1
        self.offset_sdr = 0
        self.offset_hdr = 0
        self.hdr_capacity_min = 0
        self.hdr_capacity_max = 1


struct UltraHdrImage(Movable):
    """What `parse_ultrahdr` read: the HDR image and the metadata."""

    var image: FloatImage
    var metadata: UltraHdrMetadata

    def __init__(
        out self, var image: FloatImage, var metadata: UltraHdrMetadata
    ):
        """Hold an image and its metadata."""
        self.image = image^
        self.metadata = metadata^


def _u16(bytes: List[UInt8], at: Int) -> Int:
    """Return a big-endian 16-bit number."""
    return (Int(bytes[at]) << 8) | Int(bytes[at + 1])


def _u32(bytes: List[UInt8], at: Int, little: Bool) -> Int:
    """Return a 32-bit number."""
    if little:
        return (
            Int(bytes[at])
            | (Int(bytes[at + 1]) << 8)
            | (Int(bytes[at + 2]) << 16)
            | (Int(bytes[at + 3]) << 24)
        )
    return (
        (Int(bytes[at]) << 24)
        | (Int(bytes[at + 1]) << 16)
        | (Int(bytes[at + 2]) << 8)
        | Int(bytes[at + 3])
    )


def _starts_with(bytes: List[UInt8], at: Int, end: Int, text: String) -> Bool:
    """Return True if the bytes from `at` start with `text`."""
    var t = text.as_bytes()
    if at + len(t) > end:
        return False
    # The texts are not empty. The loop always runs.
    for i in range(len(t)):  # pragma: no branch
        if bytes[at + i] != t[i]:
            return False
    return True


def _js_number(text: String) -> Float64:
    """Return JavaScript's `Number(text)`: blank is zero, and anything
    that is not a whole number text is NaN."""
    var trimmed = String(text.strip())
    if trimmed.byte_length() == 0:
        return 0
    var value = js_parse_float(trimmed)
    # `parseFloat` stops at the end of the number, `Number` does not: the
    # text must be the number and nothing else.
    try:
        if Float64(trimmed) == value:
            return value
    except:
        pass
    return nan[DType.float64]()


def _attribute_or(
    document: XmlDocument, element: Int, key: String, fallback: Float64
) raises -> Float64:
    """Return three.js's `parseFloat(node.getAttribute(key) || fallback)`."""
    if not document.has_attribute(element, key):
        return fallback
    var text = document.attribute(element, key)
    if text.byte_length() == 0:
        return fallback
    return js_parse_float(text)


def _offset(document: XmlDocument, element: Int, key: String) raises -> Float64:
    """Return three.js's `node.getAttribute(key) / (1 / 64)`: a missing
    offset is zero."""
    if not document.has_attribute(element, key):
        return 0
    return _js_number(document.attribute(element, key)) * 64


def _read_xmp(text: String, mut metadata: UltraHdrMetadata) raises:
    """Read the XMP of one APP1 segment, as three.js's `_parseXMPMetadata`
    does: a container directory says nothing, and the first
    `rdf:Description` of any other holds the `hdrgm` attributes."""
    var bytes = text.as_bytes()
    var first = -1
    var last = -1
    # An XMP segment holds its namespace's text. The loop always runs.
    for i in range(len(bytes)):  # pragma: no branch
        if bytes[i] == 60 and first < 0:
            first = i
        if bytes[i] == 62:
            last = i
    if first < 0 or last < first:
        return
    var document = parse_xml(String(text[byte = first : last + 1]))
    var description = -1
    # A document has its root. The loop always runs.
    for element in range(document.count()):  # pragma: no branch
        var name = document.name(element)
        if name == "Container:Directory":
            return
        if name == "rdf:Description" and description < 0:
            description = element
    if description < 0:
        return
    var d = description
    metadata.version = document.attribute(
        d, "hdrgm:Version"
    ) if document.has_attribute(d, "hdrgm:Version") else String()
    metadata.base_rendition_is_hdr = (
        document.has_attribute(d, "hdrgm:BaseRenditionIsHDR")
        and document.attribute(d, "hdrgm:BaseRenditionIsHDR") == "True"
    )
    metadata.gain_map_min = _attribute_or(document, d, "hdrgm:GainMapMin", 0)
    metadata.gain_map_max = _attribute_or(document, d, "hdrgm:GainMapMax", 1)
    metadata.gamma = _attribute_or(document, d, "hdrgm:Gamma", 1)
    metadata.offset_sdr = _offset(document, d, "hdrgm:OffsetSDR")
    metadata.offset_hdr = _offset(document, d, "hdrgm:OffsetHDR")
    metadata.hdr_capacity_min = _attribute_or(
        document, d, "hdrgm:HDRCapacityMin", 0
    )
    metadata.hdr_capacity_max = _attribute_or(
        document, d, "hdrgm:HDRCapacityMax", 1
    )


struct _Images(Movable):
    """Where the MPF index puts the two images."""

    var primary_offset: Int
    var primary_size: Int
    var gain_offset: Int
    var gain_size: Int

    def __init__(out self):
        """Start with no gain map."""
        self.primary_offset = 0
        self.primary_size = 0
        self.gain_offset = -1
        self.gain_size = 0


def _read_segments(
    bytes: List[UInt8],
    start: Int,
    end: Int,
    mut metadata: UltraHdrMetadata,
    mut images: _Images,
) raises:
    """Walk the marker segments of one JPEG file, up to its scan, and read
    its XMP and its MPF index."""
    if end - start < 4 or bytes[start] != 0xFF or bytes[start + 1] != 0xD8:
        raise Error("UltraHDR: a JPEG file must start with its SOI marker")
    var at = start + 2
    while at + 4 <= end:
        if bytes[at] != 0xFF:
            raise Error("UltraHDR: a JPEG segment must start with 0xFF")
        var marker = Int(bytes[at + 1])
        # The scan, or the end: no more segments to read.
        if marker == 0xDA or marker == 0xD9:
            return
        var length = _u16(bytes, at + 2)
        var payload = at + 4
        var stop = at + 2 + length
        if length < 2 or stop > end:
            raise Error("UltraHDR: a JPEG segment runs past the file")
        if marker == 0xE1 and _starts_with(bytes, payload, stop, XMP_NAMESPACE):
            var text = String(
                unsafe_from_utf8=bytes[
                    payload + len(XMP_NAMESPACE.as_bytes()) + 1 : stop
                ]
            )
            _read_xmp(text, metadata)
        elif marker == 0xE2 and _starts_with(bytes, payload, stop, "MPF\0"):
            # three.js's offsets are from the segment's length field.
            var base = at + 2
            if base + _MPF_ENTRIES + 24 > stop:
                raise Error("UltraHDR: the MPF segment is cut short")
            var little = _starts_with(bytes, base + 6, stop, "II*\0")
            images.primary_size = _u32(bytes, base + _MPF_ENTRIES, little)
            images.primary_offset = _u32(bytes, base + _MPF_ENTRIES + 4, little)
            images.gain_size = _u32(bytes, base + _MPF_ENTRIES + 16, little)
            # The gain map's offset is from the TIFF header, after the
            # length field and "MPF\0".
            images.gain_offset = (
                _u32(bytes, base + _MPF_ENTRIES + 20, little) + base + 6
            )
        at = stop
    raise Error("UltraHDR: a JPEG file ends before its scan")


def _slice(bytes: List[UInt8], offset: Int, size: Int) raises -> List[UInt8]:
    """Return one of the two images, checked against the file."""
    if size < 1 or offset + size > len(bytes):
        raise Error("UltraHDR: an image of the MPF index runs past the file")
    return List[UInt8](bytes[offset : offset + size])


def scale_gain_map(gain: DecodedImage, width: Int, height: Int) -> List[UInt8]:
    """Return a gain map scaled to the SDR image's size: bilinear, from
    the centers of the texels, as a canvas scales an image.

    Args:
        gain: The gain map.
        width: The SDR image's width.
        height: The SDR image's height.

    Returns:
        RGBA bytes, `width * height * 4` of them. A gain map of the same
        size comes back as it is.
    """
    if gain.width == width and gain.height == height:
        return gain.pixels.copy()
    var out = List[UInt8](length=width * height * 4, fill=0)
    var sx = Float64(gain.width) / Float64(width)
    var sy = Float64(gain.height) / Float64(height)
    # A decoded image has one texel or more, so these loops always run.
    for y in range(height):  # pragma: no branch
        var fy = max((Float64(y) + 0.5) * sy - 0.5, 0.0)
        var y0 = min(Int(floor(fy)), gain.height - 1)
        var y1 = min(y0 + 1, gain.height - 1)
        var ty = fy - Float64(y0)
        for x in range(width):  # pragma: no branch
            var fx = max((Float64(x) + 0.5) * sx - 0.5, 0.0)
            var x0 = min(Int(floor(fx)), gain.width - 1)
            var x1 = min(x0 + 1, gain.width - 1)
            var tx = fx - Float64(x0)
            for c in range(4):  # pragma: no branch
                var a = Float64(gain.pixels[(y0 * gain.width + x0) * 4 + c])
                var b = Float64(gain.pixels[(y0 * gain.width + x1) * 4 + c])
                var d = Float64(gain.pixels[(y1 * gain.width + x0) * 4 + c])
                var e = Float64(gain.pixels[(y1 * gain.width + x1) * 4 + c])
                var top = a + (b - a) * tx
                var bottom = d + (e - d) * tx
                out[(y * width + x) * 4 + c] = UInt8(
                    Int(floor(top + (bottom - top) * ty + 0.5))
                )
    return out^


def _srgb_to_linear(value: Float64) -> Float64:
    """Return three.js's `_srgbToLinear`: its table for a value below
    1024, which takes the value's whole part."""
    if value / 255 < 0.04045:
        return (value / 255) * 0.0773993808
    var whole = floor(value) if value < 1024 else value
    return js_pow(whole / 255 * 0.9478672986 + 0.0521327014, 2.4)


def apply_gain_map(
    sdr: DecodedImage, gain: DecodedImage, metadata: UltraHdrMetadata
) raises -> FloatImage:
    """Return the HDR image of an SDR image and its gain map, by three.js's
    `_applyGainmapToSDR`.

    Args:
        sdr: The SDR image, as sRGB bytes.
        gain: The gain map, of the same aspect ratio. It is scaled to the
            SDR image's size.
        metadata: The `hdrgm` attributes.

    Returns:
        Linear RGBA floats, from the top row down, with an alpha of one.

    Raises:
        Error: If the two images' aspect ratios differ, a number of the
            metadata is not finite, or the HDR capacity range is zero.
    """
    if Float64(sdr.width) / Float64(sdr.height) != Float64(
        gain.width
    ) / Float64(gain.height):
        raise Error(
            "UltraHDR: the SDR image and the gain map must have one aspect"
            " ratio"
        )
    var m = metadata.copy()
    # Seven numbers. The loop always runs.
    for value in [  # pragma: no branch
        m.gain_map_min,
        m.gain_map_max,
        m.gamma,
        m.offset_sdr,
        m.offset_hdr,
        m.hdr_capacity_min,
        m.hdr_capacity_max,
    ]:
        if not isfinite(value):
            raise Error(
                "UltraHDR: a number of the gain map's XMP is not finite"
            )
    if m.hdr_capacity_max == m.hdr_capacity_min:
        raise Error("UltraHDR: the HDR capacity range must not be zero")
    var width = sdr.width
    var height = sdr.height
    var map = scale_gain_map(gain, width, height)
    # 1.8, not 2, as three.js writes, to make up for its table.
    var boost = sqrt(js_pow(1.8, m.hdr_capacity_max))
    var weight = (js_log2(boost) - m.hdr_capacity_min) / (
        m.hdr_capacity_max - m.hdr_capacity_min
    )
    weight = min(max(weight, 0.0), 1.0)
    var gamma_one = m.gamma == 1.0
    var out = List[Float32](length=width * height * 4, fill=1)
    # A decoded image has one texel or more. The loops always run.
    for texel in range(width * height):  # pragma: no branch
        for c in range(3):  # pragma: no branch
            var at = texel * 4 + c
            var sdr_value = Float64(sdr.pixels[at])
            var g = Float64(map[at]) / 255.0
            var recovery = g if gamma_one else js_pow(g, 1.0 / m.gamma)
            var log_boost = (
                m.gain_map_min * (1.0 - recovery) + m.gain_map_max * recovery
            )
            var scale = 1.0 if log_boost * weight == 0.0 else js_pow(
                2.0, log_boost * weight
            )
            var hdr = (sdr_value + m.offset_sdr) * scale - m.offset_hdr
            out[at] = Float32(min(max(_srgb_to_linear(hdr), 0.0), _HALF_MAX))
    return FloatImage(width, height, out^)


def parse_ultrahdr(bytes: List[UInt8]) raises -> UltraHdrImage:
    """Read an UltraHDR file, as three.js's `UltraHDRLoader.parse` does.

    Args:
        bytes: The whole file.

    Returns:
        The HDR image and the gain map's metadata.

    Raises:
        Error: If a JPEG file's segments are not whole, the gain map's XMP
            has no `hdrgm:Version`, there is no MPF index or an image of it
            runs past the file, a JPEG file cannot be decoded, or
            `apply_gain_map` refuses the images.
    """
    var metadata = UltraHdrMetadata()
    var images = _Images()
    _read_segments(bytes, 0, len(bytes), metadata, images)
    if images.gain_offset >= 0:
        # A gain map past the end of the file is refused as a file with no
        # start of image.
        var end = min(images.gain_offset + images.gain_size, len(bytes))
        _read_segments(bytes, images.gain_offset, end, metadata, images)
    if metadata.version.byte_length() == 0:
        raise Error("UltraHDR: not a valid UltraHDR image: no hdrgm:Version")
    if images.gain_offset < 0:
        raise Error("UltraHDR: there is no MPF index of the two images")
    var sdr = decode_jpeg(
        _slice(bytes, images.primary_offset, images.primary_size)
    )
    var gain = decode_jpeg(_slice(bytes, images.gain_offset, images.gain_size))
    return UltraHdrImage(apply_gain_map(sdr, gain, metadata), metadata^)


def read_ultrahdr(path: String) raises -> UltraHdrImage:
    """Read an UltraHDR file from a path.

    Args:
        path: The file.

    Returns:
        The HDR image and the gain map's metadata.

    Raises:
        Error: If the file cannot be read, or `parse_ultrahdr` refuses it.
    """
    return parse_ultrahdr(Path(path).read_bytes())
