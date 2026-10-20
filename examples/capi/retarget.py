# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.
"""Retarget the LLVM IR that Mojo writes for the host to wasm32.

Mojo 1.1 has no WebAssembly backend, but `mojo build --emit llvm` writes plain
LLVM IR. This script swaps the module's data layout and triple for those of
wasm32 and drops the host CPU attributes, so that a stock clang can compile
the module. Use it like this:

    retarget.py CLANG IN.ll OUT.ll

The module must not use threads, lists, strings or errors, because
`mwrt.c` does not supply the runtime they need.

Mojo's LLVM is newer than any release of clang, and writes floating-point
constants in ways that an older reader refuses: a decimal that is not exactly a
float, such as `1.000000e-03`, which it rounds to the nearest float; a float's
or a double's own bits, such as `f0x3F3504F3`; infinities and quiet NaNs as
`+inf`, `-inf`, `+qnan` and `-qnan`; and a NaN with a payload as
`+nan(0x...)`, or `+snan(0x...)` for a signaling one. This script writes each
of them as the hexadecimal double of that number, which every LLVM reads as the
same number.

The IR is written for the host, so the standard library's UTF-8 check can call
an x86 byte shuffle, `llvm.x86.ssse3.pshuf.b.128`. The script gives the module
a function that does the same with WebAssembly's swizzle: a byte whose top bit
is set gives zero, and any other byte picks by its low four bits.
"""
import re
import struct
import subprocess
import sys

TRIPLE = "wasm32-unknown-unknown"
# A decimal constant as LLVM writes one.
DECIMAL = r"-?\d+\.\d+e[+-]\d+"
# An instruction whose operands take their type from it, such as
# `fmul contract float %a, 1.0e-03`, up to its first operand.
FLOAT_INSTRUCTION = re.compile(
    r"= (?:fadd|fsub|fmul|fdiv|frem|fcmp \w+|phi)"
    r"(?: (?:fast|contract|reassoc|nnan|ninf|nsz|arcp|afn))* float "
)


def exact_float(decimal: str) -> str:
    """Return a `float` constant that LLVM reads as the nearest float."""
    value = float(decimal)
    nearest = struct.unpack("<f", struct.pack("<f", value))[0]
    if nearest == value:
        return decimal
    return "0x%016X" % struct.unpack("<Q", struct.pack("<d", nearest))[0]


def float_bits(bits: str) -> str:
    """Return the hexadecimal double of a float given by its 32 bits."""
    value = struct.unpack("<f", struct.pack("<I", int(bits, 16)))[0]
    return "0x%016X" % struct.unpack("<Q", struct.pack("<d", value))[0]


# The hexadecimal doubles of the named numbers.
SPECIAL = {
    "+inf": "0x7FF0000000000000",
    "-inf": "0xFFF0000000000000",
    "+qnan": "0x7FF8000000000000",
    "-qnan": "0xFFF8000000000000",
}


def nan_bits(line: str, at: int, sign: str, quiet: bool, payload: str) -> str:
    """Return the hexadecimal double of a NaN with a payload, whose type is
    the last `float` or `double` before it on the line."""
    types = re.findall(r"\b(float|double)\b", line[:at])
    bits = (1 << 63 if sign == "-" else 0) | 0x7FF0000000000000
    if types and types[-1] == "float":
        bits |= (int(payload, 16) | (1 << 22 if quiet else 0)) << 29
    else:
        bits |= int(payload, 16) | (1 << 51 if quiet else 0)
    return "0x%016X" % bits


def exact_floats(line: str) -> str:
    """Rewrite the floating-point constants of one line of IR, outside its
    strings."""
    if '"' in line:
        parts = line.split('"')
        parts[::2] = [exact_floats(part) for part in parts[::2]]
        return '"'.join(parts)
    line = re.sub(
        r"(?<![\w.])([+-])(s?)nan\((0x[0-9A-Fa-f]+)\)",
        lambda m: nan_bits(line, m.start(), m.group(1), m.group(2) == "", m.group(3)),
        line,
    )
    line = re.sub(r"(?<![\w.])[+-](?:inf|qnan)\b", lambda m: SPECIAL[m.group(0)], line)
    line = re.sub(r"\bf0x([0-9A-Fa-f]{16})\b", r"0x\1", line)
    line = re.sub(r"\bf0x([0-9A-Fa-f]{8})\b", lambda m: float_bits(m.group(1)), line)
    line = re.sub(r"(?<=float )" + DECIMAL, lambda m: exact_float(m.group(0)), line)
    found = FLOAT_INSTRUCTION.search(line)
    if found:
        rest = re.sub(r"(?<![\w.])" + DECIMAL, lambda m: exact_float(m.group(0)), line[found.end() :])
        line = line[: found.end()] + rest
    return line


PSHUFB = "@llvm.x86.ssse3.pshuf.b.128"
# The same shuffle on WebAssembly: 0x8F keeps the top bit, which takes the
# index past 15 so that the swizzle gives zero, and the low four bits.
SWIZZLE = """
define internal <16 x i8> @tm_pshufb(<16 x i8> %table, <16 x i8> %index) {
  %kept = and <16 x i8> %index, splat (i8 -113)
  %bytes = call <16 x i8> @llvm.wasm.swizzle(<16 x i8> %table, <16 x i8> %kept)
  ret <16 x i8> %bytes
}

declare <16 x i8> @llvm.wasm.swizzle(<16 x i8>, <16 x i8>)
"""


def replace_shuffle(text: str) -> str:
    """Call `tm_pshufb` where the module calls the x86 byte shuffle."""
    if PSHUFB not in text:
        return text
    text = re.sub(r"^declare <16 x i8> " + re.escape(PSHUFB) + r"\(.*$", "", text, flags=re.M)
    return text.replace(PSHUFB, "@tm_pshufb") + SWIZZLE


def wasm_layout(clang: str) -> str:
    """Ask clang for the data layout of wasm32."""
    out = subprocess.run(
        [clang, f"--target={TRIPLE}", "-S", "-emit-llvm", "-x", "c", "/dev/null", "-o", "-"],
        check=True,
        capture_output=True,
        text=True,
    ).stdout
    match = re.search(r'^target datalayout = "([^"]*)"', out, re.M)
    if match is None:
        raise SystemExit("clang printed no data layout for " + TRIPLE)
    return match.group(1)


def retarget(text: str, layout: str) -> str:
    """Return the IR of `text` for wasm32."""
    text = re.sub(r'^target datalayout = ".*"$', f'target datalayout = "{layout}"', text, flags=re.M)
    text = re.sub(r'^target triple = ".*"$', f'target triple = "{TRIPLE}"', text, flags=re.M)
    text = re.sub(r'"target-cpu"="[^"]*"\s*', "", text)
    text = re.sub(r'"target-features"="[^"]*"\s*', "", text)
    # Mojo's IR returns an optional pointer by storing a struct that holds one
    # pointer, and then loading its first 8 bytes as an i64. A pointer is 4
    # bytes on wasm32, so the load reads 4 bytes of whatever was on the stack.
    # Give the slot 8 bytes, and clear them first.
    text = re.sub(
        r"^(\s*)(%[\w.]+) = alloca (?:\{ )+ptr(?: \})+, align 8$",
        r"\1\2 = alloca i64, align 8\n\1store i64 0, ptr \2, align 8",
        text,
        flags=re.M,
    )
    text = "\n".join(exact_floats(line) for line in text.split("\n"))
    text = replace_shuffle(text)
    # A group that the strip left empty is not valid IR.
    return re.sub(r"^(attributes #\d+ = \{)\s*\}$", r"\1 nounwind }", text, flags=re.M)


def main(clang: str, source: str, target: str) -> None:
    with open(source) as handle:
        text = handle.read()
    with open(target, "w") as handle:
        handle.write(retarget(text, wasm_layout(clang)))


if __name__ == "__main__":
    if len(sys.argv) != 4:
        raise SystemExit(__doc__)
    main(sys.argv[1], sys.argv[2], sys.argv[3])
