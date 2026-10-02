# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
"""Losslessly compress PNG/APNG image streams; keep pixels and frame controls.

Run after rendering: python3 tools/optimize_png.py out/example.png
This changes DEFLATE encoding only. It preserves all non-image chunk data,
frame delays, blend/disposal operations, metadata and filtered scanline bytes.
"""

import argparse
import os
from pathlib import Path
import struct
import tempfile
import zlib

SIGNATURE = b'\x89PNG\r\n\x1a\n'


def chunks(data):
    """Read CRC-checked chunks, refusing truncated or trailing data."""
    if not data.startswith(SIGNATURE):
        raise ValueError('not a PNG file')
    offset = len(SIGNATURE)
    result = []
    while offset < len(data):
        if offset + 12 > len(data):
            raise ValueError('truncated PNG chunk')
        size = struct.unpack_from('>I', data, offset)[0]
        end = offset + 12 + size
        if end > len(data):
            raise ValueError('truncated PNG chunk data')
        kind = data[offset + 4:offset + 8]
        body = data[offset + 8:end - 4]
        crc = struct.unpack_from('>I', data, end - 4)[0]
        if zlib.crc32(kind + body) != crc:
            raise ValueError('PNG chunk CRC mismatch')
        result.append((kind, body))
        offset = end
        if kind == b'IEND':
            if body or offset != len(data):
                raise ValueError('invalid PNG end or trailing data')
            break
    if not result or result[0][0] != b'IHDR' or result[-1][0] != b'IEND':
        raise ValueError('missing PNG header or end')
    return result


def chunk(kind, body):
    """Encode one chunk with its length and CRC."""
    return (struct.pack('>I', len(body)) + kind + body
            + struct.pack('>I', zlib.crc32(kind + body)))


def recompress(stream):
    """Return a smaller equivalent stream, or retain the original bytes."""
    decoder = zlib.decompressobj()
    raw = decoder.decompress(stream) + decoder.flush()
    if not decoder.eof or decoder.unused_data or decoder.unconsumed_tail:
        raise ValueError('invalid or trailing PNG zlib stream')
    compressed = zlib.compress(raw, 9)
    return compressed if len(compressed) < len(stream) else stream


def optimize(data):
    """Return a no-larger PNG with the same decoded streams and controls."""
    parts = chunks(data)
    groups = []
    current = []
    previous_kind = None
    for index, (kind, body) in enumerate(parts):
        if kind == b'fcTL':
            if len(body) != 26:
                raise ValueError('invalid APNG frame control')
            if current:
                groups.append(current)
                current = []
        if kind in (b'IDAT', b'fdAT'):
            if kind == b'fdAT' and len(body) < 4:
                raise ValueError('short APNG frame data')
            if current and kind != previous_kind:
                groups.append(current)
                current = []
            current.append(index)
            previous_kind = kind
    if current:
        groups.append(current)
    for group in groups:
        kind = parts[group[0]][0]
        skip = 4 if kind == b'fdAT' else 0
        stream = b''.join(parts[i][1][skip:] for i in group)
        compressed = recompress(stream)
        if len(compressed) >= len(stream):
            continue
        # Preserve chunk positions, ancillary metadata and APNG sequence
        # numbers. Empty data chunks are valid; do not move metadata around.
        for n, i in enumerate(group):
            prefix = parts[i][1][:skip]
            parts[i] = kind, prefix + (compressed if n == 0 else b'')
    result = SIGNATURE + b''.join(chunk(k, b) for k, b in parts)
    return result if len(result) < len(data) else data


def optimize_file(path):
    """Replace a PNG atomically only when its compressed form is smaller."""
    path = Path(path)
    before = path.read_bytes()
    after = optimize(before)
    if len(after) < len(before):
        # A renderer can fail without leaving a partly recompressed output.
        fd, name = tempfile.mkstemp(prefix=path.name + '.', dir=path.parent)
        try:
            with os.fdopen(fd, 'wb') as target:
                target.write(after)
            os.chmod(name, path.stat().st_mode)
            os.replace(name, path)
        finally:
            if os.path.exists(name):
                os.unlink(name)
    return len(before), len(after)


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('paths', nargs='+', type=Path)
    args = parser.parse_args(argv)
    for path in args.paths:
        before, after = optimize_file(path)
        print(f'{path}: {before} -> {after} bytes')
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
