# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md

"""Check one coverage generation origin index.

    coverage_origins --root DIR --build DIR --manifest FILE --compiler TEXT
        --flags TEXT --mojo TEXT

The program reads the build's origin index and prints the generation
record. It does not rewrite the checkpoint.
"""

from std.os import listdir
from std.os.path import isdir, isfile, islink
from std.pathlib import Path
from std.sys import argv, exit, stderr

from tools._python_json import PyJson, dumps_canonical, py_repr
from tools._sha256 import sha256_hex
from tools.coverage_loop_begin import (
    _checkpoint,
    _inside,
    _invalid_source,
    _join,
    _resolve,
)


def _usage():
    """Print the command usage and stop."""
    print(
        "usage: coverage_origins --root DIR --build DIR --manifest FILE "
        + "--compiler TEXT --flags TEXT --mojo TEXT",
        file=stderr,
    )
    exit(2)


def _copy_bytes(text: String) -> List[UInt8]:
    """Return the bytes of `text`.

    Args:
        text: The text.

    Returns:
        The bytes.
    """
    var out = List[UInt8]()
    for byte in text.as_bytes():
        out.append(byte)
    return out^


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


def _header(data: List[UInt8], mut offset: Int) raises -> List[String]:
    """Read one space-separated header line.

    Args:
        data: The bytes.
        offset: The start. It advances past the newline.

    Returns:
        The fields, including empty fields between spaces.

    Raises:
        Error: When the line is missing.
    """
    var end = offset
    while end < len(data) and data[end] != 10:
        end += 1
    if end >= len(data):
        raise Error("Truncated generation origin header")
    var bytes = List[UInt8]()
    var cursor = offset
    while cursor < end:
        bytes.append(data[cursor])
        cursor += 1
    var fields = List[String]()
    for part in String(from_utf8_lossy=bytes).split(" "):
        fields.append(String(part))
    offset = end + 1
    return fields^


def _length(text: String) raises -> Int:
    """Return a canonical decimal length.

    Args:
        text: The field.

    Returns:
        The length.

    Raises:
        Error: When the field is not `0` or a number without a leading zero.
    """
    var data = text.as_bytes()
    if len(data) == 0 or (data[0] == 48 and len(data) > 1):
        raise Error("Invalid generation origin byte length")
    for byte in data:
        if byte < 48 or byte > 57:
            raise Error("Invalid generation origin byte length")
    var value = 0
    for byte in data:
        value = value * 10 + Int(byte) - 48
    return value


def _part(data: List[UInt8], mut offset: Int, size: Int) raises -> List[UInt8]:
    """Return the next `size` bytes.

    Args:
        data: The bytes.
        offset: The start. It advances by `size`.
        size: The count.

    Returns:
        The bytes.

    Raises:
        Error: When the payload is short.
    """
    if size > len(data) - offset:
        raise Error("Truncated generation origin payload")
    var out = List[UInt8]()
    var index = 0
    while index < size:
        out.append(data[offset + index])
        index += 1
    offset += size
    return out^


def _require_source(root: String, name: String) raises -> List[UInt8]:
    """Return the bytes of one root-contained source.

    Args:
        root: The resolved directory.
        name: The relative source name.

    Returns:
        The file bytes.

    Raises:
        Error: When the name is not a contained file.
    """
    if _invalid_source(name):
        raise Error("Invalid coverage source identity: " + py_repr(name))
    var full = _join(root, name)
    if not isfile(full) or not _inside(_resolve(full), root):
        raise Error("Missing or escaped coverage source: " + name)
    return Path(full).read_bytes()


def _origin_paths(directory: String, relative: String, mut found: List[String]):
    """Collect paths whose name ends in `.cov-origin`.

    Args:
        directory: The directory to scan.
        relative: The path of `directory` inside the build, or empty.
        found: The matching relative paths.
    """
    var names: List[String]
    try:
        names = listdir(directory)
    except:
        return
    for name in names:
        var child = relative + "/" + name if relative else name
        var full = directory + "/" + name if not directory.endswith("/") else directory + name
        if name.endswith(".cov-origin"):
            found.append(child)
        if isdir(full) and not islink(full):
            _origin_paths(full, child, found)


def _space(code: Int) -> Bool:
    """Return whether `code` is ASCII whitespace that Python `split` drops.

    Args:
        code: One Unicode code point.

    Returns:
        True for tab, vertical tab, form feed, carriage return, or space.
    """
    return code == 9 or code == 11 or code == 12 or code == 13 or code == 32


def _words(line: String) -> List[String]:
    """Split `line` on ASCII whitespace.

    Args:
        line: One manifest line.

    Returns:
        The fields.
    """
    var fields = List[String]()
    var current = String()
    for codepoint in line.codepoints():
        var code = Int(codepoint.to_u32())
        if _space(code):
            if current.byte_length() > 0:
                fields.append(current)
                current = String()
        else:
            current += String(codepoint)
    if current.byte_length() > 0:
        fields.append(current)
    return fields^


def _count_text(text: String, allow_zero: Bool) -> Bool:
    """Return whether `text` is a manifest count.

    Args:
        text: The field.
        allow_zero: True when `0` is valid.

    Returns:
        True when the field matches the count rule.
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


def _manifest_lines(raw: List[UInt8]) -> List[String]:
    """Return manifest lines without their breaks.

    Args:
        raw: The manifest bytes.

    Returns:
        The lines.
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


def _check_manifest(raw: List[UInt8]) raises -> List[String]:
    """Return each record's source field.

    Args:
        raw: The manifest bytes.

    Returns:
        The source field of each record.

    Raises:
        Error: When a line is malformed, escaped, or repeated.
    """
    var sources = List[String]()
    var seen = List[String]()
    for line in _manifest_lines(raw):
        var row = String(line)
        var fields = _words(row)
        if len(fields) == 0:
            continue
        var kind = fields[0]
        var width = 3
        if kind == "C" or kind == "M":
            width = 4
        if (
            (kind != "L" and kind != "B" and kind != "C" and kind != "M")
            or len(fields) != width
            or not _count_text(fields[2], False)
            or (len(fields) == 4 and not _count_text(fields[3], True))
        ):
            raise Error("Malformed original coverage manifest: " + row)
        if _invalid_source(fields[1]):
            raise Error("Invalid coverage source identity: " + fields[1])
        var key = String()
        var index = 0
        while index < len(fields):
            if index > 0:
                key += "\x1f"
            key += fields[index]
            index += 1
        for previous in seen:
            if previous == key:
                raise Error("Duplicate coverage manifest entry: " + row)
        seen.append(key)
        sources.append(fields[1])
    return sources^


def _fragment_matches(raw: List[UInt8], module: String) raises:
    """Refuse a fragment that names another module.

    Args:
        raw: The manifest fragment.
        module: The origin module, without `.mojo`.

    Raises:
        Error: When a record is malformed or names another module.
    """
    for source in _check_manifest(raw):
        if source != module:
            raise Error("Generation fragment identifies another module")


def generation_record(
    root: String,
    build: String,
    manifest: List[UInt8],
    compiler: String,
    flags: String,
    mojo: String,
) raises -> String:
    """Return the generation record for one sealed stage.

    Args:
        root: The repository root.
        build: The build directory.
        manifest: The original manifest bytes.
        compiler: The compiler text.
        flags: The flag text.
        mojo: The producer command text.

    Returns:
        The canonical JSON record.

    Raises:
        Error: When the stage does not match its sources.
    """
    var root_real = _resolve(root)
    var build_real = _resolve(build)
    var index = Path(_join(build_real, "origins.ready")).read_bytes()
    var offset = 0
    var fields = _header(index, offset)
    if len(fields) != 4 or fields[0] != "COVORIGIN_INDEX2":
        raise Error("Missing or incomplete instrumentation generation")
    var count = _length(fields[1])
    var size = _length(fields[2])
    var checkpoint_size = _length(fields[3])
    if count < 1 or count > len(index):
        raise Error("Invalid generation module count")
    var recorded_manifest = _part(index, offset, size)
    if not _same(recorded_manifest, manifest):
        raise Error("Generation manifest does not match the original manifest")
    var checkpoint = _part(index, offset, checkpoint_size)
    var names = List[String]()
    var seen = 0
    while seen < count:
        var length = _header(index, offset)
        if len(length) != 1:
            raise Error("Invalid generation source identity")
        var raw_name = _part(index, offset, _length(length[0]))
        names.append(String(from_utf8_lossy=raw_name))
        seen += 1
    if offset != len(index):
        raise Error("Trailing or duplicate generation records")
    var left = 0
    while left < len(names):
        var right = left + 1
        while right < len(names):
            if names[left] == names[right]:
                raise Error("Trailing or duplicate generation records")
            right += 1
        left += 1
    var expected = _checkpoint(
        root_real, build_real, compiler, flags, mojo, names
    ) + "\n"
    var file_bytes = Path(_join(build_real, "generation-inputs.json")).read_bytes()
    if not _same(_copy_bytes(expected), checkpoint) or not _same(file_bytes, checkpoint):
        raise Error(
            "Stale or modified generation origin checkpoint; regenerate with"
            + " current sources/tools/compiler"
        )
    var expected_paths = List[String]()
    for name in names:
        expected_paths.append(name + ".cov-origin")
    var actual_paths = List[String]()
    _origin_paths(build_real, "", actual_paths)
    if len(actual_paths) != len(expected_paths):
        raise Error("Missing or extra generation origin records; rebuild the stage")
    for wanted in expected_paths:
        var found = False
        for got in actual_paths:
            if got == wanted:
                found = True
        if not found:
            raise Error(
                "Missing or extra generation origin records; rebuild the stage"
            )
    var doc = PyJson()
    var node = doc.new_dict()
    doc.root = node
    doc.set(node, "index_sha256", doc.new_str(sha256_hex(Span(index))))
    doc.set(node, "checkpoint_sha256", doc.new_str(sha256_hex(Span(checkpoint))))
    var modules = doc.new_dict()
    var joined = List[UInt8]()
    for name in names:
        if not name.endswith(".mojo"):
            raise Error("Invalid generation module identity")
        var module = String(name[byte = : name.byte_length() - 5])
        var original = _require_source(root_real, name)
        var generated = _require_source(build_real, name)
        var origin = _require_source(build_real, name + ".cov-origin")
        var cursor = 0
        var origin_header = _header(origin, cursor)
        if len(origin_header) != 5 or origin_header[0] != "COVORIGIN1":
            raise Error("Malformed source generation origin")
        var part0 = _part(origin, cursor, _length(origin_header[1]))
        var part1 = _part(origin, cursor, _length(origin_header[2]))
        var part2 = _part(origin, cursor, _length(origin_header[3]))
        var part3 = _part(origin, cursor, _length(origin_header[4]))
        if cursor != len(origin) or String(from_utf8_lossy=part0) != name:
            raise Error("Trailing or mixed-module generation origin")
        if not _same(original, part1) or not _same(generated, part2):
            raise Error(
                "Source/staged bytes do not match their generation origin: " + name
            )
        _fragment_matches(part3, module)
        for byte in part3:
            joined.append(byte)
        var item = doc.new_dict()
        doc.set(item, "source", doc.new_str(sha256_hex(Span(original))))
        doc.set(item, "instrumented", doc.new_str(sha256_hex(Span(generated))))
        doc.set(item, "origin_sha256", doc.new_str(sha256_hex(Span(origin))))
        doc.set(item, "fragment_sha256", doc.new_str(sha256_hex(Span(part3))))
        doc.set(modules, name, item)
    if not _same(joined, manifest):
        raise Error("Generation fragments do not reconstruct the original manifest")
    doc.set(node, "modules", modules)
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
        raise Error(
            "usage: coverage_origins --root DIR --build DIR --manifest FILE "
            + "--compiler TEXT --flags TEXT --mojo TEXT"
        )
    return arguments[index + 1]


def main() raises:
    """Check one generation origin index.

    Raises:
        Error: The command is invalid, or the stage does not match.
    """
    var arguments = List[String]()
    var given = argv()
    for index in range(1, len(given)):
        arguments.append(String(given[index]))
    var root = String()
    var build = String()
    var manifest = String()
    var compiler = String()
    var flags = String()
    var mojo = String()
    var saw_root = False
    var saw_build = False
    var saw_manifest = False
    var saw_compiler = False
    var saw_flags = False
    var saw_mojo = False
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
        elif word == "--manifest":
            manifest = _value(arguments, index)
            saw_manifest = True
            index += 2
        elif word == "--compiler":
            compiler = _value(arguments, index)
            saw_compiler = True
            index += 2
        elif word == "--flags":
            flags = _value(arguments, index)
            saw_flags = True
            index += 2
        elif word == "--mojo":
            mojo = _value(arguments, index)
            saw_mojo = True
            index += 2
        else:
            _usage()
    if not (
        saw_root
        and saw_build
        and saw_manifest
        and saw_compiler
        and saw_flags
        and saw_mojo
    ):
        _usage()
    try:
        print(
            generation_record(
                root, build, Path(manifest).read_bytes(), compiler, flags, mojo
            ),
            end="",
        )
    except error:
        print(String(error), file=stderr)
        exit(1)
