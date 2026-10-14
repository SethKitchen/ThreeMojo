# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Select the files that a change can affect, for `make ... AFFECTED=<ref>`.

    affected --base origin/main [--changed] [--verbose] FILE...
    affected --base origin/main --list

With FILE..., prints the FILEs that the change can affect, in their order.
`tools._imports.affected_set` says which files those are. With `--changed`,
prints the FILEs that changed, which is what formatting needs. With
`--list`, prints every changed path, or `ALL` when everything is affected.
With `--verbose`, the reasons for `ALL` go to standard error.

The change runs from the merge base of `--base` and `HEAD` to the working
tree, with the untracked sources and assets. When git cannot say what
changed, or a changed test removed an import, every FILE is printed.

The tool works on the repository in the current directory. The `Makefile`
runs it through `tools/tool.sh`, which builds it once.
"""

from std.sys import argv, exit, stderr

from tools._imports import (
    Selection,
    affected_set,
    changed_paths,
    sorted_strings,
    test_imports_removed,
)


struct Options(Movable):
    """The parsed command line."""

    var base: String
    """The ref to compare with."""
    var changed: Bool
    """True to print only the FILEs that changed."""
    var list: Bool
    """True to print the change."""
    var verbose: Bool
    """True to explain `ALL` on standard error."""
    var files: List[String]
    """The candidate files."""

    def __init__(out self):
        """Start with no options."""
        self.base = String()
        self.changed = False
        self.list = False
        self.verbose = False
        self.files = List[String]()


def parse_options(arguments: List[String]) raises -> Options:
    """Parse the arguments after the program name.

    Args:
        arguments: The arguments.

    Returns:
        The options.

    Raises:
        Error: For an unknown option or a missing `--base`.
    """
    var options = Options()
    var has_base = False
    var index = 0
    while index < len(arguments):
        var argument = arguments[index]
        if argument == "--base":
            if index + 1 >= len(arguments):
                raise Error("--base needs a ref")
            index += 1
            options.base = arguments[index]
            has_base = True
        elif argument.startswith("--base="):
            options.base = String(argument[byte=7:])
            has_base = True
        elif argument == "--changed":
            options.changed = True
        elif argument == "--list":
            options.list = True
        elif argument == "--verbose":
            options.verbose = True
        elif argument.startswith("-"):
            raise Error("unknown option: " + argument)
        else:
            options.files.append(argument)
        index += 1
    if not has_base:
        raise Error("--base is required")
    return options^


def select(root: String, options: Options) -> Tuple[String, List[String]]:
    """Return what the tool prints, and the reasons for `ALL`.

    Args:
        root: The repository root.
        options: The parsed command line.

    Returns:
        The standard output without its final line end, and the reasons.
    """
    var reasons = List[String]()
    var changed = changed_paths(root, options.base)
    if not changed:
        reasons.append("Git could not establish the changed inputs")
    elif test_imports_removed(root, changed.value(), options.base, reasons):
        changed = None
    var affected = affected_set(
        root, changed.value(), reasons
    ) if changed else Selection.everything()
    if not options.verbose or not affected.all:
        reasons = List[String]()
    if options.list:
        if affected.all:
            return ("ALL", reasons^)
        var paths = List[String]()
        for entry in changed.value().items():
            paths.append(entry.key)
        return ("\n".join(sorted_strings(paths^)), reasons^)
    var selected = List[String]()
    for path in options.files:
        var name = String(path[byte=2:]) if path.startswith("./") else path
        if affected.all:
            selected.append(name)
        elif options.changed:
            if name in changed.value():
                selected.append(name)
        elif name in affected.files:
            selected.append(name)
    return (" ".join(selected), reasons^)


def main() raises:
    var arguments = List[String]()
    var given = argv()
    for index in range(1, len(given)):
        arguments.append(String(given[index]))
    var options: Options
    try:
        options = parse_options(arguments)
    except error:
        print("affected:", error, file=stderr)
        exit(2)
        return
    var result = select(".", options)
    for reason in result[1]:
        print("affected: ALL because " + reason, file=stderr)
    print(result[0])
