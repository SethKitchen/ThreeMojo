# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.
#
# Follows u9rdcom and URWORD of InputOutput.f90 and the array readers of
# MODFLOW 6.9.0.dev0, commit 59d89e9f, which is in the public domain (CC0).
# See THIRD-PARTY-NOTICES.md.

"""The blocks, words, numbers and arrays of a MODFLOW 6 input file.

An input file has blocks. A block starts with `BEGIN NAME`, can have more
words on that line, and ends with `END NAME`. A line that starts with
`#`, `!` or `//`, or that is blank, is a comment. Words are separated by
blanks, commas and tabs. A word in single or double quotes can hold
blanks.

`InputFile` keeps the lines of each block. An array of a grid starts with
a control line: `CONSTANT value`, `INTERNAL [FACTOR f] [IPRN n]` or
`OPEN/CLOSE file [FACTOR f] [IPRN n]`. The values follow it in the free
format of Fortran: separated by blanks, commas or line ends, and `n*v`
repeats v n times.
"""

from std.os.path import join

from extensions.groundwater.cmath import cstrtod, mul
from extensions.groundwater.constants import DZERO

# A value of a real array that a factor does not change.
comptime DNODATA: Float64 = 3.0e30


def words(line: String) -> List[String]:
    """Split a line into words, as URWORD reads them.

    Args:
        line: The line.

    Returns:
        The words, without their quotes.
    """
    var out = List[String]()
    var b = line.as_bytes()
    var n = len(b)
    var i = 0
    while i < n:
        var c = b[i]
        if c == 32 or c == 44 or c == 9 or c == 13:
            i += 1
            continue
        if c == 34 or c == 39:
            var j = i + 1
            while j < n and b[j] != c:
                j += 1
            out.append(String(line[byte = i + 1 : j]))
            i = j + 1
            continue
        var j = i
        while j < n and b[j] != 32 and b[j] != 44 and b[j] != 9 and b[j] != 13:
            j += 1
        out.append(String(line[byte=i:j]))
        i = j
    return out^


def is_comment(line: String) -> Bool:
    """Return True if a line is a comment or is blank, as u9rdcom decides.

    Args:
        line: The line.

    Returns:
        Whether the line holds no data.
    """
    var b = line.as_bytes()
    var i = 0
    while i < len(b) and (b[i] == 32 or b[i] == 44 or b[i] == 9 or b[i] == 13):
        i += 1
    if i == len(b):
        return True
    if b[i] == 35 or b[i] == 33:
        return True
    if i + 1 < len(b) and b[i] == 47 and b[i + 1] == 47:
        return True
    return False


def read_real(word: String) raises -> Float64:
    """Read a real number as a list-directed Fortran read does.

    A `d` or `D` marks the exponent, as an `e` does.

    Args:
        word: The word.

    Returns:
        The number.

    Raises:
        Error: The word is not a number.
    """
    var text = word.replace("d", "e").replace("D", "e")
    var used = 0
    var x = cstrtod(text, used)
    if used == 0 or used != text.byte_length():
        raise Error(String("cannot read a real number from '", word, "'"))
    return x


def read_int(word: String) raises -> Int:
    """Read an integer as a list-directed Fortran read does.

    Args:
        word: The word.

    Returns:
        The integer.

    Raises:
        Error: The word is not an integer.
    """
    var b = word.as_bytes()
    var i = 0
    var sign = 1
    if len(b) > 0 and (b[0] == 43 or b[0] == 45):
        if b[0] == 45:
            sign = -1
        i = 1
    if i == len(b):
        raise Error(String("cannot read an integer from '", word, "'"))
    var v = 0
    while i < len(b):
        if b[i] < 48 or b[i] > 57:
            raise Error(String("cannot read an integer from '", word, "'"))
        v = v * 10 + Int(b[i] - 48)
        i += 1
    return sign * v


@fieldwise_init
struct Block(Copyable, Movable):
    """One block of an input file."""

    var name: String
    """The name of the block, in capitals."""
    var args: List[String]
    """The words after the name on the `BEGIN` line."""
    var lines: List[String]
    """The lines of the block, comments included, without the `BEGIN` and `END` lines.
    """

    def data_lines(self) -> List[List[String]]:
        """Return the words of each line that is not a comment.

        Returns:
            The words of each data line.
        """
        var out = List[List[String]]()
        for line in self.lines:
            if not is_comment(line):
                out.append(words(line))
        return out^


struct InputFile(Movable):
    """The blocks of one input file."""

    var path: String
    """The path of the file."""
    var folder: String
    """The folder of the simulation, for the files that the file names."""
    var blocks: List[Block]
    """The blocks, in the order of the file."""

    def __init__(out self, folder: String, path: String) raises:
        """Read the blocks of a file.

        Args:
            folder: The folder of the simulation.
            path: The path of the file, from the folder.

        Raises:
            Error: The file cannot be read, or a block does not end.
        """
        self.folder = folder
        self.path = path
        var text = open(join(folder, path), "r").read()
        self.blocks = parse_blocks(text, path)

    def find(self, name: String) -> Int:
        """Return the index of the first block with a name, or -1.

        Args:
            name: The name, in capitals.

        Returns:
            The index, or -1.
        """
        for i in range(len(self.blocks)):
            if self.blocks[i].name == name:
                return i
        return -1

    def find_all(self, name: String) -> List[Int]:
        """Return the index of each block with a name.

        Args:
            name: The name, in capitals.

        Returns:
            The indices, in the order of the file.
        """
        var out = List[Int]()
        for i in range(len(self.blocks)):
            if self.blocks[i].name == name:
                out.append(i)
        return out^


def parse_blocks(text: String, path: String) raises -> List[Block]:
    """Split the text of a file into blocks.

    Args:
        text: The text.
        path: The name of the file, for the errors.

    Returns:
        The blocks.

    Raises:
        Error: A block does not end, or data is outside a block.
    """
    var out = List[Block]()
    var lines = text.split("\n")
    var i = 0
    while i < len(lines):
        var line = String(lines[i])
        i += 1
        if is_comment(line):
            continue
        var w = words(line)
        if w[0].upper() != "BEGIN" or len(w) < 2:
            raise Error(
                String("In ", path, ": a line is outside a block: ", line)
            )
        var name = w[1].upper()
        var args = List[String]()
        for k in range(2, len(w)):
            args.append(w[k])
        var body = List[String]()
        var ended = False
        while i < len(lines):
            var inner = String(lines[i])
            i += 1
            if not is_comment(inner):
                var iw = words(inner)
                if iw[0].upper() == "END":
                    ended = True
                    break
            body.append(inner)
        if not ended:
            raise Error(String("In ", path, ": block ", name, " does not end"))
        out.append(Block(name, args^, body^))
    return out^


struct ValueReader(Movable):
    """Free-format values of Fortran, read from the lines of a block or a file.
    """

    var lines: List[String]
    """The lines to read."""
    var line: Int
    """The next line."""
    var pending: List[String]
    """The values of the current line not yet taken."""
    var repeat: Int
    """How many more times to give `repeat_value`."""
    var repeat_value: String
    """The value of an `n*v` item."""

    def __init__(out self, var lines: List[String], start: Int):
        """Read values from a list of lines.

        Args:
            lines: The lines.
            start: The first line to read.
        """
        self.lines = lines^
        self.line = start
        self.pending = List[String]()
        self.repeat = 0
        self.repeat_value = String()

    def next(mut self) raises -> String:
        """Return the next value.

        Returns:
            The text of the value.

        Raises:
            Error: The lines end.
        """
        if self.repeat > 0:
            self.repeat -= 1
            return self.repeat_value
        while len(self.pending) == 0:
            if self.line >= len(self.lines):
                raise Error("the data ends before the array is full")
            var w = words(self.lines[self.line])
            self.line += 1
            for k in range(len(w) - 1, -1, -1):
                self.pending.append(w[k])
        var v = self.pending.pop()
        var star = v.find("*")
        if star > 0:
            var n = read_int(String(v[byte=0:star]))
            self.repeat_value = String(v[byte = star + 1 :])
            self.repeat = n - 1
            return self.repeat_value
        return v^


@fieldwise_init
struct ArrayControl(Copyable, Movable):
    """The control line of an array."""

    var kind: String
    """CONSTANT, INTERNAL or OPEN/CLOSE."""
    var value: String
    """The value of a constant, or the name of a file."""
    var factor: String
    """The text of the factor, or empty."""


def read_control(w: List[String], name: String) raises -> ArrayControl:
    """Read the control words of an array.

    Args:
        w: The words of the line.
        name: The name of the array, for the errors.

    Returns:
        The control.

    Raises:
        Error: The control is not CONSTANT, INTERNAL or OPEN/CLOSE.
    """
    var kind = w[0].upper()
    var value = String()
    var k = 1
    if kind == "CONSTANT":
        if k >= len(w):
            raise Error(String("Error reading control record for ", name))
        value = w[k]
        k += 1
    elif kind == "OPEN/CLOSE":
        if k >= len(w):
            raise Error(String("Error reading control record for ", name))
        value = w[k]
        k += 1
    elif kind != "INTERNAL":
        raise Error(
            String(
                "Error reading control record for ",
                name,
                ". Use CONSTANT, INTERNAL, or OPEN/CLOSE.",
            )
        )
    var factor = String()
    if kind != "CONSTANT":
        while k < len(w):
            var key = w[k].upper()
            k += 1
            if key == "FACTOR" and k < len(w):
                factor = w[k]
                k += 1
            elif key == "IPRN" and k < len(w):
                k += 1
            elif key == "(BINARY)":
                raise Error(String("binary arrays are not supported: ", name))
    return ArrayControl(kind, value, factor)


def read_double_array(
    file: InputFile,
    lines: List[String],
    mut line: Int,
    n: Int,
    name: String,
) raises -> List[Float64]:
    """Read one real array whose control line is `lines[line]`.

    Args:
        file: The input file, for the folder of OPEN/CLOSE.
        lines: The lines of the block.
        line: The control line. Receives the line after the array.
        n: The number of values.
        name: The name of the array, for the errors.

    Returns:
        The values, from index 0.

    Raises:
        Error: The control or a value cannot be read.
    """
    var w = words(lines[line])
    var c = read_control(w, name)
    line += 1
    var out = List[Float64](capacity=n)
    if c.kind == "CONSTANT":
        var v = read_real(c.value)
        for _ in range(n):  # pragma: no branch
            out.append(v)
        return out^
    var vr: ValueReader
    if c.kind == "INTERNAL":
        vr = ValueReader(lines.copy(), line)
    else:
        var text = open(join(file.folder, c.value), "r").read()
        var fl = List[String]()
        for s in text.split("\n"):  # pragma: no branch
            fl.append(String(s))
        vr = ValueReader(fl^, 0)
    for _ in range(n):  # pragma: no branch
        out.append(read_real(vr.next()))
    # A list-directed read drops the rest of its last line.
    if c.kind == "INTERNAL":
        line = vr.line
    if c.factor.byte_length() > 0:
        var f = read_real(c.factor)
        if f != DZERO:
            for i in range(n):  # pragma: no branch
                if out[i] != DNODATA:
                    out[i] = mul(out[i], f)
    return out^


def read_int_array(
    file: InputFile,
    lines: List[String],
    mut line: Int,
    n: Int,
    name: String,
) raises -> List[Int]:
    """Read one integer array whose control line is `lines[line]`.

    Args:
        file: The input file, for the folder of OPEN/CLOSE.
        lines: The lines of the block.
        line: The control line. Receives the line after the array.
        n: The number of values.
        name: The name of the array, for the errors.

    Returns:
        The values, from index 0.

    Raises:
        Error: The control or a value cannot be read.
    """
    var w = words(lines[line])
    var c = read_control(w, name)
    line += 1
    var out = List[Int](capacity=n)
    if c.kind == "CONSTANT":
        var v = read_int(c.value)
        for _ in range(n):  # pragma: no branch
            out.append(v)
        return out^
    var vr: ValueReader
    if c.kind == "INTERNAL":
        vr = ValueReader(lines.copy(), line)
    else:
        var text = open(join(file.folder, c.value), "r").read()
        var fl = List[String]()
        for s in text.split("\n"):  # pragma: no branch
            fl.append(String(s))
        vr = ValueReader(fl^, 0)
    for _ in range(n):  # pragma: no branch
        out.append(read_int(vr.next()))
    # A list-directed read drops the rest of its last line.
    if c.kind == "INTERNAL":
        line = vr.line
    if c.factor.byte_length() > 0:
        var f = read_int(c.factor)
        if f != 0:
            for i in range(n):  # pragma: no branch
                out[i] = out[i] * f
    return out^


def _array_line(block: Block, name: String) -> Int:
    """Return the index of the line that names an array in a block.

    Args:
        block: The block.
        name: The name of the array, in capitals.

    Returns:
        The index of the line in `block.lines`, or -1.
    """
    for i in range(len(block.lines)):
        if is_comment(block.lines[i]):
            continue
        var w = words(block.lines[i])
        if w[0].upper() == name:
            return i
    return -1


def _control_line(block: Block, start: Int) -> Int:
    """Return the first data line at or after a line.

    Args:
        block: The block.
        start: The index of the first line to look at.

    Returns:
        The index of the line, or `len(block.lines)`.
    """
    var i = start
    while i < len(block.lines) and is_comment(block.lines[i]):
        i += 1
    return i


def read_grid_reals(
    file: InputFile, block: Block, name: String, nlay: Int, ncpl: Int
) raises -> List[Float64]:
    """Read a real array of a GRIDDATA block, by user node.

    An array with the word `LAYERED` after its name has one control line
    for each layer. Other arrays have one control line for all the cells.

    Args:
        file: The input file.
        block: The block.
        name: The name of the array, in capitals.
        nlay: The number of layers.
        ncpl: The number of cells in a layer.

    Returns:
        The values from index 1, or an empty list if the block does not
        name the array.

    Raises:
        Error: The array cannot be read.
    """
    var at = _array_line(block, name)
    if at < 0:
        return List[Float64]()
    var w = words(block.lines[at])
    var layered = len(w) > 1 and w[1].upper() == "LAYERED"
    var out: List[Float64] = [0.0]
    var line = at + 1
    var parts = 1
    var n = nlay * ncpl
    if layered:
        parts = nlay
        n = ncpl
    for _ in range(parts):  # pragma: no branch
        line = _control_line(block, line)
        if line >= len(block.lines):
            raise Error(String("Error reading control record for ", name))
        var a = read_double_array(file, block.lines, line, n, name)
        out.extend(a^)
    return out^


def read_grid_ints(
    file: InputFile, block: Block, name: String, nlay: Int, ncpl: Int
) raises -> List[Int]:
    """Read an integer array of a GRIDDATA block, by user node.

    Args:
        file: The input file.
        block: The block.
        name: The name of the array, in capitals.
        nlay: The number of layers.
        ncpl: The number of cells in a layer.

    Returns:
        The values from index 1, or an empty list if the block does not
        name the array.

    Raises:
        Error: The array cannot be read.
    """
    var at = _array_line(block, name)
    if at < 0:
        return List[Int]()
    var w = words(block.lines[at])
    var layered = len(w) > 1 and w[1].upper() == "LAYERED"
    var out: List[Int] = [0]
    var line = at + 1
    var parts = 1
    var n = nlay * ncpl
    if layered:
        parts = nlay
        n = ncpl
    for _ in range(parts):  # pragma: no branch
        line = _control_line(block, line)
        if line >= len(block.lines):
            raise Error(String("Error reading control record for ", name))
        var a = read_int_array(file, block.lines, line, n, name)
        out.extend(a^)
    return out^
