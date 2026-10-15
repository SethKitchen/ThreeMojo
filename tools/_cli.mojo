# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Read a small command line as Python's `argparse` reads it.

A tool that replaces a Python tool must accept the same command line and
print the same usage, help and error text. `parse_command_line` handles the
long options that these tools use: flags, options with one value, `-h` and
`--help`, a unique prefix of a long option, `--name=value` and `--`.
`absolute_path` resolves a path that an option names, as `Path.resolve()`
does.
"""

from std.collections import Set
from std.os.path import exists, realpath

from tools._python_json import py_repr


struct CommandLine(Movable):
    """The parsed options, or the text to print and the exit status."""

    var status: Int
    """0 to continue, -1 after `--help`, or 2 for a usage error."""
    var message: String
    """The help or error text. Help goes to the standard output, and an
    error to the standard error."""
    var flags: Set[String]
    """Each flag that the command line gave, such as `--available`."""
    var values: Dict[String, String]
    """Each option with a value, and its last value."""

    def __init__(out self):
        """Make an empty result that continues."""
        self.status = 0
        self.message = String()
        self.flags = Set[String]()
        self.values = Dict[String, String]()

    def value(self, name: String, default: String) -> String:
        """Return an option's value.

        Args:
            name: The option, such as `--mojo`.
            default: The value when the command line does not give it.

        Returns:
            The given value, or `default`.
        """
        return self.values.get(name).or_else(default)


def _negative_number(word: String) -> Bool:
    """Return whether a word looks like `-5` or `-.5`, which `argparse`
    reads as a value."""
    var bytes = word.as_bytes()
    if len(bytes) < 2 or bytes[0] != 45:
        return False
    var digits = 0
    var point = False
    for index in range(1, len(bytes)):
        var byte = bytes[index]
        if byte >= 48 and byte <= 57:
            digits += 1
        elif byte == 46 and not point:
            point = True
        else:
            return False
    return digits > 0 and (not point or bytes[len(bytes) - 1] != 46)


def _option_like(word: String) -> Bool:
    """Return whether `argparse` reads a word as an option."""
    return (
        word.startswith("-")
        and word.byte_length() > 1
        and not _negative_number(word)
    )


def parse_command_line(
    arguments: List[String],
    program: String,
    usage: String,
    help: String,
    flags: List[String],
    valued: List[String],
) -> CommandLine:
    """Parse a command line as an `argparse` parser with long options does.

    Args:
        arguments: The arguments, without the program name.
        program: The program name for error messages.
        usage: The usage text, with its final newline.
        help: The text after the usage for `--help`.
        flags: The options that take no value.
        valued: The options that take one value.

    Returns:
        The options. A nonzero status carries the text to print.
    """
    var result = CommandLine()
    var names: List[String] = ["--help"]
    names.extend(flags.copy())
    names.extend(valued.copy())
    var unknown = List[String]()
    var problem = String()
    var index = 0
    var positional = False
    while index < len(arguments) and not problem:
        var word = arguments[index]
        index += 1
        if positional or not _option_like(word):
            unknown.append(word)
            continue
        if word == "--":
            # A parser without positional arguments keeps the `--`.
            positional = True
            unknown.append(word)
            continue
        if word == "-h":
            word = "--help"
        if not word.startswith("--"):
            unknown.append(word)
            continue
        var value = Optional[String]()
        var equals = word.find("=")
        var key = word
        if equals >= 0:
            key = String(word[byte=:equals])
            value = String(word[byte = equals + 1 :])
        var matches = List[String]()
        for name in names:
            if name == key:
                matches = [name]
                break
            if name.startswith(key):
                matches.append(name)
        if len(matches) == 0:
            unknown.append(word)
            continue
        if len(matches) > 1:
            problem = (
                "ambiguous option: "
                + key
                + " could match "
                + ", ".join(matches)
            )
            break
        var name = matches[0]
        var is_flag = name == "--help"
        for flag in flags:
            if flag == name:
                is_flag = True
        if is_flag:
            if value:
                var label = "-h/--help" if name == "--help" else name
                problem = (
                    "argument "
                    + label
                    + ": ignored explicit argument "
                    + py_repr(value.value())
                )
                break
            if name == "--help":
                result.status = -1
                result.message = usage + help
                return result^
            result.flags.add(name)
            continue
        if value:
            result.values[name] = value.value()
            continue
        if index >= len(arguments) or _option_like(arguments[index]):
            problem = "argument " + name + ": expected one argument"
            break
        result.values[name] = arguments[index]
        index += 1
    if not problem and len(unknown) > 0:
        problem = "unrecognized arguments: " + " ".join(unknown)
    if problem:
        result.status = 2
        result.message = usage + program + ": error: " + problem + "\n"
    return result^


def normal_path(path: String) -> String:
    """Return a path without empty and `.` parts, as `pathlib` spells it.

    Args:
        path: A path.

    Returns:
        The path, or `.` for an empty relative path.
    """
    var parts = List[String]()
    for part in path.split("/"):
        var text = String(part)
        if text != "" and text != ".":
            parts.append(text)
    var joined = "/".join(parts)
    if path.startswith("/"):
        return "/" + joined
    return joined if joined.byte_length() > 0 else "."


def absolute_path(path: String) raises -> String:
    """Return a path with its links resolved, as `Path.resolve()` does.

    Each existing prefix has its links resolved. Parts that do not exist
    stay as written, and `..` removes the part before it.

    Args:
        path: A path, absolute or relative to the working directory.

    Returns:
        The absolute, normalized path.

    Raises:
        Error: If the working directory cannot be read.
    """
    var full = path if path.startswith("/") else realpath(".") + "/" + path
    var resolved = String("/")
    var found = True
    for part in full.split("/"):
        var name = String(part)
        if name == "" or name == ".":
            continue
        if name == "..":
            var slash = resolved.rfind("/")
            var parent = String(resolved[byte = : max(slash, 1)])
            resolved = parent
            continue
        var candidate = (
            resolved + name if resolved == "/" else resolved + "/" + name
        )
        if found and exists(candidate):
            resolved = realpath(candidate)
        else:
            found = False
            resolved = candidate
    return resolved^
