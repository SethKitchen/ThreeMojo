# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Keep native fault qualification explicit and fail closed on bad receipts.

A recording runner stands in for the C compiler and the harness, so no test
compiles C.
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
from tools._process import ProcessResult
from tools.coverage_hit_faults import (
    HARNESS,
    SOURCE,
    Options,
    Runner,
    fault_receipt,
    preflight,
)

comptime Outcome = Tuple[Int, String, String]
"""A stand-in program's status, standard output and standard error."""


struct Recorder(Movable, Runner):
    """Return planned outcomes and record each call."""

    var outcomes: List[Outcome]
    """The outcomes still to give, in order."""
    var commands: List[List[String]]
    """Each command run."""
    var timeouts: List[Float64]
    """Each call's time limit."""
    var touch: String
    """A file to change on each call, or empty."""

    def __init__(out self, var outcomes: List[Outcome], touch: String = ""):
        """Plan the outcomes.

        Args:
            outcomes: The outcomes to give, in order.
            touch: A file to change on each call, or empty.
        """
        self.outcomes = outcomes^
        self.commands = List[List[String]]()
        self.timeouts = List[Float64]()
        self.touch = touch

    def run(
        mut self, arguments: List[String], timeout: Float64
    ) raises -> ProcessResult:
        """Record a call and give the next outcome.

        Args:
            arguments: The program and its arguments.
            timeout: The time limit in seconds.

        Returns:
            The next planned outcome.

        Raises:
            Error: If no outcome is left.
        """
        self.commands.append(arguments.copy())
        self.timeouts.append(timeout)
        if self.touch:
            var data = Path(self.touch).read_bytes()
            data.extend("\n/* changed */\n".as_bytes())
            Path(self.touch).write_bytes(data)
        if len(self.outcomes) == 0:
            raise Error("no outcome left")
        var outcome = self.outcomes.pop(0)
        return ProcessResult(outcome[0], outcome[1], outcome[2], False)


def _options(compile_run: Bool, source: String = "") raises -> Options:
    """Return the options for the repository's sources."""
    var root = realpath(".")
    return Options(
        source if source else root + "/" + SOURCE,
        root + "/" + HARNESS,
        "cc",
        compile_run,
        None,
    )


def test_default_remains_compiler_free_and_discloses_unrun_native_checks() raises:
    var runner = Recorder(List[Outcome]())
    var receipt = fault_receipt(_options(False), runner)
    assert_equal(receipt.native_harness, "not compiled or run")
    assert_true(
        receipt.text.find('"native_harness": "not compiled or run"') >= 0
    )
    assert_true(receipt.text.endswith('"source_unchanged": true\n}\n'))
    assert_equal(len(runner.commands), 0)


def test_failed_compilation_never_runs_or_reports_a_native_pass() raises:
    var runner = Recorder([(42, String(), String("original compiler error"))])
    var receipt = fault_receipt(_options(True), runner)
    assert_equal(receipt.native_harness, "compile failed")
    assert_true(
        receipt.text.find('"compile_stderr": "original compiler error"') >= 0
    )
    assert_true(receipt.text.find('"compile_returncode": 42') >= 0)
    assert_equal(receipt.text.find("run_returncode"), -1)
    assert_equal(len(runner.commands), 1)


def test_failed_native_control_is_preserved_and_returns_failure() raises:
    var runner = Recorder(
        [
            (0, String(), String()),
            (-6, String("prior evidence"), String("failed assertion")),
        ]
    )
    var receipt = fault_receipt(_options(True), runner)
    assert_equal(receipt.native_harness, "failed")
    assert_true(receipt.text.find('"run_returncode": -6') >= 0)
    assert_true(receipt.text.find('"run_stderr": "failed assertion"') >= 0)
    assert_equal(runner.timeouts[1], 5.0)
    assert_equal(runner.timeouts[0], 30.0)


def test_success_keeps_exact_source_harness_and_command_receipts() raises:
    var runner = Recorder(
        [(0, String(), String()), (0, String("PASS41"), String())]
    )
    var receipt = fault_receipt(_options(True), runner)
    assert_equal(receipt.native_harness, "passed")
    assert_true(receipt.text.find('"run_stdout": "PASS41"') >= 0)
    var command = runner.commands[0].copy()
    assert_equal(command[0], "cc")
    var werror = False
    for word in command:
        if word == "-Werror":
            werror = True
    assert_true(werror)
    var root = realpath(".")
    assert_equal(command[7], '-DTRANSPORT_SOURCE="' + root + "/" + SOURCE + '"')
    assert_equal(command[8], root + "/" + HARNESS)
    assert_equal(runner.commands[1][0], command[10])
    assert_true(command[10].endswith("/transport-fault-harness"))
    # Each digest has 64 hexadecimal digits.
    var at = receipt.text.find('"source_sha256": "')
    assert_equal(receipt.text[byte = at + 18 + 64 : at + 18 + 66], '",')
    at = receipt.text.find('"harness_sha256": "')
    assert_equal(receipt.text[byte = at + 19 + 64 : at + 19 + 66], '",')
    assert_true(receipt.text.endswith('"source_unchanged": true\n}\n'))
    # The keys keep the Python tool's order.
    var keys: List[String] = [
        "source",
        "source_sha256",
        "harness_sha256",
        "source_preflight",
        "native_harness",
        "compile_command",
        "compile_returncode",
        "compile_stdout",
        "compile_stderr",
        "run_returncode",
        "run_stdout",
        "run_stderr",
        "source_unchanged",
    ]
    var last = -1
    for key in keys:
        var found = receipt.text.find('\n  "' + key + '": ')
        assert_true(found > last, key)
        last = found


def test_source_drift_cannot_be_certified() raises:
    var tree = Tree()
    var source = tree.root + "/helper.c"
    Path(source).write_bytes(Path(SOURCE).read_bytes())
    var runner = Recorder(
        [(0, String(), String()), (0, String(), String())], touch=source
    )
    with assert_raises(contains="result['source_unchanged']"):
        _ = fault_receipt(_options(True, source), runner)
    tree.close()


def test_preflight_names_each_missing_statement() raises:
    var text = String(from_utf8=Path(SOURCE).read_bytes())
    var harness = String(from_utf8=Path(HARNESS).read_bytes())
    preflight(text, harness)
    with assert_raises(contains="'O_WRONLY | O_NONBLOCK | O_CLOEXEC' in text"):
        preflight(text.replace("O_NONBLOCK", "O_X"), harness)
    with assert_raises(contains="ValueError: substring not found"):
        preflight(
            text.replace("write_record(probe_sink, bytes, size);", ""), harness
        )
    with assert_raises(contains="fork transition hooks"):
        preflight(text.replace("pthread_atfork", "atfork"), harness)
    with assert_raises(contains="text.count("):
        preflight(
            text + "\nmemcpy(slot->bytes, bytes, size);\n",
            harness,
        )
    with assert_raises(contains="'#include TRANSPORT_SOURCE' in"):
        preflight(text, "")
    with assert_raises(contains="!enabled)\\n        abort();' in text"):
        preflight(text.replace("abort();", "exit(1);"), harness)
    var swapped = text.replace(
        "write_record(probe_sink, bytes, size);", "WRITE"
    ).replace("memcpy(slot->bytes, bytes, size);", "COPY")
    swapped = swapped.replace("WRITE", "memcpy(slot->bytes, bytes, size);")
    swapped = swapped.replace("COPY", "write_record(probe_sink, bytes, size);")
    with assert_raises(contains="text.index("):
        preflight(swapped, harness)


def test_an_empty_compiler_command_is_refused() raises:
    var runner = Recorder(List[Outcome]())
    var options = _options(True)
    options.cc = "  "
    with assert_raises(contains="empty compiler command"):
        _ = fault_receipt(options, runner)
    assert_false(len(runner.commands) > 0)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
