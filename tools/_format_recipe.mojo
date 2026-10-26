# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Run the Makefile format check in a temporary project.

A shell script stands in for `mojo format`. A `mktemp` on `PATH` puts the
scratch directory at a known path.
"""

from std.os import getenv, listdir
from std.pathlib import Path
from std.tempfile import mkdtemp
from std.testing import assert_equal, assert_true

from tests._make_recipe import (
    LOG_ARGUMENTS,
    clean_command,
    definition,
    read_calls,
    section,
)
from tools._cli import absolute_path
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
    """Return the fixture Makefile's settings.

    Args:
        hash: The text after `HASH`, including `:=` or `?=`.

    Returns:
        The settings lines.
    """
    return (
        "CACHE_DIR := cache\nHASH "
        + hash
        + "\nFMT_STAMP := cache/fmt-$(HASH)\n"
        + "MOJO := sh formatter.sh\n"
        + "TOOL := /tmp/threemojo-shell-log-wrapper\n"
        + "quote = '$(subst ','\"'\"',$(1))'\n"
    )


def _matching(directory: String, part: String) raises -> List[String]:
    """Return the names in a directory that contain `part`.

    Args:
        directory: The directory. A missing directory has no names.
        part: The text each returned name contains.

    Returns:
        The matching names.

    Raises:
        Error: The directory cannot be listed.
    """
    var out = List[String]()
    if not Path(directory).exists():
        return out^
    for name in listdir(directory):
        if name.find(part) >= 0:
            out.append(name)
    return out^


def _mutation(stage: String) -> String:
    """Return the shell command that damages a manifest at `$path`.

    Args:
        stage: The damage name. A name that starts with `truncate-` empties
            the file. Any other name removes it.

    Returns:
        The shell command.
    """
    if stage.startswith("truncate-"):
        return ': > "$path"'
    return 'rm -f "$path"'


def _damage(stage: String, at: List[String]) -> String:
    """Return shell lines that damage the manifest when `stage` is in `at`.

    Args:
        stage: The requested damage.
        at: The stages that damage the manifest.

    Returns:
        The shell lines, or empty text when `stage` is not in `at`.
    """
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
    limit: Float64 = 60,
) raises -> Outcome:
    """Run `fmt-check` on `paths` in a temporary project.

    Args:
        paths: The files the recipe selects, in order.
        fail_batch: The formatter call that exits 7. Zero means none.
        changed: The file names the formatter rewrites.
        missing: The selected files that are not created.
        scratch_padding: Extra text in the scratch directory name.
        delete_manifest_stage: When the stand-in removes the manifest.
        check_manifest_commands: True to syntax-check each manifest writer.
        reset_tmpdir: True to pass the outer `TMPDIR` into make.
        outer: True to set an outer make's variables first.
        limit: The time limit for the make run, in seconds.

    Returns:
        The make result, the selected paths, the formatter calls, and
        whether the stamp exists.

    Raises:
        Error: A fixture file cannot be written, or a check inside the
            recipe fails.
    """
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
        limit,
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


def install_format_log() raises:
    """Point the format id command at the built Mojo program.

    Raises:
        Error: The wrapper cannot be written, or the program cannot be built.
    """
    var root = absolute_path(".")
    Path("/tmp/threemojo-shell-log-wrapper").write_text(
        "#!/bin/sh\nexec sh "
        + shell_quote(root + "/tools/tool.sh")
        + " "
        + shell_quote(root + "/.venv/bin/mojo")
        + ' "$@"\n'
    )
    var mode = run_program(
        ["chmod", "755", "/tmp/threemojo-shell-log-wrapper"], 10
    )
    if mode.status != 0:
        raise Error(mode.output)
    var built = run_program(
        [
            "sh",
            root + "/tools/tool.sh",
            root + "/.venv/bin/mojo",
            "--build",
            "shell_log",
        ],
        120,
    )
    if built.status != 0:
        raise Error(built.output + built.errors)
