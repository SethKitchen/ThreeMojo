# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Tests for `coverage.scanner`."""

from coverage.scanner import Scanner, indent_of
from std.testing import TestSuite, assert_equal, assert_false, assert_true


def executable_lines(source: String) raises -> List[Int]:
    """Return the 1-based line numbers a probe would be inserted before.

    Args:
        source: Whole Mojo source text.

    Returns:
        Line numbers classified as executable statements.

    Raises:
        Error: Never; present to satisfy the scanner's signature.
    """
    var scanner = Scanner()
    var hits = List[Int]()
    var number = 0
    for line in source.splitlines():
        number += 1
        if scanner.is_executable(String(line)):
            hits.append(number)
    return hits^


def test_indent_of_counts_leading_spaces() raises:
    assert_equal(indent_of(String("    x = 1")), 4)
    assert_equal(indent_of(String("x = 1")), 0)
    assert_equal(indent_of(String("")), 0)


def test_statements_in_a_function_are_executable() raises:
    var source = String("def f():\n    var x = 1\n    return x\n")
    var hits = executable_lines(source)
    assert_equal(len(hits), 2)
    assert_equal(hits[0], 2)
    assert_equal(hits[1], 3)


def test_def_header_and_decorator_are_skipped() raises:
    var source = String("@always_inline\ndef f():\n    return 1\n")
    assert_equal(executable_lines(source), [3])


def test_blank_and_comment_lines_are_skipped() raises:
    var source = String("def f():\n\n    # a note\n    return 1\n")
    assert_equal(executable_lines(source), [4])


def test_imports_are_skipped() raises:
    var source = String("from std.math import sqrt\nimport std.random\n")
    assert_equal(len(executable_lines(source)), 0)


def test_module_docstring_is_skipped() raises:
    var source = String(
        '"""Module.\n\nMore prose.\n"""\ndef f():\n    return 1\n'
    )
    assert_equal(executable_lines(source), [6])


def test_single_line_docstring_is_skipped() raises:
    var source = String('def f():\n    """One liner."""\n    return 1\n')
    assert_equal(executable_lines(source), [3])


def test_prose_inside_a_docstring_is_not_mistaken_for_code() raises:
    # The indented `var x = 1` here is documentation, not a statement.
    var source = String(
        'def f():\n    """Doc.\n\n    var x = 1\n    """\n    return 1\n'
    )
    assert_equal(executable_lines(source), [6])


def test_struct_fields_are_not_executable() raises:
    var source = String("struct S:\n    var x: Int\n    var y: Int\n")
    assert_equal(len(executable_lines(source)), 0)


def test_methods_inside_a_struct_are_executable() raises:
    var source = String(
        "struct S:\n    var x: Int\n\n    def get(self) -> Int:\n"
        "        return self.x\n"
    )
    assert_equal(executable_lines(source), [5])


def test_dedenting_out_of_a_method_returns_to_struct_scope() raises:
    var source = String(
        "struct S:\n    def get(self) -> Int:\n        return 1\n"
        "    var trailing: Int\n"
    )
    assert_equal(executable_lines(source), [3])


def test_comptime_declarations_are_skipped() raises:
    var source = String("comptime N = 4\ndef f():\n    return N\n")
    assert_equal(executable_lines(source), [3])


def test_else_and_elif_cannot_take_a_probe() raises:
    var source = String(
        "def f(a: Int) -> Int:\n    if a > 0:\n        return 1\n"
        "    elif a < 0:\n        return 2\n    else:\n        return 3\n"
    )
    # The `if` is probed, the `elif`/`else` clauses are not, but their bodies
    # are, so every branch still gets measured.
    assert_equal(executable_lines(source), [2, 3, 5, 7])


def test_except_and_finally_cannot_take_a_probe() raises:
    var source = String(
        "def f() raises:\n    try:\n        g()\n    except e:\n        h()\n"
        "    finally:\n        k()\n"
    )
    assert_equal(executable_lines(source), [2, 3, 5, 7])


def test_multi_line_call_is_probed_once() raises:
    var source = String(
        "def f():\n    call(\n        1,\n        2,\n    )\n    return 1\n"
    )
    # Only the opening line is probed; lines 3-5 are continuations.
    assert_equal(executable_lines(source), [2, 6])


def test_multi_line_def_signature_is_skipped_entirely() raises:
    var source = String(
        "def f(\n    a: Int,\n    b: Int,\n) -> Int:\n    return a + b\n"
    )
    assert_equal(executable_lines(source), [5])


def test_brackets_inside_string_literals_are_ignored() raises:
    # A bare "(" in a literal must not be read as opening a continuation.
    var source = String('def f():\n    print("(")\n    return 1\n')
    assert_equal(executable_lines(source), [2, 3])


def test_trailing_comment_brackets_are_ignored() raises:
    var source = String(
        "def f():\n    var x = 1  # note (unclosed\n    return x\n"
    )
    assert_equal(executable_lines(source), [2, 3])


def test_nested_function_body_is_executable() raises:
    var source = String(
        "def outer():\n    def inner():\n        return 1\n    return inner\n"
    )
    assert_equal(executable_lines(source), [3, 4])


def test_empty_source_has_no_executable_lines() raises:
    assert_equal(len(executable_lines(String(""))), 0)


def test_multi_line_comptime_assert_is_skipped_entirely() raises:
    # The formatter reflows a long assert like this. Losing the open bracket
    # here put probes inside the expression and broke the build.
    var source = String(
        'def f():\n    comptime assert (\n        N > 0\n    ), "msg"\n'
        "    return 1\n"
    )
    assert_equal(executable_lines(source), [5])


def test_multi_line_elif_condition_is_skipped_entirely() raises:
    var source = String(
        "def f(a: Int):\n    if a > 0:\n        return 1\n    elif (\n"
        "        a < 0\n    ):\n        return 2\n"
    )
    assert_equal(executable_lines(source), [2, 3, 7])


def test_multi_line_decorator_is_skipped_entirely() raises:
    var source = String("@inline(\n    .always\n)\ndef f():\n    return 1\n")
    assert_equal(executable_lines(source), [5])


def test_multi_line_import_is_skipped_entirely() raises:
    var source = String(
        "from std.math import (\n    sqrt,\n    cos,\n)\ndef f():\n"
        "    return 1\n"
    )
    assert_equal(executable_lines(source), [6])


# --- traits -----------------------------------------------------------------


def test_a_trait_method_body_is_not_executable() raises:
    # A trait declares what an implementation must provide; its bodies are a
    # docstring and `...`, and never run. Probing them emitted a call to the
    # probe function from inside a trait, where it is not in scope, and every
    # file importing that trait stopped compiling.
    var scanner = Scanner()
    assert_false(scanner.is_executable("trait Camera(Copyable, Movable):"))
    assert_false(scanner.is_executable('    """What a renderer needs."""'))
    assert_false(scanner.is_executable("    def view_matrix(self) -> Int:"))
    assert_false(scanner.is_executable('        """Return it."""'))
    assert_false(scanner.is_executable("        ..."))


def test_code_after_a_trait_is_executable_again() raises:
    # The trait scope has to close like any other, or everything following a
    # trait in the same file would go unmeasured.
    var scanner = Scanner()
    assert_false(scanner.is_executable("trait Camera:"))
    assert_false(scanner.is_executable("    def near(self) -> Int:"))
    assert_false(scanner.is_executable("        ..."))
    assert_false(scanner.is_executable(""))
    assert_false(scanner.is_executable("def after() -> Int:"))
    assert_true(scanner.is_executable("    return 1"))


def test_a_struct_implementing_a_trait_is_still_measured() raises:
    # `struct X(Trait)` starts with "struct", not "trait", and its methods are
    # ordinary code that has to be covered like any other.
    var scanner = Scanner()
    assert_false(scanner.is_executable("struct Persp(Camera):"))
    assert_false(scanner.is_executable("    var near: Int"))
    assert_false(scanner.is_executable("    def near_distance(self) -> Int:"))
    assert_true(scanner.is_executable("        return self.near"))


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
