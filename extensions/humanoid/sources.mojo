# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Bind converted humanoid inputs to their pinned source manifest.

`converted_sources` hashes each converted asset that a build reads. It
compares that SHA-256 with `assets/converted-asset-manifest.json`, which
pins the upstream repository, commit and license of each asset (#303).
A changed or unpinned asset is an error. The result names the exact
bytes, so a later change to an asset changes a recipe that records it.

The check reads the files at build time. It does not prove that a later
reader loads the same bytes, and it does not validate anatomy.

This is not a three.js port. See Extensions.
"""

from core.user_data import UserData, user_data_of
from extensions.humanoid.assets import humanoid_asset_path
from extensions.humanoid.skeleton.head.hair.styles import (
    HairStyle,
    hair_style_label,
)
from loaders.json import JsonDocument, parse_json
from std.pathlib import Path

comptime CONVERTED_MANIFEST = "assets/converted-asset-manifest.json"
comptime CONVERTED_MANIFEST_SCHEMA = 2
comptime FACE_ASSET = "assets/face/ict_face.bin"
comptime _HEX: List[String] = [
    "0",
    "1",
    "2",
    "3",
    "4",
    "5",
    "6",
    "7",
    "8",
    "9",
    "a",
    "b",
    "c",
    "d",
    "e",
    "f",
]
# FIPS 180-4 round constants.
comptime _K: List[UInt32] = [
    0x428A2F98,
    0x71374491,
    0xB5C0FBCF,
    0xE9B5DBA5,
    0x3956C25B,
    0x59F111F1,
    0x923F82A4,
    0xAB1C5ED5,
    0xD807AA98,
    0x12835B01,
    0x243185BE,
    0x550C7DC3,
    0x72BE5D74,
    0x80DEB1FE,
    0x9BDC06A7,
    0xC19BF174,
    0xE49B69C1,
    0xEFBE4786,
    0x0FC19DC6,
    0x240CA1CC,
    0x2DE92C6F,
    0x4A7484AA,
    0x5CB0A9DC,
    0x76F988DA,
    0x983E5152,
    0xA831C66D,
    0xB00327C8,
    0xBF597FC7,
    0xC6E00BF3,
    0xD5A79147,
    0x06CA6351,
    0x14292967,
    0x27B70A85,
    0x2E1B2138,
    0x4D2C6DFC,
    0x53380D13,
    0x650A7354,
    0x766A0ABB,
    0x81C2C92E,
    0x92722C85,
    0xA2BFE8A1,
    0xA81A664B,
    0xC24B8B70,
    0xC76C51A3,
    0xD192E819,
    0xD6990624,
    0xF40E3585,
    0x106AA070,
    0x19A4C116,
    0x1E376C08,
    0x2748774C,
    0x34B0BCB5,
    0x391C0CB3,
    0x4ED8AA4A,
    0x5B9CCA4F,
    0x682E6FF3,
    0x748F82EE,
    0x78A5636F,
    0x84C87814,
    0x8CC70208,
    0x90BEFFFA,
    0xA4506CEB,
    0xBEF9A3F7,
    0xC67178F2,
]


def _rotate(x: UInt32, n: UInt32) -> UInt32:
    """Rotate a word right by `n` bits, for 0 < n < 32."""
    return (x >> n) | (x << (32 - n))


def _compress(
    mut state: SIMD[DType.uint32, 8],
    data: List[UInt8],
    at: Int,
    k: List[UInt32],
    mut w: List[UInt32],
):
    """Mix one 64-byte block of `data`, starting at `at`, into `state`.

    The caller guarantees that the block lies inside `data` and that `w`
    holds 64 words, so the accesses skip bounds checks.
    """
    var bytes = data.unsafe_ptr()
    var rounds = k.unsafe_ptr()
    var words = w.unsafe_ptr()
    for t in range(16):  # pragma: no branch
        var base = at + 4 * t
        words[unsafe_offset=t] = (
            (UInt32(bytes[unsafe_offset=base]) << 24)
            | (UInt32(bytes[unsafe_offset=base + 1]) << 16)
            | (UInt32(bytes[unsafe_offset=base + 2]) << 8)
            | UInt32(bytes[unsafe_offset=base + 3])
        )
    for t in range(16, 64):  # pragma: no branch
        var x = words[unsafe_offset=t - 15]
        var y = words[unsafe_offset=t - 2]
        var s0 = _rotate(x, 7) ^ _rotate(x, 18) ^ (x >> 3)
        var s1 = _rotate(y, 17) ^ _rotate(y, 19) ^ (y >> 10)
        words[unsafe_offset=t] = (
            words[unsafe_offset=t - 16] + s0 + words[unsafe_offset=t - 7] + s1
        )
    var a = state[0]
    var b = state[1]
    var c = state[2]
    var d = state[3]
    var e = state[4]
    var f = state[5]
    var g = state[6]
    var h = state[7]
    for t in range(64):  # pragma: no branch
        var sum1 = _rotate(e, 6) ^ _rotate(e, 11) ^ _rotate(e, 25)
        var choose = (e & f) ^ (~e & g)
        var first = (
            h + sum1 + choose + rounds[unsafe_offset=t] + words[unsafe_offset=t]
        )
        var sum0 = _rotate(a, 2) ^ _rotate(a, 13) ^ _rotate(a, 22)
        var major = (a & b) ^ (a & c) ^ (b & c)
        h = g
        g = f
        f = e
        e = d + first
        d = c
        c = b
        b = a
        a = first + sum0 + major
    state += SIMD[DType.uint32, 8](a, b, c, d, e, f, g, h)


def sha256_hex(data: List[UInt8]) -> String:
    """Return the FIPS 180-4 SHA-256 digest of a byte string.

    Args:
        data: The bytes to hash.

    Returns:
        Sixty-four lowercase hexadecimal digits.
    """
    var state = SIMD[DType.uint32, 8](
        0x6A09E667,
        0xBB67AE85,
        0x3C6EF372,
        0xA54FF53A,
        0x510E527F,
        0x9B05688C,
        0x1F83D9AB,
        0x5BE0CD19,
    )
    var k = materialize[_K]()
    var w = List[UInt32](length=64, fill=0)
    var whole = len(data) - len(data) % 64
    for at in range(0, whole, 64):
        _compress(state, data, at, k, w)
    # The tail holds the remaining bytes, the 0x80 marker, zero padding
    # and the 64-bit big-endian message length in bits.
    var tail = List[UInt8]()
    for at in range(whole, len(data)):
        tail.append(data[at])
    tail.append(0x80)
    while len(tail) % 64 != 56:
        tail.append(0)
    var bits = UInt64(len(data)) * 8
    for shift in range(7, -1, -1):  # pragma: no branch
        tail.append(UInt8((bits >> UInt64(8 * shift)) & 0xFF))
    for at in range(0, len(tail), 64):  # pragma: no branch
        _compress(state, tail, at, k, w)
    var hex = materialize[_HEX]()
    var digits = String()
    for word in range(8):  # pragma: no branch
        for nibble in range(7, -1, -1):  # pragma: no branch
            digits += hex[Int((state[word] >> UInt32(4 * nibble)) & 0xF)]
    return digits^


def file_sha256(path: String) raises -> String:
    """Return the SHA-256 digest of a file's complete bytes.

    Args:
        path: The file to read.

    Returns:
        Sixty-four lowercase hexadecimal digits.

    Raises:
        Error: If the file cannot be read.
    """
    return sha256_hex(Path(path).read_bytes())


def game_source_paths(guides: Int, style: HairStyle) raises -> List[String]:
    """Return the converted assets that a game humanoid build reads.

    Every build reads the face model. Only strand guides of a scanned
    style read that style's hair file.

    Args:
        guides: Guide strands the build grows.
        style: The build's hair style.

    Returns:
        Repository-relative asset paths, face model first.

    Raises:
        Error: If the style is not named.
    """
    if not style.is_valid():
        raise Error("Converted sources require a named hair style")
    var paths = List[String]()
    paths.append(String(FACE_ASSET))
    if guides > 0 and style.is_scanned():
        paths.append(String("assets/hair/") + hair_style_label(style) + ".bin")
    return paths^


def _text(document: JsonDocument, node: Int, key: String) raises -> String:
    """Return a required string member of a manifest object."""
    if not document.has(node, key):
        raise Error("Converted asset manifest has no " + key)
    return document.string(document.get(node, key))


def _production_entry(document: JsonDocument, path: String) raises -> Int:
    """Return the manifest's production entry for one asset path."""
    var entries = document.get(document.root(), "production_assets")
    for index in range(document.length(entries)):  # pragma: no branch
        var entry = document.at(entries, index)
        if _text(document, entry, "path") == path:
            return entry
    raise Error("Converted asset is not pinned by the manifest: " + path)


def converted_sources(paths: List[String]) raises -> UserData:
    """Verify converted assets against the pinned manifest and record them.

    Each asset's SHA-256 must equal the manifest's pinned SHA-256. The
    record copies the upstream repository, commit, format version and
    license that the manifest pins for it.

    Args:
        paths: Repository-relative asset paths, from `game_source_paths`.

    Returns:
        The manifest's path, schema and SHA-256, and one entry per asset.

    Raises:
        Error: If no path is given, the manifest or an asset cannot be
            read, the manifest has another schema, an asset is not pinned,
            or an asset's bytes differ from its pinned SHA-256.
    """
    if len(paths) == 0:
        raise Error("Converted sources need at least one asset path")
    var manifest_path = humanoid_asset_path(String(CONVERTED_MANIFEST))
    var manifest_bytes = Path(manifest_path).read_bytes()
    var manifest_sha256 = sha256_hex(manifest_bytes)
    var document = parse_json(String(unsafe_from_utf8=manifest_bytes))
    var root = document.root()
    if document.integer(document.get(root, "schema_version")) != (
        CONVERTED_MANIFEST_SCHEMA
    ):
        raise Error("Converted asset manifest schema is unsupported")
    var files = document.get(root, "files")
    var sources = document.get(root, "sources")
    var assets = UserData()
    for path in paths:  # pragma: no branch
        var pinned = _text(document, files, path)
        var actual = file_sha256(humanoid_asset_path(path))
        if actual != pinned:
            raise Error(
                "Converted asset does not match its pinned manifest: " + path
            )
        var entry = _production_entry(document, path)
        var source_id = _text(document, document.get(entry, "source"), "id")
        var source = document.get(sources, source_id)
        var item = UserData()
        item.set_string("sha256", actual)
        item.set_string("source_id", source_id)
        item.set_string("repository", _text(document, source, "repository"))
        item.set_string("revision", _text(document, source, "revision"))
        item.set_number(
            "format_version",
            Float64(document.integer(document.get(entry, "format_version"))),
        )
        item.set_string(
            "license", _text(document, document.get(entry, "license"), "spdx")
        )
        assets.set_json(path, item.to_json())
    var record = UserData()
    record.set_string("manifest", String(CONVERTED_MANIFEST))
    record.set_number("manifest_schema", Float64(CONVERTED_MANIFEST_SCHEMA))
    record.set_string("manifest_sha256", manifest_sha256)
    record.set_json("assets", assets.to_json())
    return record^
