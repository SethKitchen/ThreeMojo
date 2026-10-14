# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Print the test suites that must run again, each with its cache key.

    suite_key --stamps .cache/suites --setting=... SUITE...

prints `SUITE KEY` for each suite that has no stamp named `NAME-KEY` in
`--stamps`, and a count of the others on standard error. `make test-cpu`
builds and runs only the printed suites, and writes the stamp when one
passes.

A suite's key hashes everything that can change what it does:

- the suite and every file it imports, directly or through other files,
  as `tools._imports.closure` finds them;
- every file under `assets/` whose path starts with a path that one of
  those files quotes, as `"assets/draco/"` does;
- the `Makefile` and the tools that build and run a suite, this tool's
  own import closure too;
- the native test fixtures that the suite links;
- the `--setting` values: the toolchain, the flags and the time limit.

So a change to one module runs only the suites that can reach it. A change
that the import graph cannot see, such as a new file that a suite reads
through a path it builds at run time, is not seen. `make -B test-cpu`
ignores the stamps and runs every suite.
"""

from std.collections import Set
from std.pathlib import Path
from std.sys import argv, exit, stderr

from tools._imports import (
    SourceCache,
    closure,
    mojo_files,
    sorted_strings,
    walk_files,
)
from tools._sha256 import Sha256

comptime TOOLING = [
    "Makefile",
    "tools/tool.sh",
    "tools/run_suite.mojo",
    "tools/compiler_telemetry.py",
    "tools/native_test_support.py",
]
"""The files besides this tool's own sources that decide how a suite is
built and run."""

comptime SELF = "tools/suite_key.mojo"
"""This tool. Its import closure is part of every key."""

comptime FIXTURES = [
    (
        "tests/test_carla_sum2_environment.mojo",
        "tools/fixtures/carla_sum2_fp_state.c",
    ),
    (
        "tests/test_carla_junction_endpoint_refusals.mojo",
        "tools/fixtures/carla_sum2_fp_state.c",
    ),
]
"""The C fixture each suite links. It is the `FIXTURES` table of
`tools/native_test_support.py`, and a test keeps the two the same."""


def fixture_inputs(files: List[String]) -> List[String]:
    """Return the sorted C fixtures that a set of files links.

    Args:
        files: A suite's import closure.

    Returns:
        Each fixture once.
    """
    var table = materialize[FIXTURES]()
    var found = Set[String]()
    for name in files:
        for entry in table:
            if name == entry[0]:
                found.add(entry[1])
    var list = List[String]()
    for item in found:
        list.append(item)
    return sorted_strings(list^)


def asset_files(root: String) -> List[String]:
    """Return every file under `assets/`, sorted.

    Args:
        root: The repository root.

    Returns:
        The relative paths.
    """
    return sorted_strings(walk_files(root, "assets", False))


struct KeyInputs(Movable):
    """What every key reads, found once for all the suites."""

    var root: String
    """The repository root."""
    var known: Set[String]
    """Every `.mojo` path."""
    var assets: List[String]
    """Every file under `assets/`, sorted."""
    var tooling: List[String]
    """The tool files, in key order."""
    var cache: SourceCache
    """The imports read so far."""
    var digests: Dict[String, List[UInt8]]
    """The SHA-256 of each file hashed so far."""

    def __init__(
        out self,
        root: String,
        var tooling: List[String],
        var assets: List[String],
    ) raises:
        """Find the source files.

        Args:
            root: The repository root.
            tooling: The tool files.
            assets: The asset files.

        Raises:
            Error: If this tool's sources cannot be read.
        """
        self.root = root
        self.known = Set[String]()
        for path in mojo_files(root):
            self.known.add(path)
        self.assets = assets^
        self.tooling = tooling^
        self.cache = SourceCache()
        self.digests = Dict[String, List[UInt8]]()

    @staticmethod
    def standard(root: String) raises -> KeyInputs:
        """Return the inputs `make test-cpu` uses.

        Args:
            root: The repository root.

        Returns:
            The inputs, with `TOOLING` and this tool's import closure.

        Raises:
            Error: If this tool's sources cannot be read.
        """
        var inputs = KeyInputs(root, List[String](), asset_files(root))
        for path in materialize[TOOLING]():
            inputs.tooling.append(path)
        if SELF in inputs.known:
            inputs.tooling.extend(
                closure(root, SELF, inputs.known, inputs.cache)
            )
        return inputs^

    def file_digest(mut self, path: String) raises -> List[UInt8]:
        """Return the SHA-256 of a file, once per file.

        Args:
            path: The file, relative to the root.

        Returns:
            The 32 digest bytes.

        Raises:
            Error: If the file cannot be read.
        """
        var known = self.digests.get(path)
        if known:
            return known.value().copy()
        var hash = Sha256()
        var data = Path(self.root + "/" + path).read_bytes()
        hash.update(Span(data))
        var digest = hash^.digest()
        var bytes = List[UInt8]()
        for byte in digest:
            bytes.append(byte)
        self.digests[path] = bytes.copy()
        return bytes^


def _add(mut hash: Sha256, data: Span[UInt8, _]):
    """Add one length-prefixed item to a key."""
    var length = UInt64(len(data))
    var prefix = List[UInt8]()
    for shift in range(56, -8, -8):
        prefix.append(UInt8((length >> UInt64(shift)) & 0xFF))
    hash.update(Span(prefix))
    hash.update(data)


def suite_key(
    suite: String, settings: List[String], mut inputs: KeyInputs
) raises -> String:
    """Return the cache key of a suite.

    Args:
        suite: The suite.
        settings: The `--setting` values, in order.
        inputs: The shared inputs.

    Returns:
        The first 20 hexadecimal digits of the SHA-256 of the settings and
        of the name and content digest of each input file.

    Raises:
        Error: If an input file cannot be read.
    """
    var hash = Sha256()
    for setting in settings:
        _add(hash, setting.as_bytes())
    var files = closure(inputs.root, suite, inputs.known, inputs.cache)
    var quoted = Set[String]()
    for path in files:
        for prefix in inputs.cache.assets[path]:
            quoted.add(prefix)
    var used = List[String]()
    for path in inputs.assets:
        for prefix in quoted:
            if path.startswith(prefix):
                used.append(path)
                break
    var all = inputs.tooling.copy()
    all.extend(files.copy())
    all.extend(used^)
    all.extend(fixture_inputs(files))
    for path in all:
        _add(hash, path.as_bytes())
        var digest = inputs.file_digest(path)
        _add(hash, Span(digest))
    return String(hash^.hexdigest()[byte=:20])


def run(root: String, arguments: List[String]) raises -> Tuple[String, String]:
    """Return what the tool prints on standard output and standard error.

    Args:
        root: The repository root. A relative `--stamps` is relative to the
            current directory.
        arguments: The arguments after the program name.

    Returns:
        The output lines and the count line, each without a final line end.

    Raises:
        Error: For a bad command line or an unreadable input.
    """
    var stamps = String()
    var settings = List[String]()
    var suites = List[String]()
    var index = 0
    while index < len(arguments):
        var argument = arguments[index]
        if argument == "--stamps" or argument == "--setting":
            if index + 1 >= len(arguments):
                raise Error(argument + " needs a value")
            index += 1
            if argument == "--stamps":
                stamps = arguments[index]
            else:
                settings.append(arguments[index])
        elif argument.startswith("--stamps="):
            stamps = String(argument[byte=9:])
        elif argument.startswith("--setting="):
            settings.append(String(argument[byte=10:]))
        elif argument.startswith("-"):
            raise Error("unknown option: " + argument)
        else:
            suites.append(argument)
        index += 1
    if not stamps:
        raise Error("--stamps is required")
    var inputs = KeyInputs.standard(root)
    var lines = List[String]()
    var cached = 0
    for suite in suites:
        var key = suite_key(suite, settings, inputs)
        var base = suite[byte = suite.rfind("/") + 1 :]
        var name = String(base[byte = : base.rfind(".")]) if base.rfind(
            "."
        ) > 0 else String(base)
        if Path(stamps + "/" + name + "-" + key).exists():
            cached += 1
        else:
            lines.append(suite + " " + key)
    var summary = (
        String(cached)
        + " of "
        + String(len(suites))
        + " suites passed before and are unchanged."
    )
    return ("\n".join(lines), summary)


def main() raises:
    var arguments = List[String]()
    var given = argv()
    for index in range(1, len(given)):
        arguments.append(String(given[index]))
    try:
        var result = run(".", arguments)
        if result[0]:
            print(result[0])
        print(result[1], file=stderr)
    except error:
        print("suite_key:", error, file=stderr)
        exit(2)
