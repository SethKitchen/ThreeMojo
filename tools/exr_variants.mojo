# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Construct DWA stream variants, then require the pinned native decoder.

    mojo run -I . tools/exr_variants.mojo PATH/TO/reference PATH/TO/libOpenEXR-3_1.so DIR

The input files in DIR come from reference.cpp. Only trusted local fixtures
are passed to the native Huffman API. No variant uses the Mojo decoder.

The streams are compressed with the system zlib, so the variants are the
same, byte for byte, as the Python script's that this tool replaces.
"""

from std.ffi import OwnedDLHandle
from std.memory import bitcast
from std.pathlib import Path
from std.sys import argv, exit, stderr

from tools._process import run_program
from tools._zlib import compress

comptime UNHUF = "_ZN7Imf_3_113hufUncompressEPKciPti"
"""OpenEXR 3.1's `Imf::hufUncompress(const char*, int, unsigned short*, int)`."""


@fieldwise_init
struct Attribute(Copyable, Movable):
    """One header attribute."""

    var name: String
    """The attribute name."""
    var kind: String
    """The attribute type name."""
    var value: List[UInt8]
    """The attribute bytes."""


@fieldwise_init
struct Block(Copyable, Movable):
    """One scan-line chunk."""

    var line: Int
    """The first scan line."""
    var data: List[UInt8]
    """The chunk bytes after its line and size."""


def _u(data: List[UInt8], at: Int, count: Int) -> Int:
    """Read a little-endian unsigned integer of `count` bytes."""
    var value = 0
    for index in range(count):
        value |= Int(data[at + index]) << (8 * index)
    return value


def _put(mut out: List[UInt8], value: Int, count: Int):
    """Append a little-endian integer of `count` bytes."""
    for index in range(count):
        out.append(UInt8((value >> (8 * index)) & 255))


def _slice(data: List[UInt8], start: Int, stop: Int) -> List[UInt8]:
    """Return data[start:stop], clamped as Python clamps a slice."""
    return List[UInt8](Span(data)[min(start, len(data)) : min(stop, len(data))])


def _text(text: String) -> List[UInt8]:
    """Return the bytes of ASCII text."""
    return List[UInt8](text.as_bytes())


def _find_zero(data: List[UInt8], start: Int) raises -> Int:
    """Return the index of the first zero byte at or after start."""
    for index in range(start, len(data)):
        if data[index] == 0:
            return index
    raise Error("missing NUL terminator")


def header(data: List[UInt8]) raises -> Tuple[List[Attribute], Int]:
    """Read the header attributes.

    Args:
        data: The file.

    Returns:
        The attributes and the offset of the chunk table.

    Raises:
        Error: If an attribute is not terminated.
    """
    var at = 8
    var attributes = List[Attribute]()
    while data[at] != 0:
        var end = _find_zero(data, at)
        var name = String(unsafe_from_utf8=Span(data)[at:end])
        at = end + 1
        end = _find_zero(data, at)
        var kind = String(unsafe_from_utf8=Span(data)[at:end])
        at = end + 1
        var length = _u(data, at, 4)
        at += 4
        attributes.append(Attribute(name, kind, _slice(data, at, at + length)))
        at += length
    return (attributes^, at + 1)


def file_bytes(attributes: List[Attribute], blocks: List[Block]) -> List[UInt8]:
    """Write a single-part scan-line file.

    Args:
        attributes: The header attributes.
        blocks: The chunks.

    Returns:
        The file.
    """
    var out = List[UInt8]()
    _put(out, 20000630, 4)
    _put(out, 2, 4)
    for attribute in attributes:
        out.extend(_text(attribute.name))
        out.append(0)
        out.extend(_text(attribute.kind))
        out.append(0)
        _put(out, len(attribute.value), 4)
        out.extend(attribute.value.copy())
    out.append(0)
    var at = len(out) + len(blocks) * 8
    for block in blocks:
        _put(out, at, 8)
        at += 8 + len(block.data)
    for block in blocks:
        _put(out, block.line & 0xFFFFFFFF, 4)
        _put(out, len(block.data), 4)
        out.extend(block.data.copy())
    return out^


def _fields(fields: List[Int]) -> List[UInt8]:
    """Pack the 11 DWA header fields."""
    var out = List[UInt8]()
    for value in fields:
        _put(out, value, 8)
    return out^


def _half(value: Float64) -> Int:
    """Return the bits of the nearest half, as `struct.pack("e")` does."""
    return Int(bitcast[DType.uint16](Float16(value)))


def _float(value: Float64) -> Int:
    """Return the bits of the nearest Float32."""
    return Int(bitcast[DType.uint32](Float32(value)))


struct Builder(Movable):
    """The reference decoder and the native Huffman decoder."""

    var reference: String
    """The reference executable."""
    var library: OwnedDLHandle
    """The OpenEXR library."""
    var root: String
    """The fixture folder."""

    def __init__(
        out self, reference: String, library: String, root: String
    ) raises:
        """Load the OpenEXR library.

        Args:
            reference: The reference executable.
            library: The OpenEXR library.
            root: The fixture folder.

        Raises:
            Error: If the library cannot be loaded.
        """
        self.reference = reference
        self.library = OwnedDLHandle(library)
        self.root = root

    def tokens(self, ac: List[UInt8], count: Int) -> List[UInt16]:
        """Decode Huffman-coded AC tokens with the native decoder.

        Args:
            ac: The compressed AC stream.
            count: The number of tokens.

        Returns:
            The tokens.
        """
        var out = List[UInt16](length=count, fill=0)
        self.library.call[UNHUF, NoneType](
            ac.unsafe_ptr().unsafe_bitcast[NoneType](),
            Int32(len(ac)),
            out.unsafe_ptr().unsafe_bitcast[NoneType](),
            Int32(count),
        )
        return out^

    def save(self, name: String, data: List[UInt8]) raises:
        """Write a variant and require the reference to decode it.

        Args:
            name: The file name, without `.exr`.
            data: The file.

        Raises:
            Error: If the reference refuses the file.
        """
        var path = self.root + "/" + name + ".exr"
        Path(path).write_bytes(data)
        var result = run_program(
            [self.reference, "decode", path, path + ".rgba"], 600.0
        )
        print(result.output, end="")
        if result.status != 0:
            raise Error("the reference refused " + path)


def ac_stream(block: Block) -> Tuple[List[UInt8], Int]:
    """Return a DWA chunk's Huffman-coded AC stream and its token count.

    Args:
        block: The chunk.

    Returns:
        The AC bytes and the number of tokens they hold.
    """
    var data = block.data.copy()
    var rule_size = _u(data, 88, 2)
    var at = 88 + rule_size + _u(data, 16, 8)
    return (_slice(data, at, at + _u(data, 24, 8)), _u(data, 64, 8))


def stored(codec: Int, block: Block) -> Bool:
    """Return True for a last partial strip that is stored uncompressed.

    Args:
        codec: The compression code: 8 or 9.
        block: The chunk.

    Returns:
        True when the chunk holds raw samples.
    """
    var rows = min(
        32 if codec == 8 else 256, (35 if codec == 8 else 257) - block.line
    )
    return len(block.data) == rows * 9 * 8


def needs_tokens(variant: String) -> Bool:
    """Return True for a variant that re-encodes the AC tokens.

    Args:
        variant: The variant name.

    Returns:
        True for `deflate` and `legacy0`.
    """
    return variant == "deflate" or variant == "legacy0"


def stream_variant(
    codec: Int,
    variant: String,
    block: Block,
    tokens: List[UInt16],
) raises -> Block:
    """Rewrite one DWA chunk as a stream variant.

    Args:
        codec: The compression code: 8 or 9.
        variant: `deflate`, `legacy0`, `legacy1`, `insensitive` or
            `rule_shadow`.
        block: The original chunk.
        tokens: The chunk's decoded AC tokens, from `ac_stream`; only
            `deflate` and `legacy0` use them.

    Returns:
        The rewritten chunk.

    Raises:
        Error: If the chunk is not a version 2 DWA chunk.
    """
    var line = block.line
    var data = block.data.copy()
    # Last partial strips can be stored uncompressed.
    if stored(codec, block):
        return block.copy()
    var fields = List[Int]()
    for index in range(11):
        fields.append(_u(data, 8 * index, 8))
    if fields[0] != 2:
        raise Error("expected a version 2 DWA chunk")
    var rule_size = _u(data, 88, 2)
    var rules = _slice(data, 88, 88 + rule_size)
    var at = 88 + rule_size
    var unknown = _slice(data, at, at + fields[2])
    at += fields[2]
    var ac = _slice(data, at, at + fields[3])
    at += fields[3]
    var dc = _slice(data, at, at + fields[4])
    at += fields[4]
    var rle = _slice(data, at, at + fields[5])
    if needs_tokens(variant):
        var tokens = tokens.copy()
        if variant == "legacy0":
            var position = 1
            for index in range(len(tokens)):
                var token = Int(tokens[index])
                if token == 0xFF00:
                    var remaining = 64 - position
                    tokens[index] = UInt16(
                        0 if remaining == 1 else 0xFF00 | remaining
                    )
                    position = 64
                elif token >> 8 == 0xFF:
                    position += token & 255
                else:
                    position += 1
                if position > 64:
                    raise Error("a run passes the end of a block")
                if position == 64:
                    position = 1
        var packed = List[UInt8]()
        for token in tokens:
            _put(packed, Int(token), 2)
        ac = compress(packed, 9)
        fields[3] = len(ac)
        fields[10] = 1
    if variant == "legacy0" or variant == "legacy1":
        fields[0] = 0 if variant == "legacy0" else 1
        rules = List[UInt8]()
    if variant == "rule_shadow":
        # Multiple matching rules preserve every assigned CSC slot.
        var shadow = List[UInt8]()
        _put(shadow, len(rules) + 4, 2)
        shadow.extend(_slice(rules, 2, len(rules)))
        shadow.extend([UInt8(ord("B")), 0, 0x14, 0x01])
        rules = shadow^
    if variant == "insensitive":
        var offset = 2
        while offset < len(rules):
            var end = _find_zero(rules, offset)
            for index in range(offset, end):
                var byte = Int(rules[index])
                if byte >= ord("A") and byte <= ord("Z"):
                    rules[index] = UInt8(byte + 32)
            rules[end + 1] |= 1
            offset = end + 3
    var out = _fields(fields)
    out.extend(rules^)
    out.extend(unknown^)
    out.extend(ac^)
    out.extend(dc^)
    out.extend(rle^)
    return Block(line, out^)


def single_channel(
    attributes: List[Attribute], variant: String
) raises -> Tuple[List[Attribute], List[UInt8]]:
    """Return a 16-square Y image header and its one DWA chunk.

    Args:
        attributes: The source file's attributes.
        variant: `unknown`, `rle`, `uppercase_rule`, `incomplete_csc` or
            `incomplete_rle`.

    Returns:
        The changed attributes and the chunk.

    Raises:
        Error: If zlib fails.
    """
    var size = 16
    var kind = 1 if variant == "rle" or variant == "incomplete_rle" else 2
    var channel = _text("Y")
    channel.append(0)
    _put(channel, kind, 4)
    channel.extend([UInt8(0), 0, 0, 0])
    _put(channel, 1, 4)
    _put(channel, 1, 4)
    channel.append(0)
    var window = List[UInt8]()
    for value in [0, 0, size - 1, size - 1]:
        _put(window, value, 4)
    var changed = List[Attribute]()
    for attribute in attributes:
        var value = attribute.value.copy()
        if attribute.name == "channels":
            value = channel.copy()
        elif (
            attribute.name == "dataWindow" or attribute.name == "displayWindow"
        ):
            value = window.copy()
        changed.append(Attribute(attribute.name, attribute.kind, value^))
    var raw = List[UInt8]()
    for index in range(size * size):
        var value = 0.25 + Float64(index % 4) * 0.125
        if kind == 2:
            _put(raw, _float(value), 4)
        else:
            _put(raw, _half(value), 2)
    var fields: List[Int] = [2, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0]
    var rules = List[UInt8]()
    var compressed: List[UInt8]
    if kind == 2:
        compressed = compress(raw, -1)
        fields[1] = len(raw)
        fields[2] = len(compressed)
        _put(rules, 2, 2)
        if variant == "uppercase_rule":
            # The native reader folds candidates, not serialized rules.
            # This uppercase insensitive suffix therefore does not match.
            rules = List[UInt8]()
            _put(rules, 6, 2)
            rules.extend([UInt8(ord("Y")), 0, 0x05, 0x02])
        elif variant == "incomplete_csc":
            rules = List[UInt8]()
            _put(rules, 6, 2)
            rules.extend([UInt8(ord("Y")), 0, 0x10, 0x02])
    else:
        var planar = List[UInt8]()
        for start in [0, 1]:
            for index in range(start, len(raw), 2):
                planar.append(raw[index])
        var encoded = List[UInt8]()
        for start in range(0, len(planar), 127):
            var piece = _slice(planar, start, start + 127)
            encoded.append(UInt8(256 - len(piece)))
            encoded.extend(piece^)
        compressed = compress(encoded, -1)
        fields[5] = len(compressed)
        fields[6] = len(encoded)
        fields[7] = len(raw)
        _put(rules, 6, 2)
        var suffix: List[UInt8] = [
            UInt8(ord("Y")),
            0,
            UInt8(0x18 if variant == "incomplete_rle" else 0x08),
            0x01,
        ]
        rules.extend(suffix^)
    var chunk = _fields(fields)
    chunk.extend(rules^)
    chunk.extend(compressed^)
    return (changed^, chunk^)


def build(reference: String, library: String, root: String) raises:
    """Write and decode the 20 DWA variants.

    Args:
        reference: The reference executable.
        library: The OpenEXR library.
        root: The folder with `c8_s0.exr` and `c9_s0.exr`.

    Raises:
        Error: If a file cannot be read or the reference refuses a variant.
    """
    var builder = Builder(reference, library, root)
    for codec in [8, 9]:
        var data = Path(root + "/c" + String(codec) + "_s0.exr").read_bytes()
        var parsed = header(data)
        var attributes = parsed[0].copy()
        var start = parsed[1]
        var blocks = List[Block]()
        for index in range(2):
            var at = _u(data, start + index * 8, 8)
            var line = _u(data, at, 4)
            if line >= 1 << 31:
                line -= 1 << 32
            var length = _u(data, at + 4, 4)
            blocks.append(Block(line, _slice(data, at + 8, at + 8 + length)))
        for variant in [
            "deflate",
            "legacy0",
            "legacy1",
            "insensitive",
            "rule_shadow",
        ]:
            var converted = List[Block]()
            for block in blocks:
                var tokens = List[UInt16]()
                if needs_tokens(variant) and not stored(codec, block):
                    var stream = ac_stream(block)
                    tokens = builder.tokens(stream[0], stream[1])
                converted.append(stream_variant(codec, variant, block, tokens))
            builder.save(
                "c" + String(codec) + "_" + variant,
                file_bytes(attributes, converted),
            )
        # Pure UNKNOWN and pure RLE paths still use the supported Y output.
        for variant in [
            "unknown",
            "rle",
            "uppercase_rule",
            "incomplete_csc",
            "incomplete_rle",
        ]:
            var single = single_channel(attributes, variant)
            var chunks: List[Block] = [Block(0, single[1].copy())]
            builder.save(
                "c" + String(codec) + "_" + variant,
                file_bytes(single[0], chunks),
            )


def main() raises:
    var given = argv()
    if len(given) != 4:
        print("usage: variants REFERENCE LIBRARY DIR", file=stderr)
        exit(2)
    build(String(given[1]), String(given[2]), String(given[3]))
    print("20 DWA variants accepted by OpenEXR 3.1.5")
