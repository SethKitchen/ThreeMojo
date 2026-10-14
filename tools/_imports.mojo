# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""The Mojo import graph that the build tools share.

`tools/affected.mojo`, `tools/suite_key.mojo` and `tools/shard.mojo` read
it. It finds the files a source imports as Mojo 1.1 finds them:

- A module beside the compiled entry point comes first, then the
  repository root (`-I .`). An imported module does not search its own
  directory.
- A name reaches the package initializer and the module at every prefix,
  under each search root. So a change to a hidden or an ambiguous module
  still selects its users.
- A source can also read the files under `assets/` whose path starts with
  a path it quotes, as `"assets/draco/"` does.

Every path is relative to the repository root and uses `/`.
"""

from std.collections import Set
from std.os import listdir
from std.os.path import isdir, islink
from std.pathlib import Path

from tools._process import run_program
from tools._text import split_lines

comptime SKIP_DIRS = [
    ".git",
    ".venv",
    ".cache",
    "out",
    "coverage/build",
    "node_modules",
]
"""Trees that hold no source the tools need, or copies of it."""


# --- text --------------------------------------------------------------------


def _is_space(byte: UInt8) -> Bool:
    """Return whether a byte is white space, as regular expressions see it."""
    return (
        byte == 32 or (byte >= 9 and byte <= 13) or (byte >= 28 and byte <= 31)
    )


def _is_word(byte: UInt8) -> Bool:
    """Return whether a byte can be part of a name.

    Any byte of a multibyte character counts, as Python's `\\w` takes the
    letters of every script.
    """
    return (
        (byte >= 48 and byte <= 57)
        or (byte >= 65 and byte <= 90)
        or (byte >= 97 and byte <= 122)
        or byte == 95
        or byte >= 128
    )


def _slice(text: String, start: Int, end: Int) -> String:
    """Return the bytes of `text` from `start` to `end`."""
    return String(text[byte=start:end])


def _strip(text: String) -> String:
    """Return `text` without white space at either end."""
    var bytes = text.as_bytes()
    var start = 0
    var end = len(bytes)
    while start < end and _is_space(bytes[start]):
        start += 1
    while end > start and _is_space(bytes[end - 1]):
        end -= 1
    return _slice(text, start, end)


def _skip_spaces(bytes: Span[UInt8, _], start: Int) -> Int:
    """Return the first position at or after `start` that is not a space."""
    var index = start
    while index < len(bytes) and _is_space(bytes[index]):
        index += 1
    return index


def _starts_with(bytes: Span[UInt8, _], start: Int, word: String) -> Bool:
    """Return whether `word` occurs in `bytes` at `start`."""
    var letters = word.as_bytes()
    if start + len(letters) > len(bytes):
        return False
    for index in range(len(letters)):
        if bytes[start + index] != letters[index]:
            return False
    return True


def _before_alias(item: String) -> String:
    """Return a stripped import item without its `as` alias.

    The alias starts at the first run of white space that `as` and more
    white space follow.
    """
    var text = _strip(item)
    var bytes = text.as_bytes()
    var index = 0
    while index < len(bytes):
        if _is_space(bytes[index]):
            var after = _skip_spaces(bytes, index)
            if (
                _starts_with(bytes, after, "as")
                and after + 2 < len(bytes)
                and _is_space(bytes[after + 2])
            ):
                return _strip(_slice(text, 0, index))
            index = after
        else:
            index += 1
    return text


def _code(line: String) -> String:
    """Return a line without its comment."""
    var hash = line.find("#")
    if hash < 0:
        return line
    return _slice(line, 0, hash)


def _from_import(line: String, mut module: String, mut rest: String) -> Bool:
    """Match `from MODULE import REST` at the start of a line.

    Args:
        line: One line without its comment.
        module: Set to the dotted module name.
        rest: Set to the text after `import` and its white space.

    Returns:
        True when the line is a `from` import.
    """
    var bytes = line.as_bytes()
    var index = _skip_spaces(bytes, 0)
    if not _starts_with(bytes, index, "from"):
        return False
    index += 4
    var after = _skip_spaces(bytes, index)
    if after == index or after >= len(bytes):
        return False
    var first = bytes[after]
    if not (_is_word(first) and not (first >= 48 and first <= 57)):
        return False
    var end = after + 1
    while end < len(bytes) and (_is_word(bytes[end]) or bytes[end] == 46):
        end += 1
    var gap = _skip_spaces(bytes, end)
    if gap == end or not _starts_with(bytes, gap, "import"):
        return False
    var start = _skip_spaces(bytes, gap + 6)
    if start == gap + 6:
        return False
    module = _slice(line, after, end)
    rest = _slice(line, start, len(bytes))
    return True


def _plain_import(line: String, mut rest: String) -> Bool:
    """Match `import REST` at the start of a line.

    Args:
        line: One line without its comment.
        rest: Set to the text after `import` and its white space.

    Returns:
        True when the line is a plain import.
    """
    var bytes = line.as_bytes()
    var index = _skip_spaces(bytes, 0)
    if not _starts_with(bytes, index, "import"):
        return False
    var start = _skip_spaces(bytes, index + 6)
    if start == index + 6:
        return False
    rest = _slice(line, start, len(bytes))
    return True


def imported_names(source: String) -> List[String]:
    """Return the dotted names a source imports.

    A `from` line gives its module and, for each name after `import`, the
    module and that name joined with a dot, because the name can be a
    submodule. A parenthesized list can run over several lines.

    Args:
        source: The text of a Mojo file.

    Returns:
        The names, in the order the source gives them.
    """
    var lines = List[String]()
    for line in split_lines(source):
        lines.append(_code(String(line)))
    var names = List[String]()
    var index = 0
    while index < len(lines):
        var module = String()
        var rest = String()
        if _from_import(lines[index], module, rest):
            if rest.find("(") >= 0:
                while rest.find(")") < 0 and index + 1 < len(lines):
                    index += 1
                    rest += " " + lines[index]
            rest = _code(rest).replace("(", " ").replace(")", " ")
            names.append(module)
            for item in rest.split(","):
                var name = _before_alias(String(item))
                if name.byte_length() > 0:
                    names.append(module + "." + name)
        elif _plain_import(lines[index], rest):
            for item in rest.split(","):
                var name = _before_alias(String(item))
                if name.byte_length() > 0:
                    names.append(name)
        index += 1
    return names^


def quoted_assets(source: String) -> List[String]:
    """Return each quoted path that starts with `assets/`.

    Args:
        source: The text of a source file.

    Returns:
        The paths without their quotes, in order. The quotes can enclose
        any character but a quote, a line end too.
    """
    var bytes = source.as_bytes()
    var found = List[String]()
    var index = 0
    while index < len(bytes):
        if bytes[index] == 34 and _starts_with(bytes, index + 1, "assets/"):
            var end = index + 8
            while end < len(bytes) and bytes[end] != 34:
                end += 1
            if end < len(bytes):
                found.append(_slice(source, index + 1, end))
                index = end + 1
                continue
        index += 1
    return found^


def defines_main(source: String) -> Bool:
    """Return whether a source defines `main` at the top level.

    Args:
        source: The text of a Mojo file.

    Returns:
        True when a line starts with `def` or `fn`, white space, `main`,
        optional white space and `(`.
    """
    var bytes = source.as_bytes()
    var start = 0
    while start < len(bytes):
        var index = -1
        if _starts_with(bytes, start, "def"):
            index = start + 3
        elif _starts_with(bytes, start, "fn"):
            index = start + 2
        if index >= 0:
            var after = _skip_spaces(bytes, index)
            if after > index and _starts_with(bytes, after, "main"):
                var paren = _skip_spaces(bytes, after + 4)
                if paren < len(bytes) and bytes[paren] == 40:
                    return True
        var newline = source.find("\n", start)
        if newline < 0:
            break
        start = newline + 1
    return False


def dirname(path: String) -> String:
    """Return the directory part of a relative path.

    Args:
        path: A path that uses `/`.

    Returns:
        Everything before the last `/`, or an empty string.
    """
    var slash = path.rfind("/")
    if slash < 0:
        return String()
    return _slice(path, 0, slash)


def is_documentation(path: String) -> Bool:
    """Return whether a path is documentation, which no build reads.

    Args:
        path: A repository path.

    Returns:
        True for Markdown, `docs/`, `out/`, `.vscode/` and three named
        files.
    """
    return (
        path.endswith(".md")
        or path.startswith("docs/")
        or path.startswith("out/")
        or path.startswith(".vscode/")
        or path == "LICENSE"
        or path == "skills-lock.json"
        or path == ".gitignore"
    )


# --- files -------------------------------------------------------------------


def _skipped(relative: String) -> Bool:
    """Return whether the walk leaves out a directory."""
    for name in materialize[SKIP_DIRS]():
        if relative == name:
            return True
    return False


def walk_files(root: String, top: String, skip: Bool) -> List[String]:
    """Return every file below a directory, as a relative path.

    The walk does not enter a symbolic link to a directory. A directory it
    cannot read gives no files.

    Args:
        root: The repository root.
        top: The directory to walk, relative to `root`, or empty.
        skip: True to leave out `SKIP_DIRS`.

    Returns:
        The paths, relative to `root`, in no set order.
    """
    var found = List[String]()
    var pending: List[String] = [top]
    while len(pending) > 0:
        var relative = pending.pop()
        var directory = root + "/" + relative if relative else root
        var names: List[String]
        try:
            names = listdir(directory)
        except:
            continue
        for name in names:
            var path = relative + "/" + name if relative else name
            var full = directory + "/" + name
            if isdir(full):
                if not islink(full) and not (skip and _skipped(path)):
                    pending.append(path)
            else:
                found.append(path)
    return found^


def mojo_files(root: String) -> List[String]:
    """Return every `.mojo` file in the repository.

    Args:
        root: The repository root.

    Returns:
        The relative paths, in no set order.
    """
    var found = List[String]()
    for path in walk_files(root, "", True):
        if path.endswith(".mojo"):
            found.append(path)
    return found^


def read_source(root: String, path: String) raises -> String:
    """Return a file's text.

    Args:
        root: The repository root.
        path: The file, relative to `root`.

    Returns:
        The text.

    Raises:
        Error: If the file cannot be read or is not UTF-8.
    """
    var bytes = Path(root + "/" + path).read_bytes()
    return String(from_utf8=Span(bytes))


def sorted_strings(var items: List[String]) -> List[String]:
    """Return strings in byte order.

    Args:
        items: The strings.

    Returns:
        The same strings, sorted.
    """
    sort(items)
    return items^


def sorted_set(items: Set[String]) -> List[String]:
    """Return the members of a set in byte order.

    Args:
        items: The set.

    Returns:
        Its members, sorted.
    """
    var list = List[String]()
    for item in items:
        list.append(item)
    return sorted_strings(list^)


def entry_directories(sources: Dict[String, String]) -> List[String]:
    """Return the sorted directories that hold a file defining `main`.

    Mojo searches the directory of the file it compiles before `-I .`.

    Args:
        sources: Each relative path and its text.

    Returns:
        The directories, each once.
    """
    var found = Set[String]()
    for entry in sources.items():
        if defines_main(entry.value):
            found.add(dirname(entry.key))
    return sorted_set(found)


# --- resolution --------------------------------------------------------------


def resolve(
    name: String, known: Set[String], entries: List[String]
) -> List[String]:
    """Return the files a dotted name reaches.

    Each search root gives the package initializer and the module at every
    prefix of the name. The roots are the entry directories, then the
    repository root. Keeping every root's files means a selection can only
    grow when one root hides or shadows another.

    Args:
        name: A dotted module name.
        known: Every `.mojo` path.
        entries: The directories the entry point can be in.

    Returns:
        The files, each once, in search order.
    """
    var parts = name.split(".")
    var found = List[String]()
    var bases = entries.copy()
    bases.append(String())
    for base in bases:
        var prefix = base + "/" if base else String()
        var joined = String()
        for count in range(len(parts)):
            if count > 0:
                joined += "/"
            joined += String(parts[count])
            for candidate in [
                prefix + joined + "/__init__.mojo",
                prefix + joined + ".mojo",
            ]:
                if candidate in known and not candidate in found:
                    found.append(candidate)
    return found^


struct Resolver(Movable):
    """`resolve` for one file set and one list of entry directories, which
    remembers each answer."""

    var known: Set[String]
    """Every `.mojo` path."""
    var entries: List[String]
    """The entry directories."""
    var answers: Dict[String, List[String]]
    """The answer for each name asked before."""

    def __init__(out self, var known: Set[String], var entries: List[String]):
        """Start with no answers.

        Args:
            known: Every `.mojo` path.
            entries: The entry directories.
        """
        self.known = known^
        self.entries = entries^
        self.answers = Dict[String, List[String]]()

    def lookup(mut self, name: String) -> List[String]:
        """Return the files a name reaches.

        Args:
            name: A dotted module name.

        Returns:
            What `resolve` returns for the name.
        """
        var answer = self.answers.get(name)
        if answer:
            return answer.value().copy()
        var found = resolve(name, self.known, self.entries)
        self.answers[name] = found.copy()
        return found^


def add_edge(
    mut edges: Dict[String, Set[String]], source: String, target: String
):
    """Record one edge of a graph.

    Args:
        edges: Each node and the nodes it leads to.
        source: The node the edge leaves.
        target: The node the edge reaches.
    """
    if source in edges:
        try:
            edges[source].add(target)
        except:
            pass
    else:
        var targets = Set[String]()
        targets.add(target)
        edges[source] = targets^


def reachable(
    seeds: Set[String], edges: Dict[String, Set[String]]
) -> Set[String]:
    """Return the transitive closure of `seeds` through `edges`.

    Args:
        seeds: Where the walk starts.
        edges: Each node and the nodes it leads to.

    Returns:
        The seeds and every node they reach.
    """
    var found = Set[String]()
    var pending = List[String]()
    for seed in seeds:
        pending.append(seed)
    while len(pending) > 0:
        var path = pending.pop()
        if path in found:
            continue
        found.add(path)
        var next = edges.get(path)
        if next:
            for target in next.value():
                pending.append(target)
    return found^


struct SourceCache(Movable):
    """What `closure` remembers between suites: each file's imported
    names, quoted assets and size, and its imports from each entry
    directory."""

    var names: Dict[String, List[String]]
    """The imported names of each file read."""
    var assets: Dict[String, List[String]]
    """The quoted asset paths of each file read."""
    var resolved: Dict[String, List[String]]
    """The files each file imports, keyed by entry directory and path."""
    var sizes: Dict[String, Int]
    """The size in bytes of each file read."""

    def __init__(out self):
        """Start empty."""
        self.names = Dict[String, List[String]]()
        self.assets = Dict[String, List[String]]()
        self.resolved = Dict[String, List[String]]()
        self.sizes = Dict[String, Int]()

    def read(mut self, root: String, path: String) raises:
        """Read a file once.

        Args:
            root: The repository root.
            path: The file.

        Raises:
            Error: If the file cannot be read or is not UTF-8.
        """
        if path in self.names:
            return
        var text = read_source(root, path)
        self.names[path] = imported_names(text)
        self.assets[path] = quoted_assets(text)
        self.sizes[path] = text.byte_length()


def closure(
    root: String, suite: String, known: Set[String], mut cache: SourceCache
) raises -> List[String]:
    """Return the sorted files a suite reaches through its imports.

    Every import in the build searches the suite's directory and then the
    root, not the directory of the importing module.

    Args:
        root: The repository root.
        suite: The entry point.
        known: Every `.mojo` path.
        cache: What earlier calls read.

    Returns:
        The suite and every file it reaches.

    Raises:
        Error: If a reached file cannot be read.
    """
    var entry = dirname(suite)
    var entries: List[String] = [entry]
    var seen = Set[String]()
    seen.add(suite)
    var stack: List[String] = [suite]
    while len(stack) > 0:
        var path = stack.pop()
        cache.read(root, path)
        var key = entry + "\0" + path
        if not key in cache.resolved:
            var reached = List[String]()
            for name in cache.names[path]:
                reached.extend(resolve(name, known, entries))
            cache.resolved[key] = reached^
        for target in cache.resolved[key]:
            if not target in seen:
                seen.add(target)
                stack.append(target)
    return sorted_set(seen)


# --- changes -----------------------------------------------------------------


def git(root: String, arguments: List[String]) -> Optional[String]:
    """Return git's output, or nothing when git fails.

    Args:
        root: The repository root.
        arguments: The arguments after `git`.

    Returns:
        The standard output.
    """
    var command: List[String] = ["git"]
    command.extend(arguments.copy())
    try:
        var result = run_program(
            command, 600, merge_errors=False, directory=root
        )
        if result.status != 0:
            return None
        return result.output.copy()
    except:
        return None


def split_nul(text: String) -> List[String]:
    """Return the non-empty fields of NUL-separated text.

    Args:
        text: The text.

    Returns:
        Its fields.
    """
    var fields = List[String]()
    for field in text.split("\0"):
        if field.byte_length() > 0:
            fields.append(String(field))
    return fields^


def changed_paths(root: String, base: String) -> Optional[Dict[String, Bool]]:
    """Return the paths changed since the merge base, or nothing.

    The change runs from the merge base of `base` and `HEAD` to the working
    tree. An untracked file counts when a build reads it: a source or an
    asset.

    Args:
        root: The repository root.
        base: The ref to compare with.

    Returns:
        Each changed path and whether it was deleted, or nothing when git
        cannot say.
    """
    var merge_base = git(root, ["merge-base", base, "HEAD"])
    if not merge_base:
        return None
    var diff = git(
        root,
        [
            "diff",
            "--name-status",
            "--no-renames",
            "-z",
            _strip(merge_base.value()),
        ],
    )
    var untracked = git(
        root, ["ls-files", "--others", "--exclude-standard", "-z"]
    )
    if not diff or not untracked:
        return None
    var paths = Dict[String, Bool]()
    var fields = diff.value().split("\0")
    var index = 0
    while index + 1 < len(fields):
        paths[String(fields[index + 1])] = String(fields[index]) == "D"
        index += 2
    for path in split_nul(untracked.value()):
        if (
            path.endswith(".mojo")
            or path.endswith(".py")
            or path.endswith(".c")
            or path.endswith(".h")
            or path.startswith("assets/")
        ):
            paths[path] = False
    return paths^


struct Selection(Movable):
    """The `.mojo` files a change affects, or all of them."""

    var all: Bool
    """True when the change can affect everything."""
    var files: Set[String]
    """The affected files when `all` is False."""

    def __init__(out self, all: Bool, var files: Set[String]):
        """Make a selection.

        Args:
            all: True for everything.
            files: The affected files.
        """
        self.all = all
        self.files = files^

    @staticmethod
    def everything() -> Selection:
        """Return the selection of everything.

        Returns:
            A selection with `all` set.
        """
        return Selection(True, Set[String]())


def affected_set(
    root: String, changed: Dict[String, Bool], mut reasons: List[String]
) -> Selection:
    """Return the `.mojo` files a change affects.

    A file is affected when it changed, imports an affected file, or quotes
    a path that a changed asset starts with. A changed test also selects
    the library it imports and every suite that can reach that library, so
    coverage loss is checked. Documentation affects nothing. A deleted
    suite, the coverage tool, or any other input selects everything.

    Args:
        root: The repository root.
        changed: Each changed path and whether it was deleted.
        reasons: Gets a line that says why everything is selected.

    Returns:
        The selection.
    """
    for entry in changed.items():
        var path = entry.key
        if is_documentation(path):
            continue
        if path.endswith(".mojo") and not path.startswith("coverage/"):
            if entry.value and path.startswith("tests/test_"):
                reasons.append("a test suite was deleted: " + path)
                return Selection.everything()
            continue
        if path.startswith("assets/"):
            continue
        reasons.append("a build input has no narrower dependency rule: " + path)
        return Selection.everything()

    var files = mojo_files(root)
    var known = Set[String]()
    var seeds = Set[String]()
    var assets = List[String]()
    for path in files:
        known.add(path)
    for entry in changed.items():
        if entry.key.endswith(".mojo"):
            known.add(entry.key)
            seeds.add(entry.key)
        if entry.key.startswith("assets/"):
            assets.append(entry.key)
    var sources = Dict[String, String]()
    for path in files:
        try:
            sources[path] = read_source(root, path)
        except:
            reasons.append("a source file could not be read: " + path)
            return Selection.everything()
    var lookup = Resolver(known^, entry_directories(sources))
    var importers = Dict[String, Set[String]]()
    var imports = Dict[String, Set[String]]()
    for entry in sources.items():
        var path = entry.key
        for name in imported_names(entry.value):
            for target in lookup.lookup(name):
                if target != path:
                    add_edge(importers, target, path)
                    add_edge(imports, path, target)
        for quoted in quoted_assets(entry.value):
            for asset in assets:
                if asset.startswith(quoted):
                    seeds.add(path)
                    break

    var affected = reachable(seeds, importers)
    var edited_test = False
    for path in seeds:
        if path.startswith("tests/"):
            edited_test = True
    if edited_test:
        # An edited test can stop exercising unchanged library code. Measure
        # its imports too, with all the suites that can reach those modules.
        # Include users of a changed helper, not only the helper's imports.
        var tests = Set[String]()
        for path in affected:
            if path.startswith("tests/"):
                tests.add(path)
        var measured = reachable(tests, imports)
        for path in reachable(measured, importers):
            affected.add(path)
    return Selection(False, affected^)


def _name_set(source: String) -> Set[String]:
    """Return the imported names of a source, as a set."""
    var names = Set[String]()
    for name in imported_names(source):
        names.add(name)
    return names^


def test_imports_removed(
    root: String,
    changed: Dict[String, Bool],
    base: String,
    mut reasons: List[String],
) -> Bool:
    """Return whether a changed test drops imports, or its past is unknown.

    The current graph cannot reach an import that a test no longer names,
    so the full check keeps that former coverage obligation. An added test
    has no former imports.

    Args:
        root: The repository root.
        changed: Each changed path and whether it was deleted.
        base: The ref to compare with.
        reasons: Gets a line that says why the answer is True.

    Returns:
        True when a changed test or helper removed an import or was
        deleted, or when git cannot give its former text.
    """
    var tests = List[String]()
    for entry in changed.items():
        if entry.key.startswith("tests/") and entry.key.endswith(".mojo"):
            tests.append(entry.key)
    if len(tests) == 0:
        return False
    var merge_base = git(root, ["merge-base", base, "HEAD"])
    if not merge_base:
        reasons.append("the test import baseline could not be established")
        return True
    var revision = _strip(merge_base.value())
    var arguments: List[String] = [
        "ls-tree",
        "-r",
        "--name-only",
        "-z",
        revision,
        "--",
    ]
    arguments.extend(tests^)
    var tracked = git(root, arguments)
    if not tracked:
        reasons.append("the baseline test inventory could not be read")
        return True
    for path in split_nul(tracked.value()):
        if changed.get(path).or_else(False):
            reasons.append("a test or helper was deleted: " + path)
            return True
        var before = git(root, ["show", revision + ":" + path])
        if not before:
            reasons.append("a baseline test could not be read: " + path)
            return True
        var after: String
        try:
            after = read_source(root, path)
        except:
            reasons.append("a changed test could not be read: " + path)
            return True
        var now = _name_set(after)
        for name in imported_names(before.value()):
            if not name in now:
                reasons.append("a test or helper removed imports: " + path)
                return True
    return False
