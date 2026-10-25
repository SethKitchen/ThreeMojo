# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Run one raw, compiled, or compiled exact-hit coverage profile.

    coverage_hit_aot --profile aot --root . --suite SUITE --cache CACHE -- \\
        mojo run -I . SUITE

A compiled profile builds the suite, then runs that program. The program's
name stays the source path. `aot-hits` also links `tools/coverage_hit_cache.c`.
One compiler thread is used when the command does not set one.
"""

from std.os import getenv, setenv, unsetenv
from std.os.path import realpath
from std.pathlib import Path
from std.sys import CompilationTarget, argv, exit, stderr

from tools._carla_files import fstat_id
from tools.native_test_support import (
    _exec,
    build_object,
    compiler_identity,
    dependency_inputs,
    run_fixture,
)

comptime HELPER = "tools/coverage_hit_cache.c"
"""The private hit-profile object, relative to the repository root."""

comptime _PHASE = "THREEMOJO_COVERAGE_PHASES"
"""The phase-file path set by the capture wrapper."""


def _usage() -> String:
    """Return the usage line."""
    return (
        "usage: coverage_hit_aot --profile raw|aot|aot-hits "
        + "--root DIR --suite FILE --cache DIR -- COMMAND..."
    )


def _value(arguments: List[String], name: String, index: Int) raises -> String:
    """Return the argument after `name`.

    Args:
        arguments: The command line.
        name: The option.
        index: The index of the option.

    Returns:
        The value.

    Raises:
        Error: If the value is missing.
    """
    if index + 1 >= len(arguments):
        raise Error(name + " needs a value")
    return arguments[index + 1]


def _one_thread(command: List[String]) -> List[String]:
    """Return `command` with one compiler thread when none was set.

    Args:
        command: A Mojo run command.

    Returns:
        The command.
    """
    for word in command:
        if word == "--num-threads":
            var same = List[String]()
            for item in command:
                same.append(item)
            return same^
    var prepared = List[String]()
    var placed = False
    for word in command:
        prepared.append(word)
        if not placed and word == "run":
            prepared.append("--num-threads")
            prepared.append("1")
            placed = True
    return prepared^


def _source_argument(command: List[String], suite: String) raises -> String:
    """Return the command argument that is the suite.

    Args:
        command: A Mojo run command.
        suite: The suite path.

    Returns:
        That argument, as written.

    Raises:
        Error: If the command is not a run command, or the suite is absent.
    """
    if len(command) < 3 or command[1] != "run":
        raise Error("coverage profile requires a Mojo run command")
    var wanted = suite
    if Path(suite).exists():
        wanted = realpath(suite)
    var index = 2
    while index < len(command):
        var argument = command[index]
        if argument.byte_length() > 0 and argument.as_bytes()[0] != 45:
            var found = argument
            if Path(argument).exists():
                found = realpath(argument)
            if found == wanted:
                return argument
        index += 1
    raise Error("coverage profile is missing its source argument")


def _insert_helper(
    command: List[String], suite: String, object: String
) raises -> List[String]:
    """Insert the hit-cache link flags in front of the suite.

    Args:
        command: A Mojo run command.
        suite: The suite path.
        object: The helper object path.

    Returns:
        The command.

    Raises:
        Error: If the suite argument is absent.
    """
    var name = _source_argument(command, suite)
    var prepared = List[String]()
    var index = 0
    var placed = False
    while index < len(command):
        if not placed and command[index] == name:
            prepared.append("-DTHREEMOJO_COVERAGE_HIT_CACHE")
            prepared.append("-Xlinker")
            prepared.append(object)
            placed = True
        prepared.append(command[index])
        index += 1
    return prepared^


def _fifo_stderr() raises -> Bool:
    """Return whether standard error is a pipe or a FIFO."""
    var info = fstat_id(2)
    return info.mode & 0o170000 == 0o010000


def _append_finish(path: String, suite: String, status: Int) raises:
    """Append an adapter-finish record to the phase file.

    Args:
        path: The phase file.
        suite: The suite path.
        status: The profile status.

    Raises:
        Error: If the file cannot be written.
    """
    var stem = suite
    if stem.endswith(".mojo"):
        var end = stem.byte_length() - 5
        var shortened = String(stem[byte=:end])
        stem = shortened
    var slash = stem.rfind("/")
    if slash >= 0:
        var tail = String(stem[byte = slash + 1 :])
        stem = tail
    var line = (
        '{"schema": "coverage-exec-phases-v1", "suite": "'
        + stem
        + '", "phase": "adapter_finish", "diagnostics_complete": true,'
        ' "status": '
        + String(status)
        + "}\n"
    )
    var text = ""
    if Path(path).is_file():
        text = Path(path).read_text()
    Path(path).write_text(text + line)


def _profile(
    profile: String,
    root: String,
    suite: String,
    cache: String,
    cc: String,
    command: List[String],
    repository: String,
) raises -> Int:
    """Run one profile.

    Args:
        profile: `raw`, `aot`, or `aot-hits`.
        root: The tree that holds the suite.
        suite: The suite path.
        cache: The object cache.
        cc: The C compiler command.
        command: The Mojo command.
        repository: The tree that holds `tools/coverage_hit_cache.c`.

    Returns:
        The exit status.

    Raises:
        Error: If the profile or the command is not valid.
    """
    if profile == "raw":
        var needed = dependency_inputs(root, suite)
        if len(needed) > 0:
            return run_fixture(root, suite, cache, cc, command)
        _exec(command)
        return 1
    if profile != "aot" and profile != "aot-hits":
        raise Error("unknown profile " + profile)
    var program = _source_argument(command, suite)
    var prepared = _one_thread(command)
    if profile == "aot-hits":
        if not CompilationTarget.is_linux():
            raise Error("private hit profile currently supports Linux only")
        if not _fifo_stderr():
            raise Error(
                "private hit profile requires a supervised capture pipe"
            )
        var info = fstat_id(2)
        _ = setenv("THREEMOJO_COVERAGE_PIPE_DEVICE", String(info.device), True)
        _ = setenv("THREEMOJO_COVERAGE_PIPE_INODE", String(info.inode), True)
        var identity = compiler_identity(cc + " -pthread")
        var object = build_object(repository, HELPER, cache, identity)
        prepared = _insert_helper(prepared, suite, object)
    return run_fixture(root, suite, cache, cc, prepared, program)


def run_cli(arguments: List[String]) raises -> Int:
    """Run one profile.

    Args:
        arguments: The arguments, without the program name.

    Returns:
        The exit status.

    Raises:
        Error: If the command line is incomplete.
    """
    if len(arguments) == 0:
        raise Error(_usage())
    var profile = String()
    var root = String()
    var suite = String()
    var cache = String()
    var cc = getenv("CC", "cc")
    var repository = "."
    var command = List[String]()
    var index = 0
    while index < len(arguments):
        var word = arguments[index]
        if word == "--":
            index += 1
            while index < len(arguments):
                command.append(arguments[index])
                index += 1
            break
        if word == "--profile":
            profile = _value(arguments, word, index)
            index += 1
        elif word == "--root":
            root = _value(arguments, word, index)
            index += 1
        elif word == "--suite":
            suite = _value(arguments, word, index)
            index += 1
        elif word == "--cache":
            cache = _value(arguments, word, index)
            index += 1
        elif word == "--cc":
            cc = _value(arguments, word, index)
            index += 1
        elif word == "--repository":
            repository = _value(arguments, word, index)
            index += 1
        elif word == "--help" or word == "-h":
            raise Error(_usage())
        elif word.startswith("--"):
            raise Error("unknown argument " + word)
        else:
            command.append(word)
        index += 1
    if (
        profile.byte_length() == 0
        or root.byte_length() == 0
        or suite.byte_length() == 0
        or cache.byte_length() == 0
        or len(command) == 0
    ):
        raise Error(_usage())
    var phase = getenv(_PHASE, "")
    _ = unsetenv(_PHASE)
    _ = unsetenv(_PHASE + "_DEVICE")
    _ = unsetenv(_PHASE + "_INODE")
    var status = _profile(profile, root, suite, cache, cc, command, repository)
    if phase.byte_length() > 0 and Path(phase).is_file():
        _append_finish(phase, suite, status)
    return status


def main() raises:
    """Run a raw or compiled coverage profile."""
    var arguments = List[String]()
    var given = argv()
    for index in range(1, len(given)):
        arguments.append(String(given[index]))
    try:
        exit(run_cli(arguments))
    except error:
        print("coverage_hit_aot: " + String(error), file=stderr)
        var text = String(error)
        if text.startswith("usage:"):
            exit(2)
        exit(1)
