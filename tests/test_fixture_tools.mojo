# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Tests for `tools.fixture_manifest` and `tools.fixture_runtime`.

Each test builds a small repository in a temporary directory: a manifest,
a generator, the locked runtime packages and a fake `node` script. The
fake prints the runtime for `-p` and the file `words` for a generator run,
and logs each call with its working directory.
"""

from std.os import getenv, setenv, unsetenv
from std.pathlib import Path
from std.tempfile import mkdtemp
from std.testing import (
    TestSuite,
    assert_equal,
    assert_false,
    assert_raises,
    assert_true,
)

from loaders.json import JsonDocument, parse_json
from tools.fixture_manifest import (
    check,
    digest,
    is_exact_v8,
    is_exact_version,
    runtime_metadata_errors,
)
from tools.fixture_runtime import (
    output_words,
    reproduce,
    runtime_errors,
    table_words,
    word_digest,
    word_text,
    write_word_differences,
)
from tools.json_tools import JsonWriter
from tools.process import run_program

comptime _NODE = """#!/bin/sh
dir=$(dirname "$0")
printf '%s|%s\\n' "$PWD" "$*" >>"$dir/calls"
for argument; do
    if [ "$argument" = "-p" ]; then cat "$dir/runtime"; exit 0; fi
done
cat "$dir/words"
"""
comptime _PACKAGE = (
    '{"engines": {"node": "24.19.0"}, "dependencies": {"three": "0.180.0"}}'
)
comptime _LOCK = (
    '{"packages": {"": {"engines": {"node": "24.19.0"}, "dependencies":'
    ' {"three": "0.180.0"}}, "node_modules/three": {"version": "0.180.0",'
    ' "integrity": "sha512-pinned"}}}'
)
comptime _RUNTIME = (
    '{"node": "24.19.0", "v8": "13.6.233.17-node.51", "platform": "linux",'
    ' "arch": "x64"}'
)


def _words(count: Int, first: UInt64 = 0) -> String:
    """Return `count` words from `first`, as the generator prints them."""
    var parts = List[String]()
    for i in range(count):
        parts.append(word_text(first + UInt64(i)))
    return String(",\n").join(parts)


struct Repo(Movable):
    """A temporary repository with one verified `js_number` family."""

    var root: String
    var bin: String

    def __init__(out self) raises:
        self.root = mkdtemp(prefix="threemojo-fixture-test-")
        self.bin = self.root + "/bin"
        for directory in [
            "/assets/js_number",
            "/loaders",
            "/tools/fixture-runtime",
            "/bin",
            "/deps/three",
        ]:
            _ = run_program(["mkdir", "-p", self.root + directory], 10)
        self.write("/assets/js_number/srgb.mjs", "generator\n")
        self.write(
            "/loaders/js_number.mojo",
            "# 0xFFFFFFFFFFFFFFFF\ncomptime _SRGB_TO_LINEAR: List[UInt64] = ["
            + _words(256, 7)
            + "]\n",
        )
        self.write("/tools/fixture-runtime/package.json", _PACKAGE)
        self.write("/tools/fixture-runtime/package-lock.json", _LOCK)
        self.write("/deps/three/package.json", '{"version": "0.180.0"}')
        self.write("/bin/node", _NODE)
        self.write("/bin/runtime", _RUNTIME)
        self.write("/bin/words", _words(256, 7) + "\n")
        _ = run_program(["chmod", "+x", self.bin + "/node"], 10)

    def write(self, relative: String, text: String) raises:
        Path(self.root + relative).write_text(text)

    def family_text(self) raises -> String:
        """Return the verified js_number family record."""
        return (
            '{"family": "js_number", "generator": "assets/js_number/srgb.mjs",'
            + ' "three_version": null, "version_evidence": "header",'
            + ' "cwd": ".", "commands": ["npm ci --ignore-scripts --prefix'
            + ' tools/fixture-runtime", "mojo run -I .'
            + ' tools/fixture_runtime.mojo js_number"],'
            + ' "generator_sha256": "'
            + digest(self.root + "/assets/js_number/srgb.mjs")
            + '", "artifacts": {"loaders/js_number.mojo": "'
            + digest(self.root + "/loaders/js_number.mojo")
            + '"}, "verified_runtime": {"node": "24.19.0",'
            + ' "v8": "13.6.233.17-node.51", "platform": "linux",'
            + ' "arch": "x64", "node_flags": ["--no-use-std-math-pow"],'
            + ' "dependencies": {"three": "0.180.0"}, "evidence": "baseline",'
            + ' "historical_environment_recovered": false},'
            + ' "separate_snapshot": {"generator": null, "historical_node":'
            + ' null, "historical_v8": null, "historical_node_major": 22,'
            + ' "path": "assets/js_number/v8.json", "status":'
            + ' "not_regenerated", "evidence": "snapshot"}}'
        )

    def manifest(self, family: String) raises -> JsonDocument:
        return parse_json('{"families": [' + family + "]}")

    def calls(self) raises -> List[String]:
        if not Path(self.bin + "/calls").exists():
            return List[String]()
        var lines = List[String]()
        for line in Path(self.bin + "/calls").read_text().splitlines():
            lines.append(String(line))
        return lines^

    def close(self) raises:
        """Remove the repository. A test calls it last, which also keeps
        the repository alive until the test ends."""
        _ = run_program(["rm", "-rf", self.root], 10)


def _family(document: JsonDocument) raises -> Int:
    """Return the only family node of a manifest."""
    return document.at(document.get(document.root(), "families"), 0)


def _clear_node_options() -> String:
    """Unset `NODE_OPTIONS` and return its old value for `_restore`."""
    var old = getenv("NODE_OPTIONS")
    _ = unsetenv("NODE_OPTIONS")
    return old^


def _restore(old: String):
    """Restore a `NODE_OPTIONS` value that `_clear_node_options` saved."""
    if old.byte_length() > 0:
        _ = setenv("NODE_OPTIONS", old)


# --- manifest ----------------------------------------------------------------


def test_versions_are_exact() raises:
    assert_true(is_exact_version("0.180.0"))
    for bad in ["", "0.180", "^0.180.0", "0.180.0-rc", "a.b.c", "1..2"]:
        assert_false(is_exact_version(bad))
    assert_true(is_exact_v8("13.6.233.17-node.51"))
    for bad in ["13.6.233.17", "13.6.233-node.51", "13.6.233.17-node.", "13.6"]:
        assert_false(is_exact_v8(bad))


def test_a_matching_repository_has_no_errors() raises:
    var repo = Repo()
    var manifest = repo.manifest(repo.family_text())
    assert_equal(len(check(repo.root, manifest)), 0)
    assert_equal(
        len(runtime_metadata_errors(repo.root, manifest, _family(manifest))),
        0,
    )
    repo.close()


def test_changed_missing_and_unlisted_files_are_reported() raises:
    var repo = Repo()
    var manifest = repo.manifest(repo.family_text())
    repo.write("/loaders/js_number.mojo", "changed\n")
    var errors = check(repo.root, manifest)
    assert_equal(len(errors), 1)
    assert_equal(errors[0], "changed: loaders/js_number.mojo")
    _ = run_program(["rm", repo.root + "/loaders/js_number.mojo"], 10)
    errors = check(repo.root, manifest)
    assert_equal(errors[0], "missing: loaders/js_number.mojo")
    repo.write("/assets/new.mjs", "")
    _ = run_program(["mkdir", "-p", repo.root + "/assets/node_modules"], 10)
    repo.write("/assets/node_modules/ignored.mjs", "")
    errors = check(repo.root, manifest)
    assert_equal(
        errors[len(errors) - 1], "generator inventory differs: assets/new.mjs"
    )
    repo.close()


def test_duplicates_versions_and_provenance_are_reported() raises:
    var repo = Repo()
    var other = (
        '{"family": "other", "generator": "assets/js_number/srgb.mjs",'
        + ' "three_version": "^0.180.0", "version_evidence": "",'
        + ' "commands": [], "generator_sha256": "'
        + digest(repo.root + "/assets/js_number/srgb.mjs")
        + '", "artifacts": {}}'
    )
    var errors = check(
        repo.root, repo.manifest(repo.family_text() + ", " + other)
    )
    var text = String("\n").join(errors)
    assert_true(
        text.find("duplicate generator: assets/js_number/srgb.mjs") >= 0
    )
    assert_true(text.find("three_version must be exact") >= 0)
    assert_true(text.find("missing provenance or commands") >= 0)
    repo.close()


def test_runtime_metadata_cannot_drift() raises:
    var repo = Repo()
    var base = repo.family_text()
    var mutations = [
        ('"verified_runtime"', '"verified_runtime_removed"'),
        ('"node": "24.19.0"', '"node": "24"'),
        ('"v8": "13.6.233.17-node.51"', '"v8": "13.6"'),
        ('"platform": "linux"', '"platform": "darwin"'),
        ('"arch": "x64"', '"arch": "arm64"'),
        ('"node_flags": ["--no-use-std-math-pow"]', '"node_flags": []'),
        (
            '"historical_environment_recovered": false',
            '"historical_environment_recovered": true',
        ),
        ('"evidence": "baseline"', '"evidence": ""'),
        ('"dependencies": {"three": "0.180.0"}', '"dependencies": {}'),
        (
            '"dependencies": {"three": "0.180.0"}',
            '"dependencies": {"three": "^0.180.0"}',
        ),
        ('"three_version": null', '"three_version": "0.180.0"'),
        ('"cwd": "."', '"cwd": "assets/js_number"'),
        ('"status": "not_regenerated"', '"status": "reproduced"'),
        ('"historical_node": null', '"historical_node": "24.19.0"'),
        ('"historical_node_major": 22', '"historical_node_major": 24'),
        ('"path": "assets/js_number/v8.json"', '"path": "other.json"'),
        ('"evidence": "snapshot"', '"evidence": ""'),
        ('"generator": null', '"generator": "srgb.mjs"'),
    ]
    for mutation in mutations:
        var changed = base.replace(mutation[0], mutation[1])
        assert_true(changed != base)
        var manifest = parse_json(changed)
        assert_true(
            len(runtime_metadata_errors(repo.root, manifest, manifest.root()))
            > 0
        )
    var unverified = parse_json('{"family": "unverified"}')
    assert_equal(
        len(runtime_metadata_errors(repo.root, unverified, unverified.root())),
        0,
    )
    repo.close()


def test_package_and_lock_pins_cannot_drift() raises:
    var repo = Repo()
    var manifest = repo.manifest(repo.family_text())
    var family = _family(manifest)
    var mutations = [
        (
            "/tools/fixture-runtime/package.json",
            '"node": "24.19.0"',
            '"node": ">=24"',
        ),
        (
            "/tools/fixture-runtime/package.json",
            '"three": "0.180.0"',
            '"three": "^0.180.0"',
        ),
        (
            "/tools/fixture-runtime/package-lock.json",
            '"engines": {"node": "24.19.0"}',
            '"engines": {}',
        ),
        (
            "/tools/fixture-runtime/package-lock.json",
            '"dependencies": {"three": "0.180.0"}',
            '"dependencies": {}',
        ),
        (
            "/tools/fixture-runtime/package-lock.json",
            '"version": "0.180.0"',
            '"version": "0.181.0"',
        ),
        (
            "/tools/fixture-runtime/package-lock.json",
            ', "integrity": "sha512-pinned"',
            "",
        ),
    ]
    for mutation in mutations:
        var original = _PACKAGE if mutation[0].endswith(
            "package.json"
        ) else _LOCK
        repo.write(
            mutation[0], String(original).replace(mutation[1], mutation[2])
        )
        assert_true(
            len(runtime_metadata_errors(repo.root, manifest, family)) > 0
        )
        repo.write(mutation[0], original)
    _ = run_program(
        ["rm", repo.root + "/tools/fixture-runtime/package-lock.json"], 10
    )
    var errors = runtime_metadata_errors(repo.root, manifest, family)
    assert_equal(len(errors), 1)
    assert_true(
        errors[0].find("cannot check runtime package pins: [Errno 2]") >= 0
    )
    repo.close()


# --- runtime -----------------------------------------------------------------


def test_exact_runtime_is_required() raises:
    var repo = Repo()
    var manifest = repo.manifest(repo.family_text())
    var baseline = manifest.get(_family(manifest), "verified_runtime")
    var observed = parse_json(_RUNTIME)
    assert_equal(len(runtime_errors(observed, manifest, baseline)), 0)
    for key in ["node", "v8", "platform", "arch"]:
        var changed = parse_json(
            String(_RUNTIME).replace(
                '"' + key + '": ', '"' + key + '": "different", "x": '
            )
        )
        var errors = runtime_errors(changed, manifest, baseline)
        assert_equal(len(errors), 1)
        assert_true(errors[0].startswith(key + ": expected "))
    repo.close()


def test_word_parser_is_bounded_to_the_srgb_table() raises:
    var text = _words(256)
    var words = output_words(text)
    assert_equal(len(words), 256)
    assert_equal(words[255], 255)
    var source = (
        "# 0xFFFFFFFFFFFFFFFF\ncomptime _SRGB_TO_LINEAR: List[UInt64] = ["
        + text
        + "]\n# 0xFFFFFFFFFFFFFFFF"
    )
    assert_equal(table_words(source)[17], 17)
    for bad in [
        String(""),
        text + ", 0x0000000000000000",
        "x" + String(text[byte=2:]),
        text + "\nextra",
        text.replace("0x0000000000000001", "0x000000000000000g"),
    ]:
        with assert_raises():
            _ = output_words(bad)
    with assert_raises(contains="not found"):
        _ = table_words(text)
    with assert_raises(contains="not found"):
        _ = table_words("comptime _SRGB_TO_LINEAR: List[UInt64] = [0x1")


def test_word_diff_preserves_direction_and_float32_effect() raises:
    var old: List[UInt64] = [
        0x3F76F5ADDB270744,
        0x3F78C6A940063D0E,
        0x3FF0000000000000,
    ]
    var new: List[UInt64] = [old[0] + 1, old[1] - 1, old[2]]
    var writer = JsonWriter()
    write_word_differences(old, new, writer)
    var report = parse_json(writer.text())
    assert_equal(report.length(report.root()), 2)
    var first = report.at(report.root(), 0)
    assert_equal(report.integer(report.get(first, "ulp_delta")), 1)
    assert_equal(
        report.string(report.get(first, "accepted")), "0x3F76F5ADDB270744"
    )
    assert_true(report.boolean(report.get(first, "float32_unchanged")))
    var second = report.at(report.root(), 1)
    assert_equal(report.integer(report.get(second, "ulp_delta")), -1)
    assert_true(word_digest(old) != word_digest(new))
    var same = JsonWriter()
    write_word_differences(old, old, same)
    assert_equal(same.text(), "[]")
    var one: List[UInt64] = [0x3FF0000000000000]
    var two: List[UInt64] = [0x4000000000000000]
    var changed = JsonWriter()
    write_word_differences(one, two, changed)
    assert_true(changed.text().find('"float32_unchanged": false') >= 0)
    var short = new.copy()
    _ = short.pop()
    var refused = JsonWriter()
    with assert_raises(contains="counts differ"):
        write_word_differences(old, short, refused)


def test_missing_flag_and_node_options_stop_before_node() raises:
    var saved = _clear_node_options()
    var repo = Repo()
    var manifest = repo.manifest(
        repo.family_text().replace(
            '"node_flags": ["--no-use-std-math-pow"]', '"node_flags": []'
        )
    )
    with assert_raises(contains="requires --no-use-std-math-pow"):
        _ = reproduce(
            repo.root,
            manifest,
            _family(manifest),
            repo.bin + "/node",
            repo.root + "/deps",
            False,
        )
    var good = repo.manifest(repo.family_text())
    _ = setenv("NODE_OPTIONS", "--jitless")
    with assert_raises(contains="unset NODE_OPTIONS"):
        _ = reproduce(
            repo.root,
            good,
            _family(good),
            repo.bin + "/node",
            repo.root + "/deps",
            False,
        )
    _ = unsetenv("NODE_OPTIONS")
    assert_equal(len(repo.calls()), 0)
    _restore(saved)
    repo.close()


def test_reproduction_uses_a_temporary_directory_and_exact_flags() raises:
    var saved = _clear_node_options()
    var repo = Repo()
    var manifest = repo.manifest(repo.family_text())
    var family = _family(manifest)
    var node = repo.bin + "/node"
    var deps = repo.root + "/deps"
    var result = reproduce(repo.root, manifest, family, node, deps, False)
    assert_true(result[1])
    var report = parse_json(result[0])
    var root = report.root()
    assert_true(report.boolean(report.get(root, "matches")))
    assert_false(
        report.boolean(report.get(root, "historical_environment_recovered"))
    )
    assert_equal(report.string(report.get(root, "mode")), "verify_accepted")
    assert_equal(report.integer(report.get(root, "word_count")), 256)
    assert_equal(report.key(root, 0), "family")
    var calls = repo.calls()
    assert_equal(len(calls), 2)
    var run = calls[1].split("|")
    assert_equal(String(run[1]), "--no-use-std-math-pow srgb.mjs")
    assert_true(String(run[0]) != repo.root + "/assets/js_number")
    assert_false(Path(String(run[0])).exists())
    # Diagnostic mode drops the pinned flag and never claims a match.
    var diagnostic = reproduce(repo.root, manifest, family, node, deps, True)
    var diagnosis = parse_json(diagnostic[0])
    assert_equal(
        diagnosis.string(diagnosis.get(diagnosis.root(), "mode")),
        "diagnostic_only",
    )
    var runtime = diagnosis.get(diagnosis.root(), "runtime")
    assert_equal(diagnosis.length(diagnosis.get(runtime, "node_flags")), 0)
    # A changed table word is reported, not accepted.
    repo.write("/bin/words", _words(256, 8) + "\n")
    var differs = reproduce(repo.root, manifest, family, node, deps, False)
    assert_false(differs[1])
    _restore(saved)
    repo.close()


def test_runtime_and_package_mismatches_stop_after_the_probe() raises:
    var saved = _clear_node_options()
    var repo = Repo()
    var manifest = repo.manifest(repo.family_text())
    var family = _family(manifest)
    repo.write("/bin/runtime", String(_RUNTIME).replace("24.19.0", "0.0.0"))
    with assert_raises(contains="node: expected 24.19.0, got 0.0.0"):
        _ = reproduce(
            repo.root,
            manifest,
            family,
            repo.bin + "/node",
            repo.root + "/deps",
            False,
        )
    assert_equal(len(repo.calls()), 1)
    repo.write("/bin/runtime", _RUNTIME)
    repo.write("/deps/three/package.json", '{"version": "0.181.0"}')
    with assert_raises(contains="three: expected 0.180.0, got 0.181.0"):
        _ = reproduce(
            repo.root,
            manifest,
            family,
            repo.bin + "/node",
            repo.root + "/deps",
            False,
        )
    assert_equal(len(repo.calls()), 2)
    _restore(saved)
    repo.close()


def test_a_failing_node_is_reported() raises:
    var saved = _clear_node_options()
    var repo = Repo()
    var manifest = repo.manifest(repo.family_text())
    repo.write("/bin/node", "#!/bin/sh\necho broken 1>&2\nexit 3\n")
    with assert_raises(contains="returned non-zero exit status 3"):
        _ = reproduce(
            repo.root,
            manifest,
            _family(manifest),
            repo.bin + "/node",
            repo.root + "/deps",
            False,
        )
    _restore(saved)
    repo.close()


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
