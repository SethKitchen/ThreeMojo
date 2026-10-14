# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Tests for the ICT face model converter, `tools/ict_face_model.mojo`."""

from std.pathlib import Path
from std.tempfile import mkdtemp
from std.testing import (
    TestSuite,
    assert_equal,
    assert_false,
    assert_raises,
    assert_true,
)

from tools._process import run_program
from tools._python_float import python_repr
from tools._struct import unpack_f32, unpack_u32
from tools.ict_face_model import (
    P3,
    closest,
    convert,
    counts_text,
    decimate,
    displacements,
    follow,
    normal,
    parse_coordinate,
    plane_quadric,
    quantize,
    read_obj,
    run,
    skin_topology,
)

# A square, as one quad, and a triangle beside it, with a seam: vertex 2
# has a second texture coordinate in the triangle. A blank line, too,
# which the reader skips.
comptime NEUTRAL = """v 0 0 0
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


def _shape(moved: String) -> String:
    """Return an OBJ of the square with vertex 3 moved in x."""
    return String(NEUTRAL).replace("v 0 100 0", "v " + moved + " 100 0")


def _grid(n: Int) -> Tuple[List[P3], List[Int]]:
    """Return an n-by-n grid of unit squares, two triangles each, wound
    alike, as points and triangles."""
    var points = List[P3]()
    for j in range(n + 1):
        for i in range(n + 1):
            points.append(P3(Float64(i), Float64(j), 0.0))
    var triangles = List[Int]()
    for j in range(n):
        for i in range(n):
            var a = j * (n + 1) + i
            triangles.extend([a, a + 1, a + n + 2])
            triangles.extend([a, a + n + 2, a + n + 1])
    return (points^, triangles^)


def _folder() raises -> String:
    """Return a new temporary folder."""
    return mkdtemp(prefix="ict face test ")


def _remove(folder: String) raises:
    """Remove a temporary folder."""
    _ = run_program(["rm", "-rf", folder], 10)


def _u16(data: List[UInt8], at: Int) -> Int:
    """Return a little-endian unsigned 16-bit integer."""
    return Int(data[at]) | (Int(data[at + 1]) << 8)


def _close(a: Float64, b: Float64, places: Int = 7) raises:
    """Assert as `assertAlmostEqual` does: equal to `places` decimals."""
    var tolerance = 0.5
    for _ in range(places):
        tolerance /= 10
    assert_true(abs(a - b) <= tolerance, String(a) + " != " + String(b))


def test_obj_indices_comments_and_forward_references() raises:
    var vertices = "v 0 0 0\nv 1 0 0\nv 0 1 0\nvt 0 0\nvt 1 0\nvt 0 1\n"
    var folder = _folder()
    var path = folder + "/face.obj"
    for text in [
        vertices + "f 1/1 2/2 3/3 # comment\n",
        vertices + "f -3/-3 -2/-2 -1/-1\r\n",
        "f 1/1 2/2 3/3\r" + vertices,
        vertices + "f +1/1 2/2 3/3 #\n",
    ]:
        Path(path).write_text(text)
        var parsed = read_obj(path)
        assert_equal(len(parsed.points), 3)
        assert_true(parsed.points[1] == P3(1, 0, 0))
        assert_equal(len(parsed.uvs), 6)
        assert_equal(parsed.uvs[5], 1.0)
        assert_equal(len(parsed.faces), 1)
        assert_equal(len(parsed.faces[0]), 6)
        for k in range(6):
            assert_equal(parsed.faces[0][k], k // 2)
    _remove(folder)


def test_obj_boundary_rejects_malformed_coordinates_and_indices() raises:
    var prefix = "v 0 0 0\nvt 0 0\n"
    var cases: List[String] = [
        "v 0 0\n",
        "vt 0\n",
        "v nan 0 0\n",
        "v 0 inf 0\n",
        "v 0 0 -inf\n",
        "vt nan 0\n",
        "vt 0 inf\n",
        "v 1e400 0 0\n",
        "v 1x 0 0\n",
        "v 0 0 0 é\n",
        prefix + "f 1/1 1/1\n",
        prefix + "f 1 1 1\n",
        prefix + "f 1//1 1/1 1/1\n",
        prefix + "f x/1 1/1 1/1\n",
    ]
    for corner in ["0/1", "1/0", "2/1", "1/2", "-2/1", "1/-2", "1/1/1/1"]:
        cases.append(prefix + "f " + corner + " 1/1 1/1\n")
    var folder = _folder()
    var path = folder + "/face.obj"
    for text in cases:
        Path(path).write_text(text)
        with assert_raises():
            _ = read_obj(path)
    _remove(folder)


def test_coordinates_are_read_as_float_reads_them() raises:
    assert_equal(python_repr(parse_coordinate("-0")), "-0.0")
    assert_equal(python_repr(parse_coordinate("-12.345678")), "-12.345678")
    assert_equal(python_repr(parse_coordinate("1E+3")), "1000.0")
    assert_equal(
        python_repr(parse_coordinate("123456789012345678")),
        "1.2345678901234568e+17",
    )
    assert_equal(
        python_repr(parse_coordinate("0.1234567890123456789")),
        "0.12345678901234568",
    )
    assert_equal(python_repr(parse_coordinate("3.14159e-30")), "3.14159e-30")
    assert_equal(python_repr(parse_coordinate(".5")), "0.5")
    assert_equal(python_repr(parse_coordinate("5.")), "5.0")
    with assert_raises():
        _ = parse_coordinate("1e")
    with assert_raises():
        _ = parse_coordinate(".")


def test_nonfinite_expression_cannot_replace_existing_output() raises:
    var folder = _folder()
    Path(folder + "/generic_neutral_mesh.obj").write_text(NEUTRAL)
    Path(folder + "/jawOpen.obj").write_text(
        String(NEUTRAL).replace("v 100 0 0", "v nan 0 0")
    )
    var target = folder + "/face.bin"
    Path(target).write_text("preserve")
    with assert_raises(contains="non-finite OBJ coordinate"):
        _ = convert(folder, target, 0, 5, 2)
    assert_equal(Path(target).read_text(), "preserve")
    _remove(folder)


def test_closest_handles_degenerate_triangles() raises:
    var near = closest(P3(1, 0.5, 0), P3(0, 0, 0), P3(0, 0, 0), P3(0, 1, 0))
    assert_equal(near.distance2, 1.0)
    assert_equal(near.wb, 0.0)
    assert_equal(near.wc, 0.5)
    near = closest(P3(1, 0, 0), P3(0, 0, 0), P3(0, 0, 0), P3(0, 0, 0))
    assert_equal(near.distance2, 1.0)
    assert_equal(near.wb, 0.0)
    assert_equal(near.wc, 0.0)


def test_follow_searches_past_the_first_populated_ring() raises:
    var points: List[P3] = [
        P3(0.01485, 0.01485, 0.01485),
        P3(-0.01485, -0.01485, -0.01485),
        P3(-0.01484, -0.01485, -0.01485),
        P3(-0.01485, -0.01484, -0.01485),
        P3(0.03015, 0.01485, 0.01485),
        P3(0.03015, 0.01486, 0.01485),
        P3(0.03015, 0.01485, 0.01486),
    ]
    var following = follow(points, [1, 2, 3, 4, 5, 6], 1)
    for k in range(3):
        assert_equal(following.used[following.corners[k]], 4 + k)
    with assert_raises(contains="coarse triangles"):
        _ = follow(points, List[Int](), 1)


def test_converts_a_small_model() raises:
    var folder = _folder()
    Path(folder + "/generic_neutral_mesh.obj").write_text(NEUTRAL)
    Path(folder + "/identity000.obj").write_text(_shape("2.54"))
    Path(folder + "/jawOpen.obj").write_text(_shape("-1"))
    Path(folder + "/still.obj").write_text(NEUTRAL)
    # Neither a hidden file nor another extension is an expression.
    Path(folder + "/.hidden.obj").write_text("v x\n")
    Path(folder + "/notes.txt").write_text("v x\n")
    var target = folder + "/face.bin"
    var counts = convert(folder, target, 1, 5, 2)
    assert_equal(counts_text(counts), "(5, 6, 3, 2)")
    var data = Path(target).read_bytes()
    _remove(folder)
    assert_equal(String(unsafe_from_utf8=data[:4]), "ICTF")
    # Version 6; 5 vertices, 6 drawn, 3 triangles, 1 identity mode,
    # 2 expressions; the skin's 3 triangles, 7 edges, one hole of 5
    # corners; a coarse copy of 3 triangles, since every vertex lies
    # on the hole; 40 bytes of expressions; and the coarse copy's 5
    # vertices and 7 edges, which the 5 skin vertices follow.
    var header = [6, 5, 6, 3, 1, 2, 3, 7, 1, 5, 3, 40, 5, 7, 5]
    for i in range(15):
        assert_equal(unpack_u32(Span(data), 4 + 4 * i), header[i])
    var at = 64
    assert_equal(unpack_f32(Span(data), at + 12), 1.0)
    assert_equal(unpack_f32(Span(data), at + 16), 0.0)
    at += 5 * 12 + 6 * 8
    var drawn = [0, 1, 2, 3, 1, 4]
    for i in range(6):
        assert_equal(_u16(data, at + 2 * i), drawn[i])
    var shorts = 6 + 9 + 9 + 14 + 1 + 5 + 9 + 5 + 14 + 15
    assert_equal(_u16(data, at + 2 * 38), 5)
    # Each skin vertex follows itself.
    var follows = at + 2 * (shorts - 15)
    for k in range(3, 6):
        assert_equal(_u16(data, follows + 2 * k), 1)
    at += shorts * 2
    at += (4 - at % 4) % 4
    assert_equal(unpack_f32(Span(data), at), 0.0)
    assert_equal(unpack_f32(Span(data), at + 4), 0.0)
    at += 5 * 8
    # The expressions come sorted by name, each with the vertices it
    # moves, each section on a multiple of four bytes.
    assert_equal(Int(data[at]), 7)
    assert_equal(String(unsafe_from_utf8=data[at + 1 : at + 8]), "jawOpen")
    at += 8
    assert_equal(unpack_u32(Span(data), at), 1)
    assert_equal(_u16(data, at + 8), 3)
    at += 12
    assert_equal(Int(data[at]), 0x81)
    at += 4
    assert_equal(Int(data[at]), 5)
    assert_equal(String(unsafe_from_utf8=data[at + 1 : at + 6]), "still")
    at += 8
    assert_equal(unpack_u32(Span(data), at), 0)
    assert_equal(unpack_f32(Span(data), at + 4), 1.0)
    at += 8
    # Then the identity mode.
    _close(unpack_f32(Span(data), at), 0.0254 / 127)
    assert_equal(Int(data[at + 4 + 9]), 127)
    assert_equal(len(data), at + 4 + 16)


def test_the_skin_follows_its_coarse_copy() raises:
    var grid = _grid(4)
    ref points = grid[0]
    var coarse = decimate(points, grid[1], 12)
    var following = follow(points, coarse, len(points), 0.7)
    ref used = following.used
    assert_true(len(used) < len(points))
    for k in range(0, len(following.edges), 2):
        assert_true(following.edges[k] < following.edges[k + 1])
        assert_true(following.edges[k + 1] < len(used))
    # A vertex of the copy follows itself; any other lies on its
    # triangle, at weights that rebuild it.
    for v in range(len(points)):
        var a = following.corners[3 * v]
        var b = following.corners[3 * v + 1]
        var c = following.corners[3 * v + 2]
        var wb = following.weights[2 * v]
        var wc = following.weights[2 * v + 1]
        var own = -1
        for i in range(len(used)):
            if used[i] == v:
                own = i
        if own >= 0:
            assert_equal(a, own)
            assert_equal(b, own)
            assert_equal(c, own)
            continue
        for k in range(3):
            var p = (
                points[used[a]][k] * (1 - wb - wc)
                + points[used[b]][k] * wb
                + points[used[c]][k] * wc
            )
            _close(p, points[v][k], 6)
    # Every region of the nearest point: the three corners, the
    # three edges and the face.
    var a = P3(0, 0, 0)
    var b = P3(1, 0, 0)
    var c = P3(0, 1, 0)
    var probes: List[P3] = [
        P3(-1, -1, 0),
        P3(2, -0.5, 0),
        P3(-0.5, 2, 0),
        P3(0.5, -1, 0),
        P3(-1, 0.5, 0),
        P3(1, 1, 0),
        P3(0.2, 0.3, 1),
    ]
    var weights: List[Float64] = [
        0.0,
        0.0,
        1.0,
        0.0,
        0.0,
        1.0,
        0.5,
        0.0,
        0.0,
        0.5,
        0.5,
        0.5,
        0.2,
        0.3,
    ]
    for i in range(len(probes)):
        var near = closest(probes[i], a, b, c)
        _close(near.wb, weights[2 * i])
        _close(near.wc, weights[2 * i + 1])


def test_quantize_and_displacements() raises:
    var quantized = quantize([0.0, 0.0])
    assert_equal(quantized[0], 1.0)
    assert_equal(len(quantized[1]), 2)
    assert_equal(quantized[1][0], 0)
    assert_equal(quantized[1][1], 0)
    # Halves go to even, and a byte holds -127 as 0x81.
    quantized = quantize([1.27, -1.27, 0.025])
    assert_equal(Int(quantized[1][0]), 127)
    assert_equal(Int(quantized[1][1]), 0x81)
    assert_equal(Int(quantized[1][2]), 2)
    with assert_raises(contains="one vertex per neutral vertex"):
        _ = displacements([P3(0, 0, 0)], List[P3]())


def test_the_skin_and_its_holes() raises:
    var grid = _grid(2)
    var position_of = List[Int]()
    for i in range(len(grid[0])):
        position_of.append(i)
    var topology = skin_topology(position_of, grid[1], 9)
    assert_equal(len(topology.skin), 24)
    assert_equal(len(topology.edges), 32)
    # The grid's rim, run the way its triangles run it.
    assert_equal(len(topology.holes), 1)
    var rim = [0, 1, 2, 5, 8, 7, 6, 3]
    assert_equal(len(topology.holes[0]), len(rim))
    for i in range(len(rim)):
        assert_equal(topology.holes[0][i], rim[i])
    # Triangles that leave the skin are left out.
    topology = skin_topology(position_of, grid[1], 5)
    var kept = [0, 1, 4, 0, 4, 3]
    assert_equal(len(topology.skin), len(kept))
    for i in range(len(kept)):
        assert_equal(topology.skin[i], kept[i])
    # A loop that breaks off is refused, as a missing key is.
    with assert_raises():
        _ = skin_topology([0, 1, 2, 3], [0, 1, 2, 0, 1, 3], 4)


def test_decimation_keeps_the_shape() raises:
    var grid = _grid(6)
    ref points = grid[0]
    var fewer = decimate(points, grid[1], 20)
    assert_true(len(fewer) < len(grid[1]))
    # The rim stays: every corner of the grid is still used.
    for corner in [0, 6, 42, 48]:
        var found = False
        for v in fewer:
            if v == corner:
                found = True
        assert_true(found)
    # A flat grid stays flat, and every triangle faces up.
    for t in range(0, len(fewer), 3):
        var n = normal(
            points[fewer[t]], points[fewer[t + 1]], points[fewer[t + 2]]
        )
        assert_true(n.z > 0)
    # A triangle with no area has no plane.
    assert_false(Bool(plane_quadric(P3(0, 0, 0), P3(1, 0, 0), P3(2, 0, 0))))
    var flat: List[P3] = [P3(0, 0, 0), P3(1, 0, 0), P3(2, 0, 0), P3(0, 1, 0)]
    var kept = decimate(flat, [0, 1, 2, 0, 1, 3], 1)
    assert_equal(len(kept), 6)
    with assert_raises(contains="past the points"):
        _ = decimate(flat, [0, 1, 9], 1)


def test_main() raises:
    var outcome = run(["x"])
    assert_equal(outcome[0], 2)
    assert_true(outcome[2].startswith("usage: ict_face_model.mojo"))
    assert_equal(counts_text([1, 2, 3, 4]), "(1, 2, 3, 4)")
    assert_equal(counts_text([1]), "(1,)")
    # The default recipe needs the whole model: a missing folder fails.
    with assert_raises():
        _ = run(["x", "/nonexistent folder", "/nonexistent folder/face.bin"])


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
