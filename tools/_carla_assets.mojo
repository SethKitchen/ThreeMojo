# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""The CARLA asset manifest: its rules, its cache, its downloads and credits.

`tools/carla_assets.mojo` is the command line, and the export tools
(`tools/carla_export_*.mojo`) rewrite the manifest with these functions. The
manifest is a Python value tree (`tools._python_json.PyJson`): an int stays
an int, a bool stays a bool, and a dict keeps its order. It is written back
as `json.dumps(manifest, indent=2)` writes it.

An error is raised with its Python class name first, such as
`ManifestError: ` or `FetchError: `. `tools._carla_files.exception_text`
gives the part that `str(error)` gives.

A download runs `curl`. It asks for HTTP/1.1 and sends the tool's user
agent, as `urllib` does. An HTTP error and a proxy that refuses the tunnel
are final. Another failure of an `https://` download is tried again, up to
`ATTEMPTS` times in all, with a longer wait before each new try.

A zip archive is read with `tools._carla_zip`, as `zipfile` reads it.

Two rules of Python's regular expressions are kept for ASCII text only: a
release version's digits are ASCII digits, and a word character outside
ASCII is any letter or digit outside the common punctuation blocks.
"""

from std.math import isinf, isnan
from std.os.path import realpath
from std.time import sleep

from tools._carla_zip import ZipItem, open_member, read_directory, read_member
from tools._carla_files import (
    exception_text,
    os_error,
    path_is_dir,
    make_dirs,
    make_temporary,
    path_exists,
    path_is_file,
    read_file,
    remove_file,
    replace_file,
    write_file,
    write_text,
)
from tools._cli import normal_path
from tools._process import run_program
from tools._python_json import (
    MISSING,
    PY_BOOL,
    PY_DICT,
    PY_FLOAT,
    PY_INT,
    PY_LIST,
    PY_NONE,
    PY_STR,
    PyJson,
    code_points,
    is_blank,
    loads,
    py_repr,
    sorted_order,
)
from tools._python_float import parse_float
from tools._sha256 import Sha256

comptime FORMAT = 1
"""The manifest format this tool reads."""
comptime CHUNK = 1 << 16
"""The block size of a copy or a hash."""
comptime AGENT = "ThreeMojo-carla-assets/1.0"
"""The user agent of a download; some hosts refuse a tool's default one."""
comptime ATTEMPTS = 5
"""How many times in all a dropped download is tried."""
comptime BACKOFF_SECONDS = 2.0
"""The wait before the second try; each later try waits longer."""
comptime CARLA_PREFIX = "carla."
"""The id prefix of the entries converted from a CARLA release."""
comptime CARLA_AUTHOR = "CARLA Team (Computer Vision Center)"
"""The credit every CARLA entry must keep."""
comptime CARLA_RELEASE_PAGE = (
    "https://github.com/carla-simulator/carla/releases/tag/"
)
"""The start of a CARLA release page."""
comptime CC_BY = "CC-BY-4.0"
"""The CC BY 4.0 license id."""
comptime CC0 = "CC0-1.0"
"""The CC0 1.0 license id."""
comptime CC_BY_URL = "https://creativecommons.org/licenses/by/4.0/"
"""The CC BY 4.0 license page."""
comptime CC0_URL = "https://creativecommons.org/publicdomain/zero/1.0/"
"""The CC0 1.0 license page."""
comptime KINDS: List[String] = ["hdri", "model", "texture_set", "town"]
"""The entry kinds, sorted."""
comptime LICENSES: List[String] = ["CC-BY-4.0", "CC0-1.0"]
"""The licenses, sorted."""
comptime FORWARDS: List[String] = ["+x", "+z", "-x", "-z"]
"""The forward axes of a model, sorted."""
comptime ENTRY_KEYS: List[String] = [
    "author",
    "files",
    "id",
    "kind",
    "license",
    "provenance",
    "source",
]
"""The keys every entry needs, sorted."""
comptime OPTIONAL_KEYS: List[String] = [
    "changes",
    "forward",
    "tile_meters",
    "title",
]
"""The keys an entry may have, sorted."""
comptime DRIVE_DOWNLOAD = "https://drive.usercontent.google.com/download?export=download&confirm=t&id="
"""Drive's download link, before the file id."""


def default_manifest() raises -> String:
    """Return the repository's manifest, as the Python tool found it.

    The tools run from the repository root, as `tools/tool.sh` runs them.

    Returns:
        The absolute path of `assets/carla/manifest.json`.

    Raises:
        Error: If the working directory cannot be read.
    """
    return realpath(".") + "/assets/carla/manifest.json"


def default_cache() raises -> String:
    """Return the cache that git ignores.

    Returns:
        The absolute path of `.cache/carla-assets`.

    Raises:
        Error: If the working directory cannot be read.
    """
    return realpath(".") + "/.cache/carla-assets"


def _contains(items: List[String], text: String) -> Bool:
    """Return whether a list holds a string."""
    for item in items:
        if item == text:
            return True
    return False


def _list_repr(items: List[String]) -> String:
    """Return `repr` of a list of str."""
    var out = String("[")
    for index in range(len(items)):
        if index > 0:
            out += ", "
        out += py_repr(items[index])
    return out + "]"


# --- Python values -----------------------------------------------------------------


def type_name(doc: PyJson, node: Int) -> String:
    """Return `type(value).__name__`.

    Args:
        doc: The document.
        node: The value, or `MISSING` for `None`.

    Returns:
        `NoneType`, `bool`, `int`, `float`, `str`, `list` or `dict`.
    """
    var kind = doc.kind(node)
    if kind == PY_BOOL:
        return "bool"
    if kind == PY_INT:
        return "int"
    if kind == PY_FLOAT:
        return "float"
    if kind == PY_STR:
        return "str"
    if kind == PY_LIST:
        return "list"
    if kind == PY_DICT:
        return "dict"
    return "NoneType"


def value_repr(doc: PyJson, node: Int) raises -> String:
    """Return `repr(value)`.

    Args:
        doc: The document.
        node: The value, or `MISSING` for `None`.

    Returns:
        The text.

    Raises:
        Error: Never for a value read from JSON.
    """
    var kind = doc.kind(node)
    if kind == PY_STR:
        return py_repr(doc.text(node))
    if kind == PY_LIST:
        var out = String("[")
        for index in range(doc.length(node)):
            if index > 0:
                out += ", "
            out += value_repr(doc, doc.item(node, index))
        return out + "]"
    if kind == PY_DICT:
        var out = String("{")
        for index in range(doc.length(node)):
            if index > 0:
                out += ", "
            out += py_repr(doc.key(node, index)) + ": "
            out += value_repr(doc, doc.value(node, index))
        return out + "}"
    return value_str(doc, node)


def value_str(doc: PyJson, node: Int) raises -> String:
    """Return `str(value)`, as an f-string writes it.

    Args:
        doc: The document.
        node: The value, or `MISSING` for `None`.

    Returns:
        The text.

    Raises:
        Error: Never for a value read from JSON.
    """
    var kind = doc.kind(node)
    if kind == PY_NONE:
        return "None"
    if kind == PY_BOOL:
        return "True" if doc.flag(node) else "False"
    if kind == PY_STR or kind == PY_INT or kind == PY_FLOAT:
        return doc.text(node)
    return value_repr(doc, node)


def is_str(doc: PyJson, node: Int) -> Bool:
    """Return `isinstance(value, str)`.

    Args:
        doc: The document.
        node: The value.

    Returns:
        True for a str.
    """
    return doc.kind(node) == PY_STR


def is_text(doc: PyJson, node: Int, text: String) -> Bool:
    """Return `value == text` for a str `text`.

    Args:
        doc: The document.
        node: The value.
        text: The str.

    Returns:
        True when the value is that str.
    """
    return doc.kind(node) == PY_STR and doc.text(node) == text


def truthy(doc: PyJson, node: Int) -> Bool:
    """Return `bool(value)`.

    Args:
        doc: The document.
        node: The value.

    Returns:
        Python's truth value.
    """
    var kind = doc.kind(node)
    if kind == PY_NONE:
        return False
    if kind == PY_BOOL:
        return doc.flag(node)
    if kind == PY_INT:
        return doc.text(node) != "0"
    if kind == PY_FLOAT:
        return doc.number(node) != 0.0
    if kind == PY_STR:
        return doc.text(node).byte_length() > 0
    return doc.length(node) > 0


def _check_hashable(doc: PyJson, node: Int) raises:
    """Raise Python's `TypeError` for a list or a dict used as a key."""
    var kind = doc.kind(node)
    if kind == PY_LIST or kind == PY_DICT:
        raise Error(
            "TypeError: unhashable type: " + py_repr(type_name(doc, node))
        )


def in_strings(doc: PyJson, node: Int, items: List[String]) raises -> Bool:
    """Return `value in {...}` for a set of str.

    Args:
        doc: The document.
        node: The value.
        items: The set.

    Returns:
        True when the value is one of the str.

    Raises:
        Error: Python's `TypeError` for an unhashable value.
    """
    _check_hashable(doc, node)
    return doc.kind(node) == PY_STR and _contains(items, doc.text(node))


def hash_key(doc: PyJson, node: Int) raises -> String:
    """Return a key that two equal hashable values share, as a set sees them.

    Args:
        doc: The document.
        node: A hashable value.

    Returns:
        The key.

    Raises:
        Error: Python's `TypeError` for an unhashable value.
    """
    _check_hashable(doc, node)
    var kind = doc.kind(node)
    if kind == PY_STR:
        return "s" + doc.text(node)
    if kind == PY_NONE:
        return "n"
    if kind == PY_BOOL:
        return "i1" if doc.flag(node) else "i0"
    if kind == PY_INT:
        return "i" + doc.text(node)
    var number = doc.number(node)
    if (
        number == number
        and not isinf(number)
        and number == Float64(Int(number))
        and abs(number) < 9.0e15
    ):
        return "i" + String(Int(number))
    return "f" + doc.text(node)


def subscript(doc: PyJson, node: Int, key: String) raises -> Int:
    """Return `value[key]` for a str key, with Python's errors.

    Args:
        doc: The document.
        node: The value.
        key: The key.

    Returns:
        The member.

    Raises:
        Error: Python's `KeyError` or `TypeError` text.
    """
    var kind = doc.kind(node)
    if kind == PY_DICT:
        return doc.at(node, key)
    if kind == PY_STR:
        raise Error("TypeError: string indices must be integers, not 'str'")
    if kind == PY_LIST:
        raise Error(
            "TypeError: list indices must be integers or slices, not str"
        )
    raise Error(
        "TypeError: "
        + py_repr(type_name(doc, node))
        + " object is not subscriptable"
    )


def member_get(doc: PyJson, node: Int, key: String) raises -> Int:
    """Return `value.get(key)`, with Python's error for a value that is not
    a dict.

    Args:
        doc: The document.
        node: The value.
        key: The key.

    Returns:
        The member, or `MISSING`.

    Raises:
        Error: Python's `AttributeError` text for a value that is not a
            dict.
    """
    if doc.kind(node) != PY_DICT:
        raise Error(
            "AttributeError: "
            + py_repr(type_name(doc, node))
            + " object has no attribute 'get'"
        )
    return doc.get(node, key)


def _hex4(value: Int) -> String:
    """Return four lower-case hex digits."""
    comptime digits = "0123456789abcdef"
    var out = String()
    for shift in [12, 8, 4, 0]:
        var nibble = (value >> shift) & 15
        out += String(digits[byte = nibble : nibble + 1])
    return out^


def quote_json(text: String) -> String:
    """Return a str as `json.dumps` writes it with `ensure_ascii`.

    Args:
        text: The str's bytes; a lone surrogate keeps its three bytes.

    Returns:
        The quoted ASCII text.
    """
    var out = String('"')
    for point in code_points(text, False):
        if point == 0x22:
            out += '\\"'
        elif point == 0x5C:
            out += "\\\\"
        elif point == 0x0A:
            out += "\\n"
        elif point == 0x0D:
            out += "\\r"
        elif point == 0x09:
            out += "\\t"
        elif point == 0x08:
            out += "\\b"
        elif point == 0x0C:
            out += "\\f"
        elif point >= 0x20 and point <= 0x7E:
            out += chr(point)
        elif point > 0xFFFF:
            var value = point - 0x10000
            out += "\\u" + _hex4(0xD800 | (value >> 10))
            out += "\\u" + _hex4(0xDC00 | (value & 0x3FF))
        else:
            out += "\\u" + _hex4(point)
    return out + '"'


def _dump(
    doc: PyJson, node: Int, indent: Int, depth: Int, mut out: String
) raises:
    """Write one value of `dumps_indent`."""
    var kind = doc.kind(node)
    if kind == PY_NONE:
        out += "null"
    elif kind == PY_BOOL:
        out += "true" if doc.flag(node) else "false"
    elif kind == PY_INT:
        out += doc.text(node)
    elif kind == PY_FLOAT:
        var number = doc.number(node)
        if isnan(number):
            out += "NaN"
        elif isinf(number):
            out += "Infinity" if number > 0 else "-Infinity"
        else:
            out += doc.text(node)
    elif kind == PY_STR:
        out += quote_json(doc.text(node))
    else:
        var count = doc.length(node)
        var dict = kind == PY_DICT
        if count == 0:
            out += "{}" if dict else "[]"
            return
        out += "{" if dict else "["
        var inner = "\n" + String(" ") * (indent * (depth + 1))
        for index in range(count):
            if index > 0:
                out += ","
            out += inner
            if dict:
                out += quote_json(doc.key(node, index)) + ": "
                _dump(doc, doc.value(node, index), indent, depth + 1, out)
            else:
                _dump(doc, doc.item(node, index), indent, depth + 1, out)
        out += "\n" + String(" ") * (indent * depth)
        out += "}" if dict else "]"


def dumps_indent(doc: PyJson, node: Int, indent: Int) raises -> String:
    """Return `json.dumps(value, indent=indent)`.

    Args:
        doc: The document.
        node: The value.
        indent: The spaces per level; 0 still puts each item on a line.

    Returns:
        The ASCII text, with no final newline.

    Raises:
        Error: Never for a value read from JSON.
    """
    var out = String()
    _dump(doc, node, indent, 0, out)
    return out^


def read_json_text(data: List[UInt8]) raises -> PyJson:
    """Return `json.loads(data.decode('utf-8'))`.

    Args:
        data: The file's bytes.

    Returns:
        The document.

    Raises:
        Error: Python's `UnicodeDecodeError` or `JSONDecodeError` text.
    """
    if (
        len(data) >= 3
        and data[0] == 0xEF
        and data[1] == 0xBB
        and data[2] == 0xBF
    ):
        raise Error(
            "json.decoder.JSONDecodeError: Unexpected UTF-8 BOM (decode using"
            " utf-8-sig): line 1 column 1 (char 0)"
        )
    if len(data) >= 2 and (data[0] == 0 or data[1] == 0):
        # A str that holds NUL is not JSON; `loads` on bytes would read it
        # as UTF-16 or UTF-32, which a decoded str never is.
        _ = String(from_utf8=Span(data))
        raise Error(
            "json.decoder.JSONDecodeError: Expecting value: line 1 column 1"
            " (char 0)"
        )
    try:
        return loads(Span(data))
    except error:
        var text = String(error)
        if text.startswith("'utf-8' codec"):
            raise Error("UnicodeDecodeError: " + text)
        if text.startswith("RecursionError: "):
            raise error^
        raise Error("json.decoder.JSONDecodeError: " + text)


# --- Paths ----------------------------------------------------------------------------


def path_parts(path: String) -> List[String]:
    """Return `PurePosixPath(path).parts`.

    Args:
        path: A path.

    Returns:
        Its parts: the root first for an absolute path, then each name.
    """
    var parts = List[String]()
    if path.startswith("//") and not path.startswith("///"):
        parts.append("//")
    elif path.startswith("/"):
        parts.append("/")
    for piece in path.split("/"):
        var name = String(piece)
        if name != "" and name != ".":
            parts.append(name)
    return parts^


def path_text(path: String) -> String:
    """Return `str(Path(path))`.

    Args:
        path: A path.

    Returns:
        The path without empty and `.` parts, or `.`.
    """
    if path.startswith("//") and not path.startswith("///"):
        var rest = normal_path(String(path[byte=1:]))
        return "/" + rest if rest != "/" else "//"
    return normal_path(path)


def join_path(base: String, relative: String) -> String:
    """Return `str(Path(base) / relative)`.

    Args:
        base: The base path.
        relative: A path; an absolute one replaces the base.

    Returns:
        The joined path.
    """
    if relative.startswith("/"):
        return path_text(relative)
    return path_text(base + "/" + relative)


def path_name(path: String) -> String:
    """Return `Path(path).name`.

    Args:
        path: A path.

    Returns:
        The last part, or empty for a root or `.`.
    """
    var text = path_text(path)
    if text == "." or text == "/" or text == "//":
        return ""
    var cut = text.rfind("/")
    return String(text[byte = cut + 1 :]) if cut >= 0 else text


def absolute_text(path: String) raises -> String:
    """Return `str(Path(path).absolute())`.

    Args:
        path: A path.

    Returns:
        The path, after the working directory when it is relative.

    Raises:
        Error: If the working directory cannot be read.
    """
    var text = path_text(path)
    if text.startswith("/"):
        return text
    if text == ".":
        return realpath(".")
    return realpath(".") + "/" + text


# --- Text rules ------------------------------------------------------------------------


def is_word_point(point: Int) -> Bool:
    """Return whether a regular expression's `\\w` matches a code point.

    Args:
        point: The code point.

    Returns:
        True for an ASCII letter, digit or `_`, and for a letter or digit
        outside ASCII.
    """
    if point < 0x80:
        return (
            (point >= 0x30 and point <= 0x39)
            or (point >= 0x41 and point <= 0x5A)
            or (point >= 0x61 and point <= 0x7A)
            or point == 0x5F
        )
    if point <= 0xBF:
        return (
            point == 0xAA
            or point == 0xB2
            or point == 0xB3
            or point == 0xB5
            or point == 0xB9
            or point == 0xBA
            or (point >= 0xBC and point <= 0xBE)
        )
    if point == 0xD7 or point == 0xF7:
        return False
    if point >= 0x2000 and point <= 0x206F:
        return False
    if point >= 0x2190 and point <= 0x2BFF:
        return False
    if point >= 0x3000 and point <= 0x303F:
        return False
    if point >= 0xFF00 and point <= 0xFF0F:
        return False
    if point >= 0xD800 and point <= 0xDFFF:
        return False
    return not (point >= 0xFE00 and point <= 0xFE0F)


def _digits(points: List[Int], start: Int) -> Int:
    """Return the end of the ASCII digits that start at `start`."""
    var at = start
    while at < len(points) and points[at] >= 0x30 and points[at] <= 0x39:
        at += 1
    return at


def carla_release(source: String) -> Optional[String]:
    """Return the version of a CARLA release page, as
    `CARLA_RELEASE.fullmatch(source).group(1)` does.

    Args:
        source: An entry's source page.

    Returns:
        The version, such as `0.9.16`, or nothing for another page.
    """
    if not source.startswith(CARLA_RELEASE_PAGE):
        return None
    var version = String(source[byte = CARLA_RELEASE_PAGE.byte_length() :])
    var points = code_points(version, False)
    var at = 0
    for part in range(3):
        var end = _digits(points, at)
        if end == at:
            return None
        at = end
        if part < 2:
            if at >= len(points) or points[at] != 0x2E:
                return None
            at += 1
    if at != len(points):
        return None
    return version^


def names_release(provenance: String, version: String) -> Bool:
    """Return whether a note names a release, as
    `re.search(r'\\bCARLA V(?![\\w+-]|\\.\\w)', provenance)` does.

    Args:
        provenance: The entry's provenance note.
        version: The release version.

    Returns:
        True when `CARLA V` stands as a whole name in the note.
    """
    var text = code_points(provenance, False)
    var name = code_points("CARLA " + version, False)
    var last = len(text) - len(name)
    for start in range(last + 1):
        var same = True
        for index in range(len(name)):
            if text[start + index] != name[index]:
                same = False
                break
        if not same:
            continue
        if start > 0 and is_word_point(text[start - 1]):
            continue
        var after = start + len(name)
        if after < len(text):
            var next = text[after]
            if is_word_point(next) or next == 0x2B or next == 0x2D:
                continue
            if (
                next == 0x2E
                and after + 1 < len(text)
                and is_word_point(text[after + 1])
            ):
                continue
        return True
    return False


def _drive_id(points: List[Int], start: Int) -> Int:
    """Return the end of `[\\w-]+` from `start`."""
    var at = start
    while at < len(points) and (
        is_word_point(points[at]) or points[at] == 0x2D
    ):
        at += 1
    return at


def _text_of(points: List[Int], start: Int, end: Int) -> String:
    """Return code points as text."""
    var out = String()
    for index in range(start, end):
        out += chr(points[index])
    return out^


def direct_url(url: String) -> String:
    """Return the URL that downloads a file.

    A Google Drive share link, `https://drive.google.com/file/d/ID/view` or
    `https://drive.google.com/open?id=ID`, becomes Drive's download link,
    past the page Drive shows before a large file. Any other URL is
    returned as it is.

    Args:
        url: The manifest URL.

    Returns:
        The URL to download.
    """
    comptime host = "https://drive.google.com/"
    if not url.startswith(host):
        return url
    var points = code_points(String(url[byte = host.byte_length() :]), False)
    var file = code_points("file/d/", False)
    var matched = len(points) >= len(file)
    if matched:
        for index in range(len(file)):
            if points[index] != file[index]:
                matched = False
                break
    if matched:
        var end = _drive_id(points, len(file))
        if end > len(file):
            return DRIVE_DOWNLOAD + _text_of(points, len(file), end)
    var query = -1
    for word in ["open?", "uc?"]:
        var mark = code_points(word, False)
        if len(points) >= len(mark):
            var same = True
            for index in range(len(mark)):
                if points[index] != mark[index]:
                    same = False
                    break
            if same:
                query = len(mark)
    if query < 0:
        return url
    # `(?:.*&)?id=([\w-]+)`: the greedy group tries the last `&` of the
    # line first, then each earlier one, then no `&` at all.
    var line_end = query
    while line_end < len(points) and points[line_end] != 0x0A:
        line_end += 1
    var starts = List[Int]()
    var at = line_end - 1
    while at >= query:
        if points[at] == 0x26:
            starts.append(at + 1)
        at -= 1
    starts.append(query)
    for start in starts:
        if (
            start + 3 <= len(points)
            and points[start] == 0x69
            and points[start + 1] == 0x64
            and points[start + 2] == 0x3D
        ):
            var end = _drive_id(points, start + 3)
            if end > start + 3:
                return DRIVE_DOWNLOAD + _text_of(points, start + 3, end)
    return url


def binding_kind(key: String) -> String:
    """Return the kind of entry a binding key takes.

    A texture set for a surface, the ground or a facade, an HDRI for the
    sky, a town for a `town.` key, and a model for anything else.

    Args:
        key: The binding key.

    Returns:
        The kind.
    """
    if (
        key.startswith("surface.")
        or key.startswith("ground.")
        or key.startswith("facade.")
    ):
        return "texture_set"
    if key.startswith("sky."):
        return "hdri"
    if key.startswith("town."):
        return "town"
    return "model"


def is_sum(doc: PyJson, node: Int) -> Bool:
    """Return whether a value is a SHA-256 sum: 64 lower-case hex digits.

    Args:
        doc: The document.
        node: The value.

    Returns:
        True for such a str.
    """
    if doc.kind(node) != PY_STR:
        return False
    var text = doc.text(node)
    if text.byte_length() != 64:
        return False
    for byte in text.as_bytes():
        if not (
            (byte >= 0x30 and byte <= 0x39) or (byte >= 0x61 and byte <= 0x66)
        ):
            return False
    return True


def positive_float32(doc: PyJson, node: Int) -> Bool:
    """Return whether a number stays positive and finite as a Float32.

    Args:
        doc: The document.
        node: The value.

    Returns:
        True for an int or a float, not a bool, that `struct.pack('<f')`
        stores as a finite positive value.
    """
    var kind = doc.kind(node)
    var value: Float64
    if kind == PY_FLOAT:
        value = doc.number(node)
    elif kind == PY_INT:
        try:
            value = parse_float(doc.text(node))
        except:
            return False
        if isinf(value):
            # `float(int)` overflows.
            return False
    else:
        return False
    if isnan(value) or isinf(value):
        return False
    var stored = Float32(value)
    if isinf(stored):
        # `struct.pack` refuses a finite value it would round to infinity.
        return False
    return stored > 0


# --- The manifest's rules -------------------------------------------------------------


def _manifest_error(text: String) -> Error:
    """Return a `ManifestError`."""
    return Error("ManifestError: " + text)


def _check_path(doc: PyJson, node: Int, place: String) raises:
    """Refuse a cache path that is absolute or climbs out of the cache."""
    if doc.kind(node) != PY_STR or doc.text(node).byte_length() == 0:
        raise _manifest_error(place + ": a path must be a non-empty string")
    var path = doc.text(node)
    var parts = path_parts(path)
    if path.startswith("/") or _contains(parts, "..") or path.find("\\") >= 0:
        raise _manifest_error(
            place
            + ": the path "
            + py_repr(path)
            + " must stay inside the cache"
        )


def _roles_of(kind: String) -> List[String]:
    """Return the roles a kind's files may take."""
    if kind == "texture_set":
        return [
            "albedo",
            "normal",
            "roughness",
            "ao",
            "displacement",
            "archive",
        ]
    if kind == "hdri":
        return ["hdri", "archive"]
    return ["model", "support", "archive"]


def _check_file(
    doc: PyJson, entry_id: String, kind: String, item: Int, members: Bool
) raises:
    """Check one file of an entry, or one member of an archive."""
    var place = (
        entry_id + ": file " + value_repr(doc, member_get(doc, item, "path"))
    )
    var role = doc.get(item, "role")
    if not in_strings(doc, role, _roles_of(kind)) or (
        members and is_text(doc, role, "archive")
    ):
        raise _manifest_error(
            place
            + ": the role "
            + value_repr(doc, role)
            + " is not one a "
            + kind
            + " takes"
        )
    _check_path(doc, doc.get(item, "path"), place)
    if members:
        var member = doc.get(item, "member")
        if doc.kind(member) != PY_STR or doc.text(member).byte_length() == 0:
            raise _manifest_error(
                place + ": an archive member needs its name in the archive"
            )
        return
    var url = doc.get(item, "url")
    if not doc.is_none(url) and (
        doc.kind(url) != PY_STR
        or not (
            doc.text(url).startswith("https://")
            or doc.text(url).startswith("file://")
        )
    ):
        raise _manifest_error(
            place + ": the URL must be https://, file:// or null"
        )
    var digest = doc.get(item, "sha256")
    if not doc.is_none(digest) and not is_sum(doc, digest):
        raise _manifest_error(place + ": sha256 must be 64 hex digits or null")
    if doc.is_none(url) and doc.is_none(digest):
        raise _manifest_error(
            place + ": a file that is not hosted yet needs its sum"
        )
    if is_text(doc, role, "archive"):
        var extract = doc.get(item, "extract")
        if doc.kind(extract) != PY_LIST or doc.length(extract) == 0:
            raise _manifest_error(
                place + ": an archive must name the members to extract"
            )
        for index in range(doc.length(extract)):
            _check_file(doc, entry_id, kind, doc.item(extract, index), True)


def _check_carla(doc: PyJson, entry: Int, entry_id: String) raises:
    """Refuse a CARLA entry that loses its credit, release, changes or sums."""
    if not is_text(doc, doc.get(entry, "license"), CC_BY):
        raise _manifest_error(entry_id + ": a CARLA entry must be CC-BY-4.0")
    if not is_text(doc, doc.get(entry, "author"), CARLA_AUTHOR):
        raise _manifest_error(
            entry_id + ": a CARLA entry must credit " + py_repr(CARLA_AUTHOR)
        )
    var release = carla_release(doc.text(doc.get(entry, "source")))
    if not release:
        raise _manifest_error(
            entry_id
            + ": a CARLA entry needs its release page as source, "
            + "https://github.com/carla-simulator/carla/releases/tag/VERSION"
        )
    var version = release.value()
    if not names_release(doc.text(doc.get(entry, "provenance")), version):
        raise _manifest_error(
            entry_id
            + ": the provenance must name CARLA "
            + version
            + ", the release in the source"
        )
    if not truthy(doc, doc.get(entry, "changes")):
        raise _manifest_error(
            entry_id
            + ": a CARLA entry must state its changes, as CC BY 4.0 asks"
        )
    var files = doc.get(entry, "files")
    for index in range(doc.length(files)):
        var item = doc.item(files, index)
        if doc.is_none(doc.get(item, "sha256")):
            raise _manifest_error(
                entry_id
                + ": file "
                + value_repr(doc, doc.at(item, "path"))
                + " needs a pinned sha256"
            )


def _count(items: List[String], text: String) -> Int:
    """Return `items.count(text)`."""
    var count = 0
    for item in items:
        if item == text:
            count += 1
    return count


def _format_is_one(doc: PyJson, node: Int) -> Bool:
    """Return `value == 1` for a value that is not a bool."""
    var kind = doc.kind(node)
    if kind == PY_INT:
        return doc.text(node) == "1"
    if kind == PY_FLOAT:
        return doc.number(node) == 1.0
    return False


def check_manifest(doc: PyJson, manifest: Int) raises:
    """Raise a `ManifestError` unless the manifest keeps every rule.

    The rules: format 1; unique ids; a known kind and license; an author,
    a source page and a provenance note; files whose roles fit the kind,
    whose paths stay in the cache, whose URLs are https or file, and whose
    sums are 64 hex digits or null; a texture set with an albedo and a
    positive tile size; a model with one model file and a forward axis; a
    town with one model file; an HDRI with one HDRI file; a CARLA entry
    (id `carla.`) that credits the CARLA Team, names its release, states
    its changes and pins every file; and bindings that name null or an
    entry of the kind `binding_kind` gives the key.

    Args:
        doc: The document.
        manifest: The manifest value.

    Raises:
        Error: `ManifestError` text for a broken rule, or the Python error
            that the Python tool raised for a value of the wrong type.
    """
    if doc.kind(manifest) != PY_DICT or not _format_is_one(
        doc, doc.get(manifest, "format")
    ):
        raise _manifest_error(
            'the manifest must be an object with "format": ' + String(FORMAT)
        )
    var entries = doc.get(manifest, "entries")
    if doc.kind(entries) != PY_LIST:
        raise _manifest_error("the manifest needs a list of entries")
    var seen = List[String]()
    var paths = List[String]()
    var kinds = Dict[String, String]()
    for position in range(doc.length(entries)):
        var entry = doc.item(entries, position)
        if doc.kind(entry) != PY_DICT:
            raise _manifest_error("an entry must be an object")
        var id_node = doc.get(entry, "id")
        var id_text = value_str(doc, id_node)
        var missing = List[String]()
        for key in materialize[ENTRY_KEYS]():
            if doc.get(entry, key) == MISSING:
                missing.append(key)
        if len(missing) > 0:
            raise _manifest_error(id_text + ": missing " + _list_repr(missing))
        var unknown = List[String]()
        for index in range(doc.length(entry)):
            var key = doc.key(entry, index)
            if not _contains(materialize[ENTRY_KEYS](), key) and not _contains(
                materialize[OPTIONAL_KEYS](), key
            ):
                unknown.append(key)
        if len(unknown) > 0:
            var order = sorted_order(unknown)
            var sorted_keys = List[String]()
            for index in order:
                sorted_keys.append(unknown[index])
            raise _manifest_error(
                id_text + ": unknown keys " + _list_repr(sorted_keys)
            )
        if (
            doc.kind(id_node) != PY_STR
            or doc.text(id_node).byte_length() == 0
            or _contains(seen, doc.text(id_node))
        ):
            raise _manifest_error(
                value_repr(doc, id_node)
                + ": an id must be a unique non-empty string"
            )
        var entry_id = doc.text(id_node)
        seen.append(entry_id)
        var kind_node = doc.get(entry, "kind")
        if not in_strings(doc, kind_node, materialize[KINDS]()):
            raise _manifest_error(
                entry_id
                + ": the kind "
                + value_repr(doc, kind_node)
                + " is none of "
                + _list_repr(materialize[KINDS]())
            )
        var kind = doc.text(kind_node)
        if not in_strings(
            doc, doc.get(entry, "license"), materialize[LICENSES]()
        ):
            raise _manifest_error(
                entry_id
                + ": the license must be one of "
                + _list_repr(materialize[LICENSES]())
            )
        for key in ["author", "source", "provenance"]:
            var value = doc.get(entry, key)
            if doc.kind(value) != PY_STR or is_blank(doc.text(value)):
                raise _manifest_error(
                    entry_id + ": " + key + " must be a non-empty string"
                )
        var changes = doc.get(entry, "changes")
        if changes != MISSING and (
            doc.kind(changes) != PY_STR or is_blank(doc.text(changes))
        ):
            raise _manifest_error(
                entry_id + ": changes must be a non-empty string"
            )
        var files = doc.get(entry, "files")
        if doc.kind(files) != PY_LIST or doc.length(files) == 0:
            raise _manifest_error(
                entry_id + ": an entry needs at least one file"
            )
        var roles = List[String]()
        for index in range(doc.length(files)):
            var item = doc.item(files, index)
            if doc.kind(item) != PY_DICT:
                raise _manifest_error(entry_id + ": a file must be an object")
            _check_file(doc, entry_id, kind, item, False)
            var placed: List[Int] = [item]
            var extract = doc.get(item, "extract")
            if extract != MISSING:
                if doc.kind(extract) != PY_LIST:
                    raise Error(
                        'TypeError: can only concatenate list (not "'
                        + type_name(doc, extract)
                        + '") to list'
                    )
                for member in range(doc.length(extract)):
                    placed.append(doc.item(extract, member))
            for one in placed:
                var path = subscript(doc, one, "path")
                var key = hash_key(doc, path)
                if _contains(paths, key):
                    raise _manifest_error(
                        entry_id
                        + ": two files share the path "
                        + value_repr(doc, path)
                    )
                paths.append(key)
                var role = subscript(doc, one, "role")
                if not is_text(doc, role, "archive"):
                    roles.append(
                        doc.text(role) if doc.kind(role)
                        == PY_STR else String("\x00")
                    )
        if kind == "texture_set":
            if not _contains(roles, "albedo"):
                raise _manifest_error(
                    entry_id + ": a texture set needs an albedo map"
                )
            if not positive_float32(doc, doc.get(entry, "tile_meters")):
                raise _manifest_error(
                    entry_id
                    + ": a texture set needs finite positive Float32"
                    " tile_meters"
                )
        if kind == "model":
            if _count(roles, "model") != 1:
                raise _manifest_error(
                    entry_id + ": a model needs exactly one model file"
                )
            if not in_strings(
                doc, doc.get(entry, "forward"), materialize[FORWARDS]()
            ):
                raise _manifest_error(
                    entry_id
                    + ": a model needs forward, one of "
                    + _list_repr(materialize[FORWARDS]())
                )
        if kind == "town" and _count(roles, "model") != 1:
            raise _manifest_error(
                entry_id + ": a town needs exactly one model file"
            )
        if kind == "hdri" and _count(roles, "hdri") != 1:
            raise _manifest_error(
                entry_id + ": an HDRI needs exactly one HDRI file"
            )
        if entry_id.startswith(CARLA_PREFIX):
            _check_carla(doc, entry, entry_id)
        kinds[entry_id] = kind
    var bindings = doc.get(manifest, "bindings")
    if bindings == MISSING:
        return
    if doc.kind(bindings) != PY_DICT:
        raise _manifest_error("the bindings must be an object")
    for index in range(doc.length(bindings)):
        var key = doc.key(bindings, index)
        var value = doc.value(bindings, index)
        if doc.is_none(value):
            continue
        _check_hashable(doc, value)
        if doc.kind(value) != PY_STR or not _contains(seen, doc.text(value)):
            raise _manifest_error(
                "the binding "
                + py_repr(key)
                + " names "
                + value_repr(doc, value)
                + ", which is no entry"
            )
        var wanted = binding_kind(key)
        var found = kinds[doc.text(value)]
        if found != wanted:
            raise _manifest_error(
                "the binding "
                + py_repr(key)
                + " needs a "
                + wanted
                + ", and "
                + value_repr(doc, value)
                + " is a "
                + found
            )


def load_manifest(path: String) raises -> PyJson:
    """Return the manifest at `path`, checked.

    Args:
        path: The manifest file.

    Returns:
        The document; its root is the manifest.

    Raises:
        Error: An `OSError`, a decoding error or a `ManifestError`.
    """
    var doc = read_json_text(read_file(path))
    check_manifest(doc, doc.root)
    return doc^


def manifest_text(doc: PyJson, manifest: Int) raises -> String:
    """Return the text `save_manifest` writes.

    Args:
        doc: The document.
        manifest: The manifest value.

    Returns:
        `json.dumps(manifest, indent=2)` and a final newline.

    Raises:
        Error: Never for a value read from JSON.
    """
    return dumps_indent(doc, manifest, 2) + "\n"


def save_manifest(doc: PyJson, manifest: Int, path: String) raises:
    """Check the manifest and write it back, two-space indented.

    Args:
        doc: The document.
        manifest: The manifest value.
        path: The file to write.

    Raises:
        Error: A `ManifestError`, or an `OSError` from the write.
    """
    check_manifest(doc, manifest)
    write_text(path, manifest_text(doc, manifest))


# --- Credits ----------------------------------------------------------------------------


def _credit_line(doc: PyJson, entry: Int) raises -> String:
    """Return one attribution line."""
    var title_node = doc.get(entry, "title")
    var title: String
    if doc.find(entry, "title") == MISSING:
        title = value_str(doc, doc.get(entry, "id"))
    else:
        title = value_str(doc, title_node)
    var license = doc.text(doc.get(entry, "license"))
    var name = "CC BY 4.0" if license == CC_BY else "CC0 1.0"
    var link = CC_BY_URL if license == CC_BY else CC0_URL
    var text = (
        '- "'
        + title
        + '" by '
        + value_str(doc, doc.get(entry, "author"))
        + ", "
        + value_str(doc, doc.get(entry, "source"))
        + ", "
        + name
        + " ("
        + link
        + ")."
    )
    var changes = doc.get(entry, "changes")
    if truthy(doc, changes):
        text += " Changes: " + value_str(doc, changes)
    return text^


def _sorted_by_id(doc: PyJson, entries: List[Int]) -> List[Int]:
    """Return entries sorted by id, stable."""
    var ids = List[String]()
    for entry in entries:
        ids.append(doc.text(doc.get(entry, "id")))
    var out = List[Int]()
    for index in sorted_order(ids):
        out.append(entries[index])
    return out^


def credits(doc: PyJson, entries: List[Int], everything: Bool) raises -> String:
    """Return the attribution list as Markdown.

    Every CC-BY entry is listed with its title, author, source page,
    license and changes, as CC BY 4.0 asks. With `everything`, the CC0
    entries follow as a courtesy.

    Args:
        doc: The document.
        entries: The entry values, in manifest order.
        everything: True to credit the CC0 entries too.

    Returns:
        The text, with a final newline.

    Raises:
        Error: Never for a checked manifest.
    """
    var required = List[Int]()
    var free = List[Int]()
    for entry in entries:
        var license = doc.get(entry, "license")
        if is_text(doc, license, CC_BY):
            required.append(entry)
        elif is_text(doc, license, CC0):
            free.append(entry)
    var lines: List[String] = [
        "## Credits",
        "",
        (
            "This catalog lists the manifest assets, not the contents of one"
            " image."
        ),
        "Keep the applicable credits with shared renders and asset packages.",
        (
            "Rendered outputs can use the full catalog when an exact"
            " used-asset list is unavailable."
        ),
        "The asset licenses are separate from the ThreeMojo code license.",
        "",
    ]
    if len(required) > 0:
        for entry in _sorted_by_id(doc, required):
            lines.append(_credit_line(doc, entry))
    else:
        lines.append("No CC BY entry is in the manifest.")
    if everything:
        lines.append("")
        lines.append("CC0 entries, credited as a courtesy:")
        lines.append("")
        for entry in _sorted_by_id(doc, free):
            lines.append(_credit_line(doc, entry))
    return "\n".join(lines) + "\n"


def entries_of(doc: PyJson, manifest: Int) raises -> List[Int]:
    """Return a manifest's entry values.

    Args:
        doc: The document.
        manifest: The manifest value.

    Returns:
        The entries, in order.

    Raises:
        Error: Never for a checked manifest.
    """
    var entries = doc.get(manifest, "entries")
    var out = List[Int]()
    for index in range(doc.length(entries)):
        out.append(doc.item(entries, index))
    return out^


# --- The cache ---------------------------------------------------------------------------


def _fetch_error(text: String) -> Error:
    """Return a `FetchError`."""
    return Error("FetchError: " + text)


def sha256_of(path: String) raises -> String:
    """Return the SHA-256 sum of a file, as 64 lower-case hex digits.

    Args:
        path: The file.

    Returns:
        The sum.

    Raises:
        Error: An `OSError` if the file cannot be read.
    """
    var digest = Sha256()
    digest.update(Span(read_file(path)))
    return digest^.hexdigest()


def sha256_bytes(data: Span[UInt8, _]) -> String:
    """Return the SHA-256 sum of bytes.

    Args:
        data: The bytes.

    Returns:
        The sum, as 64 lower-case hex digits.
    """
    var digest = Sha256()
    digest.update(data)
    return digest^.hexdigest()


struct Transport(Copyable, Movable):
    """How a download runs: the `curl` program and the wait between tries."""

    var curl: String
    """The program, found on `PATH` when it has no slash."""
    var backoff: Float64
    """The wait before the second try, in seconds."""

    def __init__(
        out self, curl: String = "curl", backoff: Float64 = BACKOFF_SECONDS
    ):
        """Make a transport.

        Args:
            curl: The `curl` program.
            backoff: The first wait, in seconds; each later try waits longer.
        """
        self.curl = curl
        self.backoff = backoff


def _content_type(value: String) -> String:
    """Return `Message.get_content_type()` for a Content-Type value."""
    var cut = value.find(";")
    var main = String(value[byte=:cut]) if cut >= 0 else value
    var kind = String(main.strip()).lower()
    if kind.count("/") != 1:
        return "text/plain"
    return kind^


def _file_content_type(url: String) -> String:
    """Return the type `urllib` gives a `file://` URL, from its suffix."""
    var dot = url.rfind(".")
    var slash = url.rfind("/")
    if dot <= slash:
        return "text/plain"
    var suffix = String(url[byte = dot + 1 :]).lower()
    if suffix == "html" or suffix == "htm":
        return "text/html"
    return "application/octet-stream"


struct CurlAnswer(Movable):
    """What one `curl` run did, and what the last response's headers say."""

    var status: Int
    """`curl`'s exit status."""
    var problem: String
    """`curl`'s error message, without its `curl: ` prefix."""
    var tunnel: Bool
    """Whether a proxy refused the tunnel."""
    var code: Int
    """The HTTP status, or 0 without one."""
    var reason: String
    """The reason phrase."""
    var content_type: String
    """The Content-Type value, or empty."""
    var has_type: Bool
    """Whether a Content-Type header came."""

    def __init__(out self):
        """Make an answer with no status."""
        self.status = 0
        self.problem = String()
        self.tunnel = False
        self.code = 0
        self.reason = String()
        self.content_type = String()
        self.has_type = False

    def kind(self) -> String:
        """Return `response.headers.get_content_type()`.

        Returns:
            The lower-case type without parameters, or `text/plain`.
        """
        if not self.has_type:
            return "text/plain"
        return _content_type(self.content_type)


def _read_headers(text: String, mut answer: CurlAnswer):
    """Read the last response of a `curl --dump-header` file."""
    for raw in text.split("\n"):
        var line = String(String(raw).rstrip("\r"))
        if line.startswith("HTTP/"):
            answer.code = 0
            answer.reason = String()
            answer.content_type = String()
            answer.has_type = False
            var parts = line.split(" ", 2)
            if len(parts) >= 2:
                try:
                    answer.code = Int(String(parts[1]))
                except:
                    answer.code = 0
            if len(parts) >= 3:
                answer.reason = String(parts[2])
            continue
        var colon = line.find(":")
        if colon > 0:
            var name = String(line[byte=:colon]).lower()
            if name == "content-type" and not answer.has_type:
                answer.content_type = String(
                    String(line[byte = colon + 1 :]).strip()
                )
                answer.has_type = True


def curl_get(
    source: String, destination: String, transport: Transport
) raises -> CurlAnswer:
    """Run `curl` once to copy a URL's body into a file.

    It asks for HTTP/1.1, follows redirects, sends the tool's user agent and
    gives up on a connection that stays silent for 60 seconds.

    Args:
        source: The URL.
        destination: The file for the body, emptied first.
        transport: The `curl` program.

    Returns:
        What `curl` did and the last response's status and type.

    Raises:
        Error: An `OSError` if the files cannot be written.
    """
    var headers = destination + ".headers"
    write_file(destination, List[UInt8]())
    var command: List[String] = [
        transport.curl,
        "--silent",
        "--show-error",
        "--location",
        "--http1.1",
        "--user-agent",
        AGENT,
        "--connect-timeout",
        "60",
        "--speed-limit",
        "1",
        "--speed-time",
        "60",
        "--dump-header",
        headers,
        "--output",
        destination,
        "--url",
        source,
    ]
    var result = run_program(command, 86400.0, merge_errors=False)
    var answer = CurlAnswer()
    answer.status = result.status
    if path_exists(headers):
        _read_headers(String(from_utf8_lossy=read_file(headers)), answer)
        remove_file(headers)
    if result.status != 0:
        var problem = String(result.errors.strip())
        if problem.startswith("curl: "):
            var rest = String(problem[byte=6:])
            problem = rest^
        if problem.byte_length() == 0:
            problem = "curl exited with status " + String(result.status)
        answer.tunnel = problem.find("CONNECT tunnel failed") >= 0 or (
            problem.find("from proxy after CONNECT") >= 0
        )
        answer.problem = problem^
    return answer^


def _looks_like_page(data: Span[UInt8, _]) -> Bool:
    """Return whether the first bytes are a web page's, as
    `first.lstrip()[:16].lower().startswith(WEB_PAGE)` says."""
    var at = 0
    var end = min(len(data), CHUNK)
    while at < end and (
        data[at] == 0x20 or (data[at] >= 0x09 and data[at] <= 0x0D)
    ):
        at += 1
    var head = String()
    var index = at
    while index < end and index < at + 16:
        var byte = data[index]
        if byte >= 0x41 and byte <= 0x5A:
            byte += 0x20
        head += chr(Int(byte))
        index += 1
    return head.startswith("<!doctype html") or head.startswith("<html")


def _hex_value(byte: UInt8) -> Int:
    """Return a hex digit's value, or -1."""
    if byte >= 0x30 and byte <= 0x39:
        return Int(byte) - 0x30
    if byte >= 0x61 and byte <= 0x66:
        return Int(byte) - 0x61 + 10
    if byte >= 0x41 and byte <= 0x46:
        return Int(byte) - 0x41 + 10
    return -1


def file_url_path(url: String) -> Optional[String]:
    """Return the local path of a `file://` URL, as `urllib` reads it.

    Args:
        url: A URL.

    Returns:
        The path, with `%XX` escapes decoded, for a URL with no host or the
        host `localhost`; nothing for another URL.
    """
    if not url.startswith("file://"):
        return None
    var rest = String(url[byte=7:])
    var hash = rest.find("#")
    if hash >= 0:
        var head = String(rest[byte=:hash])
        rest = head^
    var query = rest.find("?")
    if query >= 0:
        var head = String(rest[byte=:query])
        rest = head^
    var path: String
    if rest.startswith("/"):
        path = rest
    elif rest.startswith("localhost/"):
        path = String(rest[byte=9:])
    else:
        return None
    var data = path.as_bytes()
    var out = List[UInt8]()
    var at = 0
    while at < len(data):
        if data[at] == 0x25 and at + 2 < len(data):
            var high = _hex_value(data[at + 1])
            var low = _hex_value(data[at + 2])
            if high >= 0 and low >= 0:
                out.append(UInt8(high * 16 + low))
                at += 3
                continue
        out.append(data[at])
        at += 1
    return String(from_utf8_lossy=out)


def _copy_local(url: String, path: String, destination: String) raises:
    """Copy a local file as `urllib` opens a `file://` URL."""
    var page = (
        url
        + ": the host sent a web page, not the file; check the file is shared "
        + "with anyone who has the link and its download quota is not used up"
    )
    var data: List[UInt8]
    try:
        if path_is_dir(path):
            raise os_error(21, path)
        data = read_file(path)
    except error:
        raise _fetch_error(
            url + ": <urlopen error " + exception_text(error) + ">"
        )
    if _file_content_type(path) == "text/html" or _looks_like_page(Span(data)):
        raise _fetch_error(page)
    write_file(destination, Span(data))


def download(url: String, destination: String, transport: Transport) raises:
    """Copy a URL's bytes into `destination`.

    A web page sent in place of the file is refused, by its content type
    or by its first bytes. A host sends one for a file it does not share,
    for a file whose download quota is used up, or for a virus-scan
    confirmation. An HTTP error and a proxy that refuses the tunnel are
    final; a dropped connection is tried again.

    Args:
        url: The URL to download; a Drive share link is made direct.
        destination: The path to write the bytes to.
        transport: The `curl` program and the wait between tries.

    Raises:
        Error: `FetchError` text if the host or proxy refuses, sends a web
            page, or the connection fails on every try.
    """
    var page = (
        url
        + ": the host sent a web page, not the file; check the file is shared "
        + "with anyone who has the link and its download quota is not used up"
    )
    var local = file_url_path(direct_url(url))
    if local:
        _copy_local(url, local.value(), destination)
        return
    var source = direct_url(url)
    var web = source.startswith("http://") or source.startswith("https://")
    for attempt in range(ATTEMPTS):
        var answer = curl_get(source, destination, transport)
        if answer.status != 0:
            if (
                attempt + 1 == ATTEMPTS
                or not url.startswith("https://")
                or answer.tunnel
            ):
                raise _fetch_error(url + ": " + answer.problem)
            sleep(transport.backoff * Float64(attempt + 1))
            continue
        if web and (answer.code < 200 or answer.code >= 300):
            # The host answered: another try gets the same answer.
            raise _fetch_error(
                url
                + ": HTTP Error "
                + String(answer.code)
                + ": "
                + answer.reason
            )
        var kind = answer.kind() if web else _file_content_type(source)
        if kind == "text/html":
            raise _fetch_error(page)
        if _looks_like_page(Span(read_file(destination))):
            raise _fetch_error(page)
        return


# --- Fetch and verify ---------------------------------------------------------------------


struct Archive(Movable):
    """An archive's bytes and its members by name, as `ZipFile` opens it."""

    var data: List[UInt8]
    """The whole archive."""
    var items: List[ZipItem]
    """Each member, in directory order."""

    def __init__(out self, path: String) raises:
        """Read an archive and its central directory.

        Args:
            path: The archive file.

        Raises:
            Error: An `OSError`, or `zipfile.BadZipFile` text.
        """
        self.data = read_file(path)
        self.items = read_directory(Span(self.data))

    def find(self, name: String) -> Int:
        """Return a member's position; a later member of the same name wins.

        Args:
            name: The member's name.

        Returns:
            Its position, or -1.
        """
        var found = -1
        for index in range(len(self.items)):
            if self.items[index].name == name:
                found = index
        return found

    def open(self, index: Int) raises:
        """Check a member's local header, as `ZipFile.open` does.

        Args:
            index: Its position.

        Raises:
            Error: `zipfile.BadZipFile` text for a damaged header.
        """
        _ = open_member(Span(self.data), self.items[index])

    def read(self, index: Int) raises -> List[UInt8]:
        """Return a member's expanded bytes.

        Args:
            index: Its position.

        Returns:
            The bytes.

        Raises:
            Error: `zipfile.BadZipFile` text for a damaged member.
        """
        return read_member(Span(self.data), self.items[index])


def _member_matches(
    archive: Archive, index: Int, target: String
) raises -> Bool:
    """Compare an extracted file with its member of a verified archive."""
    var expected = sha256_bytes(Span(archive.read(index)))
    return path_is_file(target) and sha256_of(target) == expected


def extract(doc: PyJson, archive: String, item: Int, cache: String) raises:
    """Extract an archive's named members to their paths, never over a
    file that is already there.

    Args:
        doc: The document.
        archive: The verified archive file.
        item: The archive's manifest record.
        cache: The cache root.

    Raises:
        Error: `FetchError` text for a missing member or an extracted file
            that differs from its member; an `OSError` from a write.
    """
    var bundle = Archive(archive)
    var extract_list = doc.get(item, "extract")
    for position in range(doc.length(extract_list)):
        var member = doc.item(extract_list, position)
        var target = join_path(cache, doc.text(doc.get(member, "path")))
        var name = doc.text(doc.get(member, "member"))
        var index = bundle.find(name)
        if index < 0:
            raise _fetch_error(
                value_str(doc, doc.get(item, "url"))
                + ": the archive has no member "
                + py_repr(name)
            )
        if path_exists(target):
            if not _member_matches(bundle, index, target):
                raise _fetch_error(
                    target
                    + ": extracted member differs from the verified archive; "
                    + "remove it explicitly before fetching again"
                )
            continue
        var cut = target.rfind("/")
        if cut > 0:
            make_dirs(String(target[byte=:cut]))
        var partial = target + ".part"
        # `zipfile` opens the member, then creates the partial file, then
        # copies; a damaged member leaves the partial file behind.
        bundle.open(index)
        write_file(partial, List[UInt8]())
        write_file(partial, Span(bundle.read(index)))
        replace_file(partial, target)


def fetch_file(
    mut doc: PyJson,
    item: Int,
    cache: String,
    pin: Bool,
    offline: Bool,
    transport: Transport,
) raises -> String:
    """Bring one manifest file into the cache, and return what happened.

    Returns one of "kept" (already there and matching), "fetched",
    "pinned" (fetched and its sum recorded in `item`), "unhosted" (no URL
    and not in the cache), "unpinned" (no sum and no `pin`, so not fetched)
    or "mismatch" (a cached file whose sum differs, left alone). A download
    whose sum differs raises and leaves nothing behind. Offline recovery
    also returns "missing" when a file is absent; it never downloads or
    pins bytes.

    Args:
        doc: The document; a pinned sum is written into `item`.
        item: The manifest file record.
        cache: The cache root path.
        pin: Trust and record the first bytes of an unpinned file.
        offline: Use only cached files with existing sums.
        transport: How a download runs.

    Returns:
        The status described above.

    Raises:
        Error: `FetchError` text if verification fails, or pin and offline
            are both set; an `OSError` from the cache.
    """
    if offline and pin:
        raise _fetch_error("offline recovery cannot pin files")
    var target = join_path(cache, doc.text(doc.get(item, "path")))
    var expected = doc.get(item, "sha256")
    var archive = is_text(doc, doc.get(item, "role"), "archive")
    if path_exists(target):
        var found = sha256_of(target)
        var status: String
        if doc.is_none(expected):
            if not pin:
                return "unpinned"
            doc.set(item, "sha256", doc.new_str(found))
            status = "pinned"
        elif found != doc.text(expected):
            return "mismatch"
        else:
            status = "kept"
        if archive:
            extract(doc, target, item, cache)
        return status^
    if offline:
        return "missing" if not doc.is_none(expected) else "unpinned"
    var url = doc.at(item, "url")
    if doc.is_none(url):
        return "unhosted"
    if doc.is_none(expected) and not pin:
        return "unpinned"
    var cut = target.rfind("/")
    var parent = String(target[byte=:cut]) if cut > 0 else String("/")
    make_dirs(parent)
    var partial = make_temporary(parent, path_name(target) + ".", ".part")
    var found: String
    try:
        download(doc.text(url), partial, transport)
        found = sha256_of(partial)
        if not doc.is_none(expected) and found != doc.text(expected):
            raise _fetch_error(
                doc.text(url)
                + ": sha256 "
                + found
                + " does not match "
                + doc.text(expected)
            )
        if path_exists(target):
            raise _fetch_error(
                target
                + ": appeared during the download; it was not overwritten"
            )
        replace_file(partial, target)
    finally:
        if path_exists(partial):
            remove_file(partial)
    var status = String("fetched")
    if doc.is_none(expected):
        doc.set(item, "sha256", doc.new_str(found))
        status = "pinned"
    if archive:
        extract(doc, target, item, cache)
    return status^


def selected_entries(
    doc: PyJson, manifest: Int, ids: List[String]
) raises -> List[Int]:
    """Validate every requested id before returning the selected entries.

    Args:
        doc: The document.
        manifest: The manifest value.
        ids: Entry ids to select; none selects every entry.

    Returns:
        The selected entries, in manifest order.

    Raises:
        Error: `ManifestError` text for an id that is not in the manifest.
    """
    var entries = entries_of(doc, manifest)
    var known = List[String]()
    for entry in entries:
        known.append(doc.text(doc.get(entry, "id")))
    for wanted in ids:
        if not _contains(known, wanted):
            raise _manifest_error("no entry " + py_repr(wanted))
    if len(ids) == 0:
        return entries^
    var out = List[Int]()
    for index in range(len(entries)):
        if _contains(ids, known[index]):
            out.append(entries[index])
    return out^


struct Report(Copyable, Movable):
    """One line of a fetch or verify report."""

    var entry_id: String
    """The entry, or empty in a verify report."""
    var path: String
    """The file's cache path."""
    var status: String
    """What happened."""

    def __init__(out self, entry_id: String, path: String, status: String):
        """Make a line.

        Args:
            entry_id: The entry.
            path: The file's cache path.
            status: What happened.
        """
        self.entry_id = entry_id
        self.path = path
        self.status = status


def fetch(
    mut doc: PyJson,
    manifest: Int,
    cache: String,
    ids: List[String],
    pin: Bool,
    offline: Bool,
    transport: Transport,
) raises -> List[Report]:
    """Fetch every file of the named entries, or of every entry.

    Args:
        doc: The document; pinned sums are written into it.
        manifest: A checked manifest.
        cache: The cache root path.
        ids: Entry ids to select; none selects every entry.
        pin: Trust and record the first bytes of an unpinned file.
        offline: Verify and extract cached files without opening URLs.
        transport: How a download runs.

    Returns:
        The entry, path and status of each file.

    Raises:
        Error: `ManifestError` text for an unknown id; `FetchError` text if
            verification fails, or pin and offline are both set.
    """
    if offline and pin:
        raise _fetch_error("offline recovery cannot pin files")
    var report = List[Report]()
    for entry in selected_entries(doc, manifest, ids):
        var entry_id = doc.text(doc.get(entry, "id"))
        var files = doc.get(entry, "files")
        for index in range(doc.length(files)):
            var item = doc.item(files, index)
            var path = doc.text(doc.get(item, "path"))
            var status = fetch_file(doc, item, cache, pin, offline, transport)
            report.append(Report(entry_id, path, status))
    return report^


def cached(doc: PyJson, entry: Int, cache: String) raises -> Bool:
    """Return True when every file the renderer reads of an entry is in the
    cache: each non-archive file and each archive member.

    Args:
        doc: The document.
        entry: The entry.
        cache: The cache root path.

    Returns:
        Whether the cache holds the entry.

    Raises:
        Error: Never for a checked manifest.
    """
    var files = doc.get(entry, "files")
    for index in range(doc.length(files)):
        var item = doc.item(files, index)
        var placed = List[Int]()
        if is_text(doc, doc.get(item, "role"), "archive"):
            var extract_list = doc.get(item, "extract")
            for member in range(doc.length(extract_list)):
                placed.append(doc.item(extract_list, member))
        else:
            placed.append(item)
        for one in placed:
            if not path_is_file(
                join_path(cache, doc.text(doc.get(one, "path")))
            ):
                return False
    return True


def verify(
    doc: PyJson, manifest: Int, cache: String, ids: List[String]
) raises -> List[Report]:
    """Re-hash selected cached files and compare their extracted members.

    Args:
        doc: The document.
        manifest: A checked manifest.
        cache: The cache root path.
        ids: Entry ids to select; none selects every entry.

    Returns:
        Each path with "ok", "mismatch", "missing" or "unpinned".

    Raises:
        Error: `ManifestError` text for an unknown id.
    """
    var report = List[Report]()
    for entry in selected_entries(doc, manifest, ids):
        var files = doc.get(entry, "files")
        for index in range(doc.length(files)):
            var item = doc.item(files, index)
            var path = doc.text(doc.get(item, "path"))
            var target = join_path(cache, path)
            var expected = doc.get(item, "sha256")
            if doc.is_none(expected):
                report.append(Report("", path, "unpinned"))
            elif not path_exists(target):
                report.append(Report("", path, "missing"))
            elif sha256_of(target) != doc.text(expected):
                report.append(Report("", path, "mismatch"))
            else:
                report.append(Report("", path, "ok"))
                if is_text(doc, doc.get(item, "role"), "archive"):
                    var bundle = Archive(target)
                    var extract_list = doc.get(item, "extract")
                    for member_index in range(doc.length(extract_list)):
                        var member = doc.item(extract_list, member_index)
                        var member_path = doc.text(doc.get(member, "path"))
                        var extracted = join_path(cache, member_path)
                        var name = doc.text(doc.get(member, "member"))
                        var state: String
                        if not path_exists(extracted):
                            state = "missing"
                        elif bundle.find(name) < 0:
                            state = "mismatch"
                        elif _member_matches(
                            bundle, bundle.find(name), extracted
                        ):
                            state = "ok"
                        else:
                            state = "mismatch"
                        report.append(Report("", member_path, state))
    return report^


def pad(text: String, width: Int) -> String:
    """Return `format(text, str(width))`: the text, then spaces to `width`
    characters.

    Args:
        text: The str.
        width: The least number of characters.

    Returns:
        The padded text.
    """
    var count = len(code_points(text, False))
    if count >= width:
        return text
    return text + String(" ") * (width - count)


def status_lines(
    doc: PyJson, manifest: Int, cache: String
) raises -> List[String]:
    """Return one line per entry: its id, kind, license and whether the
    cache holds it.

    Args:
        doc: The document.
        manifest: A checked manifest.
        cache: The cache root path.

    Returns:
        The lines.

    Raises:
        Error: Never for a checked manifest.
    """
    var lines = List[String]()
    for entry in entries_of(doc, manifest):
        var state = "cached" if cached(doc, entry, cache) else String(
            "missing (procedural fallback)"
        )
        lines.append(
            pad(doc.text(doc.get(entry, "id")), 40)
            + " "
            + pad(doc.text(doc.get(entry, "kind")), 12)
            + " "
            + pad(doc.text(doc.get(entry, "license")), 10)
            + " "
            + state
        )
    return lines^
