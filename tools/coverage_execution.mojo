# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md

"""Build one coverage execution contract and check sealed capture inputs.

    coverage_execution --root DIR --build DIR --request FILE
    coverage_execution validate --root DIR --build DIR --request FILE
    coverage_execution inputs --root DIR --build DIR --request FILE

The first form prints the canonical contract. `validate` prints the
checked command. `inputs` checks sealed capture bytes and prints nothing
when they match.
"""

from std.os import getenv, listdir
from std.os.path import exists, isdir, isfile, islink
from std.pathlib import Path
from std.sys import argv, exit, stderr

from tools._imports import sorted_strings
from tools._python_json import PyJson, dumps_canonical, py_repr
from tools.cache_key import input_paths
from tools.coverage_loop_begin import (
    _command,
    _command_words,
    _executable,
    _hash_file,
    _inside,
    _invalid_source,
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


def _safe_shell(byte: Int) -> Bool:
    """Return whether `byte` needs no quotes in `shlex.quote`.

    Args:
        byte: One byte.

    Returns:
        True for ASCII letters, digits, and the safe punctuation.
    """
    if byte >= 48 and byte <= 57:
        return True
    if byte >= 65 and byte <= 90:
        return True
    if byte >= 97 and byte <= 122:
        return True
    return (
        byte == 95
        or byte == 64
        or byte == 37
        or byte == 43
        or byte == 61
        or byte == 58
        or byte == 44
        or byte == 46
        or byte == 47
        or byte == 45
    )


def _quote(text: String) -> String:
    """Return `text` as `shlex.quote` writes it.

    Args:
        text: One command word.

    Returns:
        The quoted word.
    """
    if text.byte_length() == 0:
        return "''"
    var data = text.as_bytes()
    var safe = True
    for index in range(len(data)):
        if not _safe_shell(Int(data[index])):
            safe = False
            break
    if safe:
        return text
    var out = List[UInt8]()
    out.append(39)
    for index in range(len(data)):
        if data[index] == 39:
            out.append(39)
            out.append(34)
            out.append(39)
            out.append(34)
            out.append(39)
        else:
            out.append(data[index])
    out.append(39)
    return String(from_utf8_lossy=out)


def _command_text(words: List[String]) -> String:
    """Join words as `shlex.join` does.

    Args:
        words: The command words.

    Returns:
        The command text.
    """
    var text = String()
    var index = 0
    while index < len(words):
        if index > 0:
            text = text + " "
        text = text + _quote(words[index])
        index += 1
    return text


def _expand(value: String, root: String, build: String) -> String:
    """Replace a `@ROOT@` or `@BUILD@` prefix.

    Args:
        value: A sealed path.
        root: The resolved repository root.
        build: The resolved build directory.

    Returns:
        The path on this machine.
    """
    if value == "@ROOT@":
        return root
    if value == "@BUILD@":
        return build
    if value.startswith("@ROOT@/"):
        return _join(root, String(value[byte=7:]))
    if value.startswith("@BUILD@/"):
        return _join(build, String(value[byte=8:]))
    return value


def _digest(path: String) raises -> String:
    """Return the SHA-256 of one sealed file.

    Args:
        path: The file.

    Returns:
        The lowercase hexadecimal digest.

    Raises:
        Error: `missing input file: PATH` when the file is absent.
    """
    if not exists(path):
        raise Error("missing input file: " + path)
    return _hash_file(path)


def _maintained(root: String, build: String, staged: Bool) raises -> String:
    """Return the canonical maintained-input hashes under `root`.

    Args:
        root: The directory to walk.
        build: The build directory to leave out, or empty.
        staged: True when `root` is the instrumented tree.

    Returns:
        Canonical JSON for the path-to-digest map.

    Raises:
        Error: If a walked file is not a source or cannot be read.
    """
    var doc = PyJson()
    var node = doc.new_dict()
    doc.root = node
    var root_real = _resolve(root)
    var build_real = String()
    if build.byte_length() > 0:
        build_real = _resolve(build)
    for relative in input_paths(root_real):
        if _invalid_source(relative):
            raise Error("Invalid coverage source identity: " + py_repr(relative))
        if staged and (
            relative == "hits"
            or relative.startswith("hits/")
            or relative == "loop-proofs.json"
            or relative == "generation-inputs.json"
        ):
            continue
        var full = _join(root_real, relative)
        if not isfile(full) or not _inside(_resolve(full), root_real):
            raise Error("Missing or escaped coverage source: " + relative)
        if (
            build_real.byte_length() > 0
            and not staged
            and _inside(_resolve(full), build_real)
        ):
            continue
        doc.set(node, relative, doc.new_str(_hash_file(full)))
    return doc.dumps()


def _child(directory: String, name: String) -> String:
    """Join a directory and one entry.

    Args:
        directory: The parent.
        name: The entry name.

    Returns:
        The child path.
    """
    if directory == "/":
        return "/" + name
    return directory + "/" + name


def _origin_names(directory: String, base: String, mut names: List[String]) raises:
    """Collect `.cov-origin` paths under `directory`.

    A symbolic link to a directory is not entered. An unreadable directory
    is skipped.

    Args:
        directory: The directory to read.
        base: The build directory.
        names: The relative paths found so far.

    Raises:
        Error: Never from a directory listing. A later hash can still fail.
    """
    var listed: List[String]
    try:
        listed = listdir(directory)
    except:
        return
    for name in listed:
        var full = _child(directory, name)
        var plain_directory = isdir(full) and not islink(full)
        if plain_directory:
            _origin_names(full, base, names)
        elif name.endswith(".cov-origin"):
            names.append(_relative(full, base))


def _instrumented(doc: PyJson, inputs: Int) raises -> String:
    """Return the canonical instrumented hashes.

    Args:
        doc: The receipt document.
        inputs: The staged-input dict.

    Returns:
        Canonical JSON for the path-to-digest map.

    Raises:
        Error: When an input has no instrumented hash.
    """
    var recorded = PyJson()
    var node = recorded.new_dict()
    recorded.root = node
    var index = 0
    while index < doc.length(inputs):
        var name = doc.key(inputs, index)
        var item = doc.value(inputs, index)
        recorded.set(
            node,
            name,
            recorded.new_str(doc.text(doc.at(item, "instrumented"))),
        )
        index += 1
    return recorded.dumps()


def _compiler_words(
    doc: PyJson, compiler: Int, root: String, build: String
) raises -> List[String]:
    """Return the compiler words with sealed paths expanded.

    Args:
        doc: The receipt document.
        compiler: The compiler list.
        root: The resolved repository root.
        build: The resolved build directory.

    Returns:
        The words to run.

    Raises:
        Error: When a word has neither a path nor a literal.
    """
    var words = List[String]()
    var index = 0
    while index < doc.length(compiler):
        var item = doc.item(compiler, index)
        var path = doc.find(item, "path")
        if path >= 0:
            words.append(_expand(doc.text(path), root, build))
        else:
            words.append(doc.text(doc.at(item, "literal")))
        index += 1
    return words^


def check_capture_inputs(request_text: String, root: String, build: String) raises:
    """Check sealed capture bytes against the current tree.

    Args:
        request_text: JSON with `receipt`, `active`, `python`, and `interpreter`.
        root: The repository root.
        build: The build directory.

    Raises:
        Error: When a sealed input, origin, verifier, or compiler binding changed,
            or a sealed file is missing.
    """
    var request = PyJson.parse(request_text)
    var root_real = _resolve(root)
    var build_real = _resolve(build)
    var receipt = request.at(request.root, "receipt")
    var fresh = _maintained(root_real, build_real, False)
    if fresh != dumps_canonical(request, request.at(receipt, "root_inputs")):
        raise Error("Stale or modified capture input binding")
    var staged = _maintained(build_real, String(), True)
    if staged != _instrumented(request, request.at(receipt, "inputs")):
        raise Error("Stale or modified capture input binding")
    var generation = request.at(receipt, "generation")
    if _digest(_join(build_real, "manifest.txt")) != request.text(
        request.at(receipt, "manifest_sha256")
    ):
        raise Error("Stale or modified capture input binding")
    if _digest(_join(build_real, "origins.ready")) != request.text(
        request.at(generation, "index_sha256")
    ):
        raise Error("Stale or modified capture input binding")
    if _digest(_join(build_real, "generation-inputs.json")) != request.text(
        request.at(generation, "checkpoint_sha256")
    ):
        raise Error("Stale or modified capture input binding")
    var names = List[String]()
    _origin_names(build_real, build_real, names)
    var actual = PyJson()
    var actual_node = actual.new_dict()
    actual.root = actual_node
    for name in names:
        actual.set(
            actual_node, name, actual.new_str(_digest(_join(build_real, name)))
        )
    var expected = PyJson()
    var expected_node = expected.new_dict()
    expected.root = expected_node
    var modules = request.at(generation, "modules")
    var index = 0
    while index < request.length(modules):
        var name = request.key(modules, index)
        var item = request.value(modules, index)
        expected.set(
            expected_node,
            name + ".cov-origin",
            expected.new_str(request.text(request.at(item, "origin_sha256"))),
        )
        index += 1
    if actual.dumps() != expected.dumps():
        raise Error("Stale or modified capture generation origins")
    var tools = request.at(receipt, "root_inputs")
    var active = request.at(request.root, "active")
    for name in [
        "tools/coverage_loop_proofs.py",
        "tools/cache_key.py",
        "tools/coverage_toolchain_identity.py",
    ]:
        if request.text(request.at(tools, name)) != request.text(
            request.at(active, name)
        ):
            raise Error("Stale or modified executing capture verifier")
    var execution = request.at(receipt, "execution")
    var words = _compiler_words(
        request, request.at(execution, "compiler"), root_real, build_real
    )
    var suites = _strings(request, request.at(execution, "suites"))
    var inner = PyJson()
    var inner_root = inner.new_dict()
    inner.root = inner_root
    var input_list = inner.new_list()
    var inputs = request.at(receipt, "inputs")
    index = 0
    while index < request.length(inputs):
        inner.append(input_list, inner.new_str(request.key(inputs, index)))
        index += 1
    inner.set(inner_root, "inputs", input_list)
    inner.set(inner_root, "mojo", inner.new_str(_command_text(words)))
    inner.set(
        inner_root,
        "python",
        inner.new_str(request.text(request.at(request.root, "interpreter"))),
    )
    var suite_list = inner.new_list()
    for suite in suites:
        inner.append(suite_list, inner.new_str(suite))
    inner.set(inner_root, "suites", suite_list)
    inner.set(
        inner_root,
        "cache",
        inner.new_str(
            _expand(request.text(request.at(execution, "cache")), root_real, build_real)
        ),
    )
    var current = execution_contract(inner.dumps(), root_real, build_real)
    if current != dumps_canonical(request, execution) or request.text(
        request.at(receipt, "python")
    ) != request.text(request.at(request.root, "python")):
        raise Error("Stale or modified capture compiler/execution identity")


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
    """Print one execution contract, one checked command, or check sealed inputs.

    Raises:
        Error: The command is invalid, or the check fails.
    """
    var arguments = List[String]()
    var given = argv()
    for index in range(1, len(given)):
        arguments.append(String(given[index]))
    var mode = String("contract")
    var start = 0
    if len(arguments) > 0 and arguments[0] == "validate":
        mode = "validate"
        start = 1
    elif len(arguments) > 0 and arguments[0] == "inputs":
        mode = "inputs"
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
        if mode == "validate":
            print(validate_capture_command(text, root, build), end="")
        elif mode == "inputs":
            check_capture_inputs(text, root, build)
        else:
            print(execution_contract(text, root, build), end="")
    except error:
        print(String(error), file=stderr)
        exit(1)
