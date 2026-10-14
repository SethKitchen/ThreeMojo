# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Package verified native files as reviewable UTF-8 hex and audit metadata.

    mojo run -I . assets/exr_codecs/package_fixtures.mojo FIXTURES [DESTINATION]

Run it from the repository root. DESTINATION is `assets/exr_codecs` unless
it is given. For each `*.exr` file in FIXTURES, the tool writes the file and
its decoded `.rgba` samples as hex, and records the file's layout, its
hashes and, when a `.input` source is present, the decoding error.
"""

from std.memory import bitcast
from std.os import listdir
from std.pathlib import Path
from std.sys import argv, exit, stderr

from tools._json_tools import JsonWriter
from tools._python_float import python_repr
from tools._sha256 import sha256_hex

comptime HEX = "0123456789abcdef"
comptime LINE = 128
"""The hex digits on each line of a packaged file."""


def _u32(data: List[UInt8], at: Int) -> Int:
    """Read a little-endian unsigned 32-bit integer."""
    return (
        Int(data[at])
        | (Int(data[at + 1]) << 8)
        | (Int(data[at + 2]) << 16)
        | (Int(data[at + 3]) << 24)
    )


def _i32(data: List[UInt8], at: Int) -> Int:
    """Read a little-endian signed 32-bit integer."""
    var value = _u32(data, at)
    return value - (1 << 32) if value >= 1 << 31 else value


def _u64(data: List[UInt8], at: Int) -> Int:
    """Read a little-endian 64-bit offset."""
    return _u32(data, at) | (_u32(data, at + 4) << 32)


def _f32(data: List[UInt8], at: Int) -> Float64:
    """Read a little-endian Float32 as a double."""
    return Float64(bitcast[DType.float32](UInt32(_u32(data, at))))


def _find_zero(data: List[UInt8], start: Int) raises -> Int:
    """Return the index of the first zero byte at or after start."""
    for index in range(start, len(data)):
        if data[index] == 0:
            return index
    raise Error("missing NUL terminator")


def hex_lines(data: List[UInt8]) -> String:
    """Return lowercase hex, 128 digits a line, each line ended.

    Args:
        data: The bytes.

    Returns:
        The text.
    """
    var digits = HEX.as_bytes()
    var out = String(capacity_bytes=2 * len(data) + len(data) // 64 + 1)
    for index in range(len(data)):
        if index > 0 and index % (LINE // 2) == 0:
            out += "\n"
        out += chr(Int(digits[Int(data[index] >> 4)]))
        out += chr(Int(digits[Int(data[index] & 15)]))
    return out + "\n"


@fieldwise_init
struct Channel(Copyable, Movable):
    """One channel of an EXR header."""

    var name: String
    """The channel name."""
    var kind: Int
    """The pixel type: 0 uint, 1 half, 2 float."""
    var linear: Bool
    """The pLinear flag."""


@fieldwise_init
struct Chunk(Copyable, Movable):
    """One scan-line chunk."""

    var line: Int
    """The first scan line."""
    var size: Int
    """The stored size in bytes."""
    var raw_size: Int
    """The uncompressed size in bytes."""


struct Record(Copyable, Movable):
    """The layout and hashes of one packaged file."""

    var name: String
    """The file name."""
    var codec: Int
    """The compression code."""
    var width: Int
    """The data window's width."""
    var height: Int
    """The data window's height."""
    var channels: List[Channel]
    """The channels, in header order."""
    var chunks: List[Chunk]
    """The chunks, in offset-table order."""
    var hashes: List[String]
    """The SHA-256 of the file and of its `.rgba` samples."""
    var errors: List[Float64]
    """The absolute, scaled and alpha errors against the source, if any."""

    def __init__(out self, name: String):
        """Start an empty record.

        Args:
            name: The file name.
        """
        self.name = name
        self.codec = 0
        self.width = 0
        self.height = 0
        self.channels = List[Channel]()
        self.chunks = List[Chunk]()
        self.hashes = List[String]()
        self.errors = List[Float64]()


def read_layout(name: String, data: List[UInt8]) raises -> Record:
    """Read an EXR header and its chunk table.

    Args:
        name: The file name.
        data: The file.

    Returns:
        The record, without hashes or errors.

    Raises:
        Error: If the header is malformed.
    """
    var record = Record(name)
    var at = 8
    var x0 = 0
    var y0 = 0
    var x1 = -1
    var y1 = -1
    while data[at] != 0:
        var end = _find_zero(data, at)
        var attribute = String(unsafe_from_utf8=Span(data)[at:end])
        at = _find_zero(data, end + 1) + 1
        var size = _u32(data, at)
        at += 4
        var value = List[UInt8](Span(data)[at : at + size])
        at += size
        if attribute == "channels":
            var position = 0
            while value[position] != 0:
                var stop = _find_zero(value, position)
                record.channels.append(
                    Channel(
                        String(unsafe_from_utf8=Span(value)[position:stop]),
                        _u32(value, stop + 1),
                        value[stop + 5] != 0,
                    )
                )
                position = stop + 17
        elif attribute == "dataWindow":
            x0 = _i32(value, 0)
            y0 = _i32(value, 4)
            x1 = _i32(value, 8)
            y1 = _i32(value, 12)
        elif attribute == "compression":
            record.codec = Int(value[0])
    at += 1
    record.width = x1 - x0 + 1
    record.height = y1 - y0 + 1
    var lines: List[Int] = [1, 1, 1, 16, 32, 16, 32, 32, 32, 256]
    var per = lines[record.codec]
    var texel = 0
    for channel in record.channels:
        texel += 2 if channel.kind == 1 else 4
    for index in range((record.height + per - 1) // per):
        var offset = _u64(data, at + 8 * index)
        var y = _i32(data, offset)
        var rows = min(per, record.height - y + y0)
        record.chunks.append(
            Chunk(y, _u32(data, offset + 4), record.width * rows * texel)
        )
    return record^


def _floats(data: List[UInt8]) -> List[Float64]:
    """Read every little-endian Float32."""
    var out = List[Float64]()
    for at in range(0, len(data) - 3, 4):
        out.append(_f32(data, at))
    return out^


def source_errors(source: List[UInt8], decoded: List[UInt8]) -> List[Float64]:
    """Return the largest absolute, scaled and alpha errors.

    Args:
        source: The source samples, as little-endian Float32.
        decoded: The decoded samples, as little-endian Float32.

    Returns:
        The three errors.
    """
    var a = _floats(source)
    var b = _floats(decoded)
    var count = min(len(a), len(b))
    var absolute = 0.0
    var scaled = 0.0
    var alpha = 0.0
    for index in range(count):
        var error = abs(a[index] - b[index])
        if index == 0 or error > absolute:
            absolute = error
        var relative = error / max(1.0, abs(a[index]))
        if index == 0 or relative > scaled:
            scaled = relative
    for index in range(3, len(a), 4):
        var error = abs(a[index] - b[index])
        if index == 3 or error > alpha:
            alpha = error
    return [absolute, scaled, alpha]


def write_record(mut out: JsonWriter, record: Record):
    """Write one record as the Python packager wrote its dictionary.

    Args:
        out: The writer.
        record: The record.
    """
    out.begin_object()
    out.key("name")
    out.string(record.name)
    out.key("codec")
    out.integer(record.codec)
    out.key("width")
    out.integer(record.width)
    out.key("height")
    out.integer(record.height)
    out.key("channels")
    out.begin_array()
    for channel in record.channels:
        out.begin_object()
        out.key("name")
        out.string(channel.name)
        out.key("type")
        out.integer(channel.kind)
        out.key("pLinear")
        out.boolean(channel.linear)
        out.end()
    out.end()
    out.key("chunks")
    out.begin_array()
    for chunk in record.chunks:
        out.begin_object()
        out.key("line")
        out.integer(chunk.line)
        out.key("size")
        out.integer(chunk.size)
        out.key("raw_size")
        out.integer(chunk.raw_size)
        out.key("compressed")
        out.boolean(chunk.size < chunk.raw_size)
        out.end()
    out.end()
    out.key("sha256")
    out.string(record.hashes[0])
    out.key("sha256.rgba")
    out.string(record.hashes[1])
    if len(record.errors) == 3:
        out.key("max_source_absolute_error")
        out.number(record.errors[0])
        out.key("max_source_scaled_error")
        out.number(record.errors[1])
        out.key("max_alpha_error")
        out.number(record.errors[2])
    out.end()


def package(fixtures: String, destination: String) raises -> String:
    """Package every `*.exr` file and write the manifest.

    Args:
        fixtures: The folder of native files.
        destination: The folder for the hex files and `manifest.json`.

    Returns:
        One summary line for each DWA, PXR24 and B44 codec.

    Raises:
        Error: If a file cannot be read or written.
    """
    var names = List[String]()
    for name in listdir(fixtures):
        if name.endswith(".exr"):
            names.append(name)
    sort(names)
    var records = List[Record]()
    for name in names:
        var path = fixtures + "/" + name
        var data = Path(path).read_bytes()
        var record = read_layout(name, data)
        for suffix in ["", ".rgba"]:
            var bytes = Path(path + suffix).read_bytes()
            Path(destination + "/" + name + suffix + ".hex").write_text(
                hex_lines(bytes)
            )
            record.hashes.append(sha256_hex(Span(bytes)))
        if Path(path + ".input").exists():
            record.errors = source_errors(
                Path(path + ".input").read_bytes(),
                Path(path + ".rgba").read_bytes(),
            )
        records.append(record^)
    var out = JsonWriter()
    out.begin_object()
    out.key("reference")
    out.string("OpenEXR 3.1.5; Imath 3.1.5")
    out.key("archive_sha256")
    out.begin_object()
    out.key("OpenEXR")
    out.string(
        "93925805c1fc4f8162b35f0ae109c4a75344e6decae5a240afdfce25f8a433ec"
    )
    out.key("Imath")
    out.string(
        "1e9c7c94797cf7b7e61908aed1f80a331088cc7d8873318f70376e4aed5f25fb"
    )
    out.end()
    out.key("fixtures")
    out.begin_array()
    for record in records:
        write_record(out, record)
    out.end()
    out.end()
    Path(destination + "/manifest.json").write_text(out.text() + "\n")
    var summary = String()
    for codec in range(5, 10):
        var cases = 0
        var compressed = 0
        var largest = 0.0
        var any_error = False
        for record in records:
            if record.codec != codec:
                continue
            cases += 1
            for chunk in record.chunks:
                if chunk.size < chunk.raw_size:
                    compressed += 1
            if len(record.errors) == 3 and (
                not any_error or record.errors[1] > largest
            ):
                largest = record.errors[1]
                any_error = True
        summary += (
            String(codec)
            + " "
            + String(cases)
            + " compressed chunks "
            + String(compressed)
            + " max source scaled error "
            + (python_repr(largest) if any_error else "0")
            + "\n"
        )
    return summary


def main() raises:
    var given = argv()
    if len(given) < 2 or len(given) > 3:
        print("usage: package_fixtures FIXTURES [DESTINATION]", file=stderr)
        exit(2)
    var destination = (
        String(given[2]) if len(given) == 3 else "assets/exr_codecs"
    )
    print(package(String(given[1]), destination), end="")
