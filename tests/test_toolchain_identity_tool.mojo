# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""A relocated Mojo wheel keeps one identity, and a broken wheel is refused."""

from std.os import getenv, setenv, unsetenv
from std.pathlib import Path
from std.tempfile import mkdtemp
from std.testing import (
    TestSuite,
    assert_equal,
    assert_not_equal,
    assert_raises,
    assert_true,
)

from tools._process import run_program, shell_quote
from tools.coverage_loop_begin import executable_identity


def _run(command: List[String]) raises:
    """Run `command` and require status 0.

    Args:
        command: The program and its arguments.

    Raises:
        Error: If the program fails.
    """
    var result = run_program(command, 30.0, merge_errors=False)
    if result.status != 0:
        raise Error(result.errors)


def _write(path: String, text: String) raises:
    """Write `text` to `path`, creating parent directories.

    Args:
        path: The file.
        text: The contents.

    Raises:
        Error: If a directory cannot be created.
    """
    var slash = path.rfind("/")
    if slash > 0:
        _run(["mkdir", "-p", String(path[byte=:slash])])
    Path(path).write_text(text)


def _site(root: String) raises -> String:
    """Return the one site-packages directory of a virtual environment.

    Args:
        root: The directory that contains `.venv`.

    Returns:
        The site-packages path.

    Raises:
        Error: If the environment does not have one site-packages directory.
    """
    var lib = root + "/.venv/lib"
    var found = String()
    var count = 0
    for name in run_program(["ls", lib], 10.0).output.split("\n"):
        if name.startswith("python"):
            var candidate = lib + "/" + String(name) + "/site-packages"
            if Path(candidate).is_dir():
                found = candidate
                count += 1
    if count != 1:
        raise Error("expected one site-packages directory")
    return found


def _base_python() raises -> String:
    """Return the upstream interpreter used to build a virtual environment.

    Returns:
        The `python` executable.

    Raises:
        Error: If neither the managed interpreter nor `python3` can be read.
    """
    var found = run_program(
        [
            "uv",
            "python",
            "find",
            "--managed-python",
            "--no-project",
            "3.12.14",
        ],
        30.0,
        merge_errors=False,
    )
    if found.status == 0:
        var path = found.output
        var end = path.find("\n")
        if end >= 0:
            var trimmed = String(path[byte=:end])
            path = trimmed
        if path.byte_length() > 0:
            return path
    return "python3"


def _wheel(root: String) raises -> String:
    """Create a synthetic Mojo wheel and return its launcher.

    Args:
        root: The install root.

    Returns:
        The `.venv/bin/mojo` launcher.

    Raises:
        Error: If the virtual environment cannot be created.
    """
    _run(
        [
            _base_python(),
            "-m",
            "venv",
            "--without-pip",
            root + "/.venv",
        ]
    )
    var python = root + "/.venv/bin/python"
    var launcher = root + "/.venv/bin/mojo"
    Path(launcher).write_text(
        "#!"
        + python
        + "\nfrom mojo._entrypoints import exec_mojo\nexec_mojo()\n"
    )
    var site = _site(root)
    var payload = List[String]()
    payload.append("mojo/_entrypoints.py")
    payload.append("modular/bin/mojo")
    payload.append("modular/bin/lld")
    payload.append("modular/lib/mojo/std.mojoc")
    var record = String()
    for name in payload:
        if name == "mojo/_entrypoints.py":
            _write(site + "/" + name, "def exec_mojo(): pass\n")
        elif name == "modular/bin/mojo":
            _write(site + "/" + name, "compiler payload\n")
        elif name == "modular/bin/lld":
            _write(site + "/" + name, "linker payload\n")
        else:
            _write(site + "/" + name, "standard library payload\n")
        record += name + ",,\n"
    for package in ["mojo_compiler", "mojo_compiler_mojo_libs"]:
        var title = package.replace("_", "-")
        var directory = site + "/" + package + "-1.1.0.dist-info"
        _write(directory + "/METADATA", "Name: " + title + "\nVersion: 1.1.0\n")
        _write(directory + "/RECORD", record)
    return launcher


def _cleanup(root: String) raises:
    """Remove `root`.

    Args:
        root: The directory.

    Raises:
        Error: If removal fails.
    """
    _run(["rm", "-rf", root])


def test_relocated_wheels_share_one_identity() raises:
    """Two installs of the same payload have one identity."""
    var base = mkdtemp(prefix="toolchain-identity-")
    try:
        var first = _wheel(base + "/runner-a")
        var second = _wheel(base + "/unrelated-root/runner-b")
        assert_not_equal(Path(first).read_text(), Path(second).read_text())
        var identity = executable_identity(first)
        assert_equal(identity, executable_identity(second))
        var real = base + "/real"
        var alias = base + "/alias"
        _run(["mkdir", "-p", real])
        _run(["ln", "-s", real, alias])
        var through_alias = _wheel(alias + "/install")
        var direct = _wheel(real + "/other")
        assert_equal(
            executable_identity(through_alias), executable_identity(direct)
        )
        Path(second).write_text(Path(second).read_text() + "changed\n")
        assert_not_equal(identity, executable_identity(second))
    finally:
        _cleanup(base)


def test_payload_bytes_change_the_identity() raises:
    """The launcher body, driver, linker, standard library, and package code are bound.
    """
    var base = mkdtemp(prefix="toolchain-payload-")
    try:
        var launcher = _wheel(base + "/install")
        var site = _site(base + "/install")
        var before = executable_identity(launcher)
        var files = List[String]()
        files.append(launcher)
        files.append(site + "/modular/bin/mojo")
        files.append(site + "/modular/bin/lld")
        files.append(site + "/modular/lib/mojo/std.mojoc")
        files.append(site + "/mojo/_entrypoints.py")
        for path in files:
            var raw = Path(path).read_text()
            Path(path).write_text(raw + "changed\n")
            assert_not_equal(before, executable_identity(launcher), path)
            Path(path).write_text(raw)
        assert_equal(before, executable_identity(launcher))
    finally:
        _cleanup(base)


def test_a_broken_wheel_is_refused() raises:
    """The wrong interpreter, an import hook, or a missing driver is refused."""
    var base = mkdtemp(prefix="toolchain-refuse-")
    var saved = getenv("MODULAR_MOJO_MAX_DRIVER_PATH", "")
    try:
        var first = _wheel(base + "/runner-a")
        var second = _wheel(base + "/runner-b")
        var site_b = _site(base + "/runner-b")
        var body = Path(first).read_text()
        var newline = body.find("\n")
        Path(first).write_text(
            "#!"
            + base
            + "/runner-b/.venv/bin/python\n"
            + String(body[byte = newline + 1 :])
        )
        with assert_raises(contains="different environment"):
            _ = executable_identity(first)
        for name in ["redirect.pth", "sitecustomize.py", "usercustomize.py"]:
            var hook = site_b + "/" + name
            Path(hook).write_text(
                "raise RuntimeError('hook must not execute')\n"
            )
            with assert_raises(contains="import redirection"):
                _ = executable_identity(second)
            _run(["rm", "-f", hook])
        _run(["mkdir", base + "/runner-b/.venv/bin/re"])
        with assert_raises(contains="import shadow"):
            _ = executable_identity(second)
        _run(["rmdir", base + "/runner-b/.venv/bin/re"])
        var init = site_b + "/mojo/__init__.py"
        Path(init).write_text("__path__ = ['/unbound']\n")
        with assert_raises(contains="package initialization"):
            _ = executable_identity(second)
        _run(["rm", "-f", init])
        var config = base + "/runner-b/.venv/pyvenv.cfg"
        Path(config).write_text(
            Path(config).read_text().replace("false", "true")
        )
        with assert_raises(contains="exclude system"):
            _ = executable_identity(second)
        _ = setenv("MODULAR_MOJO_MAX_DRIVER_PATH", "/other/compiler", True)
        with assert_raises(contains="override"):
            _ = executable_identity(_wheel(base + "/runner-c"))
        _ = setenv("MODULAR_MOJO_MAX_DRIVER_PATH", "", True)
        var fresh = _wheel(base + "/runner-d")
        var site_d = _site(base + "/runner-d")
        _run(["rm", "-f", site_d + "/modular/bin/mojo"])
        with assert_raises(contains="Missing"):
            _ = executable_identity(fresh)
        Path(second).write_text(
            "#!/usr/bin/env python3\nfrom mojo._entrypoints import exec_mojo\n"
        )
        with assert_raises(contains="interpreter"):
            _ = executable_identity(second)
    finally:
        _ = setenv("MODULAR_MOJO_MAX_DRIVER_PATH", saved, True)
        _cleanup(base)


def _saved(name: String) raises -> String:
    """Return the environment value, or `UNSET` when it is absent."""
    var ran = run_program(
        ["sh", "-c", 'printf %s "${' + name + '-UNSET}"'],
        10.0,
        merge_errors=False,
    )
    if ran.status != 0:
        raise Error(ran.errors)
    return ran.output


def _restore(name: String, saved: String) raises:
    """Put one environment variable back."""
    if saved == "UNSET":
        _ = unsetenv(name)
    else:
        _ = setenv(name, saved, True)


def _listing(root: String) raises -> String:
    """Return every path under `root`, in byte order."""
    var ran = run_program(
        ["sh", "-c", "find " + shell_quote(root) + " -print | sort"],
        10.0,
        merge_errors=False,
    )
    if ran.status != 0:
        raise Error(ran.errors)
    return ran.output


def _rewrite_home(root: String) raises:
    """Point the virtual environment home at its own `bin` directory."""
    var config = root + "/.venv/pyvenv.cfg"
    var text = Path(config).read_text()
    var out = String()
    var start = 0
    var bytes = text.as_bytes()
    var size = len(bytes)
    while start < size:
        var end = start
        while end < size and bytes[end] != 10:
            end += 1
        var line = String(text[byte=start:end])
        if line.startswith("home =") or line.startswith("home="):
            out += "home = " + root + "/.venv/bin\n"
        else:
            out += line + "\n"
        start = end + 1
    Path(config).write_text(out)


def _wrap_interpreter(root: String) raises -> String:
    """Replace the venv interpreter with a probe that can record and edit.

    The real interpreter still runs. `IDENTITY_LOG` records the arguments.
    `IDENTITY_INJECT=1` imports a site module under the same `-I -B`
    command. `IDENTITY_MUTATE` rewrites one probe field.

    Args:
        root: The install root.

    Returns:
        The launcher.

    Raises:
        Error: If the interpreter cannot be read.
    """
    var python = root + "/.venv/bin/python"
    var found = run_program(
        ["readlink", "-f", python], 10.0, merge_errors=False
    )
    if found.status != 0:
        raise Error(found.errors)
    var text = found.output
    var newline = text.find("\n")
    var real = text
    if newline >= 0:
        real = String(text[byte=:newline])
    _run(["rm", "-f", python])
    var body = (
        "#!"
        + real
        + '\nimport json, os, sys\nreal = "'
        + real
        + '"\n'
        + "log = os.environ.get('IDENTITY_LOG', '')\n"
        + "if log:\n"
        + "    handle = open(log, 'a', encoding='utf-8')\n"
        + "    handle.write('\\n'.join(sys.argv) + '\\n---\\n')\n"
        + "    handle.close()\n"
        + "args = list(sys.argv[1:])\n"
        + "if (os.environ.get('IDENTITY_INJECT') == '1' and args[:3] =="
        + " ['-I', '-B', '-c']):\n"
        + "    args[3] = ('import _identity_bytecode_probe; assert"
        + " _identity_bytecode_probe.VALUE == 17; ' + args[3])\n"
        + "mutate = os.environ.get('IDENTITY_MUTATE', '')\n"
        + "if not mutate:\n"
        + "    os.execv(real, [sys.argv[0], *args])\n"
        + "read_fd, write_fd = os.pipe()\n"
        + "pid = os.fork()\n"
        + "if pid == 0:\n"
        + "    os.close(read_fd)\n"
        + "    os.dup2(write_fd, 1)\n"
        + "    os.close(write_fd)\n"
        + "    os.execv(real, [sys.argv[0], *args])\n"
        + "os.close(write_fd)\n"
        + "chunks = []\n"
        + "while True:\n"
        + "    block = os.read(read_fd, 65536)\n"
        + "    if not block:\n"
        + "        break\n"
        + "    chunks.append(block)\n"
        + "os.close(read_fd)\n"
        + "_, status = os.waitpid(pid, 0)\n"
        + "if status != 0:\n"
        + "    raise SystemExit(1)\n"
        + "doc = json.loads(b''.join(chunks))\n"
        + "kind, _, value = mutate.partition('=')\n"
        + "if kind == 'implementation':\n"
        + "    doc['implementation'] = value\n"
        + "elif kind == 'prefix':\n"
        + "    doc['prefix'] = value\n"
        + "elif kind == 'user_site':\n"
        + "    doc['user_site'] = None if value == 'null' else value =="
        + " 'true'\n"
        + "elif kind == 'customizers':\n"
        + "    doc['customizers'] = [value]\n"
        + "elif kind == 'sites':\n"
        + "    doc['sites'].append(value)\n"
        + "elif kind == 'version':\n"
        + "    doc['version'] += value\n"
        + "else:\n"
        + "    raise SystemExit('unknown mutation')\n"
        + "sys.stdout.write(json.dumps(doc) + '\\n')\n"
        + "raise SystemExit(0)\n"
    )
    Path(python).write_text(body)
    _run(["chmod", "755", python])
    _rewrite_home(root)
    return root + "/.venv/bin/mojo"


def test_the_probe_is_isolated_and_writes_no_bytecode() raises:
    """The identity probe uses `-I -B` and leaves the wheel bytes unchanged."""
    var base = mkdtemp(prefix="toolchain-probe-")
    var saved_dont = _saved("PYTHONDONTWRITEBYTECODE")
    var saved_inject = _saved("IDENTITY_INJECT")
    var saved_log = _saved("IDENTITY_LOG")
    var saved_mutate = _saved("IDENTITY_MUTATE")
    try:
        var root = base + "/install"
        _ = _wheel(root)
        var launcher = _wrap_interpreter(root)
        var site = _site(root)
        Path(site + "/_identity_bytecode_probe.py").write_text("VALUE = 17\n")
        var before = _listing(site)
        var log = base + "/probe.log"
        Path(log).write_text("")
        _ = setenv("IDENTITY_LOG", log, True)
        _ = setenv("IDENTITY_INJECT", "1", True)
        _ = unsetenv("IDENTITY_MUTATE")
        _ = setenv("PYTHONDONTWRITEBYTECODE", "", True)
        var identity = executable_identity(launcher)
        var recorded = Path(log).read_text()
        var lines = recorded.split("\n")
        assert_true(len(lines) >= 4, recorded)
        assert_equal(lines[1], "-I")
        assert_equal(lines[2], "-B")
        assert_equal(lines[3], "-c")
        _ = setenv("PYTHONDONTWRITEBYTECODE", "1", True)
        Path(log).write_text("")
        assert_equal(identity, executable_identity(launcher))
        assert_equal(before, _listing(site))
        assert_true(before.find("__pycache__") < 0)
        assert_true(before.find(".pyc") < 0)
    finally:
        _restore("PYTHONDONTWRITEBYTECODE", saved_dont)
        _restore("IDENTITY_INJECT", saved_inject)
        _restore("IDENTITY_LOG", saved_log)
        _restore("IDENTITY_MUTATE", saved_mutate)
        _cleanup(base)


def test_interpreter_bytes_and_probe_fields_stay_bound() raises:
    """Interpreter bytes and probe fields change or refuse the identity."""
    var base = mkdtemp(prefix="toolchain-fields-")
    var saved_mutate = _saved("IDENTITY_MUTATE")
    var saved_inject = _saved("IDENTITY_INJECT")
    var saved_log = _saved("IDENTITY_LOG")
    try:
        var root = base + "/install"
        _ = _wheel(root)
        var launcher = _wrap_interpreter(root)
        var python = root + "/.venv/bin/python"
        _ = unsetenv("IDENTITY_INJECT")
        _ = unsetenv("IDENTITY_MUTATE")
        _ = unsetenv("IDENTITY_LOG")
        var before = executable_identity(launcher)
        var raw = Path(python).read_text()
        Path(python).write_text(raw + "# changed interpreter bytes\n")
        assert_not_equal(before, executable_identity(launcher))
        Path(python).write_text(raw)
        assert_equal(before, executable_identity(launcher))
        var refusals = List[String]()
        refusals.append("implementation=other-python")
        refusals.append("prefix=/other/venv")
        refusals.append("user_site=true")
        refusals.append("user_site=null")
        refusals.append("customizers=sitecustomize")
        refusals.append("customizers=usercustomize")
        refusals.append("sites=" + base + "/unbound-site-packages")
        for value in refusals:
            _ = setenv("IDENTITY_MUTATE", value, True)
            var expected = "environment or import customization"
            if value.startswith("sites="):
                expected = "site-packages does not match"
            with assert_raises(contains=expected):
                _ = executable_identity(launcher)
        _ = setenv("IDENTITY_MUTATE", "version=changed", True)
        assert_not_equal(before, executable_identity(launcher))
        _ = unsetenv("IDENTITY_MUTATE")
        assert_equal(before, executable_identity(launcher))
    finally:
        _restore("IDENTITY_MUTATE", saved_mutate)
        _restore("IDENTITY_INJECT", saved_inject)
        _restore("IDENTITY_LOG", saved_log)
        _cleanup(base)


def test_hosted_jobs_pin_the_upstream_interpreter_and_one_image() raises:
    """Hosted CI installs one upstream interpreter and one coverage image."""
    var workflow = Path(".github/workflows/ci.yml").read_text()
    var jobs = workflow.split("\njobs:\n")
    if len(jobs) != 2:
        raise Error("missing jobs")
    var text = String(jobs[1])
    for name in [
        "lint",
        "lint-macos",
        "tools",
        "tools-macos",
        "tools-discovery",
        "tools-discovery-macos",
        "cpu-macos",
    ]:
        assert_true(text.find("\n  " + name + ":") >= 0, name)
    assert_true(text.find("uv python install --no-bin 3.12.14") >= 0)
    assert_true(
        text.find("uv python find --managed-python --no-project 3.12.14") >= 0
    )
    assert_true(text.find('echo "$(dirname "$PYTHON")" >> "$GITHUB_PATH"') >= 0)
    assert_true(
        text.find('"$PYTHON" -m venv --without-pip --prompt ThreeMojo .venv')
        >= 0
    )
    assert_true(
        text.find('uv pip install --python .venv/bin/python "mojo==1.2.0"') >= 0
    )
    var image = (
        "python:3.12.14-bookworm@sha256:"
        + "dbbe4ceb97851e2e5fa83798b239811f871cb743b259ba3563737349f6bcfaa0"
    )
    assert_true(text.find("    container: " + image) >= 0)
    assert_true(text.find("COV_BUDGET=9000") >= 0)
    assert_true(text.find("SHARD=${{ matrix.shard }}/8") >= 0)
    assert_true(text.find("timeout-minutes: 170") >= 0)
    assert_true(text.find("timeout-minutes: 60") >= 0)
    assert_true(text.find("path: coverage/build/hits/") >= 0)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
