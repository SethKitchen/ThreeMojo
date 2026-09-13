# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Tests for `coverage.instrument`."""

from coverage.instrument import instrument
from std.testing import TestSuite, assert_equal, assert_true


def test_probe_is_inserted_above_each_statement() raises:
    var result = instrument(String("def f():\n    return 1\n"), String("m"))
    var lines = result.text.splitlines()
    assert_equal(String(lines[2].strip()), String('_cov_hit("m:2")'))
    assert_equal(String(lines[3].strip()), String("return 1"))


def test_probe_matches_the_indentation_of_its_statement() raises:
    var result = instrument(
        String("struct S:\n    def g(self):\n        return 1\n"), String("m")
    )
    for line in result.text.splitlines():
        if "_cov_hit" in String(line) and "import" not in String(line):
            assert_true(String(line).startswith("        _cov_hit"))


def test_reported_line_numbers_refer_to_the_original_file() raises:
    var result = instrument(
        String("def f():\n    var x = 1\n    return x\n"), String("m")
    )
    assert_equal(result.lines, [2, 3])


def test_import_is_added_once_above_the_first_definition() raises:
    var result = instrument(
        String("def f():\n    return 1\n\n\ndef g():\n    return 2\n"),
        String("m"),
    )
    var count = 0
    for line in result.text.splitlines():
        if String(line).startswith("from coverage.runtime"):
            count += 1
    assert_equal(count, 1)
    assert_equal(String(result.text.splitlines()[0]).startswith("from"), True)


def test_import_is_placed_below_a_module_docstring() raises:
    # A module docstring must stay the file's first expression.
    var source = String('"""Doc."""\n\ndef f():\n    return 1\n')
    var result = instrument(source, String("m"))
    var lines = result.text.splitlines()
    assert_equal(String(lines[0]), String('"""Doc."""'))
    assert_true(String(lines[2]).startswith("from coverage.runtime"))


def test_import_is_placed_below_a_multi_line_docstring() raises:
    var source = String(
        '"""Doc.\n\ndef not_real():\n"""\ndef f():\n    return 1\n'
    )
    var result = instrument(source, String("m"))
    var lines = result.text.splitlines()
    # The `def` inside the docstring must not attract the import.
    assert_true(String(lines[4]).startswith("from coverage.runtime"))
    assert_equal(String(lines[5]), String("def f():"))


def test_import_precedes_a_decorator() raises:
    var source = String("@fieldwise_init\nstruct S:\n    var x: Int\n")
    var result = instrument(source, String("m"))
    assert_true(String(result.text.splitlines()[0]).startswith("from coverage"))


def test_existing_imports_are_preserved_above_the_probe_import() raises:
    var source = String("from std.math import sqrt\n\ndef f():\n    return 1\n")
    var result = instrument(source, String("m"))
    var lines = result.text.splitlines()
    assert_equal(String(lines[0]), String("from std.math import sqrt"))
    assert_true(String(lines[2]).startswith("from coverage.runtime"))


def test_original_lines_are_preserved_verbatim() raises:
    var source = String("def f():\n    return 1\n")
    var result = instrument(source, String("m"))
    for original in source.splitlines():
        assert_true(String(original) in result.text)


def test_file_with_no_definitions_gets_no_probes() raises:
    var result = instrument(String("from std.math import sqrt\n"), String("m"))
    assert_equal(len(result.lines), 0)
    assert_true("_cov_hit" not in result.text)


def test_if_condition_is_wrapped() raises:
    var result = instrument(
        String("def f(a: Int):\n    if a > 0:\n        return 1\n"), String("m")
    )
    assert_true('if _cov_branch("m:2", a > 0):' in result.text)
    assert_equal(result.branches, [2])


def test_elif_is_a_branch_even_though_it_takes_no_line_probe() raises:
    var source = String(
        "def f(a: Int):\n    if a > 0:\n        return 1\n"
        "    elif a < 0:\n        return 2\n"
    )
    var result = instrument(source, String("m"))
    assert_true('elif _cov_branch("m:4", a < 0):' in result.text)
    assert_equal(result.branches, [2, 4])


def test_while_condition_is_wrapped() raises:
    var result = instrument(
        String("def f(a: Int):\n    while a > 0:\n        a -= 1\n"),
        String("m"),
    )
    assert_true('while _cov_branch("m:2", a > 0):' in result.text)


def test_else_is_not_wrapped_because_it_has_no_condition() raises:
    var source = String(
        "def f(a: Int):\n    if a > 0:\n        return 1\n"
        "    else:\n        return 2\n"
    )
    var result = instrument(source, String("m"))
    # The `if`'s False outcome already records that `else` ran.
    assert_equal(result.branches, [2])
    assert_true("else:" in result.text)


def test_trailing_comment_survives_wrapping() raises:
    var result = instrument(
        String("def f(a: Int):\n    if a > 0:  # note\n        return 1\n"),
        String("m"),
    )
    assert_true('if _cov_branch("m:2", a > 0):  # note' in result.text)


def test_compound_condition_wraps_the_decision_and_each_operand() raises:
    var source = String(
        "def f(a: Int):\n    if a > 0 and a < 9:\n        return 1\n"
    )
    var result = instrument(source, String("m"))
    assert_equal(result.branches, [2])
    assert_equal(result.conditions, [2])
    assert_true(
        'if _cov_branch("m:2", _cov_branch("m:2.0", a > 0)'
        ' and _cov_branch("m:2.1", a < 9)):'
        in result.text
    )


def test_single_condition_gets_no_inner_probe() raises:
    var source = String("def f(a: Int):\n    if a > 0:\n        return 1\n")
    var result = instrument(source, String("m"))
    assert_equal(result.conditions, [0])
    assert_true('_cov_branch("m:2.0"' not in result.text)


def test_mixed_and_or_keeps_precedence_by_wrapping_only_operands() raises:
    var source = String(
        "def f(a: Int, b: Int):\n    if a > 0 and b > 0 or a < 0:\n"
        "        return 1\n"
    )
    var result = instrument(source, String("m"))
    assert_equal(result.conditions, [3])
    # `and` still binds tighter than `or`, because only the leaves are wrapped.
    assert_true(
        '_cov_branch("m:2.0", a > 0) and _cov_branch("m:2.1", b > 0)'
        ' or _cov_branch("m:2.2", a < 0)'
        in result.text
    )


def test_operators_inside_brackets_do_not_split() raises:
    var source = String(
        "def f(a: Int, b: Int):\n    if not (a and b):\n        return 1\n"
    )
    var result = instrument(source, String("m"))
    assert_equal(result.conditions, [0])
    assert_true('if _cov_branch("m:2", not (a and b)):' in result.text)


def test_operators_inside_string_literals_do_not_split() raises:
    var source = String(
        'def f(s: String):\n    if s == "a and b":\n        return 1\n'
    )
    var result = instrument(source, String("m"))
    assert_equal(result.conditions, [0])


def test_identifiers_containing_and_or_are_not_split() raises:
    # `android` and `original` must not be mistaken for operators.
    var source = String(
        "def f(android: Bool, original: Bool):\n"
        "    if android or original:\n        return 1\n"
    )
    var result = instrument(source, String("m"))
    assert_equal(result.conditions, [2])
    assert_true('_cov_branch("m:2.0", android)' in result.text)
    assert_true('_cov_branch("m:2.1", original)' in result.text)


def test_while_condition_operands_are_split() raises:
    var source = String(
        "def f(a: Int, b: Int):\n    while a > 0 and b > 0:\n        a -= 1\n"
    )
    var result = instrument(source, String("m"))
    assert_equal(result.conditions, [2])


def test_loops_report_no_conditions() raises:
    var source = String(
        "def f(n: Int):\n    for i in range(n):\n        g(i)\n"
    )
    var result = instrument(source, String("m"))
    # A loop has outcomes but no boolean operands.
    assert_equal(result.conditions, [0])


def test_colon_inside_a_literal_does_not_end_the_header() raises:
    var source = String(
        'def f(s: String):\n    if s == "a:b":\n        return 1\n'
    )
    var result = instrument(source, String("m"))
    assert_true('if _cov_branch("m:2", s == "a:b"):' in result.text)


def test_colon_inside_brackets_does_not_end_the_header() raises:
    var source = String(
        "def f(d: Int):\n    if d in {1: 2}:\n        return 1\n"
    )
    var result = instrument(source, String("m"))
    assert_true('if _cov_branch("m:2", d in {1: 2}):' in result.text)


def test_multi_line_condition_is_joined_and_wrapped() raises:
    var source = String(
        "def f(a: Int):\n    if (\n        a > 0\n    ):\n        return 1\n"
    )
    var result = instrument(source, String("m"))
    # Attributed to the line the header started on.
    assert_equal(result.branches, [2])
    assert_true('if _cov_branch("m:2", ( a > 0 )):' in result.text)


def test_multi_line_condition_spanning_several_operands() raises:
    var source = String(
        "def f(a: Int):\n    if (\n        a > 0\n        and a < 9\n"
        "    ):\n        return 1\n"
    )
    var result = instrument(source, String("m"))
    assert_equal(result.branches, [2])
    assert_true('_cov_branch("m:2", ( a > 0 and a < 9 ))' in result.text)


def test_comments_inside_a_multi_line_condition_do_not_swallow_code() raises:
    # Joining the lines naively would put `and a < 9` after the `#`.
    var source = String(
        "def f(a: Int):\n    if (  # start\n        a > 0  # positive\n"
        "        and a < 9\n    ):\n        return 1\n"
    )
    var result = instrument(source, String("m"))
    assert_true('_cov_branch("m:2", ( a > 0 and a < 9 ))' in result.text)


def test_multi_line_while_header_is_wrapped() raises:
    var source = String(
        "def f(a: Int):\n    while (\n        a > 0\n    ):\n        a -= 1\n"
    )
    var result = instrument(source, String("m"))
    assert_equal(result.branches, [2])
    assert_true('while _cov_branch("m:2", ( a > 0 )):' in result.text)


def test_statement_after_a_multi_line_header_is_still_probed() raises:
    var source = String(
        "def f(a: Int):\n    if (\n        a > 0\n    ):\n        return 1\n"
        "    return 2\n"
    )
    var result = instrument(source, String("m"))
    # Line 5 is the body, line 6 follows the header; both must be measured.
    assert_true(5 in result.lines)
    assert_true(6 in result.lines)


def test_for_loop_is_a_branch() raises:
    var source = String(
        "def f(n: Int):\n    for i in range(n):\n        g(i)\n"
    )
    var result = instrument(source, String("m"))
    assert_equal(result.branches, [2])


def test_for_loop_raises_a_flag_inside_its_body() raises:
    var source = String(
        "def f(n: Int):\n    for i in range(n):\n        g(i)\n"
    )
    var result = instrument(source, String("m"))
    assert_true("var _cov_loop_2 = 0" in result.text)
    assert_true("_cov_loop_2 += 1" in result.text)


def test_for_loop_reports_the_empty_case_after_its_body() raises:
    var source = String(
        "def f(n: Int):\n    for i in range(n):\n        g(i)\n"
    )
    var result = instrument(source, String("m"))
    # Reading the flag after the loop is the only way to see zero iterations.
    assert_true('_ = _cov_branch("m:2", _cov_loop_2 > 0)' in result.text)


def test_for_loop_reports_entry_from_inside_the_body() raises:
    # A body that returns would never reach the trailing probe.
    var source = String(
        "def f(n: Int):\n    for i in range(n):\n        return i\n"
    )
    var result = instrument(source, String("m"))
    assert_true('_ = _cov_branch("m:2", True)' in result.text)


def test_nested_loops_close_innermost_first() raises:
    var source = String(
        "def f(n: Int):\n    for y in range(n):\n        for x in range(n):\n"
        "            g(x)\n"
    )
    var result = instrument(source, String("m"))
    assert_equal(result.branches, [2, 3])
    var inner = result.text.find('_ = _cov_branch("m:3", _cov_loop_3 > 0)')
    var outer = result.text.find('_ = _cov_branch("m:2", _cov_loop_2 > 0)')
    assert_true(inner < outer)


def test_loop_closer_is_indented_to_the_loop_header() raises:
    var source = String(
        "def f(n: Int):\n    for y in range(n):\n        g(y)\n    return 1\n"
    )
    var result = instrument(source, String("m"))
    assert_true(
        '\n    _ = _cov_branch("m:2", _cov_loop_2 > 0)\n' in result.text
    )


def test_statement_after_a_loop_is_still_probed() raises:
    var source = String(
        "def f(n: Int):\n    for y in range(n):\n        g(y)\n    return 1\n"
    )
    var result = instrument(source, String("m"))
    assert_true(4 in result.lines)


def test_loop_at_end_of_file_still_gets_its_closer() raises:
    var source = String(
        "def f(n: Int):\n    for y in range(n):\n        g(y)\n"
    )
    var result = instrument(source, String("m"))
    assert_true('_ = _cov_branch("m:2", _cov_loop_2 > 0)' in result.text)


def test_blank_and_comment_lines_do_not_close_a_loop_early() raises:
    var source = String(
        "def f(n: Int):\n    for y in range(n):\n        g(y)\n\n"
        "# note\n        h(y)\n"
    )
    var result = instrument(source, String("m"))
    # The closer must come after h(y), not before it.
    assert_true(result.text.find("h(y)") < result.text.find("_cov_loop_2 > 0)"))


def test_pragma_excludes_a_loop_from_branch_measurement() raises:
    var source = String(
        "def f(n: Int):\n    for i in range(n):  # pragma: no branch\n"
        "        g(i)\n"
    )
    var result = instrument(source, String("m"))
    assert_equal(len(result.branches), 0)
    assert_true("_cov_loop" not in result.text)


def test_pragma_excludes_a_decision_from_branch_measurement() raises:
    var source = String(
        "def f(a: Int):\n    if a > 0:  # pragma: no branch\n        return 1\n"
    )
    var result = instrument(source, String("m"))
    assert_equal(len(result.branches), 0)
    assert_true('_cov_branch("' not in result.text)


def test_pragma_still_leaves_the_line_measured() raises:
    # Opting out of branch measurement must not opt out of line measurement.
    var source = String(
        "def f(a: Int):\n    if a > 0:  # pragma: no branch\n        return 1\n"
    )
    var result = instrument(source, String("m"))
    assert_equal(result.lines, [2, 3])


def test_a_multi_line_for_header_is_joined_before_instrumenting() raises:
    # The formatter splits a long header like this. The loop prologue must
    # land after the whole header, not inside the range() argument list.
    var source = String(
        "def f(n: Int):\n    for i in range(\n        n\n    ):\n        g(i)\n"
    )
    var result = instrument(source, String("m"))
    assert_equal(result.branches, [2])
    assert_true(
        "for i in range( n ):\n        _cov_loop_2 += 1\n" in result.text
    )
    assert_true('_ = _cov_branch("m:2", _cov_loop_2 > 0)' in result.text)


def test_a_pragma_on_a_continuation_line_excludes_the_loop() raises:
    var source = String(
        "def f(n: Int):\n    for i in range(\n        n\n"
        "    ):  # pragma: no branch\n        g(i)\n"
    )
    var result = instrument(source, String("m"))
    assert_equal(len(result.branches), 0)
    assert_true("_cov_loop" not in result.text)


def test_a_pragma_on_a_continuation_line_excludes_the_decision() raises:
    var source = String(
        "def f(a: Int):\n    if (\n        a > 0\n"
        "    ):  # pragma: no branch\n        return 1\n"
    )
    var result = instrument(source, String("m"))
    assert_equal(len(result.branches), 0)
    assert_true('_cov_branch("' not in result.text)


def test_the_word_for_inside_a_docstring_is_not_a_loop() raises:
    var source = String(
        'def f():\n    """Doc.\n\n    for i in x:\n    """\n    return 1\n'
    )
    var result = instrument(source, String("m"))
    assert_equal(len(result.branches), 0)


def test_a_literal_condition_is_not_a_decision() raises:
    # `while True:` has one outcome by definition; wrapping it would report
    # a False that can never happen.
    var source = String("def f():\n    while True:\n        break\n")
    var result = instrument(source, String("m"))
    assert_equal(len(result.branches), 0)
    assert_true('_cov_branch("' not in result.text)


def test_the_word_if_inside_a_docstring_is_not_a_branch() raises:
    var source = String(
        'def f():\n    """Doc.\n\n    if a > 0:\n    """\n    return 1\n'
    )
    var result = instrument(source, String("m"))
    assert_equal(len(result.branches), 0)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
