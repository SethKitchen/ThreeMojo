# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.
"""Tests for the hairstyle converter."""

import contextlib
import io
import math
import os
import struct
import tempfile
import unittest

import hair_style


def _tfx(path, strands):
    """Write strands as a TressFX 4 file: its header, then each point as
    four floats."""
    points = len(strands[0])
    offset = 160
    body = struct.pack("<fIII", 4.0, len(strands), points, offset)
    body += bytes(offset - len(body))
    for strand in strands:
        for p in strand:
            body += struct.pack("<4f", p[0], p[1], p[2], 1.0)
    with open(path, "wb") as sink:
        sink.write(body)


def _head(radii=(0.08, 0.09, 0.1), center=(0.0, 1.5, 0.0), count=12):
    """Return strands rooted on an ellipsoid's upper half, each hanging
    straight down four centimeters."""
    strands = []
    for i in range(count):
        for j in range(1, 4):
            a = 2 * math.pi * i / count
            b = math.pi / 2 * j / 4
            q = (math.cos(b) * math.cos(a), math.sin(b), math.cos(b) * math.sin(a))
            root = tuple(center[k] + q[k] * radii[k] for k in range(3))
            strands.append([(root[0], root[1] - 0.01 * t, root[2]) for t in range(5)])
    return strands


def _crest(first=-28, last=150):
    """Return strands rooted round a circle in the midline's plane, from
    the brow back past the nape, each standing straight out."""
    strands = []
    for step in range(first, last, 10):
        angle = math.radians(step)
        # Up along y and back along minus z from the center (0, 1, 0).
        root = (0.0, 1.0 + 0.2 * math.cos(angle), -0.2 * math.sin(angle))
        out = (0.0, math.cos(angle), -math.sin(angle))
        strands.append([tuple(root[k] + out[k] * 0.02 * t for k in range(3)) for t in range(3)])
    return strands


class ConverterTests(unittest.TestCase):
    def test_reads_and_resamples_a_tfx_file(self):
        with tempfile.TemporaryDirectory() as folder:
            path = os.path.join(folder, "hair.tfx")
            _tfx(path, [[(0, 0, 0), (0, 1, 0), (0, 3, 0)]])
            strands = hair_style.read_tfx(path)
            self.assertEqual(strands, [[(0, 0, 0), (0, 1, 0), (0, 3, 0)]])
            with open(path, "rb") as source:
                data = source.read()
            for name, content in (
                ("short", data[:8]),
                ("cut", data[:-4]),
                ("empty", struct.pack("<fIII", 4.0, 0, 3, 16)),
            ):
                bad = os.path.join(folder, name)
                with open(bad, "wb") as sink:
                    sink.write(content)
                with self.assertRaises(ValueError):
                    hair_style.read_tfx(bad)
        even = hair_style.resample([(0, 0, 0), (0, 1, 0), (0, 3, 0)], 4)
        for k, p in enumerate(even):
            self.assertAlmostEqual(p[1], k)
        # A strand of no length stays at its root.
        still = hair_style.resample([(1, 1, 1), (1, 1, 1)], 3)
        self.assertEqual(still, [(1, 1, 1)] * 3)

    def test_fits_a_cranium_and_a_crest(self):
        radii = (0.08, 0.09, 0.1)
        roots = [s[0] for s in _head(radii)]
        center, fitted = hair_style.fit_cranium(roots)
        self.assertAlmostEqual(center[1], 1.5, places=6)
        for k in range(3):
            self.assertAlmostEqual(fitted[k], radii[k], places=6)
        crest_center, radius = hair_style.fit_crest([s[0] for s in _crest()])
        self.assertAlmostEqual(crest_center[1], 1.0, places=6)
        self.assertAlmostEqual(radius, 0.2, places=6)

    def test_the_cranium_frame(self):
        across, up, along = hair_style.cranium_frame((0, 1, 0), (1, 1, 1))
        self.assertEqual((across, up), ((1, 0, 0), (0, 1, 0)))
        self.assertAlmostEqual(along[2], -1)
        # At the side's pole plus x is the normal: across is plus z.
        across, up, _ = hair_style.cranium_frame((1, 0, 0), (1, 1, 1))
        self.assertEqual(across, (0, 0, 1))

    def test_layered_and_mohawk_styles(self):
        encoded = hair_style.layered(_head())
        q, offsets = encoded[0]
        self.assertAlmostEqual(math.hypot(*q), 1)
        self.assertEqual(offsets[0], (0, 0, 0))
        crest = hair_style.mohawk(_crest())
        # The strands before the brow and past the nape are left out.
        self.assertEqual(len(crest), 11)
        for q, _ in crest:
            self.assertAlmostEqual(math.hypot(*q), 1)
        with self.assertRaises(ValueError):
            hair_style.mohawk(_crest(128, 178))

    def test_writes_and_converts(self):
        with tempfile.TemporaryDirectory() as folder:
            source = os.path.join(folder, "hair.tfx")
            _tfx(source, _head())
            target = os.path.join(folder, "hair.bin")
            self.assertEqual(hair_style.convert("layered", source, target), 36)
            with open(target, "rb") as data:
                body = data.read()
            self.assertEqual(body[:4], b"THRS")
            version, strands, points = struct.unpack_from("<III", body, 4)
            self.assertEqual((version, strands, points), (1, 36, 16))
            roots = 20 + 36 * 6
            self.assertEqual(len(body), roots + 36 * 16 * 6)
            _tfx(source, _crest())
            self.assertEqual(hair_style.convert("mohawk", source, target), 11)
            with self.assertRaises(ValueError):
                hair_style.convert("bun", source, target)
            # A style whose strands never leave their roots.
            still = os.path.join(folder, "still.bin")
            hair_style.write(still, [((0, 1, 0), [(0, 0, 0), (0, 0, 0)])])
            with open(still, "rb") as data:
                scale = struct.unpack_from("<f", data.read(), 16)[0]
            self.assertAlmostEqual(scale, 1 / 32767)

    def test_main(self):
        with contextlib.redirect_stderr(io.StringIO()):
            self.assertEqual(hair_style.main(["x"]), 2)
        with tempfile.TemporaryDirectory() as folder:
            source = os.path.join(folder, "hair.tfx")
            _tfx(source, _head())
            target = os.path.join(folder, "hair.bin")
            with contextlib.redirect_stdout(io.StringIO()) as printed:
                code = hair_style.main(["x", "layered", source, target])
        self.assertEqual(code, 0)
        self.assertIn("36", printed.getvalue())


if __name__ == "__main__":
    unittest.main()
