# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Seal literal loop proofs for one instrumented coverage tree.

    coverage_loop_seal --root DIR --build DIR --compiler TEXT --flags TEXT
        --mojo TEXT [--capture-cache PATH] [--suites FILE ...]

The file `loop-proofs.json` matches `coverage_loop_proofs.py seal` for a
tree whose proofs are literal `range` calls and literal lists. A reviewed
theorem is not sealed here.
"""

from std.os import listdir
from std.os.path import isdir, isfile, islink, realpath
from std.pathlib import Path
from std.sys import argv, exit, stderr

from tools._python_json import PY_DICT, PyJson, dumps_canonical
from tools._sha256 import sha256_hex
from tools.cache_key import input_paths
from tools.coverage_io import _execution_contract, _hash_inputs
from tools.coverage_loop_begin import (
    _checkpoint,
    _hash_file,
    _inside,
    _join,
    _python_version,
    _relative,
    _resolve,
    _shlex,
)

comptime _TOOLS = [
    "coverage/build_cli.mojo",
    "coverage/instrument.mojo",
    "coverage/scanner.mojo",
    "coverage/runtime.mojo",
    "coverage/report.mojo",
    "coverage/report_cli.mojo",
    "coverage/mcdc.mojo",
    "tools/coverage_loop_proofs.py",
    "tools/coverage_io.py",
    "tools/cache_key.py",
    "tools/native_test_support.py",
    "tools/coverage_toolchain_identity.py",
    "tools/coverage_process_group.py",
    "tools/coverage_hit_aot.py",
    "tools/coverage_hit_cache.c",
    "tools/coverage_write_interposer.c",
    "tools/test_environment.py",
    "tools/run_suite.py",
    "Makefile",
]
"""The tool files a receipt must bind."""


struct _Tok(Copyable, Movable):
    var kind: String
    var text: String
    var line: Int
    var column: Int

    def __init__(out self, kind: String, text: String, line: Int, column: Int):
        self.kind = kind
        self.text = text
        self.line = line
        self.column = column


def _usage() -> String:
    """Return the usage line.

    Returns:
        The usage line.
    """
    return (
        "usage: coverage_loop_seal --root DIR --build DIR --compiler TEXT "
        + "--flags TEXT --mojo TEXT [--capture-cache PATH] [--suites FILE ...]"
    )


def _digits(text: String) -> Bool:
    """Return whether `text` is `0` or a decimal integer without a sign.

    Args:
        text: The token text.

    Returns:
        True when every byte is a digit and the text is not empty.
    """
    if text.byte_length() == 0:
        return False
    var data = text.as_bytes()
    if data[0] == 48 and len(data) > 1:
        return False
    for byte in data:
        if byte < 48 or byte > 57:
            return False
    return True


def _number(text: String) -> Int:
    """Return the integer in `text`.

    Args:
        text: Decimal digits.

    Returns:
        The value.
    """
    var value = 0
    for byte in text.as_bytes():
        value = value * 10 + Int(byte) - 48
    return value


def _tokenize(source: String) -> List[_Tok]:
    """Tokenize `source` the way Python's tokenizer does for this subset.

    Args:
        source: Mojo source with newlines normalized.

    Returns:
        The tokens. An empty list means the text is not in the subset.
    """
    var text = source
    if not text.endswith("\n"):
        text += "\n"
    var data = text.as_bytes()
    var tokens = List[_Tok]()
    var indents = List[Int]()
    indents.append(0)
    var index = 0
    var line = 1
    var depth = 0
    var failed = False
    while index < len(data):
        var column = 0
        var start = index
        while index < len(data) and (data[index] == 32 or data[index] == 9):
            if data[index] == 9:
                column = column - column % 8 + 8
            else:
                column += 1
            index += 1
        var blank = index >= len(data) or data[index] == 10 or data[index] == 35
        if depth == 0 and not blank:
            if column > indents[len(indents) - 1]:
                tokens.append(_Tok("INDENT", "", line, column))
                indents.append(column)
            else:
                while column < indents[len(indents) - 1]:
                    _ = indents.pop()
                    tokens.append(_Tok("DEDENT", "", line, column))
                if column != indents[len(indents) - 1]:
                    return List[_Tok]()
        while index < len(data) and data[index] != 10:
            var byte = data[index]
            if byte == 32 or byte == 9:
                index += 1
                continue
            if byte == 35:
                while index < len(data) and data[index] != 10:
                    index += 1
                tokens.append(_Tok("COMMENT", "", line, 0))
                break
            if byte == 34 or byte == 39:
                var quote = byte
                var mark = index
                index += 1
                var triple = (
                    index + 1 < len(data)
                    and data[index] == quote
                    and data[index + 1] == quote
                )
                if triple:
                    index += 2
                while index < len(data):
                    if data[index] == 92 and not triple:
                        index += 2
                        continue
                    if (
                        triple
                        and index + 2 < len(data)
                        and data[index] == quote
                        and data[index + 1] == quote
                        and data[index + 2] == quote
                    ):
                        index += 3
                        break
                    if not triple and data[index] == quote:
                        index += 1
                        break
                    if data[index] == 10 and not triple:
                        return List[_Tok]()
                    index += 1
                var literal = String(text[byte=mark:index])
                tokens.append(_Tok("STRING", literal, line, 0))
                continue
            if (
                (byte >= 65 and byte <= 90)
                or (byte >= 97 and byte <= 122)
                or byte == 95
            ):
                var mark = index
                index += 1
                while index < len(data):
                    var next = data[index]
                    var name = (
                        (next >= 65 and next <= 90)
                        or (next >= 97 and next <= 122)
                        or (next >= 48 and next <= 57)
                        or next == 95
                    )
                    if not name:
                        break
                    index += 1
                tokens.append(
                    _Tok("NAME", String(text[byte=mark:index]), line, column)
                )
                continue
            if byte >= 48 and byte <= 57:
                var mark = index
                index += 1
                while (
                    index < len(data)
                    and data[index] >= 48
                    and data[index] <= 57
                ):
                    index += 1
                tokens.append(
                    _Tok("NUMBER", String(text[byte=mark:index]), line, 0)
                )
                continue
            var two = String()
            if index + 1 < len(data):
                two = String(text[byte = index : index + 2])
            if (
                two == "=="
                or two == "!="
                or two == "<="
                or two == ">="
                or two == "**"
                or two == "//"
                or two == "->"
                or two == "+="
                or two == "-="
            ):
                tokens.append(_Tok("OP", two, line, 0))
                index += 2
                continue
            if byte == 40 or byte == 91 or byte == 123:
                depth += 1
            elif byte == 41 or byte == 93 or byte == 125:
                depth -= 1
                if depth < 0:
                    return List[_Tok]()
            tokens.append(_Tok("OP", String(chr(Int(byte))), line, 0))
            index += 1
        if index < len(data) and data[index] == 10:
            index += 1
            if depth == 0 and not blank:
                tokens.append(_Tok("NEWLINE", "", line, 0))
            else:
                tokens.append(_Tok("NL", "", line, 0))
            line += 1
        _ = start
        _ = failed
    while len(indents) > 1:
        _ = indents.pop()
        tokens.append(_Tok("DEDENT", "", line, 0))
    tokens.append(_Tok("ENDMARKER", "", line, 0))
    return tokens^


def _statements(source: String) -> List[List[_Tok]]:
    """Return the logical statements, or an empty list when recognition fails.

    Args:
        source: Mojo source.

    Returns:
        The statements. Empty means no proofs can be made.
    """
    var normalized = source.replace("\r\n", "\n").replace("\r", "\n")
    var tokens = _tokenize(normalized)
    if len(tokens) == 0:
        return List[List[_Tok]]()
    var statements = List[List[_Tok]]()
    var current = List[_Tok]()
    for token in tokens:
        if (
            token.kind == "INDENT"
            or token.kind == "DEDENT"
            or token.kind == "COMMENT"
            or token.kind == "NL"
            or token.kind == "ENDMARKER"
        ):
            continue
        if token.kind == "NEWLINE":
            if len(current) > 0:
                statements.append(current^)
                current = List[_Tok]()
        else:
            current.append(token.copy())
    if len(current) > 0:
        return List[List[_Tok]]()
    return statements^


def _words(statement: List[_Tok]) -> List[String]:
    """Return the spellings of one statement.

    Args:
        statement: The tokens.

    Returns:
        The spellings.
    """
    var words = List[String]()
    for token in statement:
        words.append(token.text)
    return words^


def _expression(tokens: List[_Tok]) -> String:
    """Return Python's compatibility spelling of `tokens`.

    Args:
        tokens: The expression tokens.

    Returns:
        The text `tokenize.untokenize` writes, with ends stripped.
    """
    var text = String()
    for token in tokens:
        text += token.text
        if token.kind == "NAME" or token.kind == "NUMBER":
            text += " "
    var data = text.as_bytes()
    var start = 0
    var end = len(data)
    while start < end and (data[start] == 32 or data[start] == 10):
        start += 1
    while end > start and (data[end - 1] == 32 or data[end - 1] == 10):
        end -= 1
    return String(text[byte=start:end])


def _list_count(tokens: List[_Tok]) -> Int:
    """Return the element count of a list literal, or -1 when it is not one.

    Args:
        tokens: The loop expression.

    Returns:
        The count, or -1 for a comprehension, a star, or another expression.
    """
    if len(tokens) == 0 or tokens[0].text != "[":
        return -1
    var depth = 0
    var count = 0
    var started = False
    for token in tokens:
        if token.text == "[":
            depth += 1
            if depth == 1:
                continue
        elif token.text == "]":
            depth -= 1
            if depth == 0:
                break
        if depth != 1:
            if token.text == "for":
                return -1
            continue
        if token.text == "for" or token.text == "*":
            return -1
        if token.text == ",":
            started = False
            continue
        if not started:
            count += 1
            started = True
    return count


def _range_count(tokens: List[_Tok]) -> Int:
    """Return the cardinality of `range(stop)` or `range(start, stop)`.

    Args:
        tokens: The call, including `range`.

    Returns:
        The cardinality, or -1 when the call is not two integer literals.
    """
    if (
        len(tokens) < 4
        or tokens[0].text != "range"
        or tokens[1].text != "("
        or tokens[len(tokens) - 1].text != ")"
    ):
        return -1
    var args = List[String]()
    var depth = 0
    var current = String()
    var index = 2
    while index < len(tokens) - 1:
        var token = tokens[index].copy()
        if token.text == "(" or token.text == "[":
            depth += 1
        elif token.text == ")" or token.text == "]":
            depth -= 1
        if depth == 0 and token.text == ",":
            if current.byte_length() == 0 or not _digits(current):
                return -1
            args.append(current)
            current = String()
        elif (
            token.kind == "NUMBER" and depth == 0 and current.byte_length() == 0
        ):
            current = token.text
        elif token.text != "," or depth != 0:
            return -1
        index += 1
    if current.byte_length() > 0:
        if not _digits(current):
            return -1
        args.append(current)
    if len(args) < 1 or len(args) > 2:
        return -1
    var start = 0
    var stop = _number(args[0])
    if len(args) == 2:
        start = stop
        stop = _number(args[1])
    var limit = (1 << 31) - 1
    if start < 0 or stop < 0 or start > limit or stop > limit:
        return -1
    var count = stop - start
    if count < 0:
        return 0
    return count


def constant_loops(source: String) -> List[List[String]]:
    """Return literal loop proofs as records of line, kind, count, and text.

    Args:
        source: One Mojo module.

    Returns:
        One record per proved loop: line, kind, cardinality, required,
        impossible, and expression.
    """
    var found = List[List[String]]()
    var statements = _statements(source)
    if len(statements) == 0 and source.byte_length() > 0:
        var normalized = source.replace("\r\n", "\n").replace("\r", "\n")
        if len(_tokenize(normalized)) == 0:
            return found^
    var names = List[_Tok]()
    for statement in statements:
        for token in statement:
            if token.kind == "NAME":
                names.append(token.copy())
    for statement in statements:
        var saw_import = False
        var saw_star = False
        for token in statement:
            if token.text == "import":
                saw_import = True
            if token.text == "*":
                saw_star = True
        if saw_import and saw_star:
            return List[List[String]]()
    var headers = List[List[_Tok]]()
    var header_lines = List[Int]()
    var allowed_lines = List[Int]()
    var allowed_columns = List[Int]()
    var declarations = List[Int]()
    var kinds = List[String]()
    var generic = List[Bool]()
    for statement in statements:
        var first = statement[0].copy()
        var keep = 0
        var index = 0
        while index < len(declarations):
            if declarations[index] < first.column:
                declarations[keep] = declarations[index]
                kinds[keep] = kinds[index]
                generic[keep] = generic[index]
                keep += 1
            index += 1
        while len(declarations) > keep:
            _ = declarations.pop()
            _ = kinds.pop()
            _ = generic.pop()
        var words = _words(statement)
        var asynchronous = (
            len(words) > 1
            and (words[0] == "async" or words[0] == "__async")
            and words[1] == "def"
        )
        if (
            words[0] == "def"
            or words[0] == "struct"
            or words[0] == "trait"
            or asynchronous
        ):
            var kind = words[0] if not asynchronous else String("def")
            var name_at = 2 if asynchronous else 1
            var is_generic = (
                len(words) > name_at + 1 and words[name_at + 1] == "["
            )
            declarations.append(first.column)
            kinds.append(kind)
            generic.append(is_generic)
            continue
        if (
            len(words) < 5
            or words[0] != "for"
            or statement[1].kind != "NAME"
            or words[2] != "in"
            or words[len(words) - 1] != ":"
        ):
            continue
        var rhs = List[_Tok]()
        var cursor = 3
        while cursor < len(statement) - 1:
            rhs.append(statement[cursor].copy())
            cursor += 1
        if len(rhs) > 1 and rhs[0].text == "range" and rhs[1].text == "(":
            allowed_lines.append(rhs[0].line)
            allowed_columns.append(rhs[0].column)
        var supported = (
            len(declarations) == 1 and kinds[0] == "def" and not generic[0]
        )
        if supported:
            headers.append(rhs^)
            header_lines.append(first.line)
    var range_builtin = True
    for token in names:
        if token.text != "range":
            continue
        var allowed = False
        var index = 0
        while index < len(allowed_lines):
            if (
                token.line == allowed_lines[index]
                and token.column == allowed_columns[index]
            ):
                allowed = True
            index += 1
        if not allowed:
            range_builtin = False
    var list_builtin = True
    for token in names:
        if token.text == "List":
            list_builtin = False
    var index = 0
    while index < len(headers):
        var rhs = headers[index].copy()
        var count = -1
        var kind = String()
        if range_builtin:
            count = _range_count(rhs)
            if count >= 0:
                kind = "literal-range"
        if kind.byte_length() == 0 and list_builtin:
            count = _list_count(rhs)
            if count >= 0:
                kind = "literal-list"
        if kind.byte_length() > 0:
            var record = List[String]()
            record.append(String(header_lines[index]))
            record.append(kind)
            record.append(String(count))
            record.append("T" if count > 0 else "F")
            record.append("F" if count > 0 else "T")
            record.append(_expression(rhs))
            found.append(record^)
        index += 1
    return found^


def _stdlib_clear(root: String) -> Bool:
    """Return whether `root` does not shadow the standard library.

    Args:
        root: A directory.

    Returns:
        True when no `std` file and no directory link is present.
    """
    if not isdir(root):
        return False
    var pending = List[String]()
    pending.append(root)
    while len(pending) > 0:
        var directory = pending.pop()
        var relative = String()
        if directory != root:
            relative = _relative(directory, root)
        var names: List[String]
        try:
            names = listdir(directory)
        except:
            return False
        for name in names:
            var folded = String()
            for byte in name.as_bytes():
                if byte >= 65 and byte <= 90:
                    folded += chr(Int(byte) + 32)
                else:
                    folded += chr(Int(byte))
            if folded == "std" or folded.startswith("std."):
                return False
            var full = directory + "/" + name
            if not isdir(full):
                continue
            var skipped = (
                name == ".git"
                or name == ".venv"
                or name == ".cache"
                or name == "out"
                or name == "node_modules"
                or name == "__pycache__"
                or name == ".agents"
                or name == ".claude"
            )
            var child = (
                relative + "/" + name if relative.byte_length() > 0 else name
            )
            if skipped or child == "coverage/build":
                continue
            if islink(full):
                return False
            pending.append(full)
    return True


def _read_header(data: List[UInt8], mut offset: Int) raises -> List[String]:
    """Read one space-separated header line.

    Args:
        data: The bytes.
        offset: The start. It advances past the newline.

    Returns:
        The fields.

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
    var line = String(from_utf8_lossy=bytes)
    var fields = List[String]()
    for part in line.split(" "):
        fields.append(String(part))
    offset = end + 1
    return fields^


def _length_field(text: String) raises -> Int:
    """Return a decimal byte length.

    Args:
        text: The field.

    Returns:
        The length.

    Raises:
        Error: When the field is not a canonical integer.
    """
    if not _digits(text):
        raise Error("Invalid generation origin byte length")
    return _number(text)


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


def _manifest_records(raw: List[UInt8]) raises -> List[List[String]]:
    """Parse one original coverage manifest.

    Args:
        raw: The manifest bytes.

    Returns:
        The records.

    Raises:
        Error: When a line is malformed or repeated.
    """
    var text = String(from_utf8_lossy=raw)
    var records = List[List[String]]()
    for line in text.split("\n"):
        var row = String(line)
        if row.byte_length() == 0:
            continue
        var fields = List[String]()
        for part in row.split(" "):
            if String(part).byte_length() > 0:
                fields.append(String(part))
        if len(fields) == 0:
            continue
        var kind = fields[0]
        var width = 4 if kind == "C" or kind == "M" else 3
        if (
            (kind != "L" and kind != "B" and kind != "C" and kind != "M")
            or len(fields) != width
            or not _digits(fields[2])
            or _number(fields[2]) < 1
        ):
            raise Error("Malformed original coverage manifest: " + row)
        if len(fields) == 4 and not _digits(fields[3]):
            raise Error("Malformed original coverage manifest: " + row)
        var module = fields[1]
        if (
            module.startswith("/")
            or module.find("..") >= 0
            or module.find("\\") >= 0
            or module.find(":") >= 0
        ):
            raise Error("Invalid coverage source identity: " + module)
        for seen in records:
            if len(seen) == len(fields):
                var same = True
                var index = 0
                while index < len(fields):
                    if seen[index] != fields[index]:
                        same = False
                    index += 1
                if same:
                    raise Error("Duplicate coverage manifest entry: " + row)
        records.append(fields^)
    return records^


def _same_bytes(left: List[UInt8], right: List[UInt8]) -> Bool:
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


def _digest(data: List[UInt8]) -> String:
    """Return the SHA-256 of `data`.

    Args:
        data: The bytes.

    Returns:
        The lowercase hexadecimal digest.
    """
    return sha256_hex(Span(data))


def _generation(
    mut doc: PyJson,
    root: String,
    build: String,
    manifest: List[UInt8],
    compiler: String,
    flags: String,
    mojo: String,
) raises -> Int:
    """Validate generation records and return their receipt object.

    Args:
        doc: The receipt document.
        root: The resolved repository root.
        build: The resolved build directory.
        manifest: The original manifest.
        compiler: The compiler text.
        flags: The flag text.
        mojo: The producer command.

    Returns:
        The generation object.

    Raises:
        Error: With Python's text when the stage does not match its sources.
    """
    var index = Path(_join(build, "origins.ready")).read_bytes()
    var offset = 0
    var header = _read_header(index, offset)
    if len(header) != 4 or header[0] != "COVORIGIN_INDEX2":
        raise Error("Missing or incomplete instrumentation generation")
    var count = _length_field(header[1])
    var size = _length_field(header[2])
    var checkpoint_size = _length_field(header[3])
    if count < 1 or count > len(index):
        raise Error("Invalid generation module count")
    var recorded_manifest = _part(index, offset, size)
    if not _same_bytes(recorded_manifest, manifest):
        raise Error("Generation manifest does not match the original manifest")
    var checkpoint = _part(index, offset, checkpoint_size)
    var names = List[String]()
    var seen = 0
    while seen < count:
        var length = _read_header(index, offset)
        if len(length) != 1:
            raise Error("Invalid generation source identity")
        var raw_name = _part(index, offset, _length_field(length[0]))
        var name = String(from_utf8_lossy=raw_name)
        for other in names:
            if other == name:
                raise Error("Trailing or duplicate generation records")
        names.append(name)
        seen += 1
    if offset != len(index):
        raise Error("Trailing or duplicate generation records")
    var expected = _checkpoint(root, build, compiler, flags, mojo, names) + "\n"
    var recorded = String(from_utf8_lossy=checkpoint)
    var file_text = Path(_join(build, "generation-inputs.json")).read_text()
    if expected != recorded or file_text != recorded:
        raise Error(
            "Stale or modified generation origin checkpoint; regenerate with"
            " current sources/tools/compiler"
        )
    var node = doc.new_dict()
    doc.set(node, "index_sha256", doc.new_str(_digest(index)))
    doc.set(node, "checkpoint_sha256", doc.new_str(_digest(checkpoint)))
    var modules = doc.new_dict()
    var joined = List[UInt8]()
    for name in names:
        if not name.endswith(".mojo"):
            raise Error("Invalid generation module identity")
        var origin = Path(_join(build, name + ".cov-origin")).read_bytes()
        var cursor = 0
        var origin_header = _read_header(origin, cursor)
        if len(origin_header) != 5 or origin_header[0] != "COVORIGIN1":
            raise Error("Malformed source generation origin")
        cursor = 0
        origin_header = _read_header(origin, cursor)
        var part0 = _part(origin, cursor, _length_field(origin_header[1]))
        var part1 = _part(origin, cursor, _length_field(origin_header[2]))
        var part2 = _part(origin, cursor, _length_field(origin_header[3]))
        var part3 = _part(origin, cursor, _length_field(origin_header[4]))
        if cursor != len(origin) or String(from_utf8_lossy=part0) != name:
            raise Error("Trailing or mixed-module generation origin")
        var original = Path(_join(root, name)).read_bytes()
        var generated = Path(_join(build, name)).read_bytes()
        if not _same_bytes(original, part1) or not _same_bytes(
            generated, part2
        ):
            raise Error(
                "Source/staged bytes do not match their generation origin: "
                + name
            )
        var records = _manifest_records(part3)
        var module = String(name[byte = : name.byte_length() - 5])
        for record in records:
            if record[1] != module:
                raise Error("Generation fragment identifies another module")
        for byte in part3:
            joined.append(byte)
        var item = doc.new_dict()
        doc.set(item, "source", doc.new_str(_digest(original)))
        doc.set(item, "instrumented", doc.new_str(_digest(generated)))
        doc.set(item, "origin_sha256", doc.new_str(_digest(origin)))
        doc.set(item, "fragment_sha256", doc.new_str(_digest(part3)))
        doc.set(modules, name, item)
    if not _same_bytes(joined, manifest):
        raise Error(
            "Generation fragments do not reconstruct the original manifest"
        )
    doc.set(node, "modules", modules)
    return node


def _proofs(
    mut doc: PyJson, source: String, module: String, branches: List[Int]
) -> Int:
    """Return the literal proofs for one module.

    Args:
        doc: The receipt document.
        source: The original source.
        module: The manifest module name.
        branches: The branch lines in the manifest.

    Returns:
        A list of proof objects.
    """
    var proofs = doc.new_list()
    for record in constant_loops(source):
        var line = _number(record[0])
        var wanted = False
        for branch in branches:
            if branch == line:
                wanted = True
        if not wanted:
            continue
        var proof = doc.new_dict()
        doc.set(proof, "module", doc.new_str(module))
        doc.set(proof, "line", doc.new_int(line))
        doc.set(proof, "kind", doc.new_str(record[1]))
        doc.set(proof, "cardinality", doc.new_int(_number(record[2])))
        doc.set(proof, "required", doc.new_str(record[3]))
        doc.set(proof, "impossible", doc.new_str(record[4]))
        doc.set(proof, "expression", doc.new_str(record[5]))
        doc.append(proofs, proof)
    return proofs


def _denom(counts: List[Int]) -> String:
    """Return the denominator as Python's default JSON writes it.

    Args:
        counts: L, B, C, M, outcomes, total, impossible, required.

    Returns:
        The JSON text.
    """
    return (
        '{"B": '
        + String(counts[1])
        + ', "C": '
        + String(counts[2])
        + ', "L": '
        + String(counts[0])
        + ', "M": '
        + String(counts[3])
        + ', "potential_outcomes": '
        + String(counts[4])
        + ', "potential_total": '
        + String(counts[5])
        + ', "proven_impossible": '
        + String(counts[6])
        + ', "required_total": '
        + String(counts[7])
        + "}"
    )


def _value(arguments: List[String], index: Int) raises -> String:
    """Return the value after a flag.

    Args:
        arguments: The command arguments.
        index: The flag position.

    Returns:
        The value.

    Raises:
        Error: When the flag is last.
    """
    if index + 1 >= len(arguments):
        raise Error(_usage())
    return arguments[index + 1]


def run_seal(
    root_text: String,
    build_text: String,
    compiler: String,
    flags: String,
    mojo: String,
    cache_text: String,
    suites: List[String],
    saw_suites: Bool,
) raises -> Int:
    """Write `loop-proofs.json` for one staged tree.

    Args:
        root_text: The repository root.
        build_text: The build directory.
        compiler: The compiler text.
        flags: The flag text.
        mojo: The producer command.
        cache_text: The capture cache, or empty for the default.
        suites: The capture suites.
        saw_suites: True when `--suites` was present.

    Returns:
        Zero after the receipt is written.

    Raises:
        Error: When the stage, the sources, or a proof cannot be bound.
    """
    var root = _resolve(root_text)
    var build = _resolve(build_text)
    if not _stdlib_clear(root) or not _stdlib_clear(build):
        raise Error("Plain receipt resolver surface changed")
    var manifest = Path(_join(build, "manifest.txt")).read_bytes()
    var records = _manifest_records(manifest)
    var doc = PyJson()
    var receipt = doc.new_dict()
    doc.root = receipt
    var generation = _generation(
        doc, root, build, manifest, compiler, flags, mojo
    )
    var fresh = PyJson()
    var root_inputs = _hash_inputs(fresh, root, build, False)
    var staged_doc = PyJson()
    var staged = _hash_inputs(staged_doc, build, String(), True)
    var inputs = doc.new_dict()
    var index = 0
    while index < staged_doc.length(staged):
        var name = staged_doc.key(staged, index)
        var digest = staged_doc.text(staged_doc.value(staged, index))
        var source_hash = fresh.find(root_inputs, name)
        if source_hash < 0:
            raise Error("Unmaintained executable input in stage: " + name)
        var item = doc.new_dict()
        doc.set(item, "source", doc.new_str(fresh.text(source_hash)))
        doc.set(item, "instrumented", doc.new_str(digest))
        doc.set(inputs, name, item)
        index += 1
    var modules = doc.at(generation, "modules")
    var module_names = List[String]()
    for record in records:
        var seen = False
        for name in module_names:
            if name == record[1]:
                seen = True
        if not seen:
            module_names.append(record[1])
    # Sort module names.
    var sorted_modules = List[String]()
    for name in module_names:
        sorted_modules.append(name)
    var place = 1
    while place < len(sorted_modules):
        var item = sorted_modules[place]
        var at = place
        while at > 0 and sorted_modules[at - 1] > item:
            sorted_modules[at] = sorted_modules[at - 1]
            at -= 1
        sorted_modules[at] = item
        place += 1
    for module in sorted_modules:
        if doc.find(modules, module + ".mojo") < 0:
            raise Error("Manifest module has no generation origin: " + module)
    var selected = List[String]()
    if saw_suites:
        for suite in suites:
            selected.append(suite)
    else:
        var cursor = 0
        while cursor < doc.length(inputs):
            var name = doc.key(inputs, cursor)
            if name.startswith("tests/test_") and name.endswith(".mojo"):
                selected.append(name)
            cursor += 1
    var words = _shlex(mojo)
    var cache = cache_text if cache_text.startswith("/") else _join(
        root,
        cache_text if cache_text.byte_length()
        > 0 else ".cache/native-coverage",
    )
    var execution = _execution_contract(
        root, build, doc, inputs, words, cache, selected
    )
    var tools = doc.new_dict()
    var executing = _resolve(".")
    for name in materialize[_TOOLS]():
        var recorded = fresh.find(root_inputs, name)
        if recorded < 0:
            raise Error("Stale or modified executing proof tool binding")
        var live = _hash_file(_join(executing, name))
        if fresh.text(recorded) != live:
            if name == "tools/coverage_loop_proofs.py":
                raise Error("Stale or modified executing proof tool binding")
            if name == "tools/cache_key.py":
                raise Error(
                    "Stale or modified executing inventory tool binding"
                )
            if name == "tools/coverage_toolchain_identity.py":
                raise Error(
                    "Stale or modified executing toolchain identity binding"
                )
        doc.set(tools, name, doc.new_str(fresh.text(recorded)))
    var proof_list = doc.new_list()
    var proved = 0
    for module in sorted_modules:
        var branches = List[Int]()
        var compound = List[Int]()
        for record in records:
            if record[1] != module:
                continue
            if record[0] == "B":
                branches.append(_number(record[2]))
            if record[0] == "C" or record[0] == "M":
                compound.append(_number(record[2]))
        var text = Path(_join(root, module + ".mojo")).read_text()
        for record in constant_loops(text):
            var line = _number(record[0])
            var wanted = False
            for branch in branches:
                if branch == line:
                    wanted = True
            if not wanted:
                continue
            for other in compound:
                if other == line:
                    raise Error(
                        "Loop proof conflicts with compound decision: " + module
                    )
            var proof = doc.new_dict()
            doc.set(proof, "module", doc.new_str(module))
            doc.set(proof, "line", doc.new_int(line))
            doc.set(proof, "kind", doc.new_str(record[1]))
            doc.set(proof, "cardinality", doc.new_int(_number(record[2])))
            doc.set(proof, "required", doc.new_str(record[3]))
            doc.set(proof, "impossible", doc.new_str(record[4]))
            doc.set(proof, "expression", doc.new_str(record[5]))
            doc.set(
                proof,
                "source_sha256",
                doc.new_str(
                    fresh.text(fresh.at(root_inputs, module + ".mojo"))
                ),
            )
            doc.append(proof_list, proof)
            proved += 1
    var counts = List[Int]()
    counts.append(0)
    counts.append(0)
    counts.append(0)
    counts.append(0)
    for record in records:
        if record[0] == "L":
            counts[0] += 1
        elif record[0] == "B":
            counts[1] += 1
        elif record[0] == "C":
            counts[2] += 1
        else:
            counts[3] += 1
    var outcomes = 2 * (counts[1] + counts[2])
    var total = counts[0] + outcomes + counts[3]
    counts.append(outcomes)
    counts.append(total)
    counts.append(proved)
    counts.append(total - proved)
    doc.set(receipt, "schema", doc.new_str("constant-loops-v2"))
    doc.set(receipt, "python", doc.new_str(_python_version()))
    doc.set(receipt, "compiler", doc.new_str(compiler))
    doc.set(receipt, "flags", doc.new_str(flags))
    doc.set(receipt, "manifest_sha256", doc.new_str(_digest(manifest)))
    doc.set(receipt, "tools", tools)
    doc.set(receipt, "root_inputs", doc.adopt(fresh, root_inputs))
    doc.set(receipt, "inputs", inputs)
    doc.set(receipt, "generation", generation)
    var parsed = PyJson.parse(execution)
    doc.set(receipt, "execution", doc.adopt(parsed, parsed.root))
    doc.set(receipt, "proofs", proof_list)
    var denominator = doc.new_dict()
    doc.set(denominator, "L", doc.new_int(counts[0]))
    doc.set(denominator, "B", doc.new_int(counts[1]))
    doc.set(denominator, "C", doc.new_int(counts[2]))
    doc.set(denominator, "M", doc.new_int(counts[3]))
    doc.set(denominator, "potential_outcomes", doc.new_int(counts[4]))
    doc.set(denominator, "potential_total", doc.new_int(counts[5]))
    doc.set(denominator, "proven_impossible", doc.new_int(counts[6]))
    doc.set(denominator, "required_total", doc.new_int(counts[7]))
    doc.set(receipt, "denominator", denominator)
    var body = dumps_canonical(doc, receipt)
    var envelope = PyJson()
    var holder = envelope.new_dict()
    envelope.root = holder
    envelope.set(holder, "receipt", envelope.adopt(doc, receipt))
    envelope.set(
        holder, "sha256", envelope.new_str(sha256_hex(body.as_bytes()))
    )
    Path(_join(build, "loop-proofs.json")).write_text(envelope.dumps() + "\n")
    print("Loop proofs:", sha256_hex(body.as_bytes()), _denom(counts))
    return 0


def run_cli(arguments: List[String]) raises -> Int:
    """Seal the tree named on the command line.

    Args:
        arguments: The arguments after the program name.

    Returns:
        Zero after the receipt is written.

    Raises:
        Error: For a bad command line or a receipt that cannot be bound.
    """
    var root = String()
    var build = String()
    var compiler = String()
    var flags = String()
    var mojo = String()
    var cache = String()
    var suites = List[String]()
    var saw_root = False
    var saw_build = False
    var saw_compiler = False
    var saw_flags = False
    var saw_mojo = False
    var saw_suites = False
    var taking = False
    var index = 0
    while index < len(arguments):
        var word = arguments[index]
        if taking and not word.startswith("--"):
            suites.append(word)
            index += 1
            continue
        taking = False
        if word == "--root":
            root = _value(arguments, index)
            saw_root = True
            index += 2
        elif word.startswith("--root="):
            root = String(word[byte=7:])
            saw_root = True
            index += 1
        elif word == "--build":
            build = _value(arguments, index)
            saw_build = True
            index += 2
        elif word.startswith("--build="):
            build = String(word[byte=8:])
            saw_build = True
            index += 1
        elif word == "--compiler":
            compiler = _value(arguments, index)
            saw_compiler = True
            index += 2
        elif word.startswith("--compiler="):
            compiler = String(word[byte=11:])
            saw_compiler = True
            index += 1
        elif word == "--flags":
            flags = _value(arguments, index)
            saw_flags = True
            index += 2
        elif word.startswith("--flags="):
            flags = String(word[byte=8:])
            saw_flags = True
            index += 1
        elif word == "--mojo":
            mojo = _value(arguments, index)
            saw_mojo = True
            index += 2
        elif word.startswith("--mojo="):
            mojo = String(word[byte=7:])
            saw_mojo = True
            index += 1
        elif word == "--capture-cache":
            cache = _value(arguments, index)
            index += 2
        elif word.startswith("--capture-cache="):
            cache = String(word[byte=16:])
            index += 1
        elif word == "--suites":
            saw_suites = True
            taking = True
            index += 1
        elif word == "--help" or word == "-h":
            raise Error(_usage())
        else:
            raise Error(_usage())
    if (
        not saw_root
        or not saw_build
        or not saw_compiler
        or not saw_flags
        or not saw_mojo
    ):
        raise Error(_usage())
    return run_seal(
        root, build, compiler, flags, mojo, cache, suites, saw_suites
    )


def main() raises:
    """Seal literal loop proofs for one coverage tree."""
    var arguments = List[String]()
    var given = argv()
    for index in range(1, len(given)):
        arguments.append(String(given[index]))
    try:
        exit(run_cli(arguments))
    except error:
        print("coverage_loop_seal: " + String(error), file=stderr)
        var text = String(error)
        if text.startswith("usage:"):
            exit(2)
        exit(1)
