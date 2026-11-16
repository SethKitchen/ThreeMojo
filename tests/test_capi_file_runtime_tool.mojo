# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Check the no-files runtime for LLVM emitted on macOS and Linux.

The file section of `examples/capi/mwrt.c` is compiled as a host library.
Failed stat calls must not write either platform's stat layout. A missing
C compiler skips the check.
"""

from std.ffi import OwnedDLHandle, c_int, external_call
from std.pathlib import Path
from std.testing import TestSuite, assert_equal

from tests._tree import Tree
from tools._process import run_program


def _source() raises -> String:
    """Return the file section of the runtime, ready to compile.

    Returns:
        C source that defines the file stand-ins.

    Raises:
        Error: If the runtime source cannot be read.
    """
    var text = Path("examples/capi/mwrt.c").read_text()
    var marked = text.split("/* ---- 3. Files:")
    var until_tasks = String(marked[1]).split("/* ---- 4. TaskGroup")
    var chunk = String(until_tasks[0])
    var end = chunk.find("*/")
    return "#include <stdint.h>\n" + String(chunk[byte = end + 2 :])


def _library() raises -> Tree:
    """Compile the file stand-ins and return the tree that holds them.

    Returns:
        A tree whose `files.so` is the compiled section.

    Raises:
        Error: If the compiler is missing or the build fails.
    """
    var found = run_program(["sh", "-c", "command -v cc"], 5)
    if found.status != 0:
        raise Error("no cc")
    var compiler = String(found.output.split("\n")[0])
    var tree = Tree()
    tree.write("files.c", _source())
    var built = run_program(
        [
            compiler,
            "-shared",
            "-fPIC",
            tree.root + "/files.c",
            "-o",
            tree.root + "/files.so",
        ],
        10,
    )
    if built.status != 0:
        var message = built.output + built.errors
        tree.close()
        raise Error(message)
    return tree^


def test_both_errno_accessors_report_no_such_file() raises:
    var found = run_program(["sh", "-c", "command -v cc"], 5)
    if found.status != 0:
        print("SKIP (no cc): C ABI file runtime")
        return
    var tree = _library()
    var library = OwnedDLHandle(tree.root + "/files.so")
    var first = library.call["__error", Int]()
    var second = library.call["__errno_location", Int]()
    # Pointer refuses this host address, so copy the word with memcpy.
    var slot = List[UInt8](length=4, fill=0)
    _ = external_call["memcpy", OpaquePointer[MutAnyOrigin]](
        OpaquePointer[MutAnyOrigin](unsafe_from_address=Int(slot.unsafe_ptr())),
        OpaquePointer[MutAnyOrigin](unsafe_from_address=first),
        4,
    )
    assert_equal(Int(slot[0]), 2)
    _ = external_call["memcpy", OpaquePointer[MutAnyOrigin]](
        OpaquePointer[MutAnyOrigin](unsafe_from_address=Int(slot.unsafe_ptr())),
        OpaquePointer[MutAnyOrigin](unsafe_from_address=second),
        4,
    )
    assert_equal(Int(slot[0]), 2)
    assert_equal(first, second)
    tree.close()


def _untouched(buffer: List[UInt8], name: String) raises:
    """Require every byte of `buffer` to still be `0xA5`.

    Args:
        buffer: The stat output.
        name: The function under test.

    Raises:
        Error: If a byte changed.
    """
    for byte in buffer:
        assert_equal(Int(byte), 0xA5, name)


def _filled() -> List[UInt8]:
    """Return a 512-byte buffer filled with `0xA5`.

    Returns:
        The buffer.
    """
    return List[UInt8](length=512, fill=0xA5)


def test_stat_fails_without_writing_either_platform_layout() raises:
    var found = run_program(["sh", "-c", "command -v cc"], 5)
    if found.status != 0:
        print("SKIP (no cc): C ABI file runtime")
        return
    var tree = _library()
    var library = OwnedDLHandle(tree.root + "/files.so")
    var path = String("missing.spz")
    var buffer = _filled()
    assert_equal(
        Int(
            library.call["stat", c_int](
                path.as_c_string_span().ptr(),
                buffer.unsafe_ptr().unsafe_bitcast[NoneType](),
            )
        ),
        -1,
    )
    _untouched(buffer, "stat")
    assert_equal(
        Int(
            library.call["stat", c_int](
                path.as_c_string_span().ptr(),
                Int(0),
            )
        ),
        -1,
    )
    buffer = _filled()
    assert_equal(
        Int(
            library.call["lstat", c_int](
                path.as_c_string_span().ptr(),
                buffer.unsafe_ptr().unsafe_bitcast[NoneType](),
            )
        ),
        -1,
    )
    _untouched(buffer, "lstat")
    assert_equal(
        Int(
            library.call["lstat", c_int](
                path.as_c_string_span().ptr(),
                Int(0),
            )
        ),
        -1,
    )
    buffer = _filled()
    assert_equal(
        Int(
            library.call["__xstat", c_int](
                c_int(0),
                path.as_c_string_span().ptr(),
                buffer.unsafe_ptr().unsafe_bitcast[NoneType](),
            )
        ),
        -1,
    )
    _untouched(buffer, "__xstat")
    assert_equal(
        Int(
            library.call["__xstat", c_int](
                c_int(0),
                path.as_c_string_span().ptr(),
                Int(0),
            )
        ),
        -1,
    )
    buffer = _filled()
    assert_equal(
        Int(
            library.call["__lxstat", c_int](
                c_int(0),
                path.as_c_string_span().ptr(),
                buffer.unsafe_ptr().unsafe_bitcast[NoneType](),
            )
        ),
        -1,
    )
    _untouched(buffer, "__lxstat")
    assert_equal(
        Int(
            library.call["__lxstat", c_int](
                c_int(0),
                path.as_c_string_span().ptr(),
                Int(0),
            )
        ),
        -1,
    )
    tree.close()


def test_allocator_wraparound_and_large_angle_sine_stay_safe() raises:
    var found = run_program(["sh", "-c", "command -v cc"], 5)
    if found.status != 0:
        print("SKIP (no cc): C ABI allocator and trig runtime")
        return
    var compiler = String(found.output.split("\n")[0])
    var text = Path("examples/capi/mwrt.c").read_text()
    var until_files = String(text.split("/* ---- 3. Files:")[0])
    var harness = (
        "#include <math.h>\n#include <stdint.h>\n#include <stdio.h>\n"
        + "static size_t cur_pages = 2;\n"
        + "unsigned char __heap_base;\n"
        + "#define __builtin_wasm_memory_size(x) cur_pages\n"
        + "#define __builtin_wasm_memory_grow(x, p) ((size_t)-1)\n"
        + until_files.replace("extern unsigned char __heap_base;", "")
        .replace("double sin(double x)", "double mw_sin(double x)")
        .replace("double cos(double x)", "double mw_cos(double x)")
        .replace("sin((double)x)", "mw_sin((double)x)")
        .replace("cos((double)x)", "mw_cos((double)x)")
        + "\nint main(void) {\n"
        + "  if (KGEN_CompilerRT_AlignedAlloc(16, (uint64_t)-8) != 0) return"
        " 1;\n"
        + "  if (KGEN_CompilerRT_AlignedAlloc(0, 16) != 0) return 2;\n"
        + "  if (KGEN_CompilerRT_AlignedAlloc(24, 16) != 0) return 3;\n"
        + "  if (KGEN_CompilerRT_AlignedAlloc(64, (uint64_t)-64) != 0) return"
        " 4;\n"
        + "  if (KGEN_CompilerRT_AlignedAlloc(64, 0xFFFFFFC0u) != 0) return"
        " 5;\n"
        + "  double xs[6] = {1e10, 1e18, 1e20, -1e30, 1e150, 1e300};\n"
        + "  for (int i = 0; i < 6; i++) {\n"
        + "    if (fabs(mw_sin(xs[i]) - sin(xs[i])) > 1e-14) return 6;\n"
        + "    if (fabs(mw_cos(xs[i]) - cos(xs[i])) > 1e-14) return 7;\n"
        + "  }\n"
        + "  return 0;\n"
        + "}\n"
    )
    var tree = Tree()
    tree.write("mwrt_check.c", harness)
    var built = run_program(
        [
            compiler,
            "-O2",
            "-ffp-contract=off",
            tree.root + "/mwrt_check.c",
            "-lm",
            "-o",
            tree.root + "/mwrt_check",
        ],
        10,
    )
    if built.status != 0:
        var msg = built.output + built.errors
        tree.close()
        raise Error(msg)
    var ran = run_program([tree.root + "/mwrt_check"], 5)
    tree.close()
    assert_equal(ran.status, 0, ran.output + ran.errors)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
