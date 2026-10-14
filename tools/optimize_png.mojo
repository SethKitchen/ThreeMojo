# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Losslessly compress PNG and APNG files in place.

    mojo run -I . tools/optimize_png.mojo out/example.png [more.png ...]

The tool changes the DEFLATE encoding only; see `render.png_optimize`. It
replaces a file only when the new file is smaller. It writes the new bytes
to a temporary file in the same directory, gives it the mode of the old
file, and renames it over the old file. So a failure cannot leave a
partly written image. It prints one line per file: the path and the size
before and after.
"""

from std.ffi import c_int, external_call
from std.os import remove, stat
from std.pathlib import Path
from std.sys import argv

from render.png_optimize import optimize


def _check(result: c_int, action: String, path: String) raises:
    """Raise when a C library call failed."""
    if result != 0:
        raise Error(action + " failed: " + path)


def optimize_file(path: String) raises -> Tuple[Int, Int]:
    """Replace a PNG with its recompressed form when that is smaller.

    Args:
        path: The PNG or APNG file.

    Returns:
        The size before and the size after, in bytes.

    Raises:
        Error: If the file is not a valid PNG, or a file operation fails.
    """
    var before = Path(path).read_bytes()
    var after = optimize(before)
    if len(after) < len(before):
        var pid = external_call["getpid", c_int]()
        var temporary = path + ".optimize-" + String(pid)
        try:
            Path(temporary).write_bytes(Span(after))
            var mode = UInt32(stat(Path(path)).st_mode & 0o7777)
            # C strings need a terminating NUL, which these copies get.
            var source = temporary
            var target = path
            _check(
                external_call["chmod", c_int](
                    source.as_c_string_span().ptr(), mode
                ),
                "chmod",
                temporary,
            )
            _check(
                external_call["rename", c_int](
                    source.as_c_string_span().ptr(),
                    target.as_c_string_span().ptr(),
                ),
                "rename",
                temporary,
            )
        finally:
            if Path(temporary).exists():
                remove(Path(temporary))
    return (len(before), len(after))


def main() raises:
    var args = argv()
    if len(args) < 2:
        raise Error("usage: optimize_png.mojo PATH [PATH ...]")
    for i in range(1, len(args)):
        var path = String(args[i])
        var sizes = optimize_file(path)
        print(
            path
            + ": "
            + String(sizes[0])
            + " -> "
            + String(sizes[1])
            + " bytes"
        )
