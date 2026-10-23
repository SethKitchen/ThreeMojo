# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Retarget the LLVM IR that Mojo writes for the host to wasm32.

Mojo 1.2 has no WebAssembly backend, but `mojo build --emit llvm` writes
plain LLVM IR. This program swaps the module's data layout and triple for
those of wasm32 and drops the host CPU attributes, so that a stock clang can
compile the module. Use it like this:

    retarget.mojo CLANG IN.ll OUT.ll

The module must not use threads, lists, strings or errors, because `mwrt.c`
does not supply the runtime they need. The rewrites match the former Python
script, including a data layout that itself contains a quote.
"""

from std.pathlib import Path
from std.sys import argv, exit, stderr

from tools._process import run_program

comptime TRIPLE = "wasm32-unknown-unknown"
"""The triple clang and wasm-ld expect."""

comptime USAGE = (
    "Retarget the LLVM IR that Mojo writes for the host to wasm32.\n"
    "\n"
    "    retarget.mojo CLANG IN.ll OUT.ll\n"
    "\n"
    "The module must not use threads, lists, strings or errors, because\n"
    "mwrt.c does not supply the runtime they need."
)
"""The text the tool prints when the command line is wrong."""


def _ends_with_newline(text: String) -> Bool:
    """Return whether `text` ends in a newline."""
    var bytes = text.as_bytes()
    return len(bytes) > 0 and bytes[len(bytes) - 1] == 10


def _split_lines(text: String) -> List[String]:
    """Split on newlines the way Python's `str.splitlines` does for `\\n`.

    Args:
        text: The text.

    Returns:
        The lines, without their terminators. A final newline does not add
        an empty line. Two newlines in a row do.
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


def _join_lines(original: String, lines: List[String]) -> String:
    """Join lines with newlines and keep a trailing newline of `original`.

    Args:
        original: The text before the rewrite.
        lines: The rewritten lines. A line may itself contain a newline.

    Returns:
        The joined text.
    """
    var joined = "\n".join(lines)
    if not _ends_with_newline(original):
        return joined
    if joined.byte_length() == 0:
        return "\n"
    return joined + "\n"


def _replace_layout(line: String, layout: String) -> String:
    """Replace one `target datalayout` line."""
    var prefix = 'target datalayout = "'
    if line.startswith(prefix) and line.endswith('"'):
        return prefix + layout + '"'
    return line


def _replace_triple(line: String) -> String:
    """Replace one `target triple` line."""
    var prefix = 'target triple = "'
    if line.startswith(prefix) and line.endswith('"'):
        return prefix + TRIPLE + '"'
    return line


def _strip_attribute(text: String, key: String) -> String:
    """Remove `"key"="..."` and the whitespace after it.

    Args:
        text: The module.
        key: `target-cpu` or `target-features`.

    Returns:
        The module without those attributes. Whitespace after an attribute
        includes newlines, as Python's `\\s` does.
    """
    var needle = '"' + key + '"="'
    var result = String()
    var rest = text
    while True:
        var at = rest.find(needle)
        if at < 0:
            return result + rest
        result += String(rest[byte=:at])
        var bytes = rest.as_bytes()
        var end = at + needle.byte_length()
        while end < len(bytes) and bytes[end] != 34:
            end += 1
        if end >= len(bytes):
            return result + String(rest[byte=at:])
        end += 1
        while end < len(bytes):
            var byte = bytes[end]
            if (
                byte == 9
                or byte == 10
                or byte == 11
                or byte == 12
                or byte == 13
                or byte == 32
            ):
                end += 1
            else:
                break
        var next = String(rest[byte=end:])
        rest = next


def _name_byte(byte: UInt8) -> Bool:
    """Return whether a byte can appear in an LLVM local name after `%`."""
    return (
        (byte >= 48 and byte <= 57)
        or (byte >= 65 and byte <= 90)
        or (byte >= 97 and byte <= 122)
        or byte == 95
        or byte == 46
    )


def _retarget_alloca(line: String) -> String:
    """Widen one optional-pointer slot from a pointer to 8 cleared bytes.

    Args:
        line: One line of IR.

    Returns:
        Two lines when the line allocates a nested `{ ptr }` slot aligned
        to 8. Otherwise the same line.
    """
    var bytes = line.as_bytes()
    var index = 0
    while index < len(bytes) and (bytes[index] == 32 or bytes[index] == 9):
        index += 1
    if index >= len(bytes) or bytes[index] != 37:
        return line
    var name_end = index + 1
    while name_end < len(bytes) and _name_byte(bytes[name_end]):
        name_end += 1
    if name_end == index + 1:
        return line
    var marker = " = alloca "
    var tail = String(line[byte=name_end:])
    if not tail.startswith(marker):
        return line
    var body = String(tail[byte = marker.byte_length() :])
    var groups = 0
    while body.startswith("{ "):
        groups += 1
        var opened = String(body[byte=2:])
        body = opened
    if groups == 0 or not body.startswith("ptr"):
        return line
    var after_ptr = String(body[byte=3:])
    body = after_ptr
    var closes = 0
    while body.startswith(" }"):
        closes += 1
        var closed = String(body[byte=2:])
        body = closed
    if closes == 0 or body != ", align 8":
        return line
    var indent = String(line[byte=:index])
    var name = String(line[byte=index:name_end])
    return (
        indent
        + name
        + " = alloca i64, align 8\n"
        + indent
        + "store i64 0, ptr "
        + name
        + ", align 8"
    )


def _fill_empty_attributes(line: String) -> String:
    """Give an empty attribute group `nounwind`, which LLVM accepts.

    Args:
        line: One line of IR.

    Returns:
        The line, with ` nounwind` inserted when the braces hold only space.
    """
    var prefix = "attributes #"
    if not line.startswith(prefix):
        return line
    var bytes = line.as_bytes()
    var index = prefix.byte_length()
    if index >= len(bytes) or bytes[index] < 48 or bytes[index] > 57:
        return line
    while index < len(bytes) and bytes[index] >= 48 and bytes[index] <= 57:
        index += 1
    var mid = " = {"
    if not String(line[byte=index:]).startswith(mid):
        return line
    index += mid.byte_length()
    if len(bytes) == 0 or bytes[len(bytes) - 1] != 125:
        return line
    var cursor = index
    var end = len(bytes) - 1
    while cursor < end:
        var byte = bytes[cursor]
        if not (
            byte == 9
            or byte == 10
            or byte == 11
            or byte == 12
            or byte == 13
            or byte == 32
        ):
            return line
        cursor += 1
    return String(line[byte=:index]) + " nounwind }"


def retarget_ir(text: String, layout: String) raises -> String:
    """Return the IR of `text` for wasm32.

    Args:
        text: Host LLVM IR.
        layout: The wasm32 data layout from clang.

    Returns:
        The retargeted IR.

    Raises:
        Error: Never. The rewrites do not fail.
    """
    var lines = _split_lines(text)
    var laid = List[String]()
    for line in lines:
        laid.append(_replace_layout(line, layout))
    var current = _join_lines(text, laid)
    lines = _split_lines(current)
    var tripled = List[String]()
    for line in lines:
        tripled.append(_replace_triple(line))
    current = _join_lines(current, tripled)
    current = _strip_attribute(current, "target-cpu")
    current = _strip_attribute(current, "target-features")
    lines = _split_lines(current)
    var slots = List[String]()
    for line in lines:
        slots.append(_retarget_alloca(line))
    current = _join_lines(current, slots)
    lines = _split_lines(current)
    var groups = List[String]()
    for line in lines:
        groups.append(_fill_empty_attributes(line))
    return _join_lines(current, groups)


def wasm_layout(clang: String) raises -> String:
    """Ask clang for the data layout of wasm32.

    Args:
        clang: The clang executable.

    Returns:
        The data layout string, without quotes.

    Raises:
        Error: If clang fails or prints no data layout.
    """
    var result = run_program(
        [
            clang,
            "--target=" + TRIPLE,
            "-S",
            "-emit-llvm",
            "-x",
            "c",
            "/dev/null",
            "-o",
            "-",
        ],
        30.0,
        merge_errors=False,
    )
    if result.status != 0:
        var detail = (
            result.errors if result.errors.byte_length() > 0 else result.output
        )
        raise Error("clang failed: " + detail)
    var marker = 'target datalayout = "'
    for line in _split_lines(result.output):
        if line.startswith(marker) and line.endswith('"'):
            var end = line.byte_length() - 1
            return String(line[byte = marker.byte_length() : end])
    raise Error("clang printed no data layout for " + TRIPLE)


def retarget_command(arguments: List[String]) raises -> Int:
    """Retarget one IR file.

    Args:
        arguments: `CLANG IN.ll OUT.ll`.

    Returns:
        The exit status.

    Raises:
        Error: Never. A failure is an exit status.
    """
    if len(arguments) != 3:
        print(USAGE, file=stderr)
        return 1
    try:
        var text = Path(arguments[1]).read_text()
        var layout = wasm_layout(arguments[0])
        Path(arguments[2]).write_text(retarget_ir(text, layout))
    except error:
        print("retarget.mojo:", error, file=stderr)
        return 1
    return 0


def main() raises:
    """Retarget one LLVM IR file from the command line."""
    var arguments = List[String]()
    var given = argv()
    for index in range(1, len(given)):
        arguments.append(String(given[index]))
    exit(retarget_command(arguments))
