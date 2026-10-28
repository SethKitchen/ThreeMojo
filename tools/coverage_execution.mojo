# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md

"""Build one coverage execution contract.

    coverage_execution --root DIR --build DIR --request FILE

`FILE` is JSON with `inputs`, `mojo`, and `python`. `suites` and `cache`
are optional. The program prints the canonical contract.
"""

from std.os import getenv
from std.pathlib import Path
from std.sys import argv, exit, stderr

from tools._imports import sorted_strings
from tools._python_json import PyJson, dumps_canonical
from tools.coverage_loop_begin import (
    _command,
    _command_words,
    _hash_file,
    _join,
    _resolve,
    _shlex,
    _symbolic,
)


def _usage():
    """Print the command usage and stop."""
    print(
        "usage: coverage_execution --root DIR --build DIR --request FILE",
        file=stderr,
    )
    exit(2)


def _strings(doc: PyJson, node: Int) raises -> List[String]:
    """Return the strings in a JSON list.

    Args:
        doc: The request document.
        node: A list.

    Returns:
        The strings.

    Raises:
        Error: When an item is not text.
    """
    var words = List[String]()
    var index = 0
    while index < doc.length(node):
        words.append(doc.text(doc.item(node, index)))
        index += 1
    return words^


def _contains(words: List[String], name: String) -> Bool:
    """Return whether `words` contains `name`.

    Args:
        words: The names.
        name: The name to find.

    Returns:
        True when one name is equal.
    """
    for word in words:
        if word == name:
            return True
    return False


def execution_contract(request_text: String, root: String, build: String) raises -> String:
    """Return the canonical execution contract.

    Args:
        request_text: JSON with the staged names and the compiler command.
        root: The repository root.
        build: The build directory.

    Returns:
        The canonical JSON contract.

    Raises:
        Error: When a suite is not staged, or a compiler is missing.
    """
    var request = PyJson.parse(request_text)
    var root_real = _resolve(root)
    var build_real = _resolve(build)
    var inputs = _strings(request, request.at(request.root, "inputs"))
    var selected = List[String]()
    var suites = request.find(request.root, "suites")
    if suites >= 0:
        selected = _strings(request, suites)
    else:
        for name in inputs:
            if name.startswith("tests/test_") and name.endswith(".mojo"):
                selected.append(name)
        selected = sorted_strings(selected^)
    var index = 0
    while index < len(selected):
        var other = index + 1
        while other < len(selected):
            if selected[index] == selected[other]:
                raise Error("Capture suite inventory is invalid or not staged")
            other += 1
        if not _contains(inputs, selected[index]):
            raise Error("Capture suite inventory is invalid or not staged")
        index += 1
    var doc = PyJson()
    var node = doc.new_dict()
    doc.root = node
    doc.set(node, "schema", doc.new_str("coverage-execution-v1"))
    var python = request.text(request.at(request.root, "python"))
    var resolved = _resolve(python)
    var interpreter = doc.new_dict()
    doc.set(interpreter, "path", doc.new_str(_symbolic(resolved, root_real, build_real)))
    doc.set(interpreter, "sha256", doc.new_str(_hash_file(resolved)))
    doc.set(node, "python", interpreter)
    var mojo = request.text(request.at(request.root, "mojo"))
    doc.set(node, "compiler", _command_words(doc, _shlex(mojo), root_real, build_real))
    var cache_node = request.find(request.root, "cache")
    var cache = _join(root_real, ".cache/native-coverage")
    if cache_node >= 0 and request.text(cache_node).startswith("/"):
        cache = request.text(cache_node)
    elif cache_node >= 0:
        cache = _join(root_real, request.text(cache_node))
    doc.set(node, "cache", doc.new_str(_symbolic(_resolve(cache), root_real, build_real)))
    var suite_list = doc.new_list()
    for suite in selected:
        doc.append(suite_list, doc.new_str(suite))
    doc.set(node, "suites", suite_list)
    var cc = getenv("CC", "cc")
    doc.set(node, "cc", doc.new_str(cc))
    doc.set(node, "native_compiler", _command(doc, cc, root_real, build_real))
    var profiles = doc.new_list()
    doc.append(profiles, doc.new_str("raw"))
    doc.append(profiles, doc.new_str("aot"))
    doc.append(profiles, doc.new_str("aot-hits"))
    doc.set(node, "profiles", profiles)
    var flags = doc.new_list()
    doc.append(flags, doc.new_str("run"))
    doc.append(flags, doc.new_str("-I"))
    doc.append(flags, doc.new_str("@BUILD@"))
    doc.append(flags, doc.new_str("@SUITE@"))
    doc.set(node, "capture_flags", flags)
    return dumps_canonical(doc, node)


def _value(arguments: List[String], index: Int) raises -> String:
    """Return the argument after a flag.

    Args:
        arguments: The command arguments.
        index: The flag position.

    Returns:
        The following argument.

    Raises:
        Error: When the flag is last.
    """
    if index + 1 >= len(arguments):
        raise Error("usage: coverage_execution --root DIR --build DIR --request FILE")
    return arguments[index + 1]


def main() raises:
    """Print one execution contract.

    Raises:
        Error: The command is invalid, or the contract cannot be built.
    """
    var arguments = List[String]()
    var given = argv()
    for index in range(1, len(given)):
        arguments.append(String(given[index]))
    var root = String()
    var build = String()
    var request = String()
    var saw_root = False
    var saw_build = False
    var saw_request = False
    var index = 0
    while index < len(arguments):
        var word = arguments[index]
        if word == "--root":
            root = _value(arguments, index)
            saw_root = True
            index += 2
        elif word == "--build":
            build = _value(arguments, index)
            saw_build = True
            index += 2
        elif word == "--request":
            request = _value(arguments, index)
            saw_request = True
            index += 2
        else:
            _usage()
    if not (saw_root and saw_build and saw_request):
        _usage()
    try:
        print(execution_contract(Path(request).read_text(), root, build), end="")
    except error:
        print(String(error), file=stderr)
        exit(1)
