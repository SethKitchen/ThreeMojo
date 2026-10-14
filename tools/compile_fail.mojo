# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Check negative fixtures without treating broken builds as type safety.

    mojo run -I . tools/compile_fail.mojo --compiler=mojo --flags='-I .' \\
        tests/compile_fail/NAME.mojo [...]

A compiler must first build a valid control. Each negative fixture must then
produce an ordinary, located source diagnostic in that fixture. Missing
imports, errors in dependencies, crashes and tool failures are not passes.
Each fixture also has an expected diagnostic location and message. Unexpected
source errors fail rather than hiding syntax errors or API drift.
Regeneration requires --update-expectations and an explicit fixture selection.

The expectations file is `tools/compile_fail_expectations.json`. An update
writes it as Python's `json.dumps(..., indent=2)` does, with the fixture keys
sorted. A record that the update does not select keeps its field order.
"""

from std.ffi import c_int, external_call
from std.os import listdir, remove, rmdir, stat
from std.os.path import basename, dirname, islink, realpath
from std.pathlib import Path
from std.reflection import source_location
from std.sys import argv, exit, stderr
from std.tempfile import mkdtemp

from loaders.json import OBJECT, JsonDocument, parse_json
from tools._json_tools import JsonWriter, truthy
from tools._process import run_program, shell_quote

# The pinned compiler can emit this startup warning without failing to
# compile. Only the entire line is removed, so real crashes, import errors
# and added text still fail.
comptime CRASHPAD_STARTUP_WARNING = (
    "Failed to initialize Crashpad.  Crash reporting will not be available."
    "  Cause: while locating crashpad handler: unable to locate crashpad"
    " handler executable"
)


@fieldwise_init
struct SourceError(Copyable, Equatable, Movable):
    """One located error: its line, column and message."""

    var line: Int
    """The line number."""
    var column: Int
    """The column number."""
    var message: String
    """The message, without surrounding whitespace."""

    def __eq__(self, other: Self) -> Bool:
        """Return whether two errors are the same.

        Args:
            other: The other error.

        Returns:
            True when the line, column and message are equal.
        """
        return (
            self.line == other.line
            and self.column == other.column
            and self.message == other.message
        )

    def __lt__(self, other: Self) -> Bool:
        """Order by line, then column, then message.

        Args:
            other: The other error.

        Returns:
            True when `self` sorts first.
        """
        if self.line != other.line:
            return self.line < other.line
        if self.column != other.column:
            return self.column < other.column
        return self.message < other.message


struct Diagnostics(Copyable, Movable):
    """The expected errors and candidate notes of one fixture."""

    var errors: List[SourceError]
    """The unique errors, in sorted order."""
    var notes: List[String]
    """The unique note messages, in sorted order."""

    def __init__(out self):
        """Make an empty record."""
        self.errors = List[SourceError]()
        self.notes = List[String]()


@fieldwise_init
struct _Located(Copyable, Movable):
    """A `path:line:column:` diagnostic that one line holds."""

    var path: String
    var line: Int
    var column: Int
    var message: String


# --- output ----------------------------------------------------------------


def strip_color(text: String) -> String:
    """Remove the ANSI color sequences `ESC [ digits-and-semicolons m`.

    Args:
        text: Compiler output.

    Returns:
        The output without color sequences.
    """
    var bytes = text.as_bytes()
    var out = List[UInt8](capacity=len(bytes))
    var i = 0
    while i < len(bytes):
        if bytes[i] == 0x1B and i + 1 < len(bytes) and bytes[i + 1] == 0x5B:
            var j = i + 2
            while j < len(bytes) and (
                (bytes[j] >= 0x30 and bytes[j] <= 0x39) or bytes[j] == 0x3B
            ):
                j += 1
            if j < len(bytes) and bytes[j] == 0x6D:
                i = j + 1
                continue
        out.append(bytes[i])
        i += 1
    return String(unsafe_from_utf8=out)


def split_lines(text: String) -> List[String]:
    """Split text at line boundaries, as Python's `str.splitlines` does.

    The boundaries are LF, CR, CR LF, VT, FF, the separators 0x1C to 0x1E,
    NEL, LINE SEPARATOR and PARAGRAPH SEPARATOR.

    Args:
        text: The text.

    Returns:
        The lines, without their boundaries. A final boundary does not make
        an empty last line.
    """
    var bytes = text.as_bytes()
    var lines = List[String]()
    var start = 0
    var i = 0
    while i < len(bytes):
        var width = 0
        var byte = bytes[i]
        if byte == 0x0D:
            width = 2 if i + 1 < len(bytes) and bytes[i + 1] == 0x0A else 1
        elif (
            byte == 0x0A
            or byte == 0x0B
            or byte == 0x0C
            or (byte >= 0x1C and byte <= 0x1E)
        ):
            width = 1
        elif byte == 0xC2 and i + 1 < len(bytes) and bytes[i + 1] == 0x85:
            width = 2
        elif (
            byte == 0xE2
            and i + 2 < len(bytes)
            and bytes[i + 1] == 0x80
            and (bytes[i + 2] == 0xA8 or bytes[i + 2] == 0xA9)
        ):
            width = 3
        if width > 0:
            lines.append(String(unsafe_from_utf8=Span(bytes)[start:i]))
            i += width
            start = i
        else:
            i += 1
    if start < len(bytes):
        lines.append(String(unsafe_from_utf8=Span(bytes)[start:]))
    return lines^


def clean_output(output: String) -> String:
    """Remove color and the one known harmless startup warning.

    Args:
        output: Compiler output.

    Returns:
        The remaining lines, joined by LF.
    """
    var kept = List[String]()
    for line in split_lines(strip_color(output)):
        if line != CRASHPAD_STARTUP_WARNING:
            kept.append(line)
    return String("\n").join(kept)


def _is_space(byte: UInt8) -> Bool:
    """Return whether a byte is ASCII whitespace inside one line."""
    return byte == 0x20 or (byte >= 0x09 and byte <= 0x0D)


def _digits_end(bytes: Span[UInt8, _], start: Int) -> Int:
    """Return the index after the ASCII digits that begin at `start`."""
    var i = start
    while i < len(bytes) and bytes[i] >= 0x30 and bytes[i] <= 0x39:
        i += 1
    return i


def _number(bytes: Span[UInt8, _], start: Int, end: Int) -> Int:
    """Return the value of the ASCII digits from `start` to `end`."""
    var value = 0
    for i in range(start, end):
        value = value * 10 + Int(bytes[i]) - 0x30
    return value


def _starts_with(bytes: Span[UInt8, _], at: Int, word: String) -> Bool:
    """Return whether `word` occurs in `bytes` at `at`."""
    var w = word.as_bytes()
    if at + len(w) > len(bytes):
        return False
    for k in range(len(w)):
        if bytes[at + k] != w[k]:
            return False
    return True


def _locate(line: String, word: String, minimum: Int) -> Optional[_Located]:
    """Find `path:line:column: [fatal ]word message` in one line.

    The path is the shortest prefix, at least `minimum` bytes long, that
    the rest of the pattern follows. `fatal ` is allowed only before
    `error:`.
    """
    var bytes = line.as_bytes()
    for i in range(minimum, len(bytes)):
        if bytes[i] != 0x3A:
            continue
        var a = _digits_end(bytes, i + 1)
        if a == i + 1 or a >= len(bytes) or bytes[a] != 0x3A:
            continue
        var b = _digits_end(bytes, a + 1)
        if b == a + 1 or b >= len(bytes) or bytes[b] != 0x3A:
            continue
        var c = b + 1
        while c < len(bytes) and _is_space(bytes[c]):
            c += 1
        if word == "error:" and _starts_with(bytes, c, "fatal error:"):
            c += 6  # The length of "fatal ".
        if not _starts_with(bytes, c, word):
            continue
        c += word.byte_length()
        while c < len(bytes) and _is_space(bytes[c]):
            c += 1
        return _Located(
            String(unsafe_from_utf8=bytes[:i]),
            _number(bytes, i + 1, a),
            _number(bytes, a + 1, b),
            String(unsafe_from_utf8=bytes[c:]),
        )
    return None


def _errors(clean: String) -> List[_Located]:
    """Return every located error, one per line at most."""
    var found = List[_Located]()
    for line in split_lines(clean):
        var located = _locate(line, "error:", 1)
        if located:
            found.append(located.value().copy())
    return found^


def _contains_after(line: String, first: String, then: String) -> Bool:
    """Return whether `then` occurs after an occurrence of `first`."""
    var at = line.find(first)
    return at >= 0 and line.find(then, at + first.byte_length()) >= 0


def is_infrastructure(clean: String) -> Bool:
    """Return whether output reports a tool, import or compiler failure.

    The check ignores ASCII case. It is a phrase test on each line.

    Args:
        clean: Output from `clean_output`.

    Returns:
        True when a line names an infrastructure failure.
    """
    var phrases = [
        "unable to locate",
        "unable to find",
        "unable to open",
        "unable to load",
        "cannot find file",
        "cannot find module",
        "cannot open file",
        "cannot open module",
        "cannot load file",
        "cannot load module",
        "no such file or directory",
        "failed to load",
        "failed to import",
        "could not find",
        "could not load",
        "could not import",
        "unknown argument",
        "unknown option",
        "unrecognized argument",
        "unrecognized option",
        "internal compiler error",
        "llvm error",
        "please submit a bug report",
        "segmentation fault",
        "stack dump",
        "out of memory",
        "resource temporarily unavailable",
    ]
    for raw in split_lines(clean):
        var line = raw.lower()
        for phrase in phrases:
            if line.find(phrase) >= 0:
                return True
        if _contains_after(line, "module ", "not found") or _contains_after(
            line, "assertion ", "failed"
        ):
            return True
    return False


def _sorted_unique_errors(var errors: List[SourceError]) -> List[SourceError]:
    """Sort errors and drop repeats."""
    for i in range(1, len(errors)):
        var j = i
        while j > 0 and errors[j] < errors[j - 1]:
            errors.swap_elements(j, j - 1)
            j -= 1
    var out = List[SourceError]()
    for item in errors:
        if len(out) == 0 or out[len(out) - 1] != item:
            out.append(item.copy())
    return out^


def _sorted_unique_strings(var items: List[String]) -> List[String]:
    """Sort strings by code point and drop repeats."""
    for i in range(1, len(items)):
        var j = i
        while j > 0 and items[j] < items[j - 1]:
            items.swap_elements(j, j - 1)
            j -= 1
    var out = List[String]()
    for item in items:
        if len(out) == 0 or out[len(out) - 1] != item:
            out.append(item)
    return out^


def expected_diagnostics(output: String) -> Diagnostics:
    """Keep exact error locations, messages and candidate notes in order.

    Args:
        output: Compiler output.

    Returns:
        The sorted, unique errors and notes.
    """
    var clean = clean_output(output)
    var errors = List[SourceError]()
    for located in _errors(clean):
        errors.append(
            SourceError(
                located.line, located.column, String(located.message.strip())
            )
        )
    var notes = List[String]()
    for line in split_lines(clean):
        var located = _locate(line, "note:", 0)
        if located:
            notes.append(located.value().message)
    var result = Diagnostics()
    result.errors = _sorted_unique_errors(errors^)
    result.notes = _sorted_unique_strings(notes^)
    return result^


def _resolved(path: String) raises -> String:
    """Return a real path, or the absolute path when it does not exist."""
    try:
        return realpath(path)
    except:
        if path.startswith("/"):
            return path
        return realpath(".") + "/" + path


def rejection_error(
    fixture: String,
    status: Int,
    output: String,
    expectations: Optional[Diagnostics],
) raises -> Optional[String]:
    """Return why a result is not a valid rejection.

    Args:
        fixture: The negative fixture that was built.
        status: The compiler's exit status.
        output: The compiler's combined output.
        expectations: The reviewed diagnostics, or None to skip the
            comparison while expectations are regenerated.

    Returns:
        None for a source rejection in the fixture, otherwise the reason.

    Raises:
        Error: If the working directory cannot be read.
    """
    if status == 0:
        return String("compiled but should not have")
    if status != 1:
        return "compiler failed abnormally (exit " + String(status) + ")"
    var clean = clean_output(output)
    if is_infrastructure(clean):
        return String("infrastructure or import failure")
    var found = _errors(clean)
    if len(found) == 0:
        return String("no located source error")
    var expected = _resolved(fixture)
    for located in found:
        if _resolved(located.path) != expected:
            return String("error outside the negative fixture")
    if expectations:
        var captured = expected_diagnostics(output)
        var wanted = expectations.value().errors.copy()
        if (
            _sorted_unique_errors(wanted^) != captured.errors
            or captured.notes != expectations.value().notes
        ):
            return String(
                "unexpected source diagnostic (update only after review)"
            )
    return None


# --- command line ------------------------------------------------------------


def shell_split(text: String) raises -> List[String]:
    """Split words as Python's `shlex.split` does in POSIX mode.

    Args:
        text: A command line.

    Returns:
        The words. Quotes group text, a backslash outside single quotes
        escapes the next character, and there are no comments.

    Raises:
        Error: If a quote is not closed or the text ends with a backslash.
    """
    var words = List[String]()
    var bytes = text.as_bytes()
    var word = List[UInt8]()
    var in_word = False
    var i = 0
    while i < len(bytes):
        var byte = bytes[i]
        if byte == 0x27:
            in_word = True
            var close = i + 1
            while close < len(bytes) and bytes[close] != 0x27:
                close += 1
            if close >= len(bytes):
                raise Error("No closing quotation")
            word.extend(Span(bytes)[i + 1 : close])
            i = close + 1
        elif byte == 0x22:
            in_word = True
            i += 1
            while True:
                if i >= len(bytes):
                    raise Error("No closing quotation")
                if bytes[i] == 0x22:
                    i += 1
                    break
                if (
                    bytes[i] == 0x5C
                    and i + 1 < len(bytes)
                    and (
                        bytes[i + 1] == 0x22
                        or bytes[i + 1] == 0x5C
                        or bytes[i + 1] == 0x24
                        or bytes[i + 1] == 0x60
                        or bytes[i + 1] == 0x0A
                    )
                ):
                    word.append(bytes[i + 1])
                    i += 2
                else:
                    word.append(bytes[i])
                    i += 1
        elif byte == 0x5C:
            if i + 1 >= len(bytes):
                raise Error("No escaped character")
            in_word = True
            word.append(bytes[i + 1])
            i += 2
        elif _is_space(byte):
            if in_word:
                words.append(String(unsafe_from_utf8=word))
                word = List[UInt8]()
                in_word = False
            i += 1
        else:
            in_word = True
            word.append(byte)
            i += 1
    if in_word:
        words.append(String(unsafe_from_utf8=word))
    return words^


def _remove_tree(directory: String) raises:
    """Remove a flat temporary directory and its files."""
    for name in listdir(directory):
        remove(Path(directory) / name)
    rmdir(directory)


def compile_source(
    command: List[String], flags: List[String], source: String, timeout: Float64
) raises -> Tuple[Int, String]:
    """Build a source file and keep all of its diagnostics.

    Args:
        command: The compiler command words.
        flags: The flag words.
        source: The file to build.
        timeout: The time limit in seconds.

    Returns:
        The exit status and the combined output.

    Raises:
        Error: If the build does not finish within the time limit.
    """
    var arguments = command.copy()
    arguments.append("build")
    arguments.extend(flags.copy())
    arguments.append("-o")
    arguments.append("/dev/null")
    arguments.append(source)
    var result = run_program(arguments, timeout)
    if result.timed_out:
        var words = List[String]()
        for argument in arguments:
            words.append(shell_quote(argument))
        raise Error(
            "Command '"
            + String(" ").join(words)
            + "' timed out after "
            + String(timeout)
            + " seconds"
        )
    return (result.status, result.output)


# --- expectations ------------------------------------------------------------


def read_record(document: JsonDocument, fixture: String) raises -> Diagnostics:
    """Read one fixture's reviewed diagnostics.

    Args:
        document: The parsed expectations.
        fixture: The fixture path, as the manifest names it.

    Returns:
        The errors in sorted order and the notes in file order.

    Raises:
        Error: If the record does not have the expected shape.
    """
    var node = document.get(document.root(), fixture)
    var record = Diagnostics()
    var errors = document.get(node, "errors")
    for i in range(document.length(errors)):
        var item = document.at(errors, i)
        record.errors.append(
            SourceError(
                document.integer(document.get(item, "line")),
                document.integer(document.get(item, "column")),
                document.string(document.get(item, "message")),
            )
        )
    var notes = document.get(node, "notes")
    for i in range(document.length(notes)):
        record.notes.append(document.string(document.at(notes, i)))
    return record^


def expectations_text(
    document: JsonDocument,
    updated_names: List[String],
    updated: List[Diagnostics],
) raises -> String:
    """Write every record with sorted fixture keys, as `json.dumps` does.

    Args:
        document: The parsed expectations.
        updated_names: The fixtures with regenerated records.
        updated: The regenerated records, in the same order.

    Returns:
        The complete file text, ending with a newline.
    """
    var root = document.root()
    var names = List[String]()
    for i in range(document.length(root)):
        names.append(document.key(root, i))
    for name in updated_names:
        names.append(name)
    names = _sorted_unique_strings(names^)
    var writer = JsonWriter()
    writer.begin_object()
    for name in names:
        writer.key(name)
        var position = -1
        for k in range(len(updated_names)):
            if updated_names[k] == name:
                position = k
        if position < 0:
            writer.node(document, document.get(root, name))
            continue
        # A regenerated record: errors first, then notes, as the Python
        # checker built it.
        ref record = updated[position]
        writer.begin_object()
        writer.key("errors")
        writer.begin_array()
        for item in record.errors:
            writer.begin_object()
            writer.key("line")
            writer.integer(item.line)
            writer.key("column")
            writer.integer(item.column)
            writer.key("message")
            writer.string(item.message)
            writer.end()
        writer.end()
        writer.key("notes")
        writer.begin_array()
        for note in record.notes:
            writer.string(note)
        writer.end()
        writer.end()
    writer.end()
    return writer.text() + "\n"


def _bytes(text: String) -> List[UInt8]:
    """Return the UTF-8 bytes of a string."""
    var out = List[UInt8]()
    out.extend(text.as_bytes())
    return out^


def write_expectations(
    path: String, original: List[UInt8], updated: String, mut report: Report
) raises -> Bool:
    """Replace the manifest atomically without losing concurrent edits.

    Args:
        path: The expectations file.
        original: The bytes read before the builds.
        updated: The new text.
        report: Receives a unified diff of the change.

    Returns:
        True when the file changed.

    Raises:
        Error: If the file is a symbolic link, changed during the builds,
            or cannot be replaced.
    """
    if islink(path):
        raise Error("Refusing to update a symlink expectations file")
    var new_bytes = _bytes(updated)
    if new_bytes == original:
        if Path(path).read_bytes() != original:
            raise Error(
                "Expectations changed during compilation; retry after review"
            )
        return False
    var directory = mkdtemp(
        prefix=basename(path) + ".",
        dir=dirname(realpath(path)),
    )
    try:
        var temporary = directory + "/expectations.json"
        Path(temporary).write_bytes(Span(new_bytes))
        var mode = UInt32(stat(Path(path)).st_mode & 0o7777)
        # C strings need a terminating NUL, which these copies get.
        var source = temporary
        var target = path
        if external_call["chmod", c_int](source.as_c_string_span().ptr(), mode):
            raise Error("Cannot copy the expectations mode")
        if islink(path):
            raise Error("Refusing to update a symlink expectations file")
        if Path(path).read_bytes() != original:
            raise Error(
                "Expectations changed during compilation; retry after review"
            )
        if external_call["rename", c_int](
            source.as_c_string_span().ptr(), target.as_c_string_span().ptr()
        ):
            raise Error("Cannot replace the expectations file")
        var before = directory + "/before.json"
        Path(before).write_bytes(Span(original))
        var diff = run_program(_unified_diff(before, path), 60)
        report.out += diff.output
    finally:
        _remove_tree(directory)
    return True


def _unified_diff(before: String, path: String) -> List[String]:
    """Return a command that prints the change as a unified diff."""
    var arguments = List[String]()
    arguments.append("diff")
    arguments.append("-u")
    arguments.append("--label")
    arguments.append(path + " (before)")
    arguments.append("--label")
    arguments.append(path + " (after)")
    arguments.append(before)
    arguments.append(path)
    return arguments^


# --- main ------------------------------------------------------------------


struct Report(Movable):
    """What a check prints and its exit status."""

    var code: Int
    """The exit status."""
    var out: String
    """The standard output text."""
    var err: String
    """The standard error text."""

    def __init__(out self):
        """Make an empty report with status zero."""
        self.code = 0
        self.out = ""
        self.err = ""

    def line(mut self, text: String):
        """Add one line of standard output.

        Args:
            text: The line, without its newline.
        """
        self.out += text + "\n"


struct Options(Movable):
    """The parsed command line."""

    var compiler: String
    """The compiler command, split like a shell command line."""
    var flags: String
    """The compiler flags, split like a shell command line."""
    var timeout: Float64
    """The time limit for each build, in seconds."""
    var expectations: String
    """The expectations file."""
    var update: Bool
    """True to regenerate the selected records."""
    var check_repository: Bool
    """True to check the manifest against the repository instead."""
    var fixtures: List[String]
    """The negative fixtures to check."""

    def __init__(out self):
        """Make the defaults."""
        self.compiler = ""
        self.flags = ""
        self.timeout = 120
        self.expectations = (
            dirname(String(source_location().file_name()))
            + "/compile_fail_expectations.json"
        )
        self.update = False
        self.check_repository = False
        self.fixtures = List[String]()


def repository_errors(root: String, manifest: String) raises -> List[String]:
    """Check the manifest against the repository, not the compiler.

    The manifest must name exactly the files `tests/compile_fail/*.mojo`.
    Each record needs at least one error, on a line of its fixture and a
    positive column. The `Makefile` and the CI workflows must never pass
    `--update-expectations`: regeneration is a reviewed, manual step.

    Args:
        root: The repository root.
        manifest: The expectations file.

    Returns:
        One message per problem.

    Raises:
        Error: If the manifest is not a JSON object of records.
    """
    var errors = List[String]()
    var document = parse_json(Path(manifest).read_text())
    var top = document.root()
    if document.kind(top) != OBJECT:
        raise Error("Expected a JSON object of fixture records")
    var fixtures = List[String]()
    for name in listdir(root + "/tests/compile_fail"):
        if String(name).endswith(".mojo"):
            fixtures.append("tests/compile_fail/" + String(name))
    fixtures = _sorted_unique_strings(fixtures^)
    var recorded = List[String]()
    for i in range(document.length(top)):
        recorded.append(document.key(top, i))
    recorded = _sorted_unique_strings(recorded^)
    for name in fixtures:
        if name not in recorded:
            errors.append("fixture has no manifest record: " + name)
    for name in recorded:
        if name not in fixtures:
            errors.append("manifest record has no fixture: " + name)
            continue
        var lines = len(split_lines(Path(root + "/" + name).read_text()))
        var record = read_record(document, name)
        if len(record.errors) == 0:
            errors.append("manifest record has no errors: " + name)
        for item in record.errors:
            if item.line < 1 or item.line > lines or item.column < 1:
                errors.append(
                    "manifest error is outside its fixture: "
                    + name
                    + ":"
                    + String(item.line)
                    + ":"
                    + String(item.column)
                )
    var sources = List[String]()
    sources.append("Makefile")
    if Path(root + "/.github/workflows").exists():
        for name in listdir(root + "/.github/workflows"):
            if String(name).endswith(".yml"):
                sources.append(".github/workflows/" + String(name))
    for source in _sorted_unique_strings(sources^):
        if (
            Path(root + "/" + source).read_text().find("--update-expectations")
            >= 0
        ):
            errors.append("regeneration must stay manual: " + source)
    return errors^


comptime USAGE = (
    "usage: compile_fail.mojo [-h] --compiler COMPILER [--flags FLAGS]"
    " [--timeout TIMEOUT] [--expectations EXPECTATIONS]"
    " [--update-expectations] [fixtures ...]\n"
    "       compile_fail.mojo --check-repository [--expectations EXPECTATIONS]"
)


def parse_options(arguments: List[String]) raises -> Options:
    """Parse the command line as the Python tool's `argparse` parser did.

    Args:
        arguments: The arguments after the program name.

    Returns:
        The options.

    Raises:
        Error: A usage message for a missing, unknown or invalid argument.
    """
    var options = Options()
    var have_compiler = False
    var only_positional = False
    var i = 0
    while i < len(arguments):
        var argument = arguments[i]
        i += 1
        if only_positional or not argument.startswith("-") or argument == "-":
            options.fixtures.append(argument)
            continue
        if argument == "--":
            only_positional = True
            continue
        if argument == "--check-repository":
            options.check_repository = True
            continue
        if argument == "--update-expectations":
            options.update = True
            continue
        var name = argument
        var value = String("")
        var has_value = False
        var equals = argument.find("=")
        if argument.startswith("--") and equals >= 0:
            name = String(argument[byte=:equals])
            value = String(argument[byte = equals + 1 :])
            has_value = True
        if (
            name != "--compiler"
            and name != "--flags"
            and name != "--timeout"
            and name != "--expectations"
        ):
            raise Error("unrecognized arguments: " + argument)
        if not has_value:
            if i >= len(arguments):
                raise Error("argument " + name + ": expected one argument")
            value = arguments[i]
            i += 1
        if name == "--compiler":
            options.compiler = value
            have_compiler = True
        elif name == "--flags":
            options.flags = value
        elif name == "--timeout":
            try:
                options.timeout = atof(value)
            except:
                raise Error(
                    "argument --timeout: invalid float value: '" + value + "'"
                )
        else:
            options.expectations = value
    if options.check_repository:
        if have_compiler or options.update or len(options.fixtures) > 0:
            raise Error("--check-repository takes only --expectations")
        return options^
    if not have_compiler:
        raise Error("the following arguments are required: --compiler")
    if options.timeout <= 0:
        raise Error("--timeout must be positive")
    return options^


def _usage_error(message: String):
    """Print a usage error and exit with status 2, as `argparse` does."""
    print(USAGE, file=stderr)
    print("compile_fail.mojo: error: " + message, file=stderr)
    exit(2)


def check(options: Options) raises -> Report:
    """Check the compiler and fixtures.

    Args:
        options: The parsed command line.

    Returns:
        The output and the exit status: zero only when every fixture is a
        valid source rejection.

    Raises:
        Error: For an invalid compiler or flag string, or an empty update.
    """
    var command = shell_split(options.compiler)
    var flags = shell_split(options.flags)
    if len(command) == 0:
        raise Error("--compiler must not be empty")
    if options.update and len(options.fixtures) == 0:
        raise Error(
            "--update-expectations requires at least one explicit fixture"
        )
    var report = Report()
    if len(options.fixtures) == 0:
        report.line("No negative fixtures selected.")
        return report^
    var fixtures = _sorted_unique_strings(options.fixtures.copy())
    try:
        _check_fixtures(options, command, flags, fixtures, report)
    except error:
        report.err += (
            "Compile-fail infrastructure error: " + String(error) + "\n"
        )
        report.code = 1
    return report^


def _check_fixtures(
    options: Options,
    command: List[String],
    flags: List[String],
    fixtures: List[String],
    mut report: Report,
) raises:
    """Run the control and every fixture, and update or compare records."""
    var manifest = options.expectations
    if options.update and islink(manifest):
        raise Error("Refusing to update a symlink expectations file")
    var original = Path(manifest).read_bytes()
    var document = parse_json(String(from_utf8=Span(original)))
    if document.kind(document.root()) != OBJECT:
        raise Error("Expected a JSON object of fixture records")
    for fixture in fixtures:
        if not options.update and not (
            document.has(document.root(), fixture)
            and truthy(document, document.get(document.root(), fixture))
        ):
            raise Error("Missing expected diagnostics for " + fixture)
    for fixture in fixtures:
        if not Path(fixture).is_file():
            raise Error(fixture)
    var control_directory = mkdtemp(prefix="threemojo-compile-control-")
    try:
        var control = control_directory + "/control.mojo"
        Path(control).write_text("def main():\n    pass\n")
        var control_result = compile_source(
            command, flags, control, options.timeout
        )
        if control_result[0] != 0:
            report.line(
                "Compiler control failed; negative checks not measured."
            )
            report.line(control_result[1])
            report.code = 1
            return
    finally:
        _remove_tree(control_directory)
    var failed = False
    var updated_names = List[String]()
    var updated = List[Diagnostics]()
    for fixture in fixtures:
        var result = compile_source(command, flags, fixture, options.timeout)
        var expected: Optional[Diagnostics] = None
        if not options.update:
            expected = read_record(document, fixture)
        var error = rejection_error(fixture, result[0], result[1], expected)
        if error:
            failed = True
            report.line(fixture + ": " + error.value())
            report.line(result[1])
        elif options.update:
            updated_names.append(fixture)
            updated.append(expected_diagnostics(result[1]))
    if failed:
        report.code = 1
        return
    if options.update:
        var changed = write_expectations(
            manifest,
            original,
            expectations_text(document, updated_names, updated),
            report,
        )
        if changed:
            report.line("Updated expectations; review every diagnostic change.")
        else:
            report.line("Expectations unchanged.")
    report.line(
        "All "
        + String(len(fixtures))
        + " negative fixtures produced source rejections."
    )


def main() raises:
    var arguments = List[String]()
    var raw = argv()
    for i in range(1, len(raw)):
        arguments.append(String(raw[i]))
    if len(arguments) > 0 and (
        arguments[0] == "-h" or arguments[0] == "--help"
    ):
        print(USAGE)
        return
    var options: Options
    try:
        options = parse_options(arguments)
    except error:
        _usage_error(String(error))
        return
    if options.check_repository:
        var root = dirname(dirname(String(source_location().file_name())))
        var problems = repository_errors(root, options.expectations)
        for problem in problems:
            print(problem)
        if len(problems) > 0:
            exit(1)
        print(
            "The manifest covers the negative fixtures; no job regenerates it."
        )
        return
    var report: Report
    try:
        report = check(options)
    except error:
        _usage_error(String(error))
        return
    print(report.out, end="")
    print(report.err, end="", file=stderr)
    exit(report.code)
