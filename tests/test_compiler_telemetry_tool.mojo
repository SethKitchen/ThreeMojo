# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Compiler-free fake-proc and lifecycle tests for `tools/compiler_telemetry`.

The fake `/proc` and cgroup trees live in a temporary directory whose name
has spaces, so a mount point needs the `\\040` escape of `mountinfo`. The
lifecycle tests run small shell programs as the compiler. Two tests run the
built tool through `tools/tool.sh`, as the Makefile does.
"""

from std.ffi import c_int, external_call
from std.os import makedirs, remove
from std.pathlib import Path
from std.sys import CompilationTarget
from std.tempfile import mkdtemp
from std.testing import (
    TestSuite,
    assert_equal,
    assert_false,
    assert_true,
)

from tests._tree import tool_mojo
from tools._owned_process import close_fd, monotonic_seconds, open_at, at_cwd
from tools._process import run_program, shell_quote
from tools._python_json import PyJson, dumps_canonical
from tools.compiler_telemetry import (
    CompilerSampler,
    HeldSignals,
    MAX_LINE,
    MAX_PROCESSES,
    MAX_THREADS,
    ProcReader,
    ProcStat,
    Sampler,
    SignalControl,
    emit,
    parse_options,
    parse_stat,
    resolve,
    run_compiler,
    safe_suite,
)
from tools._owned_process import SignalHold, c_bytes


def stat_text(
    pid: Int,
    ppid: Int = 1,
    start: Int = 100,
    ticks: Int = 20,
    threads: Int = 1,
    name: String = "compiler (worker)",
) -> String:
    """Return a `stat` line with the fields the tool reads."""
    var fields = List[String](length=50, fill="0")
    fields[0] = "S"
    fields[1] = String(ppid)
    fields[11] = String(ticks)
    fields[17] = String(threads)
    fields[19] = String(start)
    fields[21] = "10"
    var text = String(pid) + " (" + name + ")"
    for field in fields:
        text += " " + field
    return text


struct FakeProc(Movable):
    """A fake `/proc` with process 100 in cgroup `/job`."""

    var root: String
    """The temporary directory."""
    var proc: String
    """The fake `/proc`."""
    var cg: String
    """The fake cgroup2 mount."""

    def __init__(out self) raises:
        """Make the tree."""
        self.root = mkdtemp(prefix="telemetry proc ")
        self.proc = self.root + "/proc"
        self.cg = self.root + "/cgroup"
        makedirs(self.proc + "/self", exist_ok=True)
        makedirs(self.cg + "/job", exist_ok=True)
        self.mount("/", self.cg)
        self.process(100)
        Path(self.proc + "/100/cgroup").write_text("0::/job\n")
        self.counters(1, 0)

    def mount(self, mount_root: String, point: String) raises:
        """Write `mountinfo` with one cgroup2 mount."""
        Path(self.proc + "/self/mountinfo").write_text(
            "1 0 0:1 "
            + mount_root
            + " "
            + point.replace(" ", "\\040")
            + " rw - cgroup2 none rw\n"
        )

    def process(
        self,
        pid: Int,
        ppid: Int = 1,
        start: Int = 100,
        ticks: Int = 20,
        threads: Int = 1,
    ) raises:
        """Write a process and its threads."""
        var folder = self.proc + "/" + String(pid)
        makedirs(folder, exist_ok=True)
        Path(folder + "/stat").write_text(
            stat_text(pid, ppid, start, ticks, threads)
        )
        for tid in range(pid, pid + threads):
            var task = folder + "/task/" + String(tid)
            makedirs(task, exist_ok=True)
            Path(task + "/stat").write_text(stat_text(tid, ppid, start, ticks))
            Path(task + "/wchan").write_text("futex_wait_queue")
            Path(task + "/children").write_text("")

    def counters(self, oom: Int, kills: Int, group: String = "job") raises:
        """Write the OOM counters of a cgroup."""
        for name in ["memory.events", "memory.events.local"]:
            Path(self.cg + "/" + group + "/" + name).write_text(
                "low 0\nhigh 0\nmax 0\noom "
                + String(oom)
                + "\noom_kill "
                + String(kills)
                + "\noom_group_kill 0\n"
            )

    def write(self, relative: String, text: String) raises:
        """Write a file under the root."""
        Path(self.root + "/" + relative).write_text(text)

    def sampler(self) -> Sampler:
        """Return a sampler of process 100 with a fixed clock and units."""
        var sampler = Sampler(self.proc)
        sampler.pid = 100
        sampler.clock = [10.0, 70.0, 130.0]
        sampler.hz = 100
        sampler.page_kib = 4.0
        return sampler^

    def close(self) raises:
        """Remove the tree."""
        _ = run_program(["rm", "-rf", self.root], 10)


def rename(old: String, new: String) raises:
    """Rename a path."""
    var result = run_program(["mv", old, new], 10)
    if result.status != 0:
        raise Error("mv failed: " + result.output)


def _pids(records: List[ProcStat]) -> List[Int]:
    """Return the PIDs of records."""
    var out = List[Int]()
    for record in records:
        out.append(record.pid)
    return out^


def _field(text: String, key: String) raises -> String:
    """Return a top-level field of a sample, as canonical JSON text."""
    var doc = PyJson.parse(text)
    return dumps_canonical(doc, doc.get(doc.root, key))


def _sample(mut sampler: Sampler) raises -> String:
    """Return one sample as canonical JSON text."""
    var doc = PyJson()
    return dumps_canonical(doc, sampler.sample(doc))


def test_stat_handles_spaces_and_parentheses_without_exposing_name() raises:
    var result = parse_stat(stat_text(42, name="a ) strange ( name)"))
    assert_equal(result.pid, 42)
    assert_equal(result.ticks, 20)
    assert_equal(result.start, 100)
    assert_equal(result.ppid, 1)


def test_nonleader_children_are_seen_but_unrelated_processes_are_not_read() raises:
    var fake = FakeProc()
    fake.process(100, threads=2)
    fake.process(200, ppid=100)
    fake.process(999, ppid=1)
    fake.write("proc/100/task/101/children", "200")
    var reader = ProcReader(fake.proc)
    reader.logging = True
    var result = reader.tree(100)
    assert_equal(_pids(result), [100, 200])
    for path in reader.log:
        assert_false("/999/" in path)
        for part in ["environ", "cmdline", "/mem", "/maps", "/stack"]:
            assert_false(part in path)
    fake.close()


def test_cpu_deltas_and_rss_do_not_double_count_threads() raises:
    var fake = FakeProc()
    fake.process(100, ticks=100, threads=2)
    var sampler = fake.sampler()
    var first = _sample(sampler)
    fake.process(100, ticks=250, threads=2)
    var second = _sample(sampler)
    sampler.close()
    assert_equal(_field(first, "observed_cpu_delta_s"), "null")
    assert_equal(_field(second, "observed_cpu_delta_s"), "1.5")
    assert_equal(_field(second, "interval_s"), "60.0")
    assert_equal(_field(second, "tree_rss_kib_approx"), "40")
    var doc = PyJson.parse(second)
    var process = doc.item(doc.get(doc.root, "processes"), 0)
    assert_equal(
        dumps_canonical(doc, doc.get(process, "thread_states")), '{"S":2}'
    )
    fake.close()


def test_reused_child_pid_has_no_false_delta() raises:
    var fake = FakeProc()
    fake.process(200, ppid=100, ticks=1000)
    fake.write("proc/100/task/100/children", "200")
    var sampler = fake.sampler()
    _ = _sample(sampler)
    fake.process(200, ppid=100, start=200, ticks=10)
    var doc = PyJson.parse(_sample(sampler))
    sampler.close()
    var processes = doc.get(doc.root, "processes")
    assert_equal(doc.length(processes), 2)
    var child = doc.item(processes, 1)
    assert_equal(doc.text(doc.get(child, "pid")), "200")
    assert_true(doc.is_none(doc.get(child, "cpu_delta_s")))
    fake.close()


def test_replaced_root_is_not_sampled_or_mapped_to_a_cgroup() raises:
    var fake = FakeProc()
    var sampler = fake.sampler()
    _ = _sample(sampler)
    fake.process(100, start=999)
    sampler.reader.logging = True
    var result = _sample(sampler)
    sampler.close()
    assert_equal(_field(result, "processes"), "[]")
    assert_equal(_field(result, "tree_rss_kib_approx"), "null")
    for path in sampler.reader.log:
        assert_false("cgroup" in path or "mountinfo" in path)
    fake.close()


def test_candidate_must_still_be_a_child_of_the_discovered_parent() raises:
    var fake = FakeProc()
    fake.process(200, ppid=999)
    fake.write("proc/100/task/100/children", "200")
    var reader = ProcReader(fake.proc)
    assert_equal(_pids(reader.tree(100)), [100])
    fake.close()


def test_missing_and_denied_metadata_are_unavailable_not_zero() raises:
    var fake = FakeProc()
    remove(fake.proc + "/100/task/100/wchan")
    remove(fake.cg + "/job/memory.events")
    var sampler = fake.sampler()
    var result = _sample(sampler)
    sampler.close()
    var doc = PyJson.parse(result)
    assert_true(Int(doc.text(doc.get(doc.root, "unavailable_reads"))) > 0)
    var context = doc.get(doc.root, "cgroup_oom_shared_context")
    assert_true(doc.is_none(doc.get(context, "memory.events")))
    # A final symbolic link is refused, as a denied open is.
    _ = run_program(
        ["ln", "-s", fake.proc + "/100/stat", fake.proc + "/100/link"], 10
    )
    var reader = ProcReader(fake.proc)
    assert_false(reader.read(fake.proc + "/100/link"))
    assert_equal(reader.unavailable, 1)
    fake.close()


def test_traversal_and_thread_caps_are_visible() raises:
    var fake = FakeProc()
    fake.process(100, threads=40)
    var children = String()
    for pid in range(200, 220):
        fake.process(pid, ppid=100)
        children += String(pid) + " "
    fake.write("proc/100/task/100/children", children)
    var sampler = fake.sampler()
    var doc = PyJson.parse(_sample(sampler))
    sampler.close()
    var processes = doc.get(doc.root, "processes")
    assert_true(doc.length(processes) <= MAX_PROCESSES)
    var first = doc.item(processes, 0)
    assert_true(Int(doc.text(doc.get(first, "sampled_threads"))) <= MAX_THREADS)
    assert_true(doc.flag(doc.get(doc.root, "truncated")))
    fake.close()


def _subtree_mapping(mut fake: FakeProc) raises:
    """Map `/host/job` through a mount of `/host`, and check the deltas."""
    fake.mount("/host", fake.cg)
    fake.write("proc/100/cgroup", "0::/host/job\n")
    var reader = ProcReader(fake.proc)
    var group = reader.cgroup(100)
    assert_true(group)
    assert_equal(group.value(), resolve(fake.cg + "/job"))
    var sampler = fake.sampler()
    _ = _sample(sampler)
    fake.counters(2, 1)
    var doc = PyJson.parse(_sample(sampler))
    sampler.close()
    var delta = doc.get(doc.get(doc.root, "cgroup_oom_delta"), "memory.events")
    assert_equal(doc.text(doc.get(delta, "oom_kill")), "1")


def test_subtree_cgroup_mount_mapping_and_shared_counter_deltas() raises:
    var fake = FakeProc()
    _subtree_mapping(fake)
    fake.close()


def test_symlinked_cgroup_mount_preserves_mapping_and_counter_deltas() raises:
    var fake = FakeProc()
    var canonical = resolve(fake.cg + "/job")
    var alias = fake.root + "/cgroup-alias"
    _ = run_program(["ln", "-s", fake.cg, alias], 10)
    var real = fake.cg
    fake.cg = alias
    assert_true(fake.cg + "/job" != canonical)
    _subtree_mapping(fake)
    var reader = ProcReader(fake.proc)
    assert_equal(reader.cgroup(100).value(), canonical)
    fake.cg = real
    fake.close()


def test_unmappable_or_traversal_cgroup_never_uses_a_global_fallback() raises:
    var fake = FakeProc()
    fake.mount("/host", fake.cg)
    for membership in [
        "0::/outside\n",
        "0::/host/../job\n",
        "4:memory:/host/job\n",
    ]:
        fake.write("proc/100/cgroup", membership)
        var reader = ProcReader(fake.proc)
        assert_false(reader.cgroup(100))
    fake.close()


def test_changed_cgroup_does_not_reuse_counter_baselines() raises:
    var fake = FakeProc()
    var sampler = fake.sampler()
    _ = _sample(sampler)
    makedirs(fake.cg + "/other", exist_ok=True)
    fake.write("cgroup/other/memory.events", "oom 90\noom_kill 90\n")
    fake.write("proc/100/cgroup", "0::/other\n")
    var result = _sample(sampler)
    sampler.close()
    assert_equal(_field(result, "cgroup_oom_delta"), "null")
    fake.close()


def test_pinned_process_directory_does_not_follow_a_reused_pid_path() raises:
    var fake = FakeProc()
    fake.process(100, threads=2)
    var reader = ProcReader(fake.proc)
    var fd = reader.open_dir(fake.proc + "/100")
    rename(fake.proc + "/100", fake.proc + "/old-process")
    fake.process(100, start=999, threads=8)
    var records = reader.tree(100, (100, 100), fd)
    close_fd(fd)
    assert_equal(records[0].start, 100)
    assert_equal(records[0].sampled_threads, 2)
    fake.close()


def test_terminal_oom_counter_uses_pinned_group_without_pid_lookup() raises:
    var fake = FakeProc()
    var sampler = fake.sampler()
    _ = _sample(sampler)
    fake.counters(2, 1)
    rename(fake.proc + "/100", fake.proc + "/finished-process")
    sampler.reader.logging = True
    var doc = PyJson()
    var terminal = sampler.terminal(doc)
    for path in sampler.reader.log:
        assert_false("/100" in path)
    var delta = doc.get(doc.get(terminal, "cgroup_oom_delta"), "memory.events")
    assert_equal(doc.text(doc.get(delta, "oom_kill")), "1")
    sampler.close()
    assert_equal(sampler.group_fd, -1)
    fake.close()


struct FailingSampler(CompilerSampler, Movable):
    """A real sampler that fails after it pins a cgroup."""

    var inner: Sampler
    """The real sampler."""
    var opened: List[Int]
    """The pinned cgroup descriptor of each failed sample."""

    def __init__(out self, var inner: Sampler):
        """Wrap a sampler."""
        self.inner = inner^
        self.opened = List[Int]()

    def start(mut self, pid: Int) raises:
        """Keep the fake process."""
        pass

    def sample(mut self, mut doc: PyJson) raises -> Int:
        """Sample, then fail."""
        _ = self.inner.sample(doc)
        self.opened.append(self.inner.group_fd)
        raise Error("fake telemetry failure")

    def terminal(mut self, mut doc: PyJson) raises -> Int:
        """Never reached."""
        return self.inner.terminal(doc)

    def close(mut self):
        """Close the real sampler."""
        self.inner.close()


struct EmptySampler(CompilerSampler, Movable):
    """A sampler with no tree, or one that fails with a private message."""

    var broken: Bool
    """True to fail every sample."""
    var pid: Int
    """The compiler."""

    def __init__(out self, broken: Bool = False):
        """Make a sampler."""
        self.broken = broken
        self.pid = 0

    def start(mut self, pid: Int) raises:
        """Keep the compiler."""
        self.pid = pid

    def sample(mut self, mut doc: PyJson) raises -> Int:
        """Return no processes."""
        if self.broken:
            raise Error("details must not be logged")
        var node = doc.new_dict()
        doc.set(node, "processes", doc.new_list())
        doc.set(node, "root_pid", doc.new_int(self.pid))
        return node

    def terminal(mut self, mut doc: PyJson) raises -> Int:
        """Fail, as a sampler without `terminal` does."""
        raise Error("no terminal")

    def close(mut self):
        """Hold nothing."""
        pass


struct ScriptedSignals(Movable, SignalControl):
    """Signals that arrive at chosen `take` calls, and the sends."""

    var arrivals: List[Int]
    """The signal each call returns, then zeros."""
    var calls: Int
    """The calls so far."""
    var sent: List[Tuple[Int, Int]]
    """Each group and signal sent."""

    def __init__(out self, var arrivals: List[Int] = List[Int]()):
        """Script the arrivals."""
        self.arrivals = arrivals^
        self.calls = 0
        self.sent = List[Tuple[Int, Int]]()

    def take(mut self) -> Int:
        """Return the scripted signal."""
        var index = self.calls
        self.calls += 1
        if index < len(self.arrivals):
            return self.arrivals[index]
        return 0

    def send(mut self, pid: Int, number: Int):
        """Record a send."""
        self.sent.append((pid, number))


def _log_file() raises -> Tuple[String, Int]:
    """Return a temporary log file and a descriptor that writes it."""
    var directory = mkdtemp(prefix="telemetry log ")
    var path = directory + "/log"
    Path(path).write_text("")
    var fd = open_at(at_cwd(), c_bytes(path), 1)
    return (path, fd)


def _records(path: String) raises -> List[String]:
    """Return the log's lines."""
    var out = List[String]()
    for line in Path(path).read_text().splitlines():
        out.append(String(line))
    return out^


def _event(line: String) raises -> String:
    """Return a record's event."""
    var doc = PyJson.parse(line)
    return doc.text(doc.get(doc.root, "event"))


def _run[
    S: CompilerSampler
](script: String, mut sampler: S, interval: Float64 = 0.02) raises -> Tuple[
    Int, List[String]
]:
    """Run a shell program as the compiler and return its status and log."""
    var log = _log_file()
    var control = ScriptedSignals()
    var status = run_compiler(
        ["sh", "-c", script],
        "tests/test_fake.mojo",
        log[1],
        interval,
        sampler,
        control,
    )
    close_fd(log[1])
    var records = _records(log[0])
    _ = run_program(["rm", "-rf", log[0], log[0] + "/.."], 10)
    return (status, records^)


def test_sampler_error_closes_an_already_pinned_cgroup() raises:
    var fake = FakeProc()
    var failing = FailingSampler(fake.sampler())
    var result = _run("exit 0", failing)
    assert_equal(result[0], 0)
    assert_equal(len(failing.opened), 1)
    assert_true(failing.opened[0] >= 0)
    assert_equal(failing.inner.group_fd, -1)
    assert_equal(_event(result[1][0]), "telemetry-unavailable")
    assert_equal(_event(result[1][len(result[1]) - 1]), "compiler-exit")
    fake.close()


def test_record_size_and_logging_failure_are_bounded() raises:
    var log = _log_file()
    var doc = PyJson()
    var payload = doc.new_dict()
    var processes = doc.new_list()
    for i in range(8):
        var process = doc.new_dict()
        doc.set(process, "pid", doc.new_int(i))
        doc.set(process, "waits", doc.new_str(String("x") * 1500))
        doc.append(processes, process)
    doc.set(payload, "processes", processes)
    emit(log[1], "tests/test_fake.mojo", doc, payload)
    close_fd(log[1])
    var data = Path(log[0]).read_text()
    assert_true(data.byte_length() <= MAX_LINE)
    assert_equal(data.byte_length(), 3177)
    assert_equal(_field(data, "processes_omitted_from_log"), "6")
    assert_equal(_field(data, "suite"), '"tests/test_fake.mojo"')
    var other = PyJson()
    var event = other.new_dict()
    other.set(event, "event", other.new_str("test"))
    emit(-1, "tests/test_fake.mojo", other, event)
    _ = run_program(["rm", "-rf", log[0], log[0] + "/.."], 10)


def test_unsafe_suite_names_are_not_logged() raises:
    assert_equal(safe_suite("tests/test_a.mojo"), "tests/test_a.mojo")
    assert_equal(safe_suite("tests/test_.mojo"), "unlabeled")
    assert_equal(safe_suite("tests/test_a-b.mojo"), "unlabeled")
    assert_equal(safe_suite("/private/path"), "unlabeled")
    var long = "tests/test_" + String("a") * 200 + ".mojo"
    assert_equal(safe_suite(long).byte_length(), 120)


def test_success_and_nonzero_exit_are_preserved_and_monitor_ends() raises:
    for expected in [0, 7]:
        var sampler = EmptySampler()
        var result = _run("exit " + String(expected), sampler)
        assert_equal(result[0], expected)
        var last = PyJson.parse(result[1][len(result[1]) - 1])
        assert_equal(last.text(last.get(last.root, "event")), "compiler-exit")
        assert_equal(last.text(last.get(last.root, "exit")), String(expected))
        assert_true(
            last.flag(last.get(last.root, "terminal_telemetry_unavailable"))
        )


def test_signal_exit_is_the_shell_status() raises:
    var sampler = EmptySampler()
    var result = _run("kill -TERM $$", sampler)
    assert_equal(result[0], 128 + 15)


def test_telemetry_error_does_not_change_compiler_result() raises:
    var sampler = EmptySampler(broken=True)
    var result = _run("exit 7", sampler)
    assert_equal(result[0], 7)
    assert_equal(_event(result[1][0]), "telemetry-unavailable")
    for line in result[1]:
        assert_false("details must not be logged" in line)


def test_periodic_sampling_adds_no_compiler_timeout() raises:
    var sampler = EmptySampler()
    var result = _run("sleep 0.12", sampler)
    assert_equal(result[0], 0)
    var samples = 0
    for line in result[1]:
        if _event(line) == "sample":
            samples += 1
    assert_true(samples >= 2)


def test_signal_receipt_is_forwarded_once_before_or_after_child_assignment() raises:
    # The second `take` comes right after the start, the third after the
    # first sample.
    for arrival in [1, 2]:
        var arrivals = List[Int](length=arrival + 1, fill=0)
        arrivals[arrival] = 15
        var control = ScriptedSignals(arrivals^)
        var sampler = EmptySampler()
        var log = _log_file()
        var status = run_compiler(
            ["sh", "-c", "sleep 0.2"],
            "tests/test_fake.mojo",
            log[1],
            60.0,
            sampler,
            control,
        )
        close_fd(log[1])
        var records = _records(log[0])
        _ = run_program(["rm", "-rf", log[0], log[0] + "/.."], 10)
        assert_equal(status, 143)
        assert_equal(len(control.sent), 1)
        var last = PyJson.parse(records[len(records) - 1])
        assert_equal(
            String(control.sent[0][0]), last.text(last.get(last.root, "pid"))
        )
        assert_equal(control.sent[0][1], 15)


def test_a_signal_before_the_start_runs_nothing() raises:
    var control = ScriptedSignals([2])
    var sampler = EmptySampler()
    var log = _log_file()
    var status = run_compiler(
        ["sh", "-c", "exit 0"],
        "tests/test_fake.mojo",
        log[1],
        60.0,
        sampler,
        control,
    )
    close_fd(log[1])
    var records = _records(log[0])
    _ = run_program(["rm", "-rf", log[0], log[0] + "/.."], 10)
    assert_equal(status, 130)
    assert_equal(len(records), 0)
    assert_equal(sampler.pid, 0)


def test_a_missing_or_denied_compiler_raises_its_errno() raises:
    var sampler = EmptySampler()
    var control = ScriptedSignals()
    for pair in [
        ("/nonexistent/compiler", "[Errno 2]"),
        ("/etc", "[Errno 13]"),
    ]:
        var message = String()
        try:
            _ = run_compiler(
                [pair[0]], "tests/test_fake.mojo", -1, 60.0, sampler, control
            )
        except error:
            message = String(error)
        assert_true(pair[1] in message)


def test_options_follow_argparse() raises:
    var options = parse_options(
        ["--suite", "tests/test_a.mojo", "--", "mojo", "--", "x"]
    )
    assert_equal(options.message, "")
    assert_equal(options.suite, "tests/test_a.mojo")
    assert_equal(options.log_fd, 3)
    assert_equal(options.command, ["mojo", "--", "x"])
    options = parse_options(["--su=s", "--l", " 1_0 ", "a", "--suite", "y"])
    assert_equal(options.log_fd, 10)
    assert_equal(options.command, ["a", "--suite", "y"])
    options = parse_options(["--suite", "x", "--log-fd", "q", "true"])
    assert_equal(options.status, 2)
    assert_equal(
        options.message,
        (
            "usage: compiler_telemetry.mojo [-h] --suite SUITE [--log-fd"
            " LOG_FD] ...\ncompiler_telemetry.mojo: error: argument --log-fd:"
            " invalid int value: 'q'\n"
        ),
    )
    options = parse_options(["--bogus", "a"])
    assert_true("required: --suite" in options.message)
    options = parse_options(["--bogus", "--suite", "x", "a"])
    assert_true("unrecognized arguments: --bogus\n" in options.message)
    options = parse_options(["--suite", "x", "--"])
    assert_true("a compiler command is required" in options.message)
    options = parse_options(["--suite", "x", "-h"])
    assert_equal(options.status, 0)
    assert_true(options.message.startswith("usage: "))


def _tool(name: String) raises -> String:
    """Return the shell words that run a built tool, as the Makefile does."""
    return "sh tools/tool.sh " + shell_quote(tool_mojo()) + " " + name


def test_disabled_wrapper_execs_without_a_monitor() raises:
    var script = (
        "echo $$; THREEMOJO_COMPILER_TELEMETRY=0 exec "
        + _tool("compiler_telemetry")
        + " --suite tests/test_fake.mojo -- sh -c 'echo $$; exit 11'"
    )
    var result = run_program(["sh", "-c", script], 30, merge_errors=False)
    assert_equal(result.status, 11)
    var lines = result.output.splitlines()
    assert_equal(len(lines), 2)
    assert_equal(lines[0], lines[1])
    assert_equal(result.errors, "")


def test_cancellation_reaches_only_the_owned_compiler_group() raises:
    comptime if not CompilationTarget.is_linux():
        return
    var root = mkdtemp(prefix="telemetry cancel ")
    var q = shell_quote(root)
    Path(root + "/worker.sh").write_text(
        'd=$(dirname "$0")\n'
        + "trap 'echo 15 > \"$d/worker.signal\"; exit 0' TERM\n"
        + 'echo $$ > "$d/worker.ready"\n'
        + "while :; do sleep 0.02; done\n"
    )
    Path(root + "/compiler.sh").write_text(
        'd=$(dirname "$0")\n'
        + "trap 'echo 15 > \"$d/compiler.signal\"; wait $c; exit 0' TERM\n"
        + 'sh "$d/worker.sh" & c=$!\n'
        + 'echo $$ > "$d/compiler.ready"\n'
        + "while :; do sleep 0.02; done\n"
    )
    var script = (
        "THREEMOJO_COMPILER_TELEMETRY=1 "
        + _tool("compiler_telemetry")
        + " --suite tests/test_fake.mojo --log-fd 2 -- sh "
        + q
        + "/compiler.sh 2> "
        + q
        + "/log & t=$!\n"
        + "n=0; while [ ! -f "
        + q
        + "/worker.ready ] && [ $n -lt 500 ]; do sleep 0.01; n=$((n+1)); done\n"
        + "kill -TERM $t; wait $t; echo $?\n"
    )
    var result = run_program(["sh", "-c", script], 30, merge_errors=False)
    assert_equal(result.output, "143\n")
    for role in ["compiler", "worker"]:
        assert_equal(Path(root + "/" + role + ".signal").read_text(), "15\n")
    var lines = Path(root + "/log").read_text().splitlines()
    var last = PyJson.parse(String(lines[len(lines) - 1]))
    assert_equal(last.text(last.get(last.root, "event")), "compiler-exit")
    assert_equal(last.text(last.get(last.root, "exit")), "143")
    _ = run_program(["rm", "-rf", root], 10)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
