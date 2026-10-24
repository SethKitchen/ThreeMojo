# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md

"""SHA-256 of town-bake primitives, in the reviewed Python byte order.

    carla_geometry_digest REQUEST

REQUEST is a little-endian CGD1 file:

- Four bytes `CGD1`, then a u32 primitive count.
- Each primitive has a u32 field count of 4.
- The fields are `positions`, `normals`, `uvs` and `triangles`, in that
  order. Each field is a u32 name length, the name, a u32 rank, that many
  u32 dimensions, a u64 payload length and the payload bytes.

The digest of one primitive is SHA-256 over each field in order. The field
prefix is the UTF-8 JSON `["name",[dimensions]]` with no spaces, then the
payload. That is `json.dumps([name, shape], separators=(",", ":"))` and the
little-endian contiguous array bytes.
"""

from std.pathlib import Path
from std.sys import argv, exit, stderr

from tools._sha256 import Sha256


def digest_bytes(data: Span[UInt8, _]) raises -> List[String]:
    """Return one SHA-256 hex digest for each primitive.

    Args:
        data: A CGD1 geometry request.

    Returns:
        The digests, in primitive order. Each one is 64 lowercase hex
        digits. An empty request returns an empty list.

    Raises:
        Error: If the request is truncated, has trailing bytes, or does
            not list the four fields in order.
    """
    if len(data) < 8:
        raise Error("truncated geometry digest")
    if (
        Int(data[0]) != 67
        or Int(data[1]) != 71
        or Int(data[2]) != 68
        or Int(data[3]) != 49
    ):
        raise Error("geometry digest has a bad header")
    var at = 4
    var count = _u32(data, at)
    var lines = List[String]()
    for _ in range(count):
        var fields = _u32(data, at)
        if fields != 4:
            raise Error("geometry digest needs four fields")
        var state = Sha256()
        for index in range(4):
            var name = _field_name(index)
            var length = _u32(data, at)
            if length != name.byte_length():
                raise Error("geometry field is out of order")
            var got = String()
            for byte in range(length):
                got += chr(Int(data[at + byte]))
            at += length
            if got != name:
                raise Error("geometry field is out of order")
            var rank = _u32(data, at)
            if rank > 16:
                raise Error("geometry rank is too large")
            var dims = List[Int]()
            for _ in range(rank):
                dims.append(_u32(data, at))
            var prefix = _prefix(name, dims)
            state.update(prefix.as_bytes())
            var nbytes = _u64(data, at)
            if nbytes > UInt64(len(data) - at):
                raise Error("truncated geometry digest")
            var size = Int(nbytes)
            state.update(data[at : at + size])
            at += size
        lines.append(state^.hexdigest())
    if at != len(data):
        raise Error("geometry digest has trailing bytes")
    return lines^


def digest_file(path: String) raises -> List[String]:
    """Return the primitive digests stored in a CGD1 file.

    Args:
        path: The request file.

    Returns:
        The same digests `digest_bytes` returns.

    Raises:
        Error: If the file cannot be read, or is not a CGD1 request.
    """
    return digest_bytes(Path(path).read_bytes())


def _field_name(index: Int) -> String:
    """Return the field name at `index`."""
    if index == 0:
        return "positions"
    if index == 1:
        return "normals"
    if index == 2:
        return "uvs"
    return "triangles"


def _prefix(name: String, dims: List[Int]) -> String:
    """Return the JSON shape prefix for one field."""
    var text = '["' + name + '",['
    for index in range(len(dims)):
        if index > 0:
            text += ","
        text += String(dims[index])
    text += "]]"
    return text^


def _u32(data: Span[UInt8, _], mut at: Int) raises -> Int:
    """Read one little-endian u32 and advance `at`."""
    if at < 0 or at > len(data) or 4 > len(data) - at:
        raise Error("truncated geometry digest")
    var value = Int(data[at])
    value |= Int(data[at + 1]) << 8
    value |= Int(data[at + 2]) << 16
    value |= Int(data[at + 3]) << 24
    at += 4
    return value


def _u64(data: Span[UInt8, _], mut at: Int) raises -> UInt64:
    """Read one little-endian u64 and advance `at`."""
    if at < 0 or at > len(data) or 8 > len(data) - at:
        raise Error("truncated geometry digest")
    var value = UInt64(0)
    for index in range(8):
        value |= UInt64(data[at + index]) << UInt64(8 * index)
    at += 8
    return value


def main() raises:
    """Print one digest line for each primitive in the request file."""
    var arguments = argv()
    if len(arguments) != 2:
        print("usage: carla_geometry_digest REQUEST", file=stderr)
        exit(2)
    try:
        var lines = digest_file(arguments[1])
        for index in range(len(lines)):
            print(lines[index])
    except error:
        print("carla_geometry_digest:", error, file=stderr)
        exit(1)
