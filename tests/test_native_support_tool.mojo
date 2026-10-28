# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Fixture linking, compiler identity, and the object cache."""

from std.os import getenv, listdir, setenv
from std.pathlib import Path
from std.tempfile import mkdtemp
from std.testing import (
    TestSuite,
    assert_equal,
    assert_not_equal,
    assert_raises,
    assert_true,
)

from tools._process import run_program
from tools._sha256 import sha256_hex
from tools.native_test_support import (
    build_object,
    compiler_identity,
    copy_fixtures,
    dependency_inputs,
    prepare_command,
    prepare_run_commands,
)


def _run(command: List[String]) raises:
    """Run `command` and require status 0.

    Args:
        command: The program and its arguments.

    Raises:
        Error: If the program fails.
    """
    var result = run_program(command, 10.0)
    if result.status != 0:
        raise Error(result.output)


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


def _compiler(path: String, log: String, version: String) raises:
    """Write an executable compiler that records each compilation.

    Args:
        path: The compiler path.
        log: The file that receives one line per compilation.
        version: The text of `--version`.

    Raises:
        Error: If the compiler cannot be installed.
    """
    var text = "#!/bin/sh\n"
    text += 'if [ "$1" = --version ]; then\n'
    text += "  printf '%s\\n' " + version + "\n"
    text += "  exit 0\n"
    text += "fi\n"
    text += "printf 'compile\\n' >> " + log + "\n"
    text += 'if [ "${FAIL:-0}" = 1 ]; then exit 7; fi\n'
    text += "prev=\n"
    text += "src=\n"
    text += "out=\n"
    text += 'for arg in "$@"; do\n'
    text += '  if [ "$prev" = -c ]; then src=$arg; fi\n'
    text += '  if [ "$prev" = -o ]; then out=$arg; fi\n'
    text += "  prev=$arg\n"
    text += "done\n"
    text += (
        'if [ -n "${MUTATE:-}" ]; then printf "changed\\n" > "$MUTATE"; fi\n'
    )
    text += 'cat "$src" > "$out"\n'
    text += "exit 0\n"
    _write(path, text)
    _run(["chmod", "+x", path])


def _lines(path: String) raises -> Int:
    """Return how many lines `path` holds.

    Args:
        path: A text file. A missing file has no lines.

    Returns:
        The line count.
    """
    if not Path(path).is_file():
        return 0
    var count = 0
    for line in Path(path).read_text().split("\n"):
        if line.byte_length() > 0:
            count += 1
    return count


def _join(words: List[String]) -> String:
    """Return `words` on separate lines.

    Args:
        words: The words.

    Returns:
        The joined text.
    """
    return "\n".join(words)


def _tree() raises -> String:
    """Return a tree with one plain suite, one fixture suite, and one aggregate.

    Returns:
        The directory.

    Raises:
        Error: If the tree cannot be created.
    """
    var root = mkdtemp(prefix="native-support-")
    _write(root + "/tests/test_plain.mojo", "def main():\n    pass\n")
    _write(
        root + "/tests/test_carla_sum2_environment.mojo",
        "def main():\n    pass\n",
    )
    _write(
        root + "/tests/aggregate.mojo",
        "from tests.test_carla_sum2_environment import main\n",
    )
    _write(
        root + "/tools/fixtures/carla_sum2_fp_state.c",
        "int marker(void) { return 1; }\n",
    )
    return root


def _cleanup(root: String) raises:
    """Remove `root`.

    Args:
        root: The directory.

    Raises:
        Error: If removal fails.
    """
    _run(["rm", "-rf", root])


def test_dependency_inputs_follow_imports_and_stay_inside_the_root() raises:
    """A fixture suite and an aggregate that imports it both link the C file."""
    var root = _tree()
    try:
        var suite = root + "/tests/test_carla_sum2_environment.mojo"
        var fixture = "tools/fixtures/carla_sum2_fp_state.c"
        assert_equal(_join(dependency_inputs(root, suite)), fixture)
        assert_equal(
            _join(dependency_inputs(root, root + "/tests/aggregate.mojo")),
            fixture,
        )
        assert_equal(
            len(dependency_inputs(root, root + "/tests/test_plain.mojo")), 0
        )
        var outside = root + "-outside.mojo"
        Path(outside).write_text("def main():\n    pass\n")
        with assert_raises(contains="outside the root"):
            _ = dependency_inputs(root, outside)
        assert_equal(_join(dependency_inputs(root, suite)), fixture)
        _run(["rm", "-f", outside])
    finally:
        _cleanup(root)


def test_plain_commands_do_not_call_the_compiler() raises:
    """A suite with no fixture keeps the Mojo command."""
    var root = _tree()
    try:
        var suite = root + "/tests/test_plain.mojo"
        var command = List[String]()
        command.append("mojo")
        command.append("run")
        command.append("--Werror")
        command.append(suite)
        var actual = prepare_command(root, suite, root + "/cache", "", command)
        command[0] = "changed"
        assert_equal(_join(actual), "mojo\nrun\n--Werror\n" + suite)
    finally:
        _cleanup(root)


def test_compiler_identity_binds_bytes_behind_a_wrapper_and_a_symlink() raises:
    """The same version text still changes when an executable's bytes change."""
    var root = _tree()
    var saved = getenv("PATH", "")
    try:
        var log = root + "/log"
        var compiler = root + "/compiler"
        _compiler(compiler, log, "'unchanged version'")
        var before = compiler_identity(compiler)
        assert_true(before.version.find("unchanged version") >= 0)
        Path(compiler).write_text(
            Path(compiler).read_text() + "# different bytes\n"
        )
        _run(["chmod", "+x", compiler])
        var after = compiler_identity(compiler)
        assert_equal(before.version, after.version)
        assert_equal(_join(before.command), _join(after.command))
        assert_not_equal(_join(before.digests), _join(after.digests))
        var real = root + "/real"
        var alias = root + "/alias"
        _run(["mkdir", "-p", real])
        _write(real + "/cc", "compiler bytes\n")
        _write(
            real + "/wrapper", "#!/bin/sh\nprintf 'same version\\n'\nexit 0\n"
        )
        _run(["chmod", "+x", real + "/wrapper", real + "/cc"])
        _run(["ln", "-s", real, alias])
        _ = setenv("PATH", alias + ":/bin:/usr/bin", True)
        var wrapped = compiler_identity(real + "/wrapper cc")
        var files = _join(wrapped.files)
        assert_true(files.find(real + "/wrapper") >= 0)
        assert_true(files.find(real + "/cc") >= 0)
        var digest = _join(wrapped.digests)
        Path(real + "/cc").write_text("compiler bytes changed\n")
        var again = compiler_identity(real + "/wrapper cc")
        assert_equal(wrapped.version, again.version)
        assert_not_equal(digest, _join(again.digests))
    finally:
        _ = setenv("PATH", saved, True)
        _cleanup(root)


def test_build_and_run_commands_keep_flags_and_program_arguments() raises:
    """The fixture object is linked immediately before the suite."""
    var root = _tree()
    try:
        var log = root + "/log"
        var compiler = root + "/cc"
        _compiler(compiler, log, "'fixture compiler 1'")
        var suite = root + "/tests/test_carla_sum2_environment.mojo"
        var cache = root + "/cache"
        var command = List[String]()
        command.append("mojo")
        command.append("build")
        command.append("--num-threads")
        command.append("1")
        command.append("--Werror")
        command.append("-o")
        command.append("some binary")
        command.append(suite)
        var linked = prepare_command(root, suite, cache, compiler, command)
        assert_equal(linked[0], "mojo")
        assert_equal(linked[1], "build")
        assert_equal(linked[len(linked) - 1], suite)
        assert_equal(linked[len(linked) - 3], "-Xlinker")
        assert_true(linked[len(linked) - 2].endswith(".o"))
        assert_equal(_lines(log), 1)
        var executable = root + "/temporary output/suite"
        var run = List[String]()
        run.append("mojo")
        run.append("run")
        run.append("-I")
        run.append("include with spaces")
        run.append("--Werror")
        run.append(suite)
        run.append("two words")
        run.append("--Wno-error")
        var plan = prepare_run_commands(
            root, suite, cache, compiler, run, executable
        )
        var built = _join(plan.build)
        assert_true(built.find("\nrun\n") < 0)
        assert_true(built.find("-I\ninclude with spaces\n--Werror\n-o\n") >= 0)
        assert_true(built.find("-Xlinker\n") >= 0)
        assert_equal(
            _join(plan.execute), executable + "\ntwo words\n--Wno-error"
        )
        assert_equal(_lines(log), 1)
    finally:
        _cleanup(root)


def test_fixture_commands_reject_a_missing_or_repeated_source() raises:
    """A fixture object is linked only from one build of that suite."""
    var root = _tree()
    try:
        var suite = root + "/tests/test_carla_sum2_environment.mojo"
        var cache = root + "/cache"
        var empty = List[String]()
        with assert_raises(contains="a Mojo command is required"):
            _ = prepare_command(root, suite, cache, "unused", empty)
        var run = List[String]()
        run.append("mojo")
        run.append("run")
        run.append(suite)
        with assert_raises(contains="Mojo build command"):
            _ = prepare_command(root, suite, cache, "unused", run)
        var other = List[String]()
        other.append("mojo")
        other.append("build")
        other.append(root + "/other.mojo")
        with assert_raises(contains="exactly once"):
            _ = prepare_command(root, suite, cache, "unused", other)
        var twice = List[String]()
        twice.append("mojo")
        twice.append("build")
        twice.append(suite)
        twice.append(suite)
        with assert_raises(contains="exactly once"):
            _ = prepare_command(root, suite, cache, "unused", twice)
        var translated = List[String]()
        with assert_raises(contains="Mojo run command"):
            _ = prepare_run_commands(
                root, suite, cache, "unused", translated, root + "/binary"
            )
        var built = List[String]()
        built.append("mojo")
        built.append("build")
        built.append(suite)
        with assert_raises(contains="Mojo run command"):
            _ = prepare_run_commands(
                root, suite, cache, "unused", built, root + "/binary"
            )
    finally:
        _cleanup(root)


def test_the_object_cache_follows_source_compiler_and_object_bytes() raises:
    """A cached object is reused only while its recorded bytes still match."""
    var root = _tree()
    try:
        var log = root + "/log"
        var compiler = root + "/cc"
        var fixture = "tools/fixtures/carla_sum2_fp_state.c"
        _compiler(compiler, log, "'fixture compiler 1'")
        var cache = root + "/cache"
        var one = build_object(
            root, fixture, cache, compiler_identity(compiler)
        )
        assert_equal(_lines(log), 1)
        var again = build_object(
            root, fixture, cache, compiler_identity(compiler)
        )
        assert_equal(again, one)
        assert_equal(_lines(log), 1)
        Path(one).write_text("corrupted")
        var repaired = build_object(
            root, fixture, cache, compiler_identity(compiler)
        )
        assert_equal(repaired, one)
        assert_equal(_lines(log), 2)
        var record = Path(
            String(one[byte = : one.byte_length() - 2]) + ".json"
        ).read_text()
        assert_true(record.find("-Werror") >= 0)
        assert_true(record.find(sha256_hex(Path(one).read_bytes())) >= 0)
        _write(root + "/" + fixture, "int marker(void) { return 2; }\n")
        var two = build_object(
            root, fixture, cache, compiler_identity(compiler)
        )
        assert_not_equal(two, one)
        Path(compiler).write_text(
            Path(compiler)
            .read_text()
            .replace("fixture compiler 1", "fixture compiler 2")
        )
        _run(["chmod", "+x", compiler])
        var three = build_object(
            root, fixture, cache, compiler_identity(compiler)
        )
        assert_not_equal(three, two)
        var bytes = Path(compiler).read_text() + "# byte change\n"
        Path(compiler).write_text(bytes)
        _run(["chmod", "+x", compiler])
        var four = build_object(
            root, fixture, cache, compiler_identity(compiler)
        )
        assert_not_equal(four, three)
    finally:
        _cleanup(root)


def test_a_failed_or_racy_compile_leaves_no_object() raises:
    """Compilation failure and a changed fixture install nothing."""
    var root = _tree()
    try:
        var log = root + "/log"
        var compiler = root + "/cc"
        var fixture = "tools/fixtures/carla_sum2_fp_state.c"
        _compiler(compiler, log, "'fixture compiler 1'")
        var cache = root + "/cache"
        _ = setenv("FAIL", "1", True)
        with assert_raises(contains="native test build failed"):
            _ = build_object(root, fixture, cache, compiler_identity(compiler))
        assert_equal(len(listdir(cache)), 0)
        _ = setenv("FAIL", "0", True)
        _ = setenv("MUTATE", root + "/" + fixture, True)
        with assert_raises(contains="changed during compilation"):
            _ = build_object(root, fixture, cache, compiler_identity(compiler))
        assert_equal(len(listdir(cache)), 0)
    finally:
        _ = setenv("FAIL", "", True)
        _ = setenv("MUTATE", "", True)
        _cleanup(root)


def test_the_makefile_uses_the_native_support_adapter() raises:
    """CPU tests and raw coverage call the same Mojo adapter."""
    var make = Path("Makefile").read_text()
    assert_true(make.find("native_test_support run --root .") >= 0)
    assert_true(make.find("native_test_support fingerprint") >= 0)
    assert_true(
        make.find(
            "tools/tool.sh $(MOJO) native_test_support run --root $(COV_DIR)"
        )
        >= 0
    )
    assert_true(
        make.find(
            "$(TOOL) native_test_support copy --root . --destination $(COV_DIR)"
        )
        >= 0
    )
    var marker = "native-tests:$(NATIVE_TOOLCHAIN)"
    var count = 0
    var rest = make
    while rest.find(marker) >= 0:
        count += 1
        var at = rest.find(marker) + marker.byte_length()
        var next = String(rest[byte=at:])
        rest = next
    assert_true(count >= 2)
    assert_true(make.find("TEST_TIMEOUT := 5") >= 0)
    assert_true(make.find("COVERAGE_TESTS := $(CPU_TESTS)") >= 0)
    var root = _tree()
    try:
        _run(["rm", "-f", root + "/tools/fixtures/carla_sum2_fp_state.c"])
        with assert_raises():
            copy_fixtures(root, root + "/coverage/build")
    finally:
        _cleanup(root)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
