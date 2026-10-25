# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""The generation checkpoint matches the Python begin command."""

from std.os import makedirs
from std.os.path import realpath
from std.pathlib import Path
from std.tempfile import mkdtemp
from std.testing import TestSuite, assert_equal, assert_true

from tests._tree import tool_mojo
from tools._process import ProcessResult, run_program


def _text(path: String) raises -> String:
    """Return a file's bytes as text."""
    return String(from_utf8_lossy=Path(path).read_bytes())


def _same(left: String, right: String) raises:
    """Raise at the first byte where two checkpoints differ."""
    if left == right:
        return
    var left_bytes = left.as_bytes()
    var right_bytes = right.as_bytes()
    var limit = len(left_bytes)
    if len(right_bytes) < limit:
        limit = len(right_bytes)
    var index = 0
    while index < limit and left_bytes[index] == right_bytes[index]:
        index += 1
    var left_end = index + 80
    if left_end > len(left_bytes):
        left_end = len(left_bytes)
    var right_end = index + 80
    if right_end > len(right_bytes):
        right_end = len(right_bytes)
    raise Error(
        "checkpoint mismatch at "
        + String(index)
        + "\n"
        + String(left[byte=index:left_end])
        + "\n---\n"
        + String(right[byte=index:right_end])
    )


def _cleanup(path: String) raises:
    """Remove a temporary tree."""
    _ = run_program(["rm", "-rf", path], 10)


def _python(
    tools: String,
    root: String,
    build: String,
    compiler: String,
    flags: String,
    mojo: String,
    sources: List[String],
) raises:
    """Write the Python checkpoint into `build`."""
    var oracle = realpath(root + "/..") + "/oracle.py"
    Path(oracle).write_text(
        "import sys\n"
        + "sys.path.insert(0, sys.argv[1])\n"
        + "import coverage_loop_proofs as loops\n"
        + "loops.begin_generation(sys.argv[2], sys.argv[3], sys.argv[4],"
        + " sys.argv[5], mojo=sys.argv[6], sources=sys.argv[7:])\n"
    )
    var command = List[String]()
    command.append("python3")
    command.append(oracle)
    command.append(tools)
    command.append(root)
    command.append(build)
    command.append(compiler)
    command.append(flags)
    command.append(mojo)
    for source in sources:
        command.append(source)
    var ran = run_program(command, 20.0, merge_errors=False)
    if ran.status != 0:
        raise Error(ran.errors + ran.output)


def _mojo(
    root: String,
    build: String,
    compiler: String,
    flags: String,
    mojo: String,
    sources: List[String],
) raises -> ProcessResult:
    """Run the Mojo checkpoint tool."""
    var command = List[String]()
    command.append("sh")
    command.append("tools/tool.sh")
    command.append(tool_mojo())
    command.append("coverage_loop_begin")
    command.append("--root")
    command.append(root)
    command.append("--build")
    command.append(build)
    command.append("--compiler")
    command.append(compiler)
    command.append("--flags")
    command.append(flags)
    command.append("--mojo")
    command.append(mojo)
    command.append("--sources")
    for source in sources:
        command.append(source)
    return run_program(command, 20.0, merge_errors=False)


def _plain(parent: String) raises -> String:
    """Write a tree whose compiler is an ordinary file."""
    var root = parent + "/repo"
    makedirs(root + "/nested", exist_ok=True)
    makedirs(root + "/tools", exist_ok=True)
    makedirs(root + "/assets/nested", exist_ok=True)
    makedirs(root + "/.git", exist_ok=True)
    makedirs(root + "/stage", exist_ok=True)
    Path(root + "/Makefile").write_text("all:\n")
    Path(root + "/module.mojo").write_text("def main():\n    pass\n")
    Path(root + "/nested/other.mojo").write_text("def other():\n    pass\n")
    Path(root + "/tools/note.py").write_text("x = 1\n")
    Path(root + "/assets/pic.txt").write_text("pic\n")
    Path(root + "/assets/nested/noext").write_text("n\n")
    Path(root + "/.git/config").write_text("x\n")
    Path(root + "/skip.txt").write_text("no\n")
    Path(root + "/stage/extra.mojo").write_text("excluded\n")
    Path(root + "/stage/driver").write_text("plain compiler\n")
    Path(parent + "/outside-driver").write_text("outside\n")
    return root


def test_plain_checkpoint_matches_python() raises:
    var parent = mkdtemp(prefix="coverage-begin-")
    try:
        var root = _plain(parent)
        var build = root + "/stage"
        var flags = "-I '' \"quoted value\""
        var mojo = (
            build + "/driver " + parent + "/outside-driver not-a-compiler"
        )
        var sources = List[String]()
        sources.append("module.mojo")
        sources.append("nested/other.mojo")
        _python(
            realpath("tools"), root, build, "Mojo fixture", flags, mojo, sources
        )
        var expected = _text(build + "/generation-inputs.json")
        _ = run_program(["rm", "-f", build + "/generation-inputs.json"], 10)
        var ran = _mojo(root, build, "Mojo fixture", flags, mojo, sources)
        assert_equal(ran.status, 0)
        assert_equal(ran.output, "Coverage generation checkpoint prepared\n")
        _same(expected, _text(build + "/generation-inputs.json"))
        assert_equal(_text(build + "/origins.ready"), "")
    finally:
        _cleanup(parent)


def _wheel(parent: String) raises -> String:
    """Write a small wheel whose probe is a shell stand-in."""
    var root = parent + "/repo"
    var site = root + "/.venv/lib/python3.12/site-packages"
    var bin_dir = root + "/.venv/bin"
    makedirs(bin_dir, exist_ok=True)
    makedirs(site + "/mojo/__pycache__", exist_ok=True)
    makedirs(site + "/modular/lib/mojo", exist_ok=True)
    makedirs(site + "/modular/bin", exist_ok=True)
    makedirs(root + "/stage", exist_ok=True)
    Path(site + "/mojo/_entrypoints.py").write_text("def exec_mojo(): pass\n")
    Path(site + "/mojo/extra.txt").write_text("extra\n")
    Path(site + "/mojo/__pycache__/junk.py").write_text("no\n")
    Path(site + "/mojo/skip.pyc").write_text("pyc\n")
    Path(site + "/modular/lib/mojo/std.mojoc").write_text("stdlib\n")
    Path(site + "/modular/bin/mojo").write_text("compiler\n")
    Path(site + "/modular/bin/lld").write_text("linker\n")
    var payload = (
        '{"version":"probe-version","implementation":"cpython",'
        + '"cache_tag":"cpython-312","byteorder":"little","maxsize":7,'
        + '"soabi":"tag","prefix":"'
        + realpath(root + "/.venv")
        + '","sites":["'
        + realpath(site)
        + '"],"user_site":false,"mojo_paths":["'
        + realpath(site + "/mojo")
        + '"],"entrypoint":"'
        + realpath(site + "/mojo/_entrypoints.py")
        + '","customizers":[]}'
    )
    var python = bin_dir + "/python"
    Path(python).write_text("#!/bin/sh\nprintf '%s\\n' '" + payload + "'\n")
    _ = run_program(["chmod", "755", python], 10)
    Path(bin_dir + "/mojo").write_text(
        "#!"
        + realpath(python)
        + "\nfrom mojo._entrypoints import exec_mojo\nexec_mojo()\n"
    )
    Path(root + "/.venv/pyvenv.cfg").write_text(
        "home = "
        + realpath(bin_dir)
        + "\ninclude-system-site-packages = false\n"
    )
    var record = (
        "mojo/_entrypoints.py,,\nmodular/bin/mojo,,\nmodular/bin/lld,,\n"
        + "modular/lib/mojo/std.mojoc,,\n"
    )
    for package in ["mojo_compiler", "mojo_compiler_mojo_libs"]:
        var name = package.replace("_", "-")
        var directory = site + "/" + package + "-1.1.0.dist-info"
        makedirs(directory, exist_ok=True)
        Path(directory + "/METADATA").write_text(
            "Name: " + name + "\nVersion: 1.1.0\n"
        )
        Path(directory + "/RECORD").write_text(record)
    Path(root + "/Makefile").write_text("all:\n")
    Path(root + "/module.mojo").write_text("def main():\n    pass\n")
    Path(root + "/stage/extra.mojo").write_text("excluded\n")
    Path(root + "/stage/driver").write_text("staged compiler bytes\n")
    Path(parent + "/outside-driver").write_text("outside\n")
    return root


def test_wheel_checkpoint_matches_python() raises:
    var parent = mkdtemp(prefix="coverage-begin-")
    try:
        var root = _wheel(parent)
        var build = root + "/stage"
        var mojo = (
            realpath(root + "/.venv/bin/mojo")
            + " "
            + build
            + "/driver "
            + parent
            + "/outside-driver not-a-compiler"
        )
        var sources = List[String]()
        sources.append("module.mojo")
        _python(
            realpath("tools"),
            root,
            build,
            "Mojo fixture",
            "-I .",
            mojo,
            sources,
        )
        var expected = _text(build + "/generation-inputs.json")
        _ = run_program(["rm", "-f", build + "/generation-inputs.json"], 10)
        _ = run_program(["ln", "-s", root, parent + "/alias"], 10)
        var ran = _mojo(
            parent + "/alias", build, "Mojo fixture", "-I .", mojo, sources
        )
        assert_equal(ran.status, 0)
        _same(expected, _text(build + "/generation-inputs.json"))
    finally:
        _cleanup(parent)


def test_bad_sources_are_refused() raises:
    var parent = mkdtemp(prefix="coverage-begin-")
    try:
        var root = parent + "/repo"
        makedirs(root, exist_ok=True)
        Path(root + "/module.mojo").write_text("def main():\n    pass\n")
        Path(root + "/driver").write_text("compiler\n")
        var sources = List[String]()
        sources.append("module.mojo")
        sources.append("module.mojo")
        var ran = _mojo(
            root,
            root + "/stage",
            "Mojo fixture",
            "-I .",
            root + "/driver",
            sources,
        )
        assert_equal(ran.status, 1)
        assert_true(
            ran.errors.find("Generation requires distinct source identities")
            >= 0
        )
        assert_true(not Path(root + "/stage/generation-inputs.json").exists())
        assert_equal(_text(root + "/stage/origins.ready"), "")
        var other = List[String]()
        other.append("../no.mojo")
        ran = _mojo(
            root,
            root + "/stage",
            "Mojo fixture",
            "-I .",
            root + "/driver",
            other,
        )
        assert_equal(ran.status, 1)
        assert_true(ran.errors.find("Invalid coverage source identity") >= 0)
    finally:
        _cleanup(parent)


def test_usage_exits_2() raises:
    var ran = run_program(
        ["sh", "tools/tool.sh", tool_mojo(), "coverage_loop_begin"],
        20.0,
        merge_errors=False,
    )
    assert_equal(ran.status, 2)
    assert_true(ran.errors.find("usage: coverage_loop_begin ") >= 0)


def test_make_starts_the_checkpoint_in_mojo() raises:
    var text = Path("Makefile").read_text()
    assert_true(
        text.find("$(TOOL) coverage_loop_begin --root . --build $(COV_DIR)")
        >= 0
    )
    assert_true(text.find("coverage_loop_proofs.py begin") < 0)
    assert_true(text.find("coverage_loop_proofs.py seal") >= 0)


def main() raises:
    """Build the tool, then run the tests."""
    var built = run_program(
        [
            "sh",
            "tools/tool.sh",
            tool_mojo(),
            "--build",
            "coverage_loop_begin",
        ],
        120.0,
    )
    if built.status != 0:
        raise Error(built.output + built.errors)
    TestSuite.discover_tests[__functions_in_module()]().run()
