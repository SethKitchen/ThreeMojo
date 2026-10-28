# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md

"""A coverage group shares one deadline and stops when the time is gone."""

from std.pathlib import Path
from std.testing import TestSuite, assert_equal, assert_true

from tests._tree import tool_mojo
from tools._process import run_program, shell_quote
from tools._python_float import parse_float


def _run(script: String, seconds: Float64) raises -> Int:
    """Run one shell script under the built tool and return its status."""
    var ran = run_program(["sh", "-c", script], seconds, merge_errors=False)
    return ran.status


def test_a_finished_command_keeps_its_status() raises:
    var mojo = tool_mojo()
    var status = _run(
        "sh tools/tool.sh " + mojo + " coverage_group --seconds 2 -- true",
        10,
    )
    assert_equal(status, 0)


def test_a_past_deadline_exits_124() raises:
    var mojo = tool_mojo()
    var status = _run(
        "THREEMOJO_COVERAGE_DEADLINE=1 sh tools/tool.sh "
        + mojo
        + " coverage_group --seconds 10 -- true",
        10,
    )
    assert_equal(status, 124)


def _cleanup_tree(directory: String):
    """Stop a leftover capture tree and remove `directory`."""
    try:
        _ = run_program(
            [
                "sh",
                "-c",
                "dir="
                + shell_quote(directory)
                + "; for name in holder child grandchild; do "
                + 'if [ -f "$dir/$name.pid" ]; then '
                + 'pid=$(cat "$dir/$name.pid"); kill -9 "$pid" 2>/dev/null; '
                + 'kill -9 -- "-$pid" 2>/dev/null; fi; done; rm -rf "$dir"',
            ],
            10.0,
            merge_errors=False,
        )
    except:
        pass


def _wait_status(directory: String) raises -> String:
    """Return the capture status once the orphaned capture writes it."""
    var path = directory + "/status"
    var tries = 0
    while tries < 40:
        if Path(path).exists():
            var text = Path(path).read_text()
            var end = text.find("\n")
            if end >= 0:
                return String(text[byte=:end])
            return text
        _ = run_program(["sleep", "0.05"], 2.0)
        tries += 1
    var err = String()
    if Path(directory + "/holder.err").exists():
        err = Path(directory + "/holder.err").read_text()
    raise Error("capture wrote no status\n" + err)


def _number(text: String) raises -> Float64:
    """Return the first line of `text` as a float."""
    var end = text.find("\n")
    var body = text
    if end >= 0:
        body = String(text[byte=:end])
    return parse_float(body)


def _group_alarm(slow: String) raises:
    """Run one group alarm. `slow` is the startup delay before the budget."""
    var mojo = shell_quote(tool_mojo())
    var ran = run_program(
        [
            "sh",
            "-c",
            'dir=$(mktemp -d); echo "$dir"; '
            + "printf '%s\\n' 'import os, signal, subprocess, sys, time,"
            " pathlib' "
            + "'root = pathlib.Path(sys.argv[1])' 'role = sys.argv[2]' "
            + "'signal.signal(signal.SIGTERM, signal.SIG_IGN)' "
            + "'(root / (role + \".pid\")).write_text(str(os.getpid()))' "
            + "'if role == \"child\":' "
            + "'    (root /"
            ' "temporary").write_text(os.environ.get("THREEMOJO_TEST_TMPDIR",'
            ' ""))\' '
            + "'    subprocess.Popen([sys.executable, __file__, str(root),"
            ' "grandchild"])\' '
            + "'    while not (root / \"grandchild.pid\").exists():' "
            + "'        time.sleep(0.01)' "
            + "'    sys.stderr.write(\"COVLINE:m:1\\n\")' "
            + "'    sys.stderr.flush()' "
            + "'while True:' '    time.sleep(0.02)' "
            + '> "$dir/worker.py"; '
            + "printf '%s\\n' '#!/bin/sh' 'dir=$1' 'slow=$2' 'mojo=$3' "
            + '\'if [ "$slow" != 0 ]; then sleep "$slow"; fi\' '
            + "': > \"$dir/ready\"' "
            + "'while [ ! -f \"$dir/deadline\" ]; do sleep 0.01; done' "
            + "'THREEMOJO_COVERAGE_DEADLINE=$(cat \"$dir/deadline\")' "
            + "'export THREEMOJO_COVERAGE_DEADLINE' "
            + '\'sh tools/tool.sh "$mojo" coverage_io capture --out "$dir/out"'
            ' --err "$dir/err.txt.gz" -- python3 "$dir/worker.py" "$dir"'
            ' child > "$dir/progress" 2>"$dir/capture.err"\' '
            + '\'echo $? > "$dir/status"\' > "$dir/holder.sh"; '
            + 'chmod +x "$dir/holder.sh"; '
            + "printf '%s\\n' '#!/bin/sh' 'dir=$1' 'sleep 0.25' "
            + '\'printf %s "$THREEMOJO_COVERAGE_DEADLINE" >'
            ' "$dir/deadline.tmp"\' '
            + "'mv \"$dir/deadline.tmp\" \"$dir/deadline\"' 'sleep 30' "
            + '> "$dir/scheduler.sh"; chmod +x "$dir/scheduler.sh"; '
            + 'sh "$dir/holder.sh" "$dir" '
            + slow
            + " "
            + mojo
            + ' >"$dir/holder.out" 2>"$dir/holder.err" & '
            + 'echo $! > "$dir/holder.pid"; '
            + 'i=0; while [ ! -f "$dir/ready" ]; do i=$((i+1)); '
            + 'if [ "$i" -gt 500 ]; then echo ready-timeout; exit 8; fi; '
            + "sleep 0.01; done; "
            + "python3 -c 'import time; print(time.monotonic())' >"
            ' "$dir/started"; '
            + "exec sh tools/tool.sh "
            + mojo
            + ' coverage_group --seconds 0.9 -- sh "$dir/scheduler.sh" "$dir"',
        ],
        4.5,
        merge_errors=False,
    )
    var full = ran.output
    var newline = full.find("\n")
    var directory = full
    if newline >= 0:
        var head = String(full[byte=:newline])
        directory = head
    try:
        if ran.status != 142:
            var detail = ran.output + ran.errors
            if (
                directory.byte_length() > 0
                and Path(directory + "/holder.err").exists()
            ):
                detail += Path(directory + "/holder.err").read_text()
            raise Error("group status " + String(ran.status) + "\n" + detail)
        var status = _wait_status(directory)
        assert_equal(status, "124")
        var started = _number(Path(directory + "/started").read_text())
        var now = run_program(
            ["python3", "-c", "import time; print(time.monotonic())"],
            5.0,
            merge_errors=False,
        )
        if now.status != 0:
            raise Error(now.errors)
        var elapsed = _number(now.output) - started
        assert_true(elapsed < 2.5, String(elapsed))
        var tree = run_program(
            [
                "python3",
                "-c",
                "import os, sys\n"
                + "folder = sys.argv[1]\n"
                + "for name in ('child', 'grandchild'):\n"
                + "    pid = int(open(folder + '/' + name + '.pid').read())\n"
                + "    try:\n"
                + "        os.kill(pid, 0)\n"
                + "    except ProcessLookupError:\n"
                + "        continue\n"
                + "    stat = '/proc/%s/stat' % pid\n"
                + "    if os.path.exists(stat):\n"
                + "        text = open(stat).read().rpartition(') ')[2]\n"
                + "        if text.startswith('Z '):\n"
                + "            continue\n"
                + "    raise SystemExit('live ' + name)\n"
                + "temp = open(folder + '/temporary').read().strip()\n"
                + "if temp and os.path.exists(temp):\n"
                + "    raise SystemExit('temp ' + temp)\n"
                + "print('TREE_OK')\n",
                directory,
            ],
            5.0,
            merge_errors=False,
        )
        if tree.status != 0:
            raise Error(tree.output + tree.errors)
        assert_true(tree.output.find("TREE_OK") >= 0)
    finally:
        _cleanup_tree(directory)


def test_the_group_alarm_leaves_the_capture_to_stop_its_tree() raises:
    """The group alarm stops the scheduler, and the capture still stops its tree.
    """
    _group_alarm("0")


def test_a_slow_start_stays_outside_the_group_budget() raises:
    """Startup before the alarm does not consume the shared deadline."""
    _group_alarm("0.7")


def test_the_alarm_stops_a_slow_command() raises:
    var mojo = tool_mojo()
    var status = _run(
        "sh tools/tool.sh " + mojo + " coverage_group --seconds 0.3 -- sleep 5",
        4,
    )
    assert_equal(status, 142)
    var usage = run_program(
        ["sh", "tools/tool.sh", mojo, "coverage_group"],
        20,
        merge_errors=False,
    )
    assert_equal(usage.status, 2)
    assert_true(usage.errors.find("usage: coverage_group ") >= 0)


def main() raises:
    """Build the tool, then run the tests."""
    var built = run_program(
        ["sh", "tools/tool.sh", tool_mojo(), "--build", "coverage_group"],
        120,
    )
    if built.status != 0:
        raise Error(built.output + built.errors)
    built = run_program(
        ["sh", "tools/tool.sh", tool_mojo(), "--build", "coverage_io"],
        120,
    )
    if built.status != 0:
        raise Error(built.output + built.errors)
    TestSuite.discover_tests[__functions_in_module()]().run()
