# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""The coverage reducer keeps each probe once and refuses a bad record."""

from std.testing import TestSuite, assert_equal, assert_raises, assert_true

from tests._tree import tool_mojo
from tools._process import run_program, shell_quote
from tools.coverage_io import Reducer


def _repeat(text: String, count: Int) -> String:
    """Return `text` repeated `count` times.

    Args:
        text: The text.
        count: How many copies.

    Returns:
        The joined copies.
    """
    var out = String()
    var index = 0
    while index < count:
        out += text
        index += 1
    return out


def _feed(mut reducer: Reducer, lines: List[String]) raises:
    """Feed every line to `reducer`.

    Args:
        reducer: The reducer.
        lines: The raw lines.

    Raises:
        Error: If a line is a malformed probe.
    """
    for line in lines:
        reducer.feed(line)


def test_order_vectors_and_abandoned_hits_stay_distinct() raises:
    """Each distinct probe is kept, and a repeated copy adds nothing."""
    var lines = List[String]()
    lines.append("COVLINE:recursive:1.0:T\n")
    lines.append("COVLINE:recursive:1.0:F\n")
    lines.append("COVEVAL2:recursive:1:F:F-;\n")
    lines.append("COVLINE:abandoned:2.0:T\n")
    lines.append("COVEVAL2:recursive:1:F:TF;\n")
    lines.append("COVEVAL2:recursive:1:T:TT;\n")
    lines.append("COVEVAL2:callback:1:F:TF;\n")
    lines.append("COVEVAL2:callback:1:T:TF;\n")
    lines.append("COVLINE:recursive:1:T\n")
    lines.append("COVBRANCH:simple:3:F\n")
    lines.append("exception from abandoned evaluation\n")
    var reducer = Reducer()
    _feed(reducer, lines)
    var expected = String()
    var index = 0
    while index < 9:
        expected += lines[index]
        index += 1
    expected += "COVLINE:simple:3:F\n"
    expected += lines[9]
    expected += lines[10]
    assert_equal(reducer.output, expected)
    assert_equal(len(reducer.evaluations), 6)
    var again = List[String]()
    index = 0
    while index < 100:
        var copy = 0
        while copy < 10:
            again.append(lines[copy])
            copy += 1
        index += 1
    _feed(reducer, again)
    assert_equal(reducer.output, expected)


def test_whitespace_variants_collapse_and_bad_records_raise() raises:
    """Only a complete evaluation is kept, and a bad record is never cached."""
    var complete = "COVEVAL2:m:4:T:TT;\n"
    var variants = List[String]()
    variants.append(complete)
    variants.append(" " + complete)
    variants.append(
        String(complete[byte = : complete.byte_length() - 1]) + "\r\n"
    )
    variants.append("\t" + complete)
    variants.append(
        String(complete[byte = : complete.byte_length() - 1]) + " \n"
    )
    var reducer = Reducer()
    _feed(reducer, variants)
    assert_equal(reducer.output, complete)
    assert_equal(reducer.accepted_count, 5)
    var bad = List[String]()
    bad.append("COVEVAL2:m:4:T:TT\n")
    bad.append("COVEVAL2:m:4:T:T;\n")
    bad.append("COVEVAL2:m:4:T:--;\n")
    bad.append("COVEVAL2:m:4:T:TX;\n")
    bad.append("COVEVAL2:m:4:garbage:TT;\n")
    bad.append("COVEVAL2:m:4.0:T:TT;\n")
    bad.append("COVEVAL2:m:0:T:TT;\n")
    bad.append("COVEVAL2::4:T:TT;\n")
    bad.append("COVEVAL2:m:4:T:" + _repeat("T", 512) + ";\n")
    bad.append("COVBRANCH:m:4.0:T\n")
    bad.append("COVBRANCH:m:4:garbage\n")
    bad.append("COVBRANCH:m:0:T\n")
    bad.append("COVBRANCH::4:T\n")
    bad.append("COVEVAL2:m:4:F:?-;\n")
    bad.append("COVEVAL2:m:4:T:F?;\n")
    bad.append(String(complete[byte = : complete.byte_length() - 1]))
    for line in bad:
        with assert_raises():
            reducer.feed(line)
        assert_true(not line in reducer.accepted)
    assert_equal(reducer.output, complete)


def test_diagnostics_are_repeated_and_long_hits_are_not_cached() raises:
    """Ordinary text is copied every time, and an oversized hit is not stored.
    """
    var rows = List[String]()
    rows.append("hello\n")
    rows.append("COVBRANCH:unparsed\n")
    rows.append(" COVBRANCH: \n")
    rows.append("COVBRANCH:\n")
    rows.append("COVEVAL:old\n")
    rows.append("\n")
    rows.append("no newline")
    var reducer = Reducer()
    var round = 0
    while round < 3:
        _feed(reducer, rows)
        round += 1
    var expected = String()
    round = 0
    while round < 3:
        for line in rows:
            expected += line
        round += 1
    assert_equal(reducer.output, expected)
    assert_equal(reducer.accepted_count, 0)
    var prefix = "COVEVAL2:é:1:T:"
    var sizes = List[Int]()
    sizes.append(511)
    sizes.append(512)
    sizes.append(513)
    var sized = Reducer()
    var kept = String()
    for size in sizes:
        var fill = size - prefix.byte_length() - 2
        var line = prefix + _repeat("T", fill) + ";\n"
        assert_equal(line.byte_length(), size)
        if size <= 512:
            sized.feed(line)
            kept += line
        else:
            with assert_raises(contains="Malformed or truncated"):
                sized.feed(line)
    assert_equal(sized.output, kept)
    var long_line = "COVLINE:" + _repeat("x", 10000) + "\n"
    var wide = Reducer()
    wide.feed(long_line)
    wide.feed(long_line)
    assert_equal(wide.output, "COVLINE:" + _repeat("x", 10000) + "\n")
    assert_equal(wide.accepted_count, 0)


def test_the_cache_is_bounded_and_a_cold_window_bypasses() raises:
    """The cache stays within its capacity, and a cold window stops caching."""
    var reducer = Reducer()
    var index = 0
    while index < 4097:
        reducer.feed("COVLINE:m:" + String(index) + "\n")
        assert_true(reducer.accepted_count <= 4096)
        index += 1
    var output = reducer.output
    index = 0
    while index < 4097:
        reducer.feed("COVLINE:m:" + String(index) + "\n")
        index += 1
    assert_equal(reducer.output, output)
    var cold = Reducer()
    index = 0
    while index < 1024:
        cold.feed("COVLINE:cold:" + String(index) + "\n")
        index += 1
    var hot = "COVEVAL2:hot:1:T:TT;\n"
    index = 0
    while index < 16384:
        cold.feed(hot)
        assert_true(cold.bypassing)
        assert_equal(cold.accepted_count, 0)
        assert_equal(cold.remaining, 16383 - index)
        index += 1
    cold.feed(hot)
    assert_true(not cold.bypassing)
    assert_true(hot in cold.accepted)
    var window = Reducer()
    var hits = 255
    index = 0
    while index < hits + 1:
        window.feed("COVLINE:hot:1\n")
        index += 1
    index = 0
    while index < 1023 - hits:
        window.feed("COVLINE:cold:" + String(index) + "\n")
        index += 1
    assert_equal(window.remaining, 0)
    assert_equal(window.hits, hits)
    window.feed("diagnostic\n")
    assert_true(window.bypassing)


def test_a_capture_keeps_reduced_records_and_a_signal_status() raises:
    """Repeated probes are stored once, and SIGTERM is 128 plus the signal."""
    var mojo = tool_mojo()
    var ran = run_program(
        [
            "sh",
            "-c",
            "dir=$(mktemp -d); cat > \"$dir/probe.py\" << 'PY'\n"
            "import sys\n"
            "sys.stderr.write('COVLINE:m:1\\nCOVEVAL2:m:2:T:TT;\\n' * 20)\n"
            "sys.stderr.write('diagnostic\\n' * 3)\n"
            "sys.stdout.write('stdout intact\\n')\n"
            "raise SystemExit(7)\n"
            "PY\n"
            "sh tools/tool.sh "
            + shell_quote(mojo)
            + ' coverage_io capture --out "$dir/out" --err "$dir/err.gz" --'
            ' python3 "$dir/probe.py" > "$dir/progress"\n'
            "status=$?\n"
            'printf "STDOUT %s" "$(cat "$dir/out")"\n'
            'gzip -dc "$dir/err.gz"\n'
            "echo STATUS $status\n"
            'cat "$dir/progress"\n',
        ],
        20.0,
        merge_errors=False,
    )
    if ran.status != 0:
        raise Error(ran.errors)
    assert_true(ran.output.find("STDOUT stdout intact") >= 0)
    assert_true(
        ran.output.find(
            "COVLINE:m:1\nCOVEVAL2:m:2:T:TT;\ndiagnostic\ndiagnostic\ndiagnostic\n"
        )
        >= 0
    )
    assert_true(ran.output.find("STATUS 7") >= 0)
    assert_true(ran.output.find("complete (exit 7)") >= 0)
    var signaled = run_program(
        [
            "sh",
            "-c",
            "out=$(mktemp); err=$(mktemp).txt.gz; sh tools/tool.sh "
            + shell_quote(mojo)
            + ' coverage_io capture --out "$out" --err "$err" -- sh -c'
            " 'kill -TERM $$'; echo STATUS $?",
        ],
        20.0,
        merge_errors=False,
    )
    assert_true(signaled.output.find("STATUS 143") >= 0)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
