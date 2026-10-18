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
"""
import re
import subprocess
import sys

TRIPLE = "wasm32-unknown-unknown"


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
