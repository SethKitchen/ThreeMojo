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
    _executable,
    _hash_file,
    _inside,
    _join,
    _relative,
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


def _find(words: List[String], text: String) -> Int:
    """Return the index of `text`, or -1.

    Args:
        words: The words.
        text: The word to find.

    Returns:
        The first index, or -1.
    """
    var index = 0
    while index < len(words):
        if words[index] == text:
            return index
        index += 1
    return -1


def _compiler(doc: PyJson, execution: Int) raises -> List[String]:
    """Return the sealed compiler words.

    Args:
        doc: The request document.
        execution: The execution object.

    Returns:
        Each compiler word's path or literal.

    Raises:
        Error: When a compiler word has neither field.
    """
    var words = List[String]()
    var compiler = doc.at(execution, "compiler")
    var index = 0
    while index < doc.length(compiler):
        var item = doc.item(compiler, index)
        var path = doc.find(item, "path")
        if path >= 0:
            words.append(doc.text(path))
        else:
            words.append(doc.text(doc.at(item, "literal")))
        index += 1
    return words^


def _sealed_command(
    doc: PyJson, execution: Int, suite: String, profile: String
) raises -> List[String]:
    """Return the sealed capture command.

    Args:
        doc: The request document.
        execution: The execution object.
        suite: The staged suite.
        profile: The capture profile.

    Returns:
        The symbolic command.

    Raises:
        Error: When the suite or profile is outside the contract.
    """
    var suites = _strings(doc, doc.at(execution, "suites"))
    var profiles = _strings(doc, doc.at(execution, "profiles"))
    if not _contains(suites, suite) or not _contains(profiles, profile):
        raise Error("Capture suite/profile is outside the sealed execution contract")
    var compiler = _compiler(doc, execution)
    var command = List[String]()
    command.append("@ROOT@/tools/tool.sh")
    for word in compiler:
        command.append(word)
    if profile == "raw":
        command.append("native_test_support")
        command.append("run")
    else:
        command.append("coverage_hit_aot")
        command.append("--profile")
        command.append(profile)
    command.append("--root")
    command.append("@BUILD@")
    command.append("--suite")
    command.append("@BUILD@/" + suite)
    command.append("--cache")
    command.append(doc.text(doc.at(execution, "cache")))
    command.append("--")
    for word in compiler:
        command.append(word)
    command.append("run")
    command.append("-I")
    command.append("@BUILD@")
    command.append("@BUILD@/" + suite)
    return command^


def _stem(suite: String) -> String:
    """Return the suite stem the way `Path.stem` does.

    Args:
        suite: The staged suite path.

    Returns:
        The file name without its last suffix.
    """
    var slash = suite.rfind("/")
    var name = suite if slash < 0 else String(suite[byte = slash + 1 :])
    var dot = name.rfind(".")
    if dot <= 0:
        return name
    return String(name[byte = 0 : dot])


def _suite(command: List[String], root: String, build: String) raises -> String:
    """Return the staged suite named by `--suite`.

    Args:
        command: The actual command.
        root: The resolved repository root.
        build: The resolved build directory.

    Returns:
        The suite path relative to `build`.

    Raises:
        Error: When the command does not name a staged suite.
    """
    var slot = _find(command, "--suite")
    if slot < 0 or slot + 1 >= len(command):
        raise Error("Capture command does not identify a staged suite")
    var source = command[slot + 1]
    var joined = source if source.startswith("/") else _join(root, source)
    var resolved = _resolve(joined)
    if not _inside(resolved, build):
        raise Error("Capture command does not identify a staged suite")
    return _relative(resolved, build)


def validate_capture_command(
    request_text: String, root: String, build: String
) raises -> String:
    """Return the checked capture command.

    Args:
        request_text: JSON with `execution`, `command`, and optional paths.
        root: The repository root.
        build: The build directory.

    Returns:
        JSON with `suite`, `profile`, and `command`.

    Raises:
        Error: When the command does not match the sealed contract.
    """
    var request = PyJson.parse(request_text)
    var root_real = _resolve(root)
    var build_real = _resolve(build)
    var command = _strings(request, request.at(request.root, "command"))
    if len(command) == 0:
        raise Error("Coverage capture command identity is required")
    var suite = _suite(command, root_real, build_real)
    var profile = String("raw")
    var profile_at = _find(command, "--profile")
    if profile_at >= 0:
        if profile_at + 1 >= len(command):
            raise Error("Missing capture execution profile")
        profile = command[profile_at + 1]
    var execution = request.at(request.root, "execution")
    var expected = _sealed_command(request, execution, suite, profile)
    if len(command) != len(expected):
        raise Error("Capture command differs from its sealed execution contract")
    var index = 0
    while index < len(command):
        var wanted = expected[index]
        var actual = command[index]
        var normalized = actual
        var path_word = (
            wanted.startswith("@ROOT@")
            or wanted.startswith("@BUILD@")
            or wanted.startswith("/")
        )
        if index == 0:
            normalized = _symbolic(_executable(actual, root_real), root_real, build_real)
        elif path_word:
            var joined = actual if actual.startswith("/") else _join(root_real, actual)
            normalized = _symbolic(joined, root_real, build_real)
        if normalized != wanted:
            raise Error("Capture command differs from its sealed execution contract")
        index += 1
    if getenv("CC", "cc") != request.text(request.at(execution, "cc")):
        raise Error("Capture native-compiler setting differs from its sealed contract")
    var stem = _stem(suite)
    var capture = request.find(request.root, "capture")
    if capture >= 0 and _name_of(request.text(capture)) != stem + ".txt.gz":
        raise Error("Capture filename does not identify its sealed suite")
    var output = request.find(request.root, "output")
    if output >= 0 and _name_of(request.text(output)) != stem + ".out":
        raise Error("Capture stdout filename does not identify its sealed suite")
    var doc = PyJson()
    var node = doc.new_dict()
    doc.root = node
    doc.set(node, "suite", doc.new_str(suite))
    doc.set(node, "profile", doc.new_str(profile))
    var words = doc.new_list()
    for word in expected:
        doc.append(words, doc.new_str(word))
    doc.set(node, "command", words)
    return dumps_canonical(doc, node)


def _name_of(path: String) -> String:
    """Return the last path segment.

    Args:
        path: A path.

    Returns:
        The file name.
    """
    var slash = path.rfind("/")
    if slash < 0:
        return path
    return String(path[byte = slash + 1 :])


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
    """Print one execution contract or one checked capture command.

    Raises:
        Error: The command is invalid, or the check fails.
    """
    var arguments = List[String]()
    var given = argv()
    for index in range(1, len(given)):
        arguments.append(String(given[index]))
    var validating = False
    var start = 0
    if len(arguments) > 0 and arguments[0] == "validate":
        validating = True
        start = 1
    var root = String()
    var build = String()
    var request = String()
    var saw_root = False
    var saw_build = False
    var saw_request = False
    var index = start
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
        var text = Path(request).read_text()
        if validating:
            print(validate_capture_command(text, root, build), end="")
        else:
            print(execution_contract(text, root, build), end="")
    except error:
        print(String(error), file=stderr)
        exit(1)
