# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md

"""Convert an Unreal row-vector matrix into the renderer's frame.

    carla_town_frame FILE
    carla_town_frame serve

`FILE` is one 4×4 matrix. The program prints `linear` and `move`, where
a mesh point in meters becomes `linear @ point + move`. `serve` reads one
matrix per line and prints one object per line.
"""

from std.pathlib import Path
from std.sys import argv, exit, stderr

from tools._carla_files import read_some, write_all
from tools._json_tree import JsonTree
from tools._python_float import parse_float
from tools._python_json import PY_FLOAT, PY_INT, PY_LIST, PyJson


def frame_json(text: String) raises -> String:
    """Return one matrix in the renderer's frame, as JSON.

    Args:
        text: A JSON 4×4 matrix, nested or as 16 row-major numbers.

    Returns:
        An object with `linear`, a 3×3 matrix, and `move`, three meters.
        `move` is the translation with y and z swapped, divided by 100.

    Raises:
        Error: If the matrix is not 16 numbers.
    """
    return _frame_json(text)


def frame_text(path: String) raises -> String:
    """Return one matrix in the renderer's frame, as JSON.

    Args:
        path: A JSON 4×4 matrix, nested or as 16 row-major numbers.

    Returns:
        An object with `linear`, a 3×3 matrix, and `move`, three meters.
        `move` is the translation with y and z swapped, divided by 100.

    Raises:
        Error: If the file cannot be read, or the matrix is not 16 numbers.
    """
    return frame_json(Path(path).read_text())


def _frame_json(text: String) raises -> String:
    """Return the frame object for one JSON matrix."""
    var doc = PyJson.parse(text)
    var values = _sixteen(doc, doc.root)
    var tree = JsonTree()
    var obj = tree.object()
    var linear = tree.array()
    tree.append(linear, _row(tree, values[0], values[8], values[4]))
    tree.append(linear, _row(tree, values[2], values[10], values[6]))
    tree.append(linear, _row(tree, values[1], values[9], values[5]))
    tree.set(obj, "linear", linear)
    var move = tree.array()
    tree.append(move, tree.number(values[12] / 100.0))
    tree.append(move, tree.number(values[14] / 100.0))
    tree.append(move, tree.number(values[13] / 100.0))
    tree.set(obj, "move", move)
    return tree.dumps(obj, False)


def _row(mut tree: JsonTree, a: Float64, b: Float64, c: Float64) raises -> Int:
    """Return one JSON row of three numbers."""
    var row = tree.array()
    tree.append(row, tree.number(a))
    tree.append(row, tree.number(b))
    tree.append(row, tree.number(c))
    return row


def _sixteen(doc: PyJson, node: Int) raises -> List[Float64]:
    """Return a matrix as 16 row-major numbers."""
    if doc.kind(node) != PY_LIST:
        raise Error("matrix is not 16 numbers")
    var out = List[Float64]()
    var count = doc.length(node)
    if count == 16:
        for index in range(16):
            out.append(_number(doc, doc.item(node, index)))
        return out^
    if count == 4:
        for row in range(4):
            var line = doc.item(node, row)
            if doc.kind(line) != PY_LIST or doc.length(line) != 4:
                raise Error("matrix is not 16 numbers")
            for col in range(4):
                out.append(_number(doc, doc.item(line, col)))
        return out^
    raise Error("matrix is not 16 numbers")


def _number(doc: PyJson, node: Int) raises -> Float64:
    """Return a JSON number as `float`."""
    var kind = doc.kind(node)
    if kind == PY_FLOAT:
        return doc.number(node)
    if kind == PY_INT:
        return parse_float(doc.text(node))
    raise Error("matrix value is not a number")


struct _Line(Movable):
    """One request line, or the end of the input."""

    var done: Bool
    var text: String

    def __init__(out self, done: Bool, var text: String):
        """Store one line."""
        self.done = done
        self.text = text^


def _line() raises -> _Line:
    """Read one stdin line without its newline. An empty read is the end."""
    var out = String()
    while True:
        var block = read_some(0, 1)
        if len(block) == 0:
            if out.byte_length() == 0:
                return _Line(True, String(""))
            return _Line(False, out^)
        if block[0] == 10:
            return _Line(False, out^)
        out += chr(Int(block[0]))


def _write(text: String) raises:
    """Write `text` to stdout before the caller waits for it."""
    write_all(1, text.as_bytes())


def serve() raises:
    """Answer one matrix per line until the input ends."""
    while True:
        var taken = _line()
        if taken.done:
            return
        try:
            _write(_frame_json(taken.text) + "\n")
        except error:
            _write("err\t" + String(error) + "\n")


def main() raises:
    """Print one matrix, or serve matrices from stdin."""
    var arguments = argv()
    if len(arguments) == 2 and arguments[1] == "serve":
        serve()
        return
    if len(arguments) == 2:
        try:
            print(frame_text(arguments[1]))
        except error:
            print("carla_town_frame:", error, file=stderr)
            exit(1)
        return
    print("usage: carla_town_frame FILE | serve", file=stderr)
    exit(2)
