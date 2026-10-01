# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
"""Tests for the ICT face model converter."""

import contextlib
import io
import os
import struct
import tempfile
import unittest
from unittest.mock import patch

import ict_face_model

# A square, as one quad, and a triangle beside it, with a seam: vertex 2
# has a second texture coordinate in the triangle. A blank line, too,
# which the reader skips.
NEUTRAL = """v 0 0 0
v 100 0 0
v 100 100 0

v 0 100 0
v 200 50 0
vt 0 0
vt 1 0
vt 1 1
vt 0 1
vt 0.5 0
vt 0.9 0.5
f 1/1 2/2 3/3 4/4
f 2/5 5/6 3/3
"""


def _shape(moved):
    """Return an OBJ of the square with vertex 3 moved `moved` cm in x."""
    return NEUTRAL.replace("v 0 100 0", "v %g 100 0" % moved)


def _grid(n):
    """Return an n-by-n grid of unit squares, two triangles each, wound
    alike, as points and triangles."""
    points = [(i, j, 0.0) for j in range(n + 1) for i in range(n + 1)]
    triangles = []
    for j in range(n):
        for i in range(n):
            a = j * (n + 1) + i
            triangles.append((a, a + 1, a + n + 2))
            triangles.append((a, a + n + 2, a + n + 1))
    return points, triangles


class ConverterTests(unittest.TestCase):
    def test_closest_handles_degenerate_triangles(self):
        self.assertEqual(
            ict_face_model._closest((1, .5, 0), (0, 0, 0), (0, 0, 0), (0, 1, 0)),
            (1.0, 0.0, 0.5),
        )
        self.assertEqual(
            ict_face_model._closest((1, 0, 0), (0, 0, 0), (0, 0, 0), (0, 0, 0)),
            (1.0, 0.0, 0.0),
        )

    def test_follow_searches_past_the_first_populated_ring(self):
        from ict_face_model import follow

        points = [
            (.01485, .01485, .01485),
            (-.01485, -.01485, -.01485),
            (-.01484, -.01485, -.01485),
            (-.01485, -.01484, -.01485),
            (.03015, .01485, .01485),
            (.03015, .01486, .01485),
            (.03015, .01485, .01486),
        ]
        used, _, followers = follow(points, [(1, 2, 3), (4, 5, 6)], 1)
        self.assertEqual(tuple(used[i] for i in followers[0][:3]), (4, 5, 6))
        with self.assertRaisesRegex(ValueError, "coarse triangles"):
            follow(points, [], 1)

    def test_converts_a_small_model(self):
        with tempfile.TemporaryDirectory() as folder:
            files = {
                "generic_neutral_mesh.obj": NEUTRAL,
                "identity000.obj": _shape(2.54),
                "jawOpen.obj": _shape(-1),
                "still.obj": NEUTRAL,
            }
            for name, text in files.items():
                with open(os.path.join(folder, name), "w") as sink:
                    sink.write(text)
            out = os.path.join(folder, "face.bin")
            counts = ict_face_model.convert(
                folder, out, identities=1, skin_end=5, coarse_target=2
            )
            self.assertEqual(counts, (5, 6, 3, 2))
            with open(out, "rb") as source:
                data = source.read()
        self.assertEqual(data[:4], b"ICTF")
        header = struct.unpack_from("<15I", data, 4)
        # Version 6; 5 vertices, 6 drawn, 3 triangles, 1 identity mode,
        # 2 expressions; the skin's 3 triangles, 7 edges, one hole of 5
        # corners; a coarse copy of 3 triangles, since every vertex lies
        # on the hole; 40 bytes of expressions; and the coarse copy's 5
        # vertices and 7 edges, which the 5 skin vertices follow.
        self.assertEqual(
            header, (6, 5, 6, 3, 1, 2, 3, 7, 1, 5, 3, 40, 5, 7, 5)
        )
        at = 64
        self.assertEqual(struct.unpack_from("<3f", data, at + 12), (1.0, 0, 0))
        at += 5 * 12 + 6 * 8
        self.assertEqual(
            struct.unpack_from("<6H", data, at), (0, 1, 2, 3, 1, 4)
        )
        shorts = 6 + 9 + 9 + 14 + 1 + 5 + 9 + 5 + 14 + 15
        self.assertEqual(struct.unpack_from("<H", data, at + 2 * 38), (5,))
        # Each skin vertex follows itself.
        follows = struct.unpack_from("<15H", data, at + 2 * (shorts - 15))
        self.assertEqual(follows[3:6], (1, 1, 1))
        at += shorts * 2
        at += -at % 4
        self.assertEqual(struct.unpack_from("<2f", data, at), (0.0, 0.0))
        at += 5 * 8
        # The expressions come sorted by name, each with the vertices it
        # moves, each section on a multiple of four bytes.
        self.assertEqual(data[at : at + 8], b"\x07jawOpen")
        at += 8
        self.assertEqual(struct.unpack_from("<I", data, at), (1,))
        self.assertEqual(struct.unpack_from("<H", data, at + 8), (3,))
        at += 12
        self.assertEqual(data[at], 0x81)
        at += 4
        self.assertEqual(data[at : at + 6], b"\x05still")
        at += 8
        self.assertEqual(struct.unpack_from("<If", data, at), (0, 1.0))
        at += 8
        # Then the identity mode.
        scale = struct.unpack_from("<f", data, at)[0]
        self.assertAlmostEqual(scale, 0.0254 / 127)
        self.assertEqual(data[at + 4 + 9], 127)
        self.assertEqual(len(data), at + 4 + 16)

    def test_the_skin_follows_its_coarse_copy(self):
        points, triangles = _grid(4)
        coarse = ict_face_model.decimate(points, triangles, 12)
        used, links, followers = ict_face_model.follow(
            points, coarse, len(points), cell=0.7
        )
        self.assertLess(len(used), len(points))
        self.assertTrue(all(a < b < len(used) for a, b in links))
        # A vertex of the copy follows itself; any other lies on its
        # triangle, at weights that rebuild it.
        for v, (a, b, c, wb, wc) in enumerate(followers):
            if v in used:
                self.assertEqual((a, b, c), (used.index(v),) * 3)
                continue
            p = [
                points[used[a]][k] * (1 - wb - wc)
                + points[used[b]][k] * wb
                + points[used[c]][k] * wc
                for k in range(3)
            ]
            for k in range(3):
                self.assertAlmostEqual(p[k], points[v][k], places=6)
        # Every region of the nearest point: the three corners, the
        # three edges and the face.
        a, b, c = (0, 0, 0), (1, 0, 0), (0, 1, 0)
        for probe, weights in (
            ((-1, -1, 0), (0.0, 0.0)),
            ((2, -0.5, 0), (1.0, 0.0)),
            ((-0.5, 2, 0), (0.0, 1.0)),
            ((0.5, -1, 0), (0.5, 0.0)),
            ((-1, 0.5, 0), (0.0, 0.5)),
            ((1, 1, 0), (0.5, 0.5)),
            ((0.2, 0.3, 1), (0.2, 0.3)),
        ):
            _, wb, wc = ict_face_model._closest(probe, a, b, c)
            self.assertAlmostEqual(wb, weights[0])
            self.assertAlmostEqual(wc, weights[1])

    def test_quantize_and_displacements(self):
        self.assertEqual(ict_face_model.quantize([0.0, 0.0]), (1.0, b"\0\0"))
        with self.assertRaises(ValueError):
            ict_face_model.displacements([(0, 0, 0)], [])

    def test_the_skin_and_its_holes(self):
        points, triangles = _grid(2)
        skin, edges, holes = ict_face_model.skin_topology(
            list(range(len(points))), triangles, skin_end=9
        )
        self.assertEqual(len(skin), 8)
        self.assertEqual(len(edges), 16)
        # The grid's rim, run the way its triangles run it.
        self.assertEqual(holes, [[0, 1, 2, 5, 8, 7, 6, 3]])
        # Triangles that leave the skin are left out.
        skin, _, _ = ict_face_model.skin_topology(
            list(range(len(points))), triangles, skin_end=5
        )
        self.assertEqual(skin, [(0, 1, 4), (0, 4, 3)])

    def test_decimation_keeps_the_shape(self):
        points, triangles = _grid(6)
        fewer = ict_face_model.decimate(points, triangles, 20)
        self.assertLess(len(fewer), len(triangles))
        # The rim stays: every corner of the grid is still used.
        used = {v for t in fewer for v in t}
        for corner in (0, 6, 42, 48):
            self.assertIn(corner, used)
        # A flat grid stays flat, and every triangle faces up.
        for a, b, c in fewer:
            normal = ict_face_model._normal(points[a], points[b], points[c])
            self.assertGreater(normal[2], 0)
        # A triangle with no area has no plane.
        self.assertIsNone(
            ict_face_model._plane_quadric((0, 0, 0), (1, 0, 0), (2, 0, 0))
        )
        flat = [(0, 0, 0), (1, 0, 0), (2, 0, 0), (0, 1, 0)]
        kept = ict_face_model.decimate(flat, [(0, 1, 2), (0, 1, 3)], 1)
        self.assertEqual(len(kept), 2)

    def test_main(self):
        with contextlib.redirect_stderr(io.StringIO()):
            self.assertEqual(ict_face_model.main(["x"]), 2)
        with patch.object(ict_face_model, "convert", return_value=(1, 2, 3, 4)):
            with contextlib.redirect_stdout(io.StringIO()) as printed:
                code = ict_face_model.main(["x", "in", "out"])
        self.assertEqual(code, 0)
        self.assertIn("(1, 2, 3, 4)", printed.getvalue())


if __name__ == "__main__":
    unittest.main()
