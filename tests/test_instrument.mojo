# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Tests for `coverage.instrument`."""

from coverage.instrument import (
    instrument,
    split_conditions,
    _codepoint_count,
    _is_group,
    _physical_lines,
    _separator_at,
    _statement_colon,
    _strip_comment,
    _substring,
    _word_at,
    _wrap_condition,
)
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
        "if _cov_eval_begin(_cov_eval_state0, 2) and"
        ' _cov_eval_finish(_cov_eval_leaf(a > 0, _cov_eval_state0, "m:2.0", 0)'
        ' and _cov_eval_leaf(a < 9, _cov_eval_state0, "m:2.1", 1),'
        ' _cov_eval_state0, "m:2"):'
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
        '_cov_eval_leaf(a > 0, _cov_eval_state0, "m:2.0", 0) and'
        ' _cov_eval_leaf(b > 0, _cov_eval_state0, "m:2.1", 1) or'
        ' _cov_eval_leaf(a < 0, _cov_eval_state0, "m:2.2", 2)'
        in result.text
    )


def test_negated_group_measures_its_leaves() raises:
    var source = String(
        "def f(a: Int, b: Int):\n    if not (a and b):\n        return 1\n"
    )
    var result = instrument(source, String("m"))
    assert_equal(result.conditions, [2])
    assert_true(
        "if _cov_eval_begin(_cov_eval_state0, 2) and _cov_eval_finish(not"
        ' (_cov_eval_leaf(a, _cov_eval_state0, "m:2.0", 0) and'
        ' _cov_eval_leaf(b, _cov_eval_state0, "m:2.1", 1)), _cov_eval_state0,'
        ' "m:2"):'
        in result.text
    )


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
    assert_true(
        '_cov_eval_leaf(android, _cov_eval_state0, "m:2.0", 0)' in result.text
    )
    assert_true(
        '_cov_eval_leaf(original, _cov_eval_state0, "m:2.1", 1)' in result.text
    )


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
    assert_equal(result.conditions, [2])
    assert_true(
        '_cov_eval_finish((_cov_eval_leaf(a > 0, _cov_eval_state0, "m:2.0", 0)'
        ' and _cov_eval_leaf(a < 9, _cov_eval_state0, "m:2.1", 1)),'
        ' _cov_eval_state0, "m:2")'
        in result.text
    )


def test_comments_inside_a_multi_line_condition_do_not_swallow_code() raises:
    # Joining the lines naively would put `and a < 9` after the `#`.
    var source = String(
        "def f(a: Int):\n    if (  # start\n        a > 0  # positive\n"
        "        and a < 9\n    ):\n        return 1\n"
    )
    var result = instrument(source, String("m"))
    assert_equal(result.conditions, [2])
    assert_true(
        '_cov_eval_finish((_cov_eval_leaf(a > 0, _cov_eval_state0, "m:2.0", 0)'
        ' and _cov_eval_leaf(a < 9, _cov_eval_state0, "m:2.1", 1)),'
        ' _cov_eval_state0, "m:2")'
        in result.text
    )


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


def test_loop_entry_uses_actual_body_width_after_comments() raises:
    for width in [1, 2, 3, 4, 8]:
        var parent = " " * width
        var body = " " * (width * 2)
        var source = (
            "def f():\n"
            + parent
            + "for index in range(2):  # header\n"
            + "\n# left comment\n"
            + "                    # right comment\n"
            + body
            + "print(index)\n"
        )
        var result = instrument(source, "m")
        assert_equal(result.lines, [2, 6])
        assert_equal(result.branches, [2])
        assert_equal(result.conditions, [0])
        assert_true("\n" + body + "_cov_loop_2 += 1\n" in result.text)
        assert_true("\n# left comment\n" in result.text)
        assert_true("                    # right comment\n" in result.text)


def test_multiline_loop_uses_body_not_header_continuation_indent() raises:
    var source = String(
        "def f():\n  for index in range(\n              2\n  ):\n"
        "\n# note\n       print(index)\n"
    )
    var result = instrument(source, "m")
    assert_equal(result.lines, [2, 7])
    assert_equal(result.branches, [2])
    assert_true(
        "for index in range( 2 ):\n       _cov_loop_2 += 1\n" in result.text
    )


def test_loop_else_probe_precedes_its_body_and_keeps_header_adjacent() raises:
    var source = String(
        "def f():\n  for index in range(0):\n    print(index)\n"
        "  else:  # empty\n\n# note\n       return 1\n"
    )
    var result = instrument(source, "m")
    assert_equal(result.lines, [2, 3, 7])
    assert_equal(result.branches, [2])
    assert_true(
        "    print(index)\n  else:  # empty\n"
        '       _ = _cov_branch("m:2", _cov_loop_2 > 0)\n'
        in result.text
    )
    assert_true(
        '\n  _ = _cov_branch("m:2", _cov_loop_2 > 0)' not in result.text
    )


def test_loop_else_accepts_space_before_colon_without_a_line_probe() raises:
    for header in [String("else : # spaced"), String("else\t: # tab")]:
        var result = instrument(
            "def f():\n  for index in range(0):\n    print(index)\n  "
            + header
            + "\n    return 1\n",
            "m",
        )
        assert_equal(result.lines, [2, 3, 5])
        assert_equal(result.branches, [2])
        assert_true(
            "    print(index)\n  "
            + header
            + '\n    _ = _cov_branch("m:2", _cov_loop_2 > 0)\n'
            in result.text
        )


def test_physical_lines_preserve_tabs_and_crlf_source_identities() raises:
    var source = String(
        "def f():\r\n  for index in range(2):\r\n"
        '    print("left\tright", index)\r\n'
        "  else\t: # header\r\n    return 1\r\n"
    )
    var result = instrument(source, "m")
    assert_equal(result.lines, [2, 3, 5])
    assert_equal(result.branches, [2])
    assert_true('    print("left\tright", index)\r\n' in result.text)
    assert_true("  else\t: # header\r\n" in result.text)
    assert_equal(instrument(String("\n\n"), "m").text, String("\n\n"))


def test_physical_line_endings_and_unterminated_final_line() raises:
    var lines = _physical_lines("one\ttwo\r\nthree\rfour\nlast")
    assert_equal(len(lines), 4)
    assert_equal(lines[0].text, String("one\ttwo"))
    assert_equal(lines[0].ending, String("\r\n"))
    assert_equal(lines[1].text, String("three"))
    assert_equal(lines[1].ending, String("\r"))
    assert_equal(lines[2].text, String("four"))
    assert_equal(lines[2].ending, String("\n"))
    assert_equal(lines[3].text, String("last"))
    assert_equal(lines[3].ending, String("\n"))
    assert_equal(len(_physical_lines(String(""))), 0)
    assert_equal(len(_physical_lines(String("\r"))), 1)
    assert_equal(len(_physical_lines(String("\n"))), 1)
    var final = instrument("def f():\n  return 1", "m")
    var terminated = instrument("def f():\n  return 1\n", "m")
    assert_equal(final.text, terminated.text)
    assert_equal(final.lines, [2])


def test_multiline_loop_header_retains_literal_line_ending_bytes() raises:
    for ending in [String("\n"), String("\r\n"), String("\r")]:
        var literal = '"""left\tvalue' + ending + 'right"""'
        var result = instrument(
            "def f():"
            + ending
            + "  for index in range(String("
            + literal
            + ").byte_length()):"
            + ending
            + "    print(index)"
            + ending,
            "m",
        )
        assert_equal(result.lines, [2, 4])
        assert_equal(result.branches, [2])
        assert_true(literal in result.text)


def test_comments_stop_at_each_supported_physical_line_ending() raises:
    for ending in [String("\n"), String("\r\n"), String("\r")]:
        var text = "if (a # comment" + ending + " and b):"
        assert_equal(_statement_colon(text), _codepoint_count(text) - 1)
        assert_equal(_strip_comment(text), "if (a " + ending + " and b):")


def test_outer_loop_else_closes_inner_loop_before_its_header() raises:
    var result = instrument(
        String(
            "def f():\n  for outer in range(2):\n"
            "    for inner in range(2):\n      print(inner)\n"
            "  else:\n    return 1\n"
        ),
        "m",
    )
    assert_equal(result.branches, [2, 3])
    assert_true(
        '    _ = _cov_branch("m:3", _cov_loop_3 > 0)\n'
        '  else:\n    _ = _cov_branch("m:2", _cov_loop_2 > 0)\n'
        in result.text
    )


def test_if_else_inside_loop_does_not_take_its_final_probe() raises:
    var result = instrument(
        String(
            "def f():\n  for index in range(2):\n"
            "    if index == 0:\n      continue\n"
            "    else:\n      print(index)\n"
        ),
        "m",
    )
    assert_true(
        '    else:\n      _cov_hit("m:6")\n      print(index)\n'
        '  _ = _cov_branch("m:2", _cov_loop_2 > 0)\n'
        in result.text
    )


def test_inline_loop_and_loop_else_bodies_fail_explicitly() raises:
    for source in [
        String("def f():\n  for index in range(2): print(index)\n"),
        String("def f():\n  for index in range(\n      2\n  ): print(index)\n"),
        String(
            "def f():\n  for index in range(2): print(index) # pragma: no"
            " branch\n"
        ),
        String(
            "def f():\n  for index in range(2):\n    pass\n  else: return 1\n"
        ),
    ]:
        var raised = False
        try:
            _ = instrument(source, "m")
        except error:
            raised = "does not support inline" in String(error)
        assert_true(raised)


def test_loop_with_no_indented_body_fails_explicitly() raises:
    for source in [
        String("def f():\n  for index in range(2):\n"),
        String("def f():\n  for index in range(2):\n# comment\n\n  return 1\n"),
        String("def f():\n  for index in range(2):\n    pass\n  else:\n"),
    ]:
        var raised = False
        try:
            _ = instrument(source, "m")
        except error:
            raised = "requires an indented body" in String(error)
        assert_true(raised)


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


def test_escaped_literals_preserve_decisions_and_comments() raises:
    var condition = String('value == "\\" and #:( or ["')
    assert_equal(split_conditions(condition), [condition])
    assert_equal(len(split_conditions(condition + " and flag")), 3)
    var result = instrument(
        String(
            'def f(value: String) -> Int:\n    if value == "\\" and #:( or'
            ' [":\n        return 1\n    return 0\n'
        ),
        "escaped",
    )
    assert_equal(result.lines, [2, 3, 4])
    assert_equal(result.branches, [2])
    assert_equal(result.conditions, [0])
    assert_true(condition in result.text)
    var multiline = instrument(
        String(
            'def f(value: String) -> Int:\n    if value == (\n        "\\"#:('
            ' and or ["\n    ):\n        return 1\n    return 0\n'
        ),
        "multiline",
    )
    assert_equal(multiline.lines, [2, 5, 6])
    assert_equal(multiline.branches, [2])
    assert_true(String('"\\"#:( and or ["') in multiline.text)


def test_redundant_groups_and_negations_keep_leaf_order() raises:
    var result = instrument(
        String(
            "def f():\n    if (((a or (b and not (c or not d))))):\n"
            "        return 1\n"
        ),
        "m",
    )
    assert_equal(result.conditions, [4])
    assert_true(
        '(((_cov_eval_leaf(a, _cov_eval_state0, "m:2.0", 0) or'
        ' (_cov_eval_leaf(b, _cov_eval_state0, "m:2.1", 1) and not'
        ' (_cov_eval_leaf(c, _cov_eval_state0, "m:2.2", 2) or not'
        ' _cov_eval_leaf(d, _cov_eval_state0, "m:2.3", 3)))))),'
        ' _cov_eval_state0, "m:2"):'
        in result.text
    )


def test_call_index_and_comparison_are_atomic_leaves() raises:
    var result = instrument(
        String(
            'def f():\n    if (call(a or b, "and") and '
            "items[index(a and b)] or (a or b) == c):\n        return 1\n"
        ),
        "m",
    )
    assert_equal(result.conditions, [3])
    assert_true(
        '_cov_eval_leaf(call(a or b, "and"), _cov_eval_state0, "m:2.0", 0)'
        in result.text
    )
    assert_true(
        '_cov_eval_leaf(items[index(a and b)], _cov_eval_state0, "m:2.1", 1)'
        in result.text
    )
    assert_true(
        '_cov_eval_leaf((a or b) == c, _cov_eval_state0, "m:2.2", 2)'
        in result.text
    )


def test_tabs_and_adjacent_groups_delimit_logical_keywords() raises:
    var result = instrument(
        String("def f():\n    if ((a)and(b))or\tnot(c):\n        return 1\n"),
        "m",
    )
    assert_equal(result.conditions, [3])
    assert_true(
        '((_cov_eval_leaf(a, _cov_eval_state0, "m:2.0", 0)) and'
        ' (_cov_eval_leaf(b, _cov_eval_state0, "m:2.1", 1))) or not'
        ' (_cov_eval_leaf(c, _cov_eval_state0, "m:2.2", 2))'
        in result.text
    )


def test_single_leaf_redundant_groups_keep_original_spelling() raises:
    var result = instrument(
        String("def f():\n    if ((not ( a ))):\n        return 1\n"), "m"
    )
    assert_equal(result.conditions, [0])
    assert_true('_cov_branch("m:2", ((not ( a ))))' in result.text)


def test_multiline_elif_and_while_keep_all_grouped_leaves() raises:
    var result = instrument(
        String(
            "def f():\n    if a:\n        return 0\n"
            "    elif (\n        a or not (b and c)  # grouped\n"
            "    ):\n        return 1\n"
            "    while (\n        (a and b) or c\n    ):\n        break\n"
        ),
        "m",
    )
    assert_equal(result.branches, [2, 4, 8])
    assert_equal(result.conditions, [0, 3, 3])
    assert_true(
        '_cov_eval_leaf(c, _cov_eval_state0, "m:4.2", 2)' in result.text
    )
    assert_true(
        '_cov_eval_leaf(c, _cov_eval_state0, "m:8.2", 2)' in result.text
    )


def test_escaped_quotes_inside_groups_do_not_create_leaves() raises:
    var result = instrument(
        String(
            'def f():\n    if ((value == "\\" and #:( or [") or '
            "other == 'and or )'):\n        return 1\n"
        ),
        "m",
    )
    assert_equal(result.conditions, [2])
    assert_true(
        '_cov_eval_leaf(value == "\\" and #:( or [", _cov_eval_state0,'
        ' "m:2.0", 0)'
        in result.text
    )
    assert_true("other == 'and or )'" in result.text)


def test_conditional_expressions_stay_opaque() raises:
    for expression in [
        String("a if choose else b and c"),
        String("(a and b) if choose else (c or d)"),
        String("not a if choose else b"),
    ]:
        var result = instrument(
            "def f():\n    if " + expression + ":\n        return 1\n", "m"
        )
        assert_equal(result.conditions, [0])
        assert_true('_cov_branch("m:2", ' + expression + ")" in result.text)
    var compound = instrument(
        String(
            "def f():\n    if (not a if choose else b) or c:\n        pass\n"
        ),
        "m",
    )
    assert_equal(compound.conditions, [2])
    assert_true(
        '_cov_eval_leaf(not a if choose else b, _cov_eval_state0, "m:2.0", 0)'
        in compound.text
    )


def test_membership_and_chained_comparisons_stay_atomic() raises:
    var result = instrument(
        String(
            "def f():\n    if (0 < 1 not in values and flag):\n        pass\n"
        ),
        "m",
    )
    assert_equal(result.conditions, [2])
    assert_true(
        '_cov_eval_leaf(0 < 1 not in values, _cov_eval_state0, "m:2.0", 0)'
        in result.text
    )


def test_empty_and_incomplete_parser_inputs_are_retained() raises:
    assert_equal(_substring(String(""), 0, 0), String(""))
    assert_equal(_codepoint_count(String("")), 0)
    assert_equal(_statement_colon(String("")), -1)
    assert_equal(_strip_comment(String("")), String(""))
    assert_true(_word_at(List[String](), 0, String("")))
    assert_equal(split_conditions(String("")), [String("")])
    assert_equal(instrument(String(""), String("m")).text, String(""))
    var incomplete = instrument(String("def f():\n    if (\n"), String("m"))
    assert_true(incomplete.text.endswith("    if (\n"))
    assert_equal(_wrap_condition("if x", "if ", "m:2").text, String("if x"))
    assert_equal(_wrap_condition("if :", "if ", "m:2").text, String("if :"))


def test_group_scanner_handles_other_brackets_and_incomplete_text() raises:
    assert_true(_is_group(String("(items[{1: 2}[1]])")))
    assert_equal(_is_group(String("(open")), False)
    assert_equal(_strip_comment(String("'#' # outside")), String("'#'"))
    assert_equal(_separator_at([String("o"), String("r")], 0), String(" or "))
    assert_equal(
        split_conditions(String("notable and orphan")),
        [String("notable"), String(" and "), String("orphan")],
    )
    var source = String(
        "    stray\ndef f():\n    var values = (\n        1\n    )\n    while"
        " False:\n        pass\n    if # incomplete\n    :\n        pass\n   "
        " if notable and flag:\n        pass\n"
    )
    var result = instrument(source, String("m"))
    assert_true("    stray\n" in result.text)
    assert_true("while False:" in result.text)
    assert_true(
        '_cov_eval_leaf(notable, _cov_eval_state0, "m:11.0", 0)' in result.text
    )


def test_triple_quoted_operands_preserve_internal_quotes() raises:
    var result = instrument(
        String(
            'def f():\n    if (a or text == """hello" and )#[word"""):\n'
            "        return 1\n    return 0\n"
        ),
        "m",
    )
    assert_equal(result.conditions, [2])
    assert_equal(result.lines, [2, 3, 4])
    assert_true(
        '_cov_eval_leaf(text == """hello" and )#[word""", _cov_eval_state0,'
        ' "m:2.1", 1)'
        in result.text
    )


def test_multiline_literal_bytes_survive_header_rewriting() raises:
    var literal = String('"""hello"  \n# ) and or\nworld"""')
    var result = instrument(
        "def f():\n    if (a or text == "
        + literal
        + "):\n        return 1\n    return 0\n",
        "m",
    )
    assert_equal(result.conditions, [2])
    assert_equal(result.lines, [2, 5, 6])
    assert_true(literal in result.text)
    assert_true(
        "_cov_eval_leaf(text == " + literal + ', _cov_eval_state0, "m:2.1", 1)'
        in result.text
    )


def test_multiline_constant_does_not_hide_code_or_attract_imports() raises:
    var result = instrument(
        String(
            'comptime TEXT = """quoted\ndef fake():\n# ) ( and or\n"""\n'
            "def real():\n    if a and b:\n        return 1\n"
        ),
        "m",
    )
    assert_equal(result.lines, [6, 7])
    assert_equal(result.conditions, [2])
    assert_true(
        result.text.startswith('comptime TEXT = """quoted\ndef fake():')
    )
    assert_true(
        result.text.find("from coverage.runtime")
        > result.text.find("# ) ( and or")
    )


def test_literal_and_comment_token_boundaries() raises:
    assert_equal(_statement_colon("if (\n# comment\n a):"), 18)
    assert_equal(_strip_comment("a # comment\n and b"), String("a \n and b"))
    assert_equal(
        split_conditions("value == 'unfinished"),
        [String("value == 'unfinished")],
    )
    assert_equal(_is_group("('unfinished"), False)
    for condition in [
        String('text == "" and flag'),
        String('text == "" + "x" and flag'),
        String('text == """hello""x""" and flag'),
    ]:
        var result = instrument(
            "def f():\n    if (" + condition + "):\n        pass\n", "m"
        )
        assert_equal(result.conditions, [2])


def test_triple_literal_can_start_on_a_continuation_line() raises:
    for literal in [
        String("'''hello' and # (\nworld'''"),
        String('"""hello" or # (\nworld"""'),
    ]:
        var first = instrument(
            "def f():\n    if (text == "
            + literal
            + " and flag):\n        pass\n",
            "m",
        )
        var later = instrument(
            "def f():\n    if (text ==\n        "
            + literal
            + " and flag):\n        pass\n",
            "m",
        )
        assert_equal(first.conditions, [2])
        assert_equal(later.conditions, [2])
        assert_true(literal in first.text)
        assert_true(literal in later.text)


def test_buffers_belong_only_to_functions_with_compound_decisions() raises:
    var result = instrument(
        (
            "def simple():\n    if a:\n        return 1\n"
            "def compound():\n    if a and b:\n        return 2\n"
        ),
        "m",
    )
    assert_true("var _cov_eval_state0" not in result.text)
    assert_true("var _cov_eval_state1 = _cov_eval_buffer()" in result.text)


def test_nested_definitions_get_separate_invocation_buffers() raises:
    var result = instrument(
        (
            "def outer():\n    def inner():\n        if a and b:\n           "
            " return 1\n    if c and inner():\n        return 2\n"
        ),
        "m",
    )
    assert_true(
        "    var _cov_eval_state0 = _cov_eval_buffer()\n    def inner():"
        in result.text
    )
    assert_true(
        "        var _cov_eval_state1 = _cov_eval_buffer()" in result.text
    )
    assert_true(
        '_cov_eval_leaf(inner(), _cov_eval_state0, "m:5.1", 1)' in result.text
    )


def test_new_generated_names_do_not_collide_with_source_identifiers() raises:
    var result = instrument(
        (
            "def f():\n    var _cov_eval_state0 = True\n"
            "    if _cov_eval_state0 and other:\n        return 1\n"
        ),
        "m",
    )
    assert_true("var _cov_eval__state0 = _cov_eval__buffer()" in result.text)
    assert_true(
        '_cov_eval__leaf(_cov_eval_state0, _cov_eval__state0, "m:3.0", 0)'
        in result.text
    )


def test_oversized_records_fail_instead_of_removing_obligations() raises:
    for source in [
        "def f():\n    if " + "a and " * 500 + "a:\n        pass\n",
    ]:
        var raised = False
        try:
            _ = instrument(source, "m")
        except error:
            raised = "atomic record limit" in String(error)
        assert_true(raised)
    var raised = False
    try:
        _ = instrument("def f():\n    return 1\n", "é" * 250)
    except error:
        raised = "atomic record limit" in String(error)
    assert_true(raised)


def test_buffer_uses_the_actual_function_body_indentation() raises:
    var result = instrument("def f():\n  if a and b:\n    return 1\n", "m")
    assert_true(
        "\n  var _cov_eval_state0 = _cov_eval_buffer()\n" in result.text
    )


def test_instrumentation_checks_exact_utf8_record_boundaries() raises:
    for size in [511, 512, 513]:
        # COVEVAL2: + UTF-8 "é:2" + :T: + vector + semicolon/newline.
        var width = size - 18
        var source = (
            "def f():\n    if " + "a and " * (width - 1) + "a:\n        pass\n"
        )
        var raised = False
        try:
            var result = instrument(source, "é")
            assert_equal(result.conditions, [width])
        except error:
            raised = True
        assert_equal(raised, size == 513)


def test_trait_defaults_have_probes_and_private_buffers() raises:
    var source = String(
        '"""Module."""\ntrait Defaults:\n'
        "    def abstract(self):\n        ... # declaration\n"
        '    def concrete(self):\n        """Default."""\n'
        "        if left and right:\n            return True\n"
        "        return False\n"
    )
    var result = instrument(source, "m")
    assert_equal(result.lines, [7, 8, 9])
    assert_equal(result.branches, [7])
    assert_equal(result.conditions, [2])
    assert_true(result.text.startswith('"""Module."""\nfrom coverage.runtime'))
    assert_true("var _cov_eval_state0" not in result.text)
    assert_true(
        '        """Default."""\n'
        "        var _cov_eval_state1 = _cov_eval_buffer()\n"
        in result.text
    )
    assert_true(
        '_cov_eval_leaf(left, _cov_eval_state1, "m:7.0", 0)' in result.text
    )
    assert_true("        ... # declaration\n" in result.text)


def test_all_generated_names_avoid_the_entire_source() raises:
    var source = String(
        "def outer(_cov_hit: Int, _cov_branch: Int):\n"
        "    var _cov_hit_ = 2\n"
        "    var _cov_branch_ = 3\n"
        "    var _cov_loop_7 = 40\n"
        "    var _cov_loop__7 = 50\n"
        "    var _cov_eval_buffer = 60\n"
        "    for index in range(2):\n"
        "        if index > 0:\n            print(_cov_hit)\n"
        "    def inner(_cov_eval_state0: Int):\n"
        "        if _cov_branch > 0 and _cov_branch_ > 0:\n"
        "            return _cov_loop_7\n"
        "        return _cov_loop__7\n"
        "    return inner(_cov_eval_buffer)\n"
    )
    var result = instrument(source, "m")
    assert_true("hit as _cov_hit__, branch as _cov_branch__" in result.text)
    assert_true('if _cov_branch__("m:8", index > 0):' in result.text)
    assert_true("var _cov_loop___7 = 0" in result.text)
    assert_true('_ = _cov_branch__("m:7", _cov_loop___7 > 0)' in result.text)
    assert_true("var _cov_eval__state1 = _cov_eval__buffer()" in result.text)
    assert_equal(result.lines, [2, 3, 4, 5, 6, 7, 8, 9, 11, 12, 13, 14])
    assert_equal(result.branches, [7, 8, 11])
    assert_equal(result.conditions, [0, 0, 2])


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
