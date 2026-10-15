# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Time cataloged examples against three.js and, when present, Mojo 1.0.

    sh tools/tool.sh .venv/bin/mojo bench_examples [--only NAMES] [--merge]
        [--skip-threejs] [--skip-webgl] [--skip-mojo10] [--no-write-wiki]
        [--from-results] [--platform {linux,macos}]

The tool replaces `tools/bench_examples.py`. It reads `bench/catalog.json`
from the working directory, which must be the repository root. For the
same inputs it writes the same results file, wiki tables, text and exit
status as the Python tool, with these differences:

- The usage line names this program.
- The `python` host field is the version that `python3 --version` prints,
  or empty when the host has no `python3`. The Python tool wrote the
  version of the interpreter that ran it.
- Program output that is not UTF-8 is decoded with replacement
  characters. The Python tool stopped with a `UnicodeDecodeError`.
- An unexpected error prints one line and exits with status 1. Python
  printed a traceback.
"""

from std.ffi import OwnedDLHandle, external_call
from std.math import isinf, isnan
from std.os import listdir, makedirs, remove, rmdir
from std.os.path import exists, isdir, isfile, islink
from std.pathlib import Path, cwd
from std.sys import CompilationTarget, argv, exit, stderr
from std.tempfile import mkdtemp
from std.time import perf_counter_ns

from loaders.json import ARRAY, BOOLEAN, NULL, NUMBER, OBJECT, STRING
from tools._json_tools import quote_ascii
from tools._json_tree import NOTHING, JsonTree, equal, type_name
from tools._python_float import parse_float, python_repr
from tools._python_json import py_repr
from tools._python_stats import format_fixed
from tools._text import split_lines

comptime TIME_BIN = "/usr/bin/time"
"""The `time` program that reports the peak resident set."""
comptime RUNS = 3
"""How many times a built binary runs for one number. The fastest counts."""
comptime TIE_RATIO = 0.10
"""A gap under this fraction is a tie. Lower is better."""
comptime WIN_LOT_RATIO = 0.30
"""A gap of this fraction or more is a large win."""
comptime WIKI = "docs/wiki/Benchmarks.md"
"""The page whose tables the tool fills, from the repository root."""
comptime DASH = "—"
"""The cell text for a missing number."""
comptime PROGRAM = "bench_examples"
"""The program name when the command line gives none."""
comptime HOST_MISMATCH = (
    "Cannot merge results with different or missing host/toolchain metadata"
)
"""The refusal of a merge across hosts or toolchains."""
comptime DESCRIPTION = (
    "Time cataloged examples against three.js and, when present, Mojo 1.0."
)
"""The help description, as the Python tool's `argparse` showed it."""

comptime _METRIC_KEYS = [
    "ok",
    "seconds",
    "rss_kib",
    "status",
    "backend",
    "frames_seconds",
    "import_seconds",
    "error",
]
comptime _BLANK_HOSTS = ["", "unknown", "missing", "not installed"]


def this_platform() -> String:
    """Return the results key of this kind of host.

    Returns:
        `macos` on a Mac, otherwise `linux`.
    """
    comptime if CompilationTarget.is_macos():
        return "macos"
    else:
        return "linux"


def platform_title(key: String) -> String:
    """Return the heading of a host kind, as `PLATFORMS.get` gave it.

    Args:
        key: A results key.

    Returns:
        `Linux`, `macOS`, or the key itself.
    """
    if key == "linux":
        return "Linux"
    if key == "macos":
        return "macOS"
    return key


def results_path(root: String, key: String) -> String:
    """Return the results file of a host kind.

    Args:
        root: The repository root.
        key: A results key.

    Returns:
        `ROOT/bench/results-KEY.json`.
    """
    return root + "/bench/results-" + key + ".json"


# --- Python text ---------------------------------------------------------------


def _is_space(point: Int) -> Bool:
    """Return whether a code point is whitespace for `str.strip`."""
    return (
        (point >= 9 and point <= 13)
        or (point >= 0x1C and point <= 0x20)
        or point == 0x85
        or point == 0xA0
        or point == 0x1680
        or (point >= 0x2000 and point <= 0x200A)
        or point == 0x2028
        or point == 0x2029
        or point == 0x202F
        or point == 0x205F
        or point == 0x3000
    )


def _decode(text: String) -> Tuple[List[Int], List[Int]]:
    """Return the code points of UTF-8 text and the byte offset of each,
    with the end offset last."""
    var bytes = text.as_bytes()
    var points = List[Int]()
    var starts = List[Int]()
    var at = 0
    while at < len(bytes):
        var lead = Int(bytes[at])
        var width = 1
        var point = lead
        if lead >= 0xF0:
            width = 4
            point = lead & 0x07
        elif lead >= 0xE0:
            width = 3
            point = lead & 0x0F
        elif lead >= 0xC0:
            width = 2
            point = lead & 0x1F
        if at + width > len(bytes):
            width = len(bytes) - at
        for index in range(1, width):
            point = (point << 6) | (Int(bytes[at + index]) & 0x3F)
        points.append(point)
        starts.append(at)
        at += width
    starts.append(len(bytes))
    return (points^, starts^)


def py_strip(text: String) -> String:
    """Return text without surrounding whitespace, as `str.strip()` does.

    Args:
        text: UTF-8 text.

    Returns:
        The text without leading and trailing Unicode whitespace.
    """
    var decoded = _decode(text)
    ref points = decoded[0]
    ref starts = decoded[1]
    var first = 0
    var last = len(points)
    while first < last and _is_space(points[first]):
        first += 1
    while last > first and _is_space(points[last - 1]):
        last -= 1
    return String(text[byte = starts[first] : starts[last]])


def _first_chars(text: String, count: Int) -> String:
    """Return the first characters of text, as `text[:count]` does."""
    var decoded = _decode(text)
    ref starts = decoded[1]
    var stop = min(count, len(starts) - 1)
    return String(text[byte = : starts[stop]])


def _chars(text: String) -> Int:
    """Return the length of text in characters."""
    return len(_decode(text)[0])


def _universal(text: String) -> String:
    """Translate CR LF and CR to LF, as Python's text mode reads them."""
    return text.replace("\r\n", "\n").replace("\r", "\n")


def _read_text(path: String) raises -> String:
    """Read a text file as `Path.read_text` does.

    Raises:
        Error: If the file cannot be read.
    """
    if not exists(path):
        raise Error(
            "FileNotFoundError: [Errno 2] No such file or directory: "
            + py_repr(path)
        )
    return _universal(String(from_utf8_lossy=Path(path).read_bytes()))


def _ascii_lower(text: String) -> String:
    """Return text with ASCII capitals made small."""
    var out = List[UInt8]()
    for byte in text.as_bytes():
        if byte >= 65 and byte <= 90:
            out.append(byte + 32)
        else:
            out.append(byte)
    return String(unsafe_from_utf8=out)


def _join(base: String, name: String) -> String:
    """Join two path parts as `Path / name` does."""
    if name.startswith("/"):
        return name
    if base.byte_length() == 0 or base == ".":
        return name
    if base.endswith("/"):
        return base + name
    return base + "/" + name


def _parent(path: String) -> String:
    """Return a path's folder, as `Path.parent` does."""
    var cut = path.rfind("/")
    if cut < 0:
        return "."
    if cut == 0:
        return "/"
    return String(path[byte=:cut])


def _basename(path: String) -> String:
    """Return a path's last part."""
    var cut = path.rfind("/")
    return String(path[byte = cut + 1 :])


def _relative(root: String, path: String) -> String:
    """Return a path inside the root relative to it."""
    if path.startswith(root + "/"):
        return String(path[byte = root.byte_length() + 1 :])
    return path


def _normalize(path: String) -> String:
    """Return a path as `pathlib.PurePosixPath` writes it."""
    if path.byte_length() == 0:
        return "."
    var lead = String()
    if path.startswith("//") and not path.startswith("///"):
        lead = "//"
    elif path.startswith("/"):
        lead = "/"
    var parts = List[String]()
    for part in path.split("/"):
        if part.byte_length() > 0 and String(part) != ".":
            parts.append(String(part))
    var text = lead + "/".join(parts)
    if text.byte_length() == 0:
        return "."
    return text


# --- Python values -------------------------------------------------------------


def _py_repr_value(tree: JsonTree, node: Int) raises -> String:
    """Return `repr()` of a value read from JSON."""
    if tree.kind(node) == STRING:
        return py_repr(tree.text(node))
    return py_str(tree, node)


def py_str(tree: JsonTree, node: Int) raises -> String:
    """Return `str()` of a value read from JSON.

    Args:
        tree: The tree.
        node: A value or `NOTHING`.

    Returns:
        The text that Python's `str` and f-strings give.

    Raises:
        Error: If the node is not in the tree.
    """
    var kind = tree.kind(node)
    if kind == NULL:
        return "None"
    if kind == BOOLEAN:
        return "True" if tree.flag(node) else "False"
    if kind == NUMBER:
        if tree.is_int(node):
            return String(tree.int_value(node))
        return python_repr(tree.value(node))
    if kind == STRING:
        return tree.text(node)
    var parts = List[String]()
    if kind == ARRAY:
        for index in range(tree.length(node)):
            parts.append(_py_repr_value(tree, tree.at(node, index)))
        return "[" + ", ".join(parts) + "]"
    var names = tree.names(node)
    var items = tree.items(node)
    for index in range(len(names)):
        parts.append(
            py_repr(names[index]) + ": " + _py_repr_value(tree, items[index])
        )
    return "{" + ", ".join(parts) + "}"


def _num(tree: JsonTree, node: Int) raises -> Optional[Float64]:
    """Return a number, or None for `None`.

    Raises:
        Error: For a value that is neither, as Python's arithmetic does.
    """
    var kind = tree.kind(node)
    if kind == NULL:
        return None
    if kind == NUMBER or kind == BOOLEAN:
        return tree.value(node)
    raise Error(
        "TypeError: bad operand type for abs(): '" + type_name(tree, node) + "'"
    )


def _is_number(tree: JsonTree, node: Int) raises -> Bool:
    """Return `isinstance(value, (int, float))`."""
    return tree.is_numeric(node)


def _get(tree: JsonTree, node: Int, key: String) raises -> Int:
    """Return `value.get(key)`.

    Raises:
        Error: When the value is not a dict.
    """
    return tree.get(node, key)


def _get_or_empty(mut tree: JsonTree, node: Int, key: String) raises -> Int:
    """Return `value.get(key, {})`."""
    var found = tree.get(node, key)
    if found == NOTHING:
        return tree.object()
    return found


def _or_empty(mut tree: JsonTree, node: Int) raises -> Int:
    """Return `value or {}`."""
    if tree.truthy(node):
        return node
    return tree.object()


def _truthy_get(tree: JsonTree, node: Int, key: String) raises -> Bool:
    """Return `bool(value.get(key))`."""
    return tree.truthy(tree.get(node, key))


def _contains(tree: JsonTree, node: Int, key: String) raises -> Bool:
    """Return `key in value`.

    Raises:
        Error: For a value that `in` cannot search.
    """
    var kind = tree.kind(node)
    if kind == OBJECT:
        return tree.get(node, key) != NOTHING
    if kind == STRING:
        return tree.text(node).find(key) >= 0
    if kind == ARRAY:
        for index in range(tree.length(node)):
            var item = tree.at(node, index)
            if tree.kind(item) == STRING and tree.text(item) == key:
                return True
        return False
    raise Error(
        "TypeError: argument of type '"
        + type_name(tree, node)
        + "' is not iterable"
    )


def _list(tree: JsonTree, node: Int) raises -> List[Int]:
    """Return the items of a list.

    An empty dict or str iterates nothing. A full one yields strings, which
    the callers index as rows.

    Raises:
        Error: When the value is not a list, as Python's iteration and
            indexing fail.
    """
    var kind = tree.kind(node)
    if kind == ARRAY:
        return tree.items(node)
    if (kind == OBJECT or kind == STRING) and tree.length(node) == 0:
        return List[Int]()
    if kind == OBJECT or kind == STRING:
        raise Error("TypeError: string indices must be integers, not 'str'")
    raise Error(
        "TypeError: '" + type_name(tree, node) + "' object is not iterable"
    )


def _shallow(mut tree: JsonTree, node: Int) raises -> Int:
    """Return `dict(value)`, a new dict that shares the member values.

    Raises:
        Error: When the value is not a dict.
    """
    if tree.kind(node) != OBJECT:
        raise Error(
            "TypeError: '" + type_name(tree, node) + "' object is not a dict"
        )
    var copy = tree.object()
    var names = tree.names(node)
    var items = tree.items(node)
    for index in range(len(names)):
        tree.set(copy, names[index], items[index])
    return copy


def _union(mut tree: JsonTree, left: Int, right: Int) raises -> Int:
    """Return `left | right` for two dicts.

    Raises:
        Error: When either value is not a dict.
    """
    if tree.kind(left) != OBJECT or tree.kind(right) != OBJECT:
        raise Error(
            "TypeError: unsupported operand type(s) for |: '"
            + type_name(tree, left)
            + "' and '"
            + type_name(tree, right)
            + "'"
        )
    var merged = _shallow(tree, left)
    var names = tree.names(right)
    var items = tree.items(right)
    for index in range(len(names)):
        tree.set(merged, names[index], items[index])
    return merged


def _key(tree: JsonTree, node: Int) raises -> String:
    """Return a dict key for a value, so equal Python keys match.

    Raises:
        Error: For a list or a dict, which Python cannot hash.
    """
    var kind = tree.kind(node)
    if kind == STRING:
        return "s" + tree.text(node)
    if kind == NULL:
        return "n"
    if kind == NUMBER or kind == BOOLEAN:
        var value = tree.value(node)
        if (
            not isnan(value)
            and not isinf(value)
            and value == Float64(Int(value))
        ):
            if tree.is_int(node):
                return "i" + String(tree.int_value(node))
            if tree.kind(node) == BOOLEAN:
                return "i" + String(Int(value))
            return "i" + String(Int(value))
        return "f" + python_repr(value)
    raise Error("TypeError: unhashable type: '" + type_name(tree, node) + "'")


struct _Ordered(Movable):
    """A dict keyed by Python values that keeps the first insertion order."""

    var keys: List[String]
    """The keys, in insertion order."""
    var values: Dict[String, Int]
    """The value of each key."""

    def __init__(out self):
        """Start an empty dict."""
        self.keys = List[String]()
        self.values = Dict[String, Int]()

    def put(mut self, key: String, value: Int):
        """Set a key, keeping its first place."""
        if key not in self.values:
            self.keys.append(key)
        self.values[key] = value

    def find(self, key: String) -> Int:
        """Return a key's value, or `NOTHING`."""
        var found = self.values.get(key)
        if found:
            return found.value()
        return NOTHING


def dumps(tree: JsonTree, node: Int) raises -> String:
    """Write a value as `json.dumps(value, indent=2)` does.

    Args:
        tree: The tree.
        node: A value or `NOTHING`.

    Returns:
        The text, without a final newline.

    Raises:
        Error: If a node is not in the tree.
    """
    var out = String()
    _write_json(tree, out, node, 0)
    return out^


def _write_json(tree: JsonTree, mut out: String, node: Int, depth: Int) raises:
    """Append one value as `json.dumps(indent=2)` writes it."""
    var kind = tree.kind(node)
    if kind == NULL:
        out += "null"
    elif kind == BOOLEAN:
        out += "true" if tree.flag(node) else "false"
    elif kind == NUMBER:
        if tree.is_int(node):
            out += String(tree.int_value(node))
        else:
            var value = tree.value(node)
            if isnan(value):
                out += "NaN"
            elif isinf(value):
                out += "Infinity" if value > 0 else "-Infinity"
            else:
                out += python_repr(value)
    elif kind == STRING:
        out += quote_ascii(tree.text(node))
    else:
        var opener = "[" if kind == ARRAY else "{"
        var closer = "]" if kind == ARRAY else "}"
        var count = tree.length(node)
        if count == 0:
            out += opener + closer
            return
        out += opener
        var names = List[String]()
        if kind == OBJECT:
            names = tree.names(node)
        var items = tree.items(node) if kind == OBJECT else List[Int]()
        for index in range(count):
            if index > 0:
                out += ","
            out += "\n" + "  " * (depth + 1)
            var child: Int
            if kind == OBJECT:
                out += quote_ascii(names[index]) + ": "
                child = items[index]
            else:
                child = tree.at(node, index)
            _write_json(tree, out, child, depth + 1)
        out += "\n" + "  " * depth + closer


def _parse_json(mut tree: JsonTree, text: String) raises -> Int:
    """Read JSON text as `json.loads` does.

    Raises:
        Error: `json.decoder.JSONDecodeError: ...` for bad text.
    """
    try:
        return tree.parse(text)
    except error:
        raise Error("json.decoder.JSONDecodeError: " + String(error))


# --- numbers -------------------------------------------------------------------


def _fixed(value: Float64, places: Int) raises -> String:
    """Return `format(value, ".Nf")`, with `nan` and `inf` as Python writes
    them."""
    if isnan(value):
        return "nan"
    if isinf(value):
        return "inf" if value > 0 else "-inf"
    return format_fixed(value, places)


def python_round(value: Float64, places: Int) raises -> Float64:
    """Return `round(value, places)` for a float.

    Args:
        value: A double.
        places: The decimal places.

    Returns:
        The double nearest to the value rounded half to even.

    Raises:
        Error: Never for a finite value.
    """
    if isnan(value) or isinf(value):
        return value
    return parse_float(format_fixed(value, places))


def fmt_s(value: Optional[Float64]) raises -> String:
    """Round a displayed duration so sub-tenth noise does not look exact.

    Args:
        value: Seconds, or None.

    Returns:
        One decimal from 10 s, two from 0.1 s, otherwise three; `—` for
        None.

    Raises:
        Error: Never for a double.
    """
    if not value:
        return DASH
    var number = value.value()
    var magnitude = abs(number)
    if magnitude >= 10:
        return _fixed(number, 1)
    if magnitude >= 0.1:
        return _fixed(number, 2)
    return _fixed(number, 3)


def fmt_mib(kib: Optional[Float64]) raises -> String:
    """Return KiB as whole MiB.

    Args:
        kib: The size in KiB, or None.

    Returns:
        The MiB without decimals, or `—`.

    Raises:
        Error: Never for a double.
    """
    if not kib:
        return DASH
    return _fixed(kib.value() / 1024, 0)


def fmt_ratio(value: Float64) raises -> String:
    """Return a ratio with fewer decimals as it grows.

    Args:
        value: The ratio.

    Returns:
        No decimals from 10, one from 1, otherwise two.

    Raises:
        Error: Never for a double.
    """
    if value >= 10:
        return _fixed(value, 0)
    if value >= 1:
        return _fixed(value, 1)
    return _fixed(value, 2)


def good_seconds(tree: JsonTree, metric: Int) raises -> Optional[Float64]:
    """Return the seconds of a metric that ran, or None.

    Args:
        tree: The tree.
        metric: A metric dict, or `None`.

    Returns:
        The seconds when the metric is truthy, ran and holds a number.

    Raises:
        Error: When a truthy metric is not a dict.
    """
    if not tree.truthy(metric) or not _truthy_get(tree, metric, "ok"):
        return None
    var value = tree.get(metric, "seconds")
    if _is_number(tree, value):
        return tree.value(value)
    return None


def compare_pair(
    left: Optional[Float64], right: Optional[Float64]
) -> Tuple[String, String]:
    """Classify two times. Lower is better.

    Args:
        left: The first time, or None.
        right: The second time, or None.

    Returns:
        The kind of each side: `plain`, `tie`, `win_little` or `win_lot`.
    """
    if not left or not right:
        return ("plain", "plain")
    var a = left.value()
    var b = right.value()
    if a <= 0 or b <= 0:
        return ("plain", "plain")
    if a < b:
        var gap = (b - a) / a
        if gap < TIE_RATIO:
            return ("tie", "tie")
        if gap < WIN_LOT_RATIO:
            return ("win_little", "plain")
        return ("win_lot", "plain")
    if b < a:
        var gap = (a - b) / b
        if gap < TIE_RATIO:
            return ("tie", "tie")
        if gap < WIN_LOT_RATIO:
            return ("plain", "win_little")
        return ("plain", "win_lot")
    return ("tie", "tie")


def winner_name(
    left: Optional[Float64],
    right: Optional[Float64],
    left_label: String,
    right_label: String,
) -> String:
    """Name the faster side. A gap under 10% is a tie.

    Args:
        left: The first time, or None.
        right: The second time, or None.
        left_label: The first side's name.
        right_label: The second side's name.

    Returns:
        `tie`, a label, or `—`.
    """
    var kinds = compare_pair(left, right)
    if kinds[0] == "tie":
        return "tie"
    if kinds[0].startswith("win"):
        return left_label
    if kinds[1].startswith("win"):
        return right_label
    return DASH


def median(values: List[Float64]) -> Optional[Float64]:
    """Return the median, or None for no values.

    Args:
        values: The values.

    Returns:
        The middle value, or the mean of the two middle values.
    """
    if len(values) == 0:
        return None
    var ordered = values.copy()
    sort(ordered)
    var mid = len(ordered) // 2
    if len(ordered) % 2:
        return ordered[mid]
    return (ordered[mid - 1] + ordered[mid]) / 2


@fieldwise_init
struct Pair(Copyable, Movable):
    """Two times, each of which can be missing."""

    var left: Optional[Float64]
    """The ThreeMojo or Mojo 1.1 time."""
    var right: Optional[Float64]
    """The other time."""


@fieldwise_init
struct Tally(Copyable, Movable):
    """Wins for the left side, wins for the right side, and ties."""

    var mojo: Int
    """Left wins."""
    var mojo_lot: Int
    """Left wins by 30% or more."""
    var other: Int
    """Right wins."""
    var other_lot: Int
    """Right wins by 30% or more."""
    var ties: Int
    """Ties."""
    var ratio: Optional[Float64]
    """The median of right over left."""
    var count: Int
    """The pairs counted."""


def tally(pairs: List[Pair]) raises -> Tally:
    """Count wins for the left value. Lower is better. Also keep right/left.

    Args:
        pairs: The pairs.

    Returns:
        The counts and the median ratio.

    Raises:
        Error: For a missing time, as Python's comparison does.
    """
    var result = Tally(0, 0, 0, 0, 0, None, 0)
    var ratios = List[Float64]()
    for pair in pairs:
        if not pair.left:
            raise Error(
                "TypeError: '<=' not supported between instances of"
                " 'NoneType' and 'int'"
            )
        var left = pair.left.value()
        if left <= 0:
            continue
        if not pair.right:
            raise Error(
                "TypeError: unsupported operand type(s) for /: 'NoneType'"
                " and 'float'"
            )
        ratios.append(pair.right.value() / left)
        var kinds = compare_pair(pair.left, pair.right)
        if kinds[0] == "win_lot":
            result.mojo += 1
            result.mojo_lot += 1
        elif kinds[0] == "win_little":
            result.mojo += 1
        elif kinds[1] == "win_lot":
            result.other += 1
            result.other_lot += 1
        elif kinds[1] == "win_little":
            result.other += 1
        else:
            result.ties += 1
    result.ratio = median(ratios)
    result.count = result.mojo + result.other + result.ties
    return result^


# --- processes -----------------------------------------------------------------


@fieldwise_init
struct Finished(Movable):
    """What a finished program left."""

    var status: Int
    """The exit status, or minus the signal that stopped the program."""
    var stdout: String
    """The standard output, decoded as Python's text mode decodes it."""
    var stderr: String
    """The standard error, decoded the same way."""
    var elapsed_ns: Int
    """The time from launch to reaping, in nanoseconds."""


def _c_string(text: String) -> List[UInt8]:
    """Return text with a final zero byte."""
    var bytes = List[UInt8](text.as_bytes())
    bytes.append(0)
    return bytes^


def _read_c_string(address: Int) -> String:
    """Return the zero-terminated text at an address."""
    if address == 0:
        return String()
    var length = external_call["strlen", Int](address)
    var bytes = List[UInt8](length=length, fill=0)
    _ = external_call["memcpy", Int](
        bytes.unsafe_ptr().unsafe_bitcast[NoneType](), address, length
    )
    return String(from_utf8_lossy=bytes)


def environment_value(name: String) -> Optional[String]:
    """Return an environment variable, or None when it is unset.

    Args:
        name: The variable.

    Returns:
        The value, which can be empty, or None.
    """
    var key = _c_string(name)
    var address = external_call["getenv", Int](
        key.unsafe_ptr().unsafe_bitcast[NoneType]()
    )
    if address == 0:
        return None
    return _read_c_string(address)


def _environ() raises -> Int:
    """Return the address of this process's environment array."""
    comptime if CompilationTarget.is_macos():
        var cell = external_call["_NSGetEnviron", Int]()
        var value = List[Int](length=1, fill=0)
        _ = external_call["memcpy", Int](
            value.unsafe_ptr().unsafe_bitcast[NoneType](), cell, 8
        )
        return value[0]
    else:
        var handle = OwnedDLHandle()
        var symbol = handle.get_symbol[Int]("environ")
        var address: Int = symbol[][]
        return address


def _environment() raises -> List[String]:
    """Return this process's environment as `NAME=VALUE` entries."""
    var base = _environ()
    var entries = List[String]()
    var cell = List[Int](length=1, fill=0)
    var index = 0
    while base != 0:
        _ = external_call["memcpy", Int](
            cell.unsafe_ptr().unsafe_bitcast[NoneType](), base + 8 * index, 8
        )
        if cell[0] == 0:
            break
        entries.append(_read_c_string(cell[0]))
        index += 1
    return entries^


def _with_overrides(
    entries: List[String], overrides: List[String]
) -> List[String]:
    """Return environment entries with overrides set, as `{**a, **b}`."""
    var result = entries.copy()
    for override in overrides:
        var name = String(override[byte = : override.find("=") + 1])
        var replaced = False
        for index in range(len(result)):
            if result[index].startswith(name):
                result[index] = override
                replaced = True
                break
        if not replaced:
            result.append(override)
    return result^


def _executable(path: String) -> Bool:
    """Return whether a path is a file that this process can run."""
    var bytes = _c_string(path)
    var allowed = external_call["access", Int32](
        bytes.unsafe_ptr().unsafe_bitcast[NoneType](), Int32(1)
    )
    return allowed == 0 and isfile(path)


def _lookup(program: String, search: Optional[String]) -> Optional[String]:
    """Find a program as `shutil.which` does on a `PATH` value."""
    if program.find("/") >= 0:
        if exists(program) and _executable(program) and not isdir(program):
            return program
        return None
    var path = search.value() if search else String("/bin:/usr/bin")
    var seen = List[String]()
    for part in path.split(":"):
        var folder = String(part)
        var known = False
        for item in seen:
            if item == folder:
                known = True
        if known:
            continue
        seen.append(folder)
        var candidate = program if folder.byte_length() == 0 else _join(
            folder, program
        )
        if (
            exists(candidate)
            and _executable(candidate)
            and not isdir(candidate)
        ):
            return candidate
    return None


def which(program: String) -> Optional[String]:
    """Find a program on `PATH`, as `shutil.which` does.

    Args:
        program: The program name.

    Returns:
        The path, or None.
    """
    return _lookup(program, environment_value("PATH"))


def _resolve(
    program: String, directory: String, overrides: List[String]
) raises -> String:
    """Find the file that `subprocess` runs for a program.

    Raises:
        Error: `FileNotFoundError` or `PermissionError`, as `subprocess`
            raises them.
    """
    if program.find("/") >= 0:
        var path = program
        if not path.startswith("/") and directory.byte_length() > 0:
            path = _join(directory, program)
        if not exists(path):
            raise Error(
                "FileNotFoundError: [Errno 2] No such file or directory: "
                + py_repr(program)
            )
        if not _executable(path):
            raise Error(
                "PermissionError: [Errno 13] Permission denied: "
                + py_repr(program)
            )
        return path
    var search = environment_value("PATH")
    for override in overrides:
        if override.startswith("PATH="):
            search = String(override[byte=5:])
    var path = search.value() if search else String("/bin:/usr/bin")
    for part in path.split(":"):
        var folder = String(part)
        var candidate = _join(
            directory if folder.byte_length() == 0 else folder, program
        )
        if _executable(candidate):
            return candidate
    raise Error(
        "FileNotFoundError: [Errno 2] No such file or directory: "
        + py_repr(program)
    )


def _remove_flat(directory: String) raises:
    """Remove a flat temporary directory and its files."""
    for name in listdir(directory):
        remove(directory + "/" + name)
    rmdir(directory)


def spawn(
    arguments: List[String],
    directory: String,
    overrides: List[String],
) raises -> Finished:
    """Run a program to its end, as `subprocess.run(capture_output=True,
    text=True)` does.

    Args:
        arguments: The program and its arguments.
        directory: The working directory, or empty for this one.
        overrides: `NAME=VALUE` entries that replace or add environment
            variables.

    Returns:
        The status, both outputs and the elapsed time.

    Raises:
        Error: If the folder or the program does not exist, or the program
            cannot start.
    """
    if directory.byte_length() > 0 and not isdir(directory):
        raise Error(
            "FileNotFoundError: [Errno 2] No such file or directory: "
            + py_repr(directory)
        )
    var program = _resolve(arguments[0], directory, overrides)
    var scratch = mkdtemp(prefix="threemojo-bench-")
    var out_path = scratch + "/stdout"
    var err_path = scratch + "/stderr"
    var strings = List[List[UInt8]]()
    for word in arguments:
        strings.append(_c_string(word))
    var addresses = List[Int]()
    for i in range(len(strings)):
        addresses.append(Int(strings[i].unsafe_ptr()))
    addresses.append(0)
    var entries = _with_overrides(_environment(), overrides)
    var env_strings = List[List[UInt8]]()
    for entry in entries:
        env_strings.append(_c_string(entry))
    var env_addresses = List[Int]()
    for i in range(len(env_strings)):
        env_addresses.append(Int(env_strings[i].unsafe_ptr()))
    env_addresses.append(0)
    var path_bytes = _c_string(program)
    var out_bytes = _c_string(out_path)
    var err_bytes = _c_string(err_path)
    var dir_bytes = _c_string(directory)
    var flags: Int32
    comptime if CompilationTarget.is_macos():
        flags = Int32(0x1 | 0x200 | 0x400)
    else:
        flags = Int32(0x1 | 0x40 | 0x200)
    var actions = List[UInt8](length=1024, fill=0)
    var pointer = actions.unsafe_ptr().unsafe_bitcast[NoneType]()
    _ = external_call["posix_spawn_file_actions_init", Int32](pointer)
    _ = external_call["posix_spawn_file_actions_addopen", Int32](
        pointer,
        Int32(1),
        out_bytes.unsafe_ptr().unsafe_bitcast[NoneType](),
        flags,
        UInt32(0o600),
    )
    _ = external_call["posix_spawn_file_actions_addopen", Int32](
        pointer,
        Int32(2),
        err_bytes.unsafe_ptr().unsafe_bitcast[NoneType](),
        flags,
        UInt32(0o600),
    )
    if directory.byte_length() > 0:
        _ = external_call["posix_spawn_file_actions_addchdir_np", Int32](
            pointer, dir_bytes.unsafe_ptr().unsafe_bitcast[NoneType]()
        )
    var pid = List[Int32](length=1, fill=0)
    var status = List[Int32](length=1, fill=0)
    var started = perf_counter_ns()
    var spawned = external_call["posix_spawn", Int32](
        pid.unsafe_ptr().unsafe_bitcast[NoneType](),
        path_bytes.unsafe_ptr().unsafe_bitcast[NoneType](),
        pointer,
        Int(0),
        addresses.unsafe_ptr().unsafe_bitcast[NoneType](),
        env_addresses.unsafe_ptr().unsafe_bitcast[NoneType](),
    )
    _ = external_call["posix_spawn_file_actions_destroy", Int32](pointer)
    if spawned != 0:
        _remove_flat(scratch)
        raise Error(
            "OSError: [Errno "
            + String(spawned)
            + "] cannot start "
            + py_repr(arguments[0])
        )
    # A signal can interrupt the wait; the child is reaped on a retry.
    for _ in range(1000):
        var waited = external_call["waitpid", Int32](
            pid[0], status.unsafe_ptr().unsafe_bitcast[NoneType](), Int32(0)
        )
        if waited == pid[0]:
            break
    var elapsed = Int(perf_counter_ns() - started)
    _ = actions^
    _ = addresses^
    _ = strings^
    _ = env_addresses^
    _ = env_strings^
    _ = path_bytes^
    _ = out_bytes^
    _ = err_bytes^
    _ = dir_bytes^
    var raw = Int(status[0])
    var code: Int
    if raw & 0x7F == 0:
        code = (raw >> 8) & 0xFF
    else:
        code = -(raw & 0x7F)
    var output = String()
    if exists(out_path):
        output = _universal(String(from_utf8_lossy=Path(out_path).read_bytes()))
    var errors = String()
    if exists(err_path):
        errors = _universal(String(from_utf8_lossy=Path(err_path).read_bytes()))
    _remove_flat(scratch)
    return Finished(code, output^, errors^, elapsed)


# --- measuring -----------------------------------------------------------------


def _metric(
    mut tree: JsonTree,
    ok: Bool,
    seconds: Optional[Float64],
    rss_kib: Optional[Int],
    status: Int,
    output: String,
) raises -> Int:
    """Return a measurement dict, in the Python tool's key order."""
    var metric = tree.object()
    tree.set_flag(metric, "ok", ok)
    tree.set(
        metric,
        "seconds",
        tree.number(seconds.value()) if seconds else tree.null(),
    )
    tree.set(
        metric,
        "rss_kib",
        tree.integer(rss_kib.value()) if rss_kib else tree.null(),
    )
    tree.set(metric, "status", tree.integer(status))
    tree.set_text(metric, "output", output)
    return metric


def _failure(mut tree: JsonTree, status: Int) raises -> Int:
    """Return `{"ok": False, "seconds": None, "rss_kib": None, "status"}`."""
    var metric = tree.object()
    tree.set_flag(metric, "ok", False)
    tree.set_null(metric, "seconds")
    tree.set_null(metric, "rss_kib")
    tree.set(metric, "status", tree.integer(status))
    return metric


def _int_of_float_text(text: String) raises -> Int:
    """Return `int(float(text))`.

    Raises:
        Error: As Python's `float` and `int` do.
    """
    var value: Float64
    try:
        value = parse_float(text)
    except:
        raise Error(
            "ValueError: could not convert string to float: " + py_repr(text)
        )
    if isnan(value):
        raise Error("ValueError: cannot convert float NaN to integer")
    if isinf(value):
        raise Error("OverflowError: cannot convert float infinity to integer")
    return Int(value)


def rss_line(line: String) -> Optional[List[String]]:
    """Match `^TIME_RSS (\\S+) (\\S+) (\\S+)\\s*$` on a stripped line.

    Args:
        line: A line without surrounding whitespace.

    Returns:
        The elapsed, peak and status texts, or None.
    """
    if not line.startswith("TIME_RSS "):
        return None
    var rest = String(line[byte=9:])
    var tokens = List[String]()
    for part in rest.split(" "):
        tokens.append(String(part))
    if len(tokens) != 3:
        return None
    for token in tokens:
        if token.byte_length() == 0:
            return None
        for point in _decode(token)[0]:
            if _is_space(point):
                return None
    return tokens^


def bsd_peak(line: String) -> Optional[Int]:
    """Match `^\\s*(\\d+)\\s+maximum resident set size` on a line.

    Args:
        line: One line of BSD `time -l` output.

    Returns:
        The peak in bytes, or None.
    """
    var decoded = _decode(line)
    ref points = decoded[0]
    var at = 0
    while at < len(points) and _is_space(points[at]):
        at += 1
    var start = at
    var value = 0
    while at < len(points) and points[at] >= 48 and points[at] <= 57:
        value = value * 10 + points[at] - 48
        at += 1
    if at == start:
        return None
    var gap = at
    while at < len(points) and _is_space(points[at]):
        at += 1
    if at == gap:
        return None
    var tail = String(line[byte = decoded[1][at] :])
    if not tail.startswith("maximum resident set size"):
        return None
    return value


def _word_point(point: Int) -> Bool:
    """Return whether a code point is a regex word character."""
    return (
        (point >= 48 and point <= 57)
        or (point >= 65 and point <= 90)
        or (point >= 97 and point <= 122)
        or point == 95
        or point >= 0x80
    )


def bsd_real(text: String) -> Bool:
    """Return whether `^\\s*([0-9.]+)\\s+real\\b` matches at a line start.

    Args:
        text: The combined output.

    Returns:
        True when some line start matches, as `re.MULTILINE` searches.
    """
    var points = _decode(text)[0].copy()
    for begin in range(len(points) + 1):
        if begin > 0 and points[begin - 1] != 10:
            continue
        var at = begin
        while at < len(points) and _is_space(points[at]):
            at += 1
        var start = at
        while at < len(points) and (
            (points[at] >= 48 and points[at] <= 57) or points[at] == 46
        ):
            at += 1
        if at == start:
            continue
        var gap = at
        while at < len(points) and _is_space(points[at]):
            at += 1
        if at == gap or at + 4 > len(points):
            continue
        if (
            points[at] != 114
            or points[at + 1] != 101
            or points[at + 2] != 97
            or points[at + 3] != 108
        ):
            continue
        if at + 4 < len(points) and _word_point(points[at + 4]):
            continue
        return True
    return False


def measure_command(
    mut tree: JsonTree,
    command: List[String],
    directory: String,
    overrides: List[String],
    time_bin: String,
) raises -> Int:
    """Run a command and return elapsed seconds, peak RSS in KiB, status
    and output.

    GNU time takes a format string; BSD time, which macOS ships, prints a
    fixed report under `-l` with the peak in bytes. Both are read here.

    Args:
        tree: The tree for the metric.
        command: The program and its arguments.
        directory: The working directory.
        overrides: `NAME=VALUE` environment entries.
        time_bin: The `time` program; when it is not a file, the command
            runs alone and has no peak.

    Returns:
        The metric dict: `ok`, `seconds`, `rss_kib`, `status`, `output`.

    Raises:
        Error: If the command cannot start.
    """
    if isfile(time_bin):
        var wrapped: List[String]
        comptime if CompilationTarget.is_macos():
            wrapped = [time_bin, "-l"]
        else:
            wrapped = [time_bin, "-f", "TIME_RSS %e %M %x", "--"]
        wrapped.extend(command.copy())
        var done = spawn(wrapped, directory, overrides)
        var elapsed = python_round(Float64(done.elapsed_ns) / 1e9, 4)
        var combined = done.stdout + "\n" + done.stderr
        comptime if CompilationTarget.is_macos():
            var rss: Optional[Int] = None
            for line in split_lines(combined):
                var peak = bsd_peak(line)
                if peak:
                    rss = peak.value() // 1024
            if bsd_real(combined):
                return _metric(
                    tree, done.status == 0, elapsed, rss, done.status, combined
                )
        for line in split_lines(combined):
            var matched = rss_line(py_strip(line))
            if matched:
                ref tokens = matched.value()
                # Python reads the status first: `ok` leads the dict.
                var status = _int_of_float_text(tokens[2])
                var rss = _int_of_float_text(tokens[1])
                return _metric(
                    tree, status == 0, elapsed, rss, status, combined
                )
        return _metric(
            tree, done.status == 0, None, None, done.status, combined
        )
    var done = spawn(command, directory, overrides)
    return _metric(
        tree,
        done.status == 0,
        Float64(done.elapsed_ns) / 1e9,
        None,
        done.status,
        done.stdout + "\n" + done.stderr,
    )


# --- the host ------------------------------------------------------------------


trait Machine:
    """What the benchmark needs from the host: programs, time and text."""

    def measure(
        mut self,
        mut tree: JsonTree,
        command: List[String],
        directory: String,
        overrides: List[String],
    ) raises -> Int:
        """Run a command and return its metric dict.

        Args:
            tree: The tree for the metric.
            command: The program and its arguments.
            directory: The working directory.
            overrides: `NAME=VALUE` environment entries.

        Returns:
            The metric dict.

        Raises:
            Error: If the command cannot start.
        """
        ...

    def capture(
        mut self,
        command: List[String],
        directory: String,
        overrides: List[String],
    ) raises -> Finished:
        """Run a command and return its status and output.

        Args:
            command: The program and its arguments.
            directory: The working directory, or empty for this one.
            overrides: `NAME=VALUE` environment entries.

        Returns:
            The status and both outputs.

        Raises:
            Error: If the command cannot start.
        """
        ...

    def today(mut self) -> String:
        """Return the local date.

        Returns:
            `YYYY-MM-DD`.
        """
        ...

    def host(
        mut self,
        mut tree: JsonTree,
        mut state: State,
        mojo11: String,
        mojo10: String,
    ) raises -> Int:
        """Return the host and toolchain record.

        Args:
            tree: The tree for the record.
            state: The run's paths and caches.
            mojo11: The Mojo 1.1 compiler, or empty.
            mojo10: The Mojo 1.0 compiler, or empty.

        Returns:
            The record dict.

        Raises:
            Error: If a version query cannot start.
        """
        ...

    def out(mut self, text: String):
        """Write text to the standard output.

        Args:
            text: The text, with its newlines.
        """
        ...

    def err(mut self, text: String):
        """Write text to the standard error.

        Args:
            text: The text, with its newlines.
        """
        ...


struct State(Movable):
    """The repository root and what one run has found out."""

    var root: String
    """The repository root."""
    var threejs_ready: Bool
    """True once `bench/threejs` has its packages."""
    var gles_looked: Bool
    """True once the GLES library has been looked for."""
    var gles: String
    """The folder that holds `libGLESv2.so.2`, or empty."""

    def __init__(out self, root: String):
        """Start a run in a repository.

        Args:
            root: The repository root.
        """
        self.root = root
        self.threejs_ready = False
        self.gles_looked = False
        self.gles = String()

    def build(self) -> String:
        """Return `bench/build`.

        Returns:
            The folder of built programs.
        """
        return self.root + "/bench/build"

    def scratch(self) -> String:
        """Return `bench/scratch`.

        Returns:
            The folder of program outputs.
        """
        return self.root + "/bench/scratch"

    def threejs(self) -> String:
        """Return `bench/threejs`.

        Returns:
            The three.js runner folder.
        """
        return self.root + "/bench/threejs"


struct System(Machine):
    """The real host."""

    var time_bin: String
    """The `time` program."""

    def __init__(out self, time_bin: String = TIME_BIN):
        """Use the host's programs.

        Args:
            time_bin: The `time` program.
        """
        self.time_bin = time_bin

    def measure(
        mut self,
        mut tree: JsonTree,
        command: List[String],
        directory: String,
        overrides: List[String],
    ) raises -> Int:
        """Run a command under `time`.

        Args:
            tree: The tree for the metric.
            command: The program and its arguments.
            directory: The working directory.
            overrides: `NAME=VALUE` environment entries.

        Returns:
            The metric dict.

        Raises:
            Error: If the command cannot start.
        """
        return measure_command(
            tree, command, directory, overrides, self.time_bin
        )

    def capture(
        mut self,
        command: List[String],
        directory: String,
        overrides: List[String],
    ) raises -> Finished:
        """Run a command.

        Args:
            command: The program and its arguments.
            directory: The working directory, or empty for this one.
            overrides: `NAME=VALUE` environment entries.

        Returns:
            The status and both outputs.

        Raises:
            Error: If the command cannot start.
        """
        return spawn(command, directory, overrides)

    def today(mut self) -> String:
        """Return the local date, as `time.strftime("%Y-%m-%d")`.

        Returns:
            `YYYY-MM-DD`.
        """
        return local_date()

    def host(
        mut self,
        mut tree: JsonTree,
        mut state: State,
        mojo11: String,
        mojo10: String,
    ) raises -> Int:
        """Return the host and toolchain record.

        Args:
            tree: The tree for the record.
            state: The run's paths and caches.
            mojo11: The Mojo 1.1 compiler, or empty.
            mojo10: The Mojo 1.0 compiler, or empty.

        Returns:
            The record dict.

        Raises:
            Error: If a version query cannot start.
        """
        return host_info(self, tree, state, mojo11, mojo10)

    def out(mut self, text: String):
        """Write text to the standard output.

        Args:
            text: The text.
        """
        print(text, end="", flush=True)

    def err(mut self, text: String):
        """Write text to the standard error.

        Args:
            text: The text.
        """
        print(text, end="", file=stderr, flush=True)


def _two(value: Int) -> String:
    """Return a number with at least two digits."""
    return ("0" if value < 10 else "") + String(value)


def local_date() -> String:
    """Return the local date, as `time.strftime("%Y-%m-%d")`.

    Returns:
        `YYYY-MM-DD`.
    """
    var now = List[Int64](length=1, fill=0)
    _ = external_call["time", Int64](
        now.unsafe_ptr().unsafe_bitcast[NoneType]()
    )
    var fields = List[Int32](length=32, fill=0)
    _ = external_call["localtime_r", Int](
        now.unsafe_ptr().unsafe_bitcast[NoneType](),
        fields.unsafe_ptr().unsafe_bitcast[NoneType](),
    )
    return (
        String(Int(fields[5]) + 1900)
        + "-"
        + _two(Int(fields[4]) + 1)
        + "-"
        + _two(Int(fields[3]))
    )


def _home() -> String:
    """Return `Path.home()`."""
    var home = environment_value("HOME")
    if home:
        return _normalize(home.value())
    return "/"


def which_mojo(default: String) -> String:
    """Return the Mojo 1.1 compiler, or empty.

    Args:
        default: The pinned compiler in `.venv/`.

    Returns:
        The default when it is a file, else `mojo` on `PATH`, else empty.
    """
    if isfile(default):
        return default
    var found = which("mojo")
    return _normalize(found.value()) if found else String()


def which_node() -> String:
    """Return Node.js, or empty.

    Returns:
        `~/node/bin/node`, else a `node` on `PATH` that is not a Windows
        shim, else empty.
    """
    var home_node = _join(_home(), "node/bin/node")
    if isfile(home_node):
        return home_node
    var found = which("node")
    if found:
        var path = found.value()
        if path.find("nvm4w") < 0 and not path.endswith(".exe"):
            return _normalize(path)
    return String()


def which_npm() -> String:
    """Return npm, or empty.

    Returns:
        `~/node/bin/npm`, else an `npm` on `PATH` that is not a Windows
        shim, else empty.
    """
    var home_npm = _join(_home(), "node/bin/npm")
    if isfile(home_npm):
        return home_npm
    var found = which("npm")
    if found:
        var path = found.value()
        if path.find("nvm4w") < 0 and not path.endswith(".cmd"):
            return _normalize(path)
    return String()


def _symlink(target: String, link: String) -> Bool:
    """Make a symbolic link, and return whether it was made."""
    var a = _c_string(target)
    var b = _c_string(link)
    var made = external_call["symlink", Int32](
        a.unsafe_ptr().unsafe_bitcast[NoneType](),
        b.unsafe_ptr().unsafe_bitcast[NoneType](),
    )
    return made == 0


def _matches_deb(name: String) -> Bool:
    """Return whether a name matches `libgles2_*.deb`."""
    return (
        name.startswith("libgles2_")
        and name.endswith(".deb")
        and name.byte_length() >= 13
    )


def _find_gles(folder: String, mut found: List[String]) raises:
    """Collect `libGLESv2.so.*` below a folder in `Path.rglob` order."""
    var stack: List[String] = [folder]
    while len(stack) > 0:
        var directory = stack.pop()
        if not isdir(directory):
            continue
        var children = List[String]()
        for name in listdir(directory):
            var path = directory + "/" + name
            if name.startswith("libGLESv2.so."):
                found.append(path)
            if isdir(path) and not islink(path):
                children.append(path)
        for index in range(len(children) - 1, -1, -1):
            stack.append(children[index])


def gles_dir[M: Machine](mut machine: M, mut state: State) raises -> String:
    """Return a directory that holds `libGLESv2.so.2`, or empty.

    `webgl-node` loads that soname. Ubuntu keeps it in `libgles2`. A
    checkout without root can still fetch the dispatcher with
    `apt-get download`, which does not install it.

    Parameters:
        M: The host type.

    Args:
        machine: The host.
        state: The run's paths and caches.

    Returns:
        The folder, or empty.

    Raises:
        Error: If a download step cannot start or a file cannot be written.
    """
    if state.gles_looked:
        return state.gles
    state.gles_looked = True
    var names: List[String] = ["libGLESv2.so.2", "libGLESv2.so.2.1.0"]
    var candidates: List[String] = [
        state.threejs() + "/lib",
        _join(_home(), "gles-lib"),
        "/usr/lib/x86_64-linux-gnu",
        "/usr/lib64",
        "/usr/lib",
    ]
    for folder in candidates:
        for name in names:
            if exists(folder + "/" + name):
                var link = folder + "/libGLESv2.so.2"
                if not exists(link) and name != "libGLESv2.so.2":
                    if not _symlink(name, link):
                        continue
                state.gles = folder
                return folder
    comptime if CompilationTarget.is_macos():
        return String()
    if not which("apt-get") or not which("dpkg-deb"):
        return String()
    var dest = state.threejs() + "/lib"
    makedirs(dest, exist_ok=True)
    var fetched = machine.capture(
        ["apt-get", "download", "libgles2"], dest, List[String]()
    )
    if fetched.status != 0:
        return String()
    var debs = List[String]()
    for name in listdir(dest):
        if _matches_deb(name):
            debs.append(dest + "/" + name)
    if len(debs) == 0:
        return String()
    var extracted = machine.capture(
        ["dpkg-deb", "-x", debs[0], dest + "/extract"], "", List[String]()
    )
    if extracted.status != 0:
        return String()
    var found = List[String]()
    _find_gles(dest + "/extract", found)
    if len(found) == 0:
        return String()
    var library = found[0]
    var stored = dest + "/" + _basename(library)
    if not exists(stored):
        Path(stored).write_bytes(Span(Path(library).read_bytes()))
    var link = dest + "/libGLESv2.so.2"
    if not exists(link):
        if not _symlink(_basename(stored), link):
            raise Error(
                "FileExistsError: [Errno 17] File exists: " + py_repr(link)
            )
    state.gles = dest
    return dest


def node_env[
    M: Machine
](mut machine: M, mut state: State) raises -> List[String]:
    """Return the environment entries that the Node runs need.

    Parameters:
        M: The host type.

    Args:
        machine: The host.
        state: The run's paths and caches.

    Returns:
        `PATH` with Node's folder first, and `LD_LIBRARY_PATH` with the GLES
        folder first, when each applies.

    Raises:
        Error: If the GLES lookup fails.
    """
    var node = which_node()
    var env = List[String]()
    if node.byte_length() > 0:
        var current = environment_value("PATH")
        env.append(
            "PATH="
            + _parent(node)
            + ":"
            + (current.value() if current else String())
        )
    var folder = gles_dir(machine, state)
    if folder.byte_length() > 0:
        var current = environment_value("LD_LIBRARY_PATH")
        var value = folder
        if current and current.value().byte_length() > 0:
            value += ":" + current.value()
        env.append("LD_LIBRARY_PATH=" + value)
    return env^


def _first_line(done: Finished) -> String:
    """Return the first line of `(stdout or stderr or "").strip()`."""
    var text = done.stdout
    if text.byte_length() == 0:
        text = done.stderr
    var lines = split_lines(py_strip(text))
    return lines[0] if len(lines) > 0 else String("unknown")


def mojo_version[M: Machine](mut machine: M, binary: String) raises -> String:
    """Return the first line that `mojo --version` prints.

    Parameters:
        M: The host type.

    Args:
        machine: The host.
        binary: The compiler.

    Returns:
        The line, or `unknown`.

    Raises:
        Error: If the compiler cannot start.
    """
    return _first_line(
        machine.capture([binary, "--version"], "", List[String]())
    )


def _uname() -> List[String]:
    """Return `uname` as system, node, release, version and machine."""
    var buffer = List[UInt8](length=2048, fill=0)
    _ = external_call["uname", Int32](
        buffer.unsafe_ptr().unsafe_bitcast[NoneType]()
    )
    var width: Int
    comptime if CompilationTarget.is_macos():
        width = 256
    else:
        width = 65
    var fields = List[String]()
    for index in range(5):
        var text = List[UInt8]()
        for i in range(width):
            var byte = buffer[index * width + i]
            if byte == 0:
                break
            text.append(byte)
        fields.append(String(from_utf8_lossy=text))
    return fields^


def _sysctl[M: Machine](mut machine: M, name: String) raises -> String:
    """Return `sysctl -n NAME`, or empty when it fails."""
    var done = machine.capture(["sysctl", "-n", name], "", List[String]())
    return py_strip(done.stdout) if done.status == 0 else String()


def cpu_name[M: Machine](mut machine: M) raises -> String:
    """Return the processor's marketing name, with its core count on macOS.

    Parameters:
        M: The host type.

    Args:
        machine: The host.

    Returns:
        The `model name` of `/proc/cpuinfo` on Linux; the `sysctl` brand
        and core count on macOS.

    Raises:
        Error: If `sysctl` cannot start.
    """
    comptime if CompilationTarget.is_macos():
        var brand = _sysctl(machine, "machdep.cpu.brand_string")
        if brand.byte_length() == 0:
            brand = _uname()[4]
        var cores = _sysctl(machine, "hw.logicalcpu")
        return (
            brand + ", " + cores + " cores" if cores.byte_length()
            > 0 else brand
        )
    if isfile("/proc/cpuinfo"):
        var text = _read_text("/proc/cpuinfo")
        for line in split_lines(text):
            if _ascii_lower(line).startswith("model name"):
                var cut = line.find(":")
                if cut < 0:
                    raise Error("IndexError: list index out of range")
                return py_strip(String(line[byte = cut + 1 :]))
    var processor = String()
    try:
        var done = machine.capture(["uname", "-p"], "", List[String]())
        if done.status == 0:
            processor = py_strip(done.stdout)
    except:
        pass
    if processor == "unknown":
        processor = String()
    return processor if processor.byte_length() > 0 else _uname()[4]


def os_name() -> String:
    """Return the system name and release.

    Returns:
        `Linux 6.12.94+`, or `macOS 26.7 (arm64)`.
    """
    var fields = _uname()
    comptime if CompilationTarget.is_macos():
        var version = String()
        var plist = "/System/Library/CoreServices/SystemVersion.plist"
        if isfile(plist):
            try:
                var text = String(from_utf8_lossy=Path(plist).read_bytes())
                var key = text.find("<key>ProductVersion</key>")
                if key >= 0:
                    var open = text.find("<string>", key)
                    var close = text.find("</string>", open)
                    if open >= 0 and close > open:
                        version = String(text[byte = open + 8 : close])
            except:
                pass
        return "macOS " + version + " (" + fields[4] + ")"
    return fields[0] + " " + fields[2]


def python_version[M: Machine](mut machine: M) -> String:
    """Return the version that `python3 --version` prints.

    Parameters:
        M: The host type.

    Args:
        machine: The host.

    Returns:
        `3.12.3`, or empty when the host has no `python3`.
    """
    try:
        var done = machine.capture(["python3", "--version"], "", List[String]())
        var text = py_strip(done.stdout + done.stderr)
        if done.status == 0 and text.startswith("Python "):
            var words = String(text[byte=7:]).split(" ")
            return String(words[0])
    except:
        pass
    return String()


def host_info[
    M: Machine
](
    mut machine: M,
    mut tree: JsonTree,
    mut state: State,
    mojo11: String,
    mojo10: String,
) raises -> Int:
    """Return the host and toolchain record.

    Parameters:
        M: The host type.

    Args:
        machine: The host.
        tree: The tree for the record.
        state: The run's paths and caches.
        mojo11: The Mojo 1.1 compiler, or empty.
        mojo10: The Mojo 1.0 compiler, or empty.

    Returns:
        `os`, `cpu`, `python`, `mojo_1_1`, `mojo_1_0` and `node`.

    Raises:
        Error: If a version query cannot start.
    """
    var cpu = cpu_name(machine)
    var node = which_node()
    var node_ver = String()
    if node.byte_length() > 0:
        var env = node_env(machine, state)
        node_ver = py_strip(
            machine.capture([node, "--version"], "", env).stdout
        )
    var record = tree.object()
    tree.set_text(record, "os", os_name())
    tree.set_text(record, "cpu", cpu)
    tree.set_text(record, "python", python_version(machine))
    tree.set_text(
        record,
        "mojo_1_1",
        mojo_version(machine, mojo11) if mojo11.byte_length() > 0 else "",
    )
    tree.set_text(
        record,
        "mojo_1_0",
        mojo_version(machine, mojo10) if mojo10.byte_length() > 0 else "",
    )
    tree.set_text(record, "node", node_ver)
    return record


def find_mojo10(root: String) -> String:
    """Return the Mojo 1.0 compiler, or empty.

    Args:
        root: The repository root.

    Returns:
        `MOJO_1_0`, `.venv-mojo10/bin/mojo` or `~/.venvs/mojo10/bin/mojo`,
        whichever is a file first.
    """
    var candidates = List[String]()
    var env = environment_value("MOJO_1_0")
    if env and env.value().byte_length() > 0:
        candidates.append(_normalize(env.value()))
    candidates.append(root + "/.venv-mojo10/bin/mojo")
    candidates.append(_join(_home(), ".venvs/mojo10/bin/mojo"))
    for path in candidates:
        if isfile(path):
            return path
    return String()


# --- one benchmark -------------------------------------------------------------


def _remove_tree(path: String) raises:
    """Remove a folder and everything in it, as `shutil.rmtree` does."""
    if islink(path):
        raise Error("OSError: Cannot call rmtree on a symbolic link")
    for name in listdir(path):
        var child = path + "/" + name
        if isdir(child) and not islink(child):
            _remove_tree(child)
        else:
            remove(child)
    rmdir(path)


def ensure_dirs(state: State) raises:
    """Make `bench/build` and `bench/scratch`.

    Args:
        state: The run's paths.

    Raises:
        Error: If a folder cannot be made.
    """
    var build = state.build()
    if exists(build) and not isdir(build):
        remove(build)
    makedirs(build, exist_ok=True)
    makedirs(state.scratch(), exist_ok=True)


def example_run_args(
    tree: JsonTree, state: State, item: Int, dest: String
) raises -> Tuple[List[String], String]:
    """Return an example's arguments and working directory.

    Args:
        tree: The tree.
        state: The run's paths.
        item: The catalog entry.
        dest: The output image.

    Returns:
        The arguments, with `DEST` replaced, and the folder to run in.

    Raises:
        Error: If the entry is malformed or a folder cannot be made.
    """
    if _truthy_get(tree, item, "hardcoded_out"):
        var work = state.scratch() + "/" + tree.text(tree.item(item, "name"))
        makedirs(work + "/out", exist_ok=True)
        return (List[String](), work)
    var args = List[String]()
    var given = tree.get(item, "args")
    if given == NOTHING:
        args.append(dest)
    else:
        for token in _list(tree, given):
            var text = py_str(tree, token)
            args.append(
                dest if tree.kind(token) == STRING and text == "DEST" else text
            )
    return (args^, state.root)


def bench_compile[
    M: Machine
](
    mut machine: M,
    mut tree: JsonTree,
    state: State,
    mojo: String,
    src: String,
    binary: String,
) raises -> Int:
    """Build a program and time the build.

    Parameters:
        M: The host type.

    Args:
        machine: The host.
        tree: The tree for the metric.
        state: The run's paths.
        mojo: The compiler.
        src: The source.
        binary: The program to write.

    Returns:
        The build metric.

    Raises:
        Error: If the compiler cannot start or an old program cannot be
            removed.
    """
    ensure_dirs(state)
    makedirs(_parent(binary), exist_ok=True)
    if exists(binary):
        if isdir(binary):
            _remove_tree(binary)
        else:
            remove(binary)
    return machine.measure(
        tree,
        [mojo, "build", "-I", ".", "-o", binary, src],
        state.root,
        List[String](),
    )


@fieldwise_init
struct Payload(Movable):
    """What a run printed in its JSON line."""

    var backend: Int
    """The backend value, or `NOTHING` for the empty default."""
    var frames_seconds: Optional[Float64]
    """The frame loop in seconds."""
    var import_seconds: Optional[Float64]
    """The three.js import in seconds."""


def read_payload(mut tree: JsonTree, output: String) raises -> Payload:
    """Return the backend, the frames and the import time a run printed.

    three.js and every ThreeMojo example print one JSON line. The frames
    are the draw loop alone, timed inside the process.

    Args:
        tree: The tree for the parsed lines.
        output: The run's output.

    Returns:
        The values of the last JSON lines that hold each.

    Raises:
        Error: If the tree fails.
    """
    var result = Payload(NOTHING, None, None)
    for line in split_lines(output):
        var stripped = py_strip(line)
        if not (stripped.startswith("{") and stripped.endswith("}")):
            continue
        var payload: Int
        try:
            payload = tree.parse(stripped)
        except:
            continue
        var backend = tree.get(payload, "backend")
        if backend != NOTHING:
            result.backend = backend
        var frames = tree.get(payload, "frames_ms")
        if _is_number(tree, frames):
            result.frames_seconds = tree.value(frames) / 1000.0
        var imported = tree.get(payload, "import_ms")
        if _is_number(tree, imported):
            result.import_seconds = tree.value(imported) / 1000.0
    return result^


def _optional_number(mut tree: JsonTree, value: Optional[Float64]) -> Int:
    """Return a float node, or `None`."""
    if value:
        return tree.number(value.value())
    return tree.null()


def _faster(tree: JsonTree, candidate: Int, best: Int) raises -> Bool:
    """Return whether a run beats the best so far, as the Python test did."""
    if best == NOTHING:
        return True
    var seconds = tree.get(candidate, "seconds")
    if tree.is_null(seconds):
        return False
    var best_seconds = tree.get(best, "seconds")
    if tree.is_null(best_seconds):
        return True
    return tree.value(seconds) < tree.value(best_seconds)


def bench_run[
    M: Machine
](
    mut machine: M,
    mut tree: JsonTree,
    binary: String,
    args: List[String],
    directory: String,
) raises -> Int:
    """Run a built binary `RUNS` times and return the fastest run.

    Parameters:
        M: The host type.

    Args:
        machine: The host.
        tree: The tree for the metric.
        binary: The program.
        args: Its arguments.
        directory: The folder to run in.

    Returns:
        The fastest metric, with `frames_seconds`, or the first failure.

    Raises:
        Error: If the program cannot start.
    """
    var best = NOTHING
    var command: List[String] = [binary]
    command.extend(args.copy())
    for _ in range(RUNS):
        var result = machine.measure(tree, command, directory, List[String]())
        if not _truthy_get(tree, result, "ok"):
            return result
        var payload = read_payload(tree, tree.text(tree.item(result, "output")))
        tree.set(
            result,
            "frames_seconds",
            _optional_number(tree, payload.frames_seconds),
        )
        if _faster(tree, result, best):
            best = result
    return best


def ensure_threejs[M: Machine](mut machine: M, mut state: State) raises -> Bool:
    """Install the three.js runner's packages when they are missing.

    Parameters:
        M: The host type.

    Args:
        machine: The host.
        state: The run's paths and caches.

    Returns:
        True when the packages are there.

    Raises:
        Error: If npm cannot start.
    """
    if state.threejs_ready:
        return True
    if which_node().byte_length() == 0:
        return False
    var three = state.threejs() + "/node_modules/three"
    if exists(three):
        state.threejs_ready = True
        return True
    var npm = which_npm()
    if npm.byte_length() == 0:
        return False
    machine.out("Installing bench/threejs packages...\n")
    var env = node_env(machine, state)
    var proc = machine.capture(
        [npm, "install", "--omit=dev"], state.threejs(), env
    )
    if proc.status != 0:
        machine.out(proc.stdout + "\n")
        machine.err(proc.stderr + "\n")
        return False
    var ready = exists(three)
    state.threejs_ready = ready
    return ready


def _missing_runner(mut tree: JsonTree, text: String) raises -> Int:
    """Return the metric of a three.js run that could not start."""
    var metric = tree.object()
    tree.set_flag(metric, "ok", False)
    tree.set_null(metric, "seconds")
    tree.set_null(metric, "rss_kib")
    tree.set(metric, "status", tree.integer(127))
    tree.set_text(metric, "backend", "")
    tree.set_text(metric, "output", text)
    return metric


def bench_threejs[
    M: Machine
](
    mut machine: M,
    mut tree: JsonTree,
    mut state: State,
    name: String,
    backend_name: String,
) raises -> Int:
    """Time the three.js scene of an example.

    Parameters:
        M: The host type.

    Args:
        machine: The host.
        tree: The tree for the metric.
        state: The run's paths and caches.
        name: The example.
        backend_name: `cpu-flat` or `webgl`.

    Returns:
        The fastest metric, with the backend, frames and import time.

    Raises:
        Error: If Node cannot start.
    """
    if not ensure_threejs(machine, state):
        return _missing_runner(tree, "node or npm is missing")
    var node = which_node()
    if node.byte_length() == 0:
        return _missing_runner(tree, "node is missing")
    var result = NOTHING
    for _ in range(RUNS):
        var env = node_env(machine, state)
        var run = machine.measure(
            tree,
            [node, state.threejs() + "/run.mjs", name, backend_name],
            state.root,
            env,
        )
        if not _truthy_get(tree, run, "ok"):
            result = run
            break
        if _faster(tree, run, result):
            result = run
    var payload = read_payload(tree, tree.text(tree.item(result, "output")))
    tree.set(
        result,
        "backend",
        payload.backend if payload.backend != NOTHING else tree.string(""),
    )
    tree.set(
        result, "frames_seconds", _optional_number(tree, payload.frames_seconds)
    )
    tree.set(
        result, "import_seconds", _optional_number(tree, payload.import_seconds)
    )
    return result


def bench_baselines[
    M: Machine
](
    mut machine: M, mut tree: JsonTree, mut state: State, mojo: String
) raises -> Int:
    """Time a Mojo program that does nothing and a Node process that does
    nothing, so a reader can tell the process from the frames.

    Parameters:
        M: The host type.

    Args:
        machine: The host.
        tree: The tree for the metrics.
        state: The run's paths and caches.
        mojo: The compiler.

    Returns:
        `{"mojo": metric, "node": metric}`.

    Raises:
        Error: If a program cannot start.
    """
    var noop = state.build() + "/noop"
    var compiled = bench_compile(
        machine, tree, state, mojo, state.root + "/bench/noop.mojo", noop
    )
    var mojo_run: Int
    if _truthy_get(tree, compiled, "ok") and isfile(noop):
        mojo_run = bench_run(machine, tree, noop, List[String](), state.root)
    else:
        mojo_run = _failure(tree, 1)
    var node = which_node()
    var node_run = _failure(tree, 127)
    if node.byte_length() > 0:
        for _ in range(RUNS):
            var env = node_env(machine, state)
            var run = machine.measure(tree, [node, "-e", ""], state.root, env)
            if not _truthy_get(tree, run, "ok"):
                node_run = run
                break
            var best = tree.get(node_run, "seconds")
            var seconds = tree.get(run, "seconds")
            if tree.is_null(best) or (
                not tree.is_null(seconds)
                and tree.value(seconds) < tree.value(best)
            ):
                node_run = run
    var result = tree.object()
    tree.set(result, "mojo", mojo_run)
    tree.set(result, "node", node_run)
    return result


def bench_probe[
    M: Machine
](
    mut machine: M,
    mut tree: JsonTree,
    state: State,
    mojo: String,
    src: String,
    binary: String,
) raises -> Int:
    """Build and run the standalone probe.

    Parameters:
        M: The host type.

    Args:
        machine: The host.
        tree: The tree for the metrics.
        state: The run's paths.
        mojo: The compiler.
        src: The probe source.
        binary: The program to write.

    Returns:
        `{"compile": metric, "run": metric}`.

    Raises:
        Error: If a program cannot start.
    """
    var compiled = bench_compile(machine, tree, state, mojo, src, binary)
    var ran: Int
    if _truthy_get(tree, compiled, "ok") and isfile(binary):
        ran = bench_run(machine, tree, binary, List[String](), state.root)
    else:
        ran = _failure(tree, 0)
        tree.set(ran, "status", tree.item(compiled, "status"))
        tree.set(ran, "output", tree.item(compiled, "output"))
    var result = tree.object()
    tree.set(result, "compile", compiled)
    tree.set(result, "run", ran)
    return result


# --- reports -------------------------------------------------------------------


def refused_reason(output: String) -> String:
    """Return the first line that explains a failure.

    Args:
        output: A failed program's output.

    Returns:
        The first nonblank line without `Crashpad`, cut to 120 characters,
        or `refused`.
    """
    for line in split_lines(output):
        var stripped = py_strip(line)
        if stripped.byte_length() > 0 and stripped.find("Crashpad") < 0:
            return _first_chars(stripped, 120)
    return "refused"


def _is_date(text: String) -> Bool:
    """Return whether text is `\\d{4}-\\d{2}-\\d{2}`."""
    var bytes = text.as_bytes()
    if len(bytes) != 10:
        return False
    for index in range(10):
        var byte = bytes[index]
        if index == 4 or index == 7:
            if byte != 45:
                return False
        elif byte < 48 or byte > 57:
            return False
    return True


def _label(tree: JsonTree, date: Int, source: Int) raises -> String:
    """Return the measurement label of a date and its source."""
    if tree.kind(date) != STRING or not _is_date(tree.text(date)):
        return "unknown"
    if tree.kind(source) != STRING or tree.text(source) != "direct":
        return "unknown (legacy: " + tree.text(date) + ")"
    return tree.text(date)


def measurement_label(tree: JsonTree, row: Int) raises -> String:
    """Show a recorded row date without upgrading legacy aggregate metadata.

    Args:
        tree: The tree.
        row: An example row.

    Returns:
        The date, `unknown (legacy: DATE)`, or `unknown`.

    Raises:
        Error: When the row is not a dict.
    """
    return _label(
        tree,
        tree.get(row, "measured_on"),
        tree.get(row, "measurement_date_source"),
    )


def same_measurement_host(
    tree: JsonTree, previous: Int, host: Int
) raises -> Bool:
    """Return whether a merge keeps another host's results truthful.

    Args:
        tree: The tree.
        previous: The previous results.
        host: The new host record.

    Returns:
        True when the old host names its CPU, OS and Mojo 1.1, and equals
        the new host.

    Raises:
        Error: If a value is not in the tree.
    """
    var old = NOTHING
    if tree.kind(previous) == OBJECT:
        old = tree.get(previous, "host")
    if tree.kind(old) != OBJECT:
        return False
    for key in ["cpu", "os", "mojo_1_1"]:
        var value = tree.get(old, key)
        if tree.kind(value) != STRING:
            return False
        var cleaned = _ascii_lower(py_strip(tree.text(value)))
        for blank in materialize[_BLANK_HOSTS]():
            if cleaned == blank:
                return False
    return equal(tree, old, tree, host)


def require_same_measurement_host(
    tree: JsonTree, previous: Int, host: Int
) raises:
    """Refuse partial refreshes that would relabel another host's results.

    Args:
        tree: The tree.
        previous: The previous results.
        host: The new host record.

    Raises:
        Error: `HOST_MISMATCH` when the hosts differ or one is unnamed.
    """
    if not same_measurement_host(tree, previous, host):
        raise Error(HOST_MISMATCH)


def merge_measurements(
    mut tree: JsonTree, catalog: Int, previous: Int, fresh: Int
) raises -> Int:
    """Keep prior row dates and replace only the newly measured examples.

    Args:
        tree: The tree.
        catalog: The catalog list.
        previous: The previous results.
        fresh: The new slim results.

    Returns:
        The merged results, with rows in catalog order.

    Raises:
        Error: If the hosts differ or a value has the wrong type.
    """
    require_same_measurement_host(tree, previous, tree.item(fresh, "host"))
    var merged = _shallow(tree, fresh)
    var by_name = _Ordered()
    var old_rows = tree.get(previous, "examples")
    if old_rows != NOTHING:
        for original in _list(tree, old_rows):
            var row = _shallow(tree, original)
            if not tree.has(row, "measured_on"):
                var date = tree.get(previous, "generated_at")
                tree.set(
                    row,
                    "measured_on",
                    date if date != NOTHING else tree.null(),
                )
                tree.set_text(
                    row, "measurement_date_source", "legacy aggregate"
                )
            by_name.put(_key(tree, tree.item(row, "name")), row)
    for original in _list(tree, tree.item(fresh, "examples")):
        var row = _shallow(tree, original)
        tree.set(row, "measured_on", tree.item(fresh, "generated_at"))
        tree.set_text(row, "measurement_date_source", "direct")
        by_name.put(_key(tree, tree.item(row, "name")), row)
    var examples = tree.array()
    for item in _list(tree, catalog):
        var found = by_name.find(_key(tree, tree.item(item, "name")))
        if found != NOTHING:
            tree.append(examples, found)
    tree.set(merged, "examples", examples)
    tree.set(
        merged,
        "probe",
        _union(
            tree,
            _get_or_empty(tree, previous, "probe"),
            _get_or_empty(tree, fresh, "probe"),
        ),
    )
    tree.set(
        merged,
        "baselines",
        _union(
            tree,
            _get_or_empty(tree, previous, "baselines"),
            _get_or_empty(tree, fresh, "baselines"),
        ),
    )
    var webgl = False
    for row in tree.items(examples):
        var web = _or_empty(tree, tree.get(row, "threejs_webgl"))
        if _truthy_get(tree, web, "ok"):
            webgl = True
            break
    tree.set_flag(merged, "threejs_webgl", webgl)
    var total = 0
    var refused = 0
    for row in tree.items(examples):
        var version = tree.get(row, "mojo10")
        if not tree.truthy(version):
            continue
        total += 1
        var compiled = tree.get(version, "compile")
        if compiled == NOTHING:
            compiled = version
        if not _truthy_get(tree, compiled, "ok"):
            refused += 1
    tree.set(merged, "mojo10_total", tree.integer(total))
    tree.set(merged, "mojo10_refused", tree.integer(refused))
    return merged


def _first_truthy(
    mut tree: JsonTree, row: Int, keys: List[String]
) raises -> Int:
    """Return the first truthy `row.get(key)`, or a new empty dict."""
    for key in keys:
        var found = tree.get(row, key)
        if tree.truthy(found):
            return found
    return tree.object()


def _draw_cells(
    mut tree: JsonTree, row: Int, webgl_ok: Bool
) raises -> List[String]:
    """Return compile, three draw cells, the winner and Mojo RSS."""
    var tm = tree.item(row, "threemojo")
    var flat = _first_truthy(tree, row, ["threejs_flat", "threejs"])
    var web = _or_empty(tree, tree.get(row, "threejs_webgl"))
    var compiled = tree.item(tm, "compile")
    var ran = tree.item(tm, "run")
    var tm_ok = _truthy_get(tree, compiled, "ok") and _truthy_get(
        tree, ran, "ok"
    )
    var compile_s = String("failed")
    if _truthy_get(tree, compiled, "ok"):
        compile_s = fmt_s(_num(tree, tree.get(compiled, "seconds")))
    var tm_frames: Optional[Float64] = None
    if tm_ok:
        tm_frames = _num(tree, tree.get(ran, "frames_seconds"))
    var flat_ok = _truthy_get(tree, flat, "ok")
    var web_ok = _truthy_get(tree, web, "ok")
    var flat_frames: Optional[Float64] = None
    if flat_ok:
        flat_frames = _num(tree, tree.get(flat, "frames_seconds"))
    var web_frames: Optional[Float64] = None
    if web_ok:
        web_frames = _num(tree, tree.get(web, "frames_seconds"))
    var rival: Optional[Float64] = None
    var rival_label = String("WebGL")
    if webgl_ok and web_ok and web_frames:
        rival = web_frames
    elif flat_ok and flat_frames:
        rival = flat_frames
        rival_label = "cpu-flat"
    var winner = winner_name(tm_frames, rival, "Mojo", rival_label)
    var rss = String(DASH)
    if tm_ok:
        rss = fmt_mib(_num(tree, tree.get(ran, "rss_kib")))
    return [
        compile_s,
        fmt_s(tm_frames),
        fmt_s(flat_frames) if flat_ok else String("unavailable"),
        fmt_s(web_frames) if web_ok else String("unavailable"),
        winner,
        rss,
    ]


def example_table(
    mut tree: JsonTree, rows: Int, webgl_ok: Bool, legacy_date: Int
) raises -> String:
    """Return the per-example table of one host.

    Args:
        tree: The tree.
        rows: The example rows.
        webgl_ok: True when WebGL ran on the host.
        legacy_date: The file date for rows without one, or `NOTHING`.

    Returns:
        The Markdown table and its notes.

    Raises:
        Error: If a row is malformed.
    """
    var lines: List[String] = [
        (
            "| Example | Size | Frames | Compile (s) | Mojo draw (s) |"
            " cpu-flat draw (s) | WebGL draw (s) | Draw winner |"
            " Mojo RSS (MiB) | Measured |"
        ),
        "|---|---|---|---|---|---|---|---|---|---|",
    ]
    for row in _list(tree, rows):
        var cells = _draw_cells(tree, row, webgl_ok)
        var recorded = measurement_label(tree, row)
        if recorded == "unknown" and tree.kind(legacy_date) == STRING:
            var source = tree.string("legacy aggregate")
            recorded = _label(tree, legacy_date, source)
        lines.append(
            "| `"
            + py_str(tree, tree.item(row, "name"))
            + "` | "
            + py_str(tree, tree.item(row, "width"))
            + "×"
            + py_str(tree, tree.item(row, "height"))
            + " | "
            + py_str(tree, tree.item(row, "frames"))
            + " | "
            + cells[0]
            + " | "
            + cells[1]
            + " | "
            + cells[2]
            + " | "
            + cells[3]
            + " | "
            + cells[4]
            + " | "
            + cells[5]
            + " | "
            + recorded
            + " |"
        )
    lines.append("")
    lines.append(
        "A legacy date is from an older aggregate file; its per-row"
        " measurement date is unknown."
    )
    lines.append("")
    lines.append("Draw time is the frame loop inside the process.")
    lines.append("A gap under 10% is a tie.")
    lines.append("cpu-flat is a flat color fill with a depth test.")
    if webgl_ok:
        lines.append(
            "WebGL is the three.js draw used for the language comparison."
        )
    else:
        lines.append("WebGL did not run, so the draw winner uses cpu-flat.")
    return "\n".join(lines)


def _both_ran(mut tree: JsonTree, left: Int, right: Int) raises -> Bool:
    """Return whether both sides compiled and ran."""
    if (
        not tree.truthy(left)
        or not tree.truthy(right)
        or not _contains(tree, right, "compile")
    ):
        return False
    var left_ok = _truthy_get(
        tree, _get_or_empty(tree, left, "compile"), "ok"
    ) and _truthy_get(tree, _or_empty(tree, tree.get(left, "run")), "ok")
    var right_ok = _truthy_get(
        tree, _get_or_empty(tree, right, "compile"), "ok"
    ) and _truthy_get(tree, _or_empty(tree, tree.get(right, "run")), "ok")
    return left_ok and right_ok


def _mojo10_row(
    mut tree: JsonTree, name: String, left: Int, right: Int
) raises -> String:
    """Return one row of the Mojo 1.0 table."""
    var l = _or_empty(tree, left)
    var r = _or_empty(tree, right)
    var left_c = good_seconds(tree, tree.get(l, "compile"))
    var right_c = good_seconds(tree, tree.get(r, "compile"))
    var left_r = good_seconds(tree, tree.get(l, "run"))
    var right_r = good_seconds(tree, tree.get(r, "run"))
    return (
        "| `"
        + name
        + "` | "
        + fmt_s(left_c)
        + " | "
        + fmt_s(right_c)
        + " | "
        + winner_name(left_c, right_c, "1.1", "1.0")
        + " | "
        + fmt_s(left_r)
        + " | "
        + fmt_s(right_r)
        + " | "
        + winner_name(left_r, right_r, "1.1", "1.0")
        + " |"
    )


def mojo10_table(
    mut tree: JsonTree, probe11: Int, probe10: Int, examples: Int
) raises -> String:
    """Return the Mojo 1.1 against Mojo 1.0 table.

    Args:
        tree: The tree.
        probe11: The Mojo 1.1 probe.
        probe10: The Mojo 1.0 probe, or `None`.
        examples: The example rows.

    Returns:
        The Markdown table and its counts.

    Raises:
        Error: If a row is malformed.
    """
    var lines: List[String] = [
        (
            "| Program | 1.1 compile (s) | 1.0 compile (s) | Compile winner |"
            " 1.1 run (s) | 1.0 run (s) | Run winner |"
        ),
        "|---|---|---|---|---|---|---|",
    ]
    var ran = 0
    var refused = 0
    if _both_ran(tree, probe11, probe10):
        lines.append(_mojo10_row(tree, "probe", probe11, probe10))
        ran += 1
    elif tree.is_null(probe10):
        lines.append("| `probe` | — | not installed | — | — | — | — |")
    else:
        refused += 1
    for row in _list(tree, examples):
        var version = tree.get(row, "mojo10")
        if _both_ran(tree, tree.get(row, "threemojo"), version):
            lines.append(
                _mojo10_row(
                    tree,
                    py_str(tree, tree.item(row, "name")),
                    tree.item(row, "threemojo"),
                    version,
                )
            )
            ran += 1
        elif tree.truthy(version):
            refused += 1
    lines.append("")
    lines.append("Programs in this table: " + String(ran) + ".")
    lines.append("Refused catalog rows: " + String(refused) + ".")
    lines.append("A refused compile is not a faster compile.")
    lines.append("Those rows stay out of this table.")
    return "\n".join(lines)


def _frame_pairs(
    mut tree: JsonTree, rows: Int, key: String
) raises -> List[Pair]:
    """Return the ThreeMojo and rival frame times that both ran."""
    var pairs = List[Pair]()
    for row in _list(tree, rows):
        var tm = tree.item(tree.item(row, "threemojo"), "run")
        var other = _or_empty(tree, tree.get(row, key))
        var left = NOTHING
        if _truthy_get(tree, tm, "ok"):
            left = tree.get(tm, "frames_seconds")
        var right = NOTHING
        if _truthy_get(tree, other, "ok"):
            right = tree.get(other, "frames_seconds")
        if _is_number(tree, left) and _is_number(tree, right):
            pairs.append(Pair(tree.value(left), tree.value(right)))
    return pairs^


def score_report(
    mut tree: JsonTree, payload: Int, platform_key: String, catalog_count: Int
) raises -> String:
    """State who wins, in short sentences, without a colored cell per number.

    Args:
        tree: The tree.
        payload: The results.
        platform_key: The host kind.
        catalog_count: How many examples the catalog lists.

    Returns:
        The report.

    Raises:
        Error: If the results are malformed.
    """
    var rows = tree.get(payload, "examples")
    if not tree.truthy(rows):
        rows = tree.array()
    var lines: List[String] = ["### " + platform_title(platform_key), ""]
    var webgl_ok = _truthy_get(tree, payload, "threejs_webgl")
    var language_key = "threejs_webgl" if webgl_ok else "threejs_flat"
    var language_name = "WebGL" if webgl_ok else "cpu-flat"
    var language = tally(_frame_pairs(tree, rows, language_key))
    if not webgl_ok:
        lines.append("WebGL did not run on this host.")
        lines.append(
            "cpu-flat is a flat color fill, so the comparison is the CPU fill."
        )
        lines.append("")
    if language.count == 0:
        lines.append("This file has no ThreeMojo draw times.")
        lines.append("The draw winner stays blank until the next measurement.")
    else:
        lines.append(language_name + " is the draw comparison on this host.")
        if language.mojo:
            lines.append(
                "ThreeMojo wins "
                + String(language.mojo)
                + " draws, "
                + String(language.mojo_lot)
                + " of them by 30% or more."
            )
        if language.other:
            lines.append(
                language_name
                + " wins "
                + String(language.other)
                + " draws, "
                + String(language.other_lot)
                + " of them by 30% or more."
            )
        if language.ties == 1:
            lines.append("1 draw is within 10% and counts as a tie.")
        elif language.ties:
            lines.append(
                String(language.ties)
                + " draws are within 10% and count as ties."
            )
        if language.ratio:
            lines.append(
                "The median "
                + language_name
                + " draw takes "
                + fmt_ratio(language.ratio.value())
                + " times the ThreeMojo draw."
            )
        if not webgl_ok:
            lines.append(
                "The flat fill does less work than the ThreeMojo frame."
            )
    lines.append("")
    var flat = tally(_frame_pairs(tree, rows, "threejs_flat"))
    if flat.count and language_key != "threejs_flat":
        lines.append("cpu-flat is a flat color fill. It is not the same work.")
        if flat.ratio:
            lines.append(
                "The median cpu-flat draw takes "
                + fmt_ratio(flat.ratio.value())
                + " times the ThreeMojo draw."
            )
        lines.append("")
    var mojo_rss = List[Float64]()
    var web_rss = List[Float64]()
    var mojo_lower = 0
    var rss_compared = 0
    var mojo_run = List[Float64]()
    var web_run = List[Float64]()
    var compiles = List[Float64]()
    for row in _list(tree, rows):
        var tm = tree.item(row, "threemojo")
        var compiled = tree.item(tm, "compile")
        if _truthy_get(tree, compiled, "ok"):
            var seconds = good_seconds(tree, compiled)
            if seconds:
                compiles.append(seconds.value())
        var ran = tree.item(tm, "run")
        if _truthy_get(tree, ran, "ok"):
            var seconds = good_seconds(tree, ran)
            if seconds:
                mojo_run.append(seconds.value())
            var kib = tree.get(ran, "rss_kib")
            if _is_number(tree, kib):
                mojo_rss.append(tree.value(kib) / 1024.0)
        var rival = _or_empty(tree, tree.get(row, language_key))
        if _truthy_get(tree, rival, "ok") and _truthy_get(tree, ran, "ok"):
            var left = tree.get(ran, "rss_kib")
            var right = tree.get(rival, "rss_kib")
            if _is_number(tree, left) and _is_number(tree, right):
                rss_compared += 1
                if tree.value(left) < tree.value(right):
                    mojo_lower += 1
            var rival_seconds = good_seconds(tree, rival)
            if rival_seconds:
                web_run.append(rival_seconds.value())
            if _is_number(tree, right):
                web_rss.append(tree.value(right) / 1024.0)
    if rss_compared:
        lines.append(
            "ThreeMojo uses less memory on "
            + String(mojo_lower)
            + " of "
            + String(rss_compared)
            + " examples."
        )
    var mojo_med = median(mojo_rss)
    var web_med = median(web_rss)
    if mojo_med and web_med:
        lines.append(
            "The median resident set is "
            + _fixed(mojo_med.value(), 0)
            + " MiB for ThreeMojo and "
            + _fixed(web_med.value(), 0)
            + " MiB for "
            + language_name
            + "."
        )
    elif mojo_med:
        lines.append(
            "The median ThreeMojo resident set is "
            + _fixed(mojo_med.value(), 0)
            + " MiB."
        )
    lines.append("")
    lines.append("Whole-process time includes startup and writing the image.")
    var run_med = median(mojo_run)
    if run_med:
        lines.append(
            "The median ThreeMojo process takes " + fmt_s(run_med) + " s."
        )
    var web_med_run = median(web_run)
    if web_med_run:
        lines.append(
            "The median "
            + language_name
            + " process takes "
            + fmt_s(web_med_run)
            + " s."
        )
    var baselines = _or_empty(tree, tree.get(payload, "baselines"))
    var mojo_base = good_seconds(tree, tree.get(baselines, "mojo"))
    var node_base = good_seconds(tree, tree.get(baselines, "node"))
    if mojo_base:
        lines.append(
            "A Mojo program that does nothing takes " + fmt_s(mojo_base) + " s."
        )
    if node_base:
        lines.append(
            "A Node process that does nothing takes " + fmt_s(node_base) + " s."
        )
    var compile_med = median(compiles)
    if compile_med:
        lines.append(
            "The median Mojo 1.1 compile takes " + fmt_s(compile_med) + " s."
        )
    lines.append("")
    var version_c = List[Pair]()
    var version_r = List[Pair]()
    var refused = 0
    var probes = _or_empty(tree, tree.get(payload, "probe"))
    var probe10 = tree.get(probes, "v10")
    var probe11 = tree.get(probes, "v11")
    var lefts = List[Int]()
    var rights = List[Int]()
    if tree.truthy(probe11) or tree.truthy(probe10):
        lefts.append(probe11)
        rights.append(probe10)
    for row in _list(tree, rows):
        var version = tree.get(row, "mojo10")
        if tree.truthy(version):
            lefts.append(tree.get(row, "threemojo"))
            rights.append(version)
    var any_installed = False
    for right in rights:
        if tree.truthy(right):
            any_installed = True
    if not any_installed:
        lines.append("Mojo 1.0 is not installed on this host.")
    else:
        for index in range(len(lefts)):
            var left = lefts[index]
            var right = rights[index]
            if _both_ran(tree, left, right):
                version_c.append(
                    Pair(
                        good_seconds(tree, tree.item(left, "compile")),
                        good_seconds(tree, tree.item(right, "compile")),
                    )
                )
                version_r.append(
                    Pair(
                        good_seconds(tree, tree.item(left, "run")),
                        good_seconds(tree, tree.item(right, "run")),
                    )
                )
            elif tree.truthy(right):
                refused += 1
        var compile_tally = tally(version_c)
        var run_tally = tally(version_r)
        lines.append(
            "Mojo 1.0 runs " + String(compile_tally.count) + " programs."
        )
        lines.append("Refused programs: " + String(refused) + ".")
        lines.append("A refused compile is not a faster compile.")
        if compile_tally.count:
            var of = " of " + String(compile_tally.count) + "."
            if compile_tally.mojo:
                lines.append(
                    "On those programs, Mojo 1.1 compiles faster on "
                    + String(compile_tally.mojo)
                    + of
                )
            if compile_tally.other:
                lines.append(
                    "Mojo 1.0 compiles faster on "
                    + String(compile_tally.other)
                    + of
                )
            if compile_tally.ties == 1:
                lines.append("1 compile is within 10%.")
            elif compile_tally.ties:
                lines.append(
                    String(compile_tally.ties) + " compiles are within 10%."
                )
            lines.append("")
            var run_of = " of " + String(run_tally.count) + "."
            if run_tally.mojo:
                lines.append(
                    "Mojo 1.1 runs faster on " + String(run_tally.mojo) + run_of
                )
            if run_tally.other:
                lines.append(
                    "Mojo 1.0 runs faster on "
                    + String(run_tally.other)
                    + run_of
                )
            if run_tally.ties == 1:
                lines.append("1 run is within 10%.")
            elif run_tally.ties:
                lines.append(String(run_tally.ties) + " runs are within 10%.")
    lines.append("")
    lines.append("The catalog lists " + String(catalog_count) + " examples.")
    lines.append(
        "This host measures " + String(len(_list(tree, rows))) + " of them."
    )
    return "\n".join(lines)


def _rows_by_name(mut tree: JsonTree, results: Int) raises -> _Ordered:
    """Return `{row["name"]: row for row in results.get("examples", [])}`."""
    var rows = _Ordered()
    var examples = tree.get(results, "examples")
    if examples == NOTHING:
        return rows^
    for row in _list(tree, examples):
        rows.put(_key(tree, tree.item(row, "name")), row)
    return rows^


def cross_report(
    mut tree: JsonTree, linux_path: String, macos_path: String
) raises -> String:
    """Compare the two saved hosts by median ratio. Dates stay visible.

    Args:
        tree: The tree for the read files.
        linux_path: The Linux results file.
        macos_path: The macOS results file.

    Returns:
        The comparison, or a note when a file is missing.

    Raises:
        Error: If a file is not valid results JSON.
    """
    if not isfile(linux_path) or not isfile(macos_path):
        return (
            "One host has no results file. The machine comparison waits for"
            " that file."
        )
    var linux = _parse_json(tree, _read_text(linux_path))
    var macos = _parse_json(tree, _read_text(macos_path))
    var linux_rows = _rows_by_name(tree, linux)
    var mac_rows = _rows_by_name(tree, macos)
    var run_ratios = List[Float64]()
    var compile_ratios = List[Float64]()
    for name in linux_rows.keys:
        var row = linux_rows.find(name)
        var mac = mac_rows.find(name)
        if not tree.truthy(mac):
            continue
        var tm = tree.item(row, "threemojo")
        var mac_tm = tree.item(mac, "threemojo")
        var linux_run = good_seconds(tree, tree.item(tm, "run"))
        var mac_run = good_seconds(tree, tree.item(mac_tm, "run"))
        if (
            linux_run
            and linux_run.value() != 0
            and mac_run
            and mac_run.value() != 0
        ):
            run_ratios.append(linux_run.value() / mac_run.value())
        var linux_compile = good_seconds(tree, tree.item(tm, "compile"))
        var mac_compile = good_seconds(tree, tree.item(mac_tm, "compile"))
        if (
            linux_compile
            and linux_compile.value() != 0
            and mac_compile
            and mac_compile.value() != 0
        ):
            compile_ratios.append(linux_compile.value() / mac_compile.value())
    var run_med = median(run_ratios)
    var compile_med = median(compile_ratios)
    var linux_date = tree.get(linux, "generated_at")
    var mac_date = tree.get(macos, "generated_at")
    var lines = List[String]()
    if run_med:
        lines.append(
            "For these saved runs, the median Linux/macOS whole-process time"
            " ratio is "
            + fmt_ratio(run_med.value())
            + "."
        )
    if compile_med:
        lines.append(
            "The median Linux/macOS compile-time ratio is "
            + fmt_ratio(compile_med.value())
            + "."
        )
    lines.append("Each ratio is Linux time divided by macOS time.")
    lines.append("")
    lines.append(
        "The Linux date is "
        + (py_str(tree, linux_date) if linux_date != NOTHING else "unknown")
        + ". The macOS date is "
        + (py_str(tree, mac_date) if mac_date != NOTHING else "unknown")
        + "."
    )
    lines.append("The source and software can differ between these snapshots.")
    lines.append("These ratios do not isolate hardware speed.")
    lines.append(
        "The comparison uses " + String(len(run_ratios)) + " shared examples."
    )
    return "\n".join(lines)


def replace_span(text: String, name: String, body: String) raises -> String:
    """Replace every marked span of a page.

    Args:
        text: The page.
        name: The span name, such as `HOST:linux`.
        body: The new text between the markers.

    Returns:
        The page with each `<!-- BENCH:NAME -->` ... `<!-- /BENCH:NAME -->`
        span replaced.

    Raises:
        Error: `Benchmarks.md is missing <!-- BENCH:NAME -->` when no span
            is there.
    """
    var start = "<!-- BENCH:" + name + " -->"
    var end = "<!-- /BENCH:" + name + " -->"
    var block = start + "\n" + body + "\n" + end
    var out = String()
    var at = 0
    var found = False
    while True:
        var open = text.find(start, at)
        if open < 0:
            break
        var close = text.find(end, open + start.byte_length())
        if close < 0:
            break
        found = True
        out += String(text[byte=at:open]) + block
        at = close + end.byte_length()
    if not found:
        raise Error("Benchmarks.md is missing " + start)
    out += String(text[byte=at:])
    return out^


def slim_metric(mut tree: JsonTree, metric: Int) raises -> Int:
    """Keep a metric's recorded fields, and the reason for a failure.

    Args:
        tree: The tree.
        metric: A metric dict, or `None`.

    Returns:
        The kept fields, with `error` for a failure; `None` for `None`.

    Raises:
        Error: If the metric is malformed.
    """
    if tree.is_null(metric):
        return tree.null()
    var kept = tree.object()
    for key in materialize[_METRIC_KEYS]():
        if _contains(tree, metric, key):
            tree.set(kept, key, tree.item(metric, key))
    if not _truthy_get(tree, metric, "ok"):
        var output = tree.get(metric, "output")
        var text = output if output != NOTHING else tree.string("")
        if not tree.truthy(text):
            var error = tree.get(metric, "error")
            text = error if error != NOTHING else tree.string("")
        if tree.kind(text) != STRING:
            raise Error(
                "AttributeError: '"
                + type_name(tree, text)
                + "' object has no attribute 'splitlines'"
            )
        tree.set_text(kept, "error", refused_reason(tree.text(text)))
    return kept


def _items_of(tree: JsonTree, node: Int) raises -> List[Int]:
    """Return a dict's values, as `.items()` iterates them."""
    if tree.kind(node) != OBJECT:
        raise Error(
            "AttributeError: '"
            + type_name(tree, node)
            + "' object has no attribute 'items'"
        )
    return tree.items(node)


def slim_payload(mut tree: JsonTree, payload: Int) raises -> Int:
    """Return the results as the file records them.

    Args:
        tree: The tree.
        payload: The full results.

    Returns:
        The results without program output, with a reason per failure.

    Raises:
        Error: If the results are malformed.
    """
    var slim = tree.object()
    var generated = tree.item(payload, "generated_at")
    tree.set(slim, "generated_at", generated)
    tree.set(slim, "host", tree.item(payload, "host"))
    var webgl = tree.get(payload, "threejs_webgl")
    tree.set(
        slim,
        "threejs_webgl",
        webgl if webgl != NOTHING else tree.boolean(False),
    )
    var baselines = tree.object()
    var given = _get_or_empty(tree, payload, "baselines")
    var names = (
        tree.names(given) if tree.kind(given) == OBJECT else List[String]()
    )
    var values = _items_of(tree, given)
    for index in range(len(values)):
        tree.set(baselines, names[index], slim_metric(tree, values[index]))
    tree.set(slim, "baselines", baselines)
    tree.set(slim, "mojo10_refused", tree.item(payload, "mojo10_refused"))
    tree.set(slim, "mojo10_total", tree.item(payload, "mojo10_total"))
    var probe = tree.object()
    tree.set(slim, "probe", probe)
    var examples = tree.array()
    tree.set(slim, "examples", examples)
    var probes = tree.item(payload, "probe")
    var probe_values = _items_of(tree, probes)
    var probe_names = tree.names(probes)
    for index in range(len(probe_values)):
        var value = probe_values[index]
        var entry = tree.object()
        tree.set(
            entry, "compile", slim_metric(tree, tree.item(value, "compile"))
        )
        tree.set(entry, "run", slim_metric(tree, tree.item(value, "run")))
        tree.set(probe, probe_names[index], entry)
    for row in _list(tree, tree.item(payload, "examples")):
        var entry = tree.object()
        tree.set(entry, "name", tree.item(row, "name"))
        var measured = tree.get(row, "measured_on")
        tree.set(
            entry, "measured_on", measured if measured != NOTHING else generated
        )
        var source = tree.get(row, "measurement_date_source")
        tree.set(
            entry,
            "measurement_date_source",
            source if source != NOTHING else tree.string("direct"),
        )
        tree.set(entry, "width", tree.item(row, "width"))
        tree.set(entry, "height", tree.item(row, "height"))
        tree.set(entry, "frames", tree.item(row, "frames"))
        var tm = tree.item(row, "threemojo")
        var tm_entry = tree.object()
        tree.set(
            tm_entry, "compile", slim_metric(tree, tree.item(tm, "compile"))
        )
        tree.set(tm_entry, "run", slim_metric(tree, tree.item(tm, "run")))
        tree.set(entry, "threemojo", tm_entry)
        tree.set(
            entry,
            "threejs_flat",
            slim_metric(
                tree, _first_truthy(tree, row, ["threejs_flat", "threejs"])
            ),
        )
        tree.set(
            entry,
            "threejs_webgl",
            slim_metric(tree, _or_empty(tree, tree.get(row, "threejs_webgl"))),
        )
        var version = tree.get(row, "mojo10")
        if tree.truthy(version) and _contains(
            tree, _or_empty(tree, version), "compile"
        ):
            var version_entry = tree.object()
            tree.set(
                version_entry,
                "compile",
                slim_metric(tree, tree.item(version, "compile")),
            )
            tree.set(
                version_entry,
                "run",
                slim_metric(tree, tree.get(version, "run")),
            )
            tree.set(entry, "mojo10", version_entry)
        else:
            tree.set(
                entry, "mojo10", version if version != NOTHING else tree.null()
            )
        tree.append(examples, entry)
    return slim


def _truthy_text(tree: JsonTree, node: Int, fallback: String) raises -> String:
    """Return `str(value or fallback)`."""
    if tree.truthy(node):
        return py_str(tree, node)
    return fallback


def write_wiki(
    mut tree: JsonTree,
    root: String,
    payload: Int,
    platform_key: String,
    catalog_count: Int,
) raises:
    """Fill one host's tables on `docs/wiki/Benchmarks.md`.

    Args:
        tree: The tree.
        root: The repository root.
        payload: The results.
        platform_key: The host kind.
        catalog_count: How many examples the catalog lists.

    Raises:
        Error: If the page lacks a span or the results are malformed.
    """
    var host = tree.item(payload, "host")
    var lines = List[String]()
    lines.append(
        "- Latest refresh: `"
        + py_str(tree, tree.item(payload, "generated_at"))
        + "`"
    )
    lines.append("- OS: " + py_str(tree, tree.item(host, "os")))
    lines.append("- CPU: " + py_str(tree, tree.item(host, "cpu")))
    lines.append(
        "- Mojo 1.1: `"
        + _truthy_text(tree, tree.item(host, "mojo_1_1"), "missing")
        + "`"
    )
    lines.append(
        "- Mojo 1.0: `"
        + _truthy_text(tree, tree.item(host, "mojo_1_0"), "not installed")
        + "`"
    )
    lines.append(
        "- Node: `"
        + _truthy_text(tree, tree.item(host, "node"), "missing")
        + "`"
    )
    lines.append(
        "- three.js backends: "
        + (
            "`cpu-flat` and `webgl`" if _truthy_get(
                tree, payload, "threejs_webgl"
            ) else "`cpu-flat` (`webgl` did not run)"
        )
    )
    var baselines = _or_empty(tree, tree.get(payload, "baselines"))
    var mojo = _or_empty(tree, tree.get(baselines, "mojo"))
    var node = _or_empty(tree, tree.get(baselines, "node"))
    lines.append(
        "- A Mojo program that does nothing: `"
        + fmt_s(good_seconds(tree, mojo))
        + "` s"
    )
    lines.append(
        "- A Node process that does nothing: `"
        + fmt_s(good_seconds(tree, node))
        + "` s"
    )
    var host_md = "\n".join(lines)
    var path = root + "/" + WIKI
    var text = _read_text(path)
    text = replace_span(text, "HOST:" + platform_key, host_md)
    text = replace_span(
        text,
        "SCORE:" + platform_key,
        score_report(tree, payload, platform_key, catalog_count),
    )
    text = replace_span(
        text,
        "CROSS",
        cross_report(
            tree, results_path(root, "linux"), results_path(root, "macos")
        ),
    )
    text = replace_span(
        text,
        "EXAMPLES:" + platform_key,
        example_table(
            tree,
            tree.item(payload, "examples"),
            _truthy_get(tree, payload, "threejs_webgl"),
            tree.get(payload, "generated_at"),
        ),
    )
    var probes = tree.item(payload, "probe")
    text = replace_span(
        text,
        "MOJO10:" + platform_key,
        mojo10_table(
            tree,
            _or_empty(tree, tree.get(probes, "v11")),
            tree.get(probes, "v10"),
            tree.item(payload, "examples"),
        ),
    )
    Path(path).write_text(text)


def emit_tables[
    M: Machine
](
    mut machine: M,
    mut tree: JsonTree,
    root: String,
    payload: Int,
    write_wiki_page: Bool,
    platform_key: String,
    catalog_count: Int,
) raises:
    """Print both tables, and fill the page when asked.

    Parameters:
        M: The host type.

    Args:
        machine: The host, for the text.
        tree: The tree.
        root: The repository root.
        payload: The results.
        write_wiki_page: True to fill `docs/wiki/Benchmarks.md`.
        platform_key: The host kind.
        catalog_count: How many examples the catalog lists.

    Raises:
        Error: If the results are malformed or the page lacks a span.
    """
    machine.out(
        example_table(
            tree,
            tree.item(payload, "examples"),
            _truthy_get(tree, payload, "threejs_webgl"),
            tree.get(payload, "generated_at"),
        )
        + "\n"
    )
    machine.out("\n")
    var probes = tree.item(payload, "probe")
    machine.out(
        mojo10_table(
            tree,
            tree.item(probes, "v11"),
            tree.get(probes, "v10"),
            tree.item(payload, "examples"),
        )
        + "\n"
    )
    if write_wiki_page:
        write_wiki(tree, root, payload, platform_key, catalog_count)
        machine.out("\nUpdated " + WIKI + "\n")


# --- the command line ----------------------------------------------------------

comptime _OPTION_STRINGS = [
    "-h",
    "--help",
    "--only",
    "--merge",
    "--skip-threejs",
    "--skip-webgl",
    "--skip-mojo10",
    "--write-wiki",
    "--no-write-wiki",
    "--from-results",
    "--platform",
]
comptime _OPTION_ACTIONS = [0, 0, 1, 2, 3, 4, 5, 6, 7, 8, 9]
comptime _ACTION_NAMES = [
    "-h/--help",
    "--only",
    "--merge",
    "--skip-threejs",
    "--skip-webgl",
    "--skip-mojo10",
    "--write-wiki",
    "--no-write-wiki",
    "--from-results",
    "--platform",
]


def _invocations() -> List[String]:
    """Return the `_INVOCATIONS` texts."""
    return [
        "-h, --help",
        "--only ONLY",
        "--merge",
        "--skip-threejs",
        "--skip-webgl",
        "--skip-mojo10",
        "--write-wiki",
        "--no-write-wiki",
        "--from-results",
        "--platform {linux,macos}",
    ]


def _usage_parts() -> List[String]:
    """Return the `_USAGE_PARTS` texts."""
    return [
        "[-h]",
        "[--only ONLY]",
        "[--merge]",
        "[--skip-threejs]",
        "[--skip-webgl]",
        "[--skip-mojo10]",
        "[--write-wiki]",
        "[--no-write-wiki]",
        "[--from-results]",
        "[--platform {linux,macos}]",
    ]


# Each text as `textwrap.TextWrapper._split` cuts it, with `-` breaks.
def _description_chunks() -> List[String]:
    """Return the `_DESCRIPTION_CHUNKS` texts."""
    return [
        "Time",
        " ",
        "cataloged",
        " ",
        "examples",
        " ",
        "against",
        " ",
        "three.js",
        " ",
        "and,",
        " ",
        "when",
        " ",
        "present,",
        " ",
        "Mojo",
        " ",
        "1.0.",
    ]


def _help_help() -> List[String]:
    """Return the `_HELP_HELP` texts."""
    return [
        "show",
        " ",
        "this",
        " ",
        "help",
        " ",
        "message",
        " ",
        "and",
        " ",
        "exit",
    ]


def _help_only() -> List[String]:
    """Return the `_HELP_ONLY` texts."""
    return [
        "Comma-",
        "separated",
        " ",
        "example",
        " ",
        "names",
        " ",
        "to",
        " ",
        "measure",
    ]


def _help_merge() -> List[String]:
    """Return the `_HELP_MERGE` texts."""
    return [
        "Merge",
        " ",
        "into",
        " ",
        "this",
        " ",
        "host's",
        " ",
        "existing",
        " ",
        "bench/results-<platform>.json",
    ]


def _help_threejs() -> List[String]:
    """Return the `_HELP_THREEJS` texts."""
    return [
        "Skip",
        " ",
        "the",
        " ",
        "three.js",
        " ",
        "runner",
    ]


def _help_webgl() -> List[String]:
    """Return the `_HELP_WEBGL` texts."""
    return [
        "Time",
        " ",
        "cpu-",
        "flat",
        " ",
        "only.",
        " ",
        "Use",
        " ",
        "this",
        " ",
        "when",
        " ",
        "the",
        " ",
        "host",
        " ",
        "has",
        " ",
        "no",
        " ",
        "GPU.",
    ]


def _help_mojo10() -> List[String]:
    """Return the `_HELP_MOJO10` texts."""
    return [
        "Skip",
        " ",
        "the",
        " ",
        "Mojo",
        " ",
        "1.0",
        " ",
        "comparison",
    ]


def _help_wiki() -> List[String]:
    """Return the `_HELP_WIKI` texts."""
    return [
        "Update",
        " ",
        "docs/wiki/Benchmarks.md",
        " ",
        "tables",
    ]


def _help_from() -> List[String]:
    """Return the `_HELP_FROM` texts."""
    return [
        "Rebuild",
        " ",
        "wiki",
        " ",
        "tables",
        " ",
        "from",
        " ",
        "bench/results-<platform>.json",
    ]


def _help_platform() -> List[String]:
    """Return the `_HELP_PLATFORM` texts."""
    return [
        "Which",
        " ",
        "host's",
        " ",
        "tables",
        " ",
        "--from-",
        "results",
        " ",
        "rebuilds",
        " ",
        "(default:",
        " ",
        "this",
        " ",
        "host)",
    ]


def _help_chunks(action: Int) -> List[String]:
    """Return the split help text of an action, or nothing for none."""
    if action == 0:
        return _help_help()
    if action == 1:
        return _help_only()
    if action == 2:
        return _help_merge()
    if action == 3:
        return _help_threejs()
    if action == 4:
        return _help_webgl()
    if action == 5:
        return _help_mojo10()
    if action == 6:
        return _help_wiki()
    if action == 8:
        return _help_from()
    if action == 9:
        return _help_platform()
    return List[String]()


def wrap_chunks(chunks: List[String], width: Int) -> List[String]:
    """Wrap split text as `textwrap.TextWrapper._wrap_chunks` does.

    Args:
        chunks: ASCII words and single-space chunks.
        width: The line width, one or more.

    Returns:
        The lines.
    """
    var stack = List[String]()
    for index in range(len(chunks) - 1, -1, -1):
        stack.append(chunks[index])
    var lines = List[String]()
    while len(stack) > 0:
        var line = List[String]()
        var used = 0
        if stack[len(stack) - 1] == " " and len(lines) > 0:
            _ = stack.pop()
        while len(stack) > 0:
            var size = stack[len(stack) - 1].byte_length()
            if used + size <= width:
                line.append(stack.pop())
                used += size
            else:
                break
        if len(stack) > 0 and stack[len(stack) - 1].byte_length() > width:
            var room = 1 if width < 1 else width - used
            var chunk = stack[len(stack) - 1]
            var end = room
            if chunk.byte_length() > room:
                var hyphen = String(chunk[byte = : max(room, 0)]).rfind("-")
                if hyphen > 0:
                    var other = False
                    for byte in String(chunk[byte=:hyphen]).as_bytes():
                        if byte != 45:
                            other = True
                    if other:
                        end = hyphen + 1
            line.append(String(chunk[byte = : max(end, 0)]))
            stack[len(stack) - 1] = String(chunk[byte = max(end, 0) :])
            used = 0
            for part in line:
                used += part.byte_length()
        if len(line) > 0 and String(line[len(line) - 1].strip()) == "":
            used -= line[len(line) - 1].byte_length()
            _ = line.pop()
        if len(line) > 0:
            lines.append("".join(line))
    return lines^


def _usage_lines(
    parts: List[String], indent: String, prefixed: Bool, width: Int
) -> List[String]:
    """Return `get_lines` of `argparse`'s usage wrapping."""
    var lines = List[String]()
    var line = List[String]()
    var indent_length = _chars(indent)
    var used = 6 if prefixed else indent_length - 1
    for part in parts:
        if used + 1 + _chars(part) > width and len(line) > 0:
            lines.append(indent + " ".join(line))
            line = List[String]()
            used = indent_length - 1
        line.append(part)
        used += _chars(part) + 1
    if len(line) > 0:
        lines.append(indent + " ".join(line))
    if prefixed:
        var head = String(lines[0][byte = indent.byte_length() :])
        lines[0] = head
    return lines^


def usage_text(program: String, width: Int) -> String:
    """Return the usage text, as `argparse` wraps it, with one newline.

    Args:
        program: The program name.
        width: The terminal width less two.

    Returns:
        `usage: ...` and a newline.
    """
    var prefix = "usage: "
    var parts = _usage_parts()
    var usage = program + " " + " ".join(parts)
    if _chars(prefix) + _chars(usage) <= width:
        return prefix + usage + "\n"
    var lines: List[String]
    var prog_length = _chars(program)
    if Float64(_chars(prefix) + prog_length) <= 0.75 * Float64(width):
        var indent = " " * (_chars(prefix) + prog_length + 1)
        var first: List[String] = [program]
        first.extend(parts.copy())
        lines = _usage_lines(first, indent, True, width)
    else:
        var indent = " " * _chars(prefix)
        lines = _usage_lines(parts, indent, False, width)
        lines.insert(0, program)
    return prefix + "\n".join(lines) + "\n"


def help_text(program: String, width: Int) -> String:
    """Return the `--help` text, as `argparse` formats it.

    Args:
        program: The program name.
        width: The terminal width less two.

    Returns:
        The help text.
    """
    var text = usage_text(program, width) + "\n"
    text += (
        "\n".join(wrap_chunks(_description_chunks(), max(width, 11)))
        + "\n\noptions:\n"
    )
    var max_help = min(24, max(width - 20, 4))
    var position = min(26 + 2, max_help)
    var help_width = max(width - position, 11)
    var action_width = position - 2 - 2
    var invocations = _invocations()
    for action in range(len(invocations)):
        var header = invocations[action]
        var chunks = _help_chunks(action)
        if len(chunks) == 0:
            text += "  " + header + "\n"
            continue
        var lines = wrap_chunks(chunks, help_width)
        if _chars(header) <= action_width:
            text += "  " + header + " " * (action_width - _chars(header)) + "  "
            text += lines[0] + "\n"
        else:
            text += "  " + header + "\n" + " " * position + lines[0] + "\n"
        for index in range(1, len(lines)):
            text += " " * position + lines[index] + "\n"
    return text


def columns_of(value: Optional[String]) -> Int:
    """Return the width that `shutil.get_terminal_size` reads from
    `COLUMNS`, or 0 when it gives none.

    Args:
        value: The `COLUMNS` value, or None.

    Returns:
        A positive width, or 0.
    """
    if not value:
        return 0
    var text = py_strip(value.value())
    var bytes = text.as_bytes()
    var at = 0
    var negative = False
    if len(bytes) > 0 and (bytes[0] == 43 or bytes[0] == 45):
        negative = bytes[0] == 45
        at = 1
    var number = 0
    var digits = 0
    var previous_digit = False
    while at < len(bytes):
        var byte = bytes[at]
        if byte >= 48 and byte <= 57:
            if number < 100000000:
                number = number * 10 + Int(byte) - 48
            digits += 1
            previous_digit = True
        elif byte == 95 and previous_digit and at + 1 < len(bytes):
            previous_digit = False
        else:
            return 0
        at += 1
    if digits == 0 or not previous_digit or negative or number <= 0:
        return 0
    return number


def terminal_columns() -> Int:
    """Return the width that `argparse` uses on this host.

    Returns:
        `COLUMNS` when it is a positive number, else the terminal width of
        the standard output, else 80.
    """
    var columns = columns_of(environment_value("COLUMNS"))
    if columns > 0:
        return columns
    if external_call["isatty", Int32](Int32(1)) != 1:
        return 80
    comptime if CompilationTarget.is_macos():
        try:
            var done = spawn(
                ["/bin/sh", "-c", "stty size </dev/tty"], "", List[String]()
            )
            var words = py_strip(done.stdout).split(" ")
            if done.status == 0 and len(words) == 2:
                var width = Int(String(words[1]))
                if width > 0:
                    return width
        except:
            pass
        return 80
    else:
        var size = List[UInt16](length=4, fill=0)
        var got = external_call["ioctl", Int32](
            Int32(1),
            UInt64(0x5413),
            size.unsafe_ptr().unsafe_bitcast[NoneType](),
        )
        if got == 0 and size[1] > 0:
            return Int(size[1])
        return 80


@fieldwise_init
struct _Option(Copyable, Movable):
    """An argument as `argparse._parse_optional` classifies it."""

    var kind: Int
    """0 positional, 1 an option of this parser, 2 an unknown option."""
    var action: Int
    """The action of a known option."""
    var option: String
    """The option string."""
    var sep: Int
    """-1 for no explicit argument, 0 for a joined one, 1 for `=`."""
    var explicit: String
    """The explicit argument."""


def _positional() -> _Option:
    """Return the classification of a positional argument."""
    return _Option(0, -1, String(), -1, String())


def _known(option: String) -> Int:
    """Return the action of an exact option string, or -1."""
    var strings = materialize[_OPTION_STRINGS]()
    var actions = materialize[_OPTION_ACTIONS]()
    for index in range(len(strings)):
        if strings[index] == option:
            return actions[index]
    return -1


def _negative_number(text: String) -> Bool:
    """Return whether text matches `^-\\d+$|^-\\d*\\.\\d+$`."""
    var body = text
    if body.endswith("\n"):
        var cut = String(body[byte = : body.byte_length() - 1])
        body = cut
    var bytes = body.as_bytes()
    if len(bytes) < 2 or bytes[0] != 45:
        return False
    var at = 1
    var before = 0
    while at < len(bytes) and bytes[at] >= 48 and bytes[at] <= 57:
        at += 1
        before += 1
    if at == len(bytes):
        return before > 0
    if bytes[at] != 46:
        return False
    at += 1
    var after = 0
    while at < len(bytes) and bytes[at] >= 48 and bytes[at] <= 57:
        at += 1
        after += 1
    return at == len(bytes) and after > 0


def _classify(argument: String) raises -> _Option:
    """Classify an argument as `argparse._parse_optional` does.

    Raises:
        Error: `ambiguous option: ...` for a prefix of several options.
    """
    if argument.byte_length() == 0 or not argument.startswith("-"):
        return _positional()
    var exact = _known(argument)
    if exact >= 0:
        return _Option(1, exact, argument, -1, String())
    if _chars(argument) == 1:
        return _positional()
    var equals = argument.find("=")
    if equals >= 0:
        var head = String(argument[byte=:equals])
        var action = _known(head)
        if action >= 0:
            return _Option(
                1, action, head, 1, String(argument[byte = equals + 1 :])
            )
    var matches = List[_Option]()
    var strings = materialize[_OPTION_STRINGS]()
    var actions = materialize[_OPTION_ACTIONS]()
    if argument.startswith("--"):
        var prefix = argument
        var sep = -1
        var explicit = String()
        if equals >= 0:
            prefix = String(argument[byte=:equals])
            sep = 1
            explicit = String(argument[byte = equals + 1 :])
        for index in range(len(strings)):
            if strings[index].startswith(prefix):
                matches.append(
                    _Option(1, actions[index], strings[index], sep, explicit)
                )
    else:
        var short = _first_chars(argument, 2)
        var rest = String(argument[byte = short.byte_length() :])
        for index in range(len(strings)):
            if strings[index] == short:
                matches.append(
                    _Option(1, actions[index], strings[index], 0, rest)
                )
            elif strings[index].startswith(argument):
                matches.append(
                    _Option(1, actions[index], strings[index], -1, String())
                )
    if len(matches) > 1:
        var names = List[String]()
        for found in matches:
            names.append(found.option)
        raise Error(
            "ambiguous option: " + argument + " could match " + ", ".join(names)
        )
    if len(matches) == 1:
        return matches[0].copy()
    if _negative_number(argument):
        return _positional()
    if argument.find(" ") >= 0:
        return _positional()
    return _Option(2, -1, argument, -1, String())


struct Arguments(Copyable, Movable):
    """The parsed command line, or why `argparse` stopped."""

    var help: Bool
    """True when `-h` asked for the help text."""
    var error: String
    """The `argparse` error, or empty."""
    var only: Optional[String]
    """The `--only` value."""
    var merge: Bool
    """`--merge`."""
    var skip_threejs: Bool
    """`--skip-threejs`."""
    var skip_webgl: Bool
    """`--skip-webgl`."""
    var skip_mojo10: Bool
    """`--skip-mojo10`."""
    var write_wiki: Bool
    """True unless `--no-write-wiki` came last."""
    var from_results: Bool
    """`--from-results`."""
    var platform: String
    """The `--platform` value, or this host's kind."""

    def __init__(out self):
        """Start with the parser's defaults."""
        self.help = False
        self.error = String()
        self.only = None
        self.merge = False
        self.skip_threejs = False
        self.skip_webgl = False
        self.skip_mojo10 = False
        self.write_wiki = True
        self.from_results = False
        self.platform = this_platform()


def _name(action: Int) -> String:
    """Return an action's name for an error."""
    return materialize[_ACTION_NAMES]()[action]


def _take(mut result: Arguments, action: Int, value: String) -> String:
    """Apply an action, and return an error or empty."""
    if action == 0:
        result.help = True
    elif action == 1:
        result.only = value
    elif action == 2:
        result.merge = True
    elif action == 3:
        result.skip_threejs = True
    elif action == 4:
        result.skip_webgl = True
    elif action == 5:
        result.skip_mojo10 = True
    elif action == 6:
        result.write_wiki = True
    elif action == 7:
        result.write_wiki = False
    elif action == 8:
        result.from_results = True
    else:
        if value != "linux" and value != "macos":
            return (
                "argument --platform: invalid choice: "
                + py_repr(value)
                + " (choose from 'linux', 'macos')"
            )
        result.platform = value
    return String()


def parse_arguments(arguments: List[String]) -> Arguments:
    """Parse the command line as the Python tool's `argparse` parser did.

    Args:
        arguments: The arguments, without the program name.

    Returns:
        The values, or the help request, or the error.
    """
    var result = Arguments()
    var pattern = List[UInt8]()
    var found = List[_Option]()
    var dashes = False
    for argument in arguments:
        if dashes:
            pattern.append(65)
            found.append(_positional())
        elif argument == "--":
            dashes = True
            pattern.append(45)
            found.append(_positional())
        else:
            try:
                var option = _classify(argument)
                pattern.append(UInt8(65 if option.kind == 0 else 79))
                found.append(option^)
            except error:
                result.error = String(error)
                return result^
    var extras = List[String]()
    var last_option = -1
    for index in range(len(pattern)):
        if pattern[index] == 79:
            last_option = index
    var start = 0
    while start <= last_option:
        var next_option = start
        while pattern[next_option] != 79:
            next_option += 1
        for index in range(start, next_option):
            extras.append(arguments[index])
        start = next_option
        var option = found[start].copy()
        if option.kind == 2:
            extras.append(arguments[start])
            start += 1
            continue
        var taken = List[Tuple[Int, String]]()
        var stop: Int
        var action = option.action
        var name = option.option
        var sep = option.sep
        var explicit = option.explicit
        var nargs = 1 if action == 1 or action == 9 else 0
        while True:
            if sep >= 0:
                if (
                    nargs == 0
                    and not name.startswith("--")
                    and explicit.byte_length() > 0
                ):
                    if sep == 1 or explicit.startswith("-"):
                        result.error = (
                            "argument "
                            + _name(action)
                            + ": ignored explicit argument "
                            + py_repr(explicit)
                        )
                        return result^
                    taken.append((action, String()))
                    var letter = _first_chars(explicit, 1)
                    var next_action = _known("-" + letter)
                    if next_action >= 0:
                        action = next_action
                        name = "-" + letter
                        nargs = 1 if action == 1 or action == 9 else 0
                        var tail = String(
                            explicit[byte = letter.byte_length() :]
                        )
                        explicit = tail
                        if explicit.byte_length() == 0:
                            sep = -1
                        elif explicit.startswith("="):
                            sep = 1
                            var value = String(explicit[byte=1:])
                            explicit = value
                        else:
                            sep = 0
                    else:
                        extras.append("-" + explicit)
                        stop = start + 1
                        break
                elif nargs == 1:
                    taken.append((action, explicit))
                    stop = start + 1
                    break
                else:
                    result.error = (
                        "argument "
                        + _name(action)
                        + ": ignored explicit argument "
                        + py_repr(explicit)
                    )
                    return result^
            else:
                if nargs == 1:
                    if start + 1 >= len(pattern) or pattern[start + 1] != 65:
                        result.error = (
                            "argument "
                            + _name(action)
                            + ": expected one argument"
                        )
                        return result^
                    taken.append((action, arguments[start + 1]))
                    stop = start + 2
                else:
                    taken.append((action, String()))
                    stop = start + 1
                break
        for entry in taken:
            var problem = _take(result, entry[0], entry[1])
            if problem.byte_length() > 0:
                result.error = problem
                return result^
            if result.help:
                return result^
        start = stop
    for index in range(start, len(arguments)):
        extras.append(arguments[index])
    if len(extras) > 0:
        result.error = "unrecognized arguments: " + " ".join(extras)
    return result^


# --- the run -------------------------------------------------------------------


def _load_catalog(mut tree: JsonTree, root: String) raises -> Int:
    """Read `bench/catalog.json`."""
    return _parse_json(tree, _read_text(root + "/bench/catalog.json"))


def _name_text(tree: JsonTree, item: Int) raises -> String:
    """Return an entry's name."""
    return py_str(tree, tree.item(item, "name"))


def _write_results(tree: JsonTree, path: String, node: Int) raises:
    """Write results as `json.dumps(value, indent=2) + "\\n"`."""
    Path(path).write_text(dumps(tree, node) + "\n")


def run[
    M: Machine
](
    mut machine: M,
    arguments: List[String],
    program: String,
    columns: Int,
    root: String,
) raises -> Int:
    """Run the command line.

    Parameters:
        M: The host type.

    Args:
        machine: The host.
        arguments: The arguments, without the program name.
        program: The program name for the usage line.
        columns: The terminal width that `argparse` would use.
        root: The repository root.

    Returns:
        The exit status.

    Raises:
        Error: For an unexpected failure, such as a missing catalog or a
            page without a span.
    """
    var tree = JsonTree()
    var catalog = _load_catalog(tree, root)
    var catalog_items = _list(tree, catalog)
    var catalog_count = len(catalog_items)
    var width = columns - 2
    var args = parse_arguments(arguments)
    if args.help:
        machine.out(help_text(program, width))
        return 0
    if args.error.byte_length() > 0:
        machine.err(
            usage_text(program, width)
            + program
            + ": error: "
            + args.error
            + "\n"
        )
        return 2
    var state = State(root)
    var results = results_path(root, args.platform)
    var shown = _relative(root, results)
    if args.from_results:
        if not isfile(results):
            machine.err(shown + " is missing. Run the benches first.\n")
            return 1
        var payload = _parse_json(tree, _read_text(results))
        emit_tables(
            machine,
            tree,
            root,
            payload,
            args.write_wiki,
            args.platform,
            catalog_count,
        )
        return 0
    if args.platform != this_platform():
        machine.err("--platform only applies with --from-results.\n")
        return 2
    ensure_dirs(state)
    var mojo11 = which_mojo(root + "/.venv/bin/mojo")
    if mojo11.byte_length() == 0:
        machine.err("Mojo 1.1 is missing. Create .venv/ first.\n")
        return 1
    var mojo10 = String() if args.skip_mojo10 else find_mojo10(root)
    var items = catalog_items.copy()
    if args.only and args.only.value().byte_length() > 0:
        var wanted = List[String]()
        for part in args.only.value().split(","):
            var name = py_strip(String(part))
            if name.byte_length() > 0:
                wanted.append(name)
        items = List[Int]()
        var have = List[String]()
        for item in catalog_items:
            var name_node = tree.item(item, "name")
            for name in wanted:
                if (
                    tree.kind(name_node) == STRING
                    and tree.text(name_node) == name
                ):
                    items.append(item)
                    have.append(name)
                    break
        var missing = List[String]()
        for name in wanted:
            var known = False
            for item in have:
                if item == name:
                    known = True
            if not known:
                missing.append(name)
        if len(missing) > 0:
            machine.err("unknown example: " + ", ".join(missing) + "\n")
            return 2

    var payload = tree.object()
    tree.set_text(payload, "generated_at", machine.today())
    tree.set(payload, "host", machine.host(tree, state, mojo11, mojo10))
    tree.set(payload, "examples", tree.array())
    tree.set_flag(payload, "threejs_webgl", False)
    tree.set(payload, "baselines", tree.object())
    tree.set(payload, "probe", tree.object())
    tree.set(payload, "mojo10_refused", tree.integer(0))
    tree.set(payload, "mojo10_total", tree.integer(0))

    var previous = NOTHING
    if args.merge and isfile(results):
        previous = _parse_json(tree, _read_text(results))
        if not same_measurement_host(
            tree, previous, tree.item(payload, "host")
        ):
            machine.err(
                HOST_MISMATCH + ". Keep a separate full results file.\n"
            )
            return 2

    machine.out("== baselines ==\n")
    var baselines = bench_baselines(machine, tree, state, mojo11)
    tree.set(payload, "baselines", baselines)
    machine.out(
        "  mojo noop "
        + fmt_s(_num(tree, tree.path(baselines, ["mojo", "seconds"])))
        + "s  node noop "
        + fmt_s(_num(tree, tree.path(baselines, ["node", "seconds"])))
        + "s\n"
    )

    machine.out("== probe (Mojo 1.1) ==\n")
    var probes = tree.item(payload, "probe")
    var probe11 = bench_probe(
        machine,
        tree,
        state,
        mojo11,
        root + "/bench/probe.mojo",
        state.build() + "/probe11",
    )
    tree.set(probes, "v11", probe11)
    _print_probe(machine, tree, probe11)

    if mojo10.byte_length() > 0:
        machine.out("== probe (Mojo 1.0) ==\n")
        var probe10 = bench_probe(
            machine,
            tree,
            state,
            mojo10,
            root + "/bench/mojo10/probe.mojo",
            state.build() + "/probe10",
        )
        tree.set(probes, "v10", probe10)
        _print_probe(machine, tree, probe10)
    else:
        machine.out("== probe (Mojo 1.0) skipped: compiler not installed ==\n")

    for item in items:
        var name = tree.text(tree.item(item, "name"))
        machine.out("== " + name + " ==\n")
        var binary = state.build() + "/" + name
        var dest = state.scratch() + "/" + name + ".png"
        var src = _join(root, tree.text(tree.item(item, "src")))
        var compile_result = bench_compile(
            machine, tree, state, mojo11, src, binary
        )
        machine.out(
            "  1.1 compile "
            + fmt_s(_num(tree, tree.item(compile_result, "seconds")))
            + "s\n"
        )
        var run_args = example_run_args(tree, state, item, dest)
        var run_result: Int
        if _truthy_get(tree, compile_result, "ok") and isfile(binary):
            run_result = bench_run(
                machine, tree, binary, run_args[0], run_args[1]
            )
        else:
            run_result = _failure(tree, 0)
            tree.set(run_result, "status", tree.item(compile_result, "status"))
            tree.set(run_result, "output", tree.item(compile_result, "output"))
        machine.out(
            "  1.1 run "
            + fmt_s(_num(tree, tree.item(run_result, "seconds")))
            + "s  rss "
            + fmt_mib(_num(tree, tree.item(run_result, "rss_kib")))
            + " MiB\n"
        )

        var skipped = tree.object()
        tree.set_flag(skipped, "ok", False)
        tree.set_null(skipped, "seconds")
        tree.set_null(skipped, "rss_kib")
        tree.set(skipped, "status", tree.integer(0))
        tree.set_text(skipped, "backend", "")
        tree.set_text(skipped, "output", "skipped")
        var flat = skipped
        var web = skipped
        if not args.skip_threejs:
            flat = bench_threejs(machine, tree, state, name, "cpu-flat")
            if not args.skip_webgl:
                web = bench_threejs(machine, tree, state, name, "webgl")
            if _truthy_get(tree, web, "ok"):
                tree.set_flag(payload, "threejs_webgl", True)
            var webgl_text = String("unavailable")
            if _truthy_get(tree, web, "ok"):
                webgl_text = fmt_s(_num(tree, tree.item(web, "seconds"))) + "s"
            var note = tree.get(web, "backend")
            machine.out(
                "  cpu-flat "
                + fmt_s(_num(tree, tree.item(flat, "seconds")))
                + "s  webgl "
                + webgl_text
                + "  "
                + (py_str(tree, note) if tree.truthy(note) else "cpu-flat")
                + "\n"
            )

        var mojo10_example = tree.null()
        if mojo10.byte_length() > 0:
            tree.set(
                payload,
                "mojo10_total",
                tree.integer(
                    tree.int_value(tree.item(payload, "mojo10_total")) + 1
                ),
            )
            var binary10 = state.build() + "/" + name + "10"
            var compiled10 = bench_compile(
                machine, tree, state, mojo10, src, binary10
            )
            var ran10: Int
            if _truthy_get(tree, compiled10, "ok") and isfile(binary10):
                var dest10 = state.scratch() + "/" + name + "10.png"
                var run_args10 = example_run_args(tree, state, item, dest10)
                var cwd10 = run_args10[1]
                if _truthy_get(tree, item, "hardcoded_out"):
                    cwd10 = state.scratch() + "/" + name + "10"
                    makedirs(cwd10 + "/out", exist_ok=True)
                ran10 = bench_run(machine, tree, binary10, run_args10[0], cwd10)
            else:
                tree.set(
                    payload,
                    "mojo10_refused",
                    tree.integer(
                        tree.int_value(tree.item(payload, "mojo10_refused")) + 1
                    ),
                )
                ran10 = _failure(tree, 0)
                tree.set(ran10, "status", tree.item(compiled10, "status"))
                tree.set(ran10, "output", tree.item(compiled10, "output"))
            mojo10_example = tree.object()
            tree.set(mojo10_example, "compile", compiled10)
            tree.set(mojo10_example, "run", ran10)
            machine.out(
                "  1.0 compile "
                + fmt_s(_num(tree, tree.item(compiled10, "seconds")))
                + "s  run "
                + fmt_s(_num(tree, tree.item(ran10, "seconds")))
                + "s  rss "
                + fmt_mib(_num(tree, tree.item(ran10, "rss_kib")))
                + " MiB\n"
            )

        var row = tree.object()
        tree.set_text(row, "name", name)
        tree.set(row, "measured_on", tree.item(payload, "generated_at"))
        tree.set_text(row, "measurement_date_source", "direct")
        tree.set(row, "width", tree.item(item, "width"))
        tree.set(row, "height", tree.item(item, "height"))
        tree.set(row, "frames", tree.item(item, "frames"))
        var tm = tree.object()
        tree.set(tm, "compile", compile_result)
        tree.set(tm, "run", run_result)
        tree.set(row, "threemojo", tm)
        tree.set(row, "threejs_flat", flat)
        tree.set(row, "threejs_webgl", web)
        tree.set(row, "mojo10", mojo10_example)
        tree.append(tree.item(payload, "examples"), row)
        _write_results(tree, results, slim_payload(tree, payload))

    var slim = slim_payload(tree, payload)
    if previous != NOTHING:
        slim = merge_measurements(tree, catalog, previous, slim)
    _write_results(tree, results, slim)
    machine.out("\nWrote " + shown + "\n")
    machine.out("\n")
    emit_tables(
        machine,
        tree,
        root,
        slim if args.merge else payload,
        args.write_wiki,
        args.platform,
        catalog_count,
    )
    return 0


def _print_probe[M: Machine](mut machine: M, tree: JsonTree, probe: Int) raises:
    """Print a probe's build and run times."""
    var compiled = tree.item(probe, "compile")
    var ran = tree.item(probe, "run")
    machine.out(
        "  compile "
        + fmt_s(_num(tree, tree.item(compiled, "seconds")))
        + "s  run "
        + fmt_s(_num(tree, tree.item(ran, "seconds")))
        + "s  rss "
        + fmt_mib(_num(tree, tree.item(ran, "rss_kib")))
        + " MiB\n"
    )


def python_error(text: String) -> String:
    """Return the last traceback line that Python printed for an error.

    Args:
        text: An error's text, with or without the exception name.

    Returns:
        The text with Python's exception name in front.
    """
    if text.find("Error: ") >= 0 or text.startswith("Benchmarks.md"):
        return text
    if text.find("object has no attribute") >= 0:
        return "AttributeError: " + text
    if text == "'str' object is not subscriptable":
        return "TypeError: string indices must be integers, not 'str'"
    if text.startswith("'") and text.endswith("'"):
        return "KeyError: " + text
    return "TypeError: " + text


def main() raises:
    """Run the command line from the repository root.

    Raises:
        Error: If the standard streams cannot be written.
    """
    var given = argv()
    var arguments = List[String]()
    for index in range(1, len(given)):
        arguments.append(String(given[index]))
    var program = String(PROGRAM)
    if len(given) > 0:
        var name = _basename(String(given[0]))
        if name.byte_length() > 0:
            program = name
    var machine = System()
    var status: Int
    try:
        status = run(
            machine, arguments, program, terminal_columns(), String(cwd())
        )
    except error:
        print(python_error(String(error)), file=stderr)
        status = 1
    exit(status)
