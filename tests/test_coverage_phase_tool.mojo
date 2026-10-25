# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""A compiled profile records launch requests and hides program arguments."""

from std.ffi import c_int, external_call
from std.os import setenv, unsetenv
from std.pathlib import Path
from std.tempfile import mkdtemp
from std.testing import TestSuite, assert_equal, assert_true

from tests._tree import tool_mojo
from tools._carla_files import lstat_id
from tools._phase_log import (
    PHASE_ENV,
    PHASE_MAX_BYTES,
    PHASE_MAX_EVENTS,
    PHASE_MAX_RECORD,
    PhaseLog,
    phase_address,
    phase_note,
)
from tools._process import ProcessResult, run_program, shell_quote
from tools._python_json import MISSING, PyJson
from tools.native_test_support import _compiler_flags


def _compiler() -> String:
    """Return a fake Mojo compiler that can build a small C program."""
    var text = "#!/bin/sh\n"
    text += (
        'if [ -n "${THREEMOJO_COVERAGE_PHASES:-}" ]; then echo leaked > "$LOG";'
        " exit 9; fi\n"
    )
    text += (
        'if [ -n "${THREEMOJO_COVERAGE_PHASES_DEVICE:-}" ]; then echo leaked >'
        ' "$LOG"; exit 9; fi\n'
    )
    text += (
        'if [ -n "${THREEMOJO_COVERAGE_PHASES_INODE:-}" ]; then echo leaked >'
        ' "$LOG"; exit 9; fi\n'
    )
    text += 'printf \'%s\\n\' "$@" > "$LOG"\n'
    text += 'if [ "$1" != build ]; then exit "${PLAIN_STATUS:-4}"; fi\n'
    text += 'status="${BUILD_STATUS:-0}"\n'
    text += 'if [ "$status" != 0 ]; then exit "$status"; fi\n'
    text += "prev=\n"
    text += "out=\n"
    text += 'for arg in "$@"; do\n'
    text += '  if [ "$prev" = -o ]; then out=$arg; fi\n'
    text += "  prev=$arg\n"
    text += "done\n"
    text += "src=$(mktemp)\n"
    text += "cat > " + '"$src"' + " << 'END'\n"
    text += "#include <stdio.h>\n"
    text += "#include <stdlib.h>\n"
    text += "int main(int argc, char **argv) {\n"
    text += '  if (getenv("THREEMOJO_COVERAGE_PHASES")) return 2;\n'
    text += '  if (getenv("THREEMOJO_COVERAGE_PHASES_DEVICE")) return 2;\n'
    text += '  if (getenv("THREEMOJO_COVERAGE_PHASES_INODE")) return 2;\n'
    text += '  FILE *file = fopen(getenv("MARK"), "w");\n'
    text += "  if (!file) return 1;\n"
    text += "  int i;\n"
    text += '  for (i = 0; i < argc; i++) fprintf(file, "%s\\n", argv[i]);\n'
    text += "  fclose(file);\n"
    text += '  const char *status = getenv("RUNTIME_STATUS");\n'
    text += "  if (!status || !status[0]) return 0;\n"
    text += "  return atoi(status);\n"
    text += "}\n"
    text += "END\n"
    text += 'cc -x c -o "$out" "$src"\n'
    text += "status=" + "$?" + "\n"
    text += 'rm -f "$src"\n'
    text += 'exit "$status"\n'
    return text


def _fake_cc() -> String:
    """Return a C compiler stand-in for the hit helper."""
    var text = "#!/bin/sh\n"
    text += 'for arg in "$@"; do\n'
    text += (
        '  if [ "$arg" = --version ]; then echo fake cc version; exit 0; fi\n'
    )
    text += "done\n"
    text += "prev=\n"
    text += "out=\n"
    text += 'for arg in "$@"; do\n'
    text += '  if [ "$prev" = -o ]; then out=$arg; fi\n'
    text += "  prev=$arg\n"
    text += "done\n"
    text += 'if [ -z "$out" ]; then echo missing -o >&2; exit 3; fi\n'
    text += 'printf object > "$out"\n'
    return text


def _setup() raises -> String:
    """Return a tree with one plain suite and a fake compiler."""
    var root = mkdtemp(prefix="coverage-phase-")
    var made = run_program(
        ["mkdir", "-p", root + "/tests", root + "/cache", root + "/include"],
        10.0,
    )
    if made.status != 0:
        raise Error(made.output)
    Path(root + "/tests/test_plain.mojo").write_text("def main():\n    pass\n")
    Path(root + "/mojo").write_text(_compiler())
    Path(root + "/fake-cc").write_text(_fake_cc())
    var mode = run_program(
        ["chmod", "+x", root + "/mojo", root + "/fake-cc"], 10.0
    )
    if mode.status != 0:
        raise Error(mode.output)
    return root


def _cleanup(root: String) raises:
    """Remove `root`."""
    var removed = run_program(["rm", "-rf", root], 10.0)
    if removed.status != 0:
        raise Error(removed.output)


def _clear_phase():
    """Remove phase variables from this process."""
    _ = unsetenv(PHASE_ENV)
    _ = unsetenv(PHASE_ENV + "_DEVICE")
    _ = unsetenv(PHASE_ENV + "_INODE")


def _assign(key: String, value: String) -> String:
    """Return one `env` assignment."""
    return key + "=" + shell_quote(value)


def _header(path: String) raises -> Tuple[String, String]:
    """Write a capture header and return its device and inode."""
    Path(path).write_text(
        '{"schema": "coverage-exec-phases-v1", "phase": "capture_header"}\n'
    )
    var info = lstat_id(path)
    return (String(info.device), String(info.inode))


def _command(
    root: String,
    profile: String,
    mojo_args: String,
    assignments: List[String],
    cc: String = "",
) raises -> String:
    """Return the shell command for one profile."""
    var suite = root + "/tests/test_plain.mojo"
    var text = (
        "env -u THREEMOJO_COVERAGE_PHASES"
        + " -u THREEMOJO_COVERAGE_PHASES_DEVICE"
        + " -u THREEMOJO_COVERAGE_PHASES_INODE"
    )
    for item in assignments:
        text += " " + item
    text += (
        " sh tools/tool.sh "
        + shell_quote(tool_mojo())
        + " coverage_hit_aot --profile "
        + profile
        + " --root "
        + shell_quote(root)
        + " --suite "
        + shell_quote(suite)
        + " --cache "
        + shell_quote(root + "/cache")
    )
    if cc.byte_length() > 0:
        text += " --cc " + shell_quote(cc)
    text += " -- " + shell_quote(root + "/mojo") + " " + mojo_args
    return text


def _go(
    root: String,
    profile: String,
    mojo_args: String,
    assignments: List[String],
    cc: String = "",
) raises -> ProcessResult:
    """Run one profile."""
    var command = _command(root, profile, mojo_args, assignments, cc)
    return run_program(["sh", "-c", command], 40.0, merge_errors=False)


def _require(ran: ProcessResult, status: Int) raises:
    """Raise with the tool output when the status differs."""
    if ran.status != status:
        raise Error(
            "status "
            + String(ran.status)
            + "\n"
            + ran.output
            + "\n"
            + ran.errors
        )


def _lines(path: String) raises -> List[String]:
    """Return the non-empty lines of a phase file."""
    var parts = Path(path).read_text().split("\n")
    var lines = List[String]()
    for part in parts:
        if part.byte_length() > 0:
            lines.append(String(part))
    return lines^


def _phases(path: String) raises -> String:
    """Return the phase names, joined by commas."""
    var lines = _lines(path)
    var out = String()
    for line in lines:
        var doc = PyJson.parse(line)
        if out.byte_length() > 0:
            out += ","
        out += doc.text(doc.at(doc.root, "phase"))
    return out^


def _argv(line: String) raises -> String:
    """Return the argv words, one per line."""
    var doc = PyJson.parse(line)
    var node = doc.at(doc.root, "argv")
    var out = String()
    var index = 0
    while index < doc.length(node):
        if index > 0:
            out += "\n"
        out += doc.text(doc.item(node, index))
        index += 1
    return out^


def _phase_env(path: String, device: String, inode: String) -> List[String]:
    """Return the three phase assignments."""
    var items = List[String]()
    items.append(_assign(PHASE_ENV, path))
    items.append(_assign(PHASE_ENV + "_DEVICE", device))
    items.append(_assign(PHASE_ENV + "_INODE", inode))
    return items^


def _run_args(root: String) -> String:
    """Return a run command with a private program argument."""
    var suite = root + "/tests/test_plain.mojo"
    return (
        "run -I "
        + shell_quote(root + "/include")
        + " "
        + shell_quote("-Dliteral=$value; spaced")
        + " "
        + shell_quote(suite)
        + " "
        + shell_quote("argument with spaces")
        + " --literal"
    )


def _common(root: String, device: String, inode: String) -> List[String]:
    """Return the phase environment plus the log and mark paths."""
    var items = _phase_env(root + "/test_plain.phases.jsonl", device, inode)
    items.append(_assign("LOG", root + "/log"))
    items.append(_assign("MARK", root + "/mark"))
    items.append(_assign("NEVER_LOG_THIS_SECRET", "private-environment-value"))
    return items^


def test_a_compiled_profile_records_the_build_and_hides_arguments() raises:
    var root = _setup()
    try:
        var phases = root + "/test_plain.phases.jsonl"
        var identity = _header(phases)
        var ran = _go(
            root,
            "aot",
            _run_args(root),
            _common(root, identity[0], identity[1]),
        )
        _require(ran, 0)
        var suite = root + "/tests/test_plain.mojo"
        assert_equal(
            Path(root + "/mark").read_text(),
            suite + "\nargument with spaces\n--literal\n",
        )
        assert_equal(
            _phases(phases),
            "capture_header,mojo_build_launch_request,native_runtime_launch_request,adapter_finish",
        )
        var lines = _lines(phases)
        var build = PyJson.parse(lines[1])
        var runtime = PyJson.parse(lines[2])
        var finish = PyJson.parse(lines[3])
        assert_equal(
            build.text(build.at(build.root, "executable")), root + "/mojo"
        )
        assert_equal(build.text(build.at(build.root, "suite")), "test_plain")
        var words = _argv(lines[1])
        assert_true(words.startswith(root + "/mojo\nbuild\n--num-threads\n1\n"))
        assert_true(words.endswith("\n" + suite))
        assert_equal(_argv(lines[2]), suite)
        assert_equal(
            runtime.text(runtime.at(runtime.root, "omitted_program_arguments")),
            "2",
        )
        var build_words = _argv(lines[1]).split("\n")
        assert_equal(
            runtime.text(runtime.at(runtime.root, "executable")),
            String(build_words[len(build_words) - 2]),
        )
        assert_equal(finish.text(finish.at(finish.root, "status")), "0")
        assert_true(finish.flag(finish.at(finish.root, "diagnostics_complete")))
        assert_equal(
            build.text(build.at(build.root, "adapter_pid")),
            runtime.text(runtime.at(runtime.root, "adapter_pid")),
        )
        assert_equal(
            runtime.text(runtime.at(runtime.root, "adapter_pid")),
            finish.text(finish.at(finish.root, "adapter_pid")),
        )
        var first = build.number(build.at(build.root, "monotonic"))
        var second = runtime.number(runtime.at(runtime.root, "monotonic"))
        var third = finish.number(finish.at(finish.root, "monotonic"))
        assert_true(first <= second and second <= third)
        var utc = finish.text(finish.at(finish.root, "utc"))
        assert_true(utc.endswith("+00:00"))
        assert_true(utc.byte_length() == 25 or utc.byte_length() == 32)
        var text = Path(phases).read_text()
        assert_true(text.find("argument with spaces") < 0)
        assert_true(text.find("--literal") < 0)
        assert_true(text.find("private-environment-value") < 0)
        assert_true(text.find("NEVER_LOG_THIS_SECRET") < 0)
        assert_true(text.find("-Dliteral=$value; spaced") >= 0)
    finally:
        _cleanup(root)


def test_a_failed_build_records_no_program_launch() raises:
    var root = _setup()
    try:
        var phases = root + "/test_plain.phases.jsonl"
        var identity = _header(phases)
        var env = _common(root, identity[0], identity[1])
        env.append(_assign("BUILD_STATUS", "41"))
        var ran = _go(root, "aot", _run_args(root), env)
        _require(ran, 41)
        assert_equal(
            _phases(phases),
            "capture_header,mojo_build_launch_request,adapter_finish",
        )
        var finish = PyJson.parse(_lines(phases)[2])
        assert_equal(finish.text(finish.at(finish.root, "status")), "41")
        assert_true(finish.flag(finish.at(finish.root, "diagnostics_complete")))
        assert_true(not Path(root + "/mark").exists())
    finally:
        _cleanup(root)


def test_a_failed_program_keeps_its_status() raises:
    var root = _setup()
    try:
        var phases = root + "/test_plain.phases.jsonl"
        var identity = _header(phases)
        var env = _common(root, identity[0], identity[1])
        env.append(_assign("RUNTIME_STATUS", "29"))
        var ran = _go(root, "aot", _run_args(root), env)
        _require(ran, 29)
        assert_equal(
            _phases(phases),
            "capture_header,mojo_build_launch_request,native_runtime_launch_request,adapter_finish",
        )
        var finish = PyJson.parse(_lines(phases)[3])
        assert_equal(finish.text(finish.at(finish.root, "status")), "29")
        assert_true(Path(root + "/mark").exists())
    finally:
        _cleanup(root)


def test_a_missing_compiler_records_the_request() raises:
    var root = _setup()
    try:
        var removed = run_program(["rm", root + "/mojo"], 10.0)
        if removed.status != 0:
            raise Error(removed.output)
        var phases = root + "/test_plain.phases.jsonl"
        var identity = _header(phases)
        var ran = _go(
            root,
            "aot",
            _run_args(root),
            _common(root, identity[0], identity[1]),
        )
        _require(ran, 1)
        assert_true(ran.errors.find("FileNotFoundError") >= 0)
        assert_equal(
            _phases(phases),
            "capture_header,mojo_build_launch_request,adapter_finish",
        )
        var finish = PyJson.parse(_lines(phases)[2])
        assert_equal(
            finish.text(finish.at(finish.root, "exception")),
            "FileNotFoundError",
        )
        assert_equal(finish.get(finish.root, "status"), MISSING)
        assert_true(finish.flag(finish.at(finish.root, "diagnostics_complete")))
    finally:
        _cleanup(root)


def test_a_raw_profile_writes_no_launch_request() raises:
    var root = _setup()
    try:
        var phases = root + "/test_plain.phases.jsonl"
        var identity = _header(phases)
        var before = Path(phases).read_text()
        var ran = _go(
            root,
            "raw",
            "run " + shell_quote(root + "/tests/test_plain.mojo"),
            _common(root, identity[0], identity[1]),
        )
        _require(ran, 4)
        assert_equal(Path(phases).read_text(), before)
        assert_true(Path(root + "/log").read_text().find("leaked") < 0)
    finally:
        _cleanup(root)


def test_a_changed_phase_identity_leaves_the_file() raises:
    var root = _setup()
    try:
        var phases = root + "/test_plain.phases.jsonl"
        _ = _header(phases)
        var before = Path(phases).read_text()
        var env = _common(root, "0", "0")
        env.append(_assign("BUILD_STATUS", "41"))
        var ran = _go(root, "aot", _run_args(root), env)
        _require(ran, 41)
        assert_equal(Path(phases).read_text(), before)
    finally:
        _cleanup(root)


def test_no_launch_cannot_claim_a_complete_trace() raises:
    var root = _setup()
    try:
        var phases = root + "/test_plain.phases.jsonl"
        var identity = _header(phases)
        var ran = _go(
            root,
            "aot-hits",
            "run " + shell_quote(root + "/tests/test_plain.mojo"),
            _common(root, identity[0], identity[1]),
        )
        _require(ran, 1)
        assert_true(ran.errors.find("supervised capture pipe") >= 0)
        assert_equal(
            _phases(phases),
            "capture_header,diagnostics_incomplete,adapter_finish",
        )
        var lines = _lines(phases)
        var lost = PyJson.parse(lines[1])
        var finish = PyJson.parse(lines[2])
        assert_equal(lost.text(lost.at(lost.root, "exception")), "RuntimeError")
        assert_equal(lost.get(lost.root, "argv"), MISSING)
        assert_equal(
            finish.text(finish.at(finish.root, "exception")), "ValueError"
        )
        assert_true(
            not finish.flag(finish.at(finish.root, "diagnostics_complete"))
        )
    finally:
        _cleanup(root)


def test_a_full_phase_file_keeps_the_build_status() raises:
    var root = _setup()
    try:
        var phases = root + "/test_plain.phases.jsonl"
        var chunk = (
            "                                                                "
        )
        var text = String()
        while text.byte_length() + 64 <= PHASE_MAX_BYTES:
            text += chunk
        while text.byte_length() < PHASE_MAX_BYTES:
            text += " "
        Path(phases).write_text(text)
        var info = lstat_id(phases)
        var env = _common(root, String(info.device), String(info.inode))
        env.append(_assign("BUILD_STATUS", "41"))
        var ran = _go(root, "aot", _run_args(root), env)
        _require(ran, 41)
        assert_equal(Path(phases).read_text(), text)
        assert_true(Path(phases).read_text().find("adapter_finish") < 0)
    finally:
        _cleanup(root)


def test_exact_hits_record_the_helper_before_the_build() raises:
    var root = _setup()
    try:
        var phases = root + "/test_plain.phases.jsonl"
        var identity = _header(phases)
        var fifo = root + "/err.fifo"
        var made = run_program(["mkfifo", fifo], 10.0)
        if made.status != 0:
            raise Error(made.output)
        var command = _command(
            root,
            "aot-hits",
            "run " + shell_quote(root + "/tests/test_plain.mojo"),
            _common(root, identity[0], identity[1]),
            root + "/fake-cc",
        )
        var script = (
            "cat "
            + shell_quote(fifo)
            + " > "
            + shell_quote(root + "/err.txt")
            + " & "
            + command
            + " 2> "
            + shell_quote(fifo)
            + "; status=$?; wait; exit $status"
        )
        var ran = run_program(["sh", "-c", script], 40.0, merge_errors=False)
        if ran.status != 0:
            var err = ""
            if Path(root + "/err.txt").exists():
                err = Path(root + "/err.txt").read_text()
            raise Error(
                "status "
                + String(ran.status)
                + "\n"
                + ran.output
                + "\n"
                + ran.errors
                + "\n"
                + err
            )
        assert_equal(
            _phases(phases),
            "capture_header,native_helper_launch_request,native_helper_launch_request,mojo_build_launch_request,native_runtime_launch_request,adapter_finish",
        )
        var lines = _lines(phases)
        assert_equal(_argv(lines[1]), root + "/fake-cc\n-pthread\n--version")
        assert_true(_argv(lines[2]).find("\n-c\n") >= 0)
        assert_true(lines[3].find("-DTHREEMOJO_COVERAGE_HIT_CACHE") >= 0)
        var finish = PyJson.parse(lines[5])
        assert_equal(finish.text(finish.at(finish.root, "status")), "0")
        assert_true(finish.flag(finish.at(finish.root, "diagnostics_complete")))
    finally:
        _cleanup(root)


def _bind(mut log: PhaseLog, path: String) raises:
    """Attach `log` to a real phase file."""
    var info = lstat_id(path)
    _ = setenv(PHASE_ENV, path, True)
    _ = setenv(PHASE_ENV + "_DEVICE", String(info.device), True)
    _ = setenv(PHASE_ENV + "_INODE", String(info.inode), True)
    var cc = List[String]()
    cc.append("cc")
    log.attach(
        "tests/test_plain.mojo", "mojo", "suite.mojo", cc, _compiler_flags()
    )


def _note_build(mut log: PhaseLog, extra: String):
    """Record a build request, with `extra` before the source."""
    var argv = List[String]()
    argv.append("mojo")
    argv.append("build")
    if extra.byte_length() > 0:
        argv.append(extra)
    argv.append("suite.mojo")
    phase_note(phase_address(log), "mojo", argv)


def test_a_lost_launch_request_stays_incomplete() raises:
    var root = _setup()
    try:
        var unknown = root + "/unknown.jsonl"
        Path(unknown).write_text("")
        var log = PhaseLog()
        _bind(log, unknown)
        var flags = external_call["fcntl", c_int](
            c_int(log.descriptor), c_int(1)
        )
        assert_true(Int(flags) > 0)
        assert_true((Int(flags) & 1) != 0)
        var other = List[String]()
        other.append("other")
        other.append("private-token")
        phase_note(phase_address(log), "other", other)
        log.finish_status(0)
        var lost = PyJson.parse(_lines(unknown)[0])
        var finish = PyJson.parse(_lines(unknown)[1])
        assert_equal(
            lost.text(lost.at(lost.root, "phase")), "diagnostics_incomplete"
        )
        assert_equal(lost.text(lost.at(lost.root, "exception")), "ValueError")
        assert_equal(lost.get(lost.root, "argv"), MISSING)
        assert_true(Path(unknown).read_text().find("private-token") < 0)
        assert_true(
            not finish.flag(finish.at(finish.root, "diagnostics_complete"))
        )
        var blob = String()
        var piece = "xxxxxxxx"
        while blob.byte_length() < PHASE_MAX_RECORD:
            blob += piece
        var oversized = root + "/oversized.jsonl"
        Path(oversized).write_text("")
        var big = PhaseLog()
        _bind(big, oversized)
        _note_build(big, blob)
        big.finish_status(0)
        assert_true(Path(oversized).read_text().find(blob) < 0)
        assert_equal(
            _phases(oversized), "diagnostics_incomplete,adapter_finish"
        )
        var limited = root + "/limited.jsonl"
        Path(limited).write_text("")
        var capped = PhaseLog()
        _bind(capped, limited)
        capped.events = PHASE_MAX_EVENTS
        _note_build(capped, "")
        capped.finish_status(0)
        assert_equal(_phases(limited), "diagnostics_incomplete,adapter_finish")
        var quiet = root + "/quiet.jsonl"
        Path(quiet).write_text("")
        var idle = PhaseLog()
        _bind(idle, quiet)
        idle.finish_status(0)
        var idle_lines = _lines(quiet)
        var idle_lost = PyJson.parse(idle_lines[0])
        var idle_finish = PyJson.parse(idle_lines[1])
        assert_equal(
            idle_lost.text(idle_lost.at(idle_lost.root, "exception")),
            "RuntimeError",
        )
        assert_equal(
            idle_finish.text(idle_finish.at(idle_finish.root, "status")), "0"
        )
        assert_true(
            not idle_finish.flag(
                idle_finish.at(idle_finish.root, "diagnostics_complete")
            )
        )
        var target = root + "/target.jsonl"
        Path(target).write_text("header\n")
        var link = root + "/link.jsonl"
        var linked = run_program(["ln", "-s", target, link], 10.0)
        if linked.status != 0:
            raise Error(linked.output)
        var info = lstat_id(target)
        _ = setenv(PHASE_ENV, link, True)
        _ = setenv(PHASE_ENV + "_DEVICE", String(info.device), True)
        _ = setenv(PHASE_ENV + "_INODE", String(info.inode), True)
        var shadow = PhaseLog()
        var cc = List[String]()
        cc.append("cc")
        shadow.attach(
            "tests/test_plain.mojo", "mojo", "suite.mojo", cc, _compiler_flags()
        )
        assert_true(not shadow.complete)
        assert_equal(shadow.descriptor, -1)
        shadow.finish_status(0)
        assert_equal(Path(target).read_text(), "header\n")
    finally:
        _clear_phase()
        _cleanup(root)


def main() raises:
    """Build the profile tool, then run the tests."""
    var built = run_program(
        ["sh", "tools/tool.sh", tool_mojo(), "--build", "coverage_hit_aot"],
        120.0,
    )
    if built.status != 0:
        raise Error(built.output + built.errors)
    TestSuite.discover_tests[__functions_in_module()]().run()
