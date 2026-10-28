# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md

"""Check sealed coverage capture receipts.

    coverage_captures ENVELOPE CAPTURE ...

`ENVELOPE` is the loop-proof JSON. Each `CAPTURE` is a capture file whose
receipt is `CAPTURE.proof.json`. The program prints nothing when every
receipt matches.
"""

from std.os.path import isfile
from std.pathlib import Path
from std.sys import argv, exit, stderr

from tools._duplicate_pin_keys import reject_duplicate_pin_keys
from tools._python_json import PY_DICT, PY_LIST, PY_STR, PyJson
from tools._sha256 import sha256_hex


def _usage():
    """Print the command usage and stop."""
    print("usage: coverage_captures ENVELOPE CAPTURE ...", file=stderr)
    exit(2)


def _same(left: List[UInt8], right: List[UInt8]) -> Bool:
    """Return whether two byte lists are equal.

    Args:
        left: One list.
        right: The other list.

    Returns:
        True when they match.
    """
    if len(left) != len(right):
        return False
    var index = 0
    while index < len(left):
        if left[index] != right[index]:
            return False
        index += 1
    return True


def _name(path: String) -> String:
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


def _parent(path: String) -> String:
    """Return the directory that contains `path`.

    Args:
        path: A path.

    Returns:
        The parent, or `.` when `path` has no slash.
    """
    var slash = path.rfind("/")
    if slash < 0:
        return "."
    if slash == 0:
        return "/"
    return String(path[byte = 0 : slash])


def _stem(suite: String) -> String:
    """Return the suite stem the way `Path.stem` does.

    Args:
        suite: The staged suite path.

    Returns:
        The file name without its last suffix.
    """
    var name = _name(suite)
    var dot = name.rfind(".")
    if dot <= 0:
        return name
    return String(name[byte = 0 : dot])


def _join(directory: String, name: String) -> String:
    """Join a directory and a file name.

    Args:
        directory: The directory.
        name: The file name.

    Returns:
        The joined path.
    """
    if directory == "/":
        return "/" + name
    if directory.endswith("/"):
        return directory + name
    return directory + "/" + name


def _hash_file(path: String) raises -> String:
    """Return the SHA-256 of one capture file.

    Args:
        path: The file.

    Returns:
        The lowercase hexadecimal digest.

    Raises:
        Error: When the file is missing.
    """
    if not isfile(path):
        raise Error("missing capture file: " + path)
    return sha256_hex(Span(Path(path).read_bytes()))


def _load_receipt(path: String) raises -> PyJson:
    """Read one capture receipt and refuse a repeated key.

    Args:
        path: The receipt path.

    Returns:
        The parsed document. Its root is the receipt object.

    Raises:
        Error: When the file is missing, a key is repeated, or the JSON
            cannot be parsed.
    """
    if not isfile(path):
        raise Error("missing capture receipt: " + path)
    var raw = Path(path).read_bytes()
    try:
        reject_duplicate_pin_keys(Span(raw))
    except error:
        var message = String(error)
        var old = "duplicate runtime source pin key:"
        if message.startswith(old):
            var rest = message[byte = old.byte_length() :]
            raise Error("Duplicate receipt key:" + rest)
        raise error
    var doc = PyJson.parse(String(from_utf8_lossy=raw))
    return doc^


def _string_list(doc: PyJson, node: Int) raises -> List[String]:
    """Return the strings in a JSON list.

    Args:
        doc: The document.
        node: A list node.

    Returns:
        The strings.

    Raises:
        Error: When an item is not a string.
    """
    var words = List[String]()
    if doc.kind(node) != PY_LIST:
        raise Error("Missing coverage capture command identity")
    var index = 0
    while index < doc.length(node):
        var item = doc.item(node, index)
        if doc.kind(item) != PY_STR:
            raise Error("Missing coverage capture command identity")
        words.append(doc.text(item))
        index += 1
    return words^


def _has(words: List[String], text: String) -> Bool:
    """Return whether `words` contains `text`.

    Args:
        words: The words.
        text: The word to find.

    Returns:
        True when one word is equal.
    """
    for word in words:
        if word == text:
            return True
    return False


def _compiler_words(doc: PyJson, execution: Int) raises -> List[String]:
    """Return the sealed compiler words.

    Args:
        doc: The envelope document.
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


def _expected_command(
    doc: PyJson, execution: Int, suite: String, profile: String
) raises -> List[String]:
    """Return the sealed capture command.

    Args:
        doc: The envelope document.
        execution: The execution object.
        suite: The staged suite.
        profile: The capture profile.

    Returns:
        The symbolic command.

    Raises:
        Error: When the suite or profile is outside the contract.
    """
    var suites = _string_list(doc, doc.at(execution, "suites"))
    var profiles = _string_list(doc, doc.at(execution, "profiles"))
    if not _has(suites, suite) or not _has(profiles, profile):
        raise Error("Capture suite/profile is outside the sealed execution contract")
    var compiler = _compiler_words(doc, execution)
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


def _equal_words(left: List[String], right: List[String]) -> Bool:
    """Return whether two word lists are equal.

    Args:
        left: One list.
        right: The other list.

    Returns:
        True when they match in order.
    """
    if len(left) != len(right):
        return False
    var index = 0
    while index < len(left):
        if left[index] != right[index]:
            return False
        index += 1
    return True


def _keys_match(doc: PyJson, node: Int) -> Bool:
    """Return whether `node` has exactly the capture-receipt keys.

    Args:
        doc: The document.
        node: The object.

    Returns:
        True when the key set matches.
    """
    var wanted = List[String]()
    wanted.append("schema")
    wanted.append("proof_sha256")
    wanted.append("capture")
    wanted.append("capture_sha256")
    wanted.append("output")
    wanted.append("output_sha256")
    wanted.append("command")
    wanted.append("suite")
    wanted.append("profile")
    if doc.kind(node) != PY_DICT or doc.length(node) != len(wanted):
        return False
    for key in wanted:
        if doc.find(node, key) < 0:
            return False
    return True


def _check_one(doc: PyJson, envelope_sha: String, capture: String) raises:
    """Check one capture against `doc`.

    Args:
        doc: The loop-proof envelope.
        envelope_sha: The envelope digest.
        capture: The capture path.

    Raises:
        Error: When the receipt or the captured bytes do not match.
    """
    var receipt_path = capture + ".proof.json"
    var receipt = _load_receipt(receipt_path)
    var root = receipt.root
    var capture_name = _name(capture)
    if not _keys_match(receipt, root):
        raise Error("Malformed coverage capture receipt: " + capture_name)
    var command = _string_list(receipt, receipt.at(root, "command"))
    if len(command) == 0:
        raise Error("Missing coverage capture command identity")
    var execution = doc.at(doc.at(doc.root, "receipt"), "execution")
    var suite = receipt.text(receipt.at(root, "suite"))
    var profile = receipt.text(receipt.at(root, "profile"))
    var expected = _expected_command(doc, execution, suite, profile)
    if not _equal_words(command, expected):
        raise Error("Modified capture command provenance")
    var stem = _stem(suite)
    var recorded_capture = receipt.text(receipt.at(root, "capture"))
    var recorded_output = receipt.text(receipt.at(root, "output"))
    if recorded_capture != stem + ".txt.gz" or recorded_output != stem + ".out":
        raise Error("Capture files do not identify the recorded suite")
    if (
        recorded_output == ""
        or recorded_output == "."
        or recorded_output == ".."
        or _name(recorded_output) != recorded_output
    ):
        raise Error("Invalid coverage output identity")
    if (
        receipt.text(receipt.at(root, "schema")) != "constant-loops-v2"
        or receipt.text(receipt.at(root, "proof_sha256")) != envelope_sha
        or recorded_capture != capture_name
        or receipt.text(receipt.at(root, "capture_sha256")) != _hash_file(capture)
        or receipt.text(receipt.at(root, "output_sha256"))
        != _hash_file(_join(_parent(capture), recorded_output))
    ):
        raise Error("Stale or modified coverage capture: " + capture_name)


def verify_captures(envelope_path: String, captures: List[String]) raises:
    """Check every capture receipt against one envelope.

    Args:
        envelope_path: The loop-proof JSON file.
        captures: The capture paths.

    Raises:
        Error: When a receipt or a captured file does not match.
    """
    var doc = PyJson.parse(Path(envelope_path).read_text())
    var digest = doc.text(doc.at(doc.root, "sha256"))
    for capture in captures:
        _check_one(doc, digest, capture)


def main() raises:
    """Check the capture receipts named on the command line.

    Raises:
        Error: The command is invalid, or a receipt does not match.
    """
    var arguments = argv()
    if len(arguments) < 2:
        _usage()
    var captures = List[String]()
    var index = 2
    while index < len(arguments):
        captures.append(String(arguments[index]))
        index += 1
    try:
        verify_captures(String(arguments[1]), captures)
    except error:
        print(String(error), file=stderr)
        exit(1)
