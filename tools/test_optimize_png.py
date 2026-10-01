# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
"""PNG/APNG stream and metadata preservation regressions."""

from pathlib import Path
import struct
import tempfile
import unittest
import zlib

import optimize_png as png


def fixture(animated=False):
    raw = b'\0' + b'\x10\x20\x30' * 64
    stream = zlib.compress(raw, 0)
    header = struct.pack('>IIBBBBB', 64, 1, 8, 2, 0, 0, 0)
    parts = [(b'IHDR', header), (b'tEXt', b'Attribution\0Example credit')]
    if animated:
        parts += [(b'acTL', struct.pack('>II', 2, 3)),
                  (b'fcTL', struct.pack('>IIIIIHHBB', 0, 64, 1, 0, 0, 7, 60, 1, 0))]
    parts += [(b'IDAT', stream[:15]), (b'IDAT', stream[15:])]
    if animated:
        parts += [(b'fcTL', struct.pack('>IIIIIHHBB', 1, 64, 1, 0, 0, 9, 60, 2, 1)),
                  (b'fdAT', struct.pack('>I', 2) + stream[:14]),
                  (b'fdAT', struct.pack('>I', 3) + stream[14:])]
    parts += [(b'IEND', b'')]
    return png.SIGNATURE + b''.join(png.chunk(k, b) for k, b in parts)


def semantics(data):
    """Compare filtered samples and every non-data field independently."""
    result = []
    pending, previous = bytearray(), None
    for kind, body in png.chunks(data):
        if kind not in (b'IDAT', b'fdAT') or kind != previous:
            if pending:
                result.append((previous, zlib.decompress(bytes(pending))))
                pending.clear()
        if kind in (b'IDAT', b'fdAT'):
            pending.extend(body[4:] if kind == b'fdAT' else body)
        else:
            result.append((kind, body[4:] if kind == b'fcTL' else body))
        previous = kind
    return result


class OptimizePngTests(unittest.TestCase):
    def test_still_and_animation_preserve_all_samples_and_controls(self):
        for animated in (False, True):
            with self.subTest(animated=animated):
                before = fixture(animated)
                after = png.optimize(before)
                self.assertLess(len(after), len(before))
                self.assertEqual(semantics(after), semantics(before))
                self.assertEqual(png.optimize(after), after)
                seq = [struct.unpack('>I', b[:4])[0] for k, b in png.chunks(after)
                       if k in (b'fcTL', b'fdAT')]
                self.assertEqual(seq, list(range(len(seq))))

    def test_rejects_corrupt_truncated_and_trailing_files(self):
        valid = fixture()
        bad = bytearray(valid)
        bad[29] ^= 1
        for data in (b'x', valid[:-1], valid + b'x', bytes(bad)):
            with self.assertRaises(ValueError):
                png.optimize(data)

    def test_rejects_short_frame_data_and_controls(self):
        for kind in (b'fdAT', b'fcTL'):
            data = fixture()[:-12] + png.chunk(kind, b'x') + png.chunk(b'IEND', b'')
            with self.assertRaises(ValueError):
                png.optimize(data)

    def test_rejects_bad_zlib_and_extra_streams(self):
        for stream in (b'bad', zlib.compress(b'a')[:-1],
                       zlib.compress(b'a') + zlib.compress(b'b')):
            with self.assertRaises((ValueError, zlib.error)):
                png.recompress(stream)

    def test_atomic_replacement_and_no_growth(self):
        with tempfile.TemporaryDirectory() as temp:
            path = Path(temp) / 'sample.png'
            path.write_bytes(fixture(True))
            before, after = png.optimize_file(path)
            self.assertLess(after, before)
            first = path.read_bytes()
            self.assertEqual(png.optimize_file(path), (after, after))
            self.assertEqual(path.read_bytes(), first)
            self.assertEqual(list(Path(temp).iterdir()), [path])


if __name__ == '__main__':
    unittest.main()
