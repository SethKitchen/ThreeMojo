# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Write the lint log lines and the format-run id.

The Makefile used to call `python3 -c` for a UTC lint line, a quoted
failure command and a random format id. This program prints the same text.

    shell_log start lint-build-start: mojo build source.mojo
    shell_log command mojo build source.mojo
    shell_log uuid
"""

from std.ffi import c_int, external_call
from std.sys import argv, exit, stderr

from tools._process import shell_quote


def join_words(words: List[String]) -> String:
    """Return `words` joined as `shlex.join` joins them.

    Args:
        words: The arguments.

    Returns:
        The words separated by one space, each quoted for a shell.
    """
    var out = String()
    var first = True
    for word in words:
        if not first:
            out += " "
        first = False
        out += shell_quote(word)
    return out


def _utf8_width(lead: Int) -> Int:
    """Return the byte width of one UTF-8 code point."""
    if lead & 0x80 == 0:
        return 1
    if lead & 0xE0 == 0xC0:
        return 2
    if lead & 0xF0 == 0xE0:
        return 3
    if lead & 0xF8 == 0xF0:
        return 4
    return 1


def _code_point_count(text: String) -> Int:
    """Return the number of Unicode code points in `text`."""
    var raw = text.as_bytes()
    var index = 0
    var count = 0
    while index < len(raw):
        var width = _utf8_width(Int(raw[index]))
        if index + width > len(raw):
            width = 1
        index += width
        count += 1
    return count


def _prefix(text: String, count: Int) -> String:
    """Return the first `count` code points of `text`."""
    var raw = text.as_bytes()
    var out = List[UInt8]()
    var index = 0
    var seen = 0
    while index < len(raw) and seen < count:
        var width = _utf8_width(Int(raw[index]))
        if index + width > len(raw):
            width = 1
        var step = 0
        while step < width:
            out.append(raw[index + step])
            step += 1
        index += width
        seen += 1
    return String(from_utf8_lossy=out)


def limit_line(text: String) -> String:
    """Return `text`, cut the way the lint log cuts a long line.

    A line of 4096 code points or fewer stays whole. A longer line keeps
    its first 4084 code points and then ` [truncated]`.

    Args:
        text: The line, without its trailing newline.

    Returns:
        The line to print.
    """
    if _code_point_count(text) <= 4096:
        return text
    return _prefix(text, 4084) + " [truncated]"


def _digits(value: Int, width: Int) -> String:
    """Return `value` with leading zeros."""
    var text = String(value)
    while text.byte_length() < width:
        text = "0" + text
    return text


def utc_stamp() -> String:
    """Return the current UTC time as `YYYY-MM-DDTHH:MM:SSZ`.

    Returns:
        The time.
    """
    var now = List[Int](length=1, fill=0)
    _ = external_call["time", Int](
        OpaquePointer[MutAnyOrigin](unsafe_from_address=Int(now.unsafe_ptr()))
    )
    var fields = List[Int32](length=16, fill=0)
    _ = external_call["gmtime_r", OpaquePointer[MutAnyOrigin]](
        OpaquePointer[MutAnyOrigin](unsafe_from_address=Int(now.unsafe_ptr())),
        OpaquePointer[MutAnyOrigin](
            unsafe_from_address=Int(fields.unsafe_ptr())
        ),
    )
    return (
        _digits(Int(fields[5]) + 1900, 4)
        + "-"
        + _digits(Int(fields[4]) + 1, 2)
        + "-"
        + _digits(Int(fields[3]), 2)
        + "T"
        + _digits(Int(fields[2]), 2)
        + ":"
        + _digits(Int(fields[1]), 2)
        + ":"
        + _digits(Int(fields[0]), 2)
        + "Z"
    )


def start_line(label: String, words: List[String]) -> String:
    """Return one lint start line.

    Args:
        label: The label, such as `lint-build-start:`.
        words: The command that is about to run.

    Returns:
        The UTC time, the label and the quoted command, cut at 4096 code
        points.
    """
    return limit_line(utc_stamp() + " " + label + " " + join_words(words))


def command_line(words: List[String]) -> String:
    """Return the failure line `command: ` plus the quoted command.

    Args:
        words: The command that failed.

    Returns:
        The line, without a trailing newline.
    """
    return "command: " + join_words(words)


def _nibble(value: Int) -> String:
    """Return one hex digit."""
    var digits = "0123456789abcdef"
    var piece = List[UInt8](length=1, fill=digits.as_bytes()[value])
    return String(from_utf8_lossy=piece)


def _hex_byte(value: Int) -> String:
    """Return two hex digits."""
    return _nibble((value >> 4) & 15) + _nibble(value & 15)


def uuid4_hex() raises -> String:
    """Return a random UUID version 4 as 32 lower-case hex digits.

    Returns:
        The id, with no hyphens.

    Raises:
        Error: If the system cannot supply 16 random bytes.
    """
    var raw = List[UInt8](length=16, fill=0)
    var status = external_call["getentropy", c_int](
        OpaquePointer[MutAnyOrigin](unsafe_from_address=Int(raw.unsafe_ptr())),
        16,
    )
    if status != 0:
        raise Error("shell_log: cannot read random bytes")
    raw[6] = (raw[6] & 0x0F) | 0x40
    raw[8] = (raw[8] & 0x3F) | 0x80
    var text = String()
    for byte in raw:
        text += _hex_byte(Int(byte))
    return text


def _rest(start: Int) -> List[String]:
    """Return the command-line words from `start`."""
    var given = argv()
    var words = List[String]()
    var index = start
    while index < len(given):
        words.append(String(given[index]))
        index += 1
    return words^


def _fail(text: String):
    """Print `text` and stop with status 2."""
    print("shell_log: " + text, file=stderr)
    exit(2)


def main() raises:
    """Print a lint line or a format-run id."""
    var given = argv()
    if len(given) < 2:
        _fail("usage: shell_log start LABEL ARG... | command ARG... | uuid")
    var action = String(given[1])
    if action == "uuid":
        if len(given) != 2:
            _fail("uuid takes no arguments")
        print(uuid4_hex())
        return
    if action == "command":
        print(command_line(_rest(2)), file=stderr)
        return
    if action == "start":
        if len(given) < 3:
            _fail("start needs a label")
        print(start_line(String(given[2]), _rest(3)), flush=True)
        return
    _fail("unknown argument " + action)
