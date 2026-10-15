# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Print the key of the `make` stamps: a hash of every build input.

    cache_key --setting=... [--root DIRECTORY]

The key hashes, each with its length, so that a rename or a moved boundary
changes it:

- the `--setting` values: the toolchain, the flags and the time limit;
- the packages installed in `.venv`, by name and version, because MAX can
  change without a change to Mojo;
- the path and the content of each input file: every file under `assets/`,
  each `Makefile`, and each `.mojo`, `.py`, `.json`, `.toml`, `.yaml`,
  `.yml`, `.mjs`, `.c` and `.h` file.

The walk leaves out the directories named in `SKIP` at any depth, and
`coverage/build`. It does not enter a symbolic link to a directory.
"""

from std.os import listdir
from std.os.path import isdir, islink
from std.pathlib import Path
from std.sys import argv, exit, stderr

from tools._imports import sorted_strings
from tools._sha256 import Sha256

comptime SKIP = [
    ".git",
    ".venv",
    ".cache",
    "out",
    "node_modules",
    "__pycache__",
    ".agents",
    ".claude",
]
"""Directory names that hold no build input."""

comptime SUFFIXES = [
    ".mojo",
    ".py",
    ".json",
    ".toml",
    ".yaml",
    ".yml",
    ".mjs",
    ".c",
    ".h",
]
"""The file kinds that are build inputs anywhere."""


def _is_input(path: String, name: String) -> Bool:
    """Return whether a file is a build input."""
    if path.startswith("assets/") or name == "Makefile":
        return True
    var dot = name.rfind(".")
    if dot <= 0:
        return False
    var suffix = String(name[byte=dot:])
    for allowed in materialize[SUFFIXES]():
        if suffix == allowed:
            return True
    return False


def _skipped(path: String, name: String) -> Bool:
    """Return whether the walk leaves out a directory."""
    if path == "coverage/build":
        return True
    for skipped in materialize[SKIP]():
        if name == skipped:
            return True
    return False


def input_paths(root: String) -> List[String]:
    """Return every build input below a root, sorted.

    Args:
        root: The repository root.

    Returns:
        The relative paths.
    """
    var found = List[String]()
    var pending: List[String] = [String()]
    while len(pending) > 0:
        var relative = pending.pop()
        var directory = root + "/" + relative if relative else root
        var names: List[String]
        try:
            names = listdir(directory)
        except:
            continue
        for name in names:
            var path = relative + "/" + name if relative else name
            var full = directory + "/" + name
            if isdir(full):
                if not islink(full) and not _skipped(path, name):
                    pending.append(path)
            elif _is_input(path, name):
                found.append(path)
    return sorted_strings(found^)


def installed_packages(root: String) -> String:
    """Return the packages installed in `.venv`, by name and version.

    Args:
        root: The repository root.

    Returns:
        The sorted names of the `.dist-info` directories, one to a line,
        or an empty string when there is no `.venv`.
    """
    var found = List[String]()
    var lib = root + "/.venv/lib"
    try:
        for python in listdir(lib):
            var packages = lib + "/" + python + "/site-packages"
            if not isdir(packages):
                continue
            for name in listdir(packages):
                if name.endswith(".dist-info"):
                    found.append(python + "/" + name)
    except:
        return String()
    return "\n".join(sorted_strings(found^))


def _add(mut hash: Sha256, data: Span[UInt8, _]):
    """Add one length-prefixed item to the key."""
    var length = UInt64(len(data))
    var prefix = List[UInt8]()
    for shift in range(56, -8, -8):
        prefix.append(UInt8((length >> UInt64(shift)) & 0xFF))
    hash.update(Span(prefix))
    hash.update(data)


def cache_key(root: String, settings: List[String]) raises -> String:
    """Return the key of a tree.

    Args:
        root: The repository root.
        settings: The values to hash before the files.

    Returns:
        The first 20 hexadecimal digits of the SHA-256.

    Raises:
        Error: If an input file cannot be read.
    """
    var hash = Sha256()
    for setting in settings:
        _add(hash, setting.as_bytes())
    for path in input_paths(root):
        _add(hash, path.as_bytes())
        var data = Path(root + "/" + path).read_bytes()
        _add(hash, Span(data))
    return String(hash^.hexdigest()[byte=:20])


def run(arguments: List[String]) raises -> String:
    """Return the key the command line asks for.

    Args:
        arguments: The arguments after the program name.

    Returns:
        The key.

    Raises:
        Error: For a bad command line or an unreadable input.
    """
    var root = String(".")
    var settings = List[String]()
    var index = 0
    while index < len(arguments):
        var argument = arguments[index]
        if argument == "--setting" or argument == "--root":
            if index + 1 >= len(arguments):
                raise Error(argument + " needs a value")
            index += 1
            if argument == "--root":
                root = arguments[index]
            else:
                settings.append(arguments[index])
        elif argument.startswith("--setting="):
            settings.append(String(argument[byte=10:]))
        elif argument.startswith("--root="):
            root = String(argument[byte=7:])
        else:
            raise Error("unknown argument: " + argument)
        index += 1
    settings.append(installed_packages(root))
    return cache_key(root, settings)


def main() raises:
    var arguments = List[String]()
    var given = argv()
    for index in range(1, len(given)):
        arguments.append(String(given[index]))
    try:
        print(run(arguments))
    except error:
        print("cache_key:", error, file=stderr)
        exit(2)
