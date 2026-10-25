# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""A coverage capture keeps each probe record once."""

from std.testing import TestSuite, assert_equal, assert_true

from tests._tree import tool_mojo
from tools._process import run_program, shell_quote
from tools.coverage_io import _header_json


def _capture(script: String, seconds: Float64) raises -> Int:
    """Run one shell script under the capture tool."""
    var ran = run_program(["sh", "-c", script], seconds, merge_errors=False)
    return ran.status


def test_duplicate_probes_are_kept_once() raises:
    var mojo = tool_mojo()
    var ran = run_program(
        [
            "sh",
            "-c",
            "out=$(mktemp); err=$(mktemp).txt.gz; sh tools/tool.sh "
            + shell_quote(mojo)
            + ' coverage_io capture --out "$out" --err "$err" -- sh -c '
            + "'printf"
            ' "hello\\nCOVLINE:module:2:T\\nCOVLINE:module:2:T\\nCOVBRANCH:module:3:T\\nnote\\n"'
            " >&2' >/tmp/coverage-capture-progress.$$"
            + '; status=$?; gzip -dc "$err"; exit $status',
        ],
        20.0,
        merge_errors=False,
    )
    assert_equal(ran.status, 0)
    assert_equal(
        ran.output,
        "hello\nCOVLINE:module:2:T\nCOVLINE:module:3:T\nCOVBRANCH:module:3:T\nnote\n",
    )


def test_a_past_deadline_exits_124() raises:
    var status = _capture(
        "out=$(mktemp); err=$(mktemp).txt.gz; THREEMOJO_COVERAGE_DEADLINE=1 sh"
        " tools/tool.sh "
        + shell_quote(tool_mojo())
        + ' coverage_io capture --out "$out" --err "$err" -- true',
        20.0,
    )
    assert_equal(status, 124)


def test_a_short_deadline_stops_sleep() raises:
    var status = _capture(
        "out=$(mktemp); err=$(mktemp).txt.gz; d=$(python3 -c 'import time;"
        " print(repr(time.monotonic()+0.3))'); "
        + "THREEMOJO_COVERAGE_DEADLINE=$d sh tools/tool.sh "
        + shell_quote(tool_mojo())
        + ' coverage_io capture --out "$out" --err "$err" -- sleep 5',
        20.0,
    )
    assert_equal(status, 124)


def test_report_replays_captures_in_name_order() raises:
    var ran = run_program(
        [
            "sh",
            "-c",
            "dir=$(mktemp -d); printf 'hello\\n' | gzip -n -1 >"
            ' "$dir/b.txt.gz"; '
            + "printf 'world\\n' | gzip -n -1 > \"$dir/a.txt.gz\"; "
            + "sh tools/tool.sh "
            + shell_quote(tool_mojo())
            + ' coverage_io report --capture-dir "$dir" -- python3 -c '
            + "'import sys\n"
            + "for path in sys.argv[1:]:\n"
            + '    handle = open(path, "rb")\n'
            + "    sys.stdout.buffer.write(handle.read())\n"
            + "    handle.close()\n'",
        ],
        20.0,
        merge_errors=False,
    )
    assert_equal(ran.status, 0)
    assert_equal(ran.output, "world\nhello\n")


def test_progress_reports_the_first_probe_and_a_running_line() raises:
    var mojo = tool_mojo()
    var ran = run_program(
        [
            "sh",
            "-c",
            "out=$(mktemp); err=$(mktemp).txt.gz; sh tools/tool.sh "
            + shell_quote(mojo)
            + ' coverage_io capture --progress-seconds 0.02 --out "$out"'
            + ' --err "$err" -- sh -c \'printf "COVLINE:m:1:T\\n" >&2;'
            + " sleep 0.12'",
        ],
        20.0,
        merge_errors=False,
    )
    assert_equal(ran.status, 0)
    assert_true(ran.output.find("start;") >= 0)
    assert_true(ran.output.find("waiting for probes") >= 0)
    assert_true(ran.output.find("first probe;") >= 0)
    assert_true(ran.output.find("runtime probes observed") >= 0)
    assert_true(ran.output.find("running;") >= 0)
    assert_true(ran.output.find("complete (exit 0)") >= 0)


def test_a_missing_command_prints_aborted() raises:
    var mojo = tool_mojo()
    var ran = run_program(
        [
            "sh",
            "-c",
            "out=$(mktemp); err=$(mktemp).txt.gz; sh tools/tool.sh "
            + shell_quote(mojo)
            + ' coverage_io capture --out "$out" --err "$err" --'
            + " /no/such/coverage-command",
        ],
        20.0,
        merge_errors=False,
    )
    assert_true(ran.status != 0)
    assert_true(ran.output.find("aborted;") >= 0)


def _words() -> List[String]:
    """Return one compiled-capture command."""
    var command = List[String]()
    command.append("bin/coverage_hit_aot")
    command.append("--profile")
    command.append("aot-hits")
    command.append("suite.mojo")
    return command^


def test_phase_header_matches_python_json() raises:
    var digest = String()
    var index = 0
    while index < 32:
        digest += "ab"
        index += 1
    var script = (
        "import hashlib, json, sys\nsuite, proof, *command ="
        " sys.argv[1:]\nheader = {'schema': 'coverage-exec-phases-v1', 'suite':"
        " suite,\n 'phase': 'capture_header',\n 'proof_sha256': None if proof"
        " == '-' else proof,\n 'command_sha256':"
        " hashlib.sha256(json.dumps(command).encode()).hexdigest(),\n"
        " 'semantics': 'launch requests only; missing finish means"
        " incomplete'}\nsys.stdout.write(json.dumps(header) + '\\n')\n"
    )
    var with_proof = List[String]()
    with_proof.append("python3")
    with_proof.append("-c")
    with_proof.append(script)
    with_proof.append("test_fixture")
    with_proof.append(digest)
    var plain = List[String]()
    plain.append("python3")
    plain.append("-c")
    plain.append(script)
    plain.append("test_fixture")
    plain.append("-")
    for word in _words():
        var copy = word
        with_proof.append(word)
        plain.append(copy)
    var proved = run_program(with_proof, 10.0, merge_errors=False)
    var empty = run_program(plain, 10.0, merge_errors=False)
    if proved.status != 0 or empty.status != 0:
        raise Error(proved.errors + empty.errors)
    assert_equal(_header_json("test_fixture", digest, _words()), proved.output)
    assert_equal(_header_json("test_fixture", "", _words()), empty.output)
    assert_true(proved.output.find('"proof_sha256": "' + digest + '"') >= 0)
    assert_true(empty.output.find('"proof_sha256": null') >= 0)


def test_a_failed_capture_prints_its_tail_and_phase_header() raises:
    var mojo = tool_mojo()
    var ran = run_program(
        [
            "sh",
            "-c",
            'dir=$(mktemp -d); out="$dir/test_fixture.out";'
            ' err="$dir/test_fixture.txt.gz";'
            ' phases="$dir/test_fixture.phases.jsonl";'
            " cat > \"$dir/probe.py\" << 'END'\n"
            "import sys\n"
            "sys.stdout.write(''.join('out-%d\\n' % i for i in range(40)))\n"
            "sys.stderr.write(''.join('err-%d\\n' % i for i in range(40)))\n"
            "sys.stderr.write('COVLINE:m:1:T\\n')\n"
            "raise SystemExit(3)\n"
            "END\n"
            "sh tools/tool.sh "
            + shell_quote(mojo)
            + ' coverage_io capture --out "$out" --err "$err" --'
            + ' python3 "$dir/probe.py" coverage_hit_aot --profile aot'
            + ' >"$dir/tool.out"; status=$?;'
            + ' python3 - "$dir" "$status" << \'PY\'\n'
            + "import hashlib, json, pathlib, sys\n"
            + "folder, status = pathlib.Path(sys.argv[1]), int(sys.argv[2])\n"
            + "if status != 3:\n"
            + "    raise SystemExit('status %s' % status)\n"
            + "text = (folder / 'tool.out').read_text()\n"
            + "banner = 'aot failed under instrumentation:\\n'\n"
            + "mark = text.rfind(banner)\n"
            + "if mark < 0:\n"
            + "    raise SystemExit(text)\n"
            + "tail = text[mark + len(banner):]\n"
            + "stdout = ''.join('out-%d\\n' % i for i in range(10, 40))\n"
            + "stderr = ''.join('err-%d\\n' % i for i in range(10, 40))\n"
            + "if not tail.startswith(stdout + stderr):\n"
            + "    raise SystemExit(repr(tail[-200:]))\n"
            + "if 'phase diagnostics incomplete (ValueError)' not in text:\n"
            + "    raise SystemExit('missing finish note')\n"
            + "finish = text.rfind('phase diagnostics incomplete"
            " (ValueError)')\n"
            + "if finish < mark:\n"
            + "    raise SystemExit('finish printed before the tail')\n"
            + "command = ['python3', str(folder / 'probe.py'),"
            " 'coverage_hit_aot',\n"
            + " '--profile', 'aot']\n"
            + "header = {'schema': 'coverage-exec-phases-v1', 'suite':"
            " 'test_fixture',\n"
            + " 'phase': 'capture_header', 'proof_sha256': None,\n"
            + " 'command_sha256':"
            " hashlib.sha256(json.dumps(command).encode()).hexdigest(),\n"
            + " 'semantics': 'launch requests only; missing finish means"
            " incomplete'}\n"
            + "actual = (folder / 'test_fixture.phases.jsonl').read_text()\n"
            + "expected = json.dumps(header) + '\\n'\n"
            + "if actual != expected:\n"
            + "    raise SystemExit(actual + '\\n---\\n' + expected)\n"
            + "PY",
        ],
        20.0,
        merge_errors=False,
    )
    if ran.status != 0:
        raise Error(ran.output + ran.errors)


def test_a_phase_symlink_is_replaced_and_a_raw_capture_removes_it() raises:
    var mojo = tool_mojo()
    var ran = run_program(
        [
            "sh",
            "-c",
            "dir=$(mktemp -d); printf 'keep\\n' > \"$dir/keep\";"
            ' ln -s keep "$dir/test_fixture.phases.jsonl";'
            ' out="$dir/test_fixture.out"; err="$dir/test_fixture.txt.gz";'
            ' phases="$dir/test_fixture.phases.jsonl";'
            " sh tools/tool.sh "
            + shell_quote(mojo)
            + ' coverage_io capture --out "$out" --err "$err" --'
            + " python3 -c 'raise SystemExit(0)' coverage_hit_aot --profile aot"
            + ' >"$dir/tool.out"; status=$?;'
            + ' test "$status" = 0 || { echo "status $status"; exit 4; };'
            + ' test ! -L "$phases" || { echo still-link; exit 5; };'
            + ' test "$(cat "$dir/keep")" = keep || { echo target-changed; exit'
            " 6; };"
            + " grep -q 'phase diagnostics incomplete (ValueError)'"
            ' "$dir/tool.out";'
            + ' rm "$phases"; ln -s keep "$phases";'
            + " sh tools/tool.sh "
            + shell_quote(mojo)
            + ' coverage_io capture --out "$out" --err "$err" -- true'
            + ' >"$dir/raw.out"; status=$?;'
            + ' test "$status" = 0 || { echo "raw $status"; exit 7; };'
            + ' test ! -e "$phases" && test ! -L "$phases" || { echo remains;'
            " exit 8; };"
            + ' test "$(cat "$dir/keep")" = keep || { echo raw-target; exit'
            " 9; };",
        ],
        20.0,
        merge_errors=False,
    )
    if ran.status != 0:
        raise Error(ran.output + ran.errors)


def test_a_past_deadline_does_not_launch_a_compiled_capture() raises:
    var mojo = tool_mojo()
    var ran = run_program(
        [
            "sh",
            "-c",
            'dir=$(mktemp -d); marker="$dir/ran";'
            ' out="$dir/test_fixture.out"; err="$dir/test_fixture.txt.gz";'
            " THREEMOJO_COVERAGE_DEADLINE=1 sh tools/tool.sh "
            + shell_quote(mojo)
            + ' coverage_io capture --out "$out" --err "$err" --'
            + " python3 -c 'import pathlib,sys;"
            ' pathlib.Path(sys.argv[1]).write_text("ran\\n")\''
            + ' "$marker" coverage_hit_aot --profile aot >"$dir/tool.out";'
            + ' status=$?; test "$status" = 124 || { echo "status $status"; cat'
            ' "$dir/tool.out"; exit 4; };'
            + ' test ! -e "$marker" || { echo launched; exit 5; };'
            + " grep -q 'aot failed under instrumentation:' \"$dir/tool.out\";"
            + " grep -q 'phase diagnostics incomplete (ValueError)'"
            ' "$dir/tool.out";'
            + ' test "$(grep -c . "$dir/test_fixture.phases.jsonl")" = 1;',
        ],
        20.0,
        merge_errors=False,
    )
    if ran.status != 0:
        raise Error(ran.output + ran.errors)


def test_progress_is_visible_before_the_child_continues() raises:
    """A flushed running line lets the child advance, and records stay whole."""
    var mojo = tool_mojo()
    var ran = run_program(
        [
            "sh",
            "-c",
            "dir=$(mktemp -d); cat > \"$dir/child.py\" << 'PY'\n"
            "import sys, time, pathlib\n"
            "root = pathlib.Path(sys.argv[1])\n"
            "for index in range(2):\n"
            "    marker = root / str(index)\n"
            "    deadline = time.monotonic() + 8\n"
            "    while not marker.exists():\n"
            "        if time.monotonic() > deadline:\n"
            "            raise SystemExit(9)\n"
            "        time.sleep(0.001)\n"
            "    if index == 0:\n"
            "        sys.stderr.write('COVLINE:m:1\\n')\n"
            "        sys.stderr.flush()\n"
            "sys.stdout.write('diagnostic\\n')\n"
            "raise SystemExit(7)\n"
            "PY\n"
            "sh tools/tool.sh "
            + shell_quote(mojo)
            + ' coverage_io capture --progress-seconds 0.02 --out "$dir/out"'
            ' --err "$dir/err.gz" -- python3 "$dir/child.py" "$dir" >'
            ' "$dir/progress" &\npid=$!\nlimit=1600\nwhile kill -0 "$pid"'
            ' 2>/dev/null; do\n  text=$(cat "$dir/progress" 2>/dev/null ||'
            " true)\n  case \"$text\" in\n    *'running;'*'waiting for"
            ' probes\'*) touch "$dir/0" ;;\n  esac\n  case "$text" in\n   '
            " *'running;'*'runtime probes observed'*) touch \"$dir/1\" ;;\n"
            '  esac\n  limit=$((limit - 1))\n  if [ "$limit" -le 0 ]; then'
            " echo timeout; exit 8; fi\n  sleep 0.005\ndone\nwait"
            ' "$pid"\nstatus=$?\ntest "$status" = 7\ntest -f "$dir/0" -a -f'
            ' "$dir/1"\ntest "$(cat "$dir/out")" = diagnostic\ntest "$(gzip'
            " -dc \"$dir/err.gz\")\" = 'COVLINE:m:1'\ngrep -q 'start;'"
            ' "$dir/progress"\ngrep -q \'first probe;\' "$dir/progress"\ngrep'
            " -q 'complete (exit 7)' \"$dir/progress\"\n",
        ],
        20.0,
        merge_errors=False,
    )
    if ran.status != 0:
        raise Error(ran.output + ran.errors)


def test_a_bad_branch_is_not_rewritten_as_false() raises:
    """An invalid branch fails the capture and is not stored as false."""
    var mojo = tool_mojo()
    var ran = run_program(
        [
            "sh",
            "-c",
            "dir=$(mktemp -d); cat > \"$dir/probe.py\" << 'PY'\nimport"
            " sys\nsys.stderr.write('COVLINE:m:4\\nCOVBRANCH:m:4:T\\nCOVBRANCH:m:4:garbage\\n')\nPY\nsh"
            " tools/tool.sh "
            + shell_quote(mojo)
            + ' coverage_io capture --out "$dir/out" --err "$dir/err.gz" --'
            ' python3 "$dir/probe.py" > "$dir/tool.out" 2> "$dir/tool.err"\n'
            "status=$?\n"
            "echo STATUS $status\n"
            'if [ -f "$dir/err.gz" ]; then gzip -dc "$dir/err.gz"; fi\n'
            'cat "$dir/tool.out" "$dir/tool.err"\n',
        ],
        20.0,
        merge_errors=False,
    )
    assert_true(ran.output.find("STATUS 0\n") < 0)
    assert_true(ran.output.find("COVBRANCH:m:4:F") < 0)
    assert_true(ran.output.find("Malformed branch outcome") >= 0)


def test_a_failed_suite_keeps_its_diagnostics_and_status() raises:
    """Exit 7 keeps the assertion text and the non-probe error line."""
    var mojo = tool_mojo()
    var ran = run_program(
        [
            "sh",
            "-c",
            "dir=$(mktemp -d); cat > \"$dir/probe.py\" << 'PY'\n"
            "import sys\n"
            "sys.stdout.write('failed assertion\\n')\n"
            "sys.stderr.write('COVLINE:m:1\\nerror detail\\n')\n"
            "raise SystemExit(7)\n"
            "PY\n"
            "sh tools/tool.sh "
            + shell_quote(mojo)
            + ' coverage_io capture --out "$dir/out" --err "$dir/err.gz" --'
            ' python3 "$dir/probe.py" > "$dir/tool.out"\n'
            "status=$?\n"
            "echo STATUS $status\n"
            'printf "FILE %s" "$(cat "$dir/out")"\n'
            'cat "$dir/tool.out"\n',
        ],
        20.0,
        merge_errors=False,
    )
    if ran.status != 0:
        raise Error(ran.output + ran.errors)
    assert_true(ran.output.find("STATUS 7") >= 0)
    assert_true(ran.output.find("FILE failed assertion") >= 0)
    assert_true(ran.output.find("failed assertion") >= 0)
    assert_true(ran.output.find("error detail") >= 0)


def test_a_failing_reporter_returns_its_status() raises:
    """A reporter that exits 3 is not turned into a replay success."""
    var mojo = tool_mojo()
    var ran = run_program(
        [
            "sh",
            "-c",
            "dir=$(mktemp -d); printf 'valid\\n' | gzip -n -1 >"
            ' "$dir/a.txt.gz"; sh tools/tool.sh '
            + shell_quote(mojo)
            + ' coverage_io report --capture-dir "$dir" -- python3 -c'
            " 'raise SystemExit(3)'",
        ],
        20.0,
        merge_errors=False,
    )
    assert_equal(ran.status, 3)


def test_private_roots_follow_tmpdir_and_stay_separate() raises:
    """Two captures under one symlink TMPDIR keep distinct resolved roots."""
    var mojo = tool_mojo()
    var ran = run_program(
        [
            "sh",
            "-c",
            "set -eu\n"
            "base=$(mktemp -d)\n"
            'mkdir -p "$base/parent"\n'
            'ln -s "$base/parent" "$base/alias"\n'
            "cat > \"$base/child.sh\" << 'SH'\n"
            "set -eu\n"
            "name=$1\n"
            "content=$2\n"
            "base=$3\n"
            "root=$THREEMOJO_TEST_TMPDIR\n"
            '[ "$TMPDIR" = "$root" ] || exit 9\n'
            '[ "$MODULAR_CACHE_DIR" = "$root/mojo-cache" ] || exit 10\n'
            '[ "$XDG_CACHE_HOME" = "$root/xdg-cache" ] || exit 11\n'
            '[ -d "$MODULAR_CACHE_DIR" ] || exit 12\n'
            '[ -d "$XDG_CACHE_HOME" ] || exit 13\n'
            'printf %s "$root" > "$base/$name.root"\n'
            'printf %s "$content" > "$root/same.bin"\n'
            'got=$(cat "$root/same.bin")\n'
            '[ "$got" = "$content" ] || exit 4\n'
            "i=0\n"
            'while [ ! -f "$base/go" ]; do\n'
            "  i=$((i + 1))\n"
            '  if [ "$i" -gt 600 ]; then exit 8; fi\n'
            "  sleep 0.005\n"
            "done\n"
            "exit 0\n"
            "SH\n"
            "launch() {\n"
            "  name=$1\n"
            "  content=$2\n"
            '  TMPDIR="$base/alias" sh tools/tool.sh '
            + shell_quote(mojo)
            + ' coverage_io capture --out "$base/$name.out" --err'
            ' "$base/$name.txt.gz" -- sh "$base/child.sh" "$name"'
            ' "$content" "$base" > "$base/$name.progress" 2>'
            ' "$base/$name.toolerr" &\n'
            '  echo $! > "$base/$name.pid"\n'
            "}\n"
            "launch one one\n"
            "launch two two\n"
            "i=0\n"
            'while [ ! -s "$base/one.root" ] || [ ! -s "$base/two.root" ];'
            " do\n"
            "  i=$((i + 1))\n"
            '  if [ "$i" -gt 600 ]; then echo timeout; cat'
            ' "$base/one.toolerr" "$base/two.toolerr"; exit 8; fi\n'
            "  sleep 0.005\n"
            "done\n"
            'one=$(cat "$base/one.root")\n'
            'two=$(cat "$base/two.root")\n'
            '[ "$one" != "$two" ]\n'
            "parent=$(python3 -c 'import os,sys;"
            ' print(os.path.realpath(sys.argv[1]))\' "$base/parent")\n'
            'case "$one" in "$parent"/threemojo-test-*) ;; *) echo "bad'
            ' $one"; exit 5 ;; esac\n'
            'case "$two" in "$parent"/threemojo-test-*) ;; *) echo "bad'
            ' $two"; exit 5 ;; esac\n'
            "python3 -c 'import os,sys; raise SystemExit(0 if"
            " os.path.samefile(sys.argv[1], sys.argv[2]) else 1)'"
            ' "$(dirname "$one")" "$base/alias"\n'
            "python3 -c 'import os,sys; raise SystemExit(0 if"
            " os.path.samefile(sys.argv[1], sys.argv[2]) else 1)'"
            ' "$(dirname "$two")" "$base/alias"\n'
            '[ "$(cat "$one/same.bin")" = one ]\n'
            '[ "$(cat "$two/same.bin")" = two ]\n'
            'touch "$base/go"\n'
            'wait "$(cat "$base/one.pid")"\n'
            'wait "$(cat "$base/two.pid")"\n'
            '[ ! -e "$one" ]\n'
            '[ ! -e "$two" ]\n'
            '[ -d "$base/parent" ]\n'
            '[ -L "$base/alias" ]\n'
            'test -z "$(ls -A "$base/parent")"\n'
            "echo SEPARATE_OK\n",
        ],
        20.0,
        merge_errors=False,
    )
    if ran.status != 0:
        raise Error(ran.output + ran.errors)
    assert_true(ran.output.find("SEPARATE_OK") >= 0)


def test_capture_removes_the_private_root_after_every_outcome() raises:
    """Exit 0, exit 3, and a refused probe each remove the private root."""
    var mojo = tool_mojo()
    var ran = run_program(
        [
            "sh",
            "-c",
            "set -eu\n"
            "base=$(mktemp -d)\n"
            'mkdir -p "$base/plain"\n'
            "cat > \"$base/child.py\" << 'PY'\n"
            "import os, pathlib, sys\n"
            "root = os.environ['THREEMOJO_TEST_TMPDIR']\n"
            "pathlib.Path(sys.argv[1]).write_text(root)\n"
            "pathlib.Path(root, 'fixture.bin').write_bytes(b'fixture')\n"
            "raise SystemExit(int(sys.argv[2]))\n"
            "PY\n"
            "parent=$(python3 -c 'import os,sys;"
            ' print(os.path.realpath(sys.argv[1]))\' "$base/plain")\n'
            "for code in 0 3; do\n"
            '  marker="$base/mark-$code"\n'
            "  status=0\n"
            '  TMPDIR="$base/plain" sh tools/tool.sh '
            + shell_quote(mojo)
            + ' coverage_io capture --out "$base/out" --err "$base/err.txt.gz"'
            ' -- python3 "$base/child.py" "$marker" "$code" >'
            ' "$base/progress" 2> "$base/toolerr" || status=$?\n'
            '  test "$status" = "$code"\n'
            '  root=$(cat "$marker")\n'
            '  case "$root" in "$parent"/threemojo-test-*) ;; *) echo "bad'
            ' $root"; exit 5 ;; esac\n'
            '  test ! -e "$root"\n'
            "done\n"
            'marker="$base/mark-bad"\n'
            "cat > \"$base/bad.py\" << 'PY'\n"
            "import os, pathlib, sys\n"
            "root = os.environ['THREEMOJO_TEST_TMPDIR']\n"
            "pathlib.Path(sys.argv[1]).write_text(root)\n"
            "pathlib.Path(root, 'fixture.bin').write_bytes(b'fixture')\n"
            "sys.stderr.write('COVBRANCH:m:4:garbage\\n')\n"
            "PY\n"
            'TMPDIR="$base/plain" sh tools/tool.sh '
            + shell_quote(mojo)
            + ' coverage_io capture --out "$base/out" --err "$base/err.txt.gz"'
            ' -- python3 "$base/bad.py" "$marker" > "$base/progress" 2>'
            ' "$base/toolerr" || status=$?\n'
            'test "$status" = 1\n'
            'root=$(cat "$marker")\n'
            'case "$root" in "$parent"/threemojo-test-*) ;; *) echo "bad'
            ' $root"; exit 5 ;; esac\n'
            'test ! -e "$root"\n'
            'grep -q aborted "$base/progress"\n'
            'grep -q "Malformed branch outcome" "$base/toolerr"\n'
            'test -z "$(ls -A "$base/plain")"\n'
            "echo CLEAN_OK\n",
        ],
        20.0,
        merge_errors=False,
    )
    if ran.status != 0:
        raise Error(ran.output + ran.errors)
    assert_true(ran.output.find("CLEAN_OK") >= 0)


def test_usage_exits_2() raises:
    var ran = run_program(
        ["sh", "tools/tool.sh", tool_mojo(), "coverage_io"],
        20.0,
        merge_errors=False,
    )
    assert_equal(ran.status, 2)
    assert_true(ran.errors.find("usage: coverage_io capture ") >= 0)


def main() raises:
    """Build the tool, then run the tests."""
    var built = run_program(
        ["sh", "tools/tool.sh", tool_mojo(), "--build", "coverage_io"],
        120.0,
    )
    if built.status != 0:
        raise Error(built.output + built.errors)
    TestSuite.discover_tests[__functions_in_module()]().run()
