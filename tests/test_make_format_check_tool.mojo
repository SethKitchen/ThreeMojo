# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Exercise bounded formatting recipes without the Mojo compiler.

Each test copies the maintained `fmt-check` recipe from the `Makefile` into
a temporary project. A shell script stands in for `mojo format`, and a
`mktemp` on `PATH` makes the scratch directory at a known path.

The 1789-path check stays in `tools/test_make_format_check.py`: the recipe
copies and compares one file per process, so it needs more than the
five-second limit of a test here.
"""

from std.os import getenv, listdir
from std.pathlib import Path
from std.tempfile import mkdtemp
from std.testing import TestSuite, assert_equal, assert_false, assert_true

from tests._make_recipe import (
    LOG_ARGUMENTS,
    clean_command,
    definition,
    read_calls,
    section,
)
from tools._process import ProcessResult, run_program, shell_quote

comptime START = "# mojo format has no --check flag"
"""The first line of the formatting recipes."""

comptime END = "\n# Instrument the library"
"""The text after the formatting recipes."""


@fieldwise_init
struct Outcome(Movable):
    """What one formatting check did."""

    var result: ProcessResult
    """The make run."""
    var selected: List[String]
    """Each formatted path, relative to the scratch directory."""
    var calls: List[List[String]]
    """Each formatter call's paths."""
    var stamped: Bool
    """Whether the check left its stamp."""


def _header(hash: String) -> String:
    """Return the fixture Makefile's settings and the shared definitions."""
    return (
        "CACHE_DIR := cache\nHASH "
        + hash
        + "\nFMT_STAMP := cache/fmt-$(HASH)\n"
        + "MOJO := sh formatter.sh\n"
        + "quote = '$(subst ','\"'\"',$(1))'\n"
    )


def _matching(directory: String, part: String) raises -> List[String]:
    """Return the names in a directory that contain `part`."""
    var out = List[String]()
    if not Path(directory).exists():
        return out^
    for name in listdir(directory):
        if name.find(part) >= 0:
            out.append(name)
    return out^


def _mutation(stage: String) -> String:
    """Return the shell command that damages a manifest at `$path`."""
    if stage.startswith("truncate-"):
        return ': > "$path"'
    return 'rm -f "$path"'


def _damage(stage: String, at: List[String]) -> String:
    """Return shell lines that damage the manifest when `stage` is in `at`."""
    for name in at:
        if stage == name:
            return (
                "for path in cache/*inputs-*; do\n"
                + '  [ -e "$path" ] && '
                + _mutation(stage)
                + "\ndone\n"
            )
    return ""


def run_recipe(
    paths: List[String],
    fail_batch: Int = 0,
    changed: List[String] = [],
    missing: List[String] = [],
    scratch_padding: String = "",
    delete_manifest_stage: String = "",
    check_manifest_commands: Bool = False,
    reset_tmpdir: Bool = False,
    outer: Bool = False,
) raises -> Outcome:
    var source = Path("Makefile").read_text()
    var recipe = section(source, START, END)
    var root = mkdtemp(prefix="format fixture ")
    var scratch = root + "/scratch files " + scratch_padding
    _ = run_program(["mkdir", "-p", scratch, root + "/bin"], 10)
    var unique = List[String]()
    for name in paths:
        var seen = False
        for other in unique:
            if other == name:
                seen = True
        if not seen:
            unique.append(name)
    var directories = List[String]()
    for name in unique:
        var skip = False
        for item in missing:
            if item == name:
                skip = True
        if skip:
            continue
        var slash = name.rfind("/")
        var directory = root + "/" + String(name[byte=:slash])
        var known = False
        for other in directories:
            if other == directory:
                known = True
        if not known:
            directories.append(directory)
            _ = run_program(["mkdir", "-p", directory], 10)
        Path(root + "/" + name).write_text("original\n")
    # Avoid platform-dependent TMPDIR handling. Pass the fixture path
    # explicitly so spaces and byte-budget padding always reach make.
    Path(root + "/bin/mktemp").write_text(
        "#!/bin/sh\n"
        + '[ "$#" = 1 ] && [ "$1" = -d ] || exit 3\n'
        + _damage(delete_manifest_stage, ["copy", "truncate-copy"])
        + "directory="
        + shell_quote(scratch)
        + "/tmp$$\n"
        + 'mkdir "$directory" || exit 1\n'
        + "printf '%s\\n' \"$directory\"\n"
    )
    _ = run_program(["chmod", "700", root + "/bin/mktemp"], 10)
    Path(root + "/unselected.mojo").write_text("unselected\n")
    var changed_words = String()
    for name in changed:
        changed_words += " " + shell_quote(name)
    Path(root + "/formatter.sh").write_text(
        '[ "$1" = format ] && [ "$2" = -q ] || exit 3\n'
        + "shift 2\n"
        + '[ "$#" -gt 0 ] || exit 3\n'
        + "batch=1\n"
        + "[ -f invocations ] && batch=$(($(wc -l < invocations) + 1))\n"
        + LOG_ARGUMENTS
        + 'echo "Failed to initialize Crashpad"\n'
        + 'if [ "$batch" = '
        + String(fail_batch)
        + " ]; then\n"
        + '  echo "formatter failed"\n  exit 7\nfi\n'
        + _damage(delete_manifest_stage, ["diff", "truncate-diff"])
        + 'for name in "$@"; do\n'
        + "  for item in"
        + changed_words
        + "; do\n"
        + '    case "$name" in */"$item") printf "formatted\\n" > "$name";;'
        " esac\n"
        + "  done\n"
        + "done\n"
    )
    var formatted = String()
    for name in paths:
        if formatted:
            formatted += " "
        formatted += name
    Path(root + "/Makefile").write_text(
        _header(":= fixture")
        + "FORMATTED := "
        + formatted
        + "\n"
        + definition(source, "run")
        + "\n"
        + definition(source, "stamp")
        + "\n"
        + recipe
        + "\n"
    )
    var settings: List[String] = [
        "PATH=" + root + "/bin:" + getenv("PATH", "/usr/bin:/bin")
    ]
    if reset_tmpdir:
        settings.append("TMPDIR=" + getenv("TMPDIR", "/tmp"))
    if check_manifest_commands:
        var preview = run_program(
            clean_command(settings, ["make", "-n", "fmt-check"], outer),
            30,
            merge_errors=False,
            directory=root,
        )
        assert_equal(preview.status, 0, preview.errors)
        var writers = 0
        for line in preview.output.splitlines():
            var command = String(line)
            if command.startswith("printf '%s"):
                writers += 1
                assert_true(command.byte_length() < 131072)
                var syntax = run_program(
                    ["/bin/sh", "-n", "-c", command], 10, merge_errors=False
                )
                assert_equal(syntax.status, 0, syntax.errors)
        assert_true(writers > 0)
    var result = run_program(
        clean_command(settings, ["make", "-s", "fmt-check"], outer),
        60,
        merge_errors=False,
        directory=root,
    )
    var calls = read_calls(root + "/invocations")
    var selected = List[String]()
    for call in calls:
        for name in call:
            var at = name.find("/src/")
            assert_true(at >= 0, name)
            selected.append("src/" + String(name[byte = at + 5 :]))
    for name in unique:
        var skip = False
        for item in missing:
            if item == name:
                skip = True
        if not skip:
            assert_equal(Path(root + "/" + name).read_text(), "original\n")
    assert_equal(Path(root + "/unselected.mojo").read_text(), "unselected\n")
    assert_equal(len(listdir(scratch)), 0)
    assert_equal(len(_matching(root + "/cache", "inputs-")), 0)
    assert_equal((result.output + result.errors).find("Crashpad"), -1)
    var stamped = Path(root + "/cache/fmt-fixture").exists()
    _ = run_program(["rm", "-rf", root], 30)
    return Outcome(result^, selected^, calls^, stamped)


def _numbered(count: Int, width: Int = 3) -> List[String]:
    """Return `src/000.mojo`, `src/001.mojo` and so on."""
    var out = List[String]()
    for index in range(count):
        var digits = String(index)
        while digits.byte_length() < width:
            digits = "0" + digits
        out.append("src/" + digits + ".mojo")
    return out^


def _byte_budget(calls: List[List[String]]) -> Bool:
    """Return whether each call's paths and separators fit in 8192 bytes."""
    for call in calls:
        var size = 0
        for path in call:
            size += path.byte_length() + 1
        if size > 8192:
            return False
    return True


def test_empty_selection_does_not_invoke_formatter() raises:
    var outcome = run_recipe([])
    assert_equal(
        outcome.result.status, 0, outcome.result.output + outcome.result.errors
    )
    assert_equal(len(outcome.calls), 0)
    assert_true(outcome.stamped)


def test_small_selection_keeps_order_duplicates_and_scratch_spaces() raises:
    var paths: List[String] = [
        "src/z.mojo",
        "src/quote's.mojo",
        "src/a.mojo",
        "src/z.mojo",
    ]
    var outcome = run_recipe(paths)
    assert_equal(
        outcome.result.status, 0, outcome.result.output + outcome.result.errors
    )
    assert_true(outcome.selected == paths)
    assert_equal(len(outcome.calls), 1)
    assert_true(outcome.stamped)
    assert_true(outcome.calls[0][0].find("scratch files ") >= 0)


def test_byte_budget_splits_before_file_count_limit() raises:
    var paths = _numbered(70)
    var padding = String()
    for _ in range(180):
        padding += "x"
    var outcome = run_recipe(paths, scratch_padding=padding)
    assert_equal(
        outcome.result.status, 0, outcome.result.output + outcome.result.errors
    )
    assert_true(outcome.selected == paths)
    assert_true(len(outcome.calls[0]) < 64)
    assert_true(_byte_budget(outcome.calls))
    assert_true(outcome.stamped)


def test_scratch_path_survives_subprocess_tmpdir_reset() raises:
    var paths = _numbered(70)
    var padding = String()
    for _ in range(180):
        padding += "x"
    var outcome = run_recipe(paths, scratch_padding=padding, reset_tmpdir=True)
    assert_equal(
        outcome.result.status, 0, outcome.result.output + outcome.result.errors
    )
    assert_true(outcome.selected == paths)
    assert_true(outcome.calls[0][0].find("scratch files ") >= 0)
    assert_true(len(outcome.calls[0]) < 64)
    assert_true(_byte_budget(outcome.calls))
    assert_true(outcome.stamped)


def test_formatter_failure_stops_next_batch_and_is_not_stamped() raises:
    var paths = _numbered(140)
    var outcome = run_recipe(paths, fail_batch=2)
    assert_true(outcome.result.status != 0)
    assert_true(outcome.result.output.find("formatter failed") >= 0)
    assert_true(outcome.result.errors.find("Error 7") >= 0)
    assert_equal(len(outcome.calls), 2)
    for index in range(len(outcome.selected)):
        assert_equal(outcome.selected[index], paths[index])
    assert_true(len(outcome.selected) < len(paths))
    assert_false(outcome.stamped)


def test_all_differences_are_reported_without_changing_sources() raises:
    var paths = _numbered(140)
    var changed: List[String] = [paths[0], paths[70], paths[len(paths) - 1]]
    var outcome = run_recipe(paths, changed=changed)
    assert_true(outcome.result.status != 0)
    assert_true(outcome.selected == paths)
    for name in changed:
        assert_true(
            outcome.result.output.find("needs formatting: " + name) >= 0
        )
    assert_true(outcome.result.output.find("Run 'make fmt'.") >= 0)
    assert_false(outcome.stamped)


def test_missing_input_fails_without_stamp() raises:
    var paths: List[String] = ["src/present.mojo", "src/missing.mojo"]
    var outcome = run_recipe(paths, missing=["src/missing.mojo"])
    assert_true(outcome.result.status != 0)
    assert_equal(len(outcome.calls), 0)
    assert_false(outcome.stamped)


def test_missing_or_truncated_manifest_fails_at_both_read_loops() raises:
    for stage in ["copy", "diff", "truncate-copy", "truncate-diff"]:
        var outcome = run_recipe(["src/a.mojo"], delete_manifest_stage=stage)
        assert_true(outcome.result.status != 0, stage)
        assert_equal(
            outcome.result.output.find("All files formatted."), -1, stage
        )
        assert_false(outcome.stamped, stage)
        assert_equal(
            len(outcome.calls), 0 if stage.endswith("copy") else 1, stage
        )


def test_long_paths_cannot_overflow_manifest_recipe_arguments() raises:
    # These are readable where PATH_MAX permits, but 64 quoted copies
    # exceed Linux's single-argument limit. Four per recipe stay bounded.
    var prefix = String("src/")
    var part = String()
    for _ in range(180):
        part += "d"
    for _ in range(12):
        prefix += part + "/"
    var paths = List[String]()
    for path in _numbered(64):
        paths.append(prefix + String(path[byte=4:]))
    var limit = run_program(
        ["getconf", "PATH_MAX", getenv("TMPDIR", "/tmp")], 10
    )
    var value = String(limit.output.strip())
    if limit.status != 0 or value == "undefined" or Int(value) < 3000:
        # The platform path limit is below the long-path fixture.
        return
    var outcome = run_recipe(paths, check_manifest_commands=True)
    assert_equal(
        outcome.result.status, 0, outcome.result.output + outcome.result.errors
    )
    assert_true(outcome.selected == paths)
    assert_true(outcome.stamped)


def _concurrent(same_hash: Bool) raises:
    var source = Path("Makefile").read_text()
    var root = mkdtemp(prefix="format concurrent ")
    _ = run_program(["mkdir", "-p", root + "/src", root + "/results"], 10)
    for name in ["a", "b"]:
        Path(root + "/src/" + name + ".mojo").write_text("original\n")
    _ = run_program(["mkfifo", root + "/release"], 10)
    Path(root + "/formatter.sh").write_text(
        "shift 2\n"
        + 'for path in "$@"; do\n'
        + '  case "$path" in\n'
        + "    */b.mojo)\n"
        + "      : > ready\n"
        + "      read -r gate < release\n"
        + "      printf 'formatted\\n' > \"$path\";;\n"
        + "  esac\n"
        + "done\n"
    )
    Path(root + "/Makefile").write_text(
        _header("?= fixture")
        + definition(source, "run")
        + "\n"
        + definition(source, "stamp")
        + "\n"
        + section(source, START, END)
        + "\n"
    )
    var b_hash = "same" if same_hash else "b"
    var a_hash = "same" if same_hash else "a"
    var clean = String()
    for word in clean_command([], []):
        clean += shell_quote(word) + " "
    # Start the check of b, wait until its formatter blocks, check a, then
    # release b. The script stops b if its formatter does not start.
    var script = (
        clean
        + "make -s fmt-check HASH="
        + b_hash
        + " FORMATTED=src/b.mojo >results/b.out 2>results/b.err &\n"
        + "pid=$!\n"
        + "tries=0\n"
        + "while [ ! -e ready ]; do\n"
        + '  if ! kill -0 "$pid" 2>/dev/null || [ "$tries" -ge 1000 ]; then\n'
        + '    echo "blocked formatting fixture did not start"\n'
        + '    kill -KILL "$pid" 2>/dev/null; exit 90\n'
        + "  fi\n"
        + "  tries=$((tries + 1)); sleep 0.01\n"
        + "done\n"
        + "ls cache | grep -c 'inputs-' > results/manifests\n"
        + clean
        + "make -s fmt-check HASH="
        + a_hash
        + " FORMATTED=src/a.mojo >results/a.out 2>results/a.err\n"
        + "echo $? > results/a.status\n"
        + "printf x > release\n"
        + 'wait "$pid"; echo $? > results/b.status\n'
    )
    var run = run_program(["sh", "-c", script], 20, directory=root)
    assert_equal(run.status, 0, run.output)
    var results = root + "/results/"
    var a_status = String(Path(results + "a.status").read_text().strip())
    var b_status = String(Path(results + "b.status").read_text().strip())
    var a_text = (
        Path(results + "a.out").read_text()
        + Path(results + "a.err").read_text()
    )
    var b_out = Path(results + "b.out").read_text()
    var b_text = b_out + Path(results + "b.err").read_text()
    assert_equal(a_status, "0", a_text)
    assert_true(b_status != "0", b_text)
    assert_true(b_out.find("needs formatting: src/b.mojo") >= 0)
    assert_equal(b_out.find("All files formatted."), -1)
    assert_equal(String(Path(results + "manifests").read_text().strip()), "1")
    assert_equal(len(_matching(root + "/cache", "inputs-")), 0)
    if not same_hash:
        assert_false(Path(root + "/cache/fmt-b").exists())
    assert_equal(Path(root + "/src/b.mojo").read_text(), "original\n")
    _ = run_program(["rm", "-rf", root], 10)


def test_concurrent_checks_keep_private_manifests_and_detect_changes() raises:
    _concurrent(False)
    _concurrent(True)


def test_outer_make_overrides_cannot_replace_fixture_formatter() raises:
    var outcome = run_recipe(["src/a.mojo"], outer=True)
    assert_equal(
        outcome.result.status, 0, outcome.result.output + outcome.result.errors
    )
    var expected: List[String] = ["src/a.mojo"]
    assert_true(outcome.selected == expected)
    assert_true(outcome.stamped)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
