# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md

"""An unstaged capture suite is refused before the compiler is bound."""

from std.ffi import c_int, external_call
from std.os import makedirs
from std.pathlib import Path
from std.tempfile import mkdtemp
from std.testing import TestSuite, assert_equal, assert_raises

from tools._python_json import PyJson
from tools._sha256 import sha256_hex
from tools.coverage_execution import (
    _expand,
    check_capture_inputs,
    execution_contract,
    validate_capture_command,
)


def test_an_unstaged_suite_is_refused() raises:
    """A suite that is not in the staged inputs is refused."""
    with assert_raises(contains="Capture suite inventory is invalid or not staged"):
        _ = execution_contract(
            '{"inputs":["mod.mojo"],"suites":["tests/test_missing.mojo"],'
            + '"mojo":"mojo","python":"/usr/bin/python3"}',
            "/tmp",
            "/tmp/build",
        )


def test_a_command_without_a_suite_is_refused() raises:
    """A command that does not name `--suite` is refused."""
    with assert_raises(contains="Capture command does not identify a staged suite"):
        _ = validate_capture_command(
            '{"execution":{"suites":[],"profiles":["raw"],"compiler":[],'
            + '"cache":"x","cc":"cc"},"command":["sh"]}',
            "/tmp",
            "/tmp/build",
        )


def test_root_and_build_tokens_expand() raises:
    """A sealed root or build token becomes the directory on this machine."""
    assert_equal(_expand("@ROOT@", "/r", "/r/stage"), "/r")
    assert_equal(_expand("@BUILD@", "/r", "/r/stage"), "/r/stage")
    assert_equal(_expand("@ROOT@/cc", "/r", "/r/stage"), "/r/cc")
    assert_equal(_expand("@BUILD@/cc", "/r", "/r/stage"), "/r/stage/cc")
    assert_equal(_expand("literal", "/r", "/r/stage"), "literal")


def _hash(path: String) raises -> String:
    """Return the SHA-256 of `path`."""
    return sha256_hex(Span(Path(path).read_bytes()))


def _chmod(path: String, mode: UInt32) raises:
    """Set the permission bits of `path`."""
    var text = path
    if external_call["chmod", c_int](text.as_c_string_span().ptr(), mode) != 0:
        raise Error("chmod failed")


def _symlink(target: String, path: String) raises:
    """Point `path` at `target`."""
    var left = target
    var right = path
    if external_call["symlink", c_int](
        left.as_c_string_span().ptr(), right.as_c_string_span().ptr()
    ) != 0:
        raise Error("symlink failed")


def _put(path: String, text: String) raises:
    """Write `text` to `path`, creating its parent."""
    var slash = path.rfind("/")
    if slash > 0:
        makedirs(String(path[byte=:slash]), exist_ok=True)
    Path(path).write_text(text)


def _prepare() raises -> Tuple[String, String, String, String]:
    """Return a root, build, locked directory, and a matching request."""
    var parent = mkdtemp(prefix="coverage-inputs-")
    var root = parent + "/root"
    var build = root + "/stage"
    var outside = parent + "/outside"
    makedirs(root, exist_ok=True)
    makedirs(build, exist_ok=True)
    _put(root + "/module.mojo", "fn main():\n    pass\n")
    _put(root + "/tests/test_a.mojo", "fn test():\n    pass\n")
    _put(root + "/tools/coverage_loop_proofs.py", "proof\n")
    _put(root + "/tools/cache_key.py", "key\n")
    _put(root + "/tools/coverage_toolchain_identity.py", "tool\n")
    _put(root + "/cc", "compiler\n")
    _put(root + "/python-bin", "python\n")
    _put(build + "/module.mojo", "staged\n")
    _put(build + "/tests/test_a.mojo", "staged test\n")
    _put(build + "/helper", "helper\n")
    _put(build + "/manifest.txt", "L module 1\n")
    _put(build + "/origins.ready", "ready\n")
    _put(build + "/generation-inputs.json", "{}\n")
    _put(build + "/loop-proofs.json", "{}\n")
    _put(build + "/hits/skip.mojo", "skip\n")
    _put(build + "/module.mojo.cov-origin", "origin\n")
    _put(build + "/nested/other.mojo.cov-origin", "origin-two\n")
    _put(outside + "/hidden.cov-origin", "hidden\n")
    _symlink(outside, build + "/linked")
    _put(build + "/locked/extra.cov-origin", "extra\n")
    _chmod(build + "/locked", 0)
    var compiler = root + "/cc"
    var mojo = compiler + " 'a b' '' 'a'\"'\"'b'"
    var request_doc = PyJson()
    var body = request_doc.new_dict()
    request_doc.root = body
    var inputs = request_doc.new_list()
    request_doc.append(inputs, request_doc.new_str("module.mojo"))
    request_doc.append(inputs, request_doc.new_str("tests/test_a.mojo"))
    request_doc.set(body, "inputs", inputs)
    request_doc.set(body, "mojo", request_doc.new_str(mojo))
    request_doc.set(body, "python", request_doc.new_str(root + "/python-bin"))
    var suites = request_doc.new_list()
    request_doc.append(suites, request_doc.new_str("tests/test_a.mojo"))
    request_doc.set(body, "suites", suites)
    request_doc.set(body, "cache", request_doc.new_str(build))
    var contract = execution_contract(request_doc.dumps(), root, build)
    var execution = PyJson.parse(contract)
    var receipt = PyJson()
    var receipt_node = receipt.new_dict()
    receipt.root = receipt_node
    var root_inputs = receipt.new_dict()
    var names = [
        "module.mojo",
        "tests/test_a.mojo",
        "tools/coverage_loop_proofs.py",
        "tools/cache_key.py",
        "tools/coverage_toolchain_identity.py",
    ]
    for name in names:
        receipt.set(root_inputs, name, receipt.new_str(_hash(root + "/" + name)))
    receipt.set(receipt_node, "root_inputs", root_inputs)
    var staged = receipt.new_dict()
    var staged_names = ["module.mojo", "tests/test_a.mojo"]
    for name in staged_names:
        var item = receipt.new_dict()
        receipt.set(item, "instrumented", receipt.new_str(_hash(build + "/" + name)))
        receipt.set(staged, name, item)
    receipt.set(receipt_node, "inputs", staged)
    receipt.set(
        receipt_node, "manifest_sha256", receipt.new_str(_hash(build + "/manifest.txt"))
    )
    var generation = receipt.new_dict()
    receipt.set(
        generation, "index_sha256", receipt.new_str(_hash(build + "/origins.ready"))
    )
    receipt.set(
        generation,
        "checkpoint_sha256",
        receipt.new_str(_hash(build + "/generation-inputs.json")),
    )
    var modules = receipt.new_dict()
    var origin_module = receipt.new_dict()
    receipt.set(
        origin_module,
        "origin_sha256",
        receipt.new_str(_hash(build + "/module.mojo.cov-origin")),
    )
    receipt.set(modules, "module.mojo", origin_module)
    var nested = receipt.new_dict()
    receipt.set(
        nested,
        "origin_sha256",
        receipt.new_str(_hash(build + "/nested/other.mojo.cov-origin")),
    )
    receipt.set(modules, "nested/other.mojo", nested)
    receipt.set(generation, "modules", modules)
    receipt.set(receipt_node, "generation", generation)
    receipt.set(receipt_node, "execution", receipt.adopt(execution, execution.root))
    receipt.set(receipt_node, "python", receipt.new_str("fixture-version"))
    var outer = PyJson()
    var outer_node = outer.new_dict()
    outer.root = outer_node
    outer.set(outer_node, "receipt", outer.adopt(receipt, receipt.root))
    var active = outer.new_dict()
    outer.set(
        active,
        "tools/coverage_loop_proofs.py",
        outer.new_str(_hash(root + "/tools/coverage_loop_proofs.py")),
    )
    outer.set(
        active,
        "tools/cache_key.py",
        outer.new_str(_hash(root + "/tools/cache_key.py")),
    )
    outer.set(
        active,
        "tools/coverage_toolchain_identity.py",
        outer.new_str(_hash(root + "/tools/coverage_toolchain_identity.py")),
    )
    outer.set(outer_node, "active", active)
    outer.set(outer_node, "python", outer.new_str("fixture-version"))
    outer.set(outer_node, "interpreter", outer.new_str(root + "/python-bin"))
    return (root, build, build + "/locked", outer.dumps())


def _release(locked: String):
    """Restore a directory the fixture made unreadable."""
    try:
        _chmod(locked, 0o755)
    except:
        pass


def test_a_matching_capture_tree_is_accepted() raises:
    """Sealed inputs, origins, and the compiler identity match the tree."""
    var prepared = _prepare()
    var root = prepared[0]
    var build = prepared[1]
    var locked = prepared[2]
    var request = prepared[3]
    try:
        check_capture_inputs(request, root, build)
    finally:
        _release(locked)


def test_a_changed_input_byte_is_refused() raises:
    """A changed source or staged file is a stale binding."""
    var prepared = _prepare()
    var root = prepared[0]
    var build = prepared[1]
    var locked = prepared[2]
    var request = prepared[3]
    try:
        Path(root + "/module.mojo").write_text("changed\n")
        with assert_raises(contains="Stale or modified capture input binding"):
            check_capture_inputs(request, root, build)
        Path(root + "/module.mojo").write_text("fn main():\n    pass\n")
        Path(build + "/module.mojo").write_text("changed staged\n")
        with assert_raises(contains="Stale or modified capture input binding"):
            check_capture_inputs(request, root, build)
    finally:
        _release(locked)


def test_a_changed_manifest_ready_or_checkpoint_is_refused() raises:
    """Each sealed generation file is part of the input binding."""
    var prepared = _prepare()
    var root = prepared[0]
    var build = prepared[1]
    var locked = prepared[2]
    var request = prepared[3]
    try:
        var manifest = Path(build + "/manifest.txt").read_text()
        Path(build + "/manifest.txt").write_text("changed\n")
        with assert_raises(contains="Stale or modified capture input binding"):
            check_capture_inputs(request, root, build)
        Path(build + "/manifest.txt").write_text(manifest)
        var ready = Path(build + "/origins.ready").read_text()
        Path(build + "/origins.ready").write_text("changed\n")
        with assert_raises(contains="Stale or modified capture input binding"):
            check_capture_inputs(request, root, build)
        Path(build + "/origins.ready").write_text(ready)
        Path(build + "/generation-inputs.json").write_text("changed\n")
        with assert_raises(contains="Stale or modified capture input binding"):
            check_capture_inputs(request, root, build)
    finally:
        _release(locked)


def test_a_changed_origin_is_refused() raises:
    """A changed `.cov-origin` file is refused after the input binding."""
    var prepared = _prepare()
    var root = prepared[0]
    var build = prepared[1]
    var locked = prepared[2]
    var request = prepared[3]
    try:
        Path(build + "/module.mojo.cov-origin").write_text("changed\n")
        with assert_raises(contains="Stale or modified capture generation origins"):
            check_capture_inputs(request, root, build)
    finally:
        _release(locked)


def test_a_changed_verifier_or_compiler_is_refused() raises:
    """The executing tool hash and the compiler identity are sealed."""
    var prepared = _prepare()
    var root = prepared[0]
    var build = prepared[1]
    var locked = prepared[2]
    var request = prepared[3]
    try:
        var doc = PyJson.parse(request)
        var active = doc.at(doc.root, "active")
        doc.set(
            active,
            "tools/cache_key.py",
            doc.new_str("0" * 64),
        )
        with assert_raises(contains="Stale or modified executing capture verifier"):
            check_capture_inputs(doc.dumps(), root, build)
        doc = PyJson.parse(request)
        doc.set(doc.root, "python", doc.new_str("other-version"))
        with assert_raises(contains="Stale or modified capture compiler/execution identity"):
            check_capture_inputs(doc.dumps(), root, build)
        Path(root + "/cc").write_text("changed compiler\n")
        with assert_raises(contains="Stale or modified capture compiler/execution identity"):
            check_capture_inputs(request, root, build)
    finally:
        _release(locked)


def test_a_missing_manifest_names_the_file() raises:
    """A missing sealed file is reported before the binding comparison."""
    var prepared = _prepare()
    var root = prepared[0]
    var build = prepared[1]
    var locked = prepared[2]
    var request = prepared[3]
    try:
        _chmod(build + "/manifest.txt", 0o644)
        var removed = build + "/manifest.txt"
        if external_call["unlink", c_int](removed.as_c_string_span().ptr()) != 0:
            raise Error("unlink failed")
        with assert_raises(contains="missing input file: " + removed):
            check_capture_inputs(request, root, build)
    finally:
        _release(locked)


def test_an_invalid_or_escaped_source_is_refused() raises:
    """A colon in a source name, or a link out of the root, is refused."""
    var parent = mkdtemp(prefix="coverage-inputs-bad-")
    var root = parent + "/root"
    _put(root + "/weird:name.mojo", "fn main():\n    pass\n")
    with assert_raises(contains="Invalid coverage source identity"):
        check_capture_inputs('{"receipt":{}}', root, parent + "/stage")
    var escaped = parent + "/escaped"
    _put(escaped + "/module.mojo", "fn main():\n    pass\n")
    _put(parent + "/outside.mojo", "outside\n")
    _symlink(parent + "/outside.mojo", escaped + "/link.mojo")
    with assert_raises(contains="Missing or escaped coverage source: link.mojo"):
        check_capture_inputs('{"receipt":{}}', escaped, parent + "/stage")


def main() raises:
    """Run the execution contract tests."""
    TestSuite.discover_tests[__functions_in_module()]().run()
