# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Check the recorded three.js fixture baselines without running generators.

    mojo run -I . tools/fixture_manifest.mojo [--commands FAMILY]

The check reads `assets/fixture-manifest.json`. Each generator and each
artifact must exist and match its recorded SHA-256. Every `.mjs` generator
under `assets/` must be recorded. The verified runtime families also need
exact Node, V8 and package pins and the guarded commands. The check never
updates the accepted hashes. `--commands FAMILY` prints the recorded manual
steps that regenerate one family.
"""

from std.os import listdir
from std.os.path import dirname, isdir, isfile
from std.pathlib import Path
from std.reflection import source_location
from std.sys import argv, exit, stderr

from loaders.json import BOOLEAN, JsonDocument, parse_json
from tools._json_tools import (
    MISSING,
    equal,
    equals_text,
    equals_texts,
    get,
    index,
    is_none,
    keys,
    python_text,
    truthy,
)
from tools._sha256 import sha256_hex

comptime MANIFEST = "assets/fixture-manifest.json"
"""The manifest, relative to the repository root."""
comptime RUNTIME_PACKAGES = "tools/fixture-runtime"
"""The locked Node packages of the verified runtime families."""


def repository_root() -> String:
    """Return the repository root: the parent of this file's directory.

    Returns:
        The absolute repository path.
    """
    return dirname(dirname(String(source_location().file_name())))


def digest(path: String) raises -> String:
    """Return a file's SHA-256 as lowercase hexadecimal digits.

    Args:
        path: The file.

    Returns:
        The digest.

    Raises:
        Error: If the file cannot be read.
    """
    return sha256_hex(Span(Path(path).read_bytes()))


def _digit_run(bytes: Span[UInt8, _], start: Int) -> Int:
    """Return the end of the ASCII digits at `start`."""
    var i = start
    while i < len(bytes) and bytes[i] >= 0x30 and bytes[i] <= 0x39:
        i += 1
    return i


def _dotted(bytes: Span[UInt8, _], start: Int, groups: Int) -> Int:
    """Return the end of `groups` digit runs joined by dots, or -1."""
    var i = start
    for group in range(groups):
        if group > 0:
            if i >= len(bytes) or bytes[i] != 0x2E:
                return -1
            i += 1
        var end = _digit_run(bytes, i)
        if end == i:
            return -1
        i = end
    return i


def is_exact_version(text: String) -> Bool:
    """Return whether `text` is `MAJOR.MINOR.PATCH` digits, nothing more.

    Args:
        text: The version text.

    Returns:
        True for three dot-separated digit runs.
    """
    var bytes = text.as_bytes()
    return _dotted(bytes, 0, 3) == len(bytes)


def is_exact_v8(text: String) -> Bool:
    """Return whether `text` is a V8 version such as `13.6.233.17-node.51`.

    Args:
        text: The version text.

    Returns:
        True for four dot-separated digit runs, `-node.` and digits.
    """
    var bytes = text.as_bytes()
    var i = _dotted(bytes, 0, 4)
    if i < 0:
        return False
    var suffix = "-node.".as_bytes()
    if i + len(suffix) > len(bytes):
        return False
    for k in range(len(suffix)):
        if bytes[i + k] != suffix[k]:
            return False
    i += len(suffix)
    var end = _digit_run(bytes, i)
    return end > i and end == len(bytes)


def _read_json(path: String) raises -> JsonDocument:
    """Read a JSON file, with Python's message for a missing file."""
    if not Path(path).exists():
        raise Error("[Errno 2] No such file or directory: '" + path + "'")
    return parse_json(Path(path).read_text())


def _package_errors(
    root: String,
    name: String,
    manifest: JsonDocument,
    baseline: Int,
    dependencies: Int,
    mut errors: List[String],
) raises:
    """Compare the runtime package and lockfile pins with the baseline."""
    var package = _read_json(root + "/" + RUNTIME_PACKAGES + "/package.json")
    var lock = _read_json(root + "/" + RUNTIME_PACKAGES + "/package-lock.json")
    var engines = get(package, package.root(), "engines")
    if not equal(
        package,
        get(package, engines, "node"),
        manifest,
        get(manifest, baseline, "node"),
    ):
        errors.append(name + ": package Node pin differs")
    var packages = index(lock, lock.root(), "packages")
    var top = index(lock, packages, "")
    if not equal(lock, get(lock, top, "engines"), package, engines):
        errors.append(name + ": lockfile Node pin differs")
    if not equal(
        lock,
        get(lock, top, "dependencies"),
        package,
        get(package, package.root(), "dependencies"),
    ):
        errors.append(name + ": lockfile dependency pins differ")
    for dependency in keys(manifest, dependencies):
        var version = manifest.get(dependencies, dependency)
        var entry = index(lock, packages, "node_modules/" + dependency)
        var pinned = get(
            package,
            index(package, package.root(), "dependencies"),
            dependency,
        )
        if (
            not equal(package, pinned, manifest, version)
            or not equal(lock, get(lock, entry, "version"), manifest, version)
            or not truthy(lock, get(lock, entry, "integrity"))
        ):
            errors.append(
                name + ": " + dependency + " package/lock pin differs"
            )


def runtime_metadata_errors(
    root: String, manifest: JsonDocument, family: Int
) raises -> List[String]:
    """Require exact pins and guarded commands for verified runtime families.

    Args:
        root: The repository root.
        manifest: The parsed manifest.
        family: One family node.

    Returns:
        One message per problem, in the order the Python check gave them.
        A family other than `vtk` and `js_number` has none.

    Raises:
        Error: If the manifest does not have the expected shape.
    """
    var errors = List[String]()
    var name_node = get(manifest, family, "family")
    if not (
        equals_text(manifest, name_node, "vtk")
        or equals_text(manifest, name_node, "js_number")
    ):
        return errors^
    var name = manifest.string(name_node)
    var baseline = get(manifest, family, "verified_runtime")
    if not is_exact_version(
        _text_or_empty(manifest, get(manifest, baseline, "node"))
    ):
        errors.append(name + ": verified node must be exact")
    if not is_exact_v8(_text_or_empty(manifest, get(manifest, baseline, "v8"))):
        errors.append(name + ": verified v8 must be exact")
    if not equals_text(
        manifest, get(manifest, baseline, "platform"), "linux"
    ) or not equals_text(manifest, get(manifest, baseline, "arch"), "x64"):
        errors.append(name + ": verified platform must remain linux/x64")
    var flags = List[String]()
    if name == "js_number":
        flags.append("--no-use-std-math-pow")
    if not equals_texts(manifest, get(manifest, baseline, "node_flags"), flags):
        errors.append(name + ": verified Node flags differ")
    var recovered = get(manifest, baseline, "historical_environment_recovered")
    # Python required `is False`: only JSON `false` passes.
    if not (
        recovered != MISSING
        and manifest.kind(recovered) == BOOLEAN
        and not manifest.boolean(recovered)
    ):
        errors.append(name + ": do not infer historical runtime provenance")
    if not truthy(manifest, get(manifest, baseline, "evidence")):
        errors.append(name + ": missing runtime evidence")
    var dependencies = get(manifest, baseline, "dependencies")
    var names = keys(manifest, dependencies)
    var required = List[String]()
    required.append("three")
    if name == "vtk":
        required.append("@xmldom/xmldom")
    if not _same_set(names, required):
        errors.append(name + ": verified dependencies differ")
    for package in names:
        var version = manifest.get(dependencies, package)
        if not is_exact_version(python_text(manifest, version)):
            errors.append(name + ": " + package + " must be exact")
    var commands = List[String]()
    commands.append("npm ci --ignore-scripts --prefix tools/fixture-runtime")
    commands.append("mojo run -I . tools/fixture_runtime.mojo " + name)
    if not equals_text(
        manifest, get(manifest, family, "cwd"), "."
    ) or not equals_texts(
        manifest, get(manifest, family, "commands"), commands
    ):
        errors.append(name + ": use the pinned, guarded fixture commands")
    try:
        _package_errors(root, name, manifest, baseline, dependencies, errors)
    except error:
        errors.append(
            name + ": cannot check runtime package pins: " + String(error)
        )
    if name == "js_number":
        var snapshot = get(manifest, family, "separate_snapshot")
        var snapshot_keys = keys(manifest, snapshot)
        var needed = List[String]()
        needed.append("generator")
        needed.append("historical_node")
        needed.append("historical_v8")
        var major = get(manifest, snapshot, "historical_node_major")
        var twenty_two = parse_json("22")
        if (
            not is_none(manifest, get(manifest, family, "three_version"))
            or not _contains_all(snapshot_keys, needed)
            or not equal(manifest, major, twenty_two, twenty_two.root())
            or not equals_text(
                manifest,
                get(manifest, snapshot, "path"),
                "assets/js_number/v8.json",
            )
            or not equals_text(
                manifest, get(manifest, snapshot, "status"), "not_regenerated"
            )
            or not is_none(manifest, get(manifest, snapshot, "generator"))
            or not is_none(manifest, get(manifest, snapshot, "historical_node"))
            or not is_none(manifest, get(manifest, snapshot, "historical_v8"))
            or not truthy(manifest, get(manifest, snapshot, "evidence"))
        ):
            errors.append(
                name + ": keep the separate V8 snapshot provenance explicit"
            )
    return errors^


def _text_or_empty(document: JsonDocument, node: Int) raises -> String:
    """Return `str(value)` with a missing value read as an empty string."""
    if node == MISSING:
        return ""
    return python_text(document, node)


def _same_set(a: List[String], b: List[String]) -> Bool:
    """Return whether two lists hold the same set of strings."""
    return _contains_all(a, b) and _contains_all(b, a)


def _contains_all(have: List[String], want: List[String]) -> Bool:
    """Return whether every string of `want` is in `have`."""
    for item in want:
        var found = False
        for other in have:
            if other == item:
                found = True
                break
        if not found:
            return False
    return True


def _sorted(var items: List[String]) -> List[String]:
    """Sort strings by code point."""
    for i in range(1, len(items)):
        var j = i
        while j > 0 and items[j] < items[j - 1]:
            items.swap_elements(j, j - 1)
            j -= 1
    return items^


def generator_files(root: String) raises -> List[String]:
    """Return every `.mjs` path under `assets/`, outside `node_modules`.

    Args:
        root: The repository root.

    Returns:
        Repository-relative paths, in sorted order.
    """
    var found = List[String]()
    var pending = List[String]()
    pending.append("assets")
    while len(pending) > 0:
        var relative = pending.pop()
        var absolute = root + "/" + relative
        if not isdir(absolute):
            continue
        for entry in listdir(absolute):
            var name = String(entry)
            var child = relative + "/" + name
            if name == "node_modules":
                continue
            if name.endswith(".mjs"):
                found.append(child)
            if isdir(root + "/" + child):
                pending.append(child)
    return _sorted(found^)


def check(root: String, manifest: JsonDocument) raises -> List[String]:
    """Return drift and metadata errors; never update the accepted hashes.

    Args:
        root: The repository root.
        manifest: The parsed manifest.

    Returns:
        One message per problem.

    Raises:
        Error: If the manifest does not have the expected shape.
    """
    var errors = List[String]()
    var recorded = List[String]()
    var families = index(manifest, manifest.root(), "families")
    for i in range(manifest.length(families)):
        var family = manifest.at(families, i)
        var generator = manifest.string(index(manifest, family, "generator"))
        for other in recorded:
            if other == generator:
                errors.append("duplicate generator: " + generator)
                break
        recorded.append(generator)
        var version = index(manifest, family, "three_version")
        if not is_none(manifest, version) and not is_exact_version(
            manifest.string(version)
        ):
            errors.append(generator + ": three_version must be exact")
        if not truthy(
            manifest, get(manifest, family, "version_evidence")
        ) or not truthy(manifest, get(manifest, family, "commands")):
            errors.append(generator + ": missing provenance or commands")
        errors.extend(runtime_metadata_errors(root, manifest, family))
        var names = List[String]()
        var hashes = List[String]()
        names.append(generator)
        hashes.append(
            manifest.string(index(manifest, family, "generator_sha256"))
        )
        var artifacts = index(manifest, family, "artifacts")
        for artifact in keys(manifest, artifacts):
            var expected = manifest.string(manifest.get(artifacts, artifact))
            if artifact == generator:
                hashes[0] = expected
            else:
                names.append(artifact)
                hashes.append(expected)
        for k in range(len(names)):
            var path = root + "/" + names[k]
            if not isfile(path):
                errors.append("missing: " + names[k])
            elif digest(path) != hashes[k]:
                errors.append("changed: " + names[k])
    var actual = generator_files(root)
    var difference = List[String]()
    for name in actual:
        var known = False
        for other in recorded:
            if other == name:
                known = True
        if not known:
            difference.append(name)
    for name in recorded:
        var present = False
        for other in actual:
            if other == name:
                present = True
        var listed = False
        for other in difference:
            if other == name:
                listed = True
        if not present and not listed:
            difference.append(name)
    for name in _sorted(difference^):
        errors.append("generator inventory differs: " + name)
    return errors^


def main() raises:
    var arguments = argv()
    var family_name = String()
    var wanted = False
    var i = 1
    while i < len(arguments):
        var argument = String(arguments[i])
        if argument == "-h" or argument == "--help":
            print("usage: fixture_manifest.mojo [-h] [--commands FAMILY]")
            return
        if argument.startswith("--commands="):
            family_name = String(argument[byte=11:])
            wanted = True
        elif argument == "--commands" and i + 1 < len(arguments):
            family_name = String(arguments[i + 1])
            wanted = True
            i += 1
        else:
            print(
                "usage: fixture_manifest.mojo [-h] [--commands FAMILY]",
                file=stderr,
            )
            print(
                "fixture_manifest.mojo: error: unrecognized arguments: "
                + argument,
                file=stderr,
            )
            exit(2)
        i += 1
    var root = repository_root()
    var manifest = parse_json(Path(root + "/" + MANIFEST).read_text())
    var families = index(manifest, manifest.root(), "families")
    if wanted:
        for k in range(manifest.length(families)):
            var family = manifest.at(families, k)
            if not equals_text(
                manifest, index(manifest, family, "family"), family_name
            ):
                continue
            print("cwd:", python_text(manifest, index(manifest, family, "cwd")))
            var commands = index(manifest, family, "commands")
            for c in range(manifest.length(commands)):
                print(manifest.string(manifest.at(commands, c)))
            var notes = get(manifest, family, "notes")
            if notes != MISSING:
                for n in range(manifest.length(notes)):
                    print("Note:", manifest.string(manifest.at(notes, n)))
            return
        print(
            "usage: fixture_manifest.mojo [-h] [--commands FAMILY]", file=stderr
        )
        print("fixture_manifest.mojo: error: unknown family", file=stderr)
        exit(2)
    var errors = check(root, manifest)
    for error in errors:
        print(error)
    if len(errors) == 0:
        print(
            "Checked "
            + String(manifest.length(families))
            + " fixture families; hashes match."
        )
        return
    exit(1)
