# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Check the AIR call checker against small hand-written modules.

The command-line checks run no compiler: a shell script stands in for
`mojo` and prints a fixed result.
"""

from std.os.path import realpath
from std.pathlib import Path
from std.testing import (
    TestSuite,
    assert_equal,
    assert_false,
    assert_raises,
    assert_true,
)

from tests._tree import Tree
from tools._cli import parse_command_line
from tools._process import run_program
from tools.check_air_calls import (
    ENTRY,
    SEPARATOR,
    Kernel,
    Mismatch,
    check,
    default_modules,
    emit,
    emitted_modules,
    emitter_source,
    kernels,
    mismatches,
    source_tokens,
    split_top,
)

comptime CALLEE = (
    "define internal float @run({ ptr, i64, float, i1 } noundef %0, "
    "i64 noundef %1) #1 {\n  ret float 0.0\n}\n"
)
"""A callee whose aggregate holds a generic pointer."""
comptime KERNEL_CALL = (
    "define void @kernel(ptr addrspace(1) noundef %0) {\n"
    "  %3 = call float @run({ ptr addrspace(1), i64, float, i1 } %2, i64 5)\n"
    "  ret void\n}\n"
)
"""A kernel that passes a device pointer in an aggregate."""
comptime BODY = "define void @kernel() {\n  ret void\n}\n"
"""The smallest kernel body."""


def _matched() -> String:
    """Return a module whose call matches its callee."""
    return String(CALLEE).replace("{ ptr,", "{ ptr addrspace(1),") + KERNEL_CALL


def _lost() -> String:
    """Return a module whose call lost an address space."""
    return String(CALLEE) + KERNEL_CALL


def _body_with(instruction: String) -> String:
    """Return the kernel body with an instruction before its return."""
    return String(BODY).replace("ret void", instruction + "\n  ret void")


def _details(bad: List[Mismatch]) -> List[String]:
    """Return the details of mismatches."""
    var result = List[String]()
    for item in bad:
        result.append(item[1])
    return result^


def _kernel(module: String, name: String) -> Kernel:
    """Return a kernel."""
    return (module, name)


def _copy_bytes() -> Kernel:
    """Return the kernel of the entry tests."""
    return _kernel("render/gpu.mojo", "copy_bytes_kernel")


def kernel_symbol(kernel: Kernel) -> String:
    """Return a symbol in the form the compiler emits for a kernel."""
    var path = kernel[0]
    return (
        String(path[byte = : path.byte_length() - 5]).replace("/", "_")
        + "_"
        + kernel[1]
        + "6A6A6A6AoA6A_b8ccca8f7480edaa"
    )


def kernel_module(
    kernel: Kernel,
    module: String = BODY,
    symbol: String = "",
    emitted: Optional[String] = None,
) -> String:
    """Return a record reduced from the pinned compiler's actual AIR.

    The record binds !air.kernel to an entry node and a defined symbol, and
    the entry's attribute group marks it as a Metal kernel.
    """
    var name = symbol if symbol else kernel_symbol(kernel)
    var entry = emitted.value() if emitted else name
    var lines = List[String]()
    for line in module.split("\n"):
        var text = String(line)
        if text.startswith("define void @kernel("):
            text = text.replace("@kernel(", "@" + name + "(")
            if text.endswith("{"):
                var trimmed = String(text[byte = : text.byte_length() - 1])
                text = trimmed
            text += "#0 {"
        lines.append(text)
    var joined = "\n".join(lines)
    if joined.endswith("\n"):
        var trimmed = String(joined[byte = : joined.byte_length() - 1])
        joined = trimmed
    return (
        String(ENTRY)
        + entry
        + "\n"
        + joined
        + '\nattributes #0 = { "metal.kernel"="true" }\n'
        + "!air.kernel = !{!29}\n"
        + "!19 = !{}\n!28 = !{}\n"
        + "!29 = !{ptr @"
        + name
        + ", !19, !28}\n"
    )


# --- calls -----------------------------------------------------------------------


def test_matching_calls_pass() raises:
    assert_equal(len(mismatches(_matched())), 0)


def test_a_lost_address_space_in_an_aggregate_is_found() raises:
    var bad = mismatches(_lost())
    assert_equal(len(bad), 1)
    assert_equal(bad[0][0], "run")
    assert_true("argument 0" in bad[0][1])


def test_a_lost_address_space_on_a_pointer_is_found() raises:
    var module = (
        "define internal void @load(ptr addrspace(1) noundef %0) {\n"
        "  ret void\n}\n"
        "define void @kernel(ptr noundef %0) {\n"
        "  call void @load(ptr %0)\n  ret void\n}\n"
    )
    var bad = mismatches(module)
    assert_equal(len(bad), 1)
    assert_equal(bad[0][0], "load")


def test_constants_and_attributes_are_not_types() raises:
    var module = (
        "define internal float @scale(float noundef %0, "
        "{ i64 } noundef %1) {\n  ret float %0\n}\n"
        "define void @kernel() {\n"
        "  %1 = call noundef float @scale(float 1.000000e+00, "
        "{ i64 } { i64 4 })\n  ret void\n}\n"
    )
    assert_equal(len(mismatches(module)), 0)


def test_return_and_count_mismatches_are_found() raises:
    var module = (
        "define internal i32 @f(i64 noundef %0) {\n  ret i32 0\n}\n"
        "define void @kernel() {\n"
        "  %1 = call float @f(i64 1)\n"
        "  %2 = call i32 @f(i64 1, i64 2)\n  ret void\n}\n"
    )
    var details = _details(mismatches(module))
    var returns = False
    var count = False
    for detail in details:
        if "returns float" in detail:
            returns = True
        if "2 arguments" in detail:
            count = True
    assert_true(returns and count)
    assert_equal(details[0], "returns float, declared i32")
    assert_equal(details[1], "2 arguments, declared 1")


def test_kernels_are_found_from_launches() raises:
    var found = kernels(realpath("."), default_modules())
    var raster = False
    var water = False
    for kernel in found:
        if kernel[0] == "render/gpu.mojo" and kernel[1] == "rasterize_kernel":
            raster = True
        if (
            kernel[0] == "extensions/water/gpu.mojo"
            and kernel[1] == "water_kernel"
        ):
            water = True
    assert_true(raster and water)
    assert_equal(len(found), 38)


# --- discovery -------------------------------------------------------------------


def _discover(source: String) raises -> List[Kernel]:
    """Return the kernels of one fixture module."""
    var tree = Tree()
    try:
        tree.write("fixture.mojo", source)
        return kernels(tree.root, ["fixture.mojo"])
    finally:
        tree.close()


def test_all_launch_sites_resolve_before_unique_kernels_are_returned() raises:
    var found = _discover(
        "def kernel():\n    pass\nctx.enqueue_function[kernel]()\n"
        "ctx.enqueue_function [\n    kernel\n] ()\n"
    )
    assert_equal(len(found), 1)
    assert_equal(found[0][0], "fixture.mojo")
    assert_equal(found[0][1], "kernel")


def test_comments_and_strings_are_not_launches_or_definitions() raises:
    var source = (
        "# enqueue_function[unknown]()\n"
        'var text = "enqueue_function[unknown[T]]()"\n'
        '"""\ndef unknown():\n    pass\n"""\n'
    )
    assert_equal(len(_discover(source)), 0)
    with assert_raises(contains="local, non-parameterized"):
        _ = _discover(source + "ctx.enqueue_function[unknown]()\n")


def test_parameterized_imported_or_missing_definitions_fail() raises:
    for definition in [
        "def other[T: Int]():\n    pass\n",
        "from imported import other\n",
        "",
        "def outer():\n    def other():\n        pass\n",
    ]:
        var source = (
            "def good():\n    pass\nctx.enqueue_function[good]()\n"
            + definition
            + "ctx.enqueue_function[other]()\n"
        )
        with assert_raises(contains="kernel other must have a local"):
            _ = _discover(source)


def test_unsupported_launch_syntax_cannot_hide_beside_a_good_launch() raises:
    for launch in [
        "ctx.enqueue_function[good[T]]()",
        "ctx.enqueue_function[module.good]()",
        "ctx.enqueue_function[good, T]()",
        "ctx.enqueue_function[](good)",
        "ctx.enqueue_function(good)",
        "var launch = ctx.enqueue_function",
    ]:
        with assert_raises(contains="unsupported enqueue_function syntax"):
            _ = _discover(
                "def good():\n    pass\nctx.enqueue_function[good]()\n"
                + launch
                + "\n"
            )


def test_unterminated_source_fails() raises:
    with assert_raises(contains="unsupported kernel source syntax"):
        _ = _discover("ctx.enqueue_function[good\n")


def test_tokenizer_errors_match_python() raises:
    var cases: List[Tuple[String, String]] = [
        (
            "ctx.enqueue_function[good\n",
            "('unexpected EOF in multi-line statement', (1, 0))",
        ),
        (
            'x = "abc\ny = 1\n',
            "('unterminated string literal (detected at line 1)', (1, 5))",
        ),
        ('x = 1\ny = """abc\nfoo\n', "('EOF in multi-line string', (2, 5))"),
        (
            "def f():\n        pass\n    pass\n",
            (
                "unindent does not match any outer indentation level"
                " (<string>, line 3)"
            ),
        ),
        (
            "if x:\n\tpass\n        pass\n",
            (
                "inconsistent use of tabs and spaces in indentation"
                " (<string>, line 3)"
            ),
        ),
        (
            "x = 5 \\ y\n",
            (
                "('unexpected character after line continuation character',"
                " (1, 10))"
            ),
        ),
        ("x = 1 \\\n", "('unexpected EOF in multi-line statement', (1, 8))"),
        ("x = 0x\n", "('invalid hexadecimal literal', (1, 6))"),
        ("x = 0b102\n", "(\"invalid digit '2' in binary literal\", (1, 9))"),
        ("x = 1__0\n", "('invalid decimal literal', (1, 6))"),
        (
            'x= "a\\"\n',
            (
                "('unterminated string literal (detected at line 1); perhaps"
                " you escaped the end quote?', (1, 4))"
            ),
        ),
        (
            'x = f"""abc',
            (
                "('unterminated triple-quoted f-string literal (detected at"
                " line 1)', (1, 5))"
            ),
        ),
    ]
    for item in cases:
        with assert_raises(contains=item[1]):
            _ = source_tokens(item[0])


def test_tokens_follow_python() raises:
    var tokens = source_tokens(
        'x = ub"a" + 1abc + 1..2\nenqueue_function [\n    kernel\n] ()\n'
    )
    var texts = List[String]()
    for token in tokens:
        texts.append(token.text)
    assert_equal(
        " ".join(texts),
        'x = ub "a" + 1 abc + 1. .2 enqueue_function [ kernel ] ( )',
    )
    assert_equal(tokens[12].text, "kernel")
    assert_equal(tokens[12].row, 3)
    assert_equal(tokens[12].column, 4)
    assert_equal(tokens[13].row, 4)
    assert_equal(tokens[13].column, 0)


def test_unsupported_discovery_fails_cli_before_emitting() raises:
    var tree = Tree()
    tree.write(
        "fixture.mojo",
        "from imported import kernel\nctx.enqueue_function[kernel]()\n",
    )
    var mojo = _fake_mojo(tree, "", 0)
    var outcome = check(tree.root, mojo, ["fixture.mojo"])
    assert_false(Path(tree.root + "/ran").exists())
    assert_equal(outcome.status, 1)
    assert_false("PASS" in outcome.output)
    assert_true("local, non-parameterized" in outcome.errors)
    tree.close()


# --- signatures ------------------------------------------------------------------


def test_declarations_are_checked_in_both_directions() raises:
    for pair in [("ptr", "ptr addrspace(1)"), ("ptr addrspace(1)", "ptr")]:
        var expected = String(pair[0])
        var actual = String(pair[1])
        var module = (
            "declare void @f("
            + expected
            + ")\ndefine void @kernel() {\n  call void @f("
            + actual
            + " null)\n  ret void\n}\n"
        )
        assert_equal(len(mismatches(module)), 1)
        assert_equal(
            len(
                mismatches(
                    module.replace(
                        "@f(" + actual + " null)", "@f(" + expected + " null)"
                    )
                )
            ),
            0,
        )


def test_quoted_names_resolve_to_the_same_symbol() raises:
    for pair in [
        ("f", '"f"'),
        ('"f"', "f"),
        ('"f with ; space"', '"f with ; space"'),
        ('"f\\22q"', '"f\\22q"'),
        ("f", '"\\66"'),
    ]:
        var module = (
            "declare void @"
            + pair[0]
            + "(ptr addrspace(1))\ndefine void @kernel() {\n  call void @"
            + pair[1]
            + "(ptr null)\n  ret void\n}\n"
        )
        assert_equal(len(mismatches(module)), 1)
        assert_equal(
            len(
                mismatches(
                    module.replace("(ptr null)", "(ptr addrspace(1) null)")
                )
            ),
            0,
        )


def test_pointer_and_aggregate_returns_are_checked() raises:
    for pair in [
        ("ptr addrspace(1)", "ptr"),
        ("{ ptr addrspace(1), i64 }", "{ ptr, i64 }"),
    ]:
        var expected = String(pair[0])
        var actual = String(pair[1])
        var module = (
            "declare "
            + expected
            + " @f()\ndefine void @kernel() {\n  %v = call "
            + actual
            + " @f()\n  ret void\n}\n"
        )
        assert_equal(len(mismatches(module)), 1)
        assert_equal(
            len(
                mismatches(module.replace("call " + actual, "call " + expected))
            ),
            0,
        )


def test_literal_aggregate_array_and_vector_types() raises:
    var kind = String("{ [2 x ptr addrspace(1)], <4 x float>, <{ i32, ptr }> }")
    var module = (
        "declare void @f("
        + kind
        + ")\ndefine void @kernel() {\n  call void @f("
        + kind
        + " zeroinitializer)\n  ret void\n}\n"
    )
    assert_equal(len(mismatches(module)), 0)
    assert_equal(
        len(
            mismatches(
                module.replace(
                    "declare void @f(" + kind,
                    "declare void @f("
                    + kind.replace("ptr addrspace(1)", "ptr"),
                )
            )
        ),
        1,
    )


def test_captured_metal_float_and_splat_literals() raises:
    for pair in [
        ("float", "f0xBF490000"),
        ("<4 x float>", "splat (float f0xCF000000)"),
        ("<4 x float>", "splat (float 1.000000e+00)"),
    ]:
        var kind = String(pair[0])
        var module = (
            "declare void @f("
            + kind
            + ")\n"
            + _body_with("call void @f(" + kind + " " + pair[1] + ")")
        )
        assert_equal(len(mismatches(module)), 0)
        assert_equal(
            len(
                mismatches(
                    module.replace(
                        "declare void @f(" + kind + ")",
                        "declare void @f(i32)",
                    )
                )
            ),
            1,
        )


def test_uncaptured_or_malformed_float_forms_fail() raises:
    for item in [
        "float f0xBAD",
        "float f0xBF490000extra",
        "i32 f0xBF490000",
        "<4 x i32> splat (i32 1)",
        "<4 x float> splat ()",
        "<4 x float> splat (float)",
        "<4 x float> splat (float f0xBAD)",
        "<4 x float> splat (float 1.0) trailing",
    ]:
        with assert_raises():
            _ = mismatches(
                "declare void @f(float)\n"
                + _body_with("call void @f(" + item + ")")
            )


def test_supported_call_flags_attributes_and_indentation() raises:
    var module = (
        "  declare fastcc noundef float @f(float noundef)\n"
        "define void @kernel() local_unnamed_addr #0 !dbg !1 {\n"
        "  %x = tail call fast fastcc noundef float @f(float 1.0) #1, !dbg"
        " !2\n  ret void\n}\n"
    )
    assert_equal(len(mismatches(module)), 0)


def test_comments_strings_and_no_call_bodies_are_allowed() raises:
    var module = (
        'source_filename = "call @fake()"\n; call ptr @missing()\n'
        + String(BODY).replace("ret void", "ret void ; call ptr @missing()")
    )
    assert_equal(len(mismatches(module)), 0)


def test_call_words_in_values_globals_and_labels_are_not_opcodes() raises:
    var module = (
        "@call = external global float\n"
        "define void @kernel(ptr %call) {\n"
        "  %x = load float, ptr %call\n"
        "  %y = load float, ptr @call\n"
        "  br label %invoke\n"
        "invoke:\n  br label %callbr\n"
        "callbr:\n  ret void\n}\n"
    )
    assert_equal(len(mismatches(module)), 0)


def test_conflicting_or_duplicate_definitions_fail() raises:
    for module in [
        String(BODY) + BODY,
        "declare void @f(ptr)\ndeclare void @f(i32)\n" + BODY,
    ]:
        with assert_raises():
            _ = mismatches(module)


def test_missing_declaration_fails() raises:
    with assert_raises(contains="missing definition or declaration"):
        _ = mismatches(_body_with("call void @missing()"))


def test_calls_outside_a_function_fail() raises:
    for instruction in ["call void @f(ptr null)", "%x = call i32 @f(ptr null)"]:
        with assert_raises(contains="call outside function"):
            _ = mismatches(
                "declare i32 @f(ptr addrspace(1))\n" + BODY + instruction + "\n"
            )


def test_missing_or_incomplete_function_bodies_fail() raises:
    for module in [
        "",
        "not AIR\n",
        "; a comment\n",
        "declare void @f()\n",
        "define void @f()\n",
        "define void @f() {\n",
        "define void @f() {\n}\n",
        "define void @f() {\nnot an instruction\n}\n",
        "define void @f() {\n%x = add i32 1, 2\n}\n",
        "define void @f() {\nentry:\n; no instructions\n}\n",
    ]:
        with assert_raises():
            _ = mismatches(module)


def test_unsupported_call_forms_fail() raises:
    for instruction in [
        "call void %f()",
        'call void asm "", ""()',
        "invoke void @f() to label %a unwind label %b",
        "callbr void @f() to label %a [label %b]",
        "call void (i32, ...) @f(i32 1)",
        "call cc 10 void @f()",
        "call unknown @f()",
        "call void @f(unknown %x)",
        'call void @f() [ "deopt"(i32 1) ]',
        "call void @f() unknown_attribute",
    ]:
        with assert_raises():
            _ = mismatches("declare void @f()\n" + _body_with(instruction))


def test_malformed_call_inputs_fail() raises:
    for instruction in [
        "call void @f(",
        "call void @f(i32 1,)",
        "call void @f(i32)",
        "call void @f(i32 noundef)",
        "call void @f(i32 align 4)",
        "call void @f({ i32 ] %x)",
        "call void @f()(",
        'call void @"unterminated()',
        "call void @f(i8* %x)",
        "call void @f(ptr addrspace(no) %x)",
    ]:
        with assert_raises():
            _ = mismatches("declare void @f(i32)\n" + _body_with(instruction))


def test_unsupported_or_malformed_signatures_fail() raises:
    for declaration in [
        "declare void @f(...)",
        "declare void @f(%T)",
        "declare void @f(i32,)",
        "declare void @f({ ptr ])",
        "declare unknown @f()",
        "declare void @f(",
    ]:
        with assert_raises():
            _ = mismatches(declaration + "\n" + BODY)


def test_error_messages_name_the_line() raises:
    with assert_raises(
        contains="line 1: not enough values to unpack (expected 2, got 1)"
    ):
        _ = mismatches("define\n" + BODY)
    with assert_raises(
        contains="line 3: missing or unsupported type: unknown %x"
    ):
        _ = mismatches(
            "declare void @f(i32)\n" + _body_with("call void @f(unknown %x)")
        )


def test_split_top_respects_quoted_delimiters() raises:
    var parts = split_top('ptr %"a,b(c)", i32 0')
    assert_equal(len(parts), 2)
    assert_equal(parts[0], 'ptr %"a,b(c)"')
    assert_equal(parts[1], "i32 0")


# --- kernel entries --------------------------------------------------------------


def test_metadata_binds_the_defined_marked_entry() raises:
    assert_equal(
        len(mismatches(kernel_module(_copy_bytes()), _copy_bytes())), 0
    )


def test_quoted_entry_symbols_are_resolved() raises:
    var name = String(
        "render_gpu_copy_bytes_kernel6A6A6A6AoA6A_b8ccca8f7480edaa"
    )
    var module = kernel_module(_copy_bytes()).replace(
        "@" + name, '@"' + name + '"'
    )
    assert_equal(len(mismatches(module, _copy_bytes())), 0)


def test_a_helper_only_record_cannot_claim_a_kernel() raises:
    var helper = String(BODY).replace("@kernel", "@helper")
    with assert_raises(contains="!air.kernel"):
        _ = mismatches(
            String(ENTRY) + kernel_symbol(_copy_bytes()) + "\n" + helper,
            _copy_bytes(),
        )
    with assert_raises(contains="no function body"):
        _ = mismatches(kernel_module(_copy_bytes(), helper), _copy_bytes())


def test_a_different_marked_kernel_cannot_use_the_label() raises:
    for other in [
        _kernel("render/gpu.mojo", "copy_floats_kernel"),
        _kernel("render/gpu_vxgi.mojo", "copy_bytes_kernel"),
        _kernel("render/gpu.mojo", "copy_bytes_kernel_helper"),
        _kernel("render/gpu.mojo", "copy_bytes_kernel2"),
    ]:
        with assert_raises(contains="does not match"):
            _ = mismatches(
                kernel_module(other, emitted=kernel_symbol(_copy_bytes())),
                _copy_bytes(),
            )


def test_missing_malformed_duplicate_or_ambiguous_metadata_fails() raises:
    var valid = kernel_module(_copy_bytes())
    for module in [
        valid.replace("!{!29}", "!{}"),
        valid.replace("!{!29}", "!{!29, !30}"),
        valid.replace("!{!29}", "!{!99}"),
        valid.replace("!19 = !{}\n", ""),
        valid.replace("!29 = !{ptr", "!29 = !{i64"),
        valid + "!air.kernel = !{!29}\n",
        valid + "!29 = !{}\n",
    ]:
        with assert_raises():
            _ = mismatches(module, _copy_bytes())


def test_actual_truncated_and_specialized_names_need_no_guessing() raises:
    for pair in [
        (
            _kernel("render/gpu.mojo", "bloom_composite_kernel"),
            "render_gpu_bloom_composite_ker6A6A6A6A_d1876a7b8107b01b",
        ),
        (
            _kernel("render/gpu.mojo", "blur_kernel"),
            "render_gpu_blur_kernel_Point6A6A6A6AoA6A6A_40ffe11d65f1390d",
        ),
    ]:
        assert_equal(
            len(
                mismatches(
                    kernel_module(pair[0], symbol=pair[1]), pair[0].copy()
                )
            ),
            0,
        )


def test_colliding_source_prefixes_bind_distinct_exact_symbols() raises:
    var kernels_list: List[Kernel] = [
        _kernel(
            "render/gpu.mojo", "a_long_kernel_name_with_a_common_prefix_one"
        ),
        _kernel(
            "render/gpu.mojo", "a_long_kernel_name_with_a_common_prefix_two"
        ),
    ]
    assert_equal(
        String(kernel_symbol(kernels_list[0])[byte=:30]),
        String(kernel_symbol(kernels_list[1])[byte=:30]),
    )
    var symbols: List[String] = [
        "render_gpu_a_long_kernel_name6A_" + "1111111111111111",
        "render_gpu_a_long_kernel_name6A_" + "2222222222222222",
    ]
    var records = List[String]()
    for index in range(2):
        records.append(
            kernel_module(kernels_list[index], symbol=symbols[index])
        )
        assert_equal(len(mismatches(records[index], kernels_list[index])), 0)
    for index in range(2):
        var other = records[1 - index]
        var swapped = (
            String(ENTRY)
            + symbols[index]
            + "\n"
            + String(other[byte = other.find("\n") + 1 :])
        )
        with assert_raises(contains="does not match compiler-returned"):
            _ = mismatches(swapped, kernels_list[index])


def test_entry_name_must_be_present_once_before_ir() raises:
    var valid = kernel_module(_copy_bytes())
    var cut = valid.find("\n")
    var entry = String(valid[byte=:cut])
    var ir = String(valid[byte = cut + 1 :])
    for module in [
        ir,
        String(ENTRY) + "\n" + ir,
        valid + entry + "\n",
        ir + entry + "\n",
    ]:
        with assert_raises(contains="emitted entry name"):
            _ = mismatches(module, _copy_bytes())


def test_missing_or_false_metal_kernel_attribute_fails() raises:
    var valid = kernel_module(_copy_bytes())
    for module in [
        valid.replace('"metal.kernel"="true"', ""),
        valid.replace('"metal.kernel"="true"', '"metal.kernel"="false"'),
        valid.replace("attributes #0", "attributes #1"),
    ]:
        with assert_raises(contains="lacks metal.kernel"):
            _ = mismatches(module, _copy_bytes())


# --- emission --------------------------------------------------------------------


def _fake_mojo(tree: Tree, stdout: String, status: Int) raises -> String:
    """Write a stand-in compiler that copies the program it runs, prints
    `stdout`, writes a diagnostic and exits with `status`."""
    tree.write("stdout.txt", stdout)
    tree.write(
        "fake-mojo",
        '#!/bin/sh\nhere=$(dirname "$0")\n: >"$here/ran"\n'
        'cp "$5" "$here/program.mojo"\ncat "$here/stdout.txt"\n'
        "echo 'fixture emission failed' >&2\nexit "
        + String(status)
        + "\n",
    )
    _ = run_program(["chmod", "+x", tree.root + "/fake-mojo"], 10)
    return tree.root + "/fake-mojo"


def _output(found: List[Kernel], modules: List[String]) -> String:
    """Return emitter output with one record for each kernel."""
    var text = String()
    for index in range(len(found)):
        text += (
            String(SEPARATOR)
            + found[index][0]
            + ":"
            + found[index][1]
            + "\n"
            + modules[index]
        )
    return text^


def _records(found: List[Kernel]) -> List[String]:
    """Return a valid record for each kernel."""
    var result = List[String]()
    for kernel in found:
        result.append(kernel_module(kernel))
    return result^


struct _Run(Movable):
    """A command-line run with a stand-in compiler."""

    var status: Int
    """The exit status."""
    var output: String
    """The standard output."""
    var errors: String
    """The standard error."""
    var ran: Bool
    """True when the stand-in compiler ran."""

    def __init__(
        out self, status: Int, var output: String, var errors: String, ran: Bool
    ):
        """Make a run."""
        self.status = status
        self.output = output^
        self.errors = errors^
        self.ran = ran


def _cli(stdout: String, status: Int = 0) raises -> _Run:
    """Run the check with a stand-in compiler that prints `stdout`."""
    var tree = Tree()
    var mojo = _fake_mojo(tree, stdout, status)
    var outcome = check(realpath("."), mojo, default_modules())
    var ran = Path(tree.root + "/ran").exists()
    tree.close()
    return _Run(outcome.status, outcome.output, outcome.errors, ran)


def _assert_fails(stdout: String, reason: String) raises:
    """Require a failing run whose standard error names `reason`."""
    var run = _cli(stdout)
    assert_true(run.ran)
    assert_equal(run.status, 1)
    assert_false("PASS" in run.output)
    assert_true(reason in run.errors, run.errors)


def _found() raises -> List[Kernel]:
    """Return the real discovered kernels."""
    var found = kernels(realpath("."), default_modules())
    assert_true(len(found) > 0)
    return found^


def test_complete_modules_with_no_calls_pass() raises:
    var found = _found()
    var run = _cli(_output(found, _records(found)))
    assert_equal(run.status, 0)
    assert_equal(run.errors, "")
    assert_equal(
        run.output,
        "PASS "
        + String(len(found))
        + " Metal kernel AIR modules: supported direct-call types match"
        " definitions/declarations\n",
    )


def test_empty_output_fails() raises:
    _assert_fails("", "missing AIR records")


def test_missing_records_fail() raises:
    var found = _found()
    _assert_fails(
        _output([found[0].copy()], [kernel_module(found[0])]),
        "missing AIR records",
    )


def test_all_empty_records_fail() raises:
    var found = _found()
    var empty = List[String]()
    for _ in found:
        empty.append("")
    _assert_fails(_output(found, empty), "empty AIR record")


def test_entry_names_cannot_be_missing_duplicated_or_reused() raises:
    var found = _found()
    var first = kernel_module(found[0])
    var cut = first.find("\n")
    var entry = String(first[byte=:cut])
    var ir = String(first[byte = cut + 1 :])
    for bad in [ir, first + entry + "\n"]:
        var records = _records(found)
        records[0] = bad
        _assert_fails(_output(found, records), "emitted entry name")
    var reused = List[String]()
    for kernel in found:
        reused.append(kernel_module(kernel, emitted=kernel_symbol(found[0])))
    _assert_fails(_output(found, reused), "entry reused across kernel records")


def test_emitter_pairs_name_and_asm_from_each_compile_result() raises:
    var found = _found()
    var tree = Tree()
    var mojo = _fake_mojo(tree, _output(found, _records(found)), 0)
    assert_equal(len(emit(realpath("."), mojo, found)), len(found))
    var program = tree.read("program.mojo")
    assert_equal(program, emitter_source(found))
    for index in range(len(found)):
        var number = String(index)
        assert_true(
            "var compiled_" + number + " = _compile_code[kernel_" + number + ","
            in program
        )
        assert_true(
            'print("'
            + String(ENTRY)
            + '" + String(compiled_'
            + number
            + ".function_name))"
            in program
        )
        assert_true("print(compiled_" + number + ".asm)" in program)
    assert_true("from render.gpu import rasterize_kernel as kernel_" in program)
    tree.close()


def test_duplicate_cannot_hide_a_bad_record() raises:
    var found = _found()
    var records = List[String]()
    for index in range(len(found)):
        records.append(
            kernel_module(found[index], _lost() if index == 0 else String(BODY))
        )
    var more = found.copy()
    more.append(found[0].copy())
    var doubled = records.copy()
    doubled.append(kernel_module(found[0]))
    _assert_fails(_output(more, doubled), "duplicate AIR record")
    # Negative control: the original bad record itself is a type failure.
    var run = _cli(_output(found, records))
    assert_equal(run.status, 1)
    assert_true(
        run.errors.startswith(
            "render/gpu.mojo:" + found[0][1] + ": call to run: argument 0 is"
        )
    )
    assert_true(
        run.errors.endswith(
            "1 call type mismatches; see modular/modular#7238. Give every"
            " device pointer an explicit address space (`DevicePointer` in"
            " render/gpu.mojo).\n"
        )
    )


def test_unexpected_record_fails() raises:
    _assert_fails(
        _output([_kernel("/unexpected.mojo", "unknown")], [String(BODY)]),
        "unexpected AIR record",
    )


def test_unexpected_preamble_fails() raises:
    var found = _found()
    _assert_fails(
        "diagnostic text\n" + _output(found, _records(found)),
        "unexpected output",
    )


def test_each_record_requires_a_function_body() raises:
    var found = _found()
    for bad in ["not AIR\n", "; comment only\n", "declare void @f()\n"]:
        var records = _records(found)
        records[0] = bad
        _assert_fails(_output(found, records), "AIR check failed")


def test_diagnostics_after_a_module_fail() raises:
    var found = _found()
    var records = _records(found)
    records[0] = records[0] + "emission failed\n"
    _assert_fails(_output(found, records), "unrecognized output")


def test_no_discovery_fails_without_running_a_compiler() raises:
    var tree = Tree()
    var mojo = _fake_mojo(tree, "", 0)
    var outcome = check(realpath("."), mojo, List[String]())
    assert_false(Path(tree.root + "/ran").exists())
    assert_equal(outcome.status, 1)
    assert_false("PASS" in outcome.output)
    assert_equal(outcome.errors, "AIR check failed: no kernels discovered\n")
    tree.close()


def test_duplicate_discovery_fails() raises:
    var found = _found()
    with assert_raises(contains="duplicate entries"):
        _ = emitted_modules("", [found[0].copy(), found[0].copy()])


def test_emitter_failure_does_not_pass() raises:
    var run = _cli("", 1)
    assert_equal(run.status, 1)
    assert_false("PASS" in run.output)
    assert_equal(
        run.errors,
        "AIR check failed: AIR emission failed:\nfixture emission failed\n\n",
    )


def test_emitter_timeout_does_not_pass() raises:
    var tree = Tree()
    tree.write("fake-mojo", "#!/bin/sh\nexec sleep 30\n")
    _ = run_program(["chmod", "+x", tree.root + "/fake-mojo"], 10)
    var outcome = check(
        realpath("."), tree.root + "/fake-mojo", default_modules(), 0.5
    )
    tree.close()
    assert_equal(outcome.status, 1)
    assert_false("PASS" in outcome.output)
    assert_true(outcome.errors.startswith("AIR check failed: Command '['"))
    assert_true(outcome.errors.endswith("' timed out after 0.5 seconds\n"))


def test_a_missing_compiler_is_an_os_error() raises:
    var outcome = check(
        realpath("."), "/nonexistent/threemojo-mojo", default_modules()
    )
    assert_equal(
        outcome.errors,
        (
            "AIR check failed: [Errno 2] No such file or directory:"
            " '/nonexistent/threemojo-mojo'\n"
        ),
    )


def test_the_command_line_matches_argparse() raises:
    var usage = String("usage: check_air_calls.mojo [-h] [--mojo MOJO]\n")
    var help = parse_command_line(
        ["-h"],
        "check_air_calls.mojo",
        usage,
        "HELP",
        List[String](),
        ["--mojo"],
    )
    assert_equal(help.status, -1)
    assert_equal(help.message, usage + "HELP")
    var given = parse_command_line(
        ["--mo=x"], "p", usage, "", List[String](), ["--mojo"]
    )
    assert_equal(given.status, 0)
    assert_equal(given.value("--mojo", "default"), "x")
    var missing = parse_command_line(
        ["--mojo"],
        "check_air_calls.mojo",
        usage,
        "",
        List[String](),
        ["--mojo"],
    )
    assert_equal(missing.status, 2)
    assert_equal(
        missing.message,
        usage
        + "check_air_calls.mojo: error: argument --mojo: expected one"
        " argument\n",
    )
    var unknown = parse_command_line(
        ["--bogus", "x"], "p", usage, "", List[String](), ["--mojo"]
    )
    assert_equal(
        unknown.message, usage + "p: error: unrecognized arguments: --bogus x\n"
    )


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
