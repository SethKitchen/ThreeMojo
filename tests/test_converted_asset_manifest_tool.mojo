# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Offline tests for complete converted-asset provenance and cache controls.

The tests run `tools/check_converted_asset_manifest.mojo` on the
repository's manifest, on altered copies of it, and on small caches. No
test downloads: a test that fetches gives a stand-in download command.
"""

from std.os.path import exists
from std.pathlib import Path
from std.tempfile import mkdtemp
from std.testing import (
    TestSuite,
    assert_equal,
    assert_false,
    assert_raises,
    assert_true,
)

from loaders.json import (
    ARRAY,
    BOOLEAN,
    NULL,
    NUMBER,
    OBJECT,
    STRING,
    JsonDocument,
    JsonNode,
)
from tools._process import run_program
from tools._python_float import parse_float
from tools._sha1 import git_blob_sha1
from tools._sha256 import sha256_hex
from tools.check_converted_asset_manifest import (
    MALFORMED,
    MANIFEST,
    check_path,
    dump_json,
    from_hex,
    load_json,
    materialize_sources,
    regenerate_production,
    remove_tree,
    required_files,
    resolve,
    run,
    source_names,
    verify,
)

comptime OFFLINE: List[String] = ["false"]
"""A download command that fails: no test may download."""


# --- editing a manifest ----------------------------------------------------------


def _load() raises -> JsonDocument:
    """Return the repository's manifest."""
    return load_json(Path(MANIFEST).read_text())


def _add(mut data: JsonDocument, var node: JsonNode) -> Int:
    """Add a node and return its index."""
    data.nodes.append(node^)
    return len(data.nodes) - 1


def _number(mut data: JsonDocument, text: String) raises -> Int:
    """Add a number, kept as its literal."""
    var node = JsonNode(NUMBER)
    node.number = parse_float(text)
    node.text = text
    return _add(data, node^)


def _string(mut data: JsonDocument, text: String) -> Int:
    """Add a string."""
    var node = JsonNode(STRING)
    node.text = text
    return _add(data, node^)


def _boolean(mut data: JsonDocument, flag: Bool) -> Int:
    """Add `true` or `false`."""
    var node = JsonNode(BOOLEAN)
    node.flag = flag
    return _add(data, node^)


def _array(mut data: JsonDocument, children: List[Int]) -> Int:
    """Add an array of nodes."""
    var node = JsonNode(ARRAY)
    node.children = children.copy()
    return _add(data, node^)


def _object(mut data: JsonDocument) -> Int:
    """Add an empty object."""
    return _add(data, JsonNode(OBJECT))


def _set(mut data: JsonDocument, parent: Int, key: String, value: Int) raises:
    """Set an object member, as `parent[key] = value` does."""
    for i in range(len(data.nodes[parent].keys)):
        if data.nodes[parent].keys[i] == key:
            data.nodes[parent].children[i] = value
            return
    data.nodes[parent].keys.append(key)
    data.nodes[parent].children.append(value)


def _delete(mut data: JsonDocument, parent: Int, key: String) raises:
    """Remove an object member, as `del parent[key]` does."""
    for i in range(len(data.nodes[parent].keys)):
        if data.nodes[parent].keys[i] == key:
            _ = data.nodes[parent].keys.pop(i)
            _ = data.nodes[parent].children.pop(i)
            return
    raise Error("no member " + key)


def _get(data: JsonDocument, path: List[String]) raises -> Int:
    """Return the node at a path of keys and array indices."""
    var node = data.root()
    for step in path:
        if data.kind(node) == ARRAY:
            var index = Int(step)
            if index < 0:
                index += data.length(node)
            node = data.at(node, index)
        else:
            node = data.get(node, step)
    return node


struct Cases(Movable):
    """Altered manifests, each with the error it must raise."""

    var texts: List[String]
    var errors: List[String]

    def __init__(out self):
        self.texts = List[String]()
        self.errors = List[String]()

    def add(mut self, data: JsonDocument, error: String) raises:
        """Add a manifest and the text its error must contain."""
        self.texts.append(dump_json(data, data.root()))
        self.errors.append(error)

    def add_text(mut self, text: String, error: String):
        """Add a manifest as text."""
        self.texts.append(text)
        self.errors.append(error)

    def check(self) raises:
        """Verify each manifest and require its error."""
        var folder = mkdtemp(prefix="manifest test ")
        try:
            var manifest = folder + "/manifest.json"
            for i in range(len(self.texts)):
                Path(manifest).write_text(self.texts[i])
                var message = String()
                try:
                    verify(".", manifest)
                except error:
                    message = String(error)
                var wanted = self.errors[i].split("|")
                var found = False
                for part in wanted:
                    if part in message:
                        found = True
                assert_true(
                    found,
                    "case "
                    + String(i)
                    + ": wanted "
                    + self.errors[i]
                    + ", got '"
                    + message
                    + "'",
                )
        finally:
            remove_tree(folder)


def _member_case(
    mut cases: Cases,
    path: List[String],
    key: String,
    text: String,
    error: String,
) raises:
    """Add a case that sets `key` of the node at `path` to a JSON value."""
    var data = _load()
    _set(data, _get(data, path), key, _string(data, "@@value@@"))
    cases.add_text(
        dump_json(data, data.root()).replace('"@@value@@"', text), error
    )


# --- the repository's manifest ---------------------------------------------------


def test_local_hashes_source_pins_and_synthetic_reproductions() raises:
    verify()
    verify(require_source_pins=True)
    var outcome = run(["x"])
    assert_equal(outcome[0], 0, outcome[2])
    assert_true(outcome[1].startswith("Verified local hashes"))
    assert_true("Production reproduction was not run" in outcome[1])


def test_the_command_line() raises:
    var outcome = run(["x", "--fetch-sources"])
    assert_equal(outcome[0], 1)
    assert_true("explicit --source-cache" in outcome[2])
    outcome = run(["x", "--bogus"])
    assert_equal(outcome[0], 2)
    assert_true("unrecognized arguments: --bogus" in outcome[2])
    outcome = run(["x", "--source-cache"])
    assert_equal(outcome[0], 2)
    assert_true("expected one argument" in outcome[2])
    outcome = run(["x", "--require-source-pins", "--source-cache=/nonexistent"])
    assert_equal(outcome[0], 1)
    assert_true("Missing pinned source" in outcome[2])


def test_the_manifest_reads_and_writes_exactly() raises:
    var data = _load()
    var again = load_json(dump_json(data, data.root()))
    assert_equal(dump_json(again, again.root()), dump_json(data, data.root()))
    # 0.6 and 1e-07 read as Python reads them, and keep their text.
    var mohawk = _get(data, ["production_assets", "2", "parameters"])
    assert_equal(data.number(data.get(mohawk, "mohawk_head")), 0.6)
    assert_equal(
        dump_json(data, data.get(mohawk, "human_radii")), "[8.1, 9.3, 10.6]"
    )
    assert_equal(len(source_names()), 3)
    assert_equal(len(required_files()), 11)


def test_paths_and_hex_follow_python() raises:
    for good in ["a", "a/b.c", "assets/x.bin"]:
        assert_equal(check_path(good), good)
    for bad in ["", ".", "/a", "a/", "a//b", "a/./b", "../a", "a\\b", "a/.."]:
        with assert_raises(contains="Invalid manifest path"):
            _ = check_path(bad)
    var bytes = from_hex("00ff 7A\n10")
    assert_equal(len(bytes), 4)
    assert_equal(Int(bytes[1]), 255)
    assert_equal(Int(bytes[2]), 0x7A)
    for bad in ["0", "0g", "0 0"]:
        with assert_raises(contains="non-hexadecimal"):
            _ = from_hex(bad)


# --- drift --------------------------------------------------------------------------


def test_registry_status_and_shape_drift_is_refused() raises:
    var cases = Cases()
    for registry in ["production_assets", "synthetic_regeneration"]:
        var data = _load()
        _set(data, data.root(), registry, _array(data, List[Int]()))
        cases.add(data, "registry")
        data = _load()
        var items = _get(data, [registry])
        data.nodes[items].children[0] = data.nodes[items].children[1]
        cases.add(data, "registry")
    var data = _load()
    _set(data, data.root(), "schema_version", _number(data, "1"))
    cases.add(data, "schema")
    data = _load()
    _set(data, data.root(), "status", _string(data, "unverified"))
    cases.add(data, "status")
    data = _load()
    var files = _get(data, ["files"])
    var first = data.nodes[files].keys[0]
    _set(data, files, first, _string(data, "0" * 64))
    cases.add(data, "hash mismatch")
    for text in [
        "{}",
        "[]",
        "null",
        '{"schema_version": 2}',
        '{"schema_version": 2, "status": []}',
    ]:
        cases.add_text(text, MALFORMED + "|status")
    cases.check()


def test_missing_required_hashes_are_refused() raises:
    var cases = Cases()
    for path in required_files():
        var data = _load()
        _delete(data, _get(data, ["files"]), path)
        cases.add(data, "need recorded hashes")
    cases.check()


def test_production_drift_is_refused() raises:
    var cases = Cases()
    var asset: List[String] = ["production_assets", "0"]
    _member_case(cases, asset, "converter", '"wrong"', "converter binding")
    _member_case(cases, asset, "source", "{}", "source binding")
    _member_case(cases, asset, "parameters", "{}", "parameter")
    _member_case(cases, asset, "format_version", "0", "format version")
    _member_case(cases, asset, "output_size_bytes", "0", "output size")
    _member_case(cases, asset, "regeneration_verified", "false", "regeneration")
    cases.check()


def test_license_drift_is_refused() raises:
    var cases = Cases()
    var license: List[String] = ["production_assets", "0", "license"]
    _member_case(cases, license, "spdx", '"wrong"', "license")
    _member_case(cases, license, "source_files", "[]", "license evidence")
    _member_case(
        cases,
        license,
        "source_files",
        '["FaceXModel/jawOpen.obj"]',
        "license evidence",
    )
    _member_case(cases, license, "evidence_urls", "true", "license evidence")
    _member_case(
        cases, license, "evidence_urls", '["not a URL"]', "license evidence"
    )
    cases.check()


def test_source_evidence_drift_is_refused() raises:
    var cases = Cases()
    for name in source_names():
        var data = _load()
        var files = _get(data, ["sources", name, "files"])
        var inputs = List[Int]()
        for child in data.nodes[files].children:
            if data.string(data.get(child, "role")) == "input":
                inputs.append(child)
        data.nodes[files].children = inputs^
        cases.add(data, "license/context evidence")
        data = _load()
        files = _get(data, ["sources", name, "files"])
        var children = data.nodes[files].children.copy()
        for child in children:
            var role = data.string(data.get(child, "role"))
            if role != "input":
                _set(
                    data,
                    child,
                    "role",
                    _string(
                        data, "context" if role == "license" else "license"
                    ),
                )
                break
        cases.add(data, "license/context evidence")
    cases.check()


def test_source_binding_drift_is_refused() raises:
    var cases = Cases()
    var source: List[String] = ["sources", "ict"]
    _member_case(cases, source, "revision", '"main"', "immutable commit")
    _member_case(
        cases,
        source,
        "repository",
        '"https://example.com"',
        "repository binding",
    )
    _member_case(cases, source, "files", "[]", "Missing source files")
    cases.check()


def test_source_file_drift_is_refused() raises:
    var cases = Cases()
    var entry: List[String] = ["sources", "ict", "files", "0"]
    _member_case(cases, entry, "sha256", "null", "checksum")
    _member_case(cases, entry, "git_blob_sha1", '"bad"', "checksum")
    _member_case(cases, entry, "size_bytes", "true", "source size")
    _member_case(cases, entry, "size_bytes", "17000000", "source size")
    _member_case(cases, entry, "size_bytes", "1.0", "source size")
    _member_case(cases, entry, "role", '"executable"', "source role")
    cases.check()


def test_source_file_path_drift_is_refused() raises:
    var cases = Cases()
    var entry: List[String] = ["sources", "ict", "files", "0"]
    _member_case(cases, entry, "path", '"../outside"', "manifest path")
    _member_case(cases, entry, "path", '"/absolute"', "manifest path")
    _member_case(cases, entry, "path", '"a/./b"', "manifest path")
    var data = _load()
    var files = _get(data, ["sources", "ict", "files"])
    data.nodes[files].children.append(data.nodes[files].children[0])
    cases.add(data, "Duplicate source")
    data = _load()
    files = _get(data, ["sources", "ict", "files"])
    _ = data.nodes[files].children.pop(0)
    cases.add(data, "ICT input set")
    _member_case(
        cases,
        ["sources", "sintel", "files", "-1"],
        "path",
        '"wrong.tfx"',
        "Hair input binding",
    )
    cases.check()


def test_synthetic_drift_is_refused() raises:
    var cases = Cases()
    for field in ["format", "source"]:
        _member_case(
            cases,
            ["synthetic_regeneration", "1"],
            field,
            '"unrecognized"',
            "binding",
        )
    var first: List[String] = ["synthetic_regeneration", "0"]
    _member_case(
        cases,
        first,
        "output_sha256",
        '"' + "0" * 64 + '"',
        "regeneration mismatch",
    )
    _member_case(
        cases, first, "output_size_bytes", "1", "regeneration mismatch"
    )
    _member_case(
        cases,
        ["synthetic_regeneration", "1"],
        "decoded_input_sha256",
        '"' + "0" * 64 + '"',
        "Decoded synthetic source",
    )
    _member_case(cases, first, "parameters", '{"unknown": 1}', MALFORMED)
    cases.check()


def test_fetch_needs_explicit_cache() raises:
    with assert_raises(contains="explicit --source-cache"):
        verify(fetch_sources=True)


# --- the source cache -----------------------------------------------------------------


def _cache_manifest(content: String = "pinned source") raises -> JsonDocument:
    """Return a manifest of one pinned source file."""
    var bytes = content.as_bytes()
    return load_json(
        '{"sources": {"fixture": {"repository":'
        ' "https://github.com/USC-ICT/ICT-FaceKit", "revision": "'
        + "a" * 40
        + '", "files": [{"path": "input.obj", "role": "input", "size_bytes": '
        + String(len(bytes))
        + ', "sha256": "'
        + sha256_hex(bytes)
        + '", "git_blob_sha1": "'
        + git_blob_sha1(bytes)
        + '"}]}}}'
    )


def _shell(script: String) -> List[String]:
    """Return a download command that runs a shell script; the script gets
    the output file as $1 and the URL as $2."""
    return ["sh", "-c", script, "fetch"]


def test_cache_missing_wrong_revision_altered_and_extra_files() raises:
    var data = _cache_manifest()
    var root = mkdtemp(prefix="manifest cache ")
    var cache = root + "/cache"
    var source = cache + "/fixture/" + "a" * 40 + "/input.obj"
    var marker = root + "/fetched"
    var watch = _shell("touch '" + marker + "'; exit 1")
    with assert_raises(contains="Missing pinned source"):
        materialize_sources(data, cache, root + "/staged", False, watch)
    var wrong = cache + "/fixture/" + "b" * 40
    _ = run_program(["mkdir", "-p", wrong], 10)
    Path(wrong + "/input.obj").write_text("pinned source")
    with assert_raises(contains="Missing pinned source"):
        materialize_sources(data, cache, root + "/staged", False, watch)
    _ = run_program(["mkdir", "-p", cache + "/fixture/" + "a" * 40], 10)
    Path(source).write_text("altered bytes")
    with assert_raises(contains="checksum or size"):
        materialize_sources(data, cache, root + "/staged", True, watch)
    assert_equal(Path(source).read_text(), "altered bytes")
    Path(source).write_text("pinned source")
    Path(cache + "/fixture/" + "a" * 40 + "/extra.obj").write_text(
        "must not be consumed"
    )
    materialize_sources(data, cache, root + "/staged", False, watch)
    assert_equal(
        Path(root + "/staged/fixture/input.obj").read_text(), "pinned source"
    )
    assert_false(exists(root + "/staged/fixture/extra.obj"))
    assert_false(exists(marker))
    remove_tree(root)


def test_explicit_fetch_checks_bytes_and_uses_immutable_url() raises:
    var data = _cache_manifest()
    var root = mkdtemp(prefix="manifest fetch ")
    var path = root + "/cache/fixture/" + "a" * 40 + "/input.obj"
    var log = root + "/urls"
    with assert_raises(contains="checksum or size"):
        materialize_sources(
            data,
            root + "/cache",
            root + "/stage",
            True,
            _shell('printf wrong > "$1"'),
        )
    assert_false(exists(path))
    materialize_sources(
        data,
        root + "/cache",
        root + "/stage",
        True,
        _shell(
            "printf '%s\\n' \"$2\" >> '"
            + log
            + "'; printf 'pinned source' > \"$1\""
        ),
    )
    assert_equal(
        Path(log).read_text(),
        "https://raw.githubusercontent.com/USC-ICT/ICT-FaceKit/"
        + "a" * 40
        + "/input.obj\n",
    )
    # The cache is reused: a second run downloads nothing.
    materialize_sources(
        data, root + "/cache", root + "/stage", True, materialize[OFFLINE]()
    )
    assert_equal(Path(path).read_text(), "pinned source")
    assert_equal(
        Path(root + "/stage/fixture/input.obj").read_text(), "pinned source"
    )
    remove_tree(root)


def test_a_failed_download_is_reported() raises:
    var data = _cache_manifest()
    var root = mkdtemp(prefix="manifest offline ")
    with assert_raises(contains="Cannot download"):
        materialize_sources(
            data, root + "/cache", root + "/stage", True, materialize[OFFLINE]()
        )
    remove_tree(root)


def test_symlink_cannot_escape_cache() raises:
    var data = _cache_manifest()
    var root = mkdtemp(prefix="manifest link ")
    _ = run_program(["mkdir", "-p", root + "/cache", root + "/outside"], 10)
    _ = run_program(
        ["ln", "-s", root + "/outside", root + "/cache/fixture"], 10
    )
    assert_equal(
        resolve(root + "/cache/fixture/x/../y"),
        resolve(root + "/outside") + "/y",
    )
    with assert_raises(contains="escapes cache"):
        materialize_sources(
            data, root + "/cache", root + "/stage", True, materialize[OFFLINE]()
        )
    remove_tree(root)


def test_production_match_and_mismatch_never_replace_accepted_outputs() raises:
    var root = mkdtemp(prefix="manifest production ")
    var accepted = root + "/assets/hair/layered.bin"
    _ = run_program(
        [
            "mkdir",
            "-p",
            root + "/assets/hair",
            root + "/source/sintel",
            root + "/source/ict",
            root + "/scratch",
        ],
        10,
    )
    Path(accepted).write_text("accepted")
    Path(root + "/source/sintel/input.tfx").write_bytes(
        Span(
            from_hex(
                Path("assets/converted-fixtures/layered.tfx.hex").read_text()
            )
        )
    )
    _ = run_program(
        [
            "cp",
            "-R",
            "assets/converted-fixtures/face",
            root + "/source/ict/face",
        ],
        10,
    )
    var text = (
        '{"production_assets": [{"path": "assets/hair/layered.bin",'
        ' "source": {"id": "sintel", "input": "input.tfx"},'
        ' "parameters": {"style": "layered"}, "output_size_bytes": 3692},'
        ' {"path": "assets/face/ict_face.bin",'
        ' "source": {"id": "ict", "input": "face"},'
        ' "parameters": {"identities": 1, "skin_end": 5, "coarse_target": 2},'
        ' "output_size_bytes": 448}],'
        ' "files": {"assets/hair/layered.bin": "LAYERED",'
        ' "assets/face/ict_face.bin":'
        ' "d1a743cf3e984de1b6c02878271baa071e0bcd8314faaf659a12e52132bd5b65"}}'
    )
    var layered = (
        "148f5275cf1ffa80d17ef66412ad1bbf39995c53ab01779d32d87a613637f00e"
    )
    regenerate_production(
        load_json(text.replace("LAYERED", layered)),
        root + "/source",
        root + "/scratch",
    )
    with assert_raises(
        contains="Production regeneration mismatch: assets/hair/layered.bin"
    ):
        regenerate_production(
            load_json(text.replace("LAYERED", "0" * 64)),
            root + "/source",
            root + "/scratch",
        )
    assert_equal(Path(accepted).read_text(), "accepted")
    remove_tree(root)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
