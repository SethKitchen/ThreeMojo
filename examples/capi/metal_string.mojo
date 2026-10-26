# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Write `splat.metal` as a C string for the macOS host.

`build.sh` used to do this with a short Python program. The header is the
same text: each source line becomes one quoted C string that ends in `\\n`.
"""

from std.pathlib import Path
from std.sys import stderr


def _split_lines(text: String) -> List[String]:
    """Split as Python's `str.splitlines` does for CR and LF.

    Args:
        text: The source.

    Returns:
        The lines without terminators.
    """
    var lines = List[String]()
    var current = List[UInt8]()
    var bytes = text.as_bytes()
    var index = 0
    while index < len(bytes):
        var byte = bytes[index]
        if byte == 13 or byte == 10:
            lines.append(String(from_utf8_lossy=current))
            current = List[UInt8]()
            index += 1
            if byte == 13 and index < len(bytes) and bytes[index] == 10:
                index += 1
            continue
        current.append(byte)
        index += 1
    if len(current) > 0:
        lines.append(String(from_utf8_lossy=current))
    return lines^


def _c_escape(line: String) -> String:
    """Escape backslashes and quotes for a C string.

    Args:
        line: One source line.

    Returns:
        The escaped line.
    """
    return line.replace("\\", "\\\\").replace('"', '\\"')


def metal_header(source: String) -> String:
    """Return the C header for one Metal source.

    Args:
        source: The text of `splat.metal`.

    Returns:
        A header that defines `SPLAT_MSL`, ending in a newline.
    """
    var lines = List[String]()
    lines.append("/* Made by build.sh from splat.metal. */")
    lines.append("static const char SPLAT_MSL[] =")
    for line in _split_lines(source):
        lines.append('    "' + _c_escape(line) + '\\n"')
    lines.append(";")
    return "\n".join(lines) + "\n"


def metal_command(arguments: List[String]) raises -> Int:
    """Write the header for one Metal file.

    Args:
        arguments: `IN.metal OUT.h`.

    Returns:
        The exit status.

    Raises:
        Error: Never. A failure is an exit status.
    """
    if len(arguments) != 2:
        print(
            "tools/capi_metal_string.mojo IN.metal OUT.h",
            file=stderr,
        )
        return 1
    try:
        var source = Path(arguments[0]).read_text()
        Path(arguments[1]).write_text(metal_header(source))
    except error:
        print("metal_string.mojo:", error, file=stderr)
        return 1
    return 0
