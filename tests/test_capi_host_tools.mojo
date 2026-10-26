# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""The C ABI host tools run as Mojo: PPM compare, wasm32 retarget, the page
server and the Metal C string.
"""

from std.ffi import c_int, external_call
from std.memory import bitcast
from std.pathlib import Path
from std.testing import (
    TestSuite,
    assert_equal,
    assert_false,
    assert_raises,
    assert_true,
)

from tools.capi_compare_ppm import (
    compare_command,
    compare_frames,
    fixed_decimal,
    read_ppm,
)
from tools.capi_metal_string import metal_command, metal_header
from tools.capi_retarget import (
    exact_float,
    exact_floats,
    float_bits,
    replace_shuffle,
    retarget_command,
    retarget_ir,
    wasm_layout,
)
from tools.capi_serve import (
    http_response,
    listen_local,
    serve_command,
    serve_once,
)
from tests._tree import Tree
from tools._python_float import parse_float
from tools._sha256 import sha256_hex


def _pointer(address: Int) -> OpaquePointer[MutAnyOrigin]:
    """Return an address as a C pointer."""
    return OpaquePointer[MutAnyOrigin](unsafe_from_address=address)


def _ppm(path: String, width: Int, height: Int, pixels: List[UInt8]) raises:
    """Write a binary P6 file."""
    var header = "P6\n" + String(width) + " " + String(height) + "\n255\n"
    var data = List[UInt8]()
    for byte in header.as_bytes():
        data.append(byte)
    for byte in pixels:
        data.append(byte)
    Path(path).write_bytes(Span(data))


def _bytes(text: String) -> List[UInt8]:
    """Return the bytes of a string."""
    var data = List[UInt8]()
    for byte in text.as_bytes():
        data.append(byte)
    return data^


def _text(data: List[UInt8]) -> String:
    """Return bytes as text."""
    return String(from_utf8_lossy=data)


def _body(response: List[UInt8]) -> String:
    """Return the body after the HTTP header."""
    var end = 0
    while end + 3 < len(response):
        if (
            response[end] == 13
            and response[end + 1] == 10
            and response[end + 2] == 13
            and response[end + 3] == 10
        ):
            var rest = List[UInt8]()
            for index in range(end + 4, len(response)):
                rest.append(response[index])
            return _text(rest)
        end += 1
    return String()


def test_fixed_decimal_matches_python_format() raises:
    var rows = [
        "0",
        "0.0",
        "0.1",
        "1.23456",
        "1.25",
        "1.35",
        "2.5",
        "3.5",
        "12.5",
        "255.0",
        "0.00049",
        "0.00051",
        "2.675",
        "1.005",
        "0.0005",
        "0.00005",
        "9.9999",
        "-1.25",
        "-1e-10",
        "-0.00005",
        "123456.789",
    ]
    var places = [0, 1, 3, 4]
    var expected = [
        "0",
        "0.0",
        "0.000",
        "0.0000",
        "0",
        "0.0",
        "0.000",
        "0.0000",
        "0",
        "0.1",
        "0.100",
        "0.1000",
        "1",
        "1.2",
        "1.235",
        "1.2346",
        "1",
        "1.2",
        "1.250",
        "1.2500",
        "1",
        "1.4",
        "1.350",
        "1.3500",
        "2",
        "2.5",
        "2.500",
        "2.5000",
        "4",
        "3.5",
        "3.500",
        "3.5000",
        "12",
        "12.5",
        "12.500",
        "12.5000",
        "255",
        "255.0",
        "255.000",
        "255.0000",
        "0",
        "0.0",
        "0.000",
        "0.0005",
        "0",
        "0.0",
        "0.001",
        "0.0005",
        "3",
        "2.7",
        "2.675",
        "2.6750",
        "1",
        "1.0",
        "1.005",
        "1.0050",
        "0",
        "0.0",
        "0.001",
        "0.0005",
        "0",
        "0.0",
        "0.000",
        "0.0001",
        "10",
        "10.0",
        "10.000",
        "9.9999",
        "-1",
        "-1.2",
        "-1.250",
        "-1.2500",
        "-0",
        "-0.0",
        "-0.000",
        "-0.0000",
        "-0",
        "-0.0",
        "-0.000",
        "-0.0001",
        "123457",
        "123456.8",
        "123456.789",
        "123456.7890",
    ]
    var cursor = 0
    for text in rows:
        var value = parse_float(text)
        for place in places:
            assert_equal(fixed_decimal(value, place), expected[cursor], text)
            cursor += 1
    var negative_zero = bitcast[DType.float64](UInt64(1) << 63)
    assert_equal(fixed_decimal(negative_zero, 4), "-0.0000")
    assert_equal(fixed_decimal(negative_zero, 0), "-0")
    with assert_raises():
        _ = fixed_decimal(Float64.MAX * 2, 1)


def test_compare_reports_pass_and_failure() raises:
    var tree = Tree()
    var left = tree.root + "/left.ppm"
    var right = tree.root + "/right.ppm"
    _ppm(left, 1, 1, [0, 0, 0])
    _ppm(right, 1, 1, [0, 2, 0])
    var same = read_ppm(left)
    var other = read_ppm(right)
    var passed = compare_frames(same, other, 1.0, 2, 1.0)
    assert_equal(passed[0], 0)
    assert_equal(passed[1], "1x1: mean 0.6667, worst 2, 0.000% over 2")
    var failed = compare_frames(same, other, 0.1, 1, 0.0)
    assert_equal(failed[0], 1)
    assert_true(failed[1].startswith("1x1: mean 0.6667"))
    assert_equal(
        compare_command([left, right, "1", "2", "1"]),
        0,
    )
    assert_equal(compare_command([left, right, "0", "0", "0"]), 1)
    assert_equal(compare_command(["only-one"]), 1)
    assert_equal(compare_command([left, right, "nope", "1", "0"]), 1)
    assert_equal(
        compare_command([tree.root + "/missing.ppm", right, "1", "1", "1"]), 1
    )
    with assert_raises(contains="sizes differ"):
        var wide = tree.root + "/wide.ppm"
        _ppm(wide, 2, 1, [0, 0, 0, 0, 0, 0])
        _ = compare_frames(same, read_ppm(wide), 1.0, 1, 1.0)
    var bad = tree.root + "/bad.ppm"
    Path(bad).write_text("P5\n1 1\n255\nxxx")
    with assert_raises(contains="not a P6 PPM"):
        _ = read_ppm(bad)
    Path(bad).write_text("P6\n1 1\n255\n")
    with assert_raises(contains="not 3"):
        _ = read_ppm(bad)
    tree.close()


def test_retarget_matches_the_python_rewrites() raises:
    var source = (
        'target datalayout = "e-m:e-p270:32:32-p271:32:32"\n'
        'target triple = "x86_64-unknown-linux-gnu"\n'
        "define void @f() {\n"
        "  %slot = alloca { ptr }, align 8\n"
        "  %nested = alloca { { ptr } }, align 8\n"
        "  %plain = alloca ptr, align 8\n"
        "  ret void\n"
        "}\n"
        'attributes #0 = { "target-cpu"="x86-64" '
        '"target-features"="+cx16,+sahf" }\n'
        "attributes #1 = { }\n"
        'attributes #2 = { nounwind "target-features"="+cx16" }\n'
        'attributes #3 = { "target-features"="+cx16" nounwind }\n'
    )
    var expected = (
        'target datalayout = "e-m:e-p:32:32-i64:64"\n'
        'target triple = "wasm32-unknown-unknown"\n'
        "define void @f() {\n"
        "  %slot = alloca i64, align 8\n"
        "  store i64 0, ptr %slot, align 8\n"
        "  %nested = alloca i64, align 8\n"
        "  store i64 0, ptr %nested, align 8\n"
        "  %plain = alloca ptr, align 8\n"
        "  ret void\n"
        "}\n"
        "attributes #0 = { nounwind }\n"
        "attributes #1 = { nounwind }\n"
        "attributes #2 = { nounwind }\n"
        "attributes #3 = { nounwind }\n"
    )
    assert_equal(retarget_ir(source, "e-m:e-p:32:32-i64:64"), expected)
    var quoted = retarget_ir('target datalayout = "old"\n', 'layout"quote')
    assert_equal(quoted, 'target datalayout = "layout"quote"\n')
    var untouched = (
        '  %no = alloca {ptr}, align 8\nnot a target datalayout = "no"\n'
    )
    assert_equal(retarget_ir(untouched, "unused"), untouched)


def test_retarget_writes_float_constants_an_older_llvm_reads() raises:
    # Each pair is a line and the Python script's rewrite of it.
    var cases: List[String] = [
        "  %3 = fmul contract float %2, 1.000000e-03",
        "  %3 = fmul contract float %2, 0x3F50624DE0000000",
        "  %c = fcmp olt float %a, 3.000000e-01",
        "  %c = fcmp olt float %a, 0x3FD3333340000000",
        "  %c = fcmp fast olt float %a, 3.000000e-01",
        "  %c = fcmp fast olt float %a, 3.000000e-01",
        (
            "  %p = phi float [ 1.000000e-01, %b0 ], [ -2.500000e-01, %b1 ],"
            " [ 7.000000e-01, %b2 ]"
        ),
        (
            "  %p = phi float [ 0x3FB99999A0000000, %b0 ], [ -2.500000e-01,"
            " %b1 ], [ 0x3FE6666660000000, %b2 ]"
        ),
        "  %d = fadd double %a, 1.000000e-01",
        "  %d = fadd double %a, 1.000000e-01",
        "  %v = fadd fast float %a, f0x3F3504F3",
        "  %v = fadd fast float %a, 0x3FE6A09E60000000",
        "  ret double f0x3FF0000000000000",
        "  ret double 0x3FF0000000000000",
        "  %x = select i1 %c, float +inf, float -inf",
        (
            "  %x = select i1 %c, float 0x7FF0000000000000, float"
            " 0xFFF0000000000000"
        ),
        "  %q = fadd double %a, -qnan",
        "  %q = fadd double %a, 0xFFF8000000000000",
        "  call void @f(float +nan(0x2), double -nan(0x3), float +snan(0x4))",
        (
            "  call void @f(float 0x7FF8000040000000, double"
            " 0xFFF8000000000003, float 0x7FF0000080000000)"
        ),
        (
            "  call void @g(ptr @s, float 1.000000e-01)"
            ' "fn-attr"="1.000000e-01" float 3.000000e-01'
        ),
        (
            "  call void @g(ptr @s, float 0x3FB99999A0000000)"
            ' "fn-attr"="1.000000e-01" float 0x3FD3333340000000'
        ),
        "  %w = fmul fastmath float %x, 2.000000e-01",
        "  %w = fmul fastmath float %x, 2.000000e-01",
        "x.+inf a+inf +infinity -inf) (+qnan,",
        "x.+inf a+inf +infinity 0xFFF0000000000000) (0x7FF8000000000000,",
        "f0x123 af0x3F3504F3 .f0x3F3504F3 f0x3F3504F3a f0x3FF00000000000001",
        (
            "f0x123 af0x3F3504F3 .0x3FE6A09E60000000 f0x3F3504F3a"
            " f0x3FF00000000000001"
        ),
        "  %u = fsub float 3.402823e+38, 1.175494e-38",
        "  %u = fsub float 0x47EFFFFFA0000000, 0x380FFFFF40000000",
        "  %b = fadd float %a, 1.000000e-03 ; = fmul float 2.000000e-01",
        (
            "  %b = fadd float %a, 0x3F50624DE0000000 ; = fmul float"
            " 0x3FC99999A0000000"
        ),
    ]
    for index in range(0, len(cases), 2):
        assert_equal(exact_floats(cases[index]), cases[index + 1])
    assert_equal(exact_float("1.500000e+00"), "1.500000e+00")
    assert_equal(exact_float("-1.234567e+08"), "0xC19D6F3300000000")
    assert_equal(float_bits("3F3504F3"), "0x3FE6A09E60000000")


def test_retarget_swaps_the_x86_byte_shuffle_for_a_swizzle() raises:
    var source = (
        "declare <16 x i8> @llvm.x86.ssse3.pshuf.b.128(<16 x i8>, <16 x i8>)\n"
        "  %r = call <16 x i8> @llvm.x86.ssse3.pshuf.b.128(<16 x i8> %a,"
        " <16 x i8> %b)\n"
    )
    var shuffled = replace_shuffle(source)
    assert_true(shuffled.startswith("\n  %r = call <16 x i8> @tm_pshufb("))
    assert_true(shuffled.find("@llvm.x86.ssse3.pshuf.b.128") < 0)
    assert_true(
        shuffled.endswith(
            "declare <16 x i8> @llvm.wasm.swizzle(<16 x i8>, <16 x i8>)\n"
        )
    )
    assert_true(shuffled.find("splat (i8 -113)") > 0)
    assert_equal(replace_shuffle("no shuffle\n"), "no shuffle\n")


def _chmod(path: String) raises:
    """Mark a file executable."""
    var bytes = _c_path(path)
    var result = external_call["chmod", c_int](
        _pointer(Int(bytes.unsafe_ptr())), c_int(0o755)
    )
    if result != 0:
        raise Error("chmod failed")


def _clang(tree: Tree, script: String) raises -> String:
    """Write an executable stand-in clang and return its path."""
    var path = tree.root + "/clang"
    Path(path).write_text("#!/bin/sh\n" + script)
    _chmod(path)
    return path


def test_wasm_layout_reads_clang() raises:
    var tree = Tree()
    var clang = _clang(
        tree, "printf '%s\\n' 'target datalayout = \"from-clang\"'\n"
    )
    assert_equal(wasm_layout(clang), "from-clang")
    tree.close()


def test_wasm_layout_refuses_a_compiler_without_a_layout() raises:
    var tree = Tree()
    var clang = _clang(tree, "echo 'no layout here'\n")
    with assert_raises(contains="no data layout"):
        _ = wasm_layout(clang)
    tree.close()


def test_wasm_layout_refuses_a_failing_compiler() raises:
    var tree = Tree()
    var clang = _clang(tree, "echo fail >&2\nexit 3\n")
    with assert_raises(contains="clang failed"):
        _ = wasm_layout(clang)
    tree.close()


def test_retarget_command_writes_the_module() raises:
    var tree = Tree()
    var clang = _clang(
        tree, "printf '%s\\n' 'target datalayout = \"layout\"'\n"
    )
    var source = tree.root + "/in.ll"
    var target = tree.root + "/out.ll"
    Path(source).write_text('target triple = "host"\n')
    assert_equal(retarget_command([clang, source, target]), 0)
    assert_true(Path(target).read_text().find("wasm32-unknown-unknown") > 0)
    assert_equal(retarget_command([clang]), 1)
    tree.close()


def _c_path(path: String) -> List[UInt8]:
    """Return a NUL-terminated path."""
    var data = List[UInt8]()
    for byte in path.as_bytes():
        data.append(byte)
    data.append(0)
    return data^


def test_metal_header_escapes_and_matches_the_shader() raises:
    var header = metal_header('line "a"\nback\\slash\n')
    assert_equal(
        header,
        (
            "/* Made by build.sh from splat.metal. */\n"
            "static const char SPLAT_MSL[] =\n"
            '    "line \\"a\\"\\n"\n'
            '    "back\\\\slash\\n"\n'
            ";\n"
        ),
    )
    var real = metal_header(Path("examples/capi/splat.metal").read_text())
    assert_equal(
        sha256_hex(real.as_bytes()),
        "094321625d65a38e708e1fa17871bbc16026114fba49344a1812e1ef1e228790",
    )
    var tree = Tree()
    var source = tree.root + "/splat.metal"
    var out = tree.root + "/splat_msl.h"
    Path(source).write_text("void f() {}\n")
    assert_equal(metal_command([source, out]), 0)
    assert_true(Path(out).read_text().find("void f() {}") > 0)
    assert_equal(metal_command([source]), 1)
    tree.close()


def test_http_serves_files_and_refuses_the_rest() raises:
    var tree = Tree()
    tree.write("index.html", "<p>home</p>\n")
    tree.write("app.wasm", "wasm-bytes")
    tree.write("dir/index.html", "nested\n")
    tree.write("note.txt", "hello\n")
    var outside_tree = Tree()
    var outside = outside_tree.root + "/secret.txt"
    Path(outside).write_text("secret\n")
    var escape = tree.root + "/escape"
    var from_path = _c_path(outside)
    var to_path = _c_path(escape)
    _ = external_call["symlink", c_int](
        _pointer(Int(from_path.unsafe_ptr())),
        _pointer(Int(to_path.unsafe_ptr())),
    )

    var home = http_response(tree.root, _bytes("GET / HTTP/1.1\r\n\r\n"))
    var home_text = _text(home)
    assert_true(home_text.startswith("HTTP/1.1 200 OK\r\n"))
    assert_true(
        home_text.find("Cross-Origin-Opener-Policy: same-origin\r\n") > 0
    )
    assert_true(
        home_text.find("Cross-Origin-Embedder-Policy: require-corp\r\n") > 0
    )
    assert_true(home_text.find("Cache-Control: no-store\r\n") > 0)
    assert_true(home_text.find("Content-Type: text/html\r\n") > 0)
    assert_equal(_body(home), "<p>home</p>\n")
    var wasm = http_response(
        tree.root, _bytes("GET /app.wasm?x=1 HTTP/1.1\r\nHost: t\r\n\r\n")
    )
    assert_true(_text(wasm).find("Content-Type: application/wasm\r\n") > 0)
    assert_equal(_body(wasm), "wasm-bytes")
    var head = http_response(
        tree.root, _bytes("HEAD /note.txt HTTP/1.0\r\n\r\n")
    )
    assert_true(_text(head).startswith("HTTP/1.1 200 OK\r\n"))
    assert_true(_text(head).find("Content-Type: text/plain\r\n") > 0)
    assert_equal(_body(head), "")
    assert_true(_text(head).find("Content-Length: 6\r\n") > 0)
    var moved = http_response(
        tree.root, _bytes("GET /dir?q=1 HTTP/1.1\r\n\r\n")
    )
    assert_true(_text(moved).startswith("HTTP/1.1 301 Moved Permanently\r\n"))
    assert_true(_text(moved).find("Location: /dir/?q=1\r\n") > 0)
    var nested = http_response(tree.root, _bytes("GET /dir/ HTTP/1.1\r\n\r\n"))
    assert_equal(_body(nested), "nested\n")
    var missing = http_response(tree.root, _bytes("GET /nope HTTP/1.1\r\n\r\n"))
    assert_true(_text(missing).startswith("HTTP/1.1 404 Not Found\r\n"))
    var climb = http_response(
        tree.root, _bytes("GET /../secret.txt HTTP/1.1\r\n\r\n")
    )
    assert_true(
        _text(climb).startswith("HTTP/1.1 404 Not Found\r\n"), _text(climb)
    )
    assert_false(_body(climb).find("secret") >= 0)
    var escaped = http_response(
        tree.root, _bytes("GET /escape HTTP/1.1\r\n\r\n")
    )
    assert_true(_text(escaped).startswith("HTTP/1.1 404 Not Found\r\n"))
    var encoded = http_response(
        tree.root, _bytes("GET /%2e%2e/secret.txt HTTP/1.1\r\n\r\n")
    )
    assert_true(_text(encoded).startswith("HTTP/1.1 404 Not Found\r\n"))
    var bad = http_response(tree.root, _bytes("NOT / HTTP/1.1\r\n\r\n"))
    assert_true(_text(bad).startswith("HTTP/1.1 405 Method Not Allowed\r\n"))
    var broken = http_response(tree.root, _bytes("GET /\r\n"))
    assert_true(_text(broken).startswith("HTTP/1.1 400 Bad Request\r\n"))
    var js = http_response(tree.root, _bytes("GET /app.mjs HTTP/1.1\r\n\r\n"))
    assert_true(_text(js).startswith("HTTP/1.1 404 Not Found\r\n"))
    tree.close()
    outside_tree.close()


def _connect_local(port: Int) raises -> Int:
    """Connect to 127.0.0.1 and return the socket."""
    var fd = Int(external_call["socket", c_int](c_int(2), c_int(1), c_int(0)))
    if fd < 0:
        raise Error("socket failed")
    var addr = List[UInt8](length=16, fill=0)
    addr[0] = 2
    addr[2] = UInt8((port >> 8) & 255)
    addr[3] = UInt8(port & 255)
    addr[4] = 127
    addr[7] = 1
    if (
        external_call["connect", c_int](
            c_int(fd), _pointer(Int(addr.unsafe_ptr())), c_int(16)
        )
        != 0
    ):
        raise Error("connect failed")
    return fd


def _socket_write(fd: Int, text: String) raises:
    """Write one small request."""
    var data = _bytes(text)
    var count = external_call["write", Int](
        Int32(fd), _pointer(Int(data.unsafe_ptr())), len(data)
    )
    if count != len(data):
        raise Error("short socket write")


def _socket_read(fd: Int) raises -> String:
    """Read until the peer closes."""
    var data = List[UInt8]()
    var chunk = List[UInt8](length=4096, fill=0)
    while True:
        var count = external_call["read", Int](
            Int32(fd), _pointer(Int(chunk.unsafe_ptr())), len(chunk)
        )
        if count < 0:
            raise Error("socket read failed")
        if count == 0:
            break
        for index in range(count):
            data.append(chunk[index])
    return _text(data)


def test_one_connection_serves_index() raises:
    var tree = Tree()
    tree.write("index.html", "page\n")
    var server = listen_local(0)
    assert_true(server.port > 0)
    var client = _connect_local(server.port)
    _socket_write(client, "GET / HTTP/1.1\r\nHost: t\r\n\r\n")
    serve_once(server.fd, tree.root)
    var got = _socket_read(client)
    _ = external_call["close", c_int](c_int(client))
    server.close()
    assert_true(got.find("HTTP/1.1 200 OK") >= 0, got)
    assert_true(got.find("page\n") > 0)
    assert_true(got.find("Cross-Origin-Opener-Policy: same-origin") > 0)
    assert_equal(serve_command([".", "nope"]), 2)
    tree.close()


def test_shell_scripts_call_the_mojo_tools() raises:
    var build = Path("examples/capi/build.sh").read_text()
    var run = Path("examples/capi/run.sh").read_text()
    assert_true(build.find("tools/capi_retarget.mojo") > 0)
    assert_true(build.find("tools/capi_metal_string.mojo") > 0)
    assert_false(build.find("retarget.py") >= 0)
    assert_true(run.find("tools/capi_serve.mojo") > 0)
    assert_true(run.find("tools/capi_compare_ppm.mojo") > 0)
    assert_false(run.find("serve.py") >= 0)
    assert_false(run.find("compare_ppm.py") >= 0)


def test_the_capi_host_tools_live_in_tools() raises:
    # A Mojo file in examples/capi is linted as a program, and a program
    # there would make examples/capi an entry directory. Each tool and its
    # main are in tools/ instead.
    for name in ["compare_ppm", "metal_string", "retarget", "serve"]:
        assert_false(Path("examples/capi/" + name + ".mojo").exists(), name)
        var tool = Path("tools/capi_" + name + ".mojo").read_text()
        assert_true(tool.find("\ndef main(") >= 0, name)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
