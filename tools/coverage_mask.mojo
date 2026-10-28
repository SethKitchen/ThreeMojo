# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md

"""Build the outcome-masked coverage manifest.

    coverage_mask MANIFEST ENVELOPE

`MANIFEST` is the original manifest. `ENVELOPE` is the receipt JSON.
The program writes the masked manifest to standard output. It does not
read the repository.
"""

from std.pathlib import Path
from std.sys import argv, exit, stderr

from tools._python_json import PY_LIST, PyJson
from tools._sha256 import sha256_hex


def _usage():
    """Print the command usage and stop."""
    print("usage: coverage_mask MANIFEST ENVELOPE", file=stderr)
    exit(2)


def _is_space(code: Int) -> Bool:
    """Return whether `code` is ASCII whitespace that Python `split` drops.

    Args:
        code: One Unicode code point.

    Returns:
        True for tab, vertical tab, form feed, carriage return, or space.
    """
    return code == 9 or code == 11 or code == 12 or code == 13 or code == 32


def _fields(line: String) -> List[String]:
    """Split `line` the way Python `str.split` splits ASCII whitespace.

    Args:
        line: One manifest line, without its line break.

    Returns:
        The fields. Empty lines produce an empty list.
    """
    var fields = List[String]()
    var current = String()
    for codepoint in line.codepoints():
        var code = Int(codepoint.to_u32())
        if _is_space(code):
            if current.byte_length() > 0:
                fields.append(current)
                current = String()
        else:
            current += String(codepoint)
    if current.byte_length() > 0:
        fields.append(current)
    return fields^


def _digits(text: String, allow_zero: Bool) -> Bool:
    """Return whether `text` is a decimal count without a sign.

    Args:
        text: The field text.
        allow_zero: True when `0` is a valid count.

    Returns:
        True when the field matches the manifest count rule.
    """
    var data = text.as_bytes()
    if len(data) == 0:
        return False
    if data[0] == 48:
        return allow_zero and len(data) == 1
    for byte in data:
        if byte < 48 or byte > 57:
            return False
    return True


def _source_identity(name: String) -> Bool:
    """Return whether `name` is one relative manifest source.

    Args:
        name: The source field.

    Returns:
        True when the field is unchanged by a POSIX path parse.
    """
    if name.byte_length() == 0 or name.find("\\") >= 0 or name.find(":") >= 0:
        return False
    if name.startswith("/"):
        return False
    if name == ".":
        return True
    for part in name.split("/"):
        var item = String(part)
        if item.byte_length() == 0 or item == "." or item == "..":
            return False
    return True


def _lines(raw: List[UInt8]) -> List[String]:
    """Return the manifest lines without their breaks.

    Args:
        raw: The manifest bytes.

    Returns:
        The lines. A final break does not add an empty line.
    """
    var text = String(from_utf8_lossy=raw)
    text = text.replace("\r\n", "\n").replace("\r", "\n")
    var parts = text.split("\n")
    var lines = List[String]()
    var limit = len(parts)
    var data = text.as_bytes()
    if len(data) > 0 and data[len(data) - 1] == 10 and limit > 0:
        limit -= 1
    var index = 0
    while index < limit:
        lines.append(String(parts[index]))
        index += 1
    return lines^


def _record_key(fields: List[String]) -> String:
    """Return one stable key for a manifest field tuple.

    Args:
        fields: The fields of one line.

    Returns:
        The fields joined by a unit separator.
    """
    var key = String()
    var index = 0
    while index < len(fields):
        if index > 0:
            key += "\x1f"
        key += fields[index]
        index += 1
    return key


def _manifest_records(lines: List[String]) raises:
    """Refuse a malformed, escaped, or repeated manifest line.

    Args:
        lines: The manifest lines.

    Raises:
        Error: A line is malformed, escaped, or repeated.
    """
    var seen = List[String]()
    for line in lines:
        var row = String(line)
        var fields = _fields(row)
        if len(fields) == 0:
            continue
        var kind = fields[0]
        var width = 3
        if kind == "C" or kind == "M":
            width = 4
        if (
            (kind != "L" and kind != "B" and kind != "C" and kind != "M")
            or len(fields) != width
            or not _digits(fields[2], False)
            or (len(fields) == 4 and not _digits(fields[3], True))
        ):
            raise Error("Malformed original coverage manifest: " + row)
        if not _source_identity(fields[1]):
            raise Error("Invalid coverage source identity: " + fields[1])
        var key = _record_key(fields)
        for previous in seen:
            if previous == key:
                raise Error("Duplicate coverage manifest entry: " + row)
        seen.append(key)


def _proof_key(module: String, line: String) -> String:
    """Return the mask key for one module and line.

    Args:
        module: The proof module.
        line: The proof line text.

    Returns:
        The key.
    """
    return module + "\x1f" + line


def coverage_mask(raw: List[UInt8], envelope_text: String) raises -> String:
    """Return the manifest with proved branches masked.

    Args:
        raw: The original manifest bytes.
        envelope_text: The receipt envelope JSON.

    Returns:
        The masked manifest, including its final newline.

    Raises:
        Error: The manifest digest, a line, or a proof does not match.
    """
    var doc = PyJson.parse(envelope_text)
    var receipt = doc.at(doc.root, "receipt")
    if sha256_hex(Span(raw)) != doc.text(doc.at(receipt, "manifest_sha256")):
        raise Error("Loop-proof manifest binding mismatch")
    var lines = _lines(raw)
    _manifest_records(lines)
    var proofs = doc.at(receipt, "proofs")
    if doc.kind(proofs) != PY_LIST:
        raise Error("Loop proof does not identify one original branch")
    var modules = List[String]()
    var numbers = List[String]()
    var required = List[String]()
    var kinds = List[String]()
    var counts = List[String]()
    var index = 0
    while index < doc.length(proofs):
        var proof = doc.item(proofs, index)
        var module = doc.text(doc.at(proof, "module"))
        var number = doc.text(doc.at(proof, "line"))
        var key = _proof_key(module, number)
        var slot = -1
        var seen = 0
        while seen < len(modules):
            if _proof_key(modules[seen], numbers[seen]) == key:
                slot = seen
            seen += 1
        if slot < 0:
            modules.append(module)
            numbers.append(number)
            required.append(doc.text(doc.at(proof, "required")))
            kinds.append(doc.text(doc.at(proof, "kind")))
            counts.append(doc.text(doc.at(proof, "cardinality")))
        else:
            required[slot] = doc.text(doc.at(proof, "required"))
            kinds[slot] = doc.text(doc.at(proof, "kind"))
            counts[slot] = doc.text(doc.at(proof, "cardinality"))
        index += 1
    var digest = doc.text(doc.at(doc.root, "sha256"))
    var text = "P constant-loops-v2 " + digest + "\n"
    var used = List[String]()
    for line in lines:
        var row = String(line)
        var fields = _fields(row)
        if len(fields) > 0 and fields[0] == "B" and len(fields) >= 3:
            var key = _proof_key(fields[1], fields[2])
            var slot = 0
            var found = False
            while slot < len(modules):
                if _proof_key(modules[slot], numbers[slot]) == key:
                    found = True
                    break
                slot += 1
            if found:
                row = (
                    "R "
                    + fields[1]
                    + " "
                    + fields[2]
                    + " "
                    + required[slot]
                    + " "
                    + kinds[slot]
                    + " "
                    + counts[slot]
                )
                var marked = False
                for previous in used:
                    if previous == key:
                        marked = True
                if not marked:
                    used.append(key)
        text += row + "\n"
    if len(used) != len(modules):
        raise Error("Loop proof does not identify one original branch")
    return text


def main() raises:
    """Mask one manifest.

    Raises:
        Error: The command is invalid, or the manifest cannot be masked.
    """
    var arguments = argv()
    if len(arguments) != 3:
        _usage()
    try:
        var masked = coverage_mask(
            Path(arguments[1]).read_bytes(), Path(arguments[2]).read_text()
        )
        print(masked, end="")
    except error:
        print(String(error), file=stderr)
        exit(1)
