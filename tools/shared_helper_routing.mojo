# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Check the reviewed shared-helper routing.

Four consumers keep one reviewed import. Each helper call keeps its
reviewed count. A local helper must not hide that import. A changed
import or a changed call is refused.
"""

from std.pathlib import Path

from tests._python_tokens import _tokenize


comptime _DISTANCE = "extensions/carla/curve_distance.mojo"
comptime _XML = "loaders/xml.mojo"
comptime _SKY = "extensions/carla/render_sky.mojo"
comptime _WEATHER = "extensions/carla/render_weather.mojo"
comptime _PREFIX = "reviewed shared-helper successor: "


def _fail(message: String) raises:
    """Raise a shared-helper routing error.

    Args:
        message: The failure text.

    Raises:
        Error: A routing check failed.
    """
    raise Error(_PREFIX + message)


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


def _line_count(text: String, line: String) -> Int:
    """Count exact lines equal to `line`.

    Args:
        text: The source.
        line: The expected line, without a newline.

    Returns:
        The number of matching lines.
    """
    var count = 0
    var current = String("")
    var bytes = text.as_bytes()
    var index = 0
    while index < len(bytes):
        if bytes[index] == 10:
            if current == line:
                count += 1
            current = String("")
        else:
            current += String(text[byte = index : index + 1])
        index += 1
    if current == line:
        count += 1
    return count


def _check_name(
    path: String,
    kinds: List[Int],
    texts: List[String],
    name: String,
    count: Int,
) raises:
    """Require `name` to keep its call count and stay imported.

    Args:
        path: The consumer path.
        kinds: The token kinds.
        texts: The token texts.
        name: The helper name.
        count: The reviewed call count.

    Raises:
        Error: The call count changed, or a local definition hides the import.
    """
    var calls = 0
    var index = 0
    var limit = len(kinds) - 1
    while index < limit:
        if (
            kinds[index] == 1
            and texts[index] == name
            and kinds[index + 1] == 55
            and texts[index + 1] == "("
        ):
            calls += 1
        index += 1
    if calls != count:
        _fail("live helper call count changed: " + path + ":" + name)
    index = 1
    while index < len(kinds):
        if (
            kinds[index] == 1
            and texts[index] == name
            and kinds[index - 1] == 1
            and texts[index - 1] == "def"
        ):
            _fail("local helper hides import: " + path + ":" + name)
        index += 1


def _consumer(
    root: String,
    path: String,
    import_line: String,
    first: String,
    first_count: Int,
) raises:
    """Check one consumer that imports one helper.

    Args:
        root: The repository root.
        path: The consumer path.
        import_line: The reviewed import line.
        first: The helper name.
        first_count: The reviewed call count.

    Raises:
        Error: The import or the call count changed.
    """
    var text = Path(root + "/" + path).read_text()
    var kinds = List[Int]()
    var texts = List[String]()
    if _line_count(text, import_line) != 1:
        _fail("live import changed: " + path)
    _tokenize(text, kinds, texts)
    _check_name(path, kinds, texts, first, first_count)


def shared_helper_routing(root: String) raises:
    """Require the reviewed shared-helper imports and call counts.

    Args:
        root: The repository root.

    Raises:
        Error: An import, a call count, or a local helper changed.
    """
    var base = _root(root)
    var distance = Path(base + "/" + _DISTANCE).read_text()
    if (
        _line_count(
            distance,
            "from extensions.carla.curve_interval import _next_down, _next_up",
        )
        != 1
    ):
        _fail("live import changed: " + _DISTANCE)
    var kinds = List[Int]()
    var texts = List[String]()
    _tokenize(distance, kinds, texts)
    _check_name(_DISTANCE, kinds, texts, "_next_down", 2)
    _check_name(_DISTANCE, kinds, texts, "_next_up", 2)
    _consumer(
        base, _XML, "from loaders.utf8 import append_utf8", "append_utf8", 1
    )
    _consumer(
        base, _SKY, "from render.color_math import mix_opaque", "mix_opaque", 5
    )
    _consumer(
        base,
        _WEATHER,
        "from render.color_math import mix_opaque",
        "mix_opaque",
        1,
    )


def main() raises:
    """Check the shared-helper routing of this repository.

    Raises:
        Error: A shared-helper import or call changed.
    """
    shared_helper_routing(".")
