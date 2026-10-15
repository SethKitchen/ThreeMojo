# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Prepare, build, and measure serial, paired #505 image-loading experiments.

Subcommands never run implicitly. `stride` writes a source-only copy.
`build` compiles serially. `build-rusage` adds the RSS helper to an earlier
build record. `run` invokes already built programs, one process at a time.

A low-RSS C supervisor, `image_decode_rusage`, obtains the native child's
`wait4` usage. The runner's own memory is never used as decoder memory
evidence.

Usage:
    image_decode_bench stride --source DIR --destination DIR
    image_decode_bench build --mojo PATH [--cc PATH] --source LABEL=DIR ...
        [--revision LABEL=REV ...] --destination DIR [--flag=OPTION ...]
        [--timeout SECONDS]
    image_decode_bench build-rusage --build FILE [--cc PATH]
        [--timeout SECONDS]
    image_decode_bench run --build FILE --fixtures DIR --destination DIR
        [--baseline LABEL] [--repetitions N] [--workers N ...]
        [--datasets NAME ...] [--apis gltf|registry ...] [--seed N]
        [--timeout SECONDS]

The host record names the runner in `runner_language`. The earlier Python
runner wrote its interpreter version in `python` instead.
"""

from std.ffi import OwnedDLHandle, external_call
from std.os import listdir, makedirs, mkdir, remove, rmdir
from std.os.path import exists, isdir, isfile, islink
from std.pathlib import Path
from std.reflection import source_location
from std.sys import CompilationTarget, argv, exit, num_logical_cores, stderr
from std.tempfile import mkdtemp
from std.time import perf_counter_ns, sleep

from bench.image_decode_fixture import resolve_path
from tools._json_value import ABSENT, JsonTree, canonical_integer

from loaders.json import STRING
from tools._process import run_program
from tools._python_float import parse_float
from tools._python_random import PythonRandom
from tools._python_stats import (
    PyNumber,
    distribution,
    format_fixed,
    true_divide,
)
from tools._sha256 import Sha256
from tools._text import split_lines

comptime BASELINE_REVISION = "51b4424ceef57fef1f8a5e787c583126f999baf5"
"""The baseline commit of the recorded #505 comparison."""
comptime RUSAGE_MARKER = "THREEMOJO_RUSAGE_V1 "
"""The prefix of the supervisor's one usage line on standard error."""
comptime MIN_AVAILABLE_BYTES = 3 * 1024 * 1024 * 1024
"""The least `MemAvailable` that allows a launch."""
comptime MIN_DISK_BYTES = 2 * 1024 * 1024 * 1024
"""The least free workspace that allows a launch."""
comptime _GIB = 1024 * 1024 * 1024
comptime _MIB = 1024 * 1024
comptime _SIGKILL = 9
comptime _WNOHANG = 1
comptime _POSIX_SPAWN_SETPGROUP = 2


def check_fields() -> List[String]:
    """Return the native output fields that every variant must agree on.

    Returns:
        The field names in their recorded order.
    """
    return [
        String("textures"),
        String("base_bytes"),
        String("payload_bytes"),
        String("mip_levels"),
        String("all_fnv64"),
        String("base_fnv64"),
        String("shape_fnv64"),
    ]


def _ignored(name: String) -> Bool:
    """Return whether a path part hides its files from a source record."""
    return (
        name == ".git"
        or name == ".venv"
        or name == ".cache"
        or name == "build"
        or name == "__pycache__"
    )


def here() -> String:
    """Return the folder of this runner's source file.

    Returns:
        The `bench` folder that holds the driver and the C helper.
    """
    var file = String(source_location().file_name())
    var slash = file.rfind("/")
    return String(file[byte=:slash]) if slash >= 0 else String(".")


def runner_source() -> String:
    """Return this runner's source file.

    Returns:
        The path of `image_decode_bench.mojo`.
    """
    return String(source_location().file_name())


# --- small helpers -------------------------------------------------------------


def _two(value: Int) -> String:
    """Return a number with at least two digits."""
    return ("0" if value < 10 else "") + String(value)


def now() -> String:
    """Return the UTC time, as `datetime.now(timezone.utc).isoformat()`.

    Returns:
        `YYYY-MM-DDTHH:MM:SS.ffffff+00:00`, without the fraction when the
        microseconds are zero.
    """
    var spec = List[Int64](length=2, fill=0)
    _ = external_call["clock_gettime", Int32](
        Int32(0), spec.unsafe_ptr().unsafe_bitcast[NoneType]()
    )
    var seconds = Int(spec[0])
    var micro = Int(spec[1]) // 1000
    var days = seconds // 86400
    var rest = seconds - days * 86400
    # Howard Hinnant's civil_from_days.
    var z = days + 719468
    var era = (z if z >= 0 else z - 146096) // 146097
    var doe = z - era * 146097
    var yoe = (doe - doe // 1460 + doe // 36524 - doe // 146096) // 365
    var year = yoe + era * 400
    var doy = doe - (365 * yoe + yoe // 4 - yoe // 100)
    var mp = (5 * doy + 2) // 153
    var day = doy - (153 * mp + 2) // 5 + 1
    var month = mp + 3 if mp < 10 else mp - 9
    if month <= 2:
        year += 1
    var text = (
        String(year)
        + "-"
        + _two(month)
        + "-"
        + _two(day)
        + "T"
        + _two(rest // 3600)
        + ":"
        + _two((rest // 60) % 60)
        + ":"
        + _two(rest % 60)
    )
    if micro:
        var fraction = String(micro)
        while fraction.byte_length() < 6:
            fraction = "0" + fraction
        text += "." + fraction
    return text + "+00:00"


def sha(path: String) raises -> String:
    """Return the SHA-256 of a file, read a mebibyte at a time.

    Args:
        path: The file.

    Returns:
        The hexadecimal digest.

    Raises:
        Error: If the file cannot be read.
    """
    var hasher = Sha256()
    hasher.update(Span(Path(path).read_bytes()))
    return hasher^.hexdigest()


def write_json(tree: JsonTree, node: Int, path: String) raises:
    """Write a node as `json.dumps(value, indent=2, sort_keys=True)`.

    Args:
        tree: The tree.
        node: The value.
        path: The file. A newline ends it.

    Raises:
        Error: If the file cannot be written.
    """
    Path(path).write_text(tree.dumps(node, 2, True, ",", ": ") + "\n")


def read_json(mut tree: JsonTree, path: String) raises -> Int:
    """Read a JSON file into a tree.

    Args:
        tree: The tree.
        path: The file.

    Returns:
        The root node.

    Raises:
        Error: If the file cannot be read or parsed.
    """
    return tree.parse(Path(path).read_text())


def compact(tree: JsonTree, node: Int) raises -> String:
    """Return `json.dumps(value)`: one line, Python's default separators.

    Args:
        tree: The tree.
        node: The value.

    Returns:
        The text.

    Raises:
        Error: If the node does not exist.
    """
    return tree.dumps(node)


def python_repr_text(text: String) -> String:
    """Return `repr(text)` for a string, as Python writes it.

    Args:
        text: The string.

    Returns:
        The quoted string, with backslash escapes.
    """
    var quote = "'"
    if "'" in text and not ('"' in text):
        quote = '"'
    var out = quote
    for codepoint in text.codepoints():
        var code = Int(codepoint.to_u32())
        if code == ord("\\"):
            out += "\\\\"
        elif code == ord("\n"):
            out += "\\n"
        elif code == ord("\r"):
            out += "\\r"
        elif code == ord("\t"):
            out += "\\t"
        elif quote == "'" and code == ord("'"):
            out += "\\'"
        elif code < 0x20 or code == 0x7F:
            var hex = "0123456789abcdef"
            out += (
                "\\x"
                + chr(Int(hex.as_bytes()[code >> 4]))
                + chr(Int(hex.as_bytes()[code & 15]))
            )
        else:
            out += String(codepoint)
    return out + quote


def _python_list(values: List[String]) -> String:
    """Return `repr(list_of_strings)`."""
    var out = String("[")
    for i in range(len(values)):
        if i > 0:
            out += ", "
        out += python_repr_text(values[i])
    return out + "]"


def _command_text(command: List[String]) -> String:
    """Return a command as Python writes a list of strings."""
    return _python_list(command)


def _c_string(text: String) -> List[UInt8]:
    """Return text with a final zero byte."""
    var bytes = List[UInt8](text.as_bytes())
    bytes.append(0)
    return bytes^


def _read_c_string(address: Int) -> String:
    """Return the zero-terminated text at an address."""
    if address == 0:
        return String()
    var length = external_call["strlen", Int](address)
    var bytes = List[UInt8](length=length, fill=0)
    _ = external_call["memcpy", Int](
        bytes.unsafe_ptr().unsafe_bitcast[NoneType](), address, length
    )
    return String(from_utf8_lossy=bytes)


def environment_value(name: String) -> Optional[String]:
    """Return an environment variable, or None when it is unset.

    Args:
        name: The variable.

    Returns:
        The value, which can be empty, or None.
    """
    var key = _c_string(name)
    var address = external_call["getenv", Int](
        key.unsafe_ptr().unsafe_bitcast[NoneType]()
    )
    if address == 0:
        return None
    return _read_c_string(address)


def read_optional(path: String) -> Optional[String]:
    """Return a file's text without surrounding whitespace, or None.

    Args:
        path: The file.

    Returns:
        The stripped text, or None when the file cannot be read.
    """
    try:
        return String(Path(path).read_text().strip())
    except:
        return None


def _optional_text(mut tree: JsonTree, value: Optional[String]) -> Int:
    """Add a string, or `null` for None."""
    if value:
        return tree.string(value.value())
    return tree.null()


def _python_split(text: String) -> List[String]:
    """Split at runs of whitespace, as `str.split()` does."""
    var parts = List[String]()
    var current = String()
    for codepoint in text.codepoints():
        var code = Int(codepoint.to_u32())
        var space = (
            code == 0x20
            or (code >= 0x09 and code <= 0x0D)
            or (code >= 0x1C and code <= 0x1F)
            or code == 0x85
            or code == 0xA0
            or code == 0x1680
            or (code >= 0x2000 and code <= 0x200A)
            or code == 0x2028
            or code == 0x2029
            or code == 0x202F
            or code == 0x205F
            or code == 0x3000
        )
        if space:
            if current.byte_length() > 0:
                parts.append(current)
                current = String()
        else:
            current += String(codepoint)
    if current.byte_length() > 0:
        parts.append(current)
    return parts^


# --- source records ------------------------------------------------------------


def _parts_less(a: String, b: String) -> Bool:
    """Return whether path `a` sorts before `b`, as `pathlib` sorts paths:
    by their parts, not by their text."""
    var x = a.split("/")
    var y = b.split("/")
    for i in range(min(len(x), len(y))):
        if x[i] != y[i]:
            return String(x[i]) < String(y[i])
    return len(x) < len(y)


def _walk(root: String, relative: String, mut found: List[String]) raises:
    """Collect `.mojo` files below a folder, skipping ignored parts."""
    var folder = root if relative == "" else root + "/" + relative
    for name in listdir(folder):
        if _ignored(name):
            continue
        var path = name if relative == "" else relative + "/" + name
        var full = root + "/" + path
        if isdir(full) and not islink(full):
            _walk(root, path, found)
        elif name.endswith(".mojo") and isfile(full):
            found.append(path)


def source_files(root: String) raises -> List[String]:
    """Return the `.mojo` files of a tree, relative and sorted.

    Folders named `.git`, `.venv`, `.cache`, `build` or `__pycache__` are
    skipped. Symbolic links to folders are not followed.

    Args:
        root: The tree's folder.

    Returns:
        The relative paths, in `pathlib` order.

    Raises:
        Error: If a folder cannot be listed.
    """
    var found = List[String]()
    if isdir(root):
        _walk(root, "", found)
    for i in range(1, len(found)):
        var j = i
        while j > 0 and _parts_less(found[j], found[j - 1]):
            found.swap_elements(j, j - 1)
            j -= 1
    return found^


def source_record(mut tree: JsonTree, root: String) raises -> Int:
    """Add `{root, mojo_tree_sha256, files}` for a source tree.

    `files` maps each relative `.mojo` path to its SHA-256. The tree digest
    is the SHA-256 of `files` as compact JSON with sorted keys.

    Args:
        tree: The tree for the record.
        root: The source folder.

    Returns:
        The record node.

    Raises:
        Error: `No Mojo sources: ROOT` when the tree has no `.mojo` file.
    """
    var folder = resolve_path(root)
    var files = tree.object()
    var paths = source_files(folder)
    for path in paths:
        tree.set(files, path, tree.string(sha(folder + "/" + path)))
    if len(paths) == 0:
        raise Error("No Mojo sources: " + folder)
    var text = tree.dumps(files, -1, True, ",", ":")
    var hasher = Sha256()
    hasher.update(text.as_bytes())
    var record = tree.object()
    tree.set(record, "root", tree.string(folder))
    tree.set(record, "mojo_tree_sha256", tree.string(hasher^.hexdigest()))
    tree.set(record, "files", files)
    return record


@fieldwise_init
struct Named(Copyable, Movable):
    """One `LABEL=VALUE` argument."""

    var label: String
    """The label."""
    var value: String
    """The value."""


def _alphanumeric(text: String) -> Bool:
    """Return `str.isalnum()` for ASCII text."""
    if text.byte_length() == 0:
        return False
    for byte in text.as_bytes():
        var code = Int(byte)
        if not (
            (code >= ord("0") and code <= ord("9"))
            or (code >= ord("a") and code <= ord("z"))
            or (code >= ord("A") and code <= ord("Z"))
            or code >= 0x80
        ):
            return False
    return True


def named(values: List[String]) raises -> List[Named]:
    """Read unique `LABEL=VALUE` arguments.

    Args:
        values: The arguments.

    Returns:
        Each label and value, in order.

    Raises:
        Error: If an argument has no `=`, an empty side, a repeated label,
            or a label with characters other than letters, digits, `_` and
            `-`.
    """
    var result = List[Named]()
    for value in values:
        var at = value.find("=")
        var label = String(value[byte=:at]) if at >= 0 else value
        var target = String(value[byte = at + 1 :]) if at >= 0 else String()
        var repeated = False
        for item in result:
            if item.label == label:
                repeated = True
        if (
            at < 0
            or label.byte_length() == 0
            or target.byte_length() == 0
            or repeated
        ):
            raise Error("Expected unique LABEL=VALUE: " + value)
        if not _alphanumeric(label.replace("_", "").replace("-", "")):
            raise Error("Unsafe label: " + label)
        result.append(Named(label, target))
    return result^


def _copy_file(source: String, target: String) raises:
    """Copy a file's bytes."""
    Path(target).write_bytes(Span(Path(source).read_bytes()))


def _parent(path: String) -> String:
    """Return a path's folder."""
    var slash = path.rfind("/")
    return String(path[byte=:slash]) if slash > 0 else String("/")


def _stride_worker() -> String:
    """Return the experimental fixed-stride worker's source."""
    return (
        "async def _decode_worker[\n"
        + "    Source: TextureDecodeSource\n"
        + "](\n"
        + "    source: Pointer[Source, ImmutAnyOrigin],\n"
        + "    first: Int,\n"
        + "    stride: Int,\n"
        + "    count: Int,\n"
        + "    results: MutPointer[Optional[Texture], MutAnyOrigin],\n"
        + "    errors: MutPointer[Optional[String], MutAnyOrigin],\n"
        + "):\n"
        + '    """Experimental fixed-stride worker; deliberately no dynamic'
        + ' claims."""\n'
        + "    for index in range(first, count, stride):\n"
        + "        try:\n"
        + "            results[unsafe_offset=index] ="
        + " source[].decode(index)\n"
        + "        except e:\n"
        + "            errors[unsafe_offset=index] = String(e)\n"
        + "\n"
    )


def stride_source(original: String) raises -> String:
    """Return the scheduler module with fixed-stride workers in place of
    dynamic claims.

    Args:
        original: The text of `loaders/image_batch.mojo`.

    Returns:
        The changed text.

    Raises:
        Error: If an expected piece of the candidate is missing or repeated.
    """
    var start = original.find("def _claim_decode(")
    if start < 0:
        raise Error("substring not found")
    var end = original.find("\ndef decode_textures[", start)
    if end < 0:
        raise Error("substring not found")
    var modified = (
        String(original[byte=:start])
        + _stride_worker()
        + String(original[byte=end:])
    )
    var olds: List[String] = [
        "from std.atomic import Atomic\n",
        "    var next: Int64 = 0\n",
        "    for _ in range(decode_batch_size(count, workers)):\n",
        (
            "               "
            " Pointer(to=next).unsafe_origin_cast[MutAnyOrigin](),\n"
        ),
        "    _ = next\n",
        "Decode indexed images with a bounded, work-conserving queue.",
        (
            "    One worker reads one image at a time. A free worker claims"
            " the next\n    image without waiting for slower workers. Inputs"
            " must stay fixed for\n"
        ),
    ]
    var news: List[String] = [
        "",
        "    var active = decode_batch_size(count, workers)\n",
        "    for worker in range(active):\n",
        "                worker,\n                active,\n",
        "    _ = active\n",
        "Decode indexed images with experimental fixed-stride workers.",
        (
            "    One worker reads its fixed source-index stride one image at"
            " a time.\n    It cannot take another worker's jobs. Inputs must"
            " stay fixed for\n"
        ),
    ]
    for i in range(len(olds)):
        if modified.count(olds[i]) != 1:
            raise Error(
                "Candidate scheduler changed; inspect replacement: "
                + python_repr_text(olds[i])
            )
        modified = modified.replace(olds[i], news[i])
    return modified^


def prepare_stride(source_root: String, destination_root: String) raises:
    """Write a source-only copy with the experimental stride scheduler.

    Args:
        source_root: The candidate tree.
        destination_root: A new folder for the copy.

    Raises:
        Error: If the destination exists, the candidate changes during the
            copy, or a file other than the scheduler differs.
    """
    var source = resolve_path(source_root)
    var destination = resolve_path(destination_root)
    if exists(destination):
        raise Error("Stride destination must be new")
    var tree = JsonTree()
    var before = source_record(tree, source)
    makedirs(destination)
    for path in source_files(source):
        var target = destination + "/" + path
        makedirs(_parent(target), exist_ok=True)
        _copy_file(source + "/" + path, target)
    var module = destination + "/loaders/image_batch.mojo"
    Path(module).write_text(stride_source(Path(module).read_text()))
    var after_source = source_record(tree, source)
    if not tree.equal(before, after_source):
        raise Error(
            "Candidate changed during stride snapshot; create a new snapshot"
        )
    var after = source_record(tree, destination)
    var before_files = tree.get(before, "files")
    var after_files = tree.get(after, "files")
    var changed = List[String]()
    for path in tree.keys(before_files):
        if tree.text(tree.get(before_files, path)) != tree.text(
            tree.get(after_files, path)
        ):
            changed.append(path)
    if len(changed) != 1 or changed[0] != "loaders/image_batch.mojo":
        raise Error(
            "Unexpected stride source changes: " + _python_list(changed)
        )
    var record = tree.object()
    tree.set(record, "schema", tree.integer(1))
    tree.set(record, "created_utc", tree.string(now()))
    tree.set(
        record,
        "kind",
        tree.string("experimental fixed-stride persistent workers"),
    )
    tree.set(record, "candidate", before)
    tree.set(record, "stride", after)
    tree.set(record, "changed_files", tree.strings(changed))
    tree.set(
        record,
        "note",
        tree.string(
            "Benchmark control only; not a proposed production scheduler."
        ),
    )
    write_json(tree, record, destination + "/stride-provenance.json")
    var printed = tree.object()
    tree.set(printed, "stride_source", tree.string(destination))
    tree.set(printed, "sha256", tree.get(after, "mojo_tree_sha256"))
    print(compact(tree, printed))


# --- resources -----------------------------------------------------------------


def free_disk_bytes(directory: String) raises -> Int:
    """Return the free bytes an unprivileged user can use on a file system,
    as `shutil.disk_usage(directory).free` does.

    Args:
        directory: A path on the file system.

    Returns:
        `f_bavail * f_frsize` from `statvfs`.

    Raises:
        Error: If `statvfs` fails.
    """
    var path = _c_string(directory)
    var buffer = List[UInt8](length=512, fill=0)
    var status = external_call["statvfs", Int32](
        path.unsafe_ptr().unsafe_bitcast[NoneType](),
        buffer.unsafe_ptr().unsafe_bitcast[NoneType](),
    )
    if status != 0:
        raise Error("statvfs failed: " + directory)
    var frsize = 0
    for i in range(8):
        frsize |= Int(buffer[8 + i]) << (8 * i)
    var available = 0
    comptime if CompilationTarget.is_macos():
        # fsblkcnt_t is 32 bits on macOS, after two 64-bit sizes and two
        # counts.
        for i in range(4):
            available |= Int(buffer[24 + i]) << (8 * i)
    else:
        for i in range(8):
            available |= Int(buffer[32 + i]) << (8 * i)
    return available * frsize


def _is_linux() -> Bool:
    """Return whether this build targets Linux."""
    comptime if CompilationTarget.is_macos():
        return False
    else:
        return True


@fieldwise_init
struct Resources(Copyable, Movable):
    """The memory and disk readings that allowed a launch."""

    var available: Optional[Int]
    """`MemAvailable` in bytes, or None when the system does not say."""
    var free_disk: Int
    """The free workspace in bytes."""

    def to_json(self, mut tree: JsonTree) raises -> Int:
        """Add the reading and its minimums as a JSON object.

        Args:
            tree: The tree.

        Returns:
            The object node.

        Raises:
            Error: Never in practice; the tree API can raise.
        """
        var record = tree.object()
        tree.set(
            record,
            "mem_available_bytes",
            tree.integer(
                self.available.value()
            ) if self.available else tree.null(),
        )
        tree.set(record, "workspace_free_bytes", tree.integer(self.free_disk))
        tree.set(
            record,
            "minimum_mem_available_bytes",
            tree.integer(MIN_AVAILABLE_BYTES),
        )
        tree.set(
            record, "minimum_workspace_free_bytes", tree.integer(MIN_DISK_BYTES)
        )
        return record


def check_resources(
    meminfo: Optional[String], free_disk: Int, linux: Bool
) raises -> Resources:
    """Check memory and disk readings against the launch minimums.

    Args:
        meminfo: The text of `/proc/meminfo`, or None.
        free_disk: The free workspace in bytes.
        linux: True on Linux, where `MemAvailable` is required.

    Returns:
        The readings.

    Raises:
        Error: If Linux gives no `MemAvailable`, it is below 3 GiB, or the
            workspace has less than 2 GiB free.
    """
    var available: Optional[Int] = None
    if meminfo and meminfo.value().byte_length() > 0:
        for line in split_lines(meminfo.value()):
            if line.startswith("MemAvailable:"):
                var parts = _python_split(line)
                if len(parts) < 2:
                    raise Error("list index out of range")
                available = Int(canonical_integer(parts[1])) * 1024
                break
    if linux and not available:
        raise Error("Cannot verify MemAvailable before launching a process")
    if available and available.value() < MIN_AVAILABLE_BYTES:
        raise Error(
            "Resource guard: MemAvailable "
            + format_fixed(true_divide(available.value(), _GIB), 2)
            + " GiB is below 3 GiB"
        )
    if free_disk < MIN_DISK_BYTES:
        raise Error(
            "Resource guard: workspace free "
            + format_fixed(true_divide(free_disk, _GIB), 2)
            + " GiB is below 2 GiB"
        )
    return Resources(available, free_disk)


def resource_guard(directory: String) raises -> Resources:
    """Stop before a launch when memory or workspace free space is unsafe.

    Args:
        directory: The workspace folder.

    Returns:
        The readings.

    Raises:
        Error: As `check_resources` does.
    """
    var free_disk = free_disk_bytes(directory)
    return check_resources(
        read_optional("/proc/meminfo"), free_disk, _is_linux()
    )


# --- builds --------------------------------------------------------------------


def _checked_output(command: List[String], timeout: Float64) raises -> String:
    """Run a command with merged output and return it; raise on failure."""
    var result = run_program(command, timeout)
    if result.timed_out:
        raise Error(
            "Command '"
            + _command_text(command)
            + "' timed out after "
            + String(timeout)
            + " seconds"
        )
    if result.status != 0:
        raise Error(
            "Command '"
            + _command_text(command)
            + "' returned non-zero exit status "
            + String(result.status)
            + "."
        )
    return result.output


def build_helper(
    mut tree: JsonTree,
    compiler_path: String,
    destination_root: String,
    timeout: Float64,
) raises -> Int:
    """Compile and hash the small native RSS supervisor.

    Args:
        tree: The tree for the helper record.
        compiler_path: The C compiler.
        destination_root: The build folder.
        timeout: The compile time limit in seconds.

    Returns:
        The helper record node.

    Raises:
        Error: If the helper exists, a resource guard fails, or the
            compiler fails.
    """
    var compiler = resolve_path(compiler_path)
    var destination = resolve_path(destination_root)
    var source = destination + "/image_decode_rusage.c"
    var binary = destination + "/image_decode_rusage"
    if exists(source) or exists(binary):
        raise Error(
            "RSS helper destination already exists; use a fresh build directory"
        )
    _copy_file(here() + "/image_decode_rusage.c", source)
    _ = resource_guard(destination)
    var version = String(
        _checked_output([compiler, String("--version")], 86400).strip()
    )
    var command: List[String] = [
        compiler,
        "-O2",
        "-std=c11",
        "-Wall",
        "-Wextra",
        "-Werror",
        source,
        "-o",
        binary,
    ]
    var launch = resource_guard(destination)
    var result = run_program(command, timeout)
    Path(destination + "/rusage.build.log").write_text(result.output)
    if result.timed_out:
        raise Error(
            "Command '"
            + _command_text(command)
            + "' timed out after "
            + String(timeout)
            + " seconds"
        )
    if result.status != 0:
        raise Error(
            "Command '"
            + _command_text(command)
            + "' returned non-zero exit status "
            + String(result.status)
            + "."
        )
    var record = tree.object()
    tree.set(record, "binary", tree.string(binary))
    tree.set(record, "binary_sha256", tree.string(sha(binary)))
    tree.set(record, "source", tree.string(source))
    tree.set(record, "source_sha256", tree.string(sha(source)))
    tree.set(record, "command", tree.strings(command))
    var compiler_record = tree.object()
    tree.set(compiler_record, "path", tree.string(compiler))
    tree.set(compiler_record, "version", tree.string(version))
    tree.set(record, "compiler", compiler_record)
    tree.set(record, "launch_resources", launch.to_json(tree))
    tree.set(record, "protocol", tree.string("THREEMOJO_RUSAGE_V1"))
    tree.set(record, "created_utc", tree.string(now()))
    return record


def build_rusage(build_path: String, compiler: String, timeout: Float64) raises:
    """Add a verified helper build to an existing native build record.

    Args:
        build_path: The `build.json` file.
        compiler: The C compiler.
        timeout: The compile time limit in seconds.

    Raises:
        Error: If the record is incomplete, already has a helper, or a
            native binary changed since it was built.
    """
    var path = resolve_path(build_path)
    var tree = JsonTree()
    var record = read_json(tree, path)
    var status = tree.find(record, "status")
    if (
        status == ABSENT
        or not _is_string(tree, status)
        or tree.text(status) != "complete"
    ):
        raise Error("An existing completed native build record is required")
    if tree.find(record, "rusage_helper") != ABSENT:
        raise Error("Build record already has an RSS helper")
    var variants = tree.get(record, "variants")
    for label in tree.keys(variants):
        var info = tree.get(variants, label)
        if sha(tree.string_value(tree.get(info, "binary"))) != tree.text(
            tree.get(info, "binary_sha256")
        ):
            raise Error("Native binary changed since its build record")
    var helper = build_helper(tree, compiler, _parent(path), timeout)
    tree.set(record, "rusage_helper", helper)
    tree.set(record, "rss_harness_updated_utc", tree.string(now()))
    write_json(tree, record, path)
    print("RSS_HELPER", tree.text(tree.get(helper, "binary")))


def build(
    mojo: String,
    compiler: String,
    sources: List[String],
    revisions: List[String],
    destination_root: String,
    flags: List[String],
    timeout: Float64,
) raises:
    """Compile the driver against each source tree, one after another.

    Args:
        mojo: The Mojo compiler.
        compiler: The C compiler for the RSS helper.
        sources: `LABEL=DIR` arguments.
        revisions: `LABEL=REVISION` arguments.
        destination_root: A new build folder.
        flags: Compiler options; empty means `-O3`. `--Werror` is always
            added.
        timeout: Each compile's time limit in seconds.

    Raises:
        Error: If the folder exists, a source changes during its build, a
            build fails, or the stride control differs outside its
            scheduler.
    """
    var labelled = named(sources)
    var revision_list = named(revisions)
    var destination = resolve_path(destination_root)
    if exists(destination):
        raise Error("[Errno 17] File exists: '" + destination + "'")
    makedirs(destination)
    var driver = destination + "/image_decode.mojo"
    _copy_file(here() + "/image_decode.mojo", driver)
    var toolchain = resolve_path(mojo)
    _ = resource_guard(destination)
    var version = String(
        _checked_output([toolchain, String("--version")], 86400).strip()
    )
    var tree = JsonTree()
    var record = tree.object()
    tree.set(record, "schema", tree.integer(1))
    tree.set(record, "status", tree.string("building"))
    tree.set(record, "created_utc", tree.string(now()))
    var toolchain_record = tree.object()
    tree.set(toolchain_record, "path", tree.string(toolchain))
    tree.set(toolchain_record, "version", tree.string(version))
    tree.set(record, "toolchain", toolchain_record)
    tree.set(record, "driver_sha256", tree.string(sha(driver)))
    tree.set(record, "runner_sha256", tree.string(sha(runner_source())))
    var variants = tree.object()
    tree.set(record, "variants", variants)
    var record_path = destination + "/build.json"
    write_json(tree, record, record_path)
    tree.set(
        record,
        "rusage_helper",
        build_helper(tree, compiler, destination, timeout),
    )
    write_json(tree, record, record_path)
    var all_flags: List[String] = ["--Werror"]
    if len(flags) == 0:
        all_flags.append("-O3")
    else:
        all_flags.extend(flags.copy())
    for item in labelled:
        var before = source_record(tree, item.value)
        var root = tree.string_value(tree.get(before, "root"))
        var executable = destination + "/" + item.label
        var command: List[String] = [toolchain, "build"]
        command.extend(all_flags.copy())
        command.extend([String("-I"), root, driver, String("-o"), executable])
        var joined = String()
        for i in range(len(command)):
            joined += (" " if i > 0 else "") + command[i]
        print("BUILD", item.label, joined, flush=True)
        var launch = resource_guard(destination)
        var started = perf_counter_ns()
        var result = run_program(command, timeout, True, root)
        var log = destination + "/" + item.label + ".build.log"
        Path(log).write_text(result.output)
        if result.timed_out:
            raise Error(
                "Command '"
                + _command_text(command)
                + "' timed out after "
                + String(timeout)
                + " seconds"
            )
        var after = source_record(tree, item.value)
        if not tree.equal(before, after):
            raise Error(
                "Source changed during "
                + item.label
                + " build; record rejected"
            )
        if result.status != 0:
            raise Error("Build failed: " + log)
        var seconds = Float64(perf_counter_ns() - started) / 1e9
        var revision = String("uncommitted source snapshot")
        for other in revision_list:
            if other.label == item.label:
                revision = other.value
        var variant = tree.object()
        tree.set(variant, "binary", tree.string(executable))
        tree.set(variant, "binary_sha256", tree.string(sha(executable)))
        tree.set(variant, "source", before)
        tree.set(variant, "command", tree.strings(command))
        tree.set(variant, "build_seconds", tree.number(seconds))
        tree.set(variant, "launch_resources", launch.to_json(tree))
        tree.set(variant, "revision", tree.string(revision))
        tree.set(variants, item.label, variant)
        write_json(tree, record, record_path)
    var dynamic = tree.find(variants, "dynamic")
    var stride = tree.find(variants, "stride")
    if dynamic != ABSENT and stride != ABSENT:
        var dynamic_files = tree.get(tree.get(dynamic, "source"), "files")
        var stride_files = tree.get(tree.get(stride, "source"), "files")
        var dynamic_names = tree.keys(dynamic_files)
        var stride_names = tree.keys(stride_files)
        var same = len(dynamic_names) == len(stride_names)
        for name in dynamic_names:
            if tree.find(stride_files, name) == ABSENT:
                same = False
        if not same:
            raise Error(
                "Dynamic and stride file lists differ; refresh stride from the"
                " final candidate"
            )
        var changed = List[String]()
        for name in dynamic_names:
            if tree.text(tree.get(dynamic_files, name)) != tree.text(
                tree.get(stride_files, name)
            ):
                changed.append(name)
        if len(changed) != 1 or changed[0] != "loaders/image_batch.mojo":
            raise Error(
                "Experimental control differs outside its scheduler: "
                + _python_list(changed)
                + "; refresh stride"
            )
    tree.set(record, "status", tree.string("complete"))
    write_json(tree, record, record_path)
    print("BUILD_RECORD", record_path)


# --- host ----------------------------------------------------------------------


def _uname() -> List[String]:
    """Return `uname` as system, node, release, version and machine."""
    var buffer = List[UInt8](length=2048, fill=0)
    _ = external_call["uname", Int32](
        buffer.unsafe_ptr().unsafe_bitcast[NoneType]()
    )
    var width: Int
    comptime if CompilationTarget.is_macos():
        width = 256
    else:
        width = 65
    var fields = List[String]()
    for index in range(5):
        var text = List[UInt8]()
        for i in range(width):
            var byte = buffer[index * width + i]
            if byte == 0:
                break
            text.append(byte)
        fields.append(String(from_utf8_lossy=text))
    return fields^


def platform_text() -> String:
    """Return a platform name in the form of `platform.platform()`.

    Returns:
        `Linux-RELEASE-MACHINE-with-glibcVERSION` on Linux, or
        `SYSTEM-RELEASE-MACHINE` elsewhere.
    """
    var fields = _uname()
    var text = fields[0] + "-" + fields[2] + "-" + fields[4]
    comptime if CompilationTarget.is_macos():
        return text
    else:
        var version = _read_c_string(
            external_call["gnu_get_libc_version", Int]()
        )
        return text + "-with-glibc" + version


def _affinity() -> List[Int]:
    """Return the CPUs this process can run on, on Linux."""
    var cpus = List[Int]()
    comptime if not CompilationTarget.is_macos():
        var mask = List[UInt8](length=128, fill=0)
        var status = external_call["sched_getaffinity", Int32](
            Int32(0), Int(128), mask.unsafe_ptr().unsafe_bitcast[NoneType]()
        )
        if status == 0:
            for i in range(128 * 8):
                if (Int(mask[i // 8]) >> (i % 8)) & 1:
                    cpus.append(i)
    return cpus^


def host_record(mut tree: JsonTree) raises -> Int:
    """Add the host description that a run records before and after.

    Args:
        tree: The tree.

    Returns:
        The object node.

    Raises:
        Error: If a value cannot be written.
    """
    var record = tree.object()
    var fields = _uname()
    var processor = String()
    try:
        var result = run_program(["uname", "-p"], 10)
        if result.status == 0:
            processor = String(result.output.strip())
    except:
        pass
    if processor == "unknown":
        processor = String()
    tree.set(record, "platform", tree.string(platform_text()))
    tree.set(record, "machine", tree.string(fields[4]))
    tree.set(record, "runner_language", tree.string("Mojo"))
    tree.set(record, "processor", tree.string(processor))
    var models = List[String]()
    var cpuinfo = read_optional("/proc/cpuinfo")
    if cpuinfo:
        for line in split_lines(cpuinfo.value()):
            if line.startswith("model name") or line.startswith("Hardware"):
                var at = line.find(":")
                if at < 0:
                    raise Error("list index out of range")
                var model = String(String(line[byte = at + 1 :]).strip())
                if not model in models:
                    models.append(model)
    var sorted_models = List[String]()
    for model in models:
        var position = 0
        while position < len(sorted_models) and sorted_models[position] < model:
            position += 1
        sorted_models.insert(position, model)
    tree.set(record, "cpu_models", tree.strings(sorted_models))
    tree.set(record, "logical_cpu_count", tree.integer(num_logical_cores()))
    if _is_linux():
        tree.set(record, "affinity", tree.integers(_affinity()))
    else:
        tree.set(record, "affinity", tree.null())
    var loads = List[Float64](length=3, fill=0)
    var count = external_call["getloadavg", Int32](
        loads.unsafe_ptr().unsafe_bitcast[NoneType](), Int32(3)
    )
    if count == 3:
        var load = tree.array()
        for value in loads:
            tree.append(load, tree.number(value))
        tree.set(record, "load_average", load)
    else:
        tree.set(record, "load_average", tree.null())
    tree.set(
        record, "meminfo", _optional_text(tree, read_optional("/proc/meminfo"))
    )
    tree.set(
        record,
        "cgroup_cpu_max",
        _optional_text(tree, read_optional("/sys/fs/cgroup/cpu.max")),
    )
    tree.set(
        record,
        "cgroup_memory_max",
        _optional_text(tree, read_optional("/sys/fs/cgroup/memory.max")),
    )
    tree.set(
        record,
        "cgroup_cpuset",
        _optional_text(
            tree, read_optional("/sys/fs/cgroup/cpuset.cpus.effective")
        ),
    )
    tree.set(
        record,
        "cpu0_governor",
        _optional_text(
            tree,
            read_optional(
                "/sys/devices/system/cpu/cpu0/cpufreq/scaling_governor"
            ),
        ),
    )
    var environment = tree.object()
    for key in [
        "MODULAR_NUM_THREADS",
        "MOJO_NUM_THREADS",
        "OMP_NUM_THREADS",
        "OMP_THREAD_LIMIT",
        "OPENBLAS_NUM_THREADS",
        "MKL_NUM_THREADS",
        "MODULAR_THREAD_BUSY_WAIT_US",
    ]:
        var value = environment_value(key)
        if value:
            tree.set(environment, key, tree.string(value.value()))
    tree.set(record, "runtime_environment", environment)
    return record


# --- measurement ---------------------------------------------------------------


def lines_with_ends(text: String) -> List[String]:
    """Split text after each line boundary, as `splitlines(keepends=True)`.

    The boundaries are those of `tools._text.split_lines`: LF, CR, CR LF,
    VT, FF, 0x1C to 0x1E, NEL, LINE SEPARATOR and PARAGRAPH SEPARATOR.

    Args:
        text: The text.

    Returns:
        The lines, each with its boundary. A final boundary does not make
        an empty last line.
    """
    var bytes = text.as_bytes()
    var lines = List[String]()
    var start = 0
    var i = 0
    while i < len(bytes):
        var width = 0
        var byte = Int(bytes[i])
        if byte == 0x0D:
            width = 2 if i + 1 < len(bytes) and Int(bytes[i + 1]) == 0x0A else 1
        elif (
            byte == 0x0A
            or byte == 0x0B
            or byte == 0x0C
            or (byte >= 0x1C and byte <= 0x1E)
        ):
            width = 1
        elif byte == 0xC2 and i + 1 < len(bytes) and Int(bytes[i + 1]) == 0x85:
            width = 2
        elif (
            byte == 0xE2
            and i + 2 < len(bytes)
            and Int(bytes[i + 1]) == 0x80
            and (Int(bytes[i + 2]) == 0xA8 or Int(bytes[i + 2]) == 0xA9)
        ):
            width = 3
        if width > 0:
            i += width
            lines.append(String(unsafe_from_utf8=Span(bytes)[start:i]))
            start = i
        else:
            i += 1
    if start < len(bytes):
        lines.append(String(unsafe_from_utf8=Span(bytes)[start:]))
    return lines^


@fieldwise_init
struct Usage(Movable):
    """A parsed supervisor record and the native standard error."""

    var record: Int
    """The usage object node."""
    var native_stderr: String
    """The standard error without the marker line."""


def _rss_unit() -> String:
    """Return the `ru_maxrss` unit of this platform."""
    comptime if CompilationTarget.is_macos():
        return "bytes"
    else:
        return "KiB"


def parse_rusage(mut tree: JsonTree, stderr_text: String) raises -> Usage:
    """Read one exact supervisor record and keep the native stderr text.

    Args:
        tree: The tree for the record.
        stderr_text: The supervisor's whole standard error.

    Returns:
        The usage object and the other lines.

    Raises:
        Error: If there is not exactly one marker line, or its platform,
            unit, schema or byte conversion is wrong.
    """
    var lines = lines_with_ends(stderr_text)
    var marker = -1
    var count = 0
    var rest = String()
    for i in range(len(lines)):
        if lines[i].startswith(RUSAGE_MARKER):
            marker = i
            count += 1
        else:
            rest += lines[i]
    if count != 1:
        raise Error("Expected exactly one RSS supervisor marker")
    var text = String(
        lines[marker][byte = String(RUSAGE_MARKER).byte_length() :]
    )
    var result = tree.parse(text)
    var unit = tree.find(result, "rss_unit")
    var schema = tree.find(result, "schema")
    var expected = _rss_unit()
    if (
        unit == ABSENT
        or not _is_string(tree, unit)
        or tree.text(unit) != expected
        or schema == ABSENT
        or not tree.equal(schema, tree.integer(1))
    ):
        raise Error("Unsupported RSS supervisor platform, units, or schema")
    var multiplier = 1024 if expected == "KiB" else 1
    var raw = tree.get(result, "maxrss_raw")
    var raw_value = tree.float_value(raw)
    var peak = tree.get(result, "peak_rss_bytes")
    var valid = raw_value >= 0
    if valid:
        if tree.is_integer(raw) and tree.is_integer(peak):
            valid = tree.int_value(peak) == tree.int_value(raw) * multiplier
        else:
            valid = tree.float_value(peak) == raw_value * Float64(multiplier)
    if not valid:
        raise Error("Invalid RSS supervisor unit conversion")
    return Usage(result, rest^)


def _integer_or_float(tree: JsonTree, node: Int) raises -> Int:
    """Return an integer usage value, rejecting other kinds."""
    if not tree.is_integer(node):
        raise Error("expected an integer usage value")
    return tree.int_value(node)


def measurement_row(
    mut tree: JsonTree,
    command: List[String],
    wrapper_command: List[String],
    exit_code: Int,
    timed_out: Bool,
    launch_resources: Int,
    wall_ns: Int,
    stdout_text: String,
    stderr_text: String,
) raises -> Int:
    """Build the evidence row of one supervised launch.

    The supervisor's exit status must equal the native status that it
    reports. Any parse or agreement failure becomes `measurement_error`.

    Args:
        tree: The tree for the row.
        command: The native command.
        wrapper_command: The supervisor command.
        exit_code: The supervisor's exit status, or minus its signal.
        timed_out: True when the time limit stopped the group.
        launch_resources: The resource reading node.
        wall_ns: The wall time in nanoseconds.
        stdout_text: The native standard output.
        stderr_text: The supervisor's standard error.

    Returns:
        The row object node.

    Raises:
        Error: If the row cannot be built.
    """
    var row = tree.object()
    var command_node = tree.strings(command)
    tree.set(row, "command", command_node)
    tree.set(row, "native_command", command_node)
    tree.set(row, "wrapper_command", tree.strings(wrapper_command))
    tree.set(row, "exit_code", tree.integer(exit_code))
    tree.set(row, "timed_out", tree.boolean(timed_out))
    tree.set(row, "launch_resources", launch_resources)
    tree.set(row, "wall_ns", tree.integer(wall_ns))
    tree.set(row, "peak_rss_bytes", tree.null())
    tree.set(row, "stdout", tree.string(stdout_text))
    tree.set(row, "stderr", tree.string(stderr_text))
    tree.set(row, "wrapper_stderr", tree.string(stderr_text))
    tree.set(row, "measurement_error", tree.null())
    try:
        var usage = parse_rusage(tree, stderr_text)
        tree.set(row, "rusage", usage.record)
        tree.set(row, "stderr", tree.string(usage.native_stderr))
        for key in [
            "peak_rss_bytes",
            "user_seconds",
            "system_seconds",
            "minor_faults",
            "major_faults",
            "voluntary_context_switches",
            "involuntary_context_switches",
        ]:
            tree.set(row, key, tree.get(usage.record, key))
        var signal = _integer_or_float(
            tree, tree.get(usage.record, "native_signal")
        )
        var native_code = -signal if signal != 0 else _integer_or_float(
            tree, tree.get(usage.record, "native_exit_status")
        )
        tree.set(row, "native_exit_code", tree.integer(native_code))
        if native_code != exit_code:
            raise Error(
                "Supervisor did not propagate the native exit/signal status"
            )
        var errno = _integer_or_float(
            tree, tree.get(usage.record, "exec_errno")
        )
        if errno != 0:
            raise Error("Native exec failed with errno " + String(errno))
    except error:
        tree.set(row, "measurement_error", tree.string(String(error)))
    return row


@fieldwise_init
struct Launch(Movable):
    """What one supervised launch left."""

    var exit_code: Int
    """The exit status, or minus the signal that stopped the process."""
    var timed_out: Bool
    """True when the time limit stopped the process group."""
    var stdout: String
    """The standard output."""
    var stderr: String
    """The standard error."""
    var wall_ns: Int
    """The wall time from launch to reaping, in nanoseconds."""


def _environ() raises -> Int:
    """Return the address of this process's environment array."""
    comptime if CompilationTarget.is_macos():
        var cell = external_call["_NSGetEnviron", Int]()
        var value = List[Int](length=1, fill=0)
        _ = external_call["memcpy", Int](
            value.unsafe_ptr().unsafe_bitcast[NoneType](), cell, 8
        )
        return value[0]
    else:
        var handle = OwnedDLHandle()
        var symbol = handle.get_symbol[Int]("environ")
        var address: Int = symbol[][]
        return address


comptime _SHELL = (
    'cd -- "$1" || exit 125\nout=$2\nerr=$3\nshift 3\nexec "$@" >"$out"'
    ' 2>"$err"\n'
)


def launch_group(
    arguments: List[String], directory: String, timeout: Float64
) raises -> Launch:
    """Run a program in a new process group, and kill the group at the time
    limit, as `Popen(start_new_session=True)` and `os.killpg` do.

    Args:
        arguments: The program and its arguments.
        directory: The working directory.
        timeout: The time limit in seconds.

    Returns:
        The status, the two outputs, and the wall time.

    Raises:
        Error: If the folder or program does not exist, or the process
            cannot start.
    """
    if not isdir(directory):
        raise Error("[Errno 2] No such file or directory: '" + directory + "'")
    var program = arguments[0]
    if "/" in program and not exists(program):
        raise Error("[Errno 2] No such file or directory: '" + program + "'")
    var scratch = mkdtemp(prefix="threemojo-measure-")
    var out_path = scratch + "/stdout"
    var err_path = scratch + "/stderr"
    var words: List[String] = [
        "/bin/sh",
        "-c",
        _SHELL,
        "sh",
        directory,
        out_path,
        err_path,
    ]
    words.extend(arguments.copy())
    var strings = List[List[UInt8]]()
    for word in words:
        strings.append(_c_string(word))
    var addresses = List[Int]()
    for i in range(len(strings)):
        addresses.append(Int(strings[i].unsafe_ptr()))
    addresses.append(0)
    var attributes = List[UInt8](length=1024, fill=0)
    var pointer = attributes.unsafe_ptr().unsafe_bitcast[NoneType]()
    _ = external_call["posix_spawnattr_init", Int32](pointer)
    _ = external_call["posix_spawnattr_setflags", Int32](
        pointer, Int16(_POSIX_SPAWN_SETPGROUP)
    )
    _ = external_call["posix_spawnattr_setpgroup", Int32](pointer, Int32(0))
    var pid = List[Int32](length=1, fill=0)
    var status = List[Int32](length=1, fill=0)
    var started = perf_counter_ns()
    var spawned = external_call["posix_spawn", Int32](
        pid.unsafe_ptr().unsafe_bitcast[NoneType](),
        strings[0].unsafe_ptr().unsafe_bitcast[NoneType](),
        Int(0),
        pointer,
        addresses.unsafe_ptr().unsafe_bitcast[NoneType](),
        _environ(),
    )
    _ = external_call["posix_spawnattr_destroy", Int32](pointer)
    if spawned != 0:
        raise Error("posix_spawn failed with error " + String(spawned))
    var timed_out = False
    var delay = 0.0005
    while True:
        var waited = external_call["waitpid", Int32](
            pid[0],
            status.unsafe_ptr().unsafe_bitcast[NoneType](),
            Int32(_WNOHANG),
        )
        if waited == pid[0]:
            break
        if Float64(perf_counter_ns() - started) / 1e9 >= timeout:
            timed_out = True
            _ = external_call["killpg", Int32](pid[0], Int32(_SIGKILL))
            for _ in range(10000):
                waited = external_call["waitpid", Int32](
                    pid[0],
                    status.unsafe_ptr().unsafe_bitcast[NoneType](),
                    Int32(0),
                )
                if waited == pid[0]:
                    break
            break
        sleep(delay)
        delay = min(delay * 2, 0.05)
    var wall_ns = Int(perf_counter_ns() - started)
    _ = attributes^
    _ = addresses^
    _ = strings^
    var raw = Int(status[0])
    var code: Int
    if raw & 0x7F == 0:
        code = (raw >> 8) & 0xFF
    else:
        code = -(raw & 0x7F)
    var output = String(from_utf8_lossy=Path(out_path).read_bytes()) if exists(
        out_path
    ) else String()
    var errors = String(from_utf8_lossy=Path(err_path).read_bytes()) if exists(
        err_path
    ) else String()
    for name in listdir(scratch):
        remove(scratch + "/" + name)
    rmdir(scratch)
    return Launch(code, timed_out, output^, errors^, wall_ns)


trait Measurer:
    """Something that launches one native command and returns its row."""

    def measure(
        mut self,
        mut tree: JsonTree,
        command: List[String],
        timeout: Float64,
        directory: String,
        helper: String,
    ) raises -> Int:
        """Launch a command and return its evidence row.

        Args:
            tree: The tree for the row.
            command: The native command.
            timeout: The time limit in seconds.
            directory: The working directory.
            helper: The RSS supervisor.

        Returns:
            The row object node.

        Raises:
            Error: If the launch cannot happen.
        """
        ...


def measure(
    mut tree: JsonTree,
    command: List[String],
    timeout: Float64,
    directory: String,
    helper: String,
) raises -> Int:
    """Measure the supervisor's child, never the runner's own RSS.

    Args:
        tree: The tree for the row.
        command: The native command.
        timeout: The time limit in seconds.
        directory: The working directory.
        helper: The RSS supervisor.

    Returns:
        The row object node.

    Raises:
        Error: If a resource guard fails or the process cannot start.
    """
    var launch = resource_guard(directory)
    var wrapper: List[String] = [resolve_path(helper), "--"]
    wrapper.extend(command.copy())
    var result = launch_group(wrapper, directory, timeout)
    return measurement_row(
        tree,
        command,
        wrapper,
        result.exit_code,
        result.timed_out,
        launch.to_json(tree),
        result.wall_ns,
        result.stdout,
        result.stderr,
    )


struct NativeMeasurer(Measurer):
    """The real measurer: the supervisor launches the native program."""

    def __init__(out self):
        """Make the measurer."""
        pass

    def measure(
        mut self,
        mut tree: JsonTree,
        command: List[String],
        timeout: Float64,
        directory: String,
        helper: String,
    ) raises -> Int:
        """Launch a command under the supervisor.

        Args:
            tree: The tree for the row.
            command: The native command.
            timeout: The time limit in seconds.
            directory: The working directory.
            helper: The RSS supervisor.

        Returns:
            The row object node.

        Raises:
            Error: As `measure` does.
        """
        return measure(tree, command, timeout, directory, helper)


def parse_output(mut tree: JsonTree, stdout_text: String) raises -> Int:
    """Read the native program's one `result` line.

    Args:
        tree: The tree for the values.
        stdout_text: The native standard output.

    Returns:
        An object of each key and value. `api` is a string; every other
        value is an integer.

    Raises:
        Error: If there is not exactly one result line, its keys and values
            do not pair, a key repeats, or a value is not an integer.
    """
    var found = List[String]()
    for line in split_lines(stdout_text):
        if line.startswith("result "):
            found.append(line)
    if len(found) != 1:
        raise Error("Expected exactly one native result line")
    var parts = _python_split(found[0])
    _ = parts.pop(0)
    if len(parts) % 2:
        raise Error("Malformed native key/value result")
    var keys = List[String]()
    var values = List[String]()
    for i in range(0, len(parts), 2):
        var at = -1
        for k in range(len(keys)):
            if keys[k] == parts[i]:
                at = k
        if at >= 0:
            values[at] = parts[i + 1]
        else:
            keys.append(parts[i])
            values.append(parts[i + 1])
    if len(keys) * 2 != len(parts):
        raise Error("Duplicate native output keys")
    var result = tree.object()
    for i in range(len(keys)):
        if keys[i] == "api":
            tree.set(result, keys[i], tree.string(values[i]))
        else:
            tree.set(result, keys[i], tree.integer_text(values[i]))
    return result


# --- summaries -----------------------------------------------------------------


def _number(tree: JsonTree, node: Int) raises -> PyNumber:
    """Return a JSON number as a Python `int` or `float`."""
    if tree.is_integer(node):
        return PyNumber.of_int(tree.int_value(node))
    return PyNumber.of_float(tree.float_value(node))


def _divide(a: PyNumber, b: PyNumber) raises -> Float64:
    """Return `a / b` for Python numbers."""
    if a.is_int and b.is_int:
        return true_divide(a.integer, b.integer)
    return a.as_float() / b.as_float()


@fieldwise_init
struct _Group(Copyable, Movable):
    """The key of one summary group."""

    var dataset: String
    var api: String
    var workers: Int
    var variant: String

    def less(self, other: _Group) -> Bool:
        """Return whether this key sorts first, as tuples compare."""
        if self.dataset != other.dataset:
            return self.dataset < other.dataset
        if self.api != other.api:
            return self.api < other.api
        if self.workers != other.workers:
            return self.workers < other.workers
        return self.variant < other.variant

    def same(self, other: _Group) -> Bool:
        """Return whether two keys are equal."""
        return (
            self.dataset == other.dataset
            and self.api == other.api
            and self.workers == other.workers
            and self.variant == other.variant
        )


def _group_of(tree: JsonTree, row: Int) raises -> _Group:
    """Return a row's group key."""
    return _Group(
        tree.text(tree.get(row, "dataset")),
        tree.text(tree.get(row, "api")),
        tree.int_value(tree.get(row, "workers")),
        tree.text(tree.get(row, "variant")),
    )


def summarize(
    tree: JsonTree, rows: List[Int], baseline: String, mut out: JsonTree
) raises -> Int:
    """Summarize validated rows by dataset, API, workers and variant.

    Each group has distributions of load time, peak RSS, images per second
    and base megapixels per second. A group with a paired baseline row in
    the same repetition also has paired speedup and RSS ratio
    distributions.

    Args:
        tree: The rows' tree.
        rows: The validated rows.
        baseline: The baseline variant label.
        out: The tree for the summary.

    Returns:
        The summary array node.

    Raises:
        Error: If a row lacks a field.
    """
    var groups = List[_Group]()
    var members = List[List[Int]]()
    for row in rows:
        var key = _group_of(tree, row)
        var at = -1
        for i in range(len(groups)):
            if groups[i].same(key):
                at = i
        if at < 0:
            groups.append(key^)
            members.append(List[Int]())
            at = len(groups) - 1
        members[at].append(row)
    var order = List[Int]()
    for i in range(len(groups)):
        var position = len(order)
        while position > 0 and groups[i].less(groups[order[position - 1]]):
            position -= 1
        order.insert(position, i)
    var result = out.array()
    var fields = check_fields()
    for index in order:
        ref key = groups[index]
        ref group = members[index]
        var item = out.object()
        out.set(item, "dataset", out.string(key.dataset))
        out.set(item, "api", out.string(key.api))
        out.set(item, "workers", out.integer(key.workers))
        out.set(item, "variant", out.string(key.variant))
        var loads = List[PyNumber]()
        var peaks = List[PyNumber]()
        var images = List[PyNumber]()
        var megapixels = List[PyNumber]()
        var parallelism = List[Int]()
        for row in group:
            var native = tree.get(row, "native")
            var load = _number(tree, tree.get(native, "load_ns"))
            loads.append(load.copy())
            peaks.append(_number(tree, tree.get(row, "peak_rss_bytes")))
            var textures = _number(tree, tree.get(native, "textures"))
            images.append(
                PyNumber.of_float(
                    _divide(PyNumber.of_float(textures.as_float() * 1e9), load)
                )
            )
            var base = _number(tree, tree.get(native, "base_bytes"))
            var scaled = PyNumber.of_int(
                base.integer * 250
            ) if base.is_int else PyNumber.of_float(base.as_float() * 250)
            megapixels.append(PyNumber.of_float(_divide(scaled, load)))
            var level = tree.int_value(tree.get(native, "runtime_parallelism"))
            if not level in parallelism:
                var position = 0
                while (
                    position < len(parallelism)
                    and parallelism[position] < level
                ):
                    position += 1
                parallelism.insert(position, level)
        out.set(item, "load_ns", distribution(out, loads))
        out.set(item, "peak_rss_bytes", distribution(out, peaks))
        out.set(item, "images_per_second", distribution(out, images))
        out.set(
            item, "base_megapixels_per_second", distribution(out, megapixels)
        )
        out.set(item, "runtime_parallelism", out.integers(parallelism))
        var checksums = out.object()
        var first = tree.get(group[0], "native")
        for field in fields:
            out.set(
                checksums,
                field,
                out.integer_text(tree.text(tree.get(first, field))),
            )
        out.set(item, "checksums", checksums)
        var speedups = List[PyNumber]()
        var ratios = List[PyNumber]()
        for row in group:
            var repetition = tree.int_value(tree.get(row, "repetition"))
            # The last baseline row of this pair key, as the dict keeps it.
            var paired = -1
            for other in rows:
                if (
                    tree.text(tree.get(other, "dataset")) == key.dataset
                    and tree.text(tree.get(other, "api")) == key.api
                    and tree.int_value(tree.get(other, "workers"))
                    == key.workers
                    and tree.int_value(tree.get(other, "repetition"))
                    == repetition
                    and tree.text(tree.get(other, "variant")) == baseline
                ):
                    paired = other
            if paired >= 0:
                var base_load = _number(
                    tree, tree.get(tree.get(paired, "native"), "load_ns")
                )
                var load = _number(
                    tree, tree.get(tree.get(row, "native"), "load_ns")
                )
                speedups.append(PyNumber.of_float(_divide(base_load, load)))
                ratios.append(
                    PyNumber.of_float(
                        _divide(
                            _number(tree, tree.get(row, "peak_rss_bytes")),
                            _number(tree, tree.get(paired, "peak_rss_bytes")),
                        )
                    )
                )
        if len(speedups) > 0:
            out.set(
                item,
                "paired_speedup_vs_" + baseline,
                distribution(out, speedups),
            )
            out.set(
                item,
                "paired_rss_ratio_vs_" + baseline,
                distribution(out, ratios),
            )
        out.append(result, item)
    return result


# --- runs ----------------------------------------------------------------------


struct RunOptions(Movable):
    """The options of a `run`."""

    var build: String
    """The `build.json` file."""
    var fixtures: String
    """The fixture folder."""
    var destination: String
    """A new folder for the results."""
    var baseline: String
    """The baseline variant label."""
    var repetitions: Int
    """The number of paired trials of each case."""
    var workers: List[Int]
    """The worker counts, or empty for 1, 2, 4 and the count plus one."""
    var datasets: List[String]
    """The dataset names, or empty for all."""
    var apis: List[String]
    """The APIs: `gltf`, `registry` or both."""
    var seed: Int
    """The case-order seed."""
    var timeout: Float64
    """Each launch's time limit in seconds."""

    def __init__(
        out self, build: String, fixtures: String, destination: String
    ):
        """Make the default options for a build, fixtures and destination.

        Args:
            build: The `build.json` file.
            fixtures: The fixture folder.
            destination: A new folder for the results.
        """
        self.build = build
        self.fixtures = fixtures
        self.destination = destination
        self.baseline = "baseline"
        self.repetitions = 3
        self.workers = List[Int]()
        self.datasets = List[String]()
        self.apis = [String("gltf"), String("registry")]
        self.seed = 505
        self.timeout = 120


@fieldwise_init
struct _Case(Copyable, Movable):
    """One dataset, API and worker count."""

    var dataset: String
    var api: String
    var workers: Int

    def same(self, other: _Case) -> Bool:
        """Return whether two cases are equal."""
        return (
            self.dataset == other.dataset
            and self.api == other.api
            and self.workers == other.workers
        )


def _join(folder: String, name: String) -> String:
    """Return `folder / name` as `pathlib` writes it."""
    var base = folder
    while base.endswith("/") and base.byte_length() > 1:
        var shorter = String(base[byte = : base.byte_length() - 1])
        base = shorter
    if base.startswith("./") and base.byte_length() > 2:
        var shorter = String(base[byte=2:])
        base = shorter
    if base == ".":
        return name
    return base + "/" + name


def _append_line(path: String, line: String) raises:
    """Append a line to a file."""
    with open(path, "a") as stream:
        stream.write(line + "\n")


def _is_string(tree: JsonTree, node: Int) raises -> Bool:
    """Return whether a node is a string."""
    return tree.kind(node) == STRING


def run[M: Measurer](options: RunOptions, mut measurer: M) raises:
    """Measure fresh binaries serially, in paired, shuffled trials.

    Each trial launches every variant once, in a rotated order. Every row
    is saved before it is validated. A row must match the fixture oracle
    and every earlier row of the same dataset.

    Parameters:
        M: The measurer type.

    Args:
        options: The run options.
        measurer: The launcher of each native command.

    Raises:
        Error: If a record, binary or fixture changed, a launch fails, or a
            result disagrees with the oracle.
    """
    var tree = JsonTree()
    var build_record = read_json(tree, options.build)
    var status = tree.find(build_record, "status")
    if (
        status == ABSENT
        or not _is_string(tree, status)
        or tree.text(status) != "complete"
    ):
        raise Error("Build record is incomplete or failed")
    var fixtures = read_json(tree, _join(options.fixtures, "fixtures.json"))
    var variants = tree.get(build_record, "variants")
    var helper_record = tree.find(build_record, "rusage_helper")
    if not tree.truthy(helper_record):
        raise Error(
            "RSS helper missing; run build-rusage before measuring. Old smoke"
            " RSS is invalid."
        )
    var helper = tree.string_value(tree.get(helper_record, "binary"))
    if sha(helper) != tree.text(tree.get(helper_record, "binary_sha256")):
        raise Error("RSS supervisor binary changed since its build record")
    if (
        tree.find(variants, options.baseline) == ABSENT
        or tree.length(variants) < 2
    ):
        raise Error("Need a named baseline and at least one comparison variant")
    var destination = resolve_path(options.destination)
    if exists(destination):
        raise Error("[Errno 17] File exists: '" + destination + "'")
    makedirs(destination)
    if options.repetitions < 1:
        raise Error("repetitions must be positive")
    var labels = tree.keys(variants)
    for label in labels:
        var info = tree.get(variants, label)
        if sha(tree.string_value(tree.get(info, "binary"))) != tree.text(
            tree.get(info, "binary_sha256")
        ):
            raise Error("Binary changed since build: " + label)
    var names = List[String]()
    var entries = List[Int]()
    var listed = tree.get(fixtures, "datasets")
    for index in range(tree.length(listed)):
        var entry = tree.at(listed, index)
        var name = tree.string_value(tree.get(entry, "name"))
        var at = -1
        for i in range(len(names)):
            if names[i] == name:
                at = i
        if at >= 0:
            entries[at] = entry
        else:
            names.append(name)
            entries.append(entry)
    var selected = (
        options.datasets.copy() if len(options.datasets) > 0 else names.copy()
    )
    var chosen = List[Int]()
    for name in selected:
        var at = -1
        for i in range(len(names)):
            if names[i] == name:
                at = i
        if at < 0:
            raise Error("'" + name + "'")
        chosen.append(entries[at])
        var files = tree.get(entries[at], "files")
        var folder = _join(
            options.fixtures, tree.string_value(tree.get(entries[at], "path"))
        )
        for k in range(tree.length(files)):
            var item = tree.at(files, k)
            var path = _join(folder, tree.string_value(tree.get(item, "path")))
            var size = len(Path(path).read_bytes())
            if size != tree.int_value(tree.get(item, "bytes")) or sha(
                path
            ) != tree.text(tree.get(item, "sha256")):
                raise Error("Fixture changed: " + path)
    var cases = List[_Case]()
    for c in range(len(selected)):
        var choices = options.workers.copy()
        if len(choices) == 0:
            choices = [
                1,
                2,
                4,
                tree.int_value(tree.get(chosen[c], "count")) + 1,
            ]
        var unique = List[Int]()
        for worker in choices:
            if not worker in unique:
                unique.append(worker)
        for worker in unique:
            if worker < 1:
                raise Error("worker counts must be positive")
            for api in options.apis:
                cases.append(_Case(selected[c], api, worker))
    var metadata = tree.object()
    tree.set(metadata, "schema", tree.integer(1))
    tree.set(metadata, "started_utc", tree.string(now()))
    tree.set(metadata, "status", tree.string("running"))
    tree.set(metadata, "host", host_record(tree))
    tree.set(metadata, "build", build_record)
    tree.set(
        metadata,
        "fixtures_manifest_sha256",
        tree.string(sha(_join(options.fixtures, "fixtures.json"))),
    )
    tree.set(metadata, "fixtures", fixtures)
    tree.set(metadata, "repetitions", tree.integer(options.repetitions))
    tree.set(metadata, "seed", tree.integer(options.seed))
    tree.set(metadata, "runner_sha256", tree.string(sha(runner_source())))
    tree.set(metadata, "requested_variants", tree.strings(labels))
    tree.set(
        metadata,
        "measurement",
        tree.string(
            "low-RSS C fork/exec/wait4 supervisor; one fresh native child per"
            " row; serial paired runs"
        ),
    )
    tree.set(
        metadata,
        "invalid_prior_method",
        tree.string(
            "Direct Python-child wait4 RSS can retain parent heap high-water"
            " floors; do not cite old smoke RSS"
        ),
    )
    tree.set(
        metadata,
        "timer_scope",
        tree.string(
            "read_gltf including JSON/geometry, or preload excluding"
            " AssetRegistry.open"
        ),
    )
    tree.set(
        metadata,
        "page_cache",
        tree.string(
            "all case inputs read into OS page cache before each paired trial"
        ),
    )
    tree.set(
        metadata,
        "runtime",
        tree.string(
            "parallelism_level queried before timing; no task/decode warm-up"
        ),
    )
    tree.set(
        metadata,
        "rss_scope",
        tree.string(
            "entire process including setup and post-timer checksums, not"
            " isolated scratch"
        ),
    )
    var planned = len(cases) * options.repetitions * len(labels)
    tree.set(metadata, "planned_rows", tree.integer(planned))
    write_json(tree, metadata, destination + "/metadata.json")
    var rows = List[Int]()
    try:
        _measure_all(
            tree,
            options,
            measurer,
            cases,
            names,
            entries,
            labels,
            variants,
            helper,
            destination,
            planned,
            rows,
        )
        tree.set(metadata, "status", tree.string("complete"))
    except error:
        tree.set(metadata, "status", tree.string("failed"))
        tree.set(metadata, "error", tree.string(String(error)))
        _finish(tree, metadata, len(rows), destination)
        raise error^
    _finish(tree, metadata, len(rows), destination)
    print("RESULTS", destination)


def _finish(
    mut tree: JsonTree, metadata: Int, completed: Int, destination: String
) raises:
    """Record the end of a run and write its metadata."""
    tree.set(metadata, "finished_utc", tree.string(now()))
    tree.set(metadata, "completed_rows", tree.integer(completed))
    tree.set(metadata, "host_after", host_record(tree))
    write_json(tree, metadata, destination + "/metadata.json")


def _measure_all[
    M: Measurer
](
    mut tree: JsonTree,
    options: RunOptions,
    mut measurer: M,
    cases: List[_Case],
    names: List[String],
    entries: List[Int],
    labels: List[String],
    variants: Int,
    helper: String,
    destination: String,
    planned: Int,
    mut rows: List[Int],
) raises:
    """Run every repetition of every case and validate each row."""
    var random = PythonRandom(options.seed)
    var oracle_keys = List[String]()
    var oracle_values = List[String]()
    var shape_keys = List[String]()
    var shape_values = List[String]()
    var raw_path = destination + "/raw.jsonl"
    var validated_path = destination + "/validated.jsonl"
    Path(raw_path).write_text("")
    var fields = check_fields()
    for repetition in range(options.repetitions):
        var order = cases.copy()
        # random.shuffle: swap each place, last first, with one at or before it.
        var i = len(order) - 1
        while i >= 1:
            var j = random.choice(i + 1)
            order.swap_elements(i, j)
            i -= 1
        for case_index in range(len(order)):
            ref case_ = order[case_index]
            var fixture = -1
            for k in range(len(names)):
                if names[k] == case_.dataset:
                    fixture = entries[k]
            var folder = resolve_path(
                _join(
                    options.fixtures,
                    tree.string_value(tree.get(fixture, "path")),
                )
            )
            # Explicit warm-page-cache experiment. The native process is fresh.
            var files = tree.get(fixture, "files")
            for k in range(tree.length(files)):
                _ = Path(
                    folder
                    + "/"
                    + tree.string_value(tree.get(tree.at(files, k), "path"))
                ).read_bytes()
            # With three variants and three trials every variant leads once.
            var first = 0
            for k in range(len(cases)):
                if cases[k].same(case_):
                    first = k
                    break
            var offset = (repetition + first) % len(labels)
            var variant_order = List[String]()
            for k in range(len(labels)):
                variant_order.append(labels[(offset + k) % len(labels)])
            for position in range(len(variant_order)):
                var variant = variant_order[position]
                var binary = tree.string_value(
                    tree.get(tree.get(variants, variant), "binary")
                )
                var command: List[String] = [
                    binary,
                    folder,
                    case_.api,
                    String(case_.workers),
                ]
                var row = measurer.measure(
                    tree, command, options.timeout, folder, helper
                )
                tree.set(row, "dataset", tree.string(case_.dataset))
                tree.set(row, "api", tree.string(case_.api))
                tree.set(row, "workers", tree.integer(case_.workers))
                tree.set(row, "variant", tree.string(variant))
                tree.set(row, "repetition", tree.integer(repetition))
                tree.set(row, "recorded_utc", tree.string(now()))
                tree.set(row, "case_order", tree.integer(case_index))
                tree.set(row, "variant_order", tree.integer(position))
                var failed = (
                    tree.truthy(tree.get(row, "exit_code"))
                    or tree.truthy(tree.get(row, "timed_out"))
                    or tree.truthy(tree.get(row, "measurement_error"))
                )
                # Save evidence before validation, including a malformed result.
                _append_line(raw_path, compact(tree, row))
                if failed:
                    raise Error(
                        "Native process failed: "
                        + case_.dataset
                        + "/"
                        + case_.api
                        + "/"
                        + String(case_.workers)
                        + "/"
                        + variant
                    )
                var native = parse_output(
                    tree, tree.string_value(tree.get(row, "stdout"))
                )
                tree.set(row, "native", native)
                if (
                    tree.text(tree.get(native, "api")) != case_.api
                    or not tree.equal(
                        tree.get(native, "workers"), tree.integer(case_.workers)
                    )
                    or tree.float_value(tree.get(native, "load_ns")) <= 0
                ):
                    raise Error("Native result does not match the request")
                var expected = tree.get(fixture, "expected")
                for key in tree.keys(expected):
                    var value = tree.get(native, key)
                    var wanted = tree.get(expected, key)
                    if not tree.equal(value, wanted):
                        raise Error(
                            "Fixture oracle failed: "
                            + case_.dataset
                            + " "
                            + key
                            + ": "
                            + tree.text(value)
                            + " != "
                            + tree.text(wanted)
                        )
                var signature = String()
                for field in fields:
                    signature += tree.text(tree.get(native, field)) + ","
                var oracle_key = case_.dataset + "\n" + case_.api
                var at = -1
                for k in range(len(oracle_keys)):
                    if oracle_keys[k] == oracle_key:
                        at = k
                if at >= 0 and oracle_values[at] != signature:
                    raise Error(
                        "Output differs across variants/workers/trials: ('"
                        + case_.dataset
                        + "', '"
                        + case_.api
                        + "')"
                    )
                if at < 0:
                    oracle_keys.append(oracle_key)
                    oracle_values.append(signature)
                # Opaque albedo fixtures have equal pixel/mip output in both APIs.
                var shape = -1
                for k in range(len(shape_keys)):
                    if shape_keys[k] == case_.dataset:
                        shape = k
                if shape >= 0 and shape_values[shape] != signature:
                    raise Error(
                        "glTF/registry pixel or mip outputs differ: "
                        + case_.dataset
                    )
                if shape < 0:
                    shape_keys.append(case_.dataset)
                    shape_values.append(signature)
                rows.append(row)
                _append_line(validated_path, compact(tree, row))
                var load = tree.int_value(tree.get(native, "load_ns"))
                var peak = _number(tree, tree.get(row, "peak_rss_bytes"))
                print(
                    String(len(rows))
                    + "/"
                    + String(planned)
                    + " "
                    + case_.dataset
                    + " "
                    + case_.api
                    + " w="
                    + String(case_.workers)
                    + " "
                    + variant
                    + " "
                    + format_fixed(PyNumber.of_int(load).as_float() / 1e6, 3)
                    + " ms RSS="
                    + format_fixed(_divide(peak, PyNumber.of_int(_MIB)), 2)
                    + " MiB",
                    flush=True,
                )
                var summary = JsonTree()
                var node = summarize(tree, rows, options.baseline, summary)
                write_json(summary, node, destination + "/summary.json")


# --- command line --------------------------------------------------------------


def _usage() -> String:
    """Return the usage text."""
    return "usage: image_decode_bench [-h] {stride,build,build-rusage,run} ..."


def _fail(message: String):
    """Print a usage error and exit with status two, as `argparse` does."""
    print(_usage(), file=stderr)
    print("image_decode_bench: error: " + message, file=stderr)
    exit(2)


struct _Arguments(Movable):
    """Parsed options: single values, repeated values and lists."""

    var names: List[String]
    var values: List[List[String]]

    def __init__(out self):
        self.names = List[String]()
        self.values = List[List[String]]()

    def add(mut self, name: String, value: String):
        for i in range(len(self.names)):
            if self.names[i] == name:
                self.values[i].append(value)
                return
        self.names.append(name)
        self.values.append([value])

    def reset(mut self, name: String):
        for i in range(len(self.names)):
            if self.names[i] == name:
                self.values[i] = List[String]()
                return
        self.names.append(name)
        self.values.append(List[String]())

    def has(self, name: String) -> Bool:
        return name in self.names

    def all(self, name: String) -> List[String]:
        for i in range(len(self.names)):
            if self.names[i] == name:
                return self.values[i].copy()
        return List[String]()

    def last(self, name: String, default: String) -> String:
        var found = self.all(name)
        if len(found) == 0:
            return default
        return found[len(found) - 1]


def _looks_negative_number(word: String) -> Bool:
    """Return whether an argument is a negative number, as `argparse` sees."""
    if not word.startswith("-") or word.byte_length() < 2:
        return False
    try:
        _ = parse_float(String(word[byte=1:]))
        return True
    except:
        return False


def _parse(
    given: List[String],
    singles: List[String],
    appends: List[String],
    lists: List[String],
    required: List[String],
) -> _Arguments:
    """Read options as `argparse` does for one subcommand."""
    var parsed = _Arguments()
    var i = 0
    while i < len(given):
        var word = given[i]
        var value = String()
        var inline = False
        var at = word.find("=")
        if word.startswith("--") and at >= 0:
            value = String(word[byte = at + 1 :])
            var name = String(word[byte=:at])
            word = name
            inline = True
        if word == "-h" or word == "--help":
            print(_usage())
            exit(0)
        if word in singles or word in appends:
            if not inline:
                if i + 1 >= len(given) or (
                    given[i + 1].startswith("-")
                    and not _looks_negative_number(given[i + 1])
                ):
                    _fail("argument " + word + ": expected one argument")
                i += 1
                value = given[i]
            if word in singles:
                parsed.reset(word)
            parsed.add(word, value)
        elif word in lists:
            parsed.reset(word)
            var count = 0
            if inline:
                parsed.add(word, value)
                count += 1
            while i + 1 < len(given) and (
                not given[i + 1].startswith("-")
                or _looks_negative_number(given[i + 1])
            ):
                i += 1
                parsed.add(word, given[i])
                count += 1
            if count == 0:
                _fail("argument " + word + ": expected at least one argument")
        else:
            _fail("unrecognized arguments: " + word)
        i += 1
    var missing = List[String]()
    for name in required:
        if not parsed.has(name):
            missing.append(name)
    if len(missing) > 0:
        var text = String()
        for i in range(len(missing)):
            text += (", " if i > 0 else "") + missing[i]
        _fail("the following arguments are required: " + text)
    return parsed^


def _integer_argument(name: String, text: String) -> Int:
    """Return an integer option, or exit with a usage error."""
    try:
        return Int(canonical_integer(text))
    except:
        _fail("argument " + name + ": invalid int value: '" + text + "'")
        return 0


def _float_argument(name: String, text: String) -> Float64:
    """Return a float option, or exit with a usage error."""
    try:
        return parse_float(String(text.strip()))
    except:
        _fail("argument " + name + ": invalid float value: '" + text + "'")
        return 0


def main() raises:
    """Run one subcommand from the command line.

    Raises:
        Error: If the subcommand fails.
    """
    var given = List[String]()
    var arguments = argv()
    for i in range(1, len(arguments)):
        given.append(String(arguments[i]))
    if len(given) == 0:
        _fail("the following arguments are required: command")
    var command = given.pop(0)
    if command == "-h" or command == "--help":
        print(_usage())
        exit(0)
    if command == "stride":
        var parsed = _parse(
            given,
            ["--source", "--destination"],
            [],
            [],
            ["--source", "--destination"],
        )
        prepare_stride(
            parsed.last("--source", ""), parsed.last("--destination", "")
        )
    elif command == "build":
        var parsed = _parse(
            given,
            ["--mojo", "--cc", "--destination", "--timeout"],
            ["--source", "--revision", "--flag"],
            [],
            ["--mojo", "--source", "--destination"],
        )
        build(
            parsed.last("--mojo", ""),
            parsed.last("--cc", "/usr/bin/cc"),
            parsed.all("--source"),
            parsed.all("--revision"),
            parsed.last("--destination", ""),
            parsed.all("--flag"),
            _float_argument("--timeout", parsed.last("--timeout", "1800")),
        )
    elif command == "build-rusage":
        var parsed = _parse(
            given, ["--build", "--cc", "--timeout"], [], [], ["--build"]
        )
        build_rusage(
            parsed.last("--build", ""),
            parsed.last("--cc", "/usr/bin/cc"),
            _float_argument("--timeout", parsed.last("--timeout", "120")),
        )
    elif command == "run":
        var parsed = _parse(
            given,
            [
                "--build",
                "--fixtures",
                "--destination",
                "--baseline",
                "--repetitions",
                "--seed",
                "--timeout",
            ],
            [],
            ["--workers", "--datasets", "--apis"],
            ["--build", "--fixtures", "--destination"],
        )
        var options = RunOptions(
            parsed.last("--build", ""),
            parsed.last("--fixtures", ""),
            parsed.last("--destination", ""),
        )
        options.baseline = parsed.last("--baseline", "baseline")
        options.repetitions = _integer_argument(
            "--repetitions", parsed.last("--repetitions", "3")
        )
        for text in parsed.all("--workers"):
            options.workers.append(_integer_argument("--workers", text))
        options.datasets = parsed.all("--datasets")
        if parsed.has("--apis"):
            options.apis = parsed.all("--apis")
            for api in options.apis:
                if api != "gltf" and api != "registry":
                    _fail(
                        "argument --apis: invalid choice: '"
                        + api
                        + "' (choose from gltf, registry)"
                    )
        options.seed = _integer_argument("--seed", parsed.last("--seed", "505"))
        options.timeout = _float_argument(
            "--timeout", parsed.last("--timeout", "120")
        )
        var measurer = NativeMeasurer()
        run(options, measurer)
    else:
        _fail(
            "argument command: invalid choice: '"
            + command
            + "' (choose from stride, build, build-rusage, run)"
        )
