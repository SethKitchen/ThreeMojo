# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md

"""Keep a share of a tree's leaf cards.

    carla_town_cards FILE

`FILE` is JSON. It has `positions`, `normals`, `uvs`, `triangles`,
`keep` and `seed`. A card is one connected piece of triangles. The
program prints the kept cards, grown about their centers, or
`{"unchanged": true}` when fewer than eight cards exist or none are
kept. `seed` is the NumPy `default_rng` seed. `mode` `seed` prints the
seed `zlib.crc32(path) + index + 7919 * lod`.
"""

from std.math import sqrt
from std.pathlib import Path
from std.sys import argv, exit, stderr

from tools._bigint import BigInt
from tools._python_float import python_repr
from tools._python_json import MISSING, PY_DICT, PY_INT, PY_LIST, PyJson
from tools._zlib import crc32
from tools._town_json import json_number, json_vec2, json_vec3


def cards_text(text: String) raises -> String:
    """Return a thinned cut-out mesh as JSON.

    Args:
        text: A JSON object with the mesh, `keep` and `seed`.

    Returns:
        The kept cards, or `{"unchanged": true}`.

    Raises:
        Error: If the JSON is not that object, a triangle index is out
            of range, or `seed` is negative.
    """
    var doc = PyJson.parse(text)
    var root = doc.root
    if doc.kind(root) != PY_DICT:
        raise Error("card request is not an object")
    var mode = doc.get(root, "mode")
    if mode != MISSING and doc.text(mode) == "seed":
        return _seed_line(doc, root)
    var xs = List[Float64]()
    var ys = List[Float64]()
    var zs = List[Float64]()
    var nxs = List[Float64]()
    var nys = List[Float64]()
    var nzs = List[Float64]()
    var us = List[Float64]()
    var vs = List[Float64]()
    json_vec3(doc, doc.at(root, "positions"), xs, ys, zs)
    json_vec3(doc, doc.at(root, "normals"), nxs, nys, nzs)
    json_vec2(doc, doc.at(root, "uvs"), us, vs)
    if len(xs) != len(nxs) or len(xs) != len(us):
        raise Error("attributes differ in length")
    var faces = _triangles(doc, doc.at(root, "triangles"), len(xs))
    var keep = json_number(doc, doc.at(root, "keep"))
    var seed = _seed(doc, doc.at(root, "seed"))
    var count = len(xs)
    var label = _components(count, faces)
    var pieces = 0
    for index in range(count):
        if label[index] + 1 > pieces:
            pieces = label[index] + 1
    if pieces < 8:
        return '{"unchanged": true}'
    var draw = _random(seed, pieces)
    var chosen = List[Bool]()
    for index in range(pieces):
        chosen.append(draw[index] < keep)
    var kept = List[Int]()
    var face_count = len(faces) // 3
    for index in range(face_count):
        var base = index * 3
        if chosen[label[faces[base]]]:
            kept.append(faces[base])
            kept.append(faces[base + 1])
            kept.append(faces[base + 2])
    if len(kept) == 0:
        return '{"unchanged": true}'
    var used = _unique(kept)
    var remap = List[Int](length=count, fill=-1)
    for index in range(len(used)):
        remap[used[index]] = index
    var sums_x = List[Float64](length=pieces, fill=0.0)
    var sums_y = List[Float64](length=pieces, fill=0.0)
    var sums_z = List[Float64](length=pieces, fill=0.0)
    var bins = List[Int](length=pieces, fill=0)
    for index in range(len(used)):
        var vertex = used[index]
        var piece = label[vertex]
        sums_x[piece] += xs[vertex]
        sums_y[piece] += ys[vertex]
        sums_z[piece] += zs[vertex]
        bins[piece] += 1
    var floor = keep
    if floor < 0.001:
        floor = 0.001
    var grow = 1.0 / sqrt(floor)
    if grow > 2.0:
        grow = 2.0
    var px = List[Float64]()
    var py = List[Float64]()
    var pz = List[Float64]()
    var ox = List[Float64]()
    var oy = List[Float64]()
    var oz = List[Float64]()
    var ou = List[Float64]()
    var ov = List[Float64]()
    for index in range(len(used)):
        var vertex = used[index]
        var piece = label[vertex]
        var width = bins[piece]
        if width < 1:
            width = 1
        var cx = sums_x[piece] / Float64(width)
        var cy = sums_y[piece] / Float64(width)
        var cz = sums_z[piece] / Float64(width)
        px.append(_fadd(cx, _fmul(xs[vertex] - cx, grow)))
        py.append(_fadd(cy, _fmul(ys[vertex] - cy, grow)))
        pz.append(_fadd(cz, _fmul(zs[vertex] - cz, grow)))
        ox.append(nxs[vertex])
        oy.append(nys[vertex])
        oz.append(nzs[vertex])
        ou.append(us[vertex])
        ov.append(vs[vertex])
    var triangles = List[Int]()
    for index in range(len(kept)):
        triangles.append(remap[kept[index]])
    return _json(px, py, pz, ox, oy, oz, ou, ov, triangles)


def _components(count: Int, faces: List[Int]) -> List[Int]:
    """Return the component of each vertex, numbered from zero."""
    var head = List[Int](length=count, fill=-1)
    var dest = List[Int]()
    var nxt = List[Int]()
    var face_count = len(faces) // 3
    for index in range(face_count):
        var base = index * 3
        _link(head, dest, nxt, faces[base], faces[base + 1])
        _link(head, dest, nxt, faces[base + 1], faces[base + 2])
        _link(head, dest, nxt, faces[base + 2], faces[base])
    var seen = List[Bool](length=count, fill=False)
    var label = List[Int](length=count, fill=0)
    var pieces = 0
    var queue = List[Int]()
    for start in range(count):
        if seen[start]:
            continue
        var piece = pieces
        pieces += 1
        var read = len(queue)
        queue.append(start)
        seen[start] = True
        label[start] = piece
        while read < len(queue):
            var node = queue[read]
            read += 1
            var edge = head[node]
            while edge >= 0:
                var other = dest[edge]
                if not seen[other]:
                    seen[other] = True
                    label[other] = piece
                    queue.append(other)
                edge = nxt[edge]
    return label^


def _random(seed: List[UInt32], count: Int) -> List[Float64]:
    """Return `count` draws from NumPy `default_rng(seed).random`."""
    var pool = _seed_pool(seed)
    var words = _generate(pool)
    var state_high = (UInt64(words[1]) << 32) | UInt64(words[0])
    var state_low = (UInt64(words[3]) << 32) | UInt64(words[2])
    var inc_high = (UInt64(words[5]) << 32) | UInt64(words[4])
    var inc_low = (UInt64(words[7]) << 32) | UInt64(words[6])
    var inch = (inc_high << 1) | (inc_low >> 63)
    var incl = (inc_low << 1) | 1
    var sh = UInt64(0)
    var sl = UInt64(0)
    var stepped = _step(sh, sl, inch, incl)
    sh = stepped[0]
    sl = stepped[1]
    var added = _add(sh, sl, state_high, state_low)
    sh = added[0]
    sl = added[1]
    stepped = _step(sh, sl, inch, incl)
    sh = stepped[0]
    sl = stepped[1]
    var out = List[Float64]()
    var scale = 1.0 / 9007199254740992.0
    for _ in range(count):
        stepped = _step(sh, sl, inch, incl)
        sh = stepped[0]
        sl = stepped[1]
        var bits = _rotr(sh ^ sl, Int(sh >> 58))
        out.append(Float64(bits >> 11) * scale)
    return out^


def _seed_pool(seed: List[UInt32]) -> List[UInt32]:
    """Return the four-word NumPy `SeedSequence` pool."""
    var mixer = List[UInt32]()
    var hash_const = UInt32(0x43B0D7E5)
    var entropy = seed.copy()
    if len(entropy) == 0:
        entropy.append(0)
    for index in range(4):
        var value = UInt32(0)
        if index < len(entropy):
            value = entropy[index]
        mixer.append(_hashmix(value, hash_const))
    for source in range(4):
        for dest in range(4):
            if source != dest:
                var mixed = _hashmix(mixer[source], hash_const)
                mixer[dest] = _mix(mixer[dest], mixed)
    for source in range(4, len(entropy)):
        for dest in range(4):
            var mixed = _hashmix(entropy[source], hash_const)
            mixer[dest] = _mix(mixer[dest], mixed)
    return mixer^


def _generate(pool: List[UInt32]) -> List[UInt32]:
    """Return eight `uint32` words, as `generate_state(4, uint64)`."""
    var hash_const = UInt32(0x8B51F9DD)
    var out = List[UInt32]()
    for index in range(8):
        var data = pool[index % 4]
        data ^= hash_const
        hash_const *= UInt32(0x58F38DED)
        data *= hash_const
        data ^= data >> 16
        out.append(data)
    return out^


def _hashmix(value: UInt32, mut hash_const: UInt32) -> UInt32:
    """Mix one word and advance the hash constant."""
    var mixed = value ^ hash_const
    hash_const *= UInt32(0x931E8875)
    mixed *= hash_const
    mixed ^= mixed >> 16
    return mixed


def _mix(left: UInt32, right: UInt32) -> UInt32:
    """Fold two pool words together."""
    var result = UInt32(0xCA01F9DD) * left - UInt32(0x4973F715) * right
    result ^= result >> 16
    return result


def _step(sh: UInt64, sl: UInt64, ih: UInt64, il: UInt64) -> List[UInt64]:
    """Advance a PCG64 state by its multiplier and increment."""
    var product = _mul128(sh, sl)
    var total = _add(product[0], product[1], ih, il)
    return total^


def _mul128(sh: UInt64, sl: UInt64) -> List[UInt64]:
    """Multiply a 128-bit state by the PCG64 multiplier."""
    var low = _mul64(sl, UInt64(4865540595714422341))
    var high_a = _mul64(sl, UInt64(2549297995355413924))
    var high_b = _mul64(sh, UInt64(4865540595714422341))
    var high = (low[0] + high_a[1]) + high_b[1]
    var out = List[UInt64]()
    out.append(high)
    out.append(low[1])
    return out^


def _mul64(left: UInt64, right: UInt64) -> List[UInt64]:
    """Return the high and low halves of a 64-bit product."""
    var mask = UInt64(0xFFFFFFFF)
    var a0 = left & mask
    var a1 = left >> 32
    var b0 = right & mask
    var b1 = right >> 32
    var p0 = a0 * b0
    var p1 = a0 * b1
    var p2 = a1 * b0
    var p3 = a1 * b1
    var mid = (p0 >> 32) + (p1 & mask) + (p2 & mask)
    var low = (p0 & mask) | ((mid & mask) << 32)
    var high = p3 + (p1 >> 32) + (p2 >> 32) + (mid >> 32)
    var out = List[UInt64]()
    out.append(high)
    out.append(low)
    return out^


def _add(ah: UInt64, al: UInt64, bh: UInt64, bl: UInt64) -> List[UInt64]:
    """Add two 128-bit values."""
    var low = al + bl
    var carry = UInt64(0)
    if low < al:
        carry = 1
    var out = List[UInt64]()
    out.append(ah + bh + carry)
    out.append(low)
    return out^


def _rotr(value: UInt64, rot: Int) -> UInt64:
    """Rotate `value` right by `rot` bits."""
    var shift = UInt64(rot & 63)
    if shift == 0:
        return value
    return (value >> shift) | (value << (UInt64(64) - shift))


def _unique(values: List[Int]) -> List[Int]:
    """Return the sorted unique integers in `values`."""
    var order = List[Int]()
    for index in range(len(values)):
        order.append(index)
    _sort(values, order)
    var out = List[Int]()
    if len(order) == 0:
        return out^
    out.append(values[order[0]])
    for index in range(1, len(order)):
        var value = values[order[index]]
        if value != out[len(out) - 1]:
            out.append(value)
    return out^


def _sort(values: List[Int], mut order: List[Int]):
    """Sort `order` by `values`."""
    var count = len(order)
    var start = count // 2
    while start > 0:
        start -= 1
        _sift(values, order, start, count)
    var end = count
    while end > 1:
        end -= 1
        var tmp = order[0]
        order[0] = order[end]
        order[end] = tmp
        _sift(values, order, 0, end)


def _sift(values: List[Int], mut order: List[Int], start: Int, end: Int):
    """Restore one heap whose root is `start`."""
    var root = start
    while True:
        var child = root * 2 + 1
        if child >= end:
            return
        if child + 1 < end and values[order[child]] < values[order[child + 1]]:
            child += 1
        if values[order[root]] < values[order[child]]:
            var tmp = order[root]
            order[root] = order[child]
            order[child] = tmp
            root = child
        else:
            return


def _fmul(left: Float64, right: Float64) -> Float64:
    """Multiply two floats as a separate step."""
    return left * right


def _fadd(left: Float64, right: Float64) -> Float64:
    """Add two floats as a separate step."""
    return left + right


def _link(
    mut head: List[Int],
    mut dest: List[Int],
    mut nxt: List[Int],
    left: Int,
    right: Int,
):
    """Add an undirected edge once in each direction."""
    if left == right:
        return
    dest.append(right)
    nxt.append(head[left])
    head[left] = len(dest) - 1
    dest.append(left)
    nxt.append(head[right])
    head[right] = len(dest) - 1


def _json(
    px: List[Float64],
    py: List[Float64],
    pz: List[Float64],
    nx: List[Float64],
    ny: List[Float64],
    nz: List[Float64],
    us: List[Float64],
    vs: List[Float64],
    triangles: List[Int],
) raises -> String:
    """Return the thinned mesh as JSON."""
    var out = String('{"positions": ')
    out += _vec3_json(px, py, pz)
    out += ', "normals": '
    out += _vec3_json(nx, ny, nz)
    out += ', "uvs": '
    out += _vec2_json(us, vs)
    out += ', "triangles": ['
    var count = len(triangles) // 3
    for index in range(count):
        if index > 0:
            out += ", "
        var base = index * 3
        out += "["
        out += String(triangles[base])
        out += ", "
        out += String(triangles[base + 1])
        out += ", "
        out += String(triangles[base + 2])
        out += "]"
    out += "]}"
    return out^


def _vec3_json(
    xs: List[Float64], ys: List[Float64], zs: List[Float64]
) raises -> String:
    """Return 3-vectors as JSON."""
    var out = String("[")
    for index in range(len(xs)):
        if index > 0:
            out += ", "
        out += "["
        out += python_repr(xs[index])
        out += ", "
        out += python_repr(ys[index])
        out += ", "
        out += python_repr(zs[index])
        out += "]"
    out += "]"
    return out^


def _vec2_json(us: List[Float64], vs: List[Float64]) raises -> String:
    """Return 2-vectors as JSON."""
    var out = String("[")
    for index in range(len(us)):
        if index > 0:
            out += ", "
        out += "["
        out += python_repr(us[index])
        out += ", "
        out += python_repr(vs[index])
        out += "]"
    out += "]"
    return out^


def _triangles(doc: PyJson, node: Int, count: Int) raises -> List[Int]:
    """Return triangle indices, three per triangle."""
    if doc.kind(node) != PY_LIST:
        raise Error("triangles are not a list")
    var out = List[Int]()
    for index in range(doc.length(node)):
        var triangle = doc.item(node, index)
        if doc.kind(triangle) != PY_LIST or doc.length(triangle) != 3:
            raise Error("triangle is not three indices")
        for corner in range(3):
            var face = _whole(doc, doc.item(triangle, corner))
            if face < 0 or face >= count:
                raise Error("index out of range")
            out.append(face)
    return out^


def _seed_line(doc: PyJson, root: Int) raises -> String:
    """Return the leaf-card seed as JSON."""
    var path = doc.text(doc.at(root, "path"))
    var index = _count(doc, doc.at(root, "index"))
    var lod = _count(doc, doc.at(root, "lod"))
    if index < 0 or lod < 0:
        raise Error("seed index is negative")
    var raw = path.as_bytes()
    var data = List[UInt8]()
    for offset in range(len(raw)):
        data.append(raw[offset])
    var seed = Int(crc32(data)) + index + 7919 * lod
    return '{"seed":' + String(seed) + "}"


def _count(doc: PyJson, node: Int) raises -> Int:
    """Return a non-negative JSON integer that fits in `Int`."""
    if doc.kind(node) != PY_INT:
        raise Error("seed index is not an integer")
    return BigInt.parse(doc.text(node)).to_int()


def _seed(doc: PyJson, node: Int) raises -> List[UInt32]:
    """Return a NumPy seed as `uint32` words, lowest first."""
    if doc.kind(node) != PY_INT:
        raise Error("seed is not an integer")
    var value = BigInt.parse(doc.text(node))
    if value.negative:
        raise Error("seed is negative")
    var out = List[UInt32]()
    if len(value.limbs) == 0:
        out.append(0)
        return out^
    for limb in value.limbs:
        out.append(limb)
    return out^


def _whole(doc: PyJson, node: Int) raises -> Int:
    """Return a JSON integer."""
    if doc.kind(node) != PY_INT:
        raise Error("index is not an integer")
    return BigInt.parse(doc.text(node)).to_int()


def numpy_random(seed: Int, count: Int) raises -> List[Float64]:
    """Return draws from NumPy `default_rng(seed).random`.

    Args:
        seed: A non-negative seed.
        count: How many draws.

    Returns:
        The draws, in order.

    Raises:
        Error: If `seed` is negative.
    """
    if seed < 0:
        raise Error("seed is negative")
    var words = List[UInt32]()
    var value = seed
    if value == 0:
        words.append(0)
    else:
        while value > 0:
            words.append(UInt32(value & 0xFFFFFFFF))
            value >>= 32
    return _random(words, count)


def main() raises:
    """Print the thinned cards for the JSON file on the command line.

    Raises:
        Error: If the standard streams cannot be written.
    """
    var arguments = argv()
    if len(arguments) != 2:
        print("usage: carla_town_cards FILE", file=stderr)
        exit(2)
    try:
        print(cards_text(Path(arguments[1]).read_text()))
    except error:
        print("carla_town_cards:", error, file=stderr)
        exit(1)
