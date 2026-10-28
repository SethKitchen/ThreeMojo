# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Pillow's libjpeg 6.2, opened for the CARLA image tools.

The tools encode and decode JPEG with the same library Pillow uses, so
their bytes match the Python tools they replace. `jpeg_library` opens it,
and the `store_*` helpers fill libjpeg's C structures.
"""

from std.ffi import OwnedDLHandle
from std.memory import OpaquePointer
from std.os import getenv, listdir
from std.pathlib import Path


def jpeg_library() raises -> OwnedDLHandle:
    """Open Pillow's libjpeg 6.2: `CARLA_LIBJPEG`, or the first copy that
    `search_jpeg` finds.

    Returns:
        The open library.

    Raises:
        Error: If no copy is found or it cannot be opened.
    """
    var named = getenv("CARLA_LIBJPEG", "")
    if named != "":
        return OwnedDLHandle(named)
    var found = search_jpeg()
    if found == "":
        raise Error("libjpeg 6.2 was not found")
    return OwnedDLHandle(found)


def search_jpeg() raises -> String:
    """Return a path of `libjpeg` 6.2 from a Pillow install, or an empty
    string.

    Returns:
        The path.

    Raises:
        Error: If a folder cannot be listed.
    """
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


def c_pointer(address: Int) -> OpaquePointer[MutAnyOrigin]:
    """Return an address as a C pointer.

    Args:
        address: The address.

    Returns:
        The pointer.
    """
    return OpaquePointer[MutAnyOrigin](unsafe_from_address=address)


def store_u32(mut raw: List[UInt8], offset: Int, value: UInt32):
    """Write one little-endian 32-bit field.

    Args:
        raw: The bytes.
        offset: The first byte.
        value: The value.
    """
    raw[offset] = UInt8(value & 255)
    raw[offset + 1] = UInt8((value >> 8) & 255)
    raw[offset + 2] = UInt8((value >> 16) & 255)
    raw[offset + 3] = UInt8((value >> 24) & 255)


def store_u64(mut raw: List[UInt8], offset: Int, value: UInt64):
    """Write one little-endian 64-bit field.

    Args:
        raw: The bytes.
        offset: The first byte.
        value: The value.
    """
    var rest = value
    for shift in range(8):
        raw[offset + shift] = UInt8(rest & 255)
        rest >>= 8


def store_i32(mut raw: List[UInt8], offset: Int, value: Int32):
    """Write one little-endian signed 32-bit field.

    Args:
        raw: The bytes.
        offset: The first byte.
        value: The value.
    """
    store_u32(raw, offset, UInt32(value))
