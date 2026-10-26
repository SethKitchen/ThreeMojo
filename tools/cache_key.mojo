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

Each file enters the key as its path and the SHA-256 of its content. The
digests are kept in `.cache/cache-key-files`, when `.cache` exists, with
the size, the change and modification times and the inode of each file.
A file whose four values are the same is not read again, as git's index
works. A file that changed less than two seconds before that list was
written is read again: a second change in the same clock tick would keep
the same times. A key over an unchanged tree then costs a walk and a
`stat` for each file, not a read of every byte.
"""

from std.ffi import c_int, external_call
from std.os import listdir, stat
from std.os.path import isdir, islink
from std.pathlib import Path
from std.sys import argv, exit, stderr

from tools._imports import sorted_strings
from tools._sha256 import Sha256, sha256_hex

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


comptime MEMO = ".cache/cache-key-files"
"""The digest list, below the root."""

comptime RACY_NS = 2_000_000_000
"""How close to the list's own write a change may be, in nanoseconds, and
still be read again."""


@fieldwise_init
struct _Seen(Copyable, Movable):
    """One file as the digest list saw it."""

    var stamp: String
    """The size, change time, modification time and inode, as text."""
    var changed: Int
    """The later of the change and modification times, in nanoseconds."""
    var digest: String
    """The SHA-256 of the content."""


def _stamp(full: String) raises -> Tuple[String, Int]:
    """Return what `stat` says of a file, and its latest time.

    Args:
        full: The file.

    Returns:
        The size, change time, modification time and inode as text, and
        the later of the two times in nanoseconds.

    Raises:
        Error: If the file cannot be read.
    """
    var info = stat(full)
    var modified = Int(info.st_mtimespec.tv_sec) * 1_000_000_000 + Int(
        info.st_mtimespec.tv_nsec
    )
    var changed = Int(info.st_ctimespec.tv_sec) * 1_000_000_000 + Int(
        info.st_ctimespec.tv_nsec
    )
    var text = (
        String(Int(info.st_size))
        + ":"
        + String(changed)
        + ":"
        + String(modified)
        + ":"
        + String(Int(info.st_ino))
    )
    return (text, max(changed, modified))


def _memo(root: String) -> Dict[String, _Seen]:
    """Return the digests the last key wrote that can still be trusted.

    Args:
        root: The repository root.

    Returns:
        Each path whose entry predates the list's own write by more than
        `RACY_NS`. Empty when there is no list or it cannot be read.
    """
    var seen = Dict[String, _Seen]()
    var path = root + "/" + MEMO
    try:
        var written = _stamp(path)[1]
        for line in Path(path).read_text().splitlines():
            var fields = line.split(" ", 3)
            if len(fields) != 4:
                continue
            var changed = Int(fields[1])
            if changed + RACY_NS >= written:
                continue
            seen[String(fields[3])] = _Seen(
                String(fields[0]), changed, String(fields[2])
            )
    except:
        return Dict[String, _Seen]()
    return seen^


def _write_memo(root: String, lines: String):
    """Replace the digest list in one step, if `.cache` exists.

    Args:
        root: The repository root.
        lines: The new list.
    """
    if not isdir(root + "/.cache"):
        return
    var target = root + "/" + MEMO
    var temporary = (
        target + "." + String(Int(external_call["getpid", c_int]())) + ".tmp"
    )
    try:
        Path(temporary).write_text(lines)
        var source = List[UInt8](capacity=temporary.byte_length() + 1)
        for byte in temporary.as_bytes():
            source.append(byte)
        source.append(0)
        var destination = List[UInt8](capacity=target.byte_length() + 1)
        for byte in target.as_bytes():
            destination.append(byte)
        destination.append(0)
        _ = external_call["rename", c_int](
            source.unsafe_ptr(), destination.unsafe_ptr()
        )
    except:
        pass


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
    var seen = _memo(root)
    var lines = String()
    var read = 0
    for path in input_paths(root):
        var full = root + "/" + path
        var stamp = _stamp(full)
        var digest: String
        var known = seen.get(path)
        if known and known.value().stamp == stamp[0]:
            digest = known.value().digest
        else:
            digest = sha256_hex(Span(Path(full).read_bytes()))
            read += 1
        _add(hash, path.as_bytes())
        _add(hash, digest.as_bytes())
        lines += stamp[0] + " " + String(stamp[1]) + " " + digest + " " + path
        lines += "\n"
    if read > 0:
        _write_memo(root, lines)
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
