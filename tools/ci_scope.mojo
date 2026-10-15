# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Plan CI by directed source impact, and run the Makefile with exact lists.

    ci_scope plan [--base REF | --full]
    ci_scope run -- TARGET [ARGUMENT...]
    ci_scope aggregate
    ci_scope check-workflow

`plan` writes `.cache/ci-selection.json`. Execution follows changed inputs
toward their consumers, never back through an unchanged dependency to
unrelated consumers. Coverage has its own inventory: it measures the changed
production modules and their production consumers, and it captures every
current suite that can reach them. An edited test runs without measuring
every unchanged import again. A deleted test and a removed import keep their
former obligations. An assertion-only test deletion can lower the coverage of
an unchanged library without a scoped check seeing it; the explicit full
audit owns that guarantee. An unknown input or an unknown history selects
the full audit. An invalid plan fails; it never passes.

`run` checks the plan against `CI_SELECTION_SHA256` and runs
`make -B TARGET...` with the plan's lists. `aggregate` checks the results in
`CI_NEEDS`: each selected job passed, and each other job was skipped.
`check-workflow` checks that the workflow guards each job with its flag;
`make repository-check` runs it.

The tool works on the repository in the current directory.
"""

from std.collections import Set
from std.ffi import c_int, external_call
from std.os import getenv, makedirs, remove
from std.pathlib import Path
from std.sys import argv, exit, stderr

from loaders.json import (
    ARRAY,
    BOOLEAN,
    NUMBER,
    OBJECT,
    STRING,
    JsonDocument,
    parse_json,
)
from tools._imports import (
    Resolver,
    add_edge,
    entry_directories,
    git,
    imported_names,
    is_documentation,
    mojo_files,
    quoted_assets,
    read_source,
    reachable,
    sorted_set,
    split_nul,
)
from tools._json_tools import JsonWriter, quote_ascii
from tools._process import run_program, shell_quote
from tools._sha256 import sha256_hex
from tools._text import split_lines

comptime LIB_DIRS = [
    "math",
    "render",
    "units",
    "cameras",
    "core",
    "geometries",
    "helpers",
    "objects",
    "renderers",
    "materials",
    "lights",
    "loaders",
    "animation",
    "postprocessing",
    "controls",
    "window",
    "exporters",
    "environments",
    "generators",
    "extensions",
]
"""The top-level directories of the library."""

comptime GPU = [
    "render/gpu.mojo",
    "render/gpu_vxgi.mojo",
    "extensions/water/gpu.mojo",
    "tests/test_gpu.mojo",
    "tests/test_gpu_water.mojo",
    "tests/test_gpu_layout.mojo",
    "tests/test_gpu_volume_packing.mojo",
    "bench/raster_bench.mojo",
    "bench/water_gpu_bench.mojo",
    "bench/hair_frame_bench.mojo",
    "tools/gpu_status.mojo",
]
"""The files that need MAX."""

comptime BUILD_TOOLS = [
    "tools/affected.mojo",
    "tools/cache_key.mojo",
    "tools/suite_key.mojo",
    "tools/shard.mojo",
    "tools/coverage_shard.mojo",
    "tools/example_inputs.mojo",
    "tools/run_suite.mojo",
]
"""The Mojo tools the Makefile runs to select, split, key and judge the checks. A
change to one, or to any file it imports, changes the selection itself."""

comptime GLOBAL_TOOLS = [
    "tools/cache_key.py",
    "tools/suite_key.py",
    "tools/run_suite.py",
    "tools/native_test_support.py",
    "tools/test_environment.py",
    "tools/fixture_runtime.mojo",
    "tools/compiler_telemetry.mojo",
]
"""Other tools whose change selects the full audit."""

comptime BOUND_EVIDENCE = [
    "docs/validation/anatomy-template-report.json",
    "docs/validation/anatomy-provenance.json",
]
"""Evidence that Mojo sources read and bind (#702). A change runs each
source that quotes the path, with its importers."""

comptime ROUTING = [".github/workflows/ci.yml"]
"""The CI workflow, which the tool checks test."""

comptime LISTS = [
    "formatted",
    "cpu_entries",
    "cpu_docs",
    "cpu_tests",
    "compile_fail",
    "covered",
    "coverage_tests",
]
"""The file lists of a plan, in order."""

comptime FLAGS = [
    "tools",
    "native",
    "cpu",
    "coverage",
    "gpu",
    "docs",
    "coverage_tools",
    "portability",
    "export",
]
"""The job flags of a plan, in order, before `lint`."""

comptime JOBS = [
    ("lint", "lint"),
    ("tools", "tools"),
    ("cpu", "cpu"),
    ("cpu-macos", "cpu"),
    ("lint-macos", "lint"),
    ("tools-macos", "tools"),
    ("coverage-capture", "coverage"),
    ("coverage", "coverage"),
    ("gpu-host", "gpu"),
]
"""Each CI job and the flag that selects it."""

comptime SELECTION = ".cache/ci-selection.json"
"""Where `plan` writes the plan."""


def _contains[size: Int](table: Array[String, size], item: String) -> Bool:
    """Return whether a table holds a string."""
    for entry in table:
        if entry == item:
            return True
    return False


def _first_part(path: String) -> String:
    """Return the first component of a path."""
    var slash = path.find("/")
    if slash < 0:
        return path
    return String(path[byte=:slash])


def is_gpu(path: String) -> Bool:
    """Return whether a file needs MAX.

    Args:
        path: A repository path.

    Returns:
        True for the files in `GPU`.
    """
    return _contains(materialize[GPU](), path)


def library(path: String) -> Bool:
    """Return whether a path is a library module.

    Args:
        path: A repository path.

    Returns:
        True for a `.mojo` file under a library directory.
    """
    return path.endswith(".mojo") and _contains(
        materialize[LIB_DIRS](), _first_part(path)
    )


def kind(path: String) -> String:
    """Return the checks a changed path needs.

    Args:
        path: A repository path.

    Returns:
        `all`, `tools`, `docs`, `coverage_tools`, `portability`, `export` or
        `native`. An input with no explicit rule needs `all`.
    """
    if (
        _contains(materialize[GLOBAL_TOOLS](), path)
        or _contains(materialize[BUILD_TOOLS](), path)
        or path == "Makefile"
    ):
        return "all"
    if path == "bench/results-linux.json":
        return "tools"
    # The anatomy report and its inventory are evidence, not documentation:
    # the Mojo suites that quote them check their binding (#702).
    if _contains(materialize[BOUND_EVIDENCE](), path):
        return "native"
    if is_documentation(path):
        return "docs"
    if _contains(materialize[ROUTING](), path) or (
        path.startswith("tools/test_") and path.endswith(".py")
    ):
        return "tools"
    # `make repository-check` checks the gallery table with
    # tools/example_inputs.mojo; CI does not render the gallery.
    if path == "examples/gallery.mk":
        return "tools"
    for prefix in [
        "coverage/",
        "tools/coverage_",
        "tools/check_coverage_",
        "tools/fixtures/coverage_",
        "tools/carla_lane_oracle/",
    ]:
        if path.startswith(prefix):
            return "coverage_tools"
    if path == "tools/check_portability.mojo":
        return "portability"
    if (
        path == "assets/carla/tools/carla_assets.py"
        or path == "assets/carla/tools/test_carla_assets.py"
    ):
        return "tools"
    if path.startswith("assets/carla/tools/export/"):
        return "export"
    if path.startswith("assets/"):
        return "native"
    var top = _first_part(path)
    if path.endswith(".mojo") and (
        _contains(materialize[LIB_DIRS](), top)
        or top == "tests"
        or top == "examples"
        or top == "bench"
        or top == "tools"
    ):
        return "native"
    return "all"


# --- the graph -----------------------------------------------------------------


struct Graph(Movable):
    """The imports between sources, in both directions."""

    var imports: Dict[String, Set[String]]
    """Each file and the files it imports."""
    var users: Dict[String, Set[String]]
    """Each file and the files that import it."""

    def __init__(out self, sources: Dict[String, String]):
        """Resolve every import of every source.

        Any entry point can compile a module, so the graph keeps every
        search root an entry point can use.

        Args:
            sources: Each path and its text.
        """
        var known = Set[String]()
        for entry in sources.items():
            known.add(entry.key)
        var lookup = Resolver(known^, entry_directories(sources))
        self.imports = Dict[String, Set[String]]()
        self.users = Dict[String, Set[String]]()
        for entry in sources.items():
            for name in imported_names(entry.value):
                for target in lookup.lookup(name):
                    if target != entry.key:
                        add_edge(self.imports, entry.key, target)
                        add_edge(self.users, target, entry.key)


def source_tree(root: String) raises -> Dict[String, String]:
    """Return every `.mojo` file and its text.

    Args:
        root: The repository root.

    Returns:
        Each relative path and its text.

    Raises:
        Error: If a source cannot be read or is not UTF-8.
    """
    var sources = Dict[String, String]()
    for path in mojo_files(root):
        sources[path] = read_source(root, path)
    return sources^


def _git(root: String, arguments: List[String]) raises -> String:
    """Return git's output, or raise when git fails."""
    var output = git(root, arguments)
    if not output:
        raise Error("git " + " ".join(arguments) + " failed")
    return output.value()


def _strip_end(text: String) -> String:
    """Return text without trailing white space."""
    var end = text.byte_length()
    var bytes = text.as_bytes()
    while end > 0 and (
        bytes[end - 1] == 10 or bytes[end - 1] == 13 or bytes[end - 1] == 32
    ):
        end -= 1
    return String(text[byte=:end])


def changed_paths(root: String, base: String) -> Optional[Dict[String, Bool]]:
    """Return the paths changed since `base`, or nothing.

    `base` must be an ancestor of `HEAD`: a normal pull request base and a
    push's previous `main` are. Unknown or force-diverged history, and a
    diff the tool cannot read, give nothing, which is the full audit.

    Args:
        root: The repository root.
        base: The ref to compare with.

    Returns:
        Each changed path and whether it was deleted. An untracked source or
        asset counts as changed.
    """
    try:
        var revision = _strip_end(
            _git(root, ["merge-base", "--", base, "HEAD"])
        )
        var resolved = _strip_end(
            _git(root, ["rev-parse", "--verify", base + "^{commit}"])
        )
        if revision != resolved:
            return None
        var raw = _git(
            root,
            ["diff", "--name-status", "--no-renames", "-z", revision, "--"],
        )
        var fields = raw.split("\0")
        if (
            String(fields[len(fields) - 1]).byte_length() > 0
            or (len(fields) - 1) % 2 == 1
        ):
            return None
        var paths = Dict[String, Bool]()
        var index = 0
        while index + 1 < len(fields):
            var status = String(fields[index])
            var path = String(fields[index + 1])
            if (
                not (
                    status == "A"
                    or status == "M"
                    or status == "D"
                    or status == "T"
                )
                or path.byte_length() == 0
                or path in paths
            ):
                return None
            paths[path] = status == "D"
            index += 2
        var untracked = _git(
            root, ["ls-files", "--others", "--exclude-standard", "-z"]
        )
        if untracked.byte_length() > 0 and not untracked.endswith("\0"):
            return None
        for path in split_nul(untracked):
            if (
                path.endswith(".mojo")
                or path.endswith(".py")
                or path.endswith(".c")
                or path.endswith(".h")
                or path.startswith("assets/")
            ):
                paths[path] = False
        return paths^
    except:
        return None


def _names(source: String) -> Set[String]:
    """Return the imported names of a source, as a set."""
    var names = Set[String]()
    for name in imported_names(source):
        names.add(name)
    return names^


def _removes_imports(before: String, after: String) -> Bool:
    """Return whether a source names an import that a newer text drops."""
    var now = _names(after)
    for name in imported_names(before):
        if not name in now:
            return True
    return False


def previous_tests(
    root: String,
    base: String,
    changed: Dict[String, Bool],
    current: Dict[String, String],
) raises -> Dict[String, String]:
    """Return the baseline sources when a changed test lost an import.

    The baseline graph keeps the edges that a removed import or a deleted
    test had. It resolves against the baseline's own file names, so a newly
    added sibling cannot take an old dependency's place.

    Args:
        root: The repository root.
        base: The ref to compare with.
        changed: Each changed path and whether it was deleted.
        current: The current sources.

    Returns:
        Every baseline `.mojo` file and its text, or nothing when no changed
        test or helper was deleted or lost an import.

    Raises:
        Error: If git cannot give the baseline, or a baseline entry is not a
            plain file.
    """
    var tests = List[String]()
    for entry in changed.items():
        if entry.key.startswith("tests/") and entry.key.endswith(".mojo"):
            tests.append(entry.key)
    var none = Dict[String, String]()
    if len(tests) == 0:
        return none^
    var revision = _strip_end(_git(root, ["merge-base", base, "HEAD"]))
    var known = Set[String]()
    for path in split_nul(
        _git(root, ["ls-tree", "-r", "--name-only", "-z", revision])
    ):
        known.add(path)
    var removed = False
    for path in tests:
        if not path in known:
            continue
        var before = _git(root, ["show", revision + ":" + path])
        if changed[path] or _removes_imports(
            before, current.get(path).or_else(String())
        ):
            removed = True
    if not removed:
        return none^
    var paths = List[String]()
    var identities = String()
    for record in split_nul(_git(root, ["ls-tree", "-r", "-z", revision])):
        var tab = record.find("\t")
        var path = String(record[byte = tab + 1 :])
        if not path.endswith(".mojo"):
            continue
        var metadata = String(record[byte=:tab]).split(" ")
        if (
            len(metadata) != 3
            or String(metadata[1]) != "blob"
            or not (
                String(metadata[0]) == "100644"
                or String(metadata[0]) == "100755"
            )
        ):
            raise Error("Unsupported baseline source entry")
        paths.append(path)
        identities += String(metadata[2]) + "\n"
    var request = (
        root
        + "/.cache/ci-scope-objects."
        + String(external_call["getpid", c_int]())
    )
    makedirs(root + "/.cache", exist_ok=True)
    Path(request).write_text(identities)
    var result = run_program(
        ["sh", "-c", 'exec git cat-file --batch < "$0"', request],
        600,
        merge_errors=False,
        directory=root,
    )
    remove(Path(request))
    if result.status != 0:
        raise Error("git cat-file failed")
    var bytes = result.output.as_bytes()
    var old = Dict[String, String]()
    var offset = 0
    var lines = identities.split("\n")
    for index in range(len(paths)):
        var end = offset
        while end < len(bytes) and bytes[end] != 10:
            end += 1
        if end >= len(bytes):
            raise Error("Truncated baseline source object")
        var header = String(result.output[byte=offset:end]).split(" ")
        if (
            len(header) != 3
            or String(header[0]) != String(lines[index])
            or String(header[1]) != "blob"
        ):
            raise Error("Baseline source object mismatch")
        var size = Int(String(header[2]))
        offset = end + 1
        if offset + size >= len(bytes) or bytes[offset + size] != 10:
            raise Error("Truncated baseline source object")
        old[paths[index]] = String(result.output[byte = offset : offset + size])
        offset += size + 1
    if offset != len(bytes):
        raise Error("Trailing baseline object data")
    return old^


def inventories(sources: Dict[String, String]) -> Dict[String, Set[String]]:
    """Return the Makefile's file lists for a source tree.

    Args:
        sources: Each path and its text.

    Returns:
        Each list of `LISTS` as a set, as the Makefile computes it.
    """
    var helpers = Set[String]()
    var libs = Set[String]()
    var tool_libs = Set[String]()
    var entries = Set[String]()
    var negative = Set[String]()
    var tests = Set[String]()
    for entry in sources.items():
        var name = entry.key
        if (
            name.startswith("tests/_")
            or (name.startswith("tools/_") and name.count("/") == 1)
            or name == "tests/carla_fixed_s_fixture.mojo"
            or name == "tests/exact_predicates_oracle.mojo"
        ):
            helpers.add(name)
        if library(name) and not name.endswith("/__init__.mojo"):
            libs.add(name)
        if (
            name.startswith("coverage/")
            and name != "coverage/build_cli.mojo"
            and name != "coverage/report_cli.mojo"
        ):
            tool_libs.add(name)
        if name.startswith("tests/compile_fail/"):
            negative.add(name)
        if (
            name.startswith("tests/test_")
            and name.endswith(".mojo")
            and name.count("/") == 1
        ):
            tests.add(name)
    for entry in sources.items():
        var name = entry.key
        var top = _first_part(name)
        if (
            (
                (
                    top == "tests"
                    or top == "examples"
                    or top == "bench"
                    or top == "tools"
                )
                and not name.startswith("tests/compile_fail/")
                and not name.startswith("bench/mojo10/")
                and not name in helpers
            )
            or name == "coverage/build_cli.mojo"
            or name == "coverage/report_cli.mojo"
        ):
            entries.add(name)
    var result = Dict[String, Set[String]]()
    var formatted = (
        libs.union(tool_libs).union(helpers).union(entries).union(negative)
    )
    result["formatted"] = formatted^
    var cpu_entries = Set[String]()
    for name in entries:
        if not is_gpu(name):
            cpu_entries.add(name)
    result["cpu_entries"] = cpu_entries^
    var cpu_docs = Set[String]()
    for name in libs.union(tool_libs).union(helpers):
        if not is_gpu(name):
            cpu_docs.add(name)
    result["cpu_docs"] = cpu_docs^
    var cpu_tests = Set[String]()
    for name in tests:
        if not is_gpu(name):
            cpu_tests.add(name)
    result["cpu_tests"] = cpu_tests.copy()
    result["compile_fail"] = negative^
    var covered = Set[String]()
    for name in libs:
        if not is_gpu(name):
            covered.add(name)
    result["covered"] = covered^
    result["coverage_tests"] = cpu_tests^
    return result^


# --- the plan ------------------------------------------------------------------


struct Plan(Copyable, Movable):
    """Which jobs run, and with which files."""

    var full: Bool
    """True for the full audit."""
    var reason: String
    """Why the plan is full or directed."""
    var flags: Dict[String, Bool]
    """Each flag of `FLAGS`, then `lint`, in order."""
    var files: Dict[String, List[String]]
    """Each list of `LISTS`, sorted, in order."""

    def __init__(out self):
        """Make an empty full plan, which `validate` refuses."""
        self.full = True
        self.reason = String()
        self.flags = Dict[String, Bool]()
        self.files = Dict[String, List[String]]()

    def flag(self, name: String) raises -> Bool:
        """Return one flag.

        Args:
            name: The flag.

        Returns:
            Its value.

        Raises:
            Error: If the plan has no such flag.
        """
        return self.flags[name]

    def json(self) -> String:
        """Return the plan as compact JSON, as `plan` stores it.

        Returns:
            The text, with the keys in a fixed order.
        """
        var text = String('{"schema":1,"full":')
        text += "true" if self.full else "false"
        text += ',"reason":' + quote_ascii(self.reason) + ',"flags":{'
        var first = True
        for entry in self.flags.items():
            if not first:
                text += ","
            first = False
            text += (
                quote_ascii(entry.key)
                + ":"
                + ("true" if entry.value else "false")
            )
        text += '},"files":{'
        first = True
        for entry in self.files.items():
            if not first:
                text += ","
            first = False
            text += quote_ascii(entry.key) + ":["
            for index in range(len(entry.value)):
                if index > 0:
                    text += ","
                text += quote_ascii(entry.value[index])
            text += "]"
        text += "}}"
        return text^


def _safe_path(path: String) -> Bool:
    """Return whether a path can enter a Makefile as it is."""
    if (
        path.byte_length() == 0
        or path.startswith("/")
        or not path.endswith(".mojo")
    ):
        return False
    for byte in path.as_bytes():
        if not (
            (byte >= 48 and byte <= 57)
            or (byte >= 65 and byte <= 90)
            or (byte >= 97 and byte <= 122)
            or byte == 95
            or byte == 46
            or byte == 47
            or byte == 45
        ):
            return False
    for part in path.split("/"):
        if String(part) == "..":
            return False
    return True


def validate(plan: Plan) raises:
    """Refuse a plan that could run the wrong checks.

    Args:
        plan: The plan.

    Raises:
        Error: If a flag or a list is missing or extra, a path is unsafe for
            the Makefile or repeats, or a directed plan's `cpu` or
            `coverage` flag disagrees with its files.
    """
    var flags = materialize[FLAGS]()
    if len(plan.flags) != len(flags) + 1 or not "lint" in plan.flags:
        raise Error("Invalid or missing CI plan")
    for name in flags:
        if not name in plan.flags:
            raise Error("Invalid or missing CI plan")
    var lists = materialize[LISTS]()
    if len(plan.files) != len(lists):
        raise Error("Invalid or missing CI plan")
    for name in lists:
        if not name in plan.files:
            raise Error("Invalid or missing CI plan")
    for entry in plan.files.items():
        var seen = Set[String]()
        for path in entry.value:
            if not _safe_path(path):
                raise Error("Unsafe native Makefile path in CI plan")
            seen.add(path)
        if len(seen) != len(entry.value):
            raise Error("Duplicate CI path")
    if not plan.full:
        if plan.flags["cpu"] != (
            len(plan.files["cpu_tests"]) > 0
        ) or plan.flags["coverage"] != (len(plan.files["covered"]) > 0):
            raise Error("CI applicability disagrees with its inventory")


def read_plan(text: String) raises -> Plan:
    """Read a stored plan, and validate it.

    Args:
        text: The JSON text.

    Returns:
        The plan.

    Raises:
        Error: If the text is not a valid plan.
    """
    var document = parse_json(text)
    var root = document.root()
    if document.kind(root) != OBJECT:
        raise Error("Invalid or missing CI plan")
    for key in ["schema", "full", "reason", "flags", "files"]:
        if not document.has(root, key):
            raise Error("Invalid or missing CI plan")
    var schema = document.get(root, "schema")
    var full = document.get(root, "full")
    var reason = document.get(root, "reason")
    var flags = document.get(root, "flags")
    var files = document.get(root, "files")
    if (
        document.kind(schema) != NUMBER
        or document.number(schema) != 1
        or document.kind(full) != BOOLEAN
        or document.kind(reason) != STRING
        or document.kind(flags) != OBJECT
        or document.kind(files) != OBJECT
    ):
        raise Error("Invalid or missing CI plan")
    var plan = Plan()
    plan.full = document.boolean(full)
    plan.reason = document.string(reason)
    for index in range(document.length(flags)):
        var value = document.at(flags, index)
        if document.kind(value) != BOOLEAN:
            raise Error("CI flags must be booleans")
        plan.flags[document.key(flags, index)] = document.boolean(value)
    for index in range(document.length(files)):
        var value = document.at(files, index)
        if document.kind(value) != ARRAY:
            raise Error("Unsafe native Makefile path in CI plan")
        var paths = List[String]()
        for position in range(document.length(value)):
            var path = document.at(value, position)
            if document.kind(path) != STRING:
                raise Error("Unsafe native Makefile path in CI plan")
            paths.append(document.string(path))
        plan.files[document.key(files, index)] = paths^
    validate(plan)
    return plan^


def _intersect(items: Set[String], keep: Set[String]) -> Set[String]:
    """Return the members of one set that another holds."""
    var found = Set[String]()
    for item in items:
        if item in keep:
            found.add(item)
    return found^


def plan(
    root: String,
    changed: Optional[Dict[String, Bool]],
    base: String,
    old: Optional[Dict[String, String]],
    sources: Dict[String, String],
) raises -> Plan:
    """Return the checks a change needs.

    Args:
        root: The repository root, for the baseline sources.
        changed: Each changed path and whether it was deleted, or nothing
            for the full audit.
        base: The ref to compare with.
        old: The baseline sources, or nothing to read them from git when a
            changed test lost an import.
        sources: The current sources.

    Returns:
        The validated plan.

    Raises:
        Error: If the plan is not valid.
    """
    var inventory = inventories(sources)
    var full = not changed
    var types = Set[String]()
    if changed:
        for entry in changed.value().items():
            var found = kind(entry.key)
            types.add(found)
            if found == "all":
                full = True
    var graph = Graph(sources)
    if not full:
        var tools = Set[String]()
        for tool in materialize[BUILD_TOOLS]():
            if tool in sources:
                tools.add(tool)
        var build = reachable(tools, graph.imports)
        for entry in changed.value().items():
            if entry.key in build:
                full = True
    var selected = Dict[String, Set[String]]()
    var execution = Set[String]()
    if full:
        for entry in inventory.items():
            selected[entry.key] = entry.value.copy()
    else:
        var change = changed.value().copy()
        var seeds = Set[String]()
        var assets = List[String]()
        var evidence = List[String]()
        var deleted = False
        for entry in change.items():
            if entry.key in sources:
                seeds.add(entry.key)
            if _contains(materialize[BOUND_EVIDENCE](), entry.key):
                evidence.append(entry.key)
            if entry.key.startswith("assets/") and kind(entry.key) == "native":
                assets.append(entry.key)
            if entry.key.endswith(".mojo"):
                seeds.add(entry.key)
                if entry.value:
                    deleted = True
        for entry in sources.items():
            for quoted in quoted_assets(entry.value):
                for asset in assets:
                    if asset.startswith(quoted):
                        seeds.add(entry.key)
            for path in evidence:
                if entry.value.find('"' + path + '"') >= 0:
                    seeds.add(entry.key)
        # Deleted modules remain reverse-graph targets during resolution.
        if deleted:
            var graph_sources = sources.copy()
            for entry in change.items():
                if entry.value and entry.key.endswith(".mojo"):
                    graph_sources[entry.key] = String()
            graph = Graph(graph_sources)
        execution = reachable(seeds, graph.users)
        var tests = Set[String]()
        var measured = Set[String]()
        for name in execution:
            if name.startswith("tests/"):
                tests.add(name)
            if library(name):
                measured.add(name)
        var baseline = Dict[String, String]()
        if old:
            baseline = old.value().copy()
        else:
            var changed_test = False
            for entry in change.items():
                if entry.key.startswith("tests/") and entry.key.endswith(
                    ".mojo"
                ):
                    changed_test = True
            if changed_test:
                try:
                    baseline = previous_tests(root, base, change, sources)
                except:
                    return plan(root, None, base, None, sources)
        if len(baseline) > 0:
            # The old graph keeps removed imports; the current graph keeps
            # additions.
            var old_graph = Graph(baseline)
            var removed = Set[String]()
            for entry in baseline.items():
                if entry.key in change and (
                    change[entry.key]
                    or _removes_imports(
                        entry.value, sources.get(entry.key).or_else(String())
                    )
                ):
                    removed.add(entry.key)
            var old_tests = reachable(removed, old_graph.users)
            for name in reachable(old_tests, old_graph.imports):
                if library(name):
                    measured.add(name)
        measured = _intersect(measured, inventory["covered"])
        var captures = reachable(measured, graph.users).union(tests)
        for entry in inventory.items():
            selected[entry.key] = _intersect(entry.value, execution)
        var keys = Set[String]()
        for entry in change.items():
            keys.add(entry.key)
        selected["formatted"] = _intersect(inventory["formatted"], keys)
        selected["covered"] = measured.copy()
        selected["coverage_tests"] = _intersect(
            inventory["coverage_tests"], captures
        )
    var result = Plan()
    result.full = full
    result.reason = (
        "full audit: unknown input/history or manual request" if full else "directed input selection"
    )
    for name in materialize[LISTS]():
        result.files[name] = sorted_set(selected[name])
    var other = types.copy()
    other.discard("docs")
    var gpu = False
    var portability = False
    for name in execution:
        # `make check-gpu-air` runs the AIR checker in the GPU job.
        if is_gpu(name) or name == "tools/check_air_calls.mojo":
            gpu = True
        if (
            name == "tests/portability_probe.mojo"
            or name == "tests/test_scratch.mojo"
            or name == "tools/check_portability.mojo"
        ):
            portability = True
    var tasks = False
    if changed:
        tasks = "render/tasks.mojo" in changed.value()
    result.flags["tools"] = full or len(other) > 0
    result.flags["native"] = full or (
        len(result.files["formatted"]) > 0
        or len(result.files["cpu_entries"]) > 0
        or len(result.files["cpu_docs"]) > 0
        or len(result.files["compile_fail"]) > 0
    )
    result.flags["cpu"] = full or len(result.files["cpu_tests"]) > 0
    result.flags["coverage"] = full or len(result.files["covered"]) > 0
    result.flags["gpu"] = full or gpu
    result.flags["docs"] = full or "docs" in types
    result.flags["coverage_tools"] = full or "coverage_tools" in types or tasks
    result.flags["portability"] = full or "portability" in types or portability
    result.flags["export"] = full or "export" in types
    var lint = False
    for name in [
        "tools",
        "native",
        "docs",
        "coverage_tools",
        "portability",
        "export",
    ]:
        if result.flags[name]:
            lint = True
    result.flags["lint"] = lint
    validate(result)
    return result^


# --- running and checking the jobs -------------------------------------------


def selection_makefile(plan: Plan, arguments: List[String]) raises -> String:
    """Return the Makefile text that sets the plan's lists.

    Args:
        plan: The plan.
        arguments: The make targets and arguments. A coverage target gets
            the coverage suites as its tests.

    Returns:
        One `override NAME := ...` line for each list.

    Raises:
        Error: If the plan is not valid.
    """
    validate(plan)
    var coverage = False
    for argument in arguments:
        if argument == "coverage" or argument.startswith("coverage-"):
            coverage = True
    var mapping = [
        ("FORMATTED", "formatted"),
        ("CPU_ENTRY_POINTS", "cpu_entries"),
        ("CPU_DOC_SOURCES", "cpu_docs"),
        ("CPU_TESTS", "coverage_tests" if coverage else "cpu_tests"),
        ("COMPILE_FAIL_RUN", "compile_fail"),
        ("COVERED", "covered"),
    ]
    var text = String()
    for entry in mapping:
        text += (
            "override "
            + entry[0]
            + " := "
            + " ".join(plan.files[entry[1]])
            + "\n"
        )
    return text^


def make_command(
    plan: Plan, arguments: List[String], selection_file: String
) raises -> List[String]:
    """Return the make command for the plan.

    `MAKEFILES` is read before the Makefile, and recursive make inherits
    it. The lists stay in a file, because long assignments on the command
    line overflow the exported `MAKEFLAGS`. The full audit uses the
    Makefile's own lists.

    Args:
        plan: The plan.
        arguments: The make targets and arguments.
        selection_file: The file `selection_makefile` wrote.

    Returns:
        The command.

    Raises:
        Error: If the plan is not valid.
    """
    validate(plan)
    var scoped = False
    for argument in arguments:
        if (
            argument == "fmt-check"
            or argument == "lint-cpu"
            or argument == "compile-fail"
            or argument == "test-cpu"
            or argument == "coverage"
            or argument.startswith("coverage-")
        ):
            scoped = True
    var command: List[String] = ["make", "-B"]
    command.extend(arguments.copy())
    command.append("AFFECTED=")
    command.append(
        "MAKEFILES="
        + (selection_file if scoped and not plan.full else String())
    )
    return command^


def aggregate(plan: Plan, needs: String) raises:
    """Check the CI job results against the plan.

    Args:
        plan: The plan.
        needs: The `needs` context of the final job, as JSON.

    Raises:
        Error: If the plan is not valid, a job is missing or extra, the
            scope job failed, or a job's result is not `success` when its
            flag is set and `skipped` when it is not.
    """
    validate(plan)
    var document = parse_json(needs)
    var root = document.root()
    var jobs = materialize[JOBS]()
    if document.kind(root) != OBJECT or document.length(root) != len(jobs) + 1:
        raise Error("CI selection failed or a required job result is missing")
    var names = Set[String]()
    for index in range(document.length(root)):
        names.add(document.key(root, index))
    if len(names) != len(jobs) + 1 or not "scope" in names:
        raise Error("CI selection failed or a required job result is missing")
    for job in jobs:
        if not job[0] in names:
            raise Error(
                "CI selection failed or a required job result is missing"
            )
    if _result(document, "scope") != "success":
        raise Error("CI selection failed or a required job result is missing")
    for job in jobs:
        var wanted = "success" if plan.flags[job[1]] else "skipped"
        var got = _result(document, job[0])
        if got != wanted:
            raise Error(job[0] + ": expected " + wanted + ", got " + got)


def _result(document: JsonDocument, job: String) raises -> String:
    """Return a job's result, or `None` when it has none."""
    var node = document.get(document.root(), job)
    if document.kind(node) != OBJECT or not document.has(node, "result"):
        return "None"
    var result = document.get(node, "result")
    if document.kind(result) != STRING:
        return "None"
    return document.string(result)


def summary(plan: Plan) -> String:
    """Return the plan's summary, as `plan` prints it.

    Args:
        plan: The plan.

    Returns:
        JSON with two-space indentation: `full`, the flags, and the size of
        each list.
    """
    var writer = JsonWriter()
    writer.begin_object()
    writer.key("full")
    writer.boolean(plan.full)
    writer.key("flags")
    writer.begin_object()
    for entry in plan.flags.items():
        writer.key(entry.key)
        writer.boolean(entry.value)
    writer.end()
    writer.key("counts")
    writer.begin_object()
    for entry in plan.files.items():
        writer.key(entry.key)
        writer.integer(len(entry.value))
    writer.end()
    writer.end()
    return writer.text()


def stored_plan(root: String) raises -> Plan:
    """Read `.cache/ci-selection.json`, checked against its expected hash.

    Args:
        root: The repository root.

    Returns:
        The plan.

    Raises:
        Error: If the file is missing, `CI_SELECTION_SHA256` does not match
            it, or the plan is not valid.
    """
    var raw = Path(root + "/" + SELECTION).read_bytes()
    if sha256_hex(Span(raw)) != getenv("CI_SELECTION_SHA256"):
        raise Error("CI selection artifact does not match the planner output")
    return read_plan(String(from_utf8=Span(raw)))


def run_make(root: String, plan: Plan, var command: List[String]) raises -> Int:
    """Run make for the plan, with no make settings from outside.

    Args:
        root: The repository root.
        plan: The plan.
        command: The make targets and arguments.

    Returns:
        Make's exit status.

    Raises:
        Error: If no target is given or the selection file cannot be written.
    """
    if len(command) > 0 and command[0] == "--":
        _ = command.pop(0)
    if len(command) == 0:
        raise Error("No Make target provided")
    makedirs(root + "/.cache", exist_ok=True)
    # Make runs in the root, and splits MAKEFILES at spaces, so the file is
    # named relative to the root.
    var selection = (
        ".cache/ci-selection-"
        + String(external_call["getpid", c_int]())
        + ".mk"
    )
    Path(root + "/" + selection).write_text(selection_makefile(plan, command))
    var shell = String("cd -- ") + shell_quote(root) + " && exec env"
    for name in [
        "AFFECTED",
        "MAKEFLAGS",
        "MFLAGS",
        "MAKELEVEL",
        "MAKEFILES",
        "MAKEOVERRIDES",
        "GNUMAKEFLAGS",
    ]:
        shell += " -u " + name
    for word in make_command(plan, command, selection):
        shell += " " + shell_quote(word)
    var status: c_int
    try:
        # The output streams to this process's own output, as make writes it.
        var copy = shell
        status = external_call["system", c_int](copy.as_c_string_span().ptr())
    finally:
        remove(Path(root + "/" + selection))
    if status == -1:
        raise Error("cannot start make")
    var code = Int(status)
    if code & 0x7F != 0:
        return 128 + (code & 0x7F)
    return (code >> 8) & 0xFF


def write_plan(root: String, value: Plan) raises:
    """Store the plan, print its summary, and report it to GitHub Actions.

    Args:
        root: The repository root.
        value: The plan.

    Raises:
        Error: If a file cannot be written.
    """
    var encoded = value.json()
    makedirs(root + "/.cache", exist_ok=True)
    Path(root + "/" + SELECTION).write_text(encoded)
    print(summary(value))
    var output = getenv("GITHUB_OUTPUT")
    if output:
        var lines = String("selection=") + sha256_hex(encoded.as_bytes()) + "\n"
        for entry in value.flags.items():
            lines += (
                entry.key + "=" + ("true" if entry.value else "false") + "\n"
            )
        var existing = (
            Path(output).read_text() if Path(output).exists() else String()
        )
        Path(output).write_text(existing + lines)


def workflow_jobs(text: String) -> Dict[String, String]:
    """Return each top-level job of a workflow, and its text.

    A job starts at a line of two spaces, a name and a colon, after the
    `jobs:` line. Nested keys are not parsed.

    Args:
        text: The workflow.

    Returns:
        Each job name and the lines after its header, in order.
    """
    var jobs = Dict[String, String]()
    var name = String()
    var body = String()
    var inside = False
    for raw in split_lines(text):
        var line = _strip_end(raw)
        if not inside:
            inside = line == "jobs:"
            continue
        var bytes = line.as_bytes()
        var header = (
            line.startswith("  ")
            and not line.startswith("   ")
            and line.endswith(":")
            and line.byte_length() > 3
        )
        if header:
            for index in range(2, len(bytes) - 1):
                var byte = bytes[index]
                if not (
                    (byte >= 48 and byte <= 57)
                    or (byte >= 65 and byte <= 90)
                    or (byte >= 97 and byte <= 122)
                    or byte == 95
                    or byte == 45
                ):
                    header = False
        if header:
            if name:
                jobs[name] = body
            name = String(line[byte = 2 : line.byte_length() - 1])
            body = String()
        elif name:
            body += raw + "\n"
    if name:
        jobs[name] = body
    return jobs^


def workflow_errors(text: String) -> List[String]:
    """Check that the workflow runs each job only when the plan selects it.

    Args:
        text: The text of `.github/workflows/ci.yml`.

    Returns:
        A line for each problem: a job of `JOBS` that is missing, has another
        guard, or does not wait for the plan; or a job that `JOBS` does not
        name, other than `scope`, `required` and `wiki`.
    """
    var errors = List[String]()
    var jobs = workflow_jobs(text)
    var names = Set[String]()
    for job in materialize[JOBS]():
        names.add(job[0])
        if not job[0] in jobs:
            errors.append(job[0] + ": no such job")
            continue
        var body = jobs.get(job[0]).or_else(String())
        var guard = String()
        var needs = String()
        for line in split_lines(body):
            if line.startswith("    if: ") and not guard:
                guard = String(line[byte=8:])
            if line.startswith("    needs: ") and not needs:
                needs = String(line[byte=11:])
        if guard != "needs.scope.outputs.run_" + job[1] + " == 'true'":
            errors.append(job[0] + ": guard is not run_" + job[1])
        if needs != "scope" and needs != "[scope, coverage-capture]":
            errors.append(job[0] + ": does not need scope")
    for entry in jobs.items():
        if not entry.key in names and not (
            entry.key == "scope"
            or entry.key == "required"
            or entry.key == "wiki"
        ):
            errors.append(entry.key + ": not in the planner's JOBS")
    return errors^


def main_with(root: String, arguments: List[String]) raises -> Int:
    """Run one action.

    Args:
        root: The repository root.
        arguments: The arguments after the program name.

    Returns:
        The exit status.

    Raises:
        Error: For a bad command line, an invalid plan or a failed check.
    """
    if len(arguments) == 0:
        raise Error("expected plan, run or aggregate")
    var action = arguments[0]
    if action == "plan":
        var base = String()
        var full = False
        var index = 1
        while index < len(arguments):
            if arguments[index] == "--full":
                full = True
            elif arguments[index] == "--base" and index + 1 < len(arguments):
                index += 1
                base = arguments[index]
            elif arguments[index].startswith("--base="):
                base = String(arguments[index][byte=7:])
            else:
                raise Error("unknown argument: " + arguments[index])
            index += 1
        var changes: Optional[Dict[String, Bool]] = None
        if not full and base:
            changes = changed_paths(root, base)
        write_plan(root, plan(root, changes^, base, None, source_tree(root)))
        return 0
    if action == "aggregate":
        aggregate(stored_plan(root), getenv("CI_NEEDS"))
        print("Every selected check passed; inapplicable checks were skipped.")
        return 0
    if action == "check-workflow":
        var errors = workflow_errors(
            Path(root + "/.github/workflows/ci.yml").read_text()
        )
        for error in errors:
            print("ci_scope: .github/workflows/ci.yml: " + error, file=stderr)
        return 1 if len(errors) > 0 else 0
    if action == "run":
        var command = List[String]()
        for index in range(1, len(arguments)):
            command.append(arguments[index])
        return run_make(root, stored_plan(root), command^)
    raise Error("expected plan, run or aggregate, not " + action)


def main() raises:
    var arguments = List[String]()
    var given = argv()
    for index in range(1, len(given)):
        arguments.append(String(given[index]))
    try:
        exit(main_with(".", arguments))
    except error:
        print("CI scope error: " + String(error), file=stderr)
        exit(1)
