# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Write a Metal source, such as `splat.metal`, as a C string for the macOS
host.

`build.sh` used to do this with a short Python program. The header is the
same text: each source line becomes one quoted C string that ends in `\\n`.
The string is named for the file: `splat.metal` makes `SPLAT_MSL`, and
`village.metal` makes `VILLAGE_MSL`.
"""

from std.pathlib import Path
from std.sys import argv, exit, stderr

from tools._text import split_lines


def _c_escape(line: String) -> String:
    """Escape backslashes and quotes for a C string.

    Args:
        line: One source line.

    Returns:
        The escaped line.
    """
    return line.replace("\\", "\\\\").replace('"', '\\"')


def metal_header(
    source: String, file: String = "splat.metal", name: String = "SPLAT_MSL"
) -> String:
    """Return the C header for one Metal source.

    Args:
        source: The text of the Metal file.
        file: The file's name, for the comment.
        name: The name of the string that the header defines.

    Returns:
        A header that defines the string, ending in a newline.
    """
    var lines = List[String]()
    lines.append("/* Made by build.sh from " + file + ". */")
    lines.append("static const char " + name + "[] =")
    for line in split_lines(source):
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
        var parts = arguments[0].split("/")
        var file = String(parts[len(parts) - 1])
        var stem = String(file.split(".")[0])
        Path(arguments[1]).write_text(
            metal_header(source, file, stem.upper() + "_MSL")
        )
    except error:
        print("metal_string.mojo:", error, file=stderr)
        return 1
    return 0


def main() raises:
    """Write a Metal source into a C string header."""
    var arguments = List[String]()
    var given = argv()
    for index in range(1, len(given)):
        arguments.append(String(given[index]))
    exit(metal_command(arguments))
