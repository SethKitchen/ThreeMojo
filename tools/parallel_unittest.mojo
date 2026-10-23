# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Run one directory's unittest tests in separate processes, several at once.

    parallel_unittest --jobs 4 tools/carla_lane_oracle

The CARLA oracle tests copy whole repository roots and replay proofs. Run
one after another, they exceed a CI job's time limit. A test without shared
set-up runs alone in its own process. Tests of one class with shared set-up
run a few at a time, so each process repeats that set-up. A module that
cannot be listed runs as one `python3 -m unittest discover` process.
`--shard I/N` keeps every N-th unit. A failing unit prints its output in
one piece. The exit status is nonzero when a unit fails or no test module
is found.
"""

from std.ffi import c_int, external_call
from std.os import listdir
from std.os.path import realpath
from std.pathlib import Path
from std.sys import argv, exit, stderr
from std.tempfile import mkdtemp
from std.time import perf_counter_ns

from tools._owned_process import c_bytes, errno, strerror, wait_blocking
from tools._process import shell_quote
from tools._python_json import PY_BOOL, loads

comptime CHUNK = 4
"""How many tests that share set-up run in one process."""

comptime _EXCLUSIVE = [
    (
        "test_coverage_invariant_contracts.CoverageInvariantContracts."
        "test_historical_direct_and_qualified_package_verification"
    ),
    (
        "test_coverage_invariant_contracts.CoverageInvariantContracts."
        "test_direct_and_qualified_package_verification"
    ),
    (
        "test_full_audit_cleanup_contracts.FullAuditCleanupContracts."
        "test_consumer_first_import_orders_normal_and_optimized"
    ),
    (
        "test_invariant_operation_inputs.OperationReachedBindingControls."
        "test_current_cold_routes_preserve_consumed_value_bindings"
    ),
]
"""Units that must not run beside another test process."""

comptime _LIST = (
    "import json, sys, unittest\n"
    "directory, name = sys.argv[1], sys.argv[2]\n"
    "suite = unittest.TestLoader().discover(directory, pattern=name,"
    " top_level_dir=directory)\n"
    "tests, broken = [], False\n"
    "def overridden(cls, name):\n"
    "    return getattr(cls, name).__func__ is not"
    " getattr(unittest.TestCase, name).__func__\n"
    "def walk(item):\n"
    "    global broken\n"
    "    if isinstance(item, unittest.TestSuite):\n"
    "        for child in item:\n"
    "            walk(child)\n"
    "        return\n"
    "    if type(item).__name__ in ('_FailedTest', 'ModuleImportFailure'):\n"
    "        broken = True\n"
    "    cls = type(item)\n"
    "    module = sys.modules.get(cls.__module__)\n"
    "    shared = bool(getattr(module, 'setUpModule', None) or"
    " getattr(module, 'tearDownModule', None)\n"
    "                  or overridden(cls, 'setUpClass') or"
    " overridden(cls, 'tearDownClass'))\n"
    "    tests.append([item.id(), shared])\n"
    "walk(suite)\n"
    "print(json.dumps({'tests': tests, 'broken': broken}))\n"
)
"""The Python program that lists one module's tests."""


struct Unit(Movable):
    """One process the runner starts."""

    var label: String
    """The text printed when the unit fails."""
    var command: List[String]
    """The program and its arguments."""

    def __init__(out self, label: String, var command: List[String]):
        """Store a unit.

        Args:
            label: The failure label.
            command: The program and its arguments.
        """
        self.label = label
        self.command = command^


struct UnitResult(Copyable, Movable):
    """What one finished unit left."""

    var label: String
    """The failure label."""
    var code: Int
    """The process status. A signal is negative, as Python reports it."""
    var seconds: Float64
    """The wall time from start to reap, in seconds."""
    var output: String
    """The standard output and standard error, merged."""

    def __init__(
        out self, label: String, code: Int, seconds: Float64, output: String
    ):
        """Store a result.

        Args:
            label: The failure label.
            code: The process status.
            seconds: The wall time in seconds.
            output: The merged output.
        """
        self.label = label
        self.code = code
        self.seconds = seconds
        self.output = output


struct RunReport(Movable):
    """The runner's exit status and the text it prints."""

    var code: Int
    """The exit status."""
    var output: String
    """The standard output."""
    var errors: String
    """The standard error."""

    def __init__(out self, code: Int, output: String, errors: String):
        """Store a report.

        Args:
            code: The exit status.
            output: The standard output.
            errors: The standard error.
        """
        self.code = code
        self.output = output
        self.errors = errors


def _pointer(address: Int) -> OpaquePointer[MutAnyOrigin]:
    """Return an address as a C pointer. Zero is `NULL`."""
    return OpaquePointer[MutAnyOrigin](unsafe_from_address=address)


def _sort_names(mut names: List[String]):
    """Sort file names in byte order."""
    var index = 1
    while index < len(names):
        var item = names[index]
        var place = index
        while place > 0 and names[place - 1] > item:
            names[place] = names[place - 1]
            place -= 1
        names[place] = item
        index += 1


def modules(directory: String) raises -> List[String]:
    """Return the `test_*.py` file names in one directory, sorted.

    Args:
        directory: The directory.

    Returns:
        The file names. A directory is not included.

    Raises:
        Error: If the directory cannot be read.
    """
    var names = List[String]()
    for name in listdir(directory):
        var text = String(name)
        if not (text.startswith("test_") and text.endswith(".py")):
            continue
        if Path(directory + "/" + text).is_file():
            names.append(text)
    _sort_names(names)
    return names^


def _class_of(test: String) -> String:
    """Return the module and class of a test id."""
    var dot = test.rfind(".")
    if dot < 0:
        return test
    return String(test[byte=:dot])


def _module_of(test: String) -> String:
    """Return the first component of a test id, plus `.py`."""
    var dot = test.find(".")
    var name = test if dot < 0 else String(test[byte=:dot])
    return name + ".py"


def is_exclusive(command: List[String]) -> Bool:
    """Return whether a command must run with no other test process.

    Args:
        command: The program and its arguments.

    Returns:
        True for a pinned proof, or for discovery of that proof's module.
    """
    for test in materialize[_EXCLUSIVE]():
        var index = 3
        while index < len(command):
            if command[index] == test:
                return True
            index += 1
        if (
            len(command) >= 4
            and command[3] == "discover"
            and len(command) >= 2
            and command[len(command) - 2] == "-p"
            and command[len(command) - 1] == _module_of(test)
        ):
            return True
    return False


def _script(directory: String, command: List[String], output: String) -> String:
    """Return a shell command that runs `command` and merges its output."""
    var text = "cd -- " + shell_quote(directory) + " && exec"
    for argument in command:
        text += " " + shell_quote(argument)
    text += " > " + shell_quote(output) + " 2>&1"
    return text


def _spawn(
    command: List[String], directory: String, output: String
) raises -> Int:
    """Start a command and return its process id.

    Args:
        command: The program and its arguments.
        directory: The working directory.
        output: The file that receives both output streams.

    Returns:
        The process id.

    Raises:
        Error: If the process cannot be created.
    """
    var file = c_bytes("/bin/sh")
    var flag = c_bytes("-c")
    var body = c_bytes(_script(directory, command, output))
    var pointers = List[Int]()
    pointers.append(Int(file.unsafe_ptr()))
    pointers.append(Int(flag.unsafe_ptr()))
    pointers.append(Int(body.unsafe_ptr()))
    pointers.append(0)
    var pid = Int(external_call["fork", c_int]())
    if pid == 0:
        _ = external_call["execv", c_int](
            _pointer(Int(file.unsafe_ptr())),
            _pointer(Int(pointers.unsafe_ptr())),
        )
        external_call["_exit", NoneType](c_int(127))
    if pid < 0:
        raise Error("fork failed: " + strerror(errno()))
    return pid


def _read(path: String) raises -> String:
    """Return a file's text."""
    return Path(path).read_text()


def run_unit(
    directory: String, label: String, command: List[String]
) raises -> UnitResult:
    """Run one unit in `directory`.

    Args:
        directory: The working directory.
        label: The failure label.
        command: The program and its arguments.

    Returns:
        The label, the status, the seconds and the merged output.

    Raises:
        Error: If the process cannot be created or its output cannot be read.
    """
    var folder = mkdtemp(prefix="parallel-unit-")
    var output = folder + "/output"
    Path(output).write_text("")
    var started = perf_counter_ns()
    var pid = _spawn(command, directory, output)
    var waited = wait_blocking(pid)
    var seconds = Float64(perf_counter_ns() - started) / 1e9
    var text = _read(output)
    return UnitResult(label, waited.status, seconds, text)


def _append_unit(
    mut result: List[Unit], mut group: List[String], python: String
):
    """Move `group` into `result` as one unittest command."""
    if len(group) == 0:
        return
    var label = group[0]
    if len(group) != 1:
        label += " (+" + String(len(group) - 1) + ")"
    var command = List[String]()
    command.append(python)
    command.append("-m")
    command.append("unittest")
    for test in group:
        command.append(test)
    result.append(Unit(label, command^))
    group.clear()


def _listed_tests(
    output: String,
) raises -> Tuple[List[String], List[Bool], Bool]:
    """Read the listing program's last line.

    Args:
        output: The merged output.

    Returns:
        The test ids, whether each shares set-up, and whether the listing
        is unusable.

    Raises:
        Error: Never. Bad JSON is an unusable listing.
    """
    var ids = List[String]()
    var shared = List[Bool]()
    var lines = output.splitlines()
    if len(lines) == 0:
        return (ids^, shared^, True)
    var line = String(lines[len(lines) - 1])
    try:
        var document = loads(line.as_bytes())
        var tests = document.at(document.root, "tests")
        var broken = document.at(document.root, "broken")
        if document.kind(broken) != PY_BOOL:
            return (ids^, shared^, True)
        var count = document.length(tests)
        for index in range(count):
            var pair = document.item(tests, index)
            ids.append(document.text(document.item(pair, 0)))
            shared.append(document.flag(document.item(pair, 1)))
        return (ids^, shared^, document.flag(broken))
    except:
        return (ids^, shared^, True)


def units(
    directory: String, name: String, python: String = "python3"
) raises -> List[Unit]:
    """Return the commands that together run every test of one module.

    Args:
        directory: The directory that holds the module.
        name: The module file name.
        python: The Python program. It is `python3` when omitted.

    Returns:
        One command per process. A module that cannot be listed is one
        `unittest discover` command.

    Raises:
        Error: If the listing process cannot be created.
    """
    var command = List[String]()
    command.append(python)
    command.append("-c")
    command.append(_LIST)
    command.append(directory)
    command.append(name)
    var listed = run_unit(directory, name, command)
    var parsed = _listed_tests(listed.output)
    if parsed[2] or listed.code != 0 or len(parsed[0]) == 0:
        var discover = List[String]()
        discover.append(python)
        discover.append("-m")
        discover.append("unittest")
        discover.append("discover")
        discover.append("-s")
        discover.append(directory)
        discover.append("-p")
        discover.append(name)
        var fallback = List[Unit]()
        fallback.append(Unit(name, discover^))
        return fallback^
    var result = List[Unit]()
    var group = List[String]()
    for index in range(len(parsed[0])):
        var test = parsed[0][index]
        var shares = parsed[1][index]
        if len(group) > 0 and (
            not shares
            or len(group) == CHUNK
            or _class_of(test) != _class_of(group[0])
        ):
            _append_unit(result, group, python)
        group.append(test)
        if not shares:
            _append_unit(result, group, python)
    _append_unit(result, group, python)
    return result^


def parse_shard(text: String) raises -> Tuple[Int, Int]:
    """Parse canonical `I/N` with `1 <= I <= N`.

    Args:
        text: The shard text.

    Returns:
        The index and the count.

    Raises:
        Error: If the text is not canonical `I/N` in that range.
    """
    var slash = text.find("/")
    if slash < 1 or text.find("/") != text.rfind("/"):
        raise Error("--shard must be I/N")
    var left = String(text[byte=:slash])
    var right = String(text[byte = slash + 1 :])
    var index = _positive(left)
    var count = _positive(right)
    if index < 0 or count < 0:
        raise Error("--shard must be I/N")
    if text != String(index) + "/" + String(count):
        raise Error("--shard must be canonical I/N")
    if not (index >= 1 and index <= count):
        raise Error("--shard must be I/N with 1 <= I <= N")
    return (index, count)


def _positive(text: String) -> Int:
    """Return a positive decimal integer, or -1."""
    if text.byte_length() == 0:
        return -1
    var value = 0
    for byte in text.as_bytes():
        if byte < 48 or byte > 57:
            return -1
        value = value * 10 + Int(byte) - 48
    return value


def _seconds_text(seconds: Float64) -> String:
    """Return a nonnegative duration rounded to a whole second."""
    if not seconds > 0:
        return "0"
    return String(Int(seconds + 0.5))


def _print_failure(mut output: String, result: UnitResult):
    """Append one failure block."""
    output += (
        "== "
        + result.label
        + " ("
        + _seconds_text(result.seconds)
        + " s, exit "
        + String(result.code)
        + ")\n"
    )
    output += result.output
    if result.output.byte_length() == 0 or not result.output.endswith("\n"):
        output += "\n"


def _reap(
    pid: Int, label: String, started: Int, output: String
) raises -> UnitResult:
    """Wait for one child and read its output.

    Args:
        pid: The process id.
        label: The failure label.
        started: `perf_counter_ns` at spawn.
        output: The output file.

    Returns:
        The unit result.

    Raises:
        Error: If the output cannot be read.
    """
    var waited = wait_blocking(pid)
    var seconds = Float64(perf_counter_ns() - started) / 1e9
    return UnitResult(label, waited.status, seconds, _read(output))


def _run_parallel(
    directory: String, var work: List[Unit], jobs: Int, folder: String
) raises -> List[UnitResult]:
    """Run units with at most `jobs` processes, and keep their start order.

    Args:
        directory: The working directory.
        work: The units.
        jobs: The maximum number of processes.
        folder: A directory for output files.

    Returns:
        The results in the order of `work`.

    Raises:
        Error: If a process cannot be created or its output cannot be read.
    """
    var results = List[UnitResult]()
    var pids = List[Int]()
    var labels = List[String]()
    var started_at = List[Int]()
    var outputs = List[String]()
    var next = 0
    var head = 0
    var limit = jobs if jobs > 0 else 1
    while next < len(work) or head < len(pids):
        while next < len(work) and len(pids) - head < limit:
            var output = folder + "/unit-" + String(next)
            Path(output).write_text("")
            var command = _copy_command(work[next].command)
            var pid = _spawn(command, directory, output)
            pids.append(pid)
            labels.append(work[next].label)
            started_at.append(perf_counter_ns())
            outputs.append(output)
            next += 1
        if head >= len(pids):
            break
        results.append(
            _reap(pids[head], labels[head], started_at[head], outputs[head])
        )
        head += 1
    return results^


def execute(
    directory: String, var work: List[Unit], jobs: Int
) raises -> List[UnitResult]:
    """Run exclusive units first, then the others, at most `jobs` at once.

    Args:
        directory: The working directory.
        work: The units, already sharded.
        jobs: The maximum number of ordinary processes.

    Returns:
        Exclusive results in encounter order, then the ordinary results in
        their input order.

    Raises:
        Error: If a process cannot be created.
    """
    var exclusive = List[Unit]()
    var ordinary = List[Unit]()
    var index = 0
    while index < len(work):
        var command = _copy_command(work[index].command)
        if is_exclusive(command):
            exclusive.append(Unit(work[index].label, command^))
        else:
            ordinary.append(Unit(work[index].label, command^))
        index += 1
    var folder = mkdtemp(prefix="parallel-unittest-")
    var results = _run_parallel(directory, exclusive^, 1, folder)
    var rest = _run_parallel(directory, ordinary^, jobs, folder)
    results.extend(rest^)
    return results^


def _copy_command(command: List[String]) -> List[String]:
    """Return a command's arguments."""
    var copy = List[String]()
    for word in command:
        copy.append(word)
    return copy^


def _select(var work: List[Unit], index: Int, count: Int) -> List[Unit]:
    """Keep every `count`-th unit, starting at `index`.

    Args:
        work: The units, in module order.
        index: The shard, starting at 1.
        count: The number of shards.

    Returns:
        The units of this shard, in the same order.
    """
    var selected = List[Unit]()
    var place = index - 1
    while place < len(work):
        var command = _copy_command(work[place].command)
        selected.append(Unit(work[place].label, command^))
        place += count
    return selected^


def _integer_argument(text: String) raises -> Int:
    """Return a decimal integer.

    Args:
        text: The argument.

    Returns:
        The integer.

    Raises:
        Error: If `text` is not an integer.
    """
    var value = _positive(text)
    if value < 0:
        raise Error("expected an integer, not " + text)
    return value


def run(arguments: List[String]) raises -> RunReport:
    """Run the tests named by the command line.

    Args:
        arguments: `--jobs N`, `--shard I/N`, and one directory.

    Returns:
        The exit status and the printed text. A bad command line has
        status 2.

    Raises:
        Error: If a process or a directory cannot be used.
    """
    var jobs = 4
    var shard_text = "1/1"
    var directory = String()
    var index = 0
    while index < len(arguments):
        var word = arguments[index]
        if word == "--jobs" or word == "--shard":
            if index + 1 >= len(arguments):
                return RunReport(2, "", word + " needs a value\n")
            var value = arguments[index + 1]
            if word == "--jobs":
                jobs = _integer_argument(value)
            else:
                shard_text = value
            index += 2
            continue
        if word.startswith("--jobs="):
            jobs = _integer_argument(String(word[byte=7:]))
        elif word.startswith("--shard="):
            shard_text = String(word[byte=8:])
        elif word.startswith("-"):
            return RunReport(2, "", "unknown argument " + word + "\n")
        elif directory.byte_length() != 0:
            return RunReport(2, "", "one directory is required\n")
        else:
            directory = word
        index += 1
    if jobs < 1:
        return RunReport(2, "", "--jobs must be at least 1\n")
    if directory.byte_length() == 0:
        return RunReport(2, "", "one directory is required\n")
    var shard: Tuple[Int, Int]
    try:
        shard = parse_shard(shard_text)
    except error:
        return RunReport(2, "", String(error) + "\n")
    var resolved = realpath(directory)
    var names = modules(resolved)
    if len(names) == 0:
        return RunReport(1, "", "no test modules in " + directory + "\n")
    var work = List[Unit]()
    for name in names:
        var listed = units(resolved, name)
        var listed_index = 0
        while listed_index < len(listed):
            var command = _copy_command(listed[listed_index].command)
            work.append(Unit(listed[listed_index].label, command^))
            listed_index += 1
    work = _select(work^, shard[0], shard[1])
    var results = execute(resolved, work^, jobs)
    var failed = List[String]()
    var output = String()
    var total = len(results)
    for result in results:
        if result.code != 0:
            failed.append(result.label)
            _print_failure(output, result)
    var passed = total - len(failed)
    output += (
        String(passed)
        + " of "
        + String(total)
        + " units passed ("
        + String(len(names))
        + " modules)\n"
    )
    var errors = String()
    if len(failed) > 0:
        errors = "failed: " + ", ".join(failed) + "\n"
        return RunReport(1, output, errors)
    return RunReport(0, output, errors)


def main() raises:
    """Run one directory of unittest modules from the command line."""
    var arguments = List[String]()
    var given = argv()
    for index in range(1, len(given)):
        arguments.append(String(given[index]))
    try:
        var report = run(arguments)
        if report.output.byte_length() > 0:
            print(report.output, end="")
        if report.errors.byte_length() > 0:
            print(report.errors, end="", file=stderr)
        exit(report.code)
    except error:
        print("parallel_unittest:", error, file=stderr)
        exit(1)
