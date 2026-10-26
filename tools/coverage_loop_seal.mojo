# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Seal loop proofs for one instrumented coverage tree.

    coverage_loop_seal --root DIR --build DIR --compiler TEXT --flags TEXT
        --mojo TEXT [--capture-cache PATH] [--suites FILE ...]

The file `loop-proofs.json` matches `coverage_loop_proofs.py seal` for
literal ranges, literal lists, and reviewed proofs whose dependency
digests match `tools/coverage_reviewed_loops.json`. `prepare-report`
checks that receipt and writes the masked manifest.
"""

from std.os import listdir
from std.os.path import isdir, isfile, islink, realpath
from std.pathlib import Path
from std.sys import argv, exit, stderr

from tools._python_json import (
    MISSING,
    PY_DICT,
    PY_LIST,
    PY_STR,
    PyJson,
    dumps_canonical,
)
from tools._sha256 import sha256_hex
from tools.cache_key import input_paths
from tools.coverage_io import (
    _base_name,
    _execution_contract,
    _expected_command,
    _hash_inputs,
    _read_receipt,
    _reject_duplicate_keys,
    _stem_name,
)
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
        var at = column
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
                if byte == 9:
                    at = at - at % 8 + 8
                else:
                    at += 1
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
                var start_line = line
                var start_col = at
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
                    if data[index] == 10:
                        if not triple:
                            return List[_Tok]()
                        line += 1
                    index += 1
                var literal = String(text[byte=mark:index])
                tokens.append(_Tok("STRING", literal, start_line, start_col))
                at = start_col + literal.byte_length()
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
                var name = String(text[byte=mark:index])
                tokens.append(_Tok("NAME", name, line, at))
                at += name.byte_length()
                continue
            var number_start = (byte >= 48 and byte <= 57) or (
                byte == 46
                and index + 1 < len(data)
                and data[index + 1] >= 48
                and data[index + 1] <= 57
            )
            if number_start:
                var mark = index
                if byte != 46:
                    while (
                        index < len(data)
                        and data[index] >= 48
                        and data[index] <= 57
                    ):
                        index += 1
                if (
                    index < len(data)
                    and data[index] == 46
                    and index + 1 < len(data)
                    and data[index + 1] >= 48
                    and data[index + 1] <= 57
                ):
                    index += 1
                    while (
                        index < len(data)
                        and data[index] >= 48
                        and data[index] <= 57
                    ):
                        index += 1
                if index < len(data) and (
                    data[index] == 101 or data[index] == 69
                ):
                    var exponent = index + 1
                    if exponent < len(data) and (
                        data[exponent] == 43 or data[exponent] == 45
                    ):
                        exponent += 1
                    if (
                        exponent < len(data)
                        and data[exponent] >= 48
                        and data[exponent] <= 57
                    ):
                        index = exponent
                        while (
                            index < len(data)
                            and data[index] >= 48
                            and data[index] <= 57
                        ):
                            index += 1
                var number = String(text[byte=mark:index])
                tokens.append(_Tok("NUMBER", number, line, at))
                at += number.byte_length()
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
                tokens.append(_Tok("OP", two, line, at))
                at += 2
                index += 2
                continue
            if byte == 40 or byte == 91 or byte == 123:
                depth += 1
            elif byte == 41 or byte == 93 or byte == 125:
                depth -= 1
                if depth < 0:
                    return List[_Tok]()
            tokens.append(_Tok("OP", String(chr(Int(byte))), line, at))
            at += 1
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
    var brackets = 0
    var parens = 0
    var count = 0
    var started = False
    for token in tokens:
        if token.text == "[":
            brackets += 1
            if brackets == 1 and parens == 0:
                continue
        elif token.text == "]":
            brackets -= 1
            if brackets == 0 and parens == 0:
                break
        elif token.text == "(":
            parens += 1
        elif token.text == ")":
            parens -= 1
        if brackets != 1 or parens != 0:
            if token.text == "for" and parens == 0:
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


def _has_line(lines: List[Int], line: Int) -> Bool:
    """Return whether `lines` contains `line`.

    Args:
        lines: The line numbers.
        line: The line to find.

    Returns:
        True when `line` is present.
    """
    for item in lines:
        if item == line:
            return True
    return False


def _load_reviews() raises -> PyJson:
    """Return the reviewed loop table from the executing repository.

    Returns:
        The table.

    Raises:
        Error: When the table is missing or is not JSON.
    """
    var path = _join(_resolve("."), "tools/coverage_reviewed_loops.json")
    if not isfile(path):
        raise Error("Missing reviewed loop table")
    return PyJson.parse(Path(path).read_text())


def _dep_key(table: PyJson, deps: Int) -> String:
    """Return a stable key for one dependency map.

    Args:
        table: The reviewed table.
        deps: The dependency object.

    Returns:
        The path and digest pairs.
    """
    var key = String()
    var index = 0
    while index < table.length(deps):
        key += table.key(deps, index)
        key += "="
        key += table.text(table.value(deps, index))
        key += "\n"
        index += 1
    return key^


def _deps_match(table: PyJson, root: String, deps: Int) raises -> Bool:
    """Return whether every dependency file has its reviewed digest.

    Args:
        table: The reviewed table.
        root: The source root.
        deps: The dependency object.

    Returns:
        True when every file is present and its digest matches.

    Raises:
        Error: When a present file cannot be read.
    """
    var index = 0
    while index < table.length(deps):
        var full = _join(root, table.key(deps, index))
        if not isfile(full):
            return False
        if _hash_file(full) != table.text(table.value(deps, index)):
            return False
        index += 1
    return True


def _reviewed_nodes(
    table: PyJson, root: String, module: String
) raises -> List[Int]:
    """Return reviewed proofs whose dependency digests match.

    Args:
        table: The reviewed table.
        root: The source root.
        module: The manifest module name.

    Returns:
        Matching proof nodes in the table. Empty when none match.

    Raises:
        Error: When a dependency file cannot be read.
    """
    var found = table.find(table.root, module)
    var matched = List[Int]()
    if found < 0:
        return matched^
    var keys = List[String]()
    var ready = List[Bool]()
    var index = 0
    while index < table.length(found):
        var proof = table.item(found, index)
        var deps = table.at(proof, "dependency_sha256")
        var key = _dep_key(table, deps)
        var seen = -1
        var cursor = 0
        while cursor < len(keys):
            if keys[cursor] == key:
                seen = cursor
            cursor += 1
        if seen >= 0:
            if ready[seen]:
                matched.append(proof)
        else:
            var matches = _deps_match(table, root, deps)
            keys.append(key)
            ready.append(matches)
            if matches:
                matched.append(proof)
        index += 1
    return matched^


def _insert_pick(
    mut lines: List[Int],
    mut kinds: List[Int],
    mut indexes: List[Int],
    line: Int,
    kind: Int,
    index: Int,
):
    """Insert one proof pick in ascending line order.

    Args:
        lines: The line numbers, in order.
        kinds: Zero for a literal proof and one for a reviewed proof.
        indexes: The source index of each pick.
        line: The new line.
        kind: The new kind.
        index: The new source index.
    """
    var place = len(lines)
    lines.append(line)
    kinds.append(kind)
    indexes.append(index)
    while place > 0 and lines[place - 1] > line:
        lines[place] = lines[place - 1]
        kinds[place] = kinds[place - 1]
        indexes[place] = indexes[place - 1]
        place -= 1
    lines[place] = line
    kinds[place] = kind
    indexes[place] = index


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
    publish: Bool,
) raises -> String:
    """Build the loop receipt for one staged tree.

    Args:
        root_text: The repository root.
        build_text: The build directory.
        compiler: The compiler text.
        flags: The flag text.
        mojo: The producer command.
        cache_text: The capture cache, or empty for the default.
        suites: The capture suites.
        saw_suites: True when `--suites` was present.
        publish: True to write `loop-proofs.json` and print the digest.

    Returns:
        The canonical receipt text.

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
    var modules = doc.at(generation, "modules")
    var index = 0
    while index < staged_doc.length(staged):
        var name = staged_doc.key(staged, index)
        var digest = staged_doc.text(staged_doc.value(staged, index))
        var source_hash = fresh.find(root_inputs, name)
        if source_hash < 0:
            raise Error("Unmaintained executable input in stage: " + name)
        var expected = fresh.text(source_hash)
        var generated = doc.find(modules, name)
        if generated >= 0:
            expected = doc.text(doc.at(generated, "instrumented"))
        if digest != expected:
            raise Error(
                "Staged input differs from generation or passthrough source: "
                + name
            )
        var item = doc.new_dict()
        doc.set(item, "source", doc.new_str(fresh.text(source_hash)))
        doc.set(item, "instrumented", doc.new_str(digest))
        doc.set(inputs, name, item)
        index += 1
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
    var reviews = _load_reviews()
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
        var literals = constant_loops(text)
        var reviewed = _reviewed_nodes(reviews, root, module)
        var pick_lines = List[Int]()
        var pick_kinds = List[Int]()
        var pick_indexes = List[Int]()
        var literal_index = 0
        while literal_index < len(literals):
            _insert_pick(
                pick_lines,
                pick_kinds,
                pick_indexes,
                _number(literals[literal_index][0]),
                0,
                literal_index,
            )
            literal_index += 1
        var review_index = 0
        while review_index < len(reviewed):
            var line = _number(
                reviews.text(reviews.at(reviewed[review_index], "line"))
            )
            if _has_line(pick_lines, line):
                raise Error("Conflicting reviewed loop proof: " + module)
            _insert_pick(
                pick_lines,
                pick_kinds,
                pick_indexes,
                line,
                1,
                review_index,
            )
            review_index += 1
        var source_hash = fresh.text(fresh.at(root_inputs, module + ".mojo"))
        var pick = 0
        while pick < len(pick_lines):
            var line = pick_lines[pick]
            if not _has_line(branches, line):
                pick += 1
                continue
            if _has_line(compound, line):
                raise Error(
                    "Loop proof conflicts with compound decision: " + module
                )
            var proof = doc.new_dict()
            doc.set(proof, "module", doc.new_str(module))
            doc.set(proof, "line", doc.new_int(line))
            if pick_kinds[pick] == 0:
                var record = literals[pick_indexes[pick]].copy()
                doc.set(proof, "kind", doc.new_str(record[1]))
                doc.set(proof, "cardinality", doc.new_int(_number(record[2])))
                doc.set(proof, "required", doc.new_str(record[3]))
                doc.set(proof, "impossible", doc.new_str(record[4]))
                doc.set(proof, "expression", doc.new_str(record[5]))
            else:
                var node = reviewed[pick_indexes[pick]]
                doc.set(
                    proof,
                    "kind",
                    doc.new_str(reviews.text(reviews.at(node, "kind"))),
                )
                doc.set(
                    proof,
                    "cardinality",
                    doc.new_int(
                        _number(reviews.text(reviews.at(node, "cardinality")))
                    ),
                )
                var maximum = reviews.at(node, "maximum_cardinality")
                if reviews.is_none(maximum):
                    doc.set(proof, "maximum_cardinality", doc.new_none())
                else:
                    doc.set(
                        proof,
                        "maximum_cardinality",
                        doc.new_int(_number(reviews.text(maximum))),
                    )
                var minimum = reviews.find(node, "minimum_cardinality")
                if minimum >= 0:
                    doc.set(
                        proof,
                        "minimum_cardinality",
                        doc.new_int(_number(reviews.text(minimum))),
                    )
                doc.set(
                    proof,
                    "required",
                    doc.new_str(reviews.text(reviews.at(node, "required"))),
                )
                doc.set(
                    proof,
                    "impossible",
                    doc.new_str(reviews.text(reviews.at(node, "impossible"))),
                )
                doc.set(
                    proof,
                    "expression",
                    doc.new_str(reviews.text(reviews.at(node, "expression"))),
                )
                doc.set(
                    proof,
                    "proof_id",
                    doc.new_str(reviews.text(reviews.at(node, "proof_id"))),
                )
                doc.set(
                    proof,
                    "dependency_sha256",
                    doc.adopt(reviews, reviews.at(node, "dependency_sha256")),
                )
            doc.set(proof, "source_sha256", doc.new_str(source_hash))
            doc.append(proof_list, proof)
            proved += 1
            pick += 1
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
    var digest = sha256_hex(body.as_bytes())
    if publish:
        var envelope = PyJson()
        var holder = envelope.new_dict()
        envelope.root = holder
        envelope.set(holder, "receipt", envelope.adopt(doc, receipt))
        envelope.set(holder, "sha256", envelope.new_str(digest))
        Path(_join(build, "loop-proofs.json")).write_text(
            envelope.dumps() + "\n"
        )
        print("Loop proofs:", digest, _denom(counts))
    return body


def _verify_receipt(
    root: String,
    build: String,
    compiler: String,
    flags: String,
    mojo: String,
    cache: String,
    suites: List[String],
    saw_suites: Bool,
) raises -> String:
    """Rederive the receipt and require it to match the saved file.

    Args:
        root: The repository root.
        build: The build directory.
        compiler: The compiler text.
        flags: The flag text.
        mojo: The producer command.
        cache: The capture cache, or empty for the default.
        suites: The capture suites.
        saw_suites: True when `--suites` was present.

    Returns:
        The canonical receipt text.

    Raises:
        Error: When the saved receipt does not match the current tree.
    """
    var producer = mojo
    if producer.byte_length() == 0:
        producer = ".venv/bin/mojo"
    var expected = run_seal(
        root,
        build,
        compiler,
        flags,
        producer,
        cache,
        suites,
        saw_suites,
        False,
    )
    var saved = _read_receipt(_join(_resolve(build), "loop-proofs.json"))
    var body = dumps_canonical(saved, saved.at(saved.root, "receipt"))
    if body != expected:
        raise Error(
            "Stale or modified loop proof, source, tool, manifest, or compiler"
            " binding"
        )
    return body


def _report_consumer(doc: PyJson) raises:
    """Require the receipt to name the executing report wrapper.

    Args:
        doc: The saved receipt envelope.

    Raises:
        Error: When `tools/coverage_io.py` is not the sealed wrapper.
    """
    var receipt = doc.at(doc.root, "receipt")
    var recorded = doc.find(
        doc.at(receipt, "root_inputs"), "tools/coverage_io.py"
    )
    var actual = _hash_file(_join(_resolve("."), "tools/coverage_io.py"))
    if recorded < 0 or doc.text(recorded) != actual:
        raise Error("Stale or modified executing capture/report wrapper")


def _capture_names(directory: String) raises -> List[String]:
    """Return the `.txt.gz` captures in `directory`, in byte order.

    Args:
        directory: The capture directory.

    Returns:
        The capture paths. Empty when the directory has none.

    Raises:
        Error: If the directory cannot be read.
    """
    var names = List[String]()
    if not isdir(directory):
        return names^
    for name in listdir(directory):
        var text = String(name)
        if text.endswith(".txt.gz"):
            names.append(directory + "/" + text)
    var index = 1
    while index < len(names):
        var item = names[index]
        var place = index
        while place > 0 and names[place - 1] > item:
            names[place] = names[place - 1]
            place -= 1
        names[place] = item
        index += 1
    return names^


def _verify_captures(directory: String, envelope: PyJson) raises:
    """Require each capture binding to match the sealed receipt.

    Args:
        directory: The capture directory.
        envelope: The saved receipt envelope.

    Raises:
        Error: When a capture binding is missing or stale.
    """
    var receipt = envelope.at(envelope.root, "receipt")
    var proof_sha = envelope.text(envelope.at(envelope.root, "sha256"))
    var execution = envelope.at(receipt, "execution")
    for capture in _capture_names(directory):
        var text = Path(capture + ".proof.json").read_text()
        _reject_duplicate_keys(text)
        var doc = PyJson.parse(text)
        var node = doc.root
        if doc.kind(node) != PY_DICT or doc.length(node) != 9:
            raise Error(
                "Malformed coverage capture receipt: " + _base_name(capture)
            )
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
        for key in wanted:
            if doc.find(node, key) < 0:
                raise Error(
                    "Malformed coverage capture receipt: " + _base_name(capture)
                )
        var command = doc.at(node, "command")
        if doc.kind(command) != PY_LIST or doc.length(command) == 0:
            raise Error("Missing coverage capture command identity")
        var words = List[String]()
        for index in range(doc.length(command)):
            var item = doc.item(command, index)
            if doc.kind(item) != PY_STR:
                raise Error("Missing coverage capture command identity")
            words.append(doc.text(item))
        var suite = doc.text(doc.at(node, "suite"))
        var profile = doc.text(doc.at(node, "profile"))
        var expected = _expected_command(envelope, execution, suite, profile)
        if len(words) != len(expected):
            raise Error("Modified capture command provenance")
        for index in range(len(words)):
            if words[index] != expected[index]:
                raise Error("Modified capture command provenance")
        var stem = _stem_name(suite)
        if (
            doc.text(doc.at(node, "capture")) != stem + ".txt.gz"
            or doc.text(doc.at(node, "output")) != stem + ".out"
        ):
            raise Error("Capture files do not identify the recorded suite")
        var output = doc.text(doc.at(node, "output"))
        if (
            output.byte_length() == 0
            or output == "."
            or output == ".."
            or output.find("/") >= 0
        ):
            raise Error("Invalid coverage output identity")
        var slash = capture.rfind("/")
        var output_path = output
        if slash >= 0:
            output_path = String(capture[byte=:slash]) + "/" + output
        if (
            doc.text(doc.at(node, "schema")) != "constant-loops-v2"
            or doc.text(doc.at(node, "proof_sha256")) != proof_sha
            or doc.text(doc.at(node, "capture")) != _base_name(capture)
            or doc.text(doc.at(node, "capture_sha256")) != _hash_file(capture)
            or doc.text(doc.at(node, "output_sha256"))
            != _hash_file(output_path)
        ):
            raise Error(
                "Stale or modified coverage capture: " + _base_name(capture)
            )


def _manifest_lines(raw: List[UInt8]) -> List[String]:
    """Return manifest lines the way Python `splitlines` does.

    Args:
        raw: The manifest bytes.

    Returns:
        The lines, without their breaks.
    """
    var text = (
        String(from_utf8_lossy=raw).replace("\r\n", "\n").replace("\r", "\n")
    )
    var parts = text.split("\n")
    var lines = List[String]()
    var data = text.as_bytes()
    var limit = len(parts)
    if len(data) > 0 and data[len(data) - 1] == 10 and limit > 0:
        limit -= 1
    var index = 0
    while index < limit:
        lines.append(String(parts[index]))
        index += 1
    return lines^


def _words(line: String) -> List[String]:
    """Split `line` on ASCII whitespace.

    Args:
        line: One manifest line.

    Returns:
        The fields.
    """
    var fields = List[String]()
    var current = String()
    for byte in line.as_bytes():
        if byte == 32 or byte == 9 or byte == 11 or byte == 12:
            if current.byte_length() > 0:
                fields.append(current)
                current = String()
        else:
            current += chr(Int(byte))
    if current.byte_length() > 0:
        fields.append(current)
    return fields^


def _masked_manifest(raw: List[UInt8], envelope: PyJson) raises -> String:
    """Return the manifest with proved branches masked.

    Args:
        raw: The original manifest.
        envelope: The saved receipt envelope.

    Returns:
        The masked manifest text, including its final newline.

    Raises:
        Error: When a proof does not name one original branch.
    """
    var receipt = envelope.at(envelope.root, "receipt")
    if _digest(raw) != envelope.text(envelope.at(receipt, "manifest_sha256")):
        raise Error("Loop-proof manifest binding mismatch")
    _ = _manifest_records(raw)
    var proofs = envelope.at(receipt, "proofs")
    var digest = envelope.text(envelope.at(envelope.root, "sha256"))
    var text = "P constant-loops-v2 " + digest + "\n"
    var used = 0
    for line in _manifest_lines(raw):
        var fields = _words(line)
        var replaced = line
        if len(fields) >= 3 and fields[0] == "B":
            var index = 0
            while index < envelope.length(proofs):
                var proof = envelope.item(proofs, index)
                var line_text = envelope.text(envelope.at(proof, "line"))
                if (
                    envelope.text(envelope.at(proof, "module")) == fields[1]
                    and line_text == fields[2]
                ):
                    replaced = (
                        "R "
                        + fields[1]
                        + " "
                        + fields[2]
                        + " "
                        + envelope.text(envelope.at(proof, "required"))
                        + " "
                        + envelope.text(envelope.at(proof, "kind"))
                        + " "
                        + envelope.text(envelope.at(proof, "cardinality"))
                    )
                    used += 1
                index += 1
        text += replaced + "\n"
    if used != envelope.length(proofs):
        raise Error("Loop proof does not identify one original branch")
    return text


def run_mask(build_text: String, output_text: String) raises -> Int:
    """Write the masked manifest for one sealed build.

    Args:
        build_text: The build directory.
        output_text: The file that receives the masked manifest.

    Returns:
        Zero after the manifest is written.

    Raises:
        Error: When the receipt does not match the original manifest.
    """
    var build = _resolve(build_text)
    var raw = Path(_join(build, "manifest.txt")).read_bytes()
    var envelope = _read_receipt(_join(build, "loop-proofs.json"))
    Path(output_text).write_text(_masked_manifest(raw, envelope))
    return 0


def _ends_with_manifest(command: List[String], build: String) raises:
    """Require the report command to end with the original manifest.

    Args:
        command: The reporter command.
        build: The resolved build directory.

    Raises:
        Error: When the last argument is not `manifest.txt`.
    """
    if len(command) == 0:
        raise Error("The report command must end with the original manifest")
    var original = _resolve(_join(build, "manifest.txt"))
    var given = _resolve(command[len(command) - 1])
    if given != original:
        raise Error("The report command must end with the original manifest")


def _report_settings(
    arguments: List[String],
) raises -> List[String]:
    """Read the shared report flags.

    Args:
        arguments: The arguments after the mode.

    Returns:
        Root, build, compiler, flags, mojo, cache, capture directory, and
        manifest path. The manifest path is empty for `finish-report`.

    Raises:
        Error: When a required flag is absent.
    """
    var root = String()
    var build = String()
    var compiler = String()
    var flags = String()
    var mojo = String()
    var cache = String()
    var directory = String()
    var manifest = String()
    var index = 0
    while index < len(arguments):
        var word = arguments[index]
        if word == "--":
            break
        if word == "--loop-proof-root" and index + 1 < len(arguments):
            root = arguments[index + 1]
            index += 2
        elif word.startswith("--loop-proof-root="):
            root = String(word[byte=18:])
            index += 1
        elif word == "--loop-proof-build" and index + 1 < len(arguments):
            build = arguments[index + 1]
            index += 2
        elif word.startswith("--loop-proof-build="):
            build = String(word[byte=19:])
            index += 1
        elif word == "--capture-dir" and index + 1 < len(arguments):
            directory = arguments[index + 1]
            index += 2
        elif word.startswith("--capture-dir="):
            directory = String(word[byte=14:])
            index += 1
        elif word == "--manifest" and index + 1 < len(arguments):
            manifest = arguments[index + 1]
            index += 2
        elif word.startswith("--manifest="):
            manifest = String(word[byte=11:])
            index += 1
        elif word == "--compiler" and index + 1 < len(arguments):
            compiler = arguments[index + 1]
            index += 2
        elif word.startswith("--compiler="):
            compiler = String(word[byte=11:])
            index += 1
        elif word == "--flags" and index + 1 < len(arguments):
            flags = arguments[index + 1]
            index += 2
        elif word.startswith("--flags="):
            flags = String(word[byte=8:])
            index += 1
        elif word == "--mojo" and index + 1 < len(arguments):
            mojo = arguments[index + 1]
            index += 2
        elif word.startswith("--mojo="):
            mojo = String(word[byte=7:])
            index += 1
        elif word == "--capture-cache" and index + 1 < len(arguments):
            cache = arguments[index + 1]
            index += 2
        elif word.startswith("--capture-cache="):
            cache = String(word[byte=16:])
            index += 1
        elif word == "--suites":
            index += 1
        else:
            index += 1
    var result = List[String]()
    result.append(root)
    result.append(build)
    result.append(compiler)
    result.append(flags)
    result.append(mojo)
    result.append(cache)
    result.append(directory)
    result.append(manifest)
    return result^


def _report_suites(arguments: List[String]) -> List[String]:
    """Return the suites named after `--suites`.

    Args:
        arguments: The arguments after the mode.

    Returns:
        The suite paths. Empty when `--suites` is absent.
    """
    var suites = List[String]()
    var taking = False
    for word in arguments:
        if word == "--":
            break
        if taking and not word.startswith("--"):
            suites.append(word)
            continue
        taking = False
        if word == "--suites":
            taking = True
    return suites^


def _saw_suites(arguments: List[String]) -> Bool:
    """Return whether `--suites` is present.

    Args:
        arguments: The arguments after the mode.

    Returns:
        True when the flag is present.
    """
    for word in arguments:
        if word == "--":
            break
        if word == "--suites":
            return True
    return False


def _report_command(arguments: List[String]) -> List[String]:
    """Return the command after `--`.

    Args:
        arguments: The arguments after the mode.

    Returns:
        The command words.
    """
    var command = List[String]()
    var index = 0
    while index < len(arguments):
        if arguments[index] == "--":
            index += 1
            while index < len(arguments):
                command.append(arguments[index])
                index += 1
            break
        index += 1
    return command^


def _prepare_report(arguments: List[String]) raises:
    """Check the receipt and write the masked manifest.

    Args:
        arguments: The arguments after `prepare-report`.

    Raises:
        Error: When the receipt, a capture, or the manifest cannot be bound.
    """
    var settings = _report_settings(arguments)
    var command = _report_command(arguments)
    var root = _resolve(settings[0])
    var build = _resolve(settings[1])
    _ends_with_manifest(command, build)
    var suites = _report_suites(arguments)
    var saw = _saw_suites(arguments)
    _ = _verify_receipt(
        settings[0],
        settings[1],
        settings[2],
        settings[3],
        settings[4],
        settings[5],
        suites,
        saw,
    )
    var saved = _read_receipt(_join(build, "loop-proofs.json"))
    _report_consumer(saved)
    _verify_captures(settings[6], saved)
    var masked = _masked_manifest(
        Path(_join(build, "manifest.txt")).read_bytes(), saved
    )
    Path(settings[7]).write_text(masked)
    print(
        "Validated loop-proof binding "
        + saved.text(saved.at(saved.root, "sha256"))
    )


def _finish_report(arguments: List[String]) raises:
    """Require the receipt to stay the same through the report.

    Args:
        arguments: The arguments after `finish-report`.

    Raises:
        Error: When the receipt changes or a capture binding is stale.
    """
    var settings = _report_settings(arguments)
    var suites = _report_suites(arguments)
    var saw = _saw_suites(arguments)
    var first = _verify_receipt(
        settings[0],
        settings[1],
        settings[2],
        settings[3],
        settings[4],
        settings[5],
        suites,
        saw,
    )
    var saved = _read_receipt(_join(_resolve(settings[1]), "loop-proofs.json"))
    _report_consumer(saved)
    var second = _verify_receipt(
        settings[0],
        settings[1],
        settings[2],
        settings[3],
        settings[4],
        settings[5],
        suites,
        saw,
    )
    if first != second:
        raise Error("Loop-proof identity changed during reporting")
    _verify_captures(settings[6], saved)


def _report_main(mode: String, arguments: List[String]) -> Int:
    """Run one report check and print Python's error text.

    Args:
        mode: `prepare-report` or `finish-report`.
        arguments: The arguments after the mode.

    Returns:
        Zero after the check, or 1 when it fails.
    """
    try:
        if mode == "prepare-report":
            _prepare_report(arguments)
        else:
            _finish_report(arguments)
        return 0
    except error:
        print("coverage_io: " + String(error), file=stderr)
        return 1


def _fold_name(name: String) -> String:
    """Return `name` with ASCII letters in lowercase.

    Args:
        name: A directory entry.

    Returns:
        The folded name.
    """
    var folded = String()
    for byte in name.as_bytes():
        if byte >= 65 and byte <= 90:
            folded += chr(Int(byte) + 32)
        else:
            folded += chr(Int(byte))
    return folded


def _kept_child(name: String, relative: String) -> Bool:
    """Return whether a walk descends into this directory.

    Args:
        name: The directory entry.
        relative: The path relative to the walk root.

    Returns:
        False for a cache directory or `coverage/build`.
    """
    if (
        name == ".git"
        or name == ".venv"
        or name == ".cache"
        or name == "out"
        or name == "node_modules"
        or name == "__pycache__"
        or name == ".agents"
        or name == ".claude"
    ):
        return False
    return relative != "coverage/build"


def _walk_blocked(root: String, resolver: Bool) -> Bool:
    """Return whether `root` hides a renderer-cap resolver surface.

    Args:
        root: A source or include directory.
        resolver: True to apply the producer and consumer name rules.

    Returns:
        True when a symlink, a `std` name, or an alternate package is present.
    """
    if not isdir(root):
        return True
    var pending = List[String]()
    pending.append(root)
    while len(pending) > 0:
        var directory = pending.pop()
        var relative = String()
        if directory != root:
            relative = String(directory[byte = root.byte_length() + 1 :])
        var names: List[String]
        try:
            names = listdir(directory)
        except:
            return True
        for name in names:
            var entry = String(name)
            var full = directory + "/" + entry
            if islink(full):
                return True
            var folded = _fold_name(entry)
            if folded == "std" or folded.startswith("std."):
                return True
            var child = entry
            if relative.byte_length() > 0:
                child = relative + "/" + entry
            if resolver:
                if (
                    (relative == "objects" or relative == "renderers")
                    and folded.startswith("__init__.")
                    and entry != "__init__.mojo"
                    and entry != "__init__.mojo.cov-origin"
                ):
                    return True
                var alternate = False
                for stem in ["objects", "renderers", "line_segments2"]:
                    if folded == stem or folded.startswith(stem + "."):
                        alternate = True
                if alternate and not (
                    child == "objects"
                    or child == "renderers"
                    or child == "objects/line_segments2.mojo"
                    or child == "objects/line_segments2.mojo.cov-origin"
                ):
                    return True
            if isdir(full) and _kept_child(entry, child):
                pending.append(full)
    return False


def _last_stem(path: String) -> String:
    """Return `path` without its final suffix.

    Args:
        path: A relative path.

    Returns:
        The path with the last dotted suffix removed.
    """
    var slash = path.rfind("/")
    var name = path
    var directory = String()
    if slash >= 0:
        directory = String(path[byte=:slash])
        name = String(path[byte = slash + 1 :])
    var dot = name.rfind(".")
    var stem = name
    if dot > 0:
        stem = String(name[byte=:dot])
    if directory.byte_length() == 0:
        return stem
    return directory + "/" + stem


def _dependency_paths(table: PyJson, module: String) raises -> List[String]:
    """Return the dependency paths named for `module`.

    Args:
        table: The reviewed-loop table.
        module: The module name, without `.mojo`.

    Returns:
        Each dependency path once. Empty when `module` has no row.

    Raises:
        Error: When a row is not a list entry.
    """
    var paths = List[String]()
    var rows = table.get(table.root, module)
    if rows == MISSING or table.kind(rows) != PY_LIST:
        return paths^
    var index = 0
    while index < table.length(rows):
        var row = table.item(rows, index)
        var deps = table.get(row, "dependency_sha256")
        if deps != MISSING and table.kind(deps) == PY_DICT:
            var key_index = 0
            while key_index < table.length(deps):
                var path = table.key(deps, key_index)
                var seen = False
                for kept in paths:
                    if kept == path:
                        seen = True
                if not seen:
                    paths.append(path)
                key_index += 1
        index += 1
    return paths^


def _origin_competitor(
    relative: String, paths: List[String], allow_origin: Bool
) -> Bool:
    """Return whether `relative` competes with a reviewed dependency.

    An include root may hold the exact `path.cov-origin` sidecar. Any
    other suffix, package, or case variant competes. A file in the walk
    root whose name starts with a dependency namespace also competes.

    Args:
        relative: The path relative to the walk root.
        paths: The dependency paths.
        allow_origin: True when an exact origin sidecar is allowed.

    Returns:
        True when the proof must be omitted.
    """
    for path in paths:
        if relative == path:
            return False
        if allow_origin and relative == path + ".cov-origin":
            return False
    var folded = _fold_name(relative)
    for path in paths:
        var dep = _fold_name(path)
        var stem = _fold_name(_last_stem(path))
        if folded == dep or folded.startswith(dep + "."):
            return True
        if _fold_name(_last_stem(relative)) == stem:
            return True
        var cursor = 0
        var bytes = relative.as_bytes()
        while cursor < len(bytes):
            if bytes[cursor] == 46:
                var prefix = _fold_name(String(relative[byte=:cursor]))
                if prefix == dep:
                    return True
            cursor += 1
        if relative.find("/") < 0:
            var slash = path.find("/")
            var top = path
            if slash > 0:
                top = String(path[byte=:slash])
            var dot = relative.find(".")
            var scoped = relative
            if dot > 0:
                scoped = String(relative[byte=:dot])
            if _fold_name(scoped) == _fold_name(top):
                return True
    return False


def _origin_blocked(
    root: String, paths: List[String], allow_origin: Bool
) -> Bool:
    """Return whether `root` holds a competing provider file.

    Args:
        root: A source or include directory.
        paths: The dependency paths. An empty list checks nothing.
        allow_origin: True when an exact origin sidecar is allowed.

    Returns:
        True when a competing file is present or a directory cannot be read.
    """
    if len(paths) == 0 or not isdir(root):
        return False
    var pending = List[String]()
    pending.append(root)
    while len(pending) > 0:
        var directory = pending.pop()
        var relative = String()
        if directory != root:
            relative = String(directory[byte = root.byte_length() + 1 :])
        var names: List[String]
        try:
            names = listdir(directory)
        except:
            return True
        for name in names:
            var entry = String(name)
            var full = directory + "/" + entry
            var child = entry
            if relative.byte_length() > 0:
                child = relative + "/" + entry
            if isdir(full):
                if _kept_child(entry, child):
                    pending.append(full)
                continue
            if _origin_competitor(child, paths, allow_origin):
                return True
    return False


def strand_cap_line(hashes: List[String]) -> Int:
    """Return the admitted strand-cap line for five dependency digests.

    The digests are `objects/__init__.mojo`, `renderers/__init__.mojo`,
    `renderers/renderer.mojo`, `objects/line_segments2.mojo`, and
    `tests/test_small_loop_witnesses.mojo`, in that order. A historical
    endpoint is admitted only when the producer and the consumer are the
    same reviewed pair.

    Args:
        hashes: The five dependency digests.

    Returns:
        The proof line, or `-1` when the pair is not a reviewed endpoint.
    """
    if len(hashes) != 5:
        return -1
    var init = (
        "5f3ace6c2d6162c4a542666c21a966d54d5b98b8d4982794ea5bfbbcc4f52479"
    )
    var witness = (
        "8f768e04ecaebdb132cf359819be03cb039d5a546b823674c22ac06a1b790362"
    )
    var old_segments = (
        "5680f188d71c88465be6f7d8173858221a57525663fb4c75d95721fcc2658e79"
    )
    var new_segments = (
        "fdff9f90123e0d3d8d3ca9b0aaf22e3b2c110c255d01a14927ce1fca8fa7d021"
    )
    var renderer = hashes[2]
    var line = -1
    if (
        renderer
        == "ad8d3a26292683ba744d20fa05f13491e31019540774002809bfad8ba3ae6bf5"
    ):
        line = 3757
    elif (
        renderer
        == "08ce4d257874c1107305cc1abf45ec4ebd89a9b183902974085d507974410c45"
    ):
        line = 3886
    var bases = hashes[0] == init and hashes[1] == init and hashes[4] == witness
    # PR791 passes the worker count to the splat prepare call, far below the
    # cap loop. The cap function, its producer and its line are unchanged.
    if (
        bases
        and renderer
        == "c08275ccfea2f32dd84dc5ad54205052f6dfd216104836c858ff259224426332"
        and hashes[3] == new_segments
    ):
        return 4049
    if (
        bases
        and renderer
        == "990d94c815315c910b12c1b126c076183fc35cdeb9f64a26d1f7e574f424bccd"
        and hashes[3] == new_segments
    ):
        return 4049
    if (
        bases
        and renderer
        == "df552b5bc14d6cc5a0ef4cf919afaf66da620f431b0d4f5bb9c3a61538cb2b84"
        and hashes[3] == new_segments
    ):
        return 4047
    if (
        bases
        and renderer
        == "2491b99a982cd4bc49b3573d3c6db8313bfdd47372e693e932c03c27d0ff127d"
        and hashes[3] == new_segments
    ):
        return 4047
    if line < 0 or not bases or hashes[3] != old_segments:
        return -1
    return line


def run_reviews(
    root_text: String, module: String, includes: List[String]
) raises -> Int:
    """Print reviewed proofs for one module.

    Args:
        root_text: The source root.
        module: The module name, without `.mojo`.
        includes: Extra directories checked for resolver shadows.

    Returns:
        Zero after the proofs are printed.

    Raises:
        Error: When the table or a dependency file cannot be read.
    """
    var resolved = _resolve(root_text)
    var table = _load_reviews()
    var paths = _dependency_paths(table, module)
    var blocked = _walk_blocked(resolved, False)
    if not blocked:
        blocked = _origin_blocked(resolved, paths, False)
    if module == "renderers/renderer" and not blocked:
        blocked = _walk_blocked(resolved, True)
    var include_index = 0
    while include_index < len(includes) and not blocked:
        var extra = _resolve(includes[include_index])
        if _walk_blocked(extra, False) or _origin_blocked(extra, paths, True):
            blocked = True
        elif module == "renderers/renderer" and _walk_blocked(extra, True):
            blocked = True
        include_index += 1
    if blocked:
        print("[]")
        return 0
    var nodes = _reviewed_nodes(table, _resolve(root_text), module)
    var order = List[Int]()
    var index = 0
    while index < len(nodes):
        var line = _number(table.text(table.at(nodes[index], "line")))
        var place = len(order)
        order.append(index)
        while place > 0:
            var previous = _number(
                table.text(table.at(nodes[order[place - 1]], "line"))
            )
            if previous <= line:
                break
            order[place] = order[place - 1]
            place -= 1
        order[place] = index
        index += 1
    var doc = PyJson()
    var items = doc.new_list()
    doc.root = items
    for slot in order:
        doc.append(items, doc.adopt(table, nodes[slot]))
    print(dumps_canonical(doc, items))
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
    if len(arguments) > 0 and arguments[0] == "loops":
        if len(arguments) != 2:
            raise Error("usage: coverage_loop_seal loops FILE")
        var records = constant_loops(Path(arguments[1]).read_text())
        var doc = PyJson()
        var items = doc.new_list()
        doc.root = items
        for record in records:
            var proof = doc.new_dict()
            doc.set(proof, "line", doc.new_int(_number(record[0])))
            doc.set(proof, "kind", doc.new_str(record[1]))
            doc.set(proof, "cardinality", doc.new_int(_number(record[2])))
            doc.set(proof, "required", doc.new_str(record[3]))
            doc.set(proof, "impossible", doc.new_str(record[4]))
            doc.set(proof, "expression", doc.new_str(record[5]))
            doc.append(items, proof)
        print(doc.dumps())
        return 0
    if len(arguments) > 0 and arguments[0] == "mask":
        if (
            len(arguments) != 5
            or arguments[1] != "--build"
            or arguments[3] != "--output"
        ):
            raise Error(
                "usage: coverage_loop_seal mask --build DIR --output FILE"
            )
        return run_mask(arguments[2], arguments[4])
    if len(arguments) > 0 and arguments[0] == "reviews":
        if len(arguments) < 3:
            raise Error(
                "usage: coverage_loop_seal reviews ROOT MODULE [--include DIR]"
            )
        var includes = List[String]()
        var include_at = 3
        while include_at < len(arguments):
            if arguments[include_at] != "--include" or include_at + 1 >= len(
                arguments
            ):
                raise Error(
                    "usage: coverage_loop_seal reviews ROOT MODULE [--include"
                    " DIR]"
                )
            includes.append(arguments[include_at + 1])
            include_at += 2
        return run_reviews(arguments[1], arguments[2], includes)
    if len(arguments) > 0 and (
        arguments[0] == "prepare-report" or arguments[0] == "finish-report"
    ):
        var rest = List[String]()
        for index in range(1, len(arguments)):
            rest.append(arguments[index])
        return _report_main(arguments[0], rest)
    var verifying = False
    var words = List[String]()
    var start = 0
    if len(arguments) > 0 and arguments[0] == "verify":
        verifying = True
        start = 1
    for index in range(start, len(arguments)):
        words.append(arguments[index])
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
    while index < len(words):
        var word = words[index]
        if taking and not word.startswith("--"):
            suites.append(word)
            index += 1
            continue
        taking = False
        if word == "--root":
            root = _value(words, index)
            saw_root = True
            index += 2
        elif word.startswith("--root="):
            root = String(word[byte=7:])
            saw_root = True
            index += 1
        elif word == "--build":
            build = _value(words, index)
            saw_build = True
            index += 2
        elif word.startswith("--build="):
            build = String(word[byte=8:])
            saw_build = True
            index += 1
        elif word == "--compiler":
            compiler = _value(words, index)
            saw_compiler = True
            index += 2
        elif word.startswith("--compiler="):
            compiler = String(word[byte=11:])
            saw_compiler = True
            index += 1
        elif word == "--flags":
            flags = _value(words, index)
            saw_flags = True
            index += 2
        elif word.startswith("--flags="):
            flags = String(word[byte=8:])
            saw_flags = True
            index += 1
        elif word == "--mojo":
            mojo = _value(words, index)
            saw_mojo = True
            index += 2
        elif word.startswith("--mojo="):
            mojo = String(word[byte=7:])
            saw_mojo = True
            index += 1
        elif word == "--capture-cache":
            cache = _value(words, index)
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
    if verifying:
        _ = _verify_receipt(
            root, build, compiler, flags, mojo, cache, suites, saw_suites
        )
        return 0
    _ = run_seal(
        root, build, compiler, flags, mojo, cache, suites, saw_suites, True
    )
    return 0


def main() raises:
    """Seal loop proofs for one coverage tree."""
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
