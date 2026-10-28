# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md

"""Write a JPEG file with Pillow's libjpeg settings.

    carla_jpeg REQUEST OUT

`REQUEST` is JSON with `mode`, `width`, `height`, `quality`, `optimize`
and `pixels`. `mode` is `L` or `RGB`. `quality` -1 keeps libjpeg's
default. The file matches Pillow 12.3 `Image.save` for that image.
"""

from std.memory import OpaquePointer
from std.pathlib import Path
from std.sys import argv, exit, stderr

from tools._pillow_jpeg import (
    jpeg_library,
    c_pointer,
    store_u32,
    store_u64,
    store_i32,
)
from tools._python_json import PY_BOOL, PY_DICT, PY_INT, PY_LIST, PY_STR, PyJson

# libjpeg-turbo 6b ABI, the library Pillow 12.3 links. The struct is 520
# bytes. `optimize_coding` is a 4-byte boolean at byte 264.
comptime _COMPRESS_BYTES = 520
comptime _ERROR_BYTES = 168
comptime _LIB_VERSION = 62
comptime _IMAGE_WIDTH = 48
comptime _IMAGE_HEIGHT = 52
comptime _INPUT_COMPONENTS = 56
comptime _IN_COLOR_SPACE = 60
comptime _OPTIMIZE = 264
comptime _JCS_GRAYSCALE = 1
comptime _JCS_RGB = 2


def jpeg_text(text: String) raises -> List[UInt8]:
    """Return JPEG bytes for one JSON image.

    Args:
        text: A JSON object with `mode`, `width`, `height`, `quality`,
            `optimize` and `pixels`.

    Returns:
        The JPEG file. It matches Pillow's `Image.save` for `L` and
        `RGB`.

    Raises:
        Error: If the JSON is not that image, libjpeg 6.2 cannot be
            loaded, or compression fails.
    """
    var doc = PyJson.parse(text)
    var root = doc.root
    if doc.kind(root) != PY_DICT:
        raise Error("jpeg request is not an object")
    var mode_node = doc.at(root, "mode")
    if doc.kind(mode_node) != PY_STR:
        raise Error("jpeg mode is not L or RGB")
    var mode = doc.text(mode_node)
    var bands: Int
    var color: Int
    if mode == "L":
        bands = 1
        color = _JCS_GRAYSCALE
    elif mode == "RGB":
        bands = 3
        color = _JCS_RGB
    else:
        raise Error("jpeg mode is not L or RGB")
    var width = _whole(doc, doc.at(root, "width"))
    var height = _whole(doc, doc.at(root, "height"))
    if width < 1 or height < 1:
        raise Error("jpeg size is not positive")
    if width > 4096 or height > 4096:
        raise Error("jpeg size is too large")
    var quality = _whole(doc, doc.at(root, "quality"))
    if quality < -1 or quality > 100:
        raise Error("jpeg quality is out of range")
    var optimize = _flag(doc, doc.at(root, "optimize"))
    var pixels = _pixels(doc, doc.at(root, "pixels"), width * height * bands)
    return _encode(width, height, bands, color, quality, optimize, pixels)


def _encode(
    width: Int,
    height: Int,
    bands: Int,
    color: Int,
    quality: Int,
    optimize: Bool,
    pixels: List[UInt8],
) raises -> List[UInt8]:
    """Compress one image with Pillow's libjpeg calls."""
    var library = jpeg_library()
    var cinfo = List[UInt8](length=_COMPRESS_BYTES, fill=0)
    var jerr = List[UInt8](length=_ERROR_BYTES, fill=0)
    var cinfo_ptr = c_pointer(Int(cinfo.unsafe_ptr()))
    store_u64(cinfo, 0, UInt64(Int(jerr.unsafe_ptr())))
    _ = library.call["jpeg_std_error", OpaquePointer[MutAnyOrigin]](
        c_pointer(Int(jerr.unsafe_ptr()))
    )
    library.call["jpeg_CreateCompress", NoneType](
        cinfo_ptr, Int32(_LIB_VERSION), UInt64(_COMPRESS_BYTES)
    )
    var capacity = width * height * bands * 2 + 65536
    var storage = List[UInt8](length=capacity, fill=0)
    var owned = UInt64(Int(storage.unsafe_ptr()))
    var out_ptr = List[UInt64](length=1, fill=owned)
    var out_size = List[UInt64](length=1, fill=UInt64(capacity))
    library.call["jpeg_mem_dest", NoneType](
        cinfo_ptr,
        c_pointer(Int(out_ptr.unsafe_ptr())),
        c_pointer(Int(out_size.unsafe_ptr())),
    )
    store_u32(cinfo, _IMAGE_WIDTH, UInt32(width))
    store_u32(cinfo, _IMAGE_HEIGHT, UInt32(height))
    store_i32(cinfo, _INPUT_COMPONENTS, Int32(bands))
    store_i32(cinfo, _IN_COLOR_SPACE, Int32(color))
    library.call["jpeg_set_defaults", NoneType](cinfo_ptr)
    if quality >= 0:
        library.call["jpeg_set_quality", NoneType](
            cinfo_ptr, Int32(quality), Int32(1)
        )
    var flag = 0
    if optimize:
        flag = 1
    store_i32(cinfo, _OPTIMIZE, Int32(flag))
    library.call["jpeg_start_compress", NoneType](cinfo_ptr, Int32(1))
    var row = List[UInt8](length=width * bands, fill=0)
    var row_ptr = List[UInt64](length=1, fill=0)
    for y in range(height):
        var origin = y * width * bands
        for index in range(width * bands):
            row[index] = pixels[origin + index]
        row_ptr[0] = UInt64(Int(row.unsafe_ptr()))
        var wrote = library.call["jpeg_write_scanlines", UInt32](
            cinfo_ptr, c_pointer(Int(row_ptr.unsafe_ptr())), UInt32(1)
        )
        if wrote != 1:
            library.call["jpeg_destroy_compress", NoneType](cinfo_ptr)
            # libjpeg holds bare addresses of both, so they live to here.
            _ = len(cinfo)
            _ = len(jerr)
            raise Error("jpeg scanline was not written")
    library.call["jpeg_finish_compress", NoneType](cinfo_ptr)
    var address = Int(out_ptr[0])
    var size = Int(out_size[0])
    if address == 0 or size < 1 or size > capacity:
        library.call["jpeg_destroy_compress", NoneType](cinfo_ptr)
        # libjpeg holds bare addresses of both, so they live to here.
        _ = len(cinfo)
        _ = len(jerr)
        raise Error("jpeg file is empty")
    if UInt64(address) != owned:
        library.call["jpeg_destroy_compress", NoneType](cinfo_ptr)
        # libjpeg holds bare addresses of both, so they live to here.
        _ = len(cinfo)
        _ = len(jerr)
        raise Error("jpeg output grew past the buffer")
    library.call["jpeg_destroy_compress", NoneType](cinfo_ptr)
    # libjpeg holds bare addresses of both, so they live to here.
    _ = len(cinfo)
    _ = len(jerr)
    storage.resize(size, 0)
    return storage^


def _pixels(doc: PyJson, node: Int, count: Int) raises -> List[UInt8]:
    """Read the sample bytes."""
    if doc.kind(node) != PY_LIST:
        raise Error("jpeg pixels are not a list")
    if doc.length(node) != count:
        raise Error("jpeg pixels do not match the image")
    var out = List[UInt8]()
    for index in range(count):
        var value = _whole(doc, doc.item(node, index))
        if value < 0 or value > 255:
            raise Error("jpeg sample is out of range")
        out.append(UInt8(value))
    return out^


def _whole(doc: PyJson, node: Int) raises -> Int:
    """Return a JSON integer."""
    if doc.kind(node) != PY_INT:
        raise Error("jpeg field is not an integer")
    var raw = doc.text(node).as_bytes()
    var index = 0
    var negative = False
    if len(raw) > 0 and raw[0] == 45:
        negative = True
        index = 1
    var value = 0
    for offset in range(index, len(raw)):
        var byte = raw[offset]
        if byte < 48 or byte > 57:
            raise Error("jpeg field is not an integer")
        value = value * 10 + Int(byte - 48)
    if negative:
        return -value
    return value


def _flag(doc: PyJson, node: Int) raises -> Bool:
    """Return a JSON bool."""
    if doc.kind(node) != PY_BOOL:
        raise Error("optimize is not a bool")
    return doc.flag(node)


def main() raises:
    """Write the JPEG file named on the command line.

    Raises:
        Error: If the standard streams cannot be written.
    """
    var arguments = argv()
    if len(arguments) != 3:
        print("usage: carla_jpeg REQUEST OUT", file=stderr)
        exit(2)
    try:
        var payload = jpeg_text(Path(arguments[1]).read_text())
        Path(arguments[2]).write_bytes(Span(payload))
    except error:
        print("carla_jpeg:", error, file=stderr)
        exit(1)
