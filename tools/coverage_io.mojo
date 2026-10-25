# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Capture one instrumented suite and keep each probe record once.

    coverage_io capture --out SUITE.out --err SUITE.txt.gz -- COMMAND...

The command runs in its own session. Its standard error is reduced: each
`COVLINE` payload, each branch, and each complete `COVEVAL2` record is kept
once. A passed group deadline stops the session. When `--loop-proof` is
set, this program checks and binds that receipt. It prints the start, the
first probe, a running line every 60 seconds, and completion. A failed
capture prints the last 30 lines of standard output and the last 30
standard-error lines that do not start with `COV`. A compiled capture
writes a phase file and reports a missing finish record.

Each capture creates a private temporary directory. Its parent is the
resolved `TMPDIR` when that variable is set. The command sees the directory
as `TMPDIR` and as `THREEMOJO_TEST_TMPDIR`. The compiler cache is inside
the directory. The tool removes the directory after any outcome.
"""

from std.collections import Dict
from std.ffi import c_int, external_call
from std.memory import OpaquePointer
from std.os import getenv, listdir, remove, setenv, unsetenv
from std.os.path import exists, isdir, isfile, islink, realpath
from std.pathlib import Path
from std.sys import CompilationTarget, argv, exit, stderr
from std.tempfile import mkdtemp

from tools._carla_files import (
    fstat_id,
    lstat_id,
    make_temporary,
    o_nofollow_flag,
    o_nonblock,
    o_rdonly,
    os_error,
    read_some,
    remove_file,
    replace_file,
)
from tools.cache_key import input_paths
from tools.coverage_loop_begin import (
    _command,
    _command_words,
    _executable,
    _hash_file,
    _inside,
    _invalid_source,
    _join,
    _parent,
    _python_version,
    _relative,
    _resolve,
    _symbolic,
    _which,
)
from tools._owned_process import (
    SIGKILL,
    ExecPlan,
    SignalHold,
    at_cwd,
    c_bytes,
    close_fd,
    errno,
    make_pipe,
    open_at,
    signal_group,
    spawn,
    strerror,
    try_wait,
    wait_blocking,
)
from tools._json_tools import quote_ascii
from tools._process import run_program, shell_quote
from tools._python_float import parse_float
from tools._python_json import (
    MISSING,
    PY_BOOL,
    PY_DICT,
    PY_LIST,
    PY_STR,
    PyJson,
    dumps_canonical,
    py_repr,
)
from tools._sha256 import sha256_hex

comptime _LINE = "COVLINE:"
comptime _BRANCH = "COVBRANCH:"
comptime _EVAL = "COVEVAL2:"
comptime _MAX_RECORD = 512
comptime _CAPACITY = 4096
comptime _WINDOW = 1024
comptime _BYPASS = 16384
comptime _DEADLINE = "THREEMOJO_COVERAGE_DEADLINE"
comptime _PHASE = "THREEMOJO_COVERAGE_PHASES"


def _usage() -> String:
    """Return the usage line."""
    return (
        "usage: coverage_io capture --out FILE --err FILE"
        + " [--loop-proof FILE] [--loop-proof-root DIR]"
        + " [--progress-seconds N] -- COMMAND..."
    )


def _now() -> Float64:
    """Return `CLOCK_MONOTONIC` in seconds."""
    var sample = List[Int64](length=2, fill=0)
    _ = external_call["clock_gettime", Int32](
        Int32(1), sample.unsafe_ptr().unsafe_bitcast[NoneType]()
    )
    return Float64(Int(sample[0])) + Float64(Int(sample[1])) / 1000000000.0


def _tenth(value: Float64) -> String:
    """Return `value` with one decimal place, half up."""
    var scaled = value * 10.0
    if scaled < 0:
        scaled -= 0.5
    else:
        scaled += 0.5
    var digits = Int(scaled)
    var whole = digits // 10
    var frac = digits - whole * 10
    if frac < 0:
        frac = -frac
    return String(whole) + "." + String(frac)


def _stem(path: String) -> String:
    """Return the file name of `path` without a trailing `.out`."""
    var base = path
    var slash = base.rfind("/")
    if slash >= 0:
        var tail = String(base[byte = slash + 1 :])
        base = tail
    if base.endswith(".out"):
        var end = base.byte_length() - 4
        var shortened = String(base[byte=:end])
        base = shortened
    return base


def _strip(text: String) -> String:
    """Return `text` without leading or trailing ASCII whitespace."""
    var bytes = text.as_bytes()
    var start = 0
    var end = len(bytes)
    while start < end:
        var byte = bytes[start]
        if (
            byte != 9
            and byte != 10
            and byte != 11
            and byte != 12
            and byte != 13
            and byte != 32
        ):
            break
        start += 1
    while end > start:
        var byte = bytes[end - 1]
        if (
            byte != 9
            and byte != 10
            and byte != 11
            and byte != 12
            and byte != 13
            and byte != 32
        ):
            break
        end -= 1
    return String(text[byte=start:end])


def _rpartition(text: String, mark: String) -> Tuple[String, String, String]:
    """Split `text` on the last `mark`, as `str.rpartition` does."""
    var at = text.rfind(mark)
    if at < 0:
        return (String(""), String(""), text)
    var head = String(text[byte=:at])
    var tail = String(text[byte = at + mark.byte_length() :])
    return (head, mark, tail)


def _digits(text: String) -> Bool:
    """Return whether `text` is a positive decimal integer."""
    if text.byte_length() == 0:
        return False
    for byte in text.as_bytes():
        if byte < 48 or byte > 57:
            return False
    return True


struct Reducer:
    """The distinct probe records from one suite."""

    var output: String
    """The reduced standard error."""
    var payloads: Dict[String, Int]
    """`COVLINE` payloads already written."""
    var evaluations: Dict[String, Int]
    """Branch and evaluation keys already written."""
    var accepted: Dict[String, Int]
    """Raw lines remembered while reuse stays high."""
    var accepted_count: Int
    """How many raw lines `accepted` holds."""
    var remaining: Int
    """Lines left in the current sample window."""
    var hits: Int
    """Exact cache hits in the current window."""
    var bypassing: Bool
    """True while a cold window skips the cache."""
    var records: Int
    """How many raw lines were fed."""
    var saw_probe: Bool
    """True after the first coverage record."""

    def __init__(out self):
        """Make an empty reducer."""
        self.output = ""
        self.payloads = Dict[String, Int]()
        self.evaluations = Dict[String, Int]()
        self.accepted = Dict[String, Int]()
        self.accepted_count = 0
        self.remaining = _WINDOW
        self.hits = 0
        self.bypassing = False
        self.records = 0
        self.saw_probe = False

    def _write(mut self, text: String):
        """Append `text` to the reduced stream."""
        self.output += text

    def _payload(mut self, payload: String):
        """Write one `COVLINE` payload the first time it appears."""
        if not payload in self.payloads:
            self.payloads[payload] = 1
            self._write(_LINE + payload + "\n")

    def _remember(mut self, line: String):
        """Remember one accepted raw line while the cache has room."""
        if line.byte_length() > _MAX_RECORD or not line.endswith("\n"):
            return
        var record = _strip(line)
        var useful = (
            record.startswith(_LINE)
            or record.startswith(_EVAL)
            or (
                record.startswith(_BRANCH)
                and record.find(":") >= _BRANCH.byte_length()
            )
        )
        if not useful:
            return
        if self.accepted_count >= _CAPACITY:
            self.accepted = Dict[String, Int]()
            self.accepted_count = 0
        if not line in self.accepted:
            self.accepted[line] = 1
            self.accepted_count += 1

    def _window(mut self):
        """Start the next sample window, or a bypass after a cold one."""
        if self.bypassing:
            self.bypassing = False
            self.remaining = _WINDOW
        elif self.hits * 4 < _WINDOW:
            self.accepted = Dict[String, Int]()
            self.accepted_count = 0
            self.bypassing = True
            self.remaining = _BYPASS
        else:
            self.remaining = _WINDOW
        self.hits = 0

    def _evidence(mut self, line: String) raises:
        """Reduce one raw line."""
        var record = _strip(line)
        if record.startswith(_LINE):
            self._payload(String(record[byte = _LINE.byte_length() :]))
            return
        if record.startswith(_EVAL):
            if (
                record.byte_length() + 1 > _MAX_RECORD
                or not record.endswith(";")
                or not line.endswith("\n")
            ):
                raise Error("Malformed or truncated evaluation record")
            var body = String(
                record[byte = _EVAL.byte_length() : record.byte_length() - 1]
            )
            var head = _rpartition(body, ":")
            var decision = _rpartition(head[0], ":")
            var module = _rpartition(decision[0], ":")
            if decision[1] == "" or (decision[2] != "T" and decision[2] != "F"):
                raise Error("Malformed evaluation outcome")
            if (
                module[1] == ""
                or module[0].byte_length() == 0
                or not _digits(module[2])
                or module[2] == "0"
            ):
                raise Error("Malformed evaluation decision ID")
            if head[2].find("?") >= 0:
                raise Error("Inconsistent repeated truth conversion")
            if head[1] == "" or head[2].byte_length() < 2:
                raise Error("Malformed evaluation vector")
            var saw = False
            for byte in head[2].as_bytes():
                if byte != 84 and byte != 70 and byte != 45:
                    raise Error("Malformed evaluation vector")
                if byte == 84 or byte == 70:
                    saw = True
            if not saw:
                raise Error("Malformed evaluation vector")
            var key = decision[0] + "\n" + head[2] + "\n" + decision[2]
            if not key in self.evaluations:
                self.evaluations[key] = 1
                self._write(record + "\n")
            return
        if not record.startswith(_BRANCH):
            self._write(line)
            return
        var payload = String(record[byte = _BRANCH.byte_length() :])
        var parts = _rpartition(payload, ":")
        if parts[1] != "" and parts[2] != "T" and parts[2] != "F":
            raise Error("Malformed branch outcome")
        if parts[1] == "":
            self._write(line)
            return
        if parts[0].find(".") >= 0:
            raise Error("Legacy compound coverage is ambiguous")
        var module = _rpartition(parts[0], ":")
        if (
            module[1] == ""
            or module[0].byte_length() == 0
            or not _digits(module[2])
            or module[2] == "0"
        ):
            raise Error("Malformed branch decision ID")
        self._payload(payload)
        var key = parts[0] + "\n\n" + parts[2]
        if not key in self.evaluations:
            self.evaluations[key] = 1
            self._write(record + "\n")

    def feed(mut self, line: String) raises:
        """Reduce one raw line, using the bounded reuse cache.

        Args:
            line: One standard-error line, including its newline when the
                program wrote one.

        Raises:
            Error: If a probe record is malformed.
        """
        self.records += 1
        var probe = _strip(line)
        if (
            probe.startswith(_LINE)
            or probe.startswith(_BRANCH)
            or probe.startswith(_EVAL)
        ):
            self.saw_probe = True
        if self.remaining == 0:
            self._window()
        self.remaining -= 1
        if self.bypassing:
            self._evidence(line)
            return
        if line in self.accepted:
            self.hits += 1
            return
        self._evidence(line)
        self._remember(line)


def _open_output(path: String) raises -> Int:
    """Create or truncate `path` and return its descriptor.

    Args:
        path: The standard-output file.

    Returns:
        The descriptor.

    Raises:
        Error: If the file cannot be opened.
    """
    Path(path).write_text("")
    var flags = 1 | 512
    if not CompilationTarget.is_linux():
        flags = 1 | 0x400
    var fd = open_at(at_cwd(), c_bytes(path), flags)
    if fd < 0:
        raise Error("cannot open " + path + ": " + strerror(errno()))
    return fd


def _gzip(text: String, destination: String) raises:
    """Write `text` as a gzip file without a timestamp.

    Args:
        text: The reduced standard error.
        destination: The `.txt.gz` path.

    Raises:
        Error: If gzip cannot write the file.
    """
    var plain = destination + ".plain"
    Path(plain).write_text(text)
    var script = (
        "gzip -n -1 -c " + shell_quote(plain) + " > " + shell_quote(destination)
    )
    var ran = run_program(["sh", "-c", script], 30.0)
    remove(Path(plain))
    if ran.status != 0:
        raise Error("gzip failed: " + ran.output)


def _skip_json(data: Span[UInt8, _], mut cursor: List[Int]):
    """Move past ASCII whitespace in a JSON text.

    Args:
        data: The JSON bytes.
        cursor: The current offset, in a one-element list.
    """
    while cursor[0] < len(data):
        var byte = data[cursor[0]]
        if byte != 32 and byte != 9 and byte != 10 and byte != 13:
            break
        cursor[0] += 1


def _json_string(data: Span[UInt8, _], mut cursor: List[Int]) raises -> String:
    """Read one JSON string and return its text.

    Args:
        data: The JSON bytes.
        cursor: The offset of the opening quote.

    Returns:
        The decoded text.

    Raises:
        Error: If the string does not end.
    """
    cursor[0] += 1
    var raw = List[UInt8]()
    while cursor[0] < len(data):
        var byte = data[cursor[0]]
        cursor[0] += 1
        if byte == 34:
            return String(from_utf8_lossy=raw)
        if byte != 92:
            raw.append(byte)
            continue
        if cursor[0] >= len(data):
            break
        var escaped = data[cursor[0]]
        cursor[0] += 1
        if escaped == 117:
            var point = 0
            for _ in range(4):
                if cursor[0] >= len(data):
                    raise Error("Duplicate receipt key: ")
                var hex = Int(data[cursor[0]])
                cursor[0] += 1
                var digit = 0
                if hex >= 48 and hex <= 57:
                    digit = hex - 48
                elif hex >= 97 and hex <= 102:
                    digit = hex - 87
                elif hex >= 65 and hex <= 70:
                    digit = hex - 55
                point = point * 16 + digit
            if point < 128:
                raw.append(UInt8(point))
            else:
                raw.append(UInt8(point))
            continue
        if escaped == 110:
            raw.append(10)
        elif escaped == 114:
            raw.append(13)
        elif escaped == 116:
            raw.append(9)
        else:
            raw.append(escaped)
    raise Error("Malformed loop-proof receipt")


def _json_value(data: Span[UInt8, _], mut cursor: List[Int]) raises:
    """Walk one JSON value, rejecting a repeated object key.

    Args:
        data: The JSON bytes.
        cursor: The current offset.

    Raises:
        Error: When an object repeats a key, or the text is not JSON.
    """
    _skip_json(data, cursor)
    if cursor[0] >= len(data):
        raise Error("Malformed loop-proof receipt")
    var byte = data[cursor[0]]
    if byte == 123:
        cursor[0] += 1
        var keys = List[String]()
        _skip_json(data, cursor)
        if cursor[0] < len(data) and data[cursor[0]] == 125:
            cursor[0] += 1
            return
        while True:
            _skip_json(data, cursor)
            var key = _json_string(data, cursor)
            for have in keys:
                if have == key:
                    raise Error("Duplicate receipt key: " + key)
            keys.append(key)
            _skip_json(data, cursor)
            if cursor[0] >= len(data) or data[cursor[0]] != 58:
                raise Error("Malformed loop-proof receipt")
            cursor[0] += 1
            _json_value(data, cursor)
            _skip_json(data, cursor)
            if cursor[0] < len(data) and data[cursor[0]] == 125:
                cursor[0] += 1
                return
            if cursor[0] >= len(data) or data[cursor[0]] != 44:
                raise Error("Malformed loop-proof receipt")
            cursor[0] += 1
    if byte == 91:
        cursor[0] += 1
        _skip_json(data, cursor)
        if cursor[0] < len(data) and data[cursor[0]] == 93:
            cursor[0] += 1
            return
        while True:
            _json_value(data, cursor)
            _skip_json(data, cursor)
            if cursor[0] < len(data) and data[cursor[0]] == 93:
                cursor[0] += 1
                return
            if cursor[0] >= len(data) or data[cursor[0]] != 44:
                raise Error("Malformed loop-proof receipt")
            cursor[0] += 1
    if byte == 34:
        _ = _json_string(data, cursor)
        return
    if byte == 116:
        cursor[0] += 4
        return
    if byte == 102:
        cursor[0] += 5
        return
    if byte == 110:
        cursor[0] += 4
        return
    while cursor[0] < len(data):
        var mark = data[cursor[0]]
        if mark == 44 or mark == 125 or mark == 93 or mark == 32 or mark == 10:
            return
        cursor[0] += 1


def _reject_duplicate_keys(text: String) raises:
    """Reject a receipt that repeats a key, as `read_receipt` does.

    Args:
        text: The receipt text.

    Raises:
        Error: When a key is repeated or the text is not JSON.
    """
    var cursor = List[Int]()
    cursor.append(0)
    _json_value(text.as_bytes(), cursor)


def _base_name(path: String) -> String:
    """Return the last component of `path`.

    Args:
        path: A path.

    Returns:
        The file name.
    """
    var slash = path.rfind("/")
    if slash < 0:
        return path
    return String(path[byte = slash + 1 :])


def _stem_name(path: String) -> String:
    """Return the file stem, as `Path.stem` does.

    Args:
        path: A path.

    Returns:
        The last component without its last suffix.
    """
    var base = _base_name(path)
    var dot = base.rfind(".")
    if dot <= 0:
        return base
    return String(base[byte=:dot])


def _expand_token(value: String, root: String, build: String) -> String:
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


def _sorted_copy(names: List[String]) -> List[String]:
    """Return `names` in byte order.

    Args:
        names: The strings.

    Returns:
        A sorted copy.
    """
    var copy = List[String]()
    for name in names:
        copy.append(name)
    var index = 1
    while index < len(copy):
        var item = copy[index]
        var place = index
        while place > 0 and copy[place - 1] > item:
            copy[place] = copy[place - 1]
            place -= 1
        copy[place] = item
        index += 1
    return copy^


def _hash_inputs(
    mut doc: PyJson, root: String, build: String, staged: Bool
) raises -> Int:
    """Return the maintained-input hashes under `root`.

    Args:
        doc: The document that holds the dict.
        root: The directory to walk.
        build: The build directory to leave out, or empty.
        staged: True when `root` is the instrumented tree.

    Returns:
        A dict node.

    Raises:
        Error: If a walked file is not a source or cannot be read.
    """
    var node = doc.new_dict()
    var root_real = _resolve(root)
    var build_real = String()
    if build.byte_length() > 0:
        build_real = _resolve(build)
    for relative in input_paths(root_real):
        if _invalid_source(relative):
            raise Error(
                "Invalid coverage source identity: " + py_repr(relative)
            )
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
    return node


def _origin_files(
    directory: String,
    base: String,
    mut names: List[String],
    mut ancestors: List[String],
) raises:
    """Collect `.cov-origin` files under `directory`.

    Args:
        directory: The directory to read.
        base: The build directory.
        names: The relative paths found so far.
        ancestors: Real paths of the directories above this one.

    Raises:
        Error: If a directory cannot be resolved.
    """
    var real = realpath(directory)
    for seen in ancestors:
        if seen == real:
            return
    ancestors.append(real)
    var listed: List[String]
    try:
        listed = listdir(directory)
    except:
        _ = ancestors.pop()
        return
    for name in listed:
        var full = directory + "/" + name
        if isdir(full):
            _origin_files(full, base, names, ancestors)
        elif isfile(full) and name.endswith(".cov-origin"):
            if full.startswith(base + "/"):
                names.append(_relative(full, base))
    _ = ancestors.pop()


def _same_json(
    left: PyJson, left_node: Int, right: PyJson, right_node: Int
) raises -> Bool:
    """Return whether two values have the same canonical JSON.

    Args:
        left: The first document.
        left_node: The first value.
        right: The second document.
        right_node: The second value.

    Returns:
        True when the canonical texts are equal.

    Raises:
        Error: If either value cannot be written.
    """
    return dumps_canonical(left, left_node) == dumps_canonical(
        right, right_node
    )


def _list_has(doc: PyJson, node: Int, text: String) raises -> Bool:
    """Return whether a string list contains `text`.

    Args:
        doc: The document.
        node: A list.
        text: The string.

    Returns:
        True when an item equals `text`.

    Raises:
        Error: If an item position is past the end.
    """
    for index in range(doc.length(node)):
        var item = doc.item(node, index)
        if doc.kind(item) == PY_STR and doc.text(item) == text:
            return True
    return False


def _expected_command(
    doc: PyJson, execution: Int, suite: String, profile: String
) raises -> List[String]:
    """Return the sealed capture command for one suite.

    Args:
        doc: The receipt document.
        execution: The execution contract.
        suite: The staged suite path.
        profile: `raw`, `aot`, or `aot-hits`.

    Returns:
        The symbolic command.

    Raises:
        Error: When the suite or profile is outside the contract.
    """
    if not _list_has(doc, doc.at(execution, "suites"), suite) or not _list_has(
        doc, doc.at(execution, "profiles"), profile
    ):
        raise Error(
            "Capture suite/profile is outside the sealed execution contract"
        )
    var words = List[String]()
    var compiler = doc.at(execution, "compiler")
    for index in range(doc.length(compiler)):
        var item = doc.item(compiler, index)
        var path = doc.find(item, "path")
        if path >= 0:
            words.append(doc.text(path))
        else:
            words.append(doc.text(doc.at(item, "literal")))
    var command = List[String]()
    command.append("@ROOT@/tools/tool.sh")
    for word in words:
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
    for word in words:
        command.append(word)
    command.append("run")
    command.append("-I")
    command.append("@BUILD@")
    command.append("@BUILD@/" + suite)
    return command^


def _execution_contract(
    root: String,
    build: String,
    inputs: PyJson,
    input_node: Int,
    words: List[String],
    cache: String,
    suites: List[String],
) raises -> String:
    """Return the canonical execution contract.

    Args:
        root: The resolved repository root.
        build: The resolved build directory.
        inputs: The document that holds the staged inputs.
        input_node: The staged-input dict.
        words: The compiler command.
        cache: The cache directory.
        suites: The capture suites.

    Returns:
        The canonical JSON text.

    Raises:
        Error: When the suite list is not staged, or a compiler is missing.
    """
    var selected = _sorted_copy(suites)
    for index in range(len(selected)):
        for other in range(index + 1, len(selected)):
            if selected[index] == selected[other]:
                raise Error("Capture suite inventory is invalid or not staged")
        if inputs.find(input_node, selected[index]) < 0:
            raise Error("Capture suite inventory is invalid or not staged")
    var doc = PyJson()
    var node = doc.new_dict()
    doc.root = node
    doc.set(node, "schema", doc.new_str("coverage-execution-v1"))
    var python = _which("python3")
    if python.byte_length() == 0:
        raise Error("Missing capture executable: python3")
    var resolved = _resolve(python)
    var interpreter = doc.new_dict()
    doc.set(interpreter, "path", doc.new_str(_symbolic(resolved, root, build)))
    doc.set(interpreter, "sha256", doc.new_str(_hash_file(resolved)))
    doc.set(node, "python", interpreter)
    doc.set(node, "compiler", _command_words(doc, words, root, build))
    doc.set(node, "cache", doc.new_str(_symbolic(_resolve(cache), root, build)))
    var suite_list = doc.new_list()
    for suite in selected:
        doc.append(suite_list, doc.new_str(suite))
    doc.set(node, "suites", suite_list)
    var cc = getenv("CC", "cc")
    doc.set(node, "cc", doc.new_str(cc))
    doc.set(node, "native_compiler", _command(doc, cc, root, build))
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
    return doc.dumps()


def _check_inputs(
    doc: PyJson, receipt: Int, root: String, build: String
) raises:
    """Check a sealed receipt against the current tree.

    Args:
        doc: The receipt document.
        receipt: The receipt object.
        root: The resolved repository root.
        build: The resolved build directory.

    Raises:
        Error: With Python's text when a sealed byte has changed.
    """
    var fresh = PyJson()
    var hashed = _hash_inputs(fresh, root, build, False)
    if not _same_json(fresh, hashed, doc, doc.at(receipt, "root_inputs")):
        raise Error("Stale or modified capture input binding")
    var staged_doc = PyJson()
    var staged = _hash_inputs(staged_doc, build, String(), True)
    var recorded = PyJson()
    var recorded_node = recorded.new_dict()
    var inputs = doc.at(receipt, "inputs")
    for index in range(doc.length(inputs)):
        var name = doc.key(inputs, index)
        var item = doc.value(inputs, index)
        recorded.set(
            recorded_node,
            name,
            recorded.new_str(doc.text(doc.at(item, "instrumented"))),
        )
    if not _same_json(staged_doc, staged, recorded, recorded_node):
        raise Error("Stale or modified capture input binding")
    var generation = doc.at(receipt, "generation")
    if (
        _hash_file(_join(build, "manifest.txt"))
        != doc.text(doc.at(receipt, "manifest_sha256"))
        or _hash_file(_join(build, "origins.ready"))
        != doc.text(doc.at(generation, "index_sha256"))
        or _hash_file(_join(build, "generation-inputs.json"))
        != doc.text(doc.at(generation, "checkpoint_sha256"))
    ):
        raise Error("Stale or modified capture input binding")
    var found = List[String]()
    var ancestors = List[String]()
    _origin_files(build, build, found, ancestors)
    var actual = PyJson()
    var actual_node = actual.new_dict()
    for name in found:
        actual.set(
            actual_node, name, actual.new_str(_hash_file(_join(build, name)))
        )
    var expected = PyJson()
    var expected_node = expected.new_dict()
    var modules = doc.at(generation, "modules")
    for index in range(doc.length(modules)):
        var name = doc.key(modules, index)
        var item = doc.value(modules, index)
        expected.set(
            expected_node,
            name + ".cov-origin",
            expected.new_str(doc.text(doc.at(item, "origin_sha256"))),
        )
    if not _same_json(actual, actual_node, expected, expected_node):
        raise Error("Stale or modified capture generation origins")
    var tools = doc.at(receipt, "root_inputs")
    for name in [
        "tools/coverage_loop_proofs.py",
        "tools/cache_key.py",
        "tools/coverage_toolchain_identity.py",
    ]:
        if doc.text(doc.at(tools, name)) != _hash_file(_join(root, name)):
            raise Error("Stale or modified executing capture verifier")
    var execution = doc.at(receipt, "execution")
    var words = List[String]()
    var compiler = doc.at(execution, "compiler")
    for index in range(doc.length(compiler)):
        var item = doc.item(compiler, index)
        var path = doc.find(item, "path")
        if path >= 0:
            words.append(_expand_token(doc.text(path), root, build))
        else:
            words.append(doc.text(doc.at(item, "literal")))
    var suites = List[String]()
    var suite_node = doc.at(execution, "suites")
    for index in range(doc.length(suite_node)):
        suites.append(doc.text(doc.item(suite_node, index)))
    var cache = _expand_token(doc.text(doc.at(execution, "cache")), root, build)
    var current = _execution_contract(
        root, build, doc, inputs, words, cache, suites
    )
    if (
        current != dumps_canonical(doc, execution)
        or doc.text(doc.at(receipt, "python")) != _python_version()
    ):
        raise Error("Stale or modified capture compiler/execution identity")


def _read_receipt(path: String) raises -> PyJson:
    """Read a loop-proof receipt and check its digest.

    Args:
        path: The receipt file.

    Returns:
        The document. Its root is the envelope.

    Raises:
        Error: With Python's text when the receipt is malformed.
    """
    var text = Path(path).read_text()
    _reject_duplicate_keys(text)
    var doc = PyJson.parse(text)
    var root = doc.root
    if (
        doc.kind(root) != PY_DICT
        or doc.length(root) != 2
        or doc.find(root, "receipt") < 0
        or doc.find(root, "sha256") < 0
    ):
        raise Error("Malformed loop-proof receipt")
    var receipt = doc.at(root, "receipt")
    if (
        doc.kind(receipt) != PY_DICT
        or doc.text(doc.at(receipt, "schema")) != "constant-loops-v2"
    ):
        raise Error("Unsupported loop-proof schema")
    var body = dumps_canonical(doc, receipt)
    if doc.text(doc.at(root, "sha256")) != sha256_hex(body.as_bytes()):
        raise Error("Loop-proof receipt digest mismatch")
    return doc^


def _consumer(doc: PyJson, receipt: Int, root: String) raises:
    """Check that the receipt names this capture wrapper.

    Args:
        doc: The receipt document.
        receipt: The receipt object.
        root: The resolved repository root.

    Raises:
        Error: When `tools/coverage_io.py` is not the sealed wrapper.
    """
    var inputs = doc.at(receipt, "root_inputs")
    var recorded = doc.find(inputs, "tools/coverage_io.py")
    var actual = _hash_file(_join(root, "tools/coverage_io.py"))
    if recorded < 0 or doc.text(recorded) != actual:
        raise Error("Stale or modified executing capture/report wrapper")


def _checked_command(
    doc: PyJson,
    receipt: Int,
    root: String,
    build: String,
    command: List[String],
    capture: String,
    output: String,
) raises -> List[String]:
    """Return the sealed command when `command` matches it.

    Args:
        doc: The receipt document.
        receipt: The receipt object.
        root: The resolved repository root.
        build: The resolved build directory.
        command: The command about to run.
        capture: The capture path.
        output: The standard-output path.

    Returns:
        The symbolic command, then the suite, then the profile. The suite
        is the second-to-last item and the profile is the last item.

    Raises:
        Error: With Python's text when the command is not the sealed one.
    """
    if len(command) == 0:
        raise Error("Coverage capture command identity is required")
    var suite_at = -1
    for index in range(len(command)):
        if command[index] == "--suite":
            suite_at = index
    if suite_at < 0 or suite_at + 1 >= len(command):
        raise Error("Capture command does not identify a staged suite")
    var full = _resolve(_join(root, command[suite_at + 1]))
    if not _inside(full, build):
        raise Error("Capture command does not identify a staged suite")
    var suite = "." if full == build else _relative(full, build)
    var profile = String("raw")
    for index in range(len(command)):
        if command[index] == "--profile":
            if index + 1 >= len(command):
                raise Error("Missing capture execution profile")
            profile = command[index + 1]
    var execution = doc.at(receipt, "execution")
    var expected = _expected_command(doc, execution, suite, profile)
    if len(command) != len(expected):
        raise Error(
            "Capture command differs from its sealed execution contract"
        )
    for index in range(len(command)):
        var wanted = expected[index]
        var normalized = command[index]
        var is_path = (
            wanted.startswith("@ROOT@")
            or wanted.startswith("@BUILD@")
            or wanted.startswith("/")
        )
        if index == 0:
            normalized = _symbolic(
                _executable(command[index], root), root, build
            )
        elif is_path:
            normalized = _symbolic(_join(root, command[index]), root, build)
        if normalized != wanted:
            raise Error(
                "Capture command differs from its sealed execution contract"
            )
    if getenv("CC", "cc") != doc.text(doc.at(execution, "cc")):
        raise Error(
            "Capture native-compiler setting differs from its sealed contract"
        )
    var stem = _stem_name(suite)
    if _base_name(capture) != stem + ".txt.gz":
        raise Error("Capture filename does not identify its sealed suite")
    if _base_name(output) != stem + ".out":
        raise Error(
            "Capture stdout filename does not identify its sealed suite"
        )
    expected.append(suite)
    expected.append(profile)
    return expected^


def _bind_receipt(
    proof_sha: String,
    err_path: String,
    out_path: String,
    checked: List[String],
) raises:
    """Write the capture binding next to the reduced capture.

    Args:
        proof_sha: The receipt digest.
        err_path: The reduced capture.
        out_path: The standard-output file.
        checked: The symbolic command, the suite, and the profile.

    Raises:
        Error: If a capture file cannot be read.
    """
    var profile = checked[len(checked) - 1]
    var suite = checked[len(checked) - 2]
    var doc = PyJson()
    var node = doc.new_dict()
    doc.root = node
    doc.set(node, "schema", doc.new_str("constant-loops-v2"))
    doc.set(node, "proof_sha256", doc.new_str(proof_sha))
    doc.set(node, "capture", doc.new_str(_base_name(err_path)))
    doc.set(node, "capture_sha256", doc.new_str(_hash_file(err_path)))
    doc.set(node, "output", doc.new_str(_base_name(out_path)))
    doc.set(node, "output_sha256", doc.new_str(_hash_file(out_path)))
    doc.set(node, "suite", doc.new_str(suite))
    doc.set(node, "profile", doc.new_str(profile))
    var command = doc.new_list()
    for index in range(len(checked) - 2):
        doc.append(command, doc.new_str(checked[index]))
    doc.set(node, "command", command)
    Path(err_path + ".proof.json").write_text(doc.dumps() + "\n")


def _proof(
    mode: String,
    out_path: String,
    err_path: String,
    proof: String,
    root: String,
    command: List[String],
) raises:
    """Check or bind the loop proof for one capture.

    Args:
        mode: `preflight` or `bind`.
        out_path: The standard-output file.
        err_path: The reduced capture.
        proof: The loop-proof receipt.
        root: The source root.
        command: The captured command.

    Raises:
        Error: If the proof check fails.
    """
    var side = err_path + ".proof.json"
    if mode == "preflight" and (islink(side) or exists(side)):
        remove(side)
    var proof_root = _resolve(root)
    var proof_build = _resolve(_parent(_resolve(proof)))
    var doc = _read_receipt(proof)
    var receipt = doc.at(doc.root, "receipt")
    _consumer(doc, receipt, proof_root)
    if mode == "bind":
        var again = _read_receipt(proof)
        if not _same_json(doc, doc.root, again, again.root):
            raise Error("Loop-proof binding changed during capture")
    _check_inputs(doc, receipt, proof_root, proof_build)
    var checked = _checked_command(
        doc, receipt, proof_root, proof_build, command, err_path, out_path
    )
    if mode == "bind":
        _bind_receipt(
            doc.text(doc.at(doc.root, "sha256")), err_path, out_path, checked
        )


def _compiled(command: List[String]) -> Bool:
    """Return whether `command` is an `aot` or `aot-hits` profile."""
    var profile = String()
    var named = False
    var index = 0
    while index < len(command):
        if (
            command[index] == "coverage_hit_aot"
            or command[index].endswith("/coverage_hit_aot.py")
            or command[index].endswith("coverage_hit_aot.py")
        ):
            named = True
        if command[index] == "--profile" and index + 1 < len(command):
            profile = command[index + 1]
        index += 1
    return named and (profile == "aot" or profile == "aot-hits")


def _file_stem(path: String) -> String:
    """Return `Path(path).stem`.

    Args:
        path: A path.

    Returns:
        The last component without its last suffix.
    """
    var slash = path.rfind("/")
    var name = path if slash < 0 else String(path[byte = slash + 1 :])
    var dot = name.rfind(".")
    if dot <= 0:
        return name
    return String(name[byte=:dot])


def _phases_path(out_path: String) raises -> String:
    """Return the absolute phase path beside `out_path`.

    Args:
        out_path: The standard-output file.

    Returns:
        `Path(out_path).with_suffix('.phases.jsonl').absolute()`. A link
        in the path stays unresolved.

    Raises:
        Error: If the working directory cannot be read.
    """
    var slash = out_path.rfind("/")
    var name = out_path if slash < 0 else String(out_path[byte = slash + 1 :])
    var head = "" if slash < 0 else String(out_path[byte = : slash + 1])
    var dot = name.rfind(".")
    var base = name
    if dot > 0:
        base = String(name[byte=:dot])
    var relative = head + base + ".phases.jsonl"
    if relative.startswith("/"):
        return relative
    var cwd = realpath(".")
    if cwd.endswith("/"):
        return cwd + relative
    return cwd + "/" + relative


def _unlink_name(path: String) raises:
    """Remove a file or symlink, as `Path.unlink(missing_ok=True)` does.

    Args:
        path: The path. A missing path stays missing.

    Raises:
        Error: With Python's `OSError` text when the name exists and
            cannot be removed.
    """
    try:
        remove_file(path)
    except error:
        var text = String(error)
        if text.find("No such file") < 0:
            raise error


def _exception_name(error: Error) -> String:
    """Return the class name at the start of `error`.

    Args:
        error: An error whose text starts with `Name:`.

    Returns:
        That name, or `OSError` when the text has none.
    """
    var text = String(error)
    var colon = text.find(":")
    if colon > 0:
        return String(text[byte=:colon])
    return "OSError"


def _header_json(
    suite: String, proof_sha: String, command: List[String]
) -> String:
    """Return one phase header line, as `json.dumps` writes it.

    Args:
        suite: `Path(out_path).stem`.
        proof_sha: The receipt digest, or empty for JSON null.
        command: The captured command.

    Returns:
        The header object and its trailing newline.
    """
    var proof_text = "null"
    if proof_sha.byte_length() > 0:
        proof_text = quote_ascii(proof_sha)
    var words = String("[")
    var index = 0
    for word in command:
        if index > 0:
            words += ", "
        words += quote_ascii(word)
        index += 1
    words += "]"
    var digest = sha256_hex(words.as_bytes())
    return (
        '{"schema": "coverage-exec-phases-v1", "suite": '
        + quote_ascii(suite)
        + ', "phase": "capture_header", "proof_sha256": '
        + proof_text
        + ', "command_sha256": "'
        + digest
        + '", "semantics": "launch requests only; missing finish means'
        ' incomplete"}\n'
    )


def _universal_lines(text: String) -> List[String]:
    """Split text as a Python text-mode file does.

    Args:
        text: Decoded text.

    Returns:
        Each line. CR LF, CR and LF become LF. A final line with no break
        keeps its text.
    """
    var lines = List[String]()
    var bytes = text.as_bytes()
    var start = 0
    var index = 0
    var size = len(bytes)
    while index < size:
        var byte = bytes[index]
        if byte == 10 or byte == 13:
            lines.append(String(text[byte=start:index]) + "\n")
            index += 1
            if byte == 13 and index < size and bytes[index] == 10:
                index += 1
            start = index
            continue
        index += 1
    if start < size:
        lines.append(String(text[byte=start:size]))
    return lines^


def _last_text(lines: List[String], count: Int) -> String:
    """Join the last `count` lines.

    Args:
        lines: The lines. A line keeps its newline when it had one.
        count: How many lines to keep.

    Returns:
        The joined tail. It is empty when `lines` is empty.
    """
    var start = 0
    if len(lines) > count:
        start = len(lines) - count
    var out = String()
    while start < len(lines):
        out += lines[start]
        start += 1
    return out^


def _read_path(path: String) raises -> List[UInt8]:
    """Read every byte of a file.

    Args:
        path: The file.

    Returns:
        Its bytes.

    Raises:
        Error: If the file cannot be opened or read.
    """
    var fd = open_at(at_cwd(), c_bytes(path), 0)
    if fd < 0:
        raise Error("cannot read " + path + ": " + strerror(errno()))
    var out = List[UInt8]()
    try:
        while True:
            var block = read_some(fd, 4096)
            if len(block) == 0:
                break
            var index = 0
            while index < len(block):
                out.append(block[index])
                index += 1
    finally:
        close_fd(fd)
    return out^


def _failure_tail(
    command: List[String], out_path: String, reduced: String
) raises:
    """Print the last lines of a failed capture.

    Args:
        command: The captured command. The message names its last word.
        out_path: The standard-output file.
        reduced: The reduced standard error.

    Raises:
        Error: If the standard-output file cannot be read.
    """
    print(command[len(command) - 1] + " failed under instrumentation:")
    var raw = _read_path(out_path)
    print(
        _last_text(_universal_lines(String(from_utf8_lossy=Span(raw))), 30),
        end="",
    )
    var kept = List[String]()
    for line in _universal_lines(reduced):
        if not line.startswith("COV"):
            kept.append(line)
    print(_last_text(kept, 30), end="")


struct PhaseWatch(ImplicitlyCopyable, Movable):
    """The phase file a compiled capture must finish."""

    var path: String
    """The phase file, or empty when this capture keeps none."""
    var device: UInt64
    """The device recorded when the header was replaced into place."""
    var inode: UInt64
    """The inode recorded when the header was replaced into place."""
    var active: Bool
    """True when a header was published."""

    def __init__(out self):
        """Make an inactive watch."""
        self.path = ""
        self.device = 0
        self.inode = 0
        self.active = False


def _phase_header(
    command: List[String], out_path: String, proof: String
) -> PhaseWatch:
    """Replace the phase file when this capture is compiled.

    A raw capture still removes an old phase file. The published
    `proof_sha256` is the receipt digest. A write failure prints
    `phase diagnostics unavailable` and leaves the capture running.

    Args:
        command: The captured command.
        out_path: The standard-output file.
        proof: The loop-proof path, or empty.

    Returns:
        The watch. It is inactive when this capture keeps no phases.
    """
    _ = unsetenv(_PHASE)
    _ = unsetenv(_PHASE + "_DEVICE")
    _ = unsetenv(_PHASE + "_INODE")
    var temporary = String()
    try:
        var path = _phases_path(out_path)
        _unlink_name(path)
        if not _compiled(command):
            return PhaseWatch()
        var proof_sha = String()
        if proof.byte_length() > 0:
            var doc = _read_receipt(proof)
            proof_sha = doc.text(doc.at(doc.root, "sha256"))
        var slash = path.rfind("/")
        var directory = "." if slash < 0 else String(path[byte=:slash])
        if directory.byte_length() == 0:
            directory = "/"
        var name = path if slash < 0 else String(path[byte = slash + 1 :])
        temporary = make_temporary(directory, name + ".", "")
        Path(temporary).write_text(
            _header_json(_file_stem(out_path), proof_sha, command)
        )
        var info = lstat_id(temporary)
        replace_file(temporary, path)
        _ = setenv(_PHASE, path, True)
        _ = setenv(_PHASE + "_DEVICE", String(info.device), True)
        _ = setenv(_PHASE + "_INODE", String(info.inode), True)
        var watch = PhaseWatch()
        watch.path = path
        watch.device = info.device
        watch.inode = info.inode
        watch.active = True
        return watch
    except error:
        if temporary.byte_length() > 0:
            try:
                remove_file(temporary)
            except:
                pass
        print(
            "Coverage "
            + _file_stem(out_path)
            + ": phase diagnostics unavailable ("
            + _exception_name(error)
            + "); ignore any existing phase file"
        )
        return PhaseWatch()


def _read_limit(fd: Int, limit: Int) raises -> List[UInt8]:
    """Read at most `limit` bytes, plus one when the file is longer.

    Args:
        fd: The descriptor.
        limit: The largest accepted size.

    Returns:
        The bytes read. One extra byte means the file is too long.

    Raises:
        Error: With Python's `OSError` text if a read fails.
    """
    var out = List[UInt8]()
    while len(out) <= limit:
        var block = read_some(fd, 4096)
        if len(block) == 0:
            return out^
        var index = 0
        while index < len(block) and len(out) <= limit:
            out.append(block[index])
            index += 1
    return out^


def _require_finish(watch: PhaseWatch) raises:
    """Raise unless the phase file still holds a complete finish record.

    Args:
        watch: The published header.

    Raises:
        Error: `OSError` when the file cannot be read, `JSONDecodeError`
            when the last line is not JSON, and `ValueError` when the
            finish record is missing or the file identity changed.
    """
    var flags = o_rdonly() | o_nonblock() | o_nofollow_flag()
    var fd = open_at(at_cwd(), c_bytes(watch.path), flags)
    if fd < 0:
        raise os_error(errno(), watch.path)
    var data: List[UInt8]
    try:
        var info = fstat_id(fd)
        if (
            not info.is_regular()
            or info.device != watch.device
            or info.inode != watch.inode
        ):
            raise Error("ValueError: phase file identity changed")
        data = _read_limit(fd, 128 * 1024)
    finally:
        close_fd(fd)
    if len(data) > 128 * 1024 or len(data) == 0 or data[len(data) - 1] != 10:
        raise Error("ValueError: phase file is incomplete")
    var text = String(from_utf8_lossy=Span(data))
    var parts = text.split("\n")
    if len(parts) < 2:
        raise Error("ValueError: phase file is incomplete")
    var last = String(parts[len(parts) - 2])
    var doc: PyJson
    try:
        doc = PyJson.parse(last)
    except error:
        raise Error("JSONDecodeError: " + String(error))
    var schema = doc.get(doc.root, "schema")
    var phase = doc.get(doc.root, "phase")
    var done = doc.get(doc.root, "diagnostics_complete")
    if (
        schema == MISSING
        or phase == MISSING
        or done == MISSING
        or doc.kind(schema) != PY_STR
        or doc.text(schema) != "coverage-exec-phases-v1"
        or doc.kind(phase) != PY_STR
        or doc.text(phase) != "adapter_finish"
        or doc.kind(done) != PY_BOOL
        or not doc.flag(done)
    ):
        raise Error("ValueError: no complete adapter finish")


def _finish_phases(watch: PhaseWatch):
    """Report a compiled capture whose phase file has no finish record.

    Args:
        watch: The header published for this capture. An inactive watch
            prints nothing.
    """
    if not watch.active:
        return
    try:
        _require_finish(watch)
    except error:
        print(
            "Coverage "
            + _file_stem(watch.path)
            + ": phase diagnostics incomplete ("
            + _exception_name(error)
            + "); last launch request is advisory"
        )


def _release_capture(folder: String) raises:
    """Remove the capture's private temporary root.

    Args:
        folder: The directory created for this capture.

    Raises:
        Error: If the removal command cannot start or remove the directory.
    """
    _ = unsetenv("TMPDIR")
    _ = unsetenv("THREEMOJO_TEST_TMPDIR")
    _ = unsetenv("MODULAR_CACHE_DIR")
    _ = unsetenv("XDG_CACHE_HOME")
    var removed = run_program(["rm", "-rf", folder], 30.0)
    if removed.status != 0:
        raise Error(removed.output)


def _start(command: List[String], output: Int) raises -> Tuple[Int, Int]:
    """Start `command` in a new session.

    Args:
        command: The program and its arguments.
        output: The standard-output descriptor.

    Returns:
        The process id and the standard-error read end.

    Raises:
        Error: If the program cannot start.
    """
    var plan = ExecPlan(command)
    var errors = make_pipe()
    var report_pipe = make_pipe()
    var report = List[Int32](length=1, fill=0)
    var pid = Int(external_call["fork", c_int]())
    if pid == 0:
        _ = external_call["setsid", c_int]()
        _ = external_call["dup2", c_int](c_int(output), c_int(1))
        _ = external_call["dup2", c_int](c_int(errors[1]), c_int(2))
        close_fd(output)
        close_fd(errors[0])
        close_fd(errors[1])
        close_fd(report_pipe[0])
        report[0] = Int32(plan.run())
        _ = external_call["write", Int](
            Int32(report_pipe[1]),
            OpaquePointer[MutAnyOrigin](
                unsafe_from_address=Int(report.unsafe_ptr())
            ),
            4,
        )
        external_call["_exit", NoneType](c_int(127))
    var fork_error = errno()
    close_fd(report_pipe[1])
    close_fd(errors[1])
    close_fd(output)
    if pid < 0:
        close_fd(errors[0])
        close_fd(report_pipe[0])
        raise Error("fork failed: " + strerror(fork_error))
    var got = 0
    while True:
        var count = external_call["read", Int](
            Int32(report_pipe[0]),
            OpaquePointer[MutAnyOrigin](
                unsafe_from_address=Int(report.unsafe_ptr()) + got
            ),
            4 - got,
        )
        if count > 0:
            got += count
            if got == 4:
                break
            continue
        if count < 0 and errno() == 4:
            continue
        break
    close_fd(report_pipe[0])
    if got == 4:
        _ = wait_blocking(pid)
        close_fd(errors[0])
        raise Error(
            "cannot start " + command[0] + ": " + strerror(Int(report[0]))
        )
    return (pid, errors[0])


def _emit(text: String):
    """Write `text` and a newline to standard output without buffering.

    Args:
        text: One progress line, without its newline.
    """
    var bytes = List[UInt8]()
    for byte in text.as_bytes():
        bytes.append(byte)
    bytes.append(10)
    var pending = len(bytes)
    var sent = 0
    while sent < pending:
        var count = external_call["write", Int](
            Int32(1),
            OpaquePointer[MutAnyOrigin](
                unsafe_from_address=Int(bytes.unsafe_ptr()) + sent
            ),
            pending - sent,
        )
        if count < 0:
            if errno() == 4:
                continue
            return
        if count == 0:
            return
        sent += count


def _progress(
    suite: String,
    stage: String,
    started: Float64,
    records: Int,
    saw_probe: Bool,
):
    """Print one capture progress line.

    Args:
        suite: The capture stem.
        stage: `start`, `running`, `first probe`, `complete`, or `aborted`.
        started: The monotonic time the capture started.
        records: How many standard-error lines have been read.
        saw_probe: True after the first coverage record.
    """
    var phase = "waiting for probes (compile/startup)"
    if saw_probe:
        phase = "runtime probes observed"
    _emit(
        "Coverage "
        + suite
        + ": "
        + stage
        + "; "
        + _tenth(_now() - started)
        + "s; "
        + phase
        + "; "
        + String(records)
        + " stderr records"
    )


def _read_lines(
    pid: Int,
    fd: Int,
    mut reducer: Reducer,
    deadline: Float64,
    started: Float64,
    suite: String,
    interval: Float64,
) raises -> Int:
    """Read the child's standard error until it ends or the deadline passes.

    Args:
        pid: The session leader.
        fd: The standard-error read end.
        reducer: The probe reducer.
        deadline: The monotonic deadline, or a negative value when none is set.
        started: The monotonic time the capture started.
        suite: The capture stem, used in progress lines.
        interval: The seconds between running lines.

    Returns:
        The child's status, or 124 when the deadline wins.

    Raises:
        Error: If a probe record is malformed or the wait fails.
    """
    var poll = List[Int32](length=2, fill=0)
    var chunk = List[UInt8](length=4096, fill=0)
    var pending = String()
    var announced = False
    var next_progress = started + interval
    var cancelled = False
    while True:
        if _now() >= next_progress:
            _progress(
                suite, "running", started, reducer.records, reducer.saw_probe
            )
            next_progress = _now() + interval
        var limit = 0.05
        if deadline >= 0:
            limit = deadline - _now()
            if limit <= 0:
                _ = signal_group(pid, SIGKILL)
                cancelled = True
                break
            if limit > 0.05:
                limit = 0.05
        var until_progress = next_progress - _now()
        if until_progress < limit:
            limit = until_progress
        if limit < 0.001:
            limit = 0.001
        poll[0] = Int32(fd)
        poll[1] = Int32(1)
        var ready = external_call["poll", c_int](
            OpaquePointer[MutAnyOrigin](
                unsafe_from_address=Int(poll.unsafe_ptr())
            ),
            c_int(1),
            c_int(Int(limit * 1000.0) + 1),
        )
        if ready < 0:
            if errno() == 4:
                continue
            raise Error("poll failed: " + strerror(errno()))
        if ready == 0:
            continue
        var count = external_call["read", Int](
            Int32(fd),
            OpaquePointer[MutAnyOrigin](
                unsafe_from_address=Int(chunk.unsafe_ptr())
            ),
            4096,
        )
        if count < 0:
            if errno() == 4:
                continue
            raise Error("read failed: " + strerror(errno()))
        if count == 0:
            break
        var raw = List[UInt8]()
        var offset = 0
        while offset < count:
            raw.append(chunk[offset])
            offset += 1
        var piece = String(from_utf8_lossy=Span(raw))
        pending += piece
        while True:
            var at = pending.find("\n")
            if at < 0:
                break
            var end = at + 1
            var line = String(pending[byte=:end])
            var rest = String(pending[byte=end:])
            pending = rest
            reducer.feed(line)
            if not announced and reducer.saw_probe:
                announced = True
                _progress(
                    suite,
                    "first probe",
                    started,
                    reducer.records,
                    True,
                )
    if pending.byte_length() > 0:
        reducer.feed(pending)
        if not announced and reducer.saw_probe:
            _progress(suite, "first probe", started, reducer.records, True)
    close_fd(fd)
    var waited = wait_blocking(pid)
    if cancelled:
        return 124
    if not waited.done:
        raise Error("wait failed: " + strerror(waited.error))
    if waited.status < 0:
        return 128 - waited.status
    return waited.status


def _capture(arguments: List[String]) raises -> Int:
    """Run one capture described by `arguments`.

    Args:
        arguments: The arguments after `capture`, without the program name.

    Returns:
        The captured command's status.

    Raises:
        Error: If the command line, the proof, a probe record, or the
            private directory is wrong.
    """
    var out_path = String()
    var err_path = String()
    var proof = String()
    var root = "."
    var interval = 60.0
    var command = List[String]()
    var index = 0
    while index < len(arguments):
        var word = arguments[index]
        if word == "--":
            index += 1
            while index < len(arguments):
                command.append(arguments[index])
                index += 1
            break
        if (
            word == "--out"
            or word == "--err"
            or word == "--loop-proof"
            or word == "--loop-proof-root"
        ):
            if index + 1 >= len(arguments):
                raise Error(word + " needs a value")
            var value = arguments[index + 1]
            if word == "--out":
                out_path = value
            elif word == "--err":
                err_path = value
            elif word == "--loop-proof":
                proof = value
            else:
                root = value
            index += 2
            continue
        if word == "--progress-seconds":
            if index + 1 >= len(arguments):
                raise Error(word + " needs a value")
            interval = parse_float(arguments[index + 1])
            index += 2
            continue
        if word.startswith("--progress-seconds="):
            interval = parse_float(String(word[byte=19:]))
            index += 1
            continue
        if word == "--help" or word == "-h":
            raise Error(_usage())
        raise Error("unknown argument " + word)
    if (
        out_path.byte_length() == 0
        or err_path.byte_length() == 0
        or len(command) == 0
    ):
        raise Error(_usage())
    if not (interval == interval) or interval <= 0 or interval > 1e300:
        raise Error("progress interval must be positive")
    if proof.byte_length() > 0:
        _proof("preflight", out_path, err_path, proof, root, command)
    var deadline = Float64(-1)
    var text = getenv(_DEADLINE, "")
    if text.byte_length() > 0:
        deadline = parse_float(text)
        if not (deadline == deadline) or deadline > 1e300 or deadline < -1e300:
            raise Error("coverage deadline must be finite")
    var parent = getenv("TMPDIR")
    var folder: String
    if parent:
        folder = mkdtemp(prefix="threemojo-test-", dir=parent)
    else:
        folder = mkdtemp(prefix="threemojo-test-")
    var private: String
    try:
        private = realpath(folder)
    except error:
        _ = run_program(["rm", "-rf", folder], 30.0)
        raise error
    var compiler = private + "/mojo-cache"
    var xdg = private + "/xdg-cache"
    var made = run_program(["mkdir", "-p", compiler, xdg], 10.0)
    if made.status != 0:
        _ = run_program(["rm", "-rf", folder], 30.0)
        raise Error(made.output)
    _ = setenv("TMPDIR", private, True)
    _ = setenv("THREEMOJO_TEST_TMPDIR", private, True)
    _ = setenv("MODULAR_CACHE_DIR", compiler, True)
    _ = setenv("XDG_CACHE_HOME", xdg, True)
    var started = _now()
    var suite = _stem(out_path)
    _progress(suite, "start", started, 0, False)
    var records = 0
    var saw_probe = False
    var reduced = String()
    var watch = _phase_header(command, out_path, proof)
    var status = 124
    try:
        if deadline >= 0 and _now() >= deadline:
            Path(out_path).write_text("")
            _gzip("", err_path)
        else:
            var output = _open_output(out_path)
            var child = _start(command, output)
            var reducer = Reducer()
            status = _read_lines(
                child[0],
                child[1],
                reducer,
                deadline,
                started,
                suite,
                interval,
            )
            records = reducer.records
            saw_probe = reducer.saw_probe
            reduced = reducer.output
            _gzip(reduced, err_path)
        _progress(
            suite,
            "complete (exit " + String(status) + ")",
            started,
            records,
            saw_probe,
        )
        if status != 0:
            _failure_tail(command, out_path, reduced)
        elif proof.byte_length() > 0:
            _proof("bind", out_path, err_path, proof, root, command)
    except error:
        _progress(suite, "aborted", started, records, saw_probe)
        _finish_phases(watch)
        _release_capture(folder)
        raise error
    _finish_phases(watch)
    _release_capture(folder)
    return status


def _sort_paths(mut names: List[String]):
    """Sort paths in byte order."""
    var index = 1
    while index < len(names):
        var item = names[index]
        var place = index
        while place > 0 and names[place - 1] > item:
            names[place] = names[place - 1]
            place -= 1
        names[place] = item
        index += 1


def _captures(directory: String) raises -> List[String]:
    """Return the `.txt.gz` captures in `directory`, in byte order.

    Args:
        directory: The capture directory.

    Returns:
        The capture paths.

    Raises:
        Error: If the directory cannot be read, or it has no captures.
    """
    var names = List[String]()
    for name in listdir(directory):
        var text = String(name)
        if text.endswith(".txt.gz"):
            names.append(directory + "/" + text)
    if len(names) == 0:
        raise Error("no coverage captures were found")
    _sort_paths(names)
    return names^


def _fifo(path: String) raises:
    """Create a FIFO at `path`.

    Args:
        path: The FIFO path.

    Raises:
        Error: If `mkfifo` fails.
    """
    var name = c_bytes(path)
    if (
        external_call["mkfifo", c_int](
            OpaquePointer[MutAnyOrigin](
                unsafe_from_address=Int(name.unsafe_ptr())
            ),
            c_int(420),
        )
        != 0
    ):
        raise Error("cannot create " + path + ": " + strerror(errno()))


def _open_reader(path: String, pid: Int, mut reaped: List[Int]) raises -> Int:
    """Open a FIFO for writing once its reader is waiting.

    Args:
        path: The FIFO.
        pid: The reporter. A finished reporter ends the wait.
        reaped: Set to the reporter status when `try_wait` reaps it.

    Returns:
        The write descriptor, or -1 when the reporter has finished.

    Raises:
        Error: If the open fails for a reason other than a missing reader.
    """
    var flags = 1 | 0x800
    if not CompilationTarget.is_linux():
        flags = 1 | 4
    var spins = 0
    while spins < 1000:
        var waited = try_wait(pid)
        if waited.done:
            var code = waited.status
            if code < 0:
                code = 128 - code
            reaped[0] = code
            return -1
        var fd = open_at(at_cwd(), c_bytes(path), flags)
        if fd >= 0:
            close_fd(fd)
            return open_at(at_cwd(), c_bytes(path), 1)
        if errno() != 6:
            raise Error("cannot open " + path + ": " + strerror(errno()))
        _ = external_call["usleep", c_int](UInt32(10000))
        spins += 1
    raise Error("the reporter did not open " + path)


def _replay(command: List[String], captures: List[String]) raises -> Int:
    """Feed each capture through a FIFO, in order, to `command`.

    Args:
        command: The reporter.
        captures: The gzip captures, already sorted.

    Returns:
        The reporter's status, or 1 when a capture cannot be replayed.

    Raises:
        Error: If a FIFO cannot be created.
    """
    var folder = mkdtemp(prefix="threemojo-coverage-")
    var pipes = List[String]()
    var index = 0
    while index < len(captures):
        var path = folder + "/" + String(index)
        _fifo(path)
        pipes.append(path)
        index += 1
    var reporter = List[String]()
    for word in command:
        reporter.append(word)
    for path in pipes:
        reporter.append(path)
    var pid = spawn(reporter, SignalHold(), -1, False)
    var reaped = List[Int]()
    reaped.append(-1)
    var failed = False
    index = 0
    while index < len(pipes):
        var fd = _open_reader(pipes[index], pid, reaped)
        if fd < 0:
            break
        var gzip_pid = spawn(
            ["gzip", "-dc", captures[index]], SignalHold(), fd, False
        )
        var gzip_done = wait_blocking(gzip_pid)
        close_fd(fd)
        if not gzip_done.done or gzip_done.status != 0:
            failed = True
            _ = signal_group(pid, SIGKILL)
            break
        index += 1
    if reaped[0] >= 0:
        _ = run_program(["rm", "-rf", folder], 30.0)
        return reaped[0]
    var done = wait_blocking(pid)
    _ = run_program(["rm", "-rf", folder], 30.0)
    if failed:
        print("Coverage replay failed", file=stderr)
        return 1
    if not done.done:
        raise Error("wait failed: " + strerror(done.error))
    if done.status < 0:
        return 128 - done.status
    return done.status


def _report(arguments: List[String]) raises -> Int:
    """Replay captures for one report command.

    Args:
        arguments: The arguments after `report`.

    Returns:
        The reporter's status.

    Raises:
        Error: If the command line or the proof check is wrong.
    """
    var directory = String()
    var proof_root = String()
    var proof_build = String()
    var compiler = String()
    var flags = String()
    var mojo = String()
    var cache = String()
    var suites = List[String]()
    var command = List[String]()
    var taking_suites = False
    var index = 0
    while index < len(arguments):
        var word = arguments[index]
        if word == "--":
            index += 1
            while index < len(arguments):
                command.append(arguments[index])
                index += 1
            break
        if taking_suites and not word.startswith("--"):
            suites.append(word)
            index += 1
            continue
        taking_suites = False
        if word.startswith("--compiler="):
            compiler = String(word[byte=11:])
        elif word.startswith("--flags="):
            flags = String(word[byte=8:])
        elif word.startswith("--mojo="):
            mojo = String(word[byte=7:])
        elif word.startswith("--capture-cache="):
            cache = String(word[byte=16:])
        elif word == "--capture-dir":
            directory = arguments[index + 1]
            index += 1
        elif word == "--loop-proof-root":
            proof_root = arguments[index + 1]
            index += 1
        elif word == "--loop-proof-build":
            proof_build = arguments[index + 1]
            index += 1
        elif word == "--compiler":
            compiler = arguments[index + 1]
            index += 1
        elif word == "--flags":
            flags = arguments[index + 1]
            index += 1
        elif word == "--mojo":
            mojo = arguments[index + 1]
            index += 1
        elif word == "--capture-cache":
            cache = arguments[index + 1]
            index += 1
        elif word == "--suites":
            taking_suites = True
        elif word == "--help" or word == "-h":
            raise Error(
                "usage: coverage_io report --capture-dir DIR -- COMMAND..."
            )
        else:
            raise Error("unknown argument " + word)
        index += 1
    if directory.byte_length() == 0 or len(command) == 0:
        raise Error("usage: coverage_io report --capture-dir DIR -- COMMAND...")
    var captures = _captures(directory)
    var manifest = String()
    if proof_root.byte_length() > 0 or proof_build.byte_length() > 0:
        if proof_root.byte_length() == 0 or proof_build.byte_length() == 0:
            raise Error("both loop-proof root and build are required")
        var folder = mkdtemp(prefix="threemojo-loop-report-")
        manifest = folder + "/manifest.txt"
        var prepare = List[String]()
        prepare.append("sh")
        prepare.append("tools/tool.sh")
        if mojo.byte_length() > 0:
            prepare.append(mojo)
        else:
            prepare.append(".venv/bin/mojo")
        prepare.append("coverage_loop_seal")
        prepare.append("prepare-report")
        prepare.append("--capture-dir")
        prepare.append(directory)
        prepare.append("--loop-proof-root")
        prepare.append(proof_root)
        prepare.append("--loop-proof-build")
        prepare.append(proof_build)
        prepare.append("--manifest")
        prepare.append(manifest)
        prepare.append("--compiler=" + compiler)
        prepare.append("--flags=" + flags)
        if mojo.byte_length() > 0:
            prepare.append("--mojo")
            prepare.append(mojo)
        if cache.byte_length() > 0:
            prepare.append("--capture-cache")
            prepare.append(cache)
        if len(suites) > 0:
            prepare.append("--suites")
            for suite in suites:
                prepare.append(suite)
        prepare.append("--")
        for word in command:
            prepare.append(word)
        var ready = run_program(prepare, 180.0, merge_errors=False)
        if ready.output.byte_length() > 0:
            print(ready.output, end="")
        if ready.status != 0:
            _ = run_program(["rm", "-rf", folder], 30.0)
            raise Error(ready.errors)
    var reporter = List[String]()
    var last = len(command) - 1
    var cursor = 0
    while cursor < len(command):
        if cursor == last and manifest.byte_length() > 0:
            reporter.append(manifest)
        else:
            reporter.append(command[cursor])
        cursor += 1
    var status = _replay(reporter, captures)
    if manifest.byte_length() > 0:
        var finish = List[String]()
        finish.append("sh")
        finish.append("tools/tool.sh")
        if mojo.byte_length() > 0:
            finish.append(mojo)
        else:
            finish.append(".venv/bin/mojo")
        finish.append("coverage_loop_seal")
        finish.append("finish-report")
        finish.append("--capture-dir")
        finish.append(directory)
        finish.append("--loop-proof-root")
        finish.append(proof_root)
        finish.append("--loop-proof-build")
        finish.append(proof_build)
        finish.append("--compiler=" + compiler)
        finish.append("--flags=" + flags)
        if mojo.byte_length() > 0:
            finish.append("--mojo")
            finish.append(mojo)
        if cache.byte_length() > 0:
            finish.append("--capture-cache")
            finish.append(cache)
        if len(suites) > 0:
            finish.append("--suites")
            for suite in suites:
                finish.append(suite)
        var checked = run_program(finish, 180.0, merge_errors=False)
        var slash = manifest.rfind("/")
        if slash > 0:
            _ = run_program(["rm", "-rf", String(manifest[byte=:slash])], 30.0)
        if checked.status != 0:
            raise Error(checked.errors)
    return status


def _proof_flag(arguments: List[String], name: String) raises -> String:
    """Return the value of one proof flag.

    Args:
        arguments: The arguments after the mode.
        name: The flag.

    Returns:
        The value.

    Raises:
        Error: When the flag is absent.
    """
    var index = 0
    while index < len(arguments):
        if arguments[index] == "--":
            break
        if arguments[index] == name and index + 1 < len(arguments):
            return arguments[index + 1]
        index += 1
    raise Error(name + " needs a value")


def _proof_root(arguments: List[String]) -> String:
    """Return the proof root, or `.` when the flag is absent.

    Args:
        arguments: The arguments after the mode.

    Returns:
        The root.
    """
    var index = 0
    while index < len(arguments):
        if arguments[index] == "--":
            break
        if arguments[index] == "--loop-proof-root" and index + 1 < len(
            arguments
        ):
            return arguments[index + 1]
        index += 1
    return "."


def _proof_command(arguments: List[String]) raises -> List[String]:
    """Return the command after `--`.

    Args:
        arguments: The arguments after the mode.

    Returns:
        The command words.

    Raises:
        Error: When `--` is absent.
    """
    var command = List[String]()
    var index = 0
    var seen = False
    while index < len(arguments):
        if arguments[index] == "--":
            seen = True
            index += 1
            while index < len(arguments):
                command.append(arguments[index])
                index += 1
            break
        index += 1
    if not seen:
        raise Error("Coverage capture command identity is required")
    return command^


def main() raises:
    """Capture one suite, or replay captures to the reporter."""
    var arguments = List[String]()
    var given = argv()
    for index in range(1, len(given)):
        arguments.append(String(given[index]))
    try:
        if len(arguments) == 0:
            raise Error(_usage())
        var rest = List[String]()
        for index in range(1, len(arguments)):
            rest.append(arguments[index])
        if arguments[0] == "capture":
            exit(_capture(rest))
        if arguments[0] == "report":
            exit(_report(rest))
        if arguments[0] == "preflight" or arguments[0] == "bind":
            _proof(
                arguments[0],
                _proof_flag(rest, "--out"),
                _proof_flag(rest, "--err"),
                _proof_flag(rest, "--loop-proof"),
                _proof_root(rest),
                _proof_command(rest),
            )
            exit(0)
        raise Error(_usage())
    except error:
        print("coverage_io: " + String(error), file=stderr)
        var text = String(error)
        if text.startswith("usage:"):
            exit(2)
        exit(1)
