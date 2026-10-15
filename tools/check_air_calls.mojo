# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Check direct-call types in emitted Metal kernel AIR.

    sh tools/tool.sh .venv/bin/mojo check_air_calls --mojo .venv/bin/mojo

Mojo can drop a device pointer's `addrspace(1)` where the pointer crosses a
call or rides in a struct. The call then passes `ptr addrspace(1)` to a
function that declares `ptr`, or the reverse. LLVM's verifier accepts that
under opaque pointers, but Apple's air-lld linker segfaults on it and Mojo
reports only "Metal Compiler failed to compile metallib"
(modular/modular#7238).

This bounded checker compares direct calls with definitions or declarations
using scalar, opaque-pointer and literal aggregate types. It requires one
nonempty module with a function body for every discovered kernel. Every
enqueue_function reference must name a local, non-parameterized kernel;
unsupported launches fail before emission. Missing signatures and unsupported
call/type syntax fail closed; this is not an LLVM verifier or a GPU execution
test. Run with `make check-gpu-air`. The tool works on the repository in the
current directory. The emitted program needs MAX; this tool does not.
"""

from std.collections import Set
from std.os.path import exists, realpath
from std.pathlib import Path
from std.sys import argv, exit, stderr
from std.tempfile import mkdtemp

from tools._cli import absolute_path, parse_command_line
from tools._process import run_program
from tools._python_json import py_repr
from tools._text import split_lines

comptime MODULES = [
    "render/gpu.mojo",
    "render/gpu_vxgi.mojo",
    "extensions/water/gpu.mojo",
]
"""Kernels are launched from these modules. Every `enqueue_function`
reference must resolve to a supported, plainly named local kernel."""
comptime TARGET = "metal:4"
"""The GPU target of the emitted AIR."""
comptime SEPARATOR = "; ===== kernel "
"""The line before each kernel's AIR record."""
comptime ENTRY = "; ===== entry "
"""The line with the compiler-returned entry name, first in each record."""
comptime EMIT_SECONDS = 1800
"""The time limit of the emitting program, in seconds."""
comptime PROGRAM = "check_air_calls.mojo"
"""The program name in usage messages."""
comptime USAGE = "usage: check_air_calls.mojo [-h] [--mojo MOJO]\n"
"""The usage text, as `argparse` writes it."""
comptime HELP = (
    "\nCheck direct-call types in emitted Metal kernel AIR.\n\noptions:\n "
    " -h, --help   show this help message and exit\n  --mojo MOJO\n"
)
"""The help text after the usage."""

comptime Kernel = Tuple[String, String]
"""A kernel: its module and its name."""
comptime Mismatch = Tuple[String, String]
"""A call type mismatch: the callee and the detail."""


# --- characters ----------------------------------------------------------------


def _space(byte: UInt8) -> Bool:
    """Return whether a byte is Python whitespace (`\\s`, `str.isspace`)."""
    return (
        byte == 0x20
        or (byte >= 0x09 and byte <= 0x0D)
        or (byte >= 0x1C and byte <= 0x1F)
    )


def _digit(byte: UInt8) -> Bool:
    """Return whether a byte is an ASCII digit."""
    return byte >= 0x30 and byte <= 0x39


def _hex(byte: UInt8) -> Bool:
    """Return whether a byte is an ASCII hexadecimal digit."""
    return (
        _digit(byte)
        or (byte >= 0x41 and byte <= 0x46)
        or (byte >= 0x61 and byte <= 0x66)
    )


def _word(byte: UInt8) -> Bool:
    """Return whether a byte belongs to a `\\w` character.

    A byte of a multibyte character counts as a word character, as most
    such characters are letters.
    """
    return (
        _digit(byte)
        or (byte >= 0x41 and byte <= 0x5A)
        or (byte >= 0x61 and byte <= 0x7A)
        or byte == 0x5F
        or byte >= 0x80
    )


def _cut(text: String, start: Int, end: Int) -> String:
    """Return the bytes `start` to `end` of a text."""
    return String(text[byte=start:end])


def _from(text: String, start: Int) -> String:
    """Return a text from byte `start` to its end."""
    return String(text[byte=start:])


def strip(text: String) -> String:
    """Return a text without Python whitespace at either end.

    Args:
        text: The text.

    Returns:
        The text as `str.strip()` returns it, for ASCII whitespace.
    """
    var bytes = text.as_bytes()
    var start = 0
    var end = len(bytes)
    while start < end and _space(bytes[start]):
        start += 1
    while end > start and _space(bytes[end - 1]):
        end -= 1
    return _cut(text, start, end)


def head(text: String, count: Int) -> String:
    """Return the first characters of a text, as `text[:count]` does.

    Args:
        text: The text.
        count: The number of characters.

    Returns:
        The first `count` characters, or the whole text.
    """
    var bytes = text.as_bytes()
    var seen = 0
    for index in range(len(bytes)):
        if (bytes[index] & 0xC0) != 0x80:
            if seen == count:
                return _cut(text, 0, index)
            seen += 1
    return text


def _tail_chars(text: String, count: Int) -> String:
    """Return the last characters of a text, as `text[-count:]` does."""
    var bytes = text.as_bytes()
    var seen = 0
    var index = len(bytes)
    while index > 0:
        index -= 1
        if (bytes[index] & 0xC0) != 0x80:
            seen += 1
            if seen == count:
                return _from(text, index)
    return text


def _skip_space(text: String, start: Int) -> Int:
    """Return the index after the whitespace at `start`."""
    var bytes = text.as_bytes()
    var index = start
    while index < len(bytes) and _space(bytes[index]):
        index += 1
    return index


def _skip_digits(text: String, start: Int) -> Int:
    """Return the index after the ASCII digits at `start`."""
    var bytes = text.as_bytes()
    var index = start
    while index < len(bytes) and _digit(bytes[index]):
        index += 1
    return index


def _skip_word(text: String, start: Int) -> Int:
    """Return the index after the `\\w` characters at `start`."""
    var bytes = text.as_bytes()
    var index = start
    while index < len(bytes) and _word(bytes[index]):
        index += 1
    return index


def _at(text: String, index: Int, literal: String) -> Bool:
    """Return whether `literal` appears at byte `index` of a text."""
    var bytes = text.as_bytes()
    var want = literal.as_bytes()
    if index + len(want) > len(bytes):
        return False
    for offset in range(len(want)):
        if bytes[index + offset] != want[offset]:
            return False
    return True


def _byte(text: String, index: Int) -> UInt8:
    """Return a byte of a text, or 0 past its end."""
    var bytes = text.as_bytes()
    if index < 0 or index >= len(bytes):
        return 0
    return bytes[index]


def _contains(words: List[String], word: String) -> Bool:
    """Return whether a list holds a word."""
    for item in words:
        if item == word:
            return True
    return False


def _closer(byte: UInt8) -> UInt8:
    """Return the closing delimiter of an opening one, or 0."""
    if byte == 0x28:
        return 0x29
    if byte == 0x7B:
        return 0x7D
    if byte == 0x5B:
        return 0x5D
    if byte == 0x3C:
        return 0x3E
    return 0


def _is_closer(byte: UInt8) -> Bool:
    """Return whether a byte closes a delimiter pair."""
    return byte == 0x29 or byte == 0x7D or byte == 0x5D or byte == 0x3E


# --- AIR syntax ------------------------------------------------------------------


def _quoted_name_end(text: String, start: Int, newline: Bool) -> Int:
    """Return the end of the quoted name at `start`, or -1.

    The name is `"(?:[^"\\\\]|\\\\[0-9a-fA-F]{2})*"`. With `newline` False,
    a newline cannot appear in it.
    """
    var bytes = text.as_bytes()
    if start >= len(bytes) or bytes[start] != 0x22:
        return -1
    var index = start + 1
    while index < len(bytes):
        var byte = bytes[index]
        if byte == 0x22:
            return index + 1
        if byte == 0x5C:
            if (
                index + 2 < len(bytes)
                and _hex(bytes[index + 1])
                and _hex(bytes[index + 2])
            ):
                index += 3
                continue
            return -1
        if byte == 0x0A and not newline:
            return -1
        index += 1
    return -1


def quoted_end(text: String, start: Int) raises -> Int:
    """Return the end of the quoted string at `start`.

    Args:
        text: The text.
        start: The index of the opening quote.

    Returns:
        The index after the closing quote.

    Raises:
        Error: If the string is unterminated or has an unsupported escape.
    """
    var end = _quoted_name_end(text, start, False)
    if end < 0:
        raise Error("unterminated or unsupported quoted string")
    return end


def group_end(text: String, start: Int) raises -> Int:
    """Return the end of a balanced group, respecting quoted symbols.

    Args:
        text: The text.
        start: The index of the opening delimiter.

    Returns:
        The index after the matching closing delimiter.

    Raises:
        Error: If the delimiters do not balance.
    """
    var bytes = text.as_bytes()
    var stack = List[UInt8]()
    var index = start
    while index < len(bytes):
        var byte = bytes[index]
        if byte == 0x22:
            index = quoted_end(text, index)
            continue
        if _closer(byte) != 0:
            stack.append(_closer(byte))
        elif _is_closer(byte):
            if len(stack) == 0 or stack.pop() != byte:
                raise Error("unbalanced delimiters: " + head(text, 80))
            if len(stack) == 0:
                return index + 1
        index += 1
    raise Error("unbalanced delimiters: " + head(text, 80))


def split_top(text: String) raises -> List[String]:
    """Split a parameter or argument list at its top-level commas.

    Args:
        text: The list, without its parentheses.

    Returns:
        The stripped parts, or no parts for a blank list.

    Raises:
        Error: If the delimiters do not balance or a part is empty.
    """
    var parts = List[String]()
    if strip(text).byte_length() == 0:
        return parts^
    var bytes = text.as_bytes()
    var start = 0
    var index = 0
    while index < len(bytes):
        var byte = bytes[index]
        if byte == 0x22:
            index = quoted_end(text, index)
            continue
        if _closer(byte) != 0:
            index = group_end(text, index)
            continue
        if _is_closer(byte):
            raise Error("unbalanced delimiters: " + head(text, 80))
        if byte == 0x2C:
            parts.append(strip(_cut(text, start, index)))
            start = index + 1
        index += 1
    parts.append(strip(_from(text, start)))
    for part in parts:
        if part.byte_length() == 0:
            raise Error("empty parameter or argument")
    return parts^


def _scalar_end(item: String) -> Int:
    """Return the end of the scalar type at the start of `item`, or -1."""
    var words: List[String] = [
        "void",
        "half",
        "bfloat",
        "float",
        "double",
        "fp128",
        "x86_fp80",
        "ppc_fp128",
        "ptr",
    ]
    var bytes = item.as_bytes()
    var end = -1
    if (
        len(bytes) >= 2
        and bytes[0] == 0x69
        and bytes[1] >= 0x31
        and bytes[1] <= 0x39
    ):
        end = _skip_digits(item, 2)
    else:
        for word in words:
            if _at(item, 0, word):
                end = word.byte_length()
                break
    if end < 0 or (end < len(bytes) and _word(bytes[end])):
        return -1
    return end


def _trim_zeros(digits: String) -> String:
    """Return decimal digits without leading zeros, as `str(int())` does."""
    var bytes = digits.as_bytes()
    var start = 0
    while start + 1 < len(bytes) and bytes[start] == 0x30:
        start += 1
    return _from(digits, start)


def read_type(item_text: String) raises -> Tuple[String, String]:
    """Return the canonical type at the start of an item and the rest.

    Args:
        item_text: A parameter, an argument or a type.

    Returns:
        The canonical type and the stripped text after it.

    Raises:
        Error: If the type is missing or unsupported.
    """
    var item = strip(item_text)
    var bytes = item.as_bytes()
    var end = _scalar_end(item)
    if end >= 0:
        var kind = _cut(item, 0, end)
        if kind == "ptr":
            # \s+addrspace\(\s*([0-9]+)\s*\)
            var at = _skip_space(item, end)
            if at > end and _at(item, at, "addrspace("):
                var first = _skip_space(item, at + 10)
                var last = _skip_digits(item, first)
                var close = _skip_space(item, last)
                if last > first and _byte(item, close) == 0x29:
                    kind += (
                        " addrspace("
                        + _trim_zeros(_cut(item, first, last))
                        + ")"
                    )
                    end = close + 1
        if end < len(bytes) and not _space(bytes[end]):
            raise Error("unsupported type: " + head(item, 80))
        return (kind^, strip(_from(item, end)))
    if len(bytes) > 0 and (
        bytes[0] == 0x7B or bytes[0] == 0x5B or bytes[0] == 0x3C
    ):
        var close = group_end(item, 0)
        var inside = strip(_cut(item, 1, close - 1))
        var kind: String
        if bytes[0] == 0x7B:
            var fields = List[String]()
            for field in split_top(inside):
                fields.append(complete_type(field))
            kind = "{ " + ", ".join(fields) + " }"
        elif bytes[0] == 0x3C and inside.startswith("{"):
            kind = "<" + complete_type(inside) + ">"
        else:
            var sequence = _sequence(inside)
            if not sequence or (bytes[0] == 0x5B and "vscale" in inside):
                raise Error("unsupported type: " + head(item, 80))
            var count = List[String]()
            for word in sequence.value()[0].split():
                count.append(String(word))
            var closing = String(")")
            if bytes[0] == 0x5B:
                closing = "]"
            elif bytes[0] == 0x3C:
                closing = ">"
            kind = (
                _cut(item, 0, 1)
                + " ".join(count)
                + " x "
                + complete_type(sequence.value()[1])
                + closing
            )
        return (kind^, strip(_from(item, close)))
    raise Error("missing or unsupported type: " + head(item, 80))


def _sequence(inside: String) -> Optional[Tuple[String, String]]:
    """Match `((?:vscale\\s+x\\s+)?[0-9]+)\\s+x\\s+(.+)` against all of
    `inside`, and return its two groups."""
    var start = 0
    if _at(inside, 0, "vscale"):
        var after = _skip_space(inside, 6)
        if after > 6 and _byte(inside, after) == 0x78:
            var next = _skip_space(inside, after + 1)
            if next > after + 1:
                start = next
    var digits = _skip_digits(inside, start)
    if digits == start:
        return None
    var before = _skip_space(inside, digits)
    if before == digits or _byte(inside, before) != 0x78:
        return None
    var rest = _skip_space(inside, before + 1)
    if rest == before + 1 or rest >= inside.byte_length():
        return None
    var element = _from(inside, rest)
    if "\n" in element:
        return None
    return (_cut(inside, 0, digits), element^)


def complete_type(item: String) raises -> String:
    """Return a type that must stand alone.

    Args:
        item: The type.

    Returns:
        The canonical type.

    Raises:
        Error: If text follows the type or the type is `void`.
    """
    var found = read_type(item)
    if found[1].byte_length() > 0 or found[0] == "void":
        raise Error("unsupported aggregate element: " + head(item, 80))
    return found[0]


def item_type(item: String) raises -> String:
    """Return a parameter or argument type, without value or attributes.

    Args:
        item: The parameter or argument.

    Returns:
        The canonical type.

    Raises:
        Error: If the type is `void`, a typed pointer or a function type.
    """
    var found = read_type(item)
    if (
        found[0] == "void"
        or found[1].startswith("addrspace")
        or found[1].startswith("*")
        or found[1].startswith("(")
    ):
        raise Error("unsupported parameter or argument: " + head(item, 80))
    return found[0]


def _strip_words(text: String, words: List[String]) -> String:
    """Remove leading words that each end in whitespace, as
    `^(?:(?:WORD|...)\\s+)*` does."""
    var index = 0
    var bytes = text.as_bytes()
    while index < len(bytes):
        var end = index
        while end < len(bytes) and not _space(bytes[end]):
            end += 1
        if end == len(bytes) or not _contains(words, _cut(text, index, end)):
            break
        index = _skip_space(text, end)
    return _from(text, index)


def _function_attributes() -> List[String]:
    """Return the linkage, visibility, convention and flag words before a
    return type."""
    return [
        "internal",
        "private",
        "external",
        "dso_local",
        "dso_preemptable",
        "hidden",
        "protected",
        "default",
        "linkonce",
        "linkonce_odr",
        "weak",
        "weak_odr",
        "available_externally",
        "dllimport",
        "dllexport",
        "ccc",
        "fastcc",
        "coldcc",
        "noundef",
        "nonnull",
        "noalias",
        "zeroext",
        "signext",
        "fast",
        "nnan",
        "ninf",
        "nsz",
        "arcp",
        "contract",
        "afn",
        "reassoc",
    ]


def _strip_argument_attributes(text: String) -> String:
    """Remove the leading argument attributes, as `_ARG_ATTRIBUTES` does."""
    var words: List[String] = [
        "noundef",
        "nonnull",
        "noalias",
        "nocapture",
        "readonly",
        "readnone",
        "writeonly",
        "immarg",
        "inreg",
        "returned",
        "nest",
        "swiftself",
        "swifterror",
        "zeroext",
        "signext",
    ]
    var bytes = text.as_bytes()
    var index = 0
    while index < len(bytes):
        var end = index
        while end < len(bytes) and not _space(bytes[end]):
            end += 1
        var token = _cut(text, index, end)
        var after = -1
        if end < len(bytes) and _contains(words, token):
            after = end
        elif _at(text, index, "align"):
            var first = _skip_space(text, index + 5)
            var last = _skip_digits(text, first)
            if first > index + 5 and last > first:
                after = last
        else:
            var open = -1
            if _at(text, index, "dereferenceable_or_null("):
                open = index + 24
            elif _at(text, index, "dereferenceable("):
                open = index + 16
            if open >= 0:
                var last = _skip_digits(text, open)
                if last > open and _byte(text, last) == 0x29:
                    after = last + 1
        if after < 0:
            break
        var next = _skip_space(text, after)
        if next == after:
            break
        index = next
    return _from(text, index)


def _float_literal_end(text: String, start: Int) -> Int:
    """Return the end of the float literal at `start`, or -1.

    The literal is `f0x` and 8 hexadecimal digits, or
    `[+-]?[0-9]+\\.[0-9]*(?:[eE][+-]?[0-9]+)?`.
    """
    if _at(text, start, "f0x"):
        for offset in range(8):
            if not _hex(_byte(text, start + 3 + offset)):
                return -1
        return start + 11
    var index = start
    if _byte(text, index) == 0x2B or _byte(text, index) == 0x2D:
        index += 1
    var digits = _skip_digits(text, index)
    if digits == index or _byte(text, digits) != 0x2E:
        return -1
    index = _skip_digits(text, digits + 1)
    var mark = _byte(text, index)
    if mark == 0x65 or mark == 0x45:
        var exponent = index + 1
        if _byte(text, exponent) == 0x2B or _byte(text, exponent) == 0x2D:
            exponent += 1
        var last = _skip_digits(text, exponent)
        if last > exponent:
            index = last
    return index


def _splat(kind: String, value: String) -> Bool:
    """Return whether a splat literal is the supported float form."""
    # <[1-9][0-9]* x float>
    var bytes = kind.as_bytes()
    if (
        len(bytes) < 2
        or bytes[0] != 0x3C
        or not (bytes[1] >= 0x31 and bytes[1] <= 0x39)
    ):
        return False
    var digits = _skip_digits(kind, 1)
    if _from(kind, digits) != " x float>":
        return False
    # splat\s*\(\s*float\s+FLOAT\s*\)
    var index = _skip_space(value, 5)
    if _byte(value, index) != 0x28:
        return False
    index = _skip_space(value, index + 1)
    if not _at(value, index, "float"):
        return False
    var after = _skip_space(value, index + 5)
    if after == index + 5:
        return False
    var end = _float_literal_end(value, after)
    if end < 0:
        return False
    end = _skip_space(value, end)
    return _byte(value, end) == 0x29 and end + 1 == value.byte_length()


def argument_type(item: String) raises -> String:
    """Return a call argument's type, after checking its value's form.

    Args:
        item: The argument.

    Returns:
        The canonical type.

    Raises:
        Error: If the argument has no value or an unsupported value.
    """
    var kind = item_type(item)
    var rest = read_type(item)[1]
    # A value must remain after recognized attributes. This is deliberately
    # not a verifier for constant expressions or aggregate value contents.
    var value = strip(_strip_argument_attributes(rest + " "))
    if value.byte_length() == 0:
        raise Error("call argument has no value")
    # These are the additional literal forms observed in the pinned Metal
    # emitter, rather than a blanket acceptance of arbitrary value keywords.
    if value.startswith("f0x"):
        if (
            kind != "float"
            or value.byte_length() != 11
            or _float_literal_end(value, 0) != 11
        ):
            raise Error("unsupported f0x literal")
        return kind
    if value.startswith("splat"):
        if not _splat(kind, value):
            raise Error("unsupported splat literal")
        return kind
    var first = _byte(value, 0)
    var keywords: List[String] = [
        "true",
        "false",
        "null",
        "undef",
        "poison",
        "zeroinitializer",
        "getelementptr",
        "bitcast",
        "inttoptr",
        "ptrtoint",
        "addrspacecast",
        "blockaddress",
    ]
    if not (
        first == 0x25
        or first == 0x40
        or first == 0x2B
        or first == 0x2D
        or _digit(first)
        or first == 0x5B
        or first == 0x7B
        or first == 0x3C
        or _contains(keywords, _cut(value, 0, _skip_word(value, 0)))
    ):
        raise Error(
            "unsupported call argument value or attributes: " + head(item, 80)
        )
    # Validate delimiter/quote balance even though value semantics are outside
    # this check (including commas within an aggregate or constant expression).
    _ = split_top(value)
    return kind


def _delimited(text: String, index: Int) -> Bool:
    """Return whether `(?=\\s|,|$)` holds at `index`."""
    var byte = _byte(text, index)
    return index >= text.byte_length() or _space(byte) or byte == 0x2C


def _signature_attribute_end(text: String) -> Int:
    """Return the end of the attribute at the start of `text`, or -1."""
    var words: List[String] = [
        "local_unnamed_addr",
        "unnamed_addr",
        "nounwind",
        "willreturn",
        "noreturn",
        "norecurse",
        "nosync",
        "nofree",
        "readnone",
        "readonly",
        "writeonly",
        "convergent",
        "mustprogress",
        "alwaysinline",
        "noinline",
        "optnone",
        "optsize",
        "minsize",
        "speculatable",
        "nocallback",
        "cold",
        "hot",
        "nobuiltin",
        "builtin",
        "memory(none)",
        "memory(read)",
        "memory(write)",
        "memory(readwrite)",
    ]
    var end = -1
    if _byte(text, 0) == 0x23:
        var last = _skip_digits(text, 1)
        if last > 1:
            end = last
    elif _at(text, 0, "align"):
        var first = _skip_space(text, 5)
        var last = _skip_digits(text, first)
        if first > 5 and last > first:
            end = last
    elif _at(text, 0, "addrspace("):
        var last = _skip_digits(text, 10)
        if last > 10 and _byte(text, last) == 0x29:
            end = last + 1
    else:
        for word in words:
            if _at(text, 0, word) and _delimited(text, word.byte_length()):
                return word.byte_length()
    if end >= 0 and _delimited(text, end):
        return end
    return -1


def _metadata_suffix(text: String) -> Bool:
    """Return whether all of `text` is `(?:,?\\s*![\\w.]+\\s+![0-9]+\\s*)+`."""
    var index = 0
    var groups = 0
    var size = text.byte_length()
    while index < size:
        if _byte(text, index) == 0x2C:
            index += 1
        index = _skip_space(text, index)
        if _byte(text, index) != 0x21:
            return False
        var start = index + 1
        index = start
        while index < size and (
            _word(_byte(text, index)) or _byte(text, index) == 0x2E
        ):
            index += 1
        if index == start:
            return False
        var space = _skip_space(text, index)
        if space == index or _byte(text, space) != 0x21:
            return False
        var digits = _skip_digits(text, space + 1)
        if digits == space + 1:
            return False
        index = _skip_space(text, digits)
        groups += 1
    return groups > 0


def signature_suffix(tail_text: String, definition: Bool = False) raises:
    """Check the supported attribute/metadata suffix, not LLVM attribute
    semantics.

    Args:
        tail_text: The text after a signature's or call's parameters.
        definition: True for a definition, whose suffix ends in `{`.

    Raises:
        Error: If the suffix has an unsupported form.
    """
    var tail = tail_text
    if definition:
        if not tail.endswith("{"):
            raise Error("definition has no opening body brace")
        tail = strip(_cut(tail, 0, tail.byte_length() - 1))
    while tail.byte_length() > 0:
        var end = _signature_attribute_end(tail)
        if end < 0:
            break
        tail = strip(_from(tail, end))
    if tail.byte_length() > 0 and not _metadata_suffix(tail):
        raise Error("unsupported signature/call suffix: " + head(tail, 80))


def _append_utf8(mut out: List[UInt8], point: Int):
    """Append a code point below 0x800 as UTF-8."""
    if point < 0x80:
        out.append(UInt8(point))
    else:
        out.append(UInt8(0xC0 | (point >> 6)))
        out.append(UInt8(0x80 | (point & 0x3F)))


def _hex_value(byte: UInt8) -> Int:
    """Return the value of a hexadecimal digit."""
    if _digit(byte):
        return Int(byte) - 0x30
    if byte >= 0x61:
        return Int(byte) - 0x61 + 10
    return Int(byte) - 0x41 + 10


def symbol_name(name: String) -> String:
    """Return a symbol's name, with a quoted name's escapes decoded.

    Args:
        name: A plain name, or a quoted name with `\\XX` escapes.

    Returns:
        The name. An escape decodes to the code point `U+00XX`.
    """
    if not name.startswith('"'):
        return name
    var bytes = name.as_bytes()
    var out = List[UInt8]()
    var index = 1
    var end = len(bytes) - 1
    while index < end:
        if (
            bytes[index] == 0x5C
            and index + 2 < end
            and _hex(bytes[index + 1])
            and _hex(bytes[index + 2])
        ):
            _append_utf8(
                out,
                _hex_value(bytes[index + 1]) * 16
                + _hex_value(bytes[index + 2]),
            )
            index += 3
            continue
        out.append(bytes[index])
        index += 1
    return String(unsafe_from_utf8=out)


def _name_end(text: String, start: Int) -> Int:
    """Return the end of the `_NAME` at `start`, or -1."""
    if _byte(text, start) == 0x22:
        return _quoted_name_end(text, start, False)
    var bytes = text.as_bytes()
    var index = start
    while index < len(bytes) and (
        _word(bytes[index])
        or bytes[index] == 0x2D
        or bytes[index] == 0x2E
        or bytes[index] == 0x24
    ):
        index += 1
    return index if index > start else -1


def signature(
    text: String,
) raises -> Tuple[String, String, List[String], String]:
    """Read a direct-call signature or call.

    Args:
        text: The text after `define`, `declare` or the call word.

    Returns:
        The callee's name, the return type, the parameters or arguments and
        the stripped text after them.

    Raises:
        Error: If the text has no supported signature.
    """
    var bytes = text.as_bytes()
    var found = -1
    var name_end = -1
    var open = -1
    for index in range(len(bytes)):
        if bytes[index] != 0x40:
            continue
        var end = _name_end(text, index + 1)
        if end < 0:
            continue
        var paren = _skip_space(text, end)
        if _byte(text, paren) == 0x28:
            found = index
            name_end = end
            open = paren
            break
    if found < 0:
        raise Error(
            "missing or unsupported direct-call signature: " + head(text, 80)
        )
    var name = symbol_name(_cut(text, found + 1, name_end))
    var returned = read_type(
        strip(_strip_words(_cut(text, 0, found), _function_attributes()))
    )
    if returned[1].byte_length() > 0:
        raise Error("unsupported return/call signature: " + head(text, 80))
    var end = group_end(text, open)
    var items = split_top(_cut(text, open + 1, end - 1))
    return (name^, returned[0], items^, strip(_from(text, end)))


def clean_line(line: String) raises -> String:
    """Remove LLVM comments without treating semicolons in quotes as
    comments.

    Args:
        line: A line.

    Returns:
        The stripped line without its comment.

    Raises:
        Error: If a quoted string is unterminated.
    """
    var bytes = line.as_bytes()
    var index = 0
    while index < len(bytes):
        if bytes[index] == 0x22:
            index = quoted_end(line, index)
        elif bytes[index] == 0x3B:
            return strip(_cut(line, 0, index))
        else:
            index += 1
    return strip(line)


def emitted_symbol(air: String) raises -> String:
    """Read one entry name emitted from the same CompiledFunctionInfo as asm.

    Args:
        air: One kernel's record.

    Returns:
        The entry name.

    Raises:
        Error: If the entry line is missing, repeated or not first.
    """
    var lines = split_lines(air)
    var entries = List[String]()
    for line in lines:
        if line.startswith(ENTRY):
            entries.append(_from(line, ENTRY.byte_length()))
    if (
        len(entries) != 1
        or entries[0].byte_length() == 0
        or not lines[0].startswith(ENTRY)
    ):
        raise Error("missing, duplicate or misplaced emitted entry name")
    return entries[0]


def _metadata_key(line: String) -> Int:
    """Return the end of a `!air.kernel` or `!N` key that `\\s*=` follows,
    or -1."""
    if _at(line, 0, "!air.kernel"):
        return 11
    if _byte(line, 0) == 0x21:
        var last = _skip_digits(line, 1)
        if last > 1:
            return last
    return -1


def kernel_entry(
    air: String, definitions: Dict[String, String], expected: Kernel
) raises:
    """Bind !air.kernel to the exact compiler-returned function_name.

    The observed single-entry metadata form selects a defined function with
    a metal.kernel attribute. Source-name prefixes are insufficient because
    the compiler truncates them and includes specialization text. No Mojo
    mangling or demangling rule is assumed.

    Args:
        air: One kernel's record.
        definitions: Each defined function and its signature suffix.
        expected: The kernel the record claims.

    Raises:
        Error: If the metadata does not bind the entry.
    """
    var expected_symbol = emitted_symbol(air)
    var metadata = Dict[String, String]()
    var attributes = Dict[String, String]()
    for raw in split_lines(air):
        var line = clean_line(raw)
        var key_end = _metadata_key(line)
        if key_end >= 0:
            var equals = _skip_space(line, key_end)
            if _byte(line, equals) == 0x3D:
                var key = _cut(line, 0, key_end)
                if key in metadata:
                    raise Error("duplicate metadata: " + key)
                metadata[key] = _from(line, _skip_space(line, equals + 1))
        if _at(line, 0, "attributes"):
            var hash = _skip_space(line, 10)
            if hash > 10 and _byte(line, hash) == 0x23:
                var last = _skip_digits(line, hash + 1)
                var equals = _skip_space(line, last)
                if last > hash + 1 and _byte(line, equals) == 0x3D:
                    var value_start = _skip_space(line, equals + 1)
                    var value = _from(line, value_start)
                    if value.startswith("{") and value.endswith("}"):
                        var key = _cut(line, hash + 1, last)
                        if key in attributes:
                            raise Error("duplicate attribute group: #" + key)
                        attributes[key] = value
    var reference = String()
    var listed = metadata.get("!air.kernel").or_else(String())
    if listed.startswith("!{") and listed.endswith("}"):
        var inside = strip(_cut(listed, 2, listed.byte_length() - 1))
        if _byte(inside, 0) == 0x21:
            var last = _skip_digits(inside, 1)
            if last > 1 and last == inside.byte_length():
                reference = inside
    if reference.byte_length() == 0:
        raise Error("missing or unsupported single-entry !air.kernel metadata")
    var node = metadata.get(reference).or_else(String())
    if not node.startswith("!{") or not node.endswith("}"):
        raise Error("missing or unsupported kernel entry metadata node")
    var operands = split_top(_cut(node, 2, node.byte_length() - 1))
    var entry = String()
    var matched = False
    if len(operands) > 0 and _at(operands[0], 0, "ptr"):
        var at = _skip_space(operands[0], 3)
        if at > 3 and _byte(operands[0], at) == 0x40:
            var end = _name_end(operands[0], at + 1)
            if end == operands[0].byte_length():
                matched = True
                entry = _cut(operands[0], at + 1, end)
    var numbered = True
    for index in range(1, len(operands)):
        var operand = operands[index]
        if not (
            _byte(operand, 0) == 0x21
            and operand.byte_length() > 1
            and _skip_digits(operand, 1) == operand.byte_length()
        ):
            numbered = False
    if not matched or len(operands) != 3 or not numbered:
        raise Error("unsupported kernel entry metadata operands")
    for index in range(1, len(operands)):
        if not operands[index] in metadata:
            raise Error("missing kernel argument metadata")
    var name = symbol_name(entry)
    if not name in definitions:
        raise Error("kernel entry has no function body: " + name)
    if name != expected_symbol:
        raise Error(
            "kernel entry "
            + name
            + " does not match compiler-returned entry "
            + expected_symbol
            + " for "
            + expected[0]
            + ":"
            + expected[1]
        )
    var suffix = definitions[name]
    var marked = False
    var index = 0
    while index < suffix.byte_length():
        if _byte(suffix, index) == 0x23:
            var last = _skip_digits(suffix, index + 1)
            if last > index + 1:
                var group = attributes.get(_cut(suffix, index + 1, last))
                if group and _metal_kernel(group.value()):
                    marked = True
                index = last
                continue
        index += 1
    if not marked:
        raise Error("kernel entry lacks metal.kernel attribute: " + name)


def _metal_kernel(group: String) -> Bool:
    """Return whether an attribute group holds `"metal.kernel"="true"`."""
    var start = 0
    while True:
        var found = group.find('"metal.kernel"', start)
        if found < 0:
            return False
        var equals = _skip_space(group, found + 14)
        if _byte(group, equals) == 0x3D:
            var value = _skip_space(group, equals + 1)
            if _at(group, value, '"true"'):
                return True
        start = found + 1


def _call_word(line: String) -> Optional[Tuple[String, Int]]:
    """Match `_CALL` at the start of a line.

    Returns:
        The call word and the index after it, or nothing.
    """
    var index = 0
    if _byte(line, 0) == 0x25:
        var end: Int
        if _byte(line, 1) == 0x22:
            end = _quoted_name_end(line, 1, True)
        else:
            end = _name_end(line, 1)
            if _byte(line, 1) == 0x22:
                end = -1
        if end < 0:
            return None
        var equals = _skip_space(line, end)
        if _byte(line, equals) != 0x3D:
            return None
        index = _skip_space(line, equals + 1)
    for flag in ["tail", "musttail", "notail"]:
        if _at(line, index, flag):
            var after = index + flag.byte_length()
            if after < line.byte_length() and _space(_byte(line, after)):
                index = _skip_space(line, after)
                break
    var word = _cut(line, index, _skip_word(line, index))
    if word == "call" or word == "invoke" or word == "callbr":
        return (word, index + word.byte_length())
    return None


def _starts_with_word(line: String, words: List[String]) -> Bool:
    """Return whether a line's leading `\\w` run is one of `words`."""
    return _contains(words, _cut(line, 0, _skip_word(line, 0)))


def _outside_function(line: String) -> Bool:
    """Return whether a line is a recognized module-level line."""
    if _at(line, 0, "source_filename"):
        if _byte(line, _skip_space(line, 15)) == 0x3D:
            return True
    if _at(line, 0, "target") and _space(_byte(line, 6)):
        return True
    if _at(line, 0, "module") and _space(_byte(line, 6)):
        var at = _skip_space(line, 6)
        if _at(line, at, "asm") and _space(_byte(line, at + 3)):
            return True
    if _at(line, 0, "attributes") and _space(_byte(line, 10)):
        var hash = _skip_space(line, 10)
        if _byte(line, hash) == 0x23:
            var last = _skip_digits(line, hash + 1)
            if last > hash + 1 and _byte(line, _skip_space(line, last)) == 0x3D:
                return True
    var first = _byte(line, 0)
    return first == 0x21 or first == 0x40 or first == 0x24 or first == 0x25


struct _Signature(Copyable, Movable):
    """A function's return type and parameter types."""

    var returned: String
    """The return type."""
    var params: List[String]
    """The parameter types."""

    def __init__(out self, returned: String, var params: List[String]):
        """Make a signature.

        Args:
            returned: The return type.
            params: The parameter types.
        """
        self.returned = returned
        self.params = params^

    def same(self, other: Self) -> Bool:
        """Return whether two signatures are equal.

        Args:
            other: The other signature.

        Returns:
            True for the same return and parameter types.
        """
        if self.returned != other.returned or len(self.params) != len(
            other.params
        ):
            return False
        for index in range(len(self.params)):
            if self.params[index] != other.params[index]:
                return False
        return True


struct _Call(Copyable, Movable):
    """A direct call: the callee, the return type and the argument types."""

    var name: String
    """The callee."""
    var returned: String
    """The call's return type."""
    var args: List[String]
    """The argument types."""

    def __init__(
        out self, name: String, returned: String, var args: List[String]
    ):
        """Make a call.

        Args:
            name: The callee.
            returned: The call's return type.
            args: The argument types.
        """
        self.name = name
        self.returned = returned
        self.args = args^


def _check_line(
    line: String,
    mut signatures: Dict[String, _Signature],
    mut calls: List[_Call],
    mut definitions: Dict[String, String],
    mut active: Optional[String],
    mut body: Bool,
) raises:
    """Check one cleaned, nonblank line of a module."""
    if _starts_with_word(line, ["define", "declare"]):
        if active:
            raise Error("nested function or missing closing brace")
        # `line.split(None, 1)` must give the form and the text.
        var split = 0
        while split < line.byte_length() and not _space(_byte(line, split)):
            split += 1
        if split == line.byte_length():
            raise Error("not enough values to unpack (expected 2, got 1)")
        var form = _cut(line, 0, split)
        var text = _from(line, _skip_space(line, split))
        var found = signature(text)
        var name = found[0]
        var tail = found[3]
        signature_suffix(tail, definition=form == "define")
        var types = List[String]()
        for item in found[2]:
            types.append(item_type(item))
        var current = _Signature(found[1], types^)
        if name in signatures and not signatures[name].same(current):
            raise Error("conflicting signatures for " + name)
        signatures[name] = current^
        if form == "define":
            if name in definitions or not tail.endswith("{"):
                raise Error("duplicate or incomplete definition for " + name)
            definitions[name] = tail
            active = name
            body = False
        elif "{" in tail or "}" in tail:
            raise Error("body on declaration for " + name)
        return
    if line == "}":
        if not active or not body:
            raise Error("missing function body or recognized terminator")
        active = None
        return
    if line.endswith(":"):
        if not active:
            raise Error("label outside function")
        return
    var call = _call_word(line)
    if call and not active:
        raise Error("call outside function")
    if not active:
        if not _outside_function(line):
            raise Error("unrecognized output outside function")
        return
    if call:
        if call.value()[0] != "call":
            raise Error("unsupported call instruction")
        var found = signature(strip(_from(line, call.value()[1])))
        signature_suffix(found[3])
        var args = List[String]()
        for item in found[2]:
            args.append(argument_type(item))
        calls.append(_Call(found[0], found[1], args^))
    if _starts_with_word(
        line,
        [
            "ret",
            "br",
            "switch",
            "indirectbr",
            "unreachable",
            "resume",
            "catchret",
            "cleanupret",
        ],
    ):
        body = True


def mismatches(
    air: String, expected_kernel: Optional[Kernel] = None
) raises -> List[Mismatch]:
    """Compare supported direct calls; reject uncheckable input.

    A body must close and contain a recognized terminator. Function headers
    and calls must each fit on one line. Indirect calls,
    invoke/callbr, explicit function types, varargs and named types are not
    supported. Other instructions and argument values are not LLVM-verified.

    Args:
        air: One module's AIR, with its entry line when `expected_kernel` is
            given.
        expected_kernel: The kernel the record claims, or nothing for a
            module without an entry check.

    Returns:
        Each call whose types differ from its callee's: the callee and the
        detail.

    Raises:
        Error: If the module is missing, malformed or unsupported.
    """
    var signatures = Dict[String, _Signature]()
    var calls = List[_Call]()
    var definitions = Dict[String, String]()
    var active = Optional[String]()
    var body = False
    var number = 0
    for raw in split_lines(air):
        number += 1
        var line = clean_line(raw)
        if line.byte_length() == 0:
            continue
        try:
            _check_line(line, signatures, calls, definitions, active, body)
        except error:
            raise Error("line " + String(number) + ": " + String(error))
    if active:
        raise Error("unterminated function body: " + active.value())
    if len(definitions) == 0:
        raise Error("AIR module has no function body")
    if expected_kernel:
        kernel_entry(air, definitions, expected_kernel.value())
    var found_bad = List[Mismatch]()
    for call in calls:
        if not call.name in signatures:
            raise Error(
                "missing definition or declaration for callee " + call.name
            )
        var declared = signatures[call.name].copy()
        if call.returned != declared.returned:
            found_bad.append(
                (
                    call.name,
                    "returns "
                    + call.returned
                    + ", declared "
                    + declared.returned,
                )
            )
        if len(call.args) != len(declared.params):
            found_bad.append(
                (
                    call.name,
                    String(len(call.args))
                    + " arguments, declared "
                    + String(len(declared.params)),
                )
            )
            continue
        for index in range(len(call.args)):
            if call.args[index] != declared.params[index]:
                found_bad.append(
                    (
                        call.name,
                        "argument "
                        + String(index)
                        + " is "
                        + call.args[index]
                        + ", declared "
                        + declared.params[index],
                    )
                )
    return found_bad^


# --- Mojo source tokens ----------------------------------------------------------

comptime NAME = 1
"""A token kind: a name or keyword."""
comptime OP = 2
"""A token kind: an operator or delimiter."""
comptime OTHER = 3
"""A token kind: a number or a string."""


struct Token(Copyable, Movable):
    """A token of Mojo source, as Python's `tokenize` reads it."""

    var kind: Int
    """`NAME`, `OP` or `OTHER`."""
    var text: String
    """The token's text."""
    var row: Int
    """The line, from 1."""
    var column: Int
    """The column in characters, from 0."""

    def __init__(out self, kind: Int, var text: String, row: Int, column: Int):
        """Make a token.

        Args:
            kind: `NAME`, `OP` or `OTHER`.
            text: The token's text.
            row: The line, from 1.
            column: The column in characters, from 0.
        """
        self.kind = kind
        self.text = text^
        self.row = row
        self.column = column


def _token_error(message: String, row: Int, column: Int) -> Error:
    """Return a `tokenize.TokenError` as `str()` writes it."""
    return Error(
        "("
        + py_repr(message)
        + ", ("
        + String(row)
        + ", "
        + String(column)
        + "))"
    )


def _indentation_error(message: String, row: Int) -> Error:
    """Return an `IndentationError` as `str()` writes it."""
    return Error(message + " (<string>, line " + String(row) + ")")


def _escaped_hint(escaped_quote: Bool) -> String:
    """Return the hint that Python adds when a string escaped its quote."""
    if escaped_quote:
        return "; perhaps you escaped the end quote?"
    return String()


def _chars(text: String, start: Int, end: Int) -> Int:
    """Return the characters from byte `start` to byte `end`.

    Each byte past the text's end counts as one character, as the newline
    that Python's tokenizer adds at the end does.
    """
    var bytes = text.as_bytes()
    var count = 0
    for at in range(start, min(end, len(bytes))):
        if (bytes[at] & 0xC0) != 0x80:
            count += 1
    return count + max(0, end - max(start, len(bytes)))


def _name_start(byte: UInt8) -> Bool:
    """Return whether a byte starts a Python identifier."""
    return (
        (byte >= 0x41 and byte <= 0x5A)
        or (byte >= 0x61 and byte <= 0x7A)
        or byte == 0x5F
        or byte >= 0x80
    )


struct _Tokenizer:
    """Python's `tokenize`, for the tokens that kernel discovery reads."""

    var index: Int
    """The next byte."""
    var row: Int
    """The current line, from 1."""
    var line_start: Int
    """The byte where the current line starts."""
    var segment_start: Int
    """The byte after the last LF that was not a line continuation."""
    var depth: Int
    """The open bracket count."""

    def __init__(out self):
        """Start at the beginning of a source."""
        self.index = 0
        self.row = 1
        self.line_start = 0
        self.segment_start = 0
        self.depth = 0

    def column(self, text: String, index: Int) -> Int:
        """Return the character column of a byte on the current line.

        Args:
            text: The source.
            index: The byte.

        Returns:
            The characters from the line start to the byte.
        """
        return _chars(text, self.line_start, index)

    def newline(mut self, index: Int, continuation: Bool = False):
        """Move to the line after the LF at `index`.

        Args:
            index: The LF.
            continuation: True for the LF of a line continuation.
        """
        self.row += 1
        self.line_start = index + 1
        if not continuation:
            self.segment_start = index + 1

    def string_end(
        mut self,
        text: String,
        start: Int,
        quote_at: Int,
        formatted: Bool = False,
    ) raises -> Int:
        """Return the end of the string whose token starts at `start`.

        Args:
            text: The source.
            start: The token start, at its prefix or quote.
            quote_at: The first quote.
            formatted: True for an f-string. Its replacement fields are
                not read; Mojo has no f-strings.

        Returns:
            The index after the closing quote.

        Raises:
            Error: For an unterminated string.
        """
        var bytes = text.as_bytes()
        var size = len(bytes)
        var quote = bytes[quote_at]
        var row = self.row
        var column = self.column(text, start) + 1
        var triple = (
            quote_at + 2 < size
            and bytes[quote_at + 1] == quote
            and bytes[quote_at + 2] == quote
        )
        var index = quote_at + (3 if triple else 1)
        var escaped_quote = False
        while True:
            if index >= size:
                if formatted:
                    raise _token_error(
                        "unterminated "
                        + ("triple-quoted " if triple else "")
                        + "f-string literal (detected at line "
                        + String(row)
                        + ")",
                        row,
                        column,
                    )
                if triple:
                    raise _token_error("EOF in multi-line string", row, column)
                # An escaped final LF is not a line of its own.
                var detected = self.row
                if (
                    size >= 2
                    and bytes[size - 2] == 0x5C
                    and bytes[size - 1] == 0x0A
                    and self.line_start == size
                ):
                    detected -= 1
                raise _token_error(
                    "unterminated string literal (detected at line "
                    + String(detected)
                    + ")"
                    + _escaped_hint(escaped_quote),
                    row,
                    column,
                )
            var byte = bytes[index]
            if byte == 0x5C:
                if index + 1 < size and bytes[index + 1] == 0x0A:
                    self.newline(index + 1, continuation=True)
                if index + 1 < size and bytes[index + 1] == quote:
                    escaped_quote = True
                index += 2
                continue
            if byte == 0x0A:
                if not triple:
                    raise _token_error(
                        "unterminated "
                        + ("f-string" if formatted else "string")
                        + " literal (detected at line "
                        + String(self.row)
                        + ")"
                        + ("" if formatted else _escaped_hint(escaped_quote)),
                        row,
                        column,
                    )
                self.newline(index, continuation=True)
                index += 1
                continue
            if byte == quote:
                if not triple:
                    return index + 1
                if (
                    index + 2 < size
                    and bytes[index + 1] == quote
                    and bytes[index + 2] == quote
                ):
                    return index + 3
            index += 1

    def _digits(
        self, text: String, start: Int, kind: String, accept: Int
    ) raises -> Int:
        """Read digits with single underscores between them.

        Args:
            text: The source.
            start: The first digit, which must be present.
            kind: `decimal`, `hexadecimal`, `octal` or `binary`.
            accept: The radix.

        Returns:
            The index after the digits.

        Raises:
            Error: For a misplaced underscore or a missing digit.
        """
        var bytes = text.as_bytes()
        var index = start
        while True:
            while index < len(bytes) and self._in_radix(bytes[index], accept):
                index += 1
            if index < len(bytes) and bytes[index] == 0x5F:
                index += 1
                if index >= len(bytes) or not self._in_radix(
                    bytes[index], accept
                ):
                    if (
                        accept < 10
                        and index < len(bytes)
                        and _digit(bytes[index])
                    ):
                        raise _token_error(
                            "invalid digit '"
                            + _cut(text, index, index + 1)
                            + "' in "
                            + kind
                            + " literal",
                            self.row,
                            self.column(text, index + 1),
                        )
                    raise _token_error(
                        "invalid " + kind + " literal",
                        self.row,
                        self.column(text, index),
                    )
                continue
            return index

    def _in_radix(self, byte: UInt8, radix: Int) -> Bool:
        """Return whether a byte is a digit of a radix."""
        if radix == 16:
            return _hex(byte)
        if radix == 10:
            return _digit(byte)
        return byte >= 0x30 and Int(byte) < 0x30 + radix

    def number_end(self, text: String, start: Int) raises -> Int:
        """Return the end of the number at `start`.

        Args:
            text: The source.
            start: A digit, or a point before a digit.

        Returns:
            The index after the number.

        Raises:
            Error: For an invalid literal.
        """
        var bytes = text.as_bytes()
        var size = len(bytes)
        if bytes[start] == 0x30 and start + 1 < size:
            var mark = bytes[start + 1] | 0x20
            var radix = 0
            var kind = String()
            if mark == 0x78:
                radix = 16
                kind = "hexadecimal"
            elif mark == 0x6F:
                radix = 8
                kind = "octal"
            elif mark == 0x62:
                radix = 2
                kind = "binary"
            if radix > 0:
                var index = start + 2
                if index < size and bytes[index] == 0x5F:
                    index += 1
                if index >= size or not self._in_radix(bytes[index], radix):
                    if radix < 16 and index < size and _digit(bytes[index]):
                        raise _token_error(
                            "invalid digit '"
                            + _cut(text, index, index + 1)
                            + "' in "
                            + kind
                            + " literal",
                            self.row,
                            self.column(text, index + 1),
                        )
                    raise _token_error(
                        "invalid " + kind + " literal",
                        self.row,
                        self.column(text, index),
                    )
                index = self._digits(text, index, kind, radix)
                if radix < 16 and index < size and _digit(bytes[index]):
                    raise _token_error(
                        "invalid digit '"
                        + _cut(text, index, index + 1)
                        + "' in "
                        + kind
                        + " literal",
                        self.row,
                        self.column(text, index + 1),
                    )
                return index
        var index = start
        if bytes[index] != 0x2E:
            index = self._digits(text, index, "decimal", 10)
        if index < size and bytes[index] == 0x2E:
            index += 1
            if index < size and _digit(bytes[index]):
                index = self._digits(text, index, "decimal", 10)
        if index < size and (bytes[index] | 0x20) == 0x65:
            var exponent = index + 1
            var signed = False
            if exponent < size and (
                bytes[exponent] == 0x2B or bytes[exponent] == 0x2D
            ):
                exponent += 1
                signed = True
            if exponent < size and _digit(bytes[exponent]):
                index = self._digits(text, exponent, "decimal", 10)
            elif signed:
                raise _token_error(
                    "invalid decimal literal",
                    self.row,
                    self.column(text, exponent),
                )
        if index < size and (bytes[index] | 0x20) == 0x6A:
            index += 1
        return index

    def tokens(mut self, text: String) raises -> List[Token]:
        """Return the source's tokens, without comments, newlines,
        indentation and the end marker.

        Args:
            text: The source, with newlines as LF.

        Returns:
            The tokens.

        Raises:
            Error: As `tokenize.TokenError` or `IndentationError`, for an
                unterminated string or statement, an invalid number or
                inconsistent indentation.
        """
        var bytes = text.as_bytes()
        var size = len(bytes)
        var result = List[Token]()
        var indents: List[Int] = [0]
        var alternates: List[Int] = [0]
        var line_begins = True
        var continued = False
        while True:
            if line_begins:
                line_begins = False
                if not continued:
                    # Python reads the indentation across line
                    # continuations; the first one sets the level.
                    var column = 0
                    var alternate = 0
                    var held = 0
                    var at = self.index
                    while at < size:
                        var byte = bytes[at]
                        if byte == 0x20:
                            column += 1
                            alternate += 1
                        elif byte == 0x09:
                            column = (column // 8 + 1) * 8
                            alternate += 1
                        elif byte == 0x0C:
                            column = 0
                            alternate = 0
                        elif byte == 0x5C:
                            if held == 0:
                                held = column
                            if at + 1 < size and bytes[at + 1] != 0x0A:
                                var finish = at
                                while finish < size and bytes[finish] != 0x0A:
                                    finish += 1
                                raise _token_error(
                                    (
                                        "unexpected character after line"
                                        " continuation character"
                                    ),
                                    self.row,
                                    _chars(text, self.segment_start, finish)
                                    + 1,
                                )
                            if at + 2 >= size:
                                raise _token_error(
                                    "unexpected EOF in multi-line statement",
                                    self.row,
                                    0,
                                )
                            self.newline(at + 1)
                            at += 2
                            continue
                        else:
                            break
                        at += 1
                    if held != 0:
                        column = held
                        alternate = held
                    var blank = (
                        at >= size or bytes[at] == 0x23 or bytes[at] == 0x0A
                    )
                    if not blank and self.depth == 0:
                        var top = indents[len(indents) - 1]
                        var alternate_top = alternates[len(alternates) - 1]
                        if column == top:
                            if alternate != alternate_top:
                                raise _indentation_error(
                                    (
                                        "inconsistent use of tabs and spaces in"
                                        " indentation"
                                    ),
                                    self.row,
                                )
                        elif column > top:
                            if alternate <= alternate_top:
                                raise _indentation_error(
                                    (
                                        "inconsistent use of tabs and spaces in"
                                        " indentation"
                                    ),
                                    self.row,
                                )
                            indents.append(column)
                            alternates.append(alternate)
                        else:
                            while (
                                len(indents) > 1
                                and column < indents[len(indents) - 1]
                            ):
                                _ = indents.pop()
                                _ = alternates.pop()
                            if column != indents[len(indents) - 1]:
                                raise _indentation_error(
                                    (
                                        "unindent does not match any outer"
                                        " indentation level"
                                    ),
                                    self.row,
                                )
                            if alternate != alternates[len(alternates) - 1]:
                                raise _indentation_error(
                                    (
                                        "inconsistent use of tabs and spaces in"
                                        " indentation"
                                    ),
                                    self.row,
                                )
                    self.index = at
                continued = False
            if self.index >= size:
                break
            var start = self.index
            var byte = bytes[start]
            if byte == 0x20 or byte == 0x09 or byte == 0x0C or byte == 0x0D:
                self.index += 1
                continue
            if byte == 0x23:
                while self.index < size and bytes[self.index] != 0x0A:
                    self.index += 1
                continue
            if byte == 0x0A:
                self.newline(start)
                self.index += 1
                line_begins = True
                continue
            if byte == 0x5C:
                if start + 1 < size and bytes[start + 1] != 0x0A:
                    var end = start
                    while end < size and bytes[end] != 0x0A:
                        end += 1
                    raise _token_error(
                        (
                            "unexpected character after line continuation"
                            " character"
                        ),
                        self.row,
                        _chars(text, self.segment_start, end) + 1,
                    )
                var after = start + 2
                if after >= size:
                    raise _token_error(
                        "unexpected EOF in multi-line statement",
                        self.row,
                        after - self.segment_start,
                    )
                self.newline(start + 1, continuation=True)
                self.index = after
                line_begins = True
                continued = True
                continue
            var column = self.column(text, start)
            var row = self.row
            if _name_start(byte):
                var end = start
                while end < size and (_word(bytes[end]) and bytes[end] != 0):
                    end += 1
                var word = _cut(text, start, end).lower()
                if (
                    end < size
                    and (bytes[end] == 0x22 or bytes[end] == 0x27)
                    and _contains(
                        ["r", "u", "b", "f", "br", "rb", "fr", "rf"], word
                    )
                ):
                    var finish = self.string_end(
                        text, start, end, formatted="f" in word
                    )
                    result.append(
                        Token(OTHER, _cut(text, start, finish), row, column)
                    )
                    self.index = finish
                    continue
                result.append(Token(NAME, _cut(text, start, end), row, column))
                self.index = end
                continue
            if _digit(byte) or (
                byte == 0x2E and start + 1 < size and _digit(bytes[start + 1])
            ):
                var end = self.number_end(text, start)
                result.append(Token(OTHER, _cut(text, start, end), row, column))
                self.index = end
                continue
            if byte == 0x22 or byte == 0x27:
                var finish = self.string_end(text, start, start)
                result.append(
                    Token(OTHER, _cut(text, start, finish), row, column)
                )
                self.index = finish
                continue
            if byte == 0x28 or byte == 0x5B or byte == 0x7B:
                self.depth += 1
            elif byte == 0x29 or byte == 0x5D or byte == 0x7D:
                self.depth = max(0, self.depth - 1)
            var width = 1
            if byte >= 0x80:
                while (
                    start + width < size
                    and (bytes[start + width] & 0xC0) == 0x80
                ):
                    width += 1
            result.append(
                Token(OP, _cut(text, start, start + width), row, column)
            )
            self.index = start + width
        if self.depth > 0:
            var lines = text.count("\n")
            if size > 0 and bytes[size - 1] != 0x0A:
                lines += 1
            raise _token_error(
                "unexpected EOF in multi-line statement", lines, 0
            )
        return result^


def source_tokens(source: String) raises -> List[Token]:
    """Return Mojo source's tokens, as Python's `tokenize` reads them.

    Comments, newlines, indentation and the end marker are left out. An
    f-string is one token here; it is not a Mojo form.

    Args:
        source: The source text. CR LF and CR count as LF, as Python's text
            files read them.

    Returns:
        The tokens.

    Raises:
        Error: As `tokenize.TokenError` or `IndentationError` writes it.
    """
    var text = source.replace("\r\n", "\n").replace("\r", "\n")
    var tokenizer = _Tokenizer()
    return tokenizer.tokens(text)


def module_kernels(module: String, source: String) raises -> List[String]:
    """Resolve every launch in one module, or refuse unsupported syntax.

    Args:
        module: The module's repository path, for messages.
        source: The module's text.

    Returns:
        The launched kernels, sorted.

    Raises:
        Error: For source that cannot be read or a launch that is not
            `enqueue_function[local_kernel](...)` of a top-level `def`.
    """
    # Mojo uses Python's comment, string and identifier spelling here.
    # Tokenization keeps examples in comments/docstrings out of discovery
    # and catches spaced or multiline launches without parsing Mojo types.
    var tokens: List[Token]
    try:
        tokens = source_tokens(source)
    except error:
        raise Error(
            module + ": unsupported kernel source syntax: " + String(error)
        )
    var definitions = Set[String]()
    for index in range(len(tokens) - 2):
        if (
            tokens[index].kind == NAME
            and tokens[index].text == "def"
            and tokens[index].column == 0
            and tokens[index + 1].kind == NAME
            and tokens[index + 2].text == "("
        ):
            definitions.add(tokens[index + 1].text)
    var launched = Set[String]()
    for index in range(len(tokens)):
        if (
            tokens[index].kind != NAME
            or tokens[index].text != "enqueue_function"
        ):
            continue
        var row = String(tokens[index].row)
        if (
            index + 4 >= len(tokens)
            or tokens[index + 1].text != "["
            or tokens[index + 2].kind != NAME
            or tokens[index + 3].text != "]"
            or tokens[index + 4].text != "("
        ):
            raise Error(
                module
                + ":"
                + row
                + ": unsupported enqueue_function syntax; expected"
                " enqueue_function[local_kernel](...)"
            )
        var name = tokens[index + 2].text
        if not name in definitions:
            raise Error(
                module
                + ":"
                + row
                + ": kernel "
                + name
                + " must have a local, non-parameterized top-level definition"
            )
        launched.add(name)
    var names = List[String]()
    for name in launched:
        names.append(name)
    sort(names)
    return names^


def default_modules() -> List[String]:
    """Return the modules that launch kernels.

    Returns:
        `MODULES`, in order.
    """
    var modules = List[String]()
    for module in materialize[MODULES]():
        modules.append(module)
    return modules^


def kernels(root: String, modules: List[String]) raises -> List[Kernel]:
    """Resolve every launch, or refuse syntax the emitter cannot compile.

    Args:
        root: The repository root.
        modules: The modules that launch kernels, relative to `root`.

    Returns:
        Each module's launched kernels, sorted, in module order.

    Raises:
        Error: For a missing module or unsupported launch syntax.
    """
    var out = List[Kernel]()
    for module in modules:
        var path = root + "/" + module
        if not exists(path):
            raise Error("[Errno 2] No such file or directory: " + py_repr(path))
        var text = Path(path).read_text()
        for name in module_kernels(module, text):
            out.append((module, name))
    return out^


# --- emission --------------------------------------------------------------------


def _label(kernel: Kernel) -> String:
    """Return a kernel's record label."""
    return kernel[0] + ":" + kernel[1]


def emitted_modules(
    stdout: String, found: List[Kernel]
) raises -> List[Tuple[String, String]]:
    """Require exactly one nonempty record for every expected kernel.

    Args:
        stdout: The emitting program's standard output.
        found: The discovered kernels.

    Returns:
        Each record's label and module, in output order.

    Raises:
        Error: For a missing, empty, repeated, unexpected or unbound record.
    """
    var expected = Set[String]()
    for kernel in found:
        expected.add(_label(kernel))
    if len(expected) == 0 or len(expected) != len(found):
        raise Error("kernel discovery is empty or contains duplicate entries")
    var records = List[Tuple[String, String]]()
    var seen = Set[String]()
    var symbols = Set[String]()
    var label = Optional[String]()
    var body = List[String]()
    var lines = split_lines(stdout)
    for index in range(len(lines) + 1):
        var finish = index == len(lines) or lines[index].startswith(SEPARATOR)
        if finish and label:
            var module = "\n".join(body)
            if strip(module).byte_length() == 0:
                raise Error("empty AIR record: " + label.value())
            var symbol = emitted_symbol(module)
            if symbol in symbols:
                raise Error(
                    "emitted entry reused across kernel records: " + symbol
                )
            symbols.add(symbol)
            seen.add(label.value())
            records.append((label.value(), module^))
        if index == len(lines):
            break
        var line = lines[index]
        if line.startswith(SEPARATOR):
            var name = _from(line, SEPARATOR.byte_length())
            if not name in expected:
                raise Error("unexpected AIR record: " + name)
            if name in seen:
                raise Error("duplicate AIR record: " + name)
            label = name
            body = List[String]()
        elif not label:
            if strip(line).byte_length() > 0:
                raise Error("unexpected output before first AIR record")
        else:
            body.append(line)
    var missing = List[String]()
    for name in expected:
        if not name in seen:
            missing.append(name)
    if len(missing) > 0:
        sort(missing)
        raise Error("missing AIR records: " + ", ".join(missing))
    return records^


def emitter_source(found: List[Kernel]) -> String:
    """Return the program that prints each kernel's AIR.

    Args:
        found: The discovered kernels.

    Returns:
        The program text.
    """
    var lines: List[String] = [
        "from max.gpu.host.compile import _compile_code, get_gpu_target"
    ]
    # Two modules can name a kernel alike, so each is imported by number.
    for index in range(len(found)):
        var module = found[index][0]
        var package = _cut(module, 0, module.byte_length() - 5).replace(
            "/", "."
        )
        lines.append(
            "from "
            + package
            + " import "
            + found[index][1]
            + " as kernel_"
            + String(index)
        )
    lines.append("")
    lines.append("")
    lines.append("def main() raises:")
    for index in range(len(found)):
        var number = String(index)
        lines.append(
            "    var compiled_"
            + number
            + " = _compile_code[kernel_"
            + number
            + ', emission_kind="asm", target = get_gpu_target["'
            + TARGET
            + '"]()]()'
        )
        lines.append('    print("' + SEPARATOR + _label(found[index]) + '")')
        lines.append(
            '    print("'
            + ENTRY
            + '" + String(compiled_'
            + number
            + ".function_name))"
        )
        lines.append("    print(compiled_" + number + ".asm)")
    return "\n".join(lines) + "\n"


def _list_repr(items: List[String]) -> String:
    """Return a list of strings as Python's `repr` writes it."""
    var quoted = List[String]()
    for item in items:
        quoted.append(py_repr(item))
    return "[" + ", ".join(quoted) + "]"


def _seconds_text(seconds: Float64) -> String:
    """Return a time limit as Python writes the number."""
    if seconds == Float64(Int(seconds)):
        return String(Int(seconds))
    return String(seconds)


def emit(
    root: String,
    mojo: String,
    found: List[Kernel],
    seconds: Float64 = Float64(EMIT_SECONDS),
) raises -> List[Tuple[String, String]]:
    """Return each kernel's AIR, from one generated program.

    Args:
        root: The repository root.
        mojo: The compiler, absolute.
        found: The discovered kernels.
        seconds: The program's time limit.

    Returns:
        Each record's label and module.

    Raises:
        Error: If nothing is discovered, the program fails or does not end
            in time, or its output is not one record for each kernel.
    """
    if len(found) == 0:
        raise Error("no kernels discovered")
    if not exists(mojo):
        raise Error("[Errno 2] No such file or directory: " + py_repr(mojo))
    var folder = mkdtemp(prefix="threemojo-air-")
    var program = folder + "/emit_air.mojo"
    var command: List[String] = [mojo, "run", "--Werror", "-I", root, program]
    var status: Int
    var output: String
    var errors: String
    var timed_out: Bool
    try:
        Path(program).write_text(emitter_source(found))
        var result = run_program(
            command, seconds, merge_errors=False, directory=root
        )
        status = result.status
        output = result.output
        errors = result.errors
        timed_out = result.timed_out
    finally:
        _ = run_program(["rm", "-rf", folder], 60)
    if timed_out:
        raise Error(
            "Command '"
            + _list_repr(command)
            + "' timed out after "
            + _seconds_text(seconds)
            + " seconds"
        )
    if status != 0:
        raise Error("AIR emission failed:\n" + _tail_chars(errors, 4000))
    return emitted_modules(output, found)


struct Outcome(Movable):
    """What a check printed and its exit status."""

    var status: Int
    """0 when every call matches, otherwise 1."""
    var output: String
    """The standard output."""
    var errors: String
    """The standard error."""

    def __init__(out self):
        """Make an empty outcome."""
        self.status = 0
        self.output = String()
        self.errors = String()


def check(
    root: String,
    mojo: String,
    modules: List[String],
    seconds: Float64 = Float64(EMIT_SECONDS),
) -> Outcome:
    """Discover, emit and check every kernel.

    Args:
        root: The repository root.
        mojo: The compiler, absolute.
        modules: The modules that launch kernels.
        seconds: The emitting program's time limit.

    Returns:
        The exit status and the text for the standard output and error.
    """
    var outcome = Outcome()
    var failed = 0
    var count: Int
    try:
        var found = kernels(root, modules)
        var records = emit(root, mojo, found, seconds)
        count = len(records)
        for record in records:
            var name = record[0]
            var colon = name.find(":")
            var kernel: Kernel = (_cut(name, 0, colon), _from(name, colon + 1))
            var bad: List[Mismatch]
            try:
                bad = mismatches(record[1], kernel)
            except error:
                raise Error(name + ": " + String(error))
            for item in bad:
                outcome.errors += (
                    name + ": call to " + item[0] + ": " + item[1] + "\n"
                )
            failed += len(bad)
    except error:
        outcome.errors += "AIR check failed: " + String(error) + "\n"
        outcome.status = 1
        return outcome^
    if failed:
        outcome.errors += (
            String(failed)
            + " call type mismatches; see modular/modular#7238. Give every"
            " device pointer an explicit address space (`DevicePointer` in"
            " render/gpu.mojo).\n"
        )
        outcome.status = 1
        return outcome^
    outcome.output = (
        "PASS "
        + String(count)
        + " Metal kernel AIR modules: supported direct-call types match"
        " definitions/declarations\n"
    )
    return outcome^


def main() raises:
    """Run the check, or print the help or a usage error.

    Raises:
        Error: If the command line cannot be read, or the check fails.
    """
    var arguments = List[String]()
    var given = argv()
    for index in range(1, len(given)):
        arguments.append(String(given[index]))
    var command = parse_command_line(
        arguments, PROGRAM, USAGE, HELP, List[String](), ["--mojo"]
    )
    if command.status == -1:
        print(command.message, end="")
        exit(0)
    if command.status != 0:
        print(command.message, end="", file=stderr)
        exit(command.status)
    var root = realpath(".")
    var mojo = absolute_path(command.value("--mojo", root + "/.venv/bin/mojo"))
    var outcome = check(root, mojo, default_modules())
    print(outcome.output, end="")
    print(outcome.errors, end="", file=stderr)
    exit(outcome.status)
