# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md

"""Read a PNG or a JPEG as Pillow reads it.

    carla_image FILE
    carla_image unit FILE

`FILE` is an image. The program prints `mode`, `width`, `height` and
`pixels`. `pixels` are RGBA samples, the same bytes as Pillow's
`convert("RGBA")`. `mode` is the mode Pillow's `open` reports.

`unit` reads JSON `pixels` of those bytes. It divides each byte by 255
and prints `rgba`. The values match NumPy's float64 division.
"""

from std.ffi import OwnedDLHandle
from std.memory import OpaquePointer
from std.os import getenv, listdir
from std.pathlib import Path
from std.sys import argv, exit, stderr

from render.png import decode
from tools._python_float import (
    append_ascii,
    ascii_text,
    parse_float,
    python_repr,
)
from tools._python_json import MISSING, PY_DICT, PY_INT, PY_LIST, PyJson

comptime _DECOMPRESS_BYTES = 632
comptime _ERROR_BYTES = 168
comptime _LIB_VERSION = 62
comptime _JPEG_COLOR = 60
comptime _OUT_COLOR = 64
comptime _OUTPUT_WIDTH = 136
comptime _OUTPUT_HEIGHT = 140
comptime _OUTPUT_COMPONENTS = 148
comptime _JCS_GRAYSCALE = 1
comptime _JCS_RGB = 2


def unit_text(text: String) raises -> String:
    """Return RGBA bytes as unit color.

    Args:
        text: JSON with `pixels`, one integer from 0 to 255 per channel.

    Returns:
        JSON `rgba`. Each value is that byte divided by 255.

    Raises:
        Error: If `pixels` is not a list of bytes.
    """
    var doc = PyJson.parse(text)
    var root = doc.root
    if doc.kind(root) != PY_DICT:
        raise Error("unit request is not an object")
    var node = doc.get(root, "pixels")
    if node == MISSING or doc.kind(node) != PY_LIST:
        raise Error("pixels are not a list")
    var out = String('{"rgba":[')
    for index in range(doc.length(node)):
        if index > 0:
            out += ","
        var sample = _byte(doc, doc.item(node, index))
        out += python_repr(_fdiv(Float64(sample), 255.0))
    out += "]}"
    return out^


def image_file(path: String) raises -> String:
    """Return one image as JSON.

    Args:
        path: A PNG or JPEG file.

    Returns:
        `mode`, `width`, `height` and RGBA `pixels`.

    Raises:
        Error: If the file is not a PNG or a JPEG that this reader can
            open, or libjpeg 6.2 cannot be loaded.
    """
    var data = Path(path).read_bytes()
    if _is_png(data):
        return _emit_png(_png_mode(data), data)
    if _is_jpeg(data):
        return _jpeg(data)
    raise Error("image file is not png or jpeg")


def _emit(
    mode: String, width: Int, height: Int, pixels: List[UInt8]
) raises -> String:
    """Return the RGBA image as JSON."""
    var out = List[UInt8]()
    append_ascii(out, '{"mode":"')
    append_ascii(out, mode)
    append_ascii(out, '","width":')
    append_ascii(out, String(width))
    append_ascii(out, ',"height":')
    append_ascii(out, String(height))
    append_ascii(out, ',"pixels":[')
    for index in range(len(pixels)):
        if index > 0:
            append_ascii(out, ",")
        append_ascii(out, String(Int(pixels[index])))
    append_ascii(out, "]}")
    return ascii_text(out)


def _png_mode(data: List[UInt8]) raises -> String:
    """Return the Pillow mode of a PNG color type."""
    if len(data) < 26:
        raise Error("image file is not png or jpeg")
    var kind = Int(data[25])
    if kind == 0:
        return "L"
    if kind == 2:
        return "RGB"
    if kind == 3:
        return "P"
    if kind == 4:
        return "LA"
    if kind == 6:
        return "RGBA"
    raise Error("png color type is not supported")


def _emit_png(mode: String, data: List[UInt8]) raises -> String:
    """Decode a PNG and return its JSON."""
    var image = decode(data)
    return _emit(mode, image.width, image.height, image.pixels)


def _is_png(data: List[UInt8]) -> Bool:
    """Return whether `data` starts with the PNG signature."""
    if len(data) < 8:
        return False
    return (
        data[0] == 137
        and data[1] == 80
        and data[2] == 78
        and data[3] == 71
        and data[4] == 13
        and data[5] == 10
        and data[6] == 26
        and data[7] == 10
    )


def _is_jpeg(data: List[UInt8]) -> Bool:
    """Return whether `data` starts with a JPEG start marker."""
    return len(data) >= 2 and data[0] == 255 and data[1] == 216


def _jpeg(data: List[UInt8]) raises -> String:
    """Decode a JPEG into RGBA pixels."""
    var library = _jpeg_library()
    var cinfo = List[UInt8](length=_DECOMPRESS_BYTES, fill=0)
    var jerr = List[UInt8](length=_ERROR_BYTES, fill=0)
    var cinfo_ptr = _pointer(Int(cinfo.unsafe_ptr()))
    _store_u64(cinfo, 0, UInt64(Int(jerr.unsafe_ptr())))
    _ = library.call["jpeg_std_error", OpaquePointer[MutAnyOrigin]](
        _pointer(Int(jerr.unsafe_ptr()))
    )
    library.call["jpeg_CreateDecompress", NoneType](
        cinfo_ptr, Int32(_LIB_VERSION), UInt64(_DECOMPRESS_BYTES)
    )
    library.call["jpeg_mem_src", NoneType](
        cinfo_ptr, _pointer(Int(data.unsafe_ptr())), UInt64(len(data))
    )
    var header = library.call["jpeg_read_header", Int32](cinfo_ptr, Int32(1))
    if header != 1:
        library.call["jpeg_destroy_decompress", NoneType](cinfo_ptr)
        # libjpeg holds bare addresses of both, so they live to here.
        _ = len(cinfo)
        _ = len(jerr)
        raise Error("jpeg header was not read")
    var mode = String("RGB")
    var out_space = _JCS_RGB
    if _load_i32(cinfo, _JPEG_COLOR) == _JCS_GRAYSCALE:
        mode = "L"
        out_space = _JCS_GRAYSCALE
    _store_i32(cinfo, _OUT_COLOR, Int32(out_space))
    var started = library.call["jpeg_start_decompress", Int32](cinfo_ptr)
    if started == 0:
        library.call["jpeg_destroy_decompress", NoneType](cinfo_ptr)
        # libjpeg holds bare addresses of both, so they live to here.
        _ = len(cinfo)
        _ = len(jerr)
        raise Error("jpeg image did not start")
    var width = Int(_load_u32(cinfo, _OUTPUT_WIDTH))
    var height = Int(_load_u32(cinfo, _OUTPUT_HEIGHT))
    var bands = _load_i32(cinfo, _OUTPUT_COMPONENTS)
    if bands != 1 and bands != 3:
        library.call["jpeg_destroy_decompress", NoneType](cinfo_ptr)
        # libjpeg holds bare addresses of both, so they live to here.
        _ = len(cinfo)
        _ = len(jerr)
        raise Error("jpeg image is not gray or rgb")
    var row = List[UInt8](length=width * bands, fill=0)
    var row_ptr = List[UInt64](length=1, fill=0)
    var pixels = List[UInt8]()
    for _ in range(height):
        row_ptr[0] = UInt64(Int(row.unsafe_ptr()))
        var read = library.call["jpeg_read_scanlines", UInt32](
            cinfo_ptr, _pointer(Int(row_ptr.unsafe_ptr())), UInt32(1)
        )
        if read != 1:
            library.call["jpeg_destroy_decompress", NoneType](cinfo_ptr)
            # libjpeg holds bare addresses of both, so they live to here.
            _ = len(cinfo)
            _ = len(jerr)
            raise Error("jpeg scanline was not read")
        for index in range(width):
            if bands == 1:
                var gray = row[index]
                pixels.append(gray)
                pixels.append(gray)
                pixels.append(gray)
                pixels.append(255)
            else:
                var at = index * 3
                pixels.append(row[at])
                pixels.append(row[at + 1])
                pixels.append(row[at + 2])
                pixels.append(255)
    _ = library.call["jpeg_finish_decompress", Int32](cinfo_ptr)
    library.call["jpeg_destroy_decompress", NoneType](cinfo_ptr)
    # libjpeg holds bare addresses of both, so they live to here.
    _ = len(cinfo)
    _ = len(jerr)
    return _emit(mode, width, height, pixels)


def _jpeg_library() raises -> OwnedDLHandle:
    """Open Pillow's libjpeg 6.2."""
    var named = getenv("CARLA_LIBJPEG", "")
    if named != "":
        return OwnedDLHandle(named)
    var found = _search_jpeg()
    if found == "":
        raise Error("libjpeg 6.2 was not found")
    return OwnedDLHandle(found)


def _search_jpeg() raises -> String:
    """Return a path of `libjpeg` 6.2, or an empty string."""
    var folders = List[String]()
    var home = getenv("HOME", "")
    if home != "":
        for version in range(9, 15):
            _append_pillow_site(
                folders,
                home
                + "/.local/lib/python3."
                + String(version)
                + "/site-packages",
            )
    _append_pillow_site(
        folders, ".venv-carla-export/lib/python3.12/site-packages"
    )
    _append_pillow_site(folders, ".venv/lib/python3.12/site-packages")
    _append_env_pillow_libs(folders)
    for index in range(len(folders)):
        var folder = folders[index]
        if not Path(folder).exists():
            continue
        for name in listdir(folder):
            var text = String(name)
            if not text.startswith("libjpeg"):
                continue
            if text.find(".so") < 0 and text.find(".dylib") < 0:
                continue
            return folder + "/" + text
    return String("")


def _append_env_pillow_libs(mut folders: List[String]):
    """Add Pillow's library folder for the active Python."""
    _append_pillow_root(folders, getenv("VIRTUAL_ENV", ""))
    var path = getenv("PATH", "")
    var raw = path.as_bytes()
    var start = 0
    for index in range(len(raw) + 1):
        if index < len(raw) and raw[index] != 58:
            continue
        var entry = String(path[byte=start:index])
        start = index + 1
        var bytes = entry.as_bytes()
        var count = len(bytes)
        if count < 4:
            continue
        if (
            bytes[count - 4] == 47
            and bytes[count - 3] == 98
            and bytes[count - 2] == 105
            and bytes[count - 1] == 110
        ):
            _append_pillow_root(folders, String(entry[byte = : count - 4]))


def _append_pillow_root(mut folders: List[String], root: String):
    """Add Pillow's library folders under one Python prefix."""
    if root.byte_length() == 0:
        return
    for version in range(9, 15):
        _append_pillow_site(
            folders,
            root + "/lib/python3." + String(version) + "/site-packages",
        )


def _append_pillow_site(mut folders: List[String], site: String):
    """Add Pillow's library folders under one `site-packages` folder.

    Linux wheels keep the libraries in `pillow.libs`. macOS wheels keep
    them in `PIL/.dylibs`, for example `libjpeg.62.4.0.dylib`.
    """
    folders.append(site + "/pillow.libs")
    folders.append(site + "/PIL/.dylibs")


def _pointer(address: Int) -> OpaquePointer[MutAnyOrigin]:
    """Return an address as a C pointer."""
    return OpaquePointer[MutAnyOrigin](unsafe_from_address=address)


def _store_u64(mut raw: List[UInt8], offset: Int, value: UInt64):
    """Write one little-endian 64-bit field."""
    var rest = value
    for shift in range(8):
        raw[offset + shift] = UInt8(rest & 255)
        rest >>= 8


def _store_i32(mut raw: List[UInt8], offset: Int, value: Int32):
    """Write one little-endian 32-bit field."""
    var bits = UInt32(value)
    raw[offset] = UInt8(bits & 255)
    raw[offset + 1] = UInt8((bits >> 8) & 255)
    raw[offset + 2] = UInt8((bits >> 16) & 255)
    raw[offset + 3] = UInt8((bits >> 24) & 255)


def _load_u32(raw: List[UInt8], offset: Int) -> UInt32:
    """Read one little-endian 32-bit field."""
    var value = UInt32(0)
    for shift in range(4):
        value |= UInt32(raw[offset + shift]) << UInt32(8 * shift)
    return value


def _load_i32(raw: List[UInt8], offset: Int) -> Int:
    """Read one little-endian signed 32-bit field as an integer."""
    return Int(_load_u32(raw, offset))


def _byte(doc: PyJson, node: Int) raises -> Int:
    """Return one RGBA byte, or raise when it is not a byte."""
    if doc.kind(node) != PY_INT:
        raise Error("pixel is not an integer")
    var digits = doc.text(node)
    if digits.byte_length() > 3:
        raise Error("pixel is out of range")
    var value = Int(parse_float(digits))
    if value < 0 or value > 255:
        raise Error("pixel is out of range")
    return value


@no_inline
def _fdiv(left: Float64, right: Float64) -> Float64:
    """Return one quotient, rounded before the next operation."""
    return left / right


def main() raises:
    """Print one image, or the unit color of its bytes.

    Raises:
        Error: If the standard streams cannot be written.
    """
    var arguments = argv()
    if len(arguments) == 3 and arguments[1] == "unit":
        try:
            print(unit_text(Path(arguments[2]).read_text()))
        except error:
            print("carla_image:", error, file=stderr)
            exit(1)
        return
    if len(arguments) != 2:
        print("usage: carla_image FILE | carla_image unit FILE", file=stderr)
        exit(2)
    try:
        print(image_file(arguments[1]))
    except error:
        print("carla_image:", error, file=stderr)
        exit(1)
