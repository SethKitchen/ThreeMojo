# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Check the reviewed seed-count premises.

Forty-five declarations keep their score-era token digests. Map premises
use the later guard digests. Road info premises come from the restored
border pin. A changed premise is refused.
"""

from std.pathlib import Path

from tests._border_pin_predecessor import _apply, _edits_24
from tests._python_tokens import token_sha256
from tools._python_json import loads
from tools._sha256 import sha256_hex


comptime _RECORD = "tools/carla_lane_oracle/seed-count-successor.json"
comptime _RECORD_SHA = (
    "fe8f0b4bba9ddc037113340e06f223d1ee4ed0b8ec4d67752d4e39ea946be271"
)
comptime _MAP = "extensions/carla/map.mojo"
comptime _ROAD_INFO = "extensions/carla/road_info.mojo"
comptime _ROAD_INFO_LIVE = (
    "3ae47c8a824902138a5921015ad78928d9e1db3cafc66c4df2929023950d9bb8"
)
comptime _ROAD_INFO_PIN = (
    "60460851e8884dd89271357a07fa8e127979d68a43c7f4e5962907d1634e12cb"
)
comptime _ROOM = (
    "6fe8fb2c7802c06ac92466ad1903bb8146548c91f014b3ec4d33b754c1916908"
)
comptime _DOMAIN = (
    "2dac22303e098b801af08b9abfab282dae48a6895c3ef5754a27ddee83871d1e"
)
comptime _CALLER = (
    "530591a025e3ab9a31870ed03f0b79d871e8a96c958eb688aa31d047b0143e40"
)
comptime _RECORD_CHANGED = (
    "reviewed seed-count successor: immutable successor record changed"
)
comptime _PREMISE = (
    "reviewed seed-count successor: live theorem premise changed: "
)


def _fail(message: String) raises:
    """Raise a seed-count premise error.

    Args:
        message: The failure text.

    Raises:
        Error: A premise check failed.
    """
    raise Error(message)


def _root(root: String) -> String:
    """Return `root` without a trailing slash.

    Args:
        root: The repository root.

    Returns:
        The root used to join paths.
    """
    if root.byte_length() > 1 and root.endswith("/"):
        var end = root.byte_length() - 1
        return String(root[byte=0:end])
    return root


def _line_starts(text: String) -> List[Int]:
    """Return the byte index of each line.

    Args:
        text: The source.

    Returns:
        The line starts, including zero.
    """
    var starts = List[Int]()
    starts.append(0)
    var bytes = text.as_bytes()
    var index = 0
    while index < len(bytes):
        if bytes[index] == 10 and index + 1 < len(bytes):
            starts.append(index + 1)
        index += 1
    return starts^


def _indent(text: String, at: Int) -> Int:
    """Return the number of leading spaces on the line at `at`.

    Args:
        text: The source.
        at: A line start.

    Returns:
        The space count.
    """
    var bytes = text.as_bytes()
    var index = at
    var count = 0
    while index < len(bytes) and bytes[index] == 32:
        count += 1
        index += 1
    return count


def _starts_with(text: String, at: Int, prefix: String) -> Bool:
    """Return whether `text` has `prefix` at byte `at`.

    Args:
        text: The source.
        at: The byte index.
        prefix: The expected text.

    Returns:
        True when the prefix is present.
    """
    var end = at + prefix.byte_length()
    if end > text.byte_length():
        return False
    return String(text[byte=at:end]) == prefix


def _boundary(text: String, at: Int, indent: Int) -> Bool:
    """Return whether a line ends a declaration.

    Args:
        text: The source.
        at: A line start.
        indent: The declaration indent.

    Returns:
        True for `def`, `struct`, or `@` at `indent` or less.
    """
    if _indent(text, at) > indent:
        return False
    var body = at + _indent(text, at)
    if _starts_with(text, body, "def "):
        return True
    if _starts_with(text, body, "struct "):
        return True
    return _starts_with(text, body, "@")


def _content_end(text: String, at: Int, stop: Int) -> Int:
    """Return `stop` without a trailing newline.

    Args:
        text: The source.
        at: The line start.
        stop: The exclusive end, including a newline when present.

    Returns:
        The exclusive end of the line content.
    """
    if stop > at and text.as_bytes()[stop - 1] == 10:
        return stop - 1
    return stop


def _dedent(text: String) -> String:
    """Remove the common leading indent, as `textwrap.dedent` does.

    Args:
        text: The declaration slice.

    Returns:
        The slice with the common space indent removed.
    """
    var starts = _line_starts(text)
    var size = text.byte_length()
    var margin = -1
    var index = 0
    while index < len(starts):
        var at = starts[index]
        var stop = size
        if index + 1 < len(starts):
            stop = starts[index + 1]
        stop = _content_end(text, at, stop)
        var cursor = at
        var spaces = 0
        var blank = True
        var raw = text.as_bytes()
        while cursor < stop:
            if raw[cursor] != 32 and raw[cursor] != 9:
                blank = False
                break
            spaces += 1
            cursor += 1
        if not blank and (margin < 0 or spaces < margin):
            margin = spaces
        index += 1
    if margin < 0:
        margin = 0
    var out = String("")
    index = 0
    while index < len(starts):
        var at = starts[index]
        var stop = size
        var newline = False
        if index + 1 < len(starts):
            stop = starts[index + 1]
            newline = True
        elif size > 0 and text.as_bytes()[size - 1] == 10:
            newline = True
        var content = _content_end(text, at, stop)
        var cursor = at
        var blank = True
        var raw = text.as_bytes()
        while cursor < content:
            if raw[cursor] != 32 and raw[cursor] != 9:
                blank = False
                break
            cursor += 1
        if not blank:
            var begin = at + margin
            if begin > content:
                begin = content
            out += String(text[byte=begin:content])
        if newline:
            out += "\n"
        index += 1
    return out


def _is_definition(text: String, at: Int, name: String) -> Bool:
    """Return whether a line body declares `name`.

    Args:
        text: The source.
        at: The first byte after the indent.
        name: The function name.

    Returns:
        True for `def name(` and `def name[`.
    """
    var prefix = "def " + name
    if not _starts_with(text, at, prefix):
        return False
    var next = at + prefix.byte_length()
    var bytes = text.as_bytes()
    if next >= len(bytes):
        return False
    return bytes[next] == 40 or bytes[next] == 91


def _declaration(
    text: String, name: String, owner: String, label: String
) raises -> String:
    """Return one declaration named `name`.

    Args:
        text: The module source.
        name: The function name.
        owner: The struct name, or empty for a top-level function.
        label: The premise label used in a refusal.

    Returns:
        The declaration through the following declaration.

    Raises:
        Error: The declaration is missing or repeated.
    """
    var starts = _line_starts(text)
    var region_start = 0
    var region_stop = len(starts)
    if owner != "":
        var struct_at = -1
        var index = 0
        while index < len(starts):
            if _indent(text, starts[index]) == 0 and _starts_with(
                text, starts[index], "struct " + owner
            ):
                struct_at = index
                break
            index += 1
        if struct_at < 0:
            _fail(_PREMISE + label)
        region_start = struct_at + 1
        index = region_start
        while index < len(starts):
            if _indent(text, starts[index]) == 0 and _boundary(
                text, starts[index], 0
            ):
                region_stop = index
                break
            index += 1
    var found = -1
    var count = 0
    var method_indent = 0
    var index = region_start
    while index < region_stop:
        var at = starts[index]
        var indent = _indent(text, at)
        var body = at + indent
        var top_level = owner == "" and indent == 0
        var method = owner != "" and indent > 0
        if (top_level or method) and _is_definition(text, body, name):
            count += 1
            found = index
            method_indent = indent
        index += 1
    if count != 1 or found < 0:
        _fail(_PREMISE + label)
    var start = starts[found]
    var previous = found
    while previous > region_start:
        previous -= 1
        var at = starts[previous]
        var indent = _indent(text, at)
        var body = at + indent
        if indent == method_indent and _starts_with(text, body, "@"):
            start = at
        else:
            break
    var stop = text.byte_length()
    index = found + 1
    while index < len(starts):
        if _boundary(text, starts[index], method_indent):
            stop = starts[index]
            break
        index += 1
    return _dedent(String(text[byte=start:stop]))


def _road_info(text: String) raises -> String:
    """Return the reviewed road-info border pin.

    Args:
        text: The live road-info module.

    Returns:
        The module with the reviewed line edits removed.

    Raises:
        Error: The live file or the restored pin changed.
    """
    if sha256_hex(text.as_bytes()) != _ROAD_INFO_LIVE:
        _fail(
            "reviewed border parser successor: border pin changed: "
            + _ROAD_INFO
        )
    var starts = List[Int]()
    var stops = List[Int]()
    var befores = List[String]()
    _edits_24(starts, stops, befores)
    var restored = _apply(text, starts, stops, befores)
    if sha256_hex(restored.as_bytes()) != _ROAD_INFO_PIN:
        _fail(
            "reviewed border parser successor: border pin changed: "
            + _ROAD_INFO
        )
    return restored


def _expected(
    path: String, name: String, owner: String, after: String
) -> String:
    """Return the score-era token digest for one premise.

    Args:
        path: The module path.
        name: The function name.
        owner: The struct name, or empty.
        after: The record's after digest.

    Returns:
        The digest required for the live score-era source.
    """
    if path != _MAP or owner != "":
        return after
    if name == "_winner_seed_room":
        return _ROOM
    if name == "_seed_reference_domain":
        return _DOMAIN
    if name == "_try_winner_seed":
        return _CALLER
    return after


def seed_count_premises(root: String) raises:
    """Require the reviewed seed-count premise digests.

    Args:
        root: The repository root.

    Raises:
        Error: The record or a premise declaration changed.
    """
    var base = _root(root)
    var raw = Path(base + "/" + _RECORD).read_bytes()
    if sha256_hex(raw) != _RECORD_SHA:
        _fail(_RECORD_CHANGED)
    var doc = loads(raw)
    var items = doc.at(doc.root, "premise_declarations")
    var road_info = ""
    var index = 0
    var count = doc.length(items)
    while index < count:
        var item = doc.item(items, index)
        var path = doc.text(doc.at(item, "path"))
        var name = doc.text(doc.at(item, "name"))
        var owner_node = doc.at(item, "owner")
        var owner = ""
        if doc.length(owner_node) == 1:
            owner = doc.text(doc.item(owner_node, 0))
        var label = path + ":" + name
        if owner != "":
            label = path + ":" + owner + "." + name
        var source = Path(base + "/" + path).read_text()
        if path == _ROAD_INFO:
            if road_info == "":
                road_info = _road_info(source)
            source = road_info
        var after = doc.text(doc.at(item, "after_token_sha256"))
        var expected = _expected(path, name, owner, after)
        var actual = token_sha256(_declaration(source, name, owner, label))
        if actual != expected:
            _fail(_PREMISE + label)
        index += 1
    if count != 45:
        _fail(_RECORD_CHANGED)


def main() raises:
    """Check the seed-count premises of this repository.

    Raises:
        Error: A premise declaration changed.
    """
    seed_count_premises(".")
