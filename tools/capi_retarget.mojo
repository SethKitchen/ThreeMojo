# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Retarget the LLVM IR that Mojo writes for the host to wasm32.

Mojo 1.2 has no WebAssembly backend, but `mojo build --emit llvm` writes
plain LLVM IR. This program swaps the module's data layout and triple for
those of wasm32 and drops the host CPU attributes, so that a stock clang can
compile the module. `build.sh` runs it:

    tools/capi_retarget.mojo CLANG IN.ll OUT.ll

The module must not use threads, lists, strings or errors, because `mwrt.c`
does not supply the runtime they need. The rewrites match the former Python
script, including a data layout that itself contains a quote.

Mojo's LLVM is newer than any release of clang, and writes floating-point
constants in ways that an older reader refuses: a decimal that is not exactly a
float, such as `1.000000e-03`, which it rounds to the nearest float; a float's
or a double's own bits, such as `f0x3F3504F3`; infinities and quiet NaNs as
`+inf`, `-inf`, `+qnan` and `-qnan`; and a NaN with a payload as
`+nan(0x...)`, or `+snan(0x...)` for a signaling one. This program writes each
of them as the hexadecimal double of that number, which every LLVM reads as the
same number.

The IR is written for the host, so the standard library's UTF-8 check can call
an x86 byte shuffle, `llvm.x86.ssse3.pshuf.b.128`. The program gives the module
a function that does the same with WebAssembly's swizzle: a byte whose top bit
is set gives zero, and any other byte picks by its low four bits.
"""

from std.memory import bitcast
from std.pathlib import Path
from std.sys import argv, exit, stderr

from tools._process import run_program

comptime TRIPLE = "wasm32-unknown-unknown"
"""The triple clang and wasm-ld expect."""

comptime USAGE = (
    "Retarget the LLVM IR that Mojo writes for the host to wasm32.\n"
    "\n"
    "    tools/capi_retarget.mojo CLANG IN.ll OUT.ll\n"
    "\n"
    "The module must not use threads, lists, strings or errors, because\n"
    "mwrt.c does not supply the runtime they need."
)
"""The text the tool prints when the command line is wrong."""

comptime PSHUFB = "@llvm.x86.ssse3.pshuf.b.128"
"""The x86 byte shuffle that the standard library's UTF-8 check can call."""

comptime SWIZZLE = """
define internal <16 x i8> @tm_pshufb(<16 x i8> %table, <16 x i8> %index) {
  %kept = and <16 x i8> %index, splat (i8 -113)
  %bytes = call <16 x i8> @llvm.wasm.swizzle(<16 x i8> %table, <16 x i8> %kept)
  ret <16 x i8> %bytes
}

declare <16 x i8> @llvm.wasm.swizzle(<16 x i8>, <16 x i8>)
"""
"""The same shuffle on WebAssembly: 0x8F keeps the top bit, which takes the
index past 15 so that the swizzle gives zero, and the low four bits."""

comptime FAST_MATH = [
    "fast",
    "contract",
    "reassoc",
    "nnan",
    "ninf",
    "nsz",
    "arcp",
    "afn",
]
"""The fast-math flags an instruction may carry before its type."""


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


def _word_byte(byte: UInt8) -> Bool:
    """Return whether a byte is a word character, as regex `\\w` reads ASCII."""
    return (
        (byte >= 48 and byte <= 57)
        or (byte >= 65 and byte <= 90)
        or (byte >= 97 and byte <= 122)
        or byte == 95
    )


def _digit_byte(byte: UInt8) -> Bool:
    """Return whether a byte is a decimal digit."""
    return byte >= 48 and byte <= 57


def _hex_byte(byte: UInt8) -> Bool:
    """Return whether a byte is a hexadecimal digit."""
    return (
        _digit_byte(byte)
        or (byte >= 65 and byte <= 70)
        or (byte >= 97 and byte <= 102)
    )


def _hex_value(digits: String) -> UInt64:
    """Return the value of hexadecimal digits, wrapping past 64 bits."""
    var value = UInt64(0)
    for byte in digits.as_bytes():
        var digit: UInt64
        if _digit_byte(byte):
            digit = UInt64(byte - 48)
        elif byte >= 65 and byte <= 70:
            digit = UInt64(byte - 55)
        else:
            digit = UInt64(byte - 87)
        value = (value << 4) | digit
    return value


def _hex_double(bits: UInt64) -> String:
    """Return `0x` and 16 uppercase hexadecimal digits, as `%016X` writes."""
    comptime DIGITS = "0123456789ABCDEF"
    var text = String("0x")
    for shift in range(60, -4, -4):
        var nibble = Int((bits >> UInt64(shift)) & 15)
        text += DIGITS[byte=nibble]
    return text


def _clear_before(bytes: Span[UInt8, _], at: Int) -> Bool:
    """Return whether no word character and no `.` comes just before `at`,
    as the lookbehind `(?<![\\w.])` asks."""
    return at == 0 or not (_word_byte(bytes[at - 1]) or bytes[at - 1] == 46)


def _boundary(bytes: Span[UInt8, _], at: Int) -> Bool:
    """Return whether `at` is a word boundary before or after a word
    character: no word character on its other side."""
    return at < 0 or at >= len(bytes) or not _word_byte(bytes[at])


def _decimal_end(bytes: Span[UInt8, _], start: Int) -> Int:
    """Return where a decimal as LLVM writes one ends, or -1.

    The shape is `-?\\d+\\.\\d+e[+-]\\d+`, matched greedily.
    """
    var at = start
    if at < len(bytes) and bytes[at] == 45:
        at += 1
    var first = at
    while at < len(bytes) and _digit_byte(bytes[at]):
        at += 1
    if at == first or at >= len(bytes) or bytes[at] != 46:
        return -1
    at += 1
    var fraction = at
    while at < len(bytes) and _digit_byte(bytes[at]):
        at += 1
    if at == fraction or at >= len(bytes) or bytes[at] != 101:
        return -1
    at += 1
    if at >= len(bytes) or (bytes[at] != 43 and bytes[at] != 45):
        return -1
    at += 1
    var power = at
    while at < len(bytes) and _digit_byte(bytes[at]):
        at += 1
    if at == power:
        return -1
    return at


def exact_float(decimal: String) raises -> String:
    """Return a `float` constant that LLVM reads as the nearest float.

    Args:
        decimal: A decimal as LLVM writes one, such as `1.000000e-03`.

    Returns:
        The decimal when it is exactly a float. Otherwise the hexadecimal
        double of the nearest float.

    Raises:
        Error: If the text is not a number.
    """
    var value = Float64(decimal)
    var nearest = Float64(Float32(value))
    if nearest == value:
        return decimal
    return _hex_double(bitcast[DType.uint64](nearest))


def float_bits(bits: String) -> String:
    """Return the hexadecimal double of a float given by its 32 bits.

    Args:
        bits: Eight hexadecimal digits.

    Returns:
        `0x` and the 16 digits of the same number as a double.
    """
    var value = bitcast[DType.float32](UInt32(_hex_value(bits)))
    return _hex_double(bitcast[DType.uint64](Float64(value)))


def _last_float_type(text: String) -> String:
    """Return the last whole word `float` or `double` in `text`, or empty."""
    var bytes = text.as_bytes()
    var last = String()
    for at in range(len(bytes)):
        if not _boundary(bytes, at - 1):
            continue
        for name in ["float", "double"]:
            var end = at + name.byte_length()
            if String(text[byte=at:]).startswith(name) and _boundary(
                bytes, end
            ):
                last = name
    return last


def nan_bits(
    line: String, at: Int, negative: Bool, quiet: Bool, payload: String
) -> String:
    """Return the hexadecimal double of a NaN with a payload.

    Its type is the last `float` or `double` before it on the line.

    Args:
        line: The line.
        at: Where the NaN starts.
        negative: Whether its sign is `-`.
        quiet: Whether it is quiet, written `nan` rather than `snan`.
        payload: Its payload's hexadecimal digits, without `0x`.

    Returns:
        `0x` and the 16 digits of the double.
    """
    var bits = UInt64(0x7FF0000000000000)
    if negative:
        bits |= UInt64(1) << 63
    var value = _hex_value(payload)
    if _last_float_type(String(line[byte=:at])) == "float":
        if quiet:
            value |= UInt64(1) << 22
        bits |= value << 29
    else:
        if quiet:
            value |= UInt64(1) << 51
        bits |= value
    return _hex_double(bits)


def _nans(line: String) -> String:
    """Rewrite `+nan(0x...)` and `+snan(0x...)`, either sign."""
    var bytes = line.as_bytes()
    var out = String()
    var at = 0
    var copied = 0
    while at < len(bytes):
        var sign = bytes[at]
        if (sign == 43 or sign == 45) and _clear_before(bytes, at):
            var cursor = at + 1
            var signaling = cursor < len(bytes) and bytes[cursor] == 115
            if signaling:
                cursor += 1
            if String(line[byte=cursor:]).startswith("nan(0x"):
                var digits = cursor + 6
                var end = digits
                while end < len(bytes) and _hex_byte(bytes[end]):
                    end += 1
                if end > digits and end < len(bytes) and bytes[end] == 41:
                    out += String(line[byte=copied:at])
                    out += nan_bits(
                        line,
                        at,
                        sign == 45,
                        not signaling,
                        String(line[byte=digits:end]),
                    )
                    at = end + 1
                    copied = at
                    continue
        at += 1
    return out + String(line[byte=copied:])


def _specials(line: String) -> String:
    """Rewrite `+inf`, `-inf`, `+qnan` and `-qnan`."""
    var bytes = line.as_bytes()
    var out = String()
    var at = 0
    var copied = 0
    while at < len(bytes):
        var sign = bytes[at]
        if (sign == 43 or sign == 45) and _clear_before(bytes, at):
            var rest = String(line[byte = at + 1 :])
            var word = String()
            if rest.startswith("inf"):
                word = "inf"
            elif rest.startswith("qnan"):
                word = "qnan"
            var end = at + 1 + word.byte_length()
            if word.byte_length() > 0 and _boundary(bytes, end):
                var bits = UInt64(0x7FF0000000000000)
                if word == "qnan":
                    bits |= UInt64(1) << 51
                if sign == 45:
                    bits |= UInt64(1) << 63
                out += String(line[byte=copied:at]) + _hex_double(bits)
                at = end
                copied = at
                continue
        at += 1
    return out + String(line[byte=copied:])


def _float_hex(line: String, digits: Int) -> String:
    """Rewrite `f0x` and `digits` hexadecimal digits as a whole word.

    Sixteen digits are a double's bits and keep their digits. Eight are a
    float's bits and become the bits of the same double.
    """
    var bytes = line.as_bytes()
    var out = String()
    var at = 0
    var copied = 0
    while at < len(bytes):
        if (
            bytes[at] == 102
            and _boundary(bytes, at - 1)
            and String(line[byte = at + 1 :]).startswith("0x")
        ):
            var first = at + 3
            var end = first
            while (
                end < len(bytes)
                and end < first + digits
                and _hex_byte(bytes[end])
            ):
                end += 1
            if end == first + digits and _boundary(bytes, end):
                var hex = String(line[byte=first:end])
                out += String(line[byte=copied:at])
                if digits == 16:
                    out += "0x" + hex
                else:
                    out += float_bits(hex)
                at = end
                copied = at
                continue
        at += 1
    return out + String(line[byte=copied:])


def _decimals(line: String, after_float: Bool) raises -> String:
    """Rewrite each decimal that is not exactly a float.

    Args:
        line: The text.
        after_float: True to rewrite only a decimal right after `float `.
            False to rewrite each decimal with no word character or `.`
            just before it.

    Returns:
        The text.

    Raises:
        Error: Never for a decimal of LLVM's shape.
    """
    var bytes = line.as_bytes()
    var out = String()
    var at = 0
    var copied = 0
    while at < len(bytes):
        var allowed: Bool
        if after_float:
            allowed = at >= 6 and String(line[byte = at - 6 : at]) == "float "
        else:
            allowed = _clear_before(bytes, at)
        if allowed:
            var end = _decimal_end(bytes, at)
            if end > 0:
                out += String(line[byte=copied:at])
                out += exact_float(String(line[byte=at:end]))
                at = end
                copied = at
                continue
        at += 1
    return out + String(line[byte=copied:])


def _float_operands(line: String) -> Int:
    """Return where the first instruction whose operands take their type
    from it reaches its `float `, or -1.

    The instruction is `fadd`, `fsub`, `fmul`, `fdiv`, `frem`, `fcmp` and a
    condition, or `phi`, after `= `, with any fast-math flags.
    """
    var bytes = line.as_bytes()
    for start in range(len(bytes)):
        if not String(line[byte=start:]).startswith("= "):
            continue
        var at = start + 2
        var rest = String(line[byte=at:])
        var named = -1
        for name in ["fadd", "fsub", "fmul", "fdiv", "frem", "phi"]:
            if rest.startswith(name):
                named = at + name.byte_length()
        if named < 0 and rest.startswith("fcmp "):
            var word = at + 5
            var end = word
            while end < len(bytes) and _word_byte(bytes[end]):
                end += 1
            if end > word:
                named = end
        if named < 0:
            continue
        # Each flag that follows, then ` float `. Fewer flags never help:
        # a flag's word is not `float`.
        var cursor = named
        var moved = True
        while moved:
            moved = False
            for flag in materialize[FAST_MATH]():
                if String(line[byte=cursor:]).startswith(" " + flag):
                    cursor += 1 + flag.byte_length()
                    moved = True
                    break
        if String(line[byte=cursor:]).startswith(" float "):
            return cursor + 7
    return -1


def exact_floats(line: String) raises -> String:
    """Rewrite the floating-point constants of one line of IR, outside its
    strings.

    Args:
        line: One line of IR.

    Returns:
        The line, with each constant an older LLVM refuses written as the
        hexadecimal double of the same number.

    Raises:
        Error: Never for IR that LLVM wrote.
    """
    if line.find('"') >= 0:
        var parts = line.split('"')
        var rewritten = List[String]()
        for index in range(len(parts)):
            var part = String(parts[index])
            if index % 2 == 0:
                rewritten.append(exact_floats(part))
            else:
                rewritten.append(part)
        return '"'.join(rewritten)
    var text = _nans(line)
    text = _specials(text)
    text = _float_hex(text, 16)
    text = _float_hex(text, 8)
    text = _decimals(text, True)
    var found = _float_operands(text)
    if found >= 0:
        return String(text[byte=:found]) + _decimals(
            String(text[byte=found:]), False
        )
    return text


def replace_shuffle(text: String) -> String:
    """Call `tm_pshufb` where the module calls the x86 byte shuffle.

    Args:
        text: The module.

    Returns:
        The module, with the shuffle's declaration emptied, each call
        renamed, and `SWIZZLE` added. A module that does not name the
        shuffle is returned as it is.
    """
    if text.find(PSHUFB) < 0:
        return text
    var declaration = "declare <16 x i8> " + PSHUFB + "("
    var kept = List[String]()
    for line in text.split("\n"):
        var piece = String(line)
        if piece.startswith(declaration):
            kept.append(String())
        else:
            kept.append(piece)
    return "\n".join(kept).replace(PSHUFB, "@tm_pshufb") + SWIZZLE


def retarget_ir(text: String, layout: String) raises -> String:
    """Return the IR of `text` for wasm32.

    Args:
        text: Host LLVM IR.
        layout: The wasm32 data layout from clang.

    Returns:
        The retargeted IR.

    Raises:
        Error: Never for IR that LLVM wrote. The rewrites do not fail.
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
    var floats = List[String]()
    for line in lines:
        floats.append(exact_floats(line))
    current = replace_shuffle(_join_lines(current, floats))
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
