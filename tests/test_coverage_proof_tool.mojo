# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""A capture proof check matches the Python receipt check."""

from std.os import makedirs
from std.os.path import realpath
from std.pathlib import Path
from std.tempfile import mkdtemp
from std.testing import TestSuite, assert_equal, assert_true

from tests._tree import tool_mojo
from tools._process import run_program


def _text(path: String) raises -> String:
    """Return a file as text."""
    return String(from_utf8_lossy=Path(path).read_bytes())


def _same(left: String, right: String) raises:
    """Raise at the first different byte."""
    if left == right:
        return
    var left_bytes = left.as_bytes()
    var right_bytes = right.as_bytes()
    var limit = len(left_bytes)
    if len(right_bytes) < limit:
        limit = len(right_bytes)
    var index = 0
    while index < limit and left_bytes[index] == right_bytes[index]:
        index += 1
    var left_end = index + 120
    if left_end > len(left_bytes):
        left_end = len(left_bytes)
    var right_end = index + 120
    if right_end > len(right_bytes):
        right_end = len(right_bytes)
    raise Error(
        "proof mismatch at "
        + String(index)
        + "\n"
        + String(left[byte=index:left_end])
        + "\n---\n"
        + String(right[byte=index:right_end])
    )


def _cleanup(path: String) raises:
    """Remove a temporary tree."""
    _ = run_program(["rm", "-rf", path], 10)


def _oracle() -> String:
    """Return the Python script that seals a small receipt."""
    return (
        "import sys\nfrom pathlib import Path\nsys.path.insert(0,"
        " sys.argv[1])\nimport coverage_io\nimport coverage_loop_proofs as"
        " loops\nroot = Path(sys.argv[2]).resolve()\nbuild ="
        " Path(sys.argv[3]).resolve()\ndriver ="
        " Path(sys.argv[4]).resolve()\nout = Path(sys.argv[5])\nerr ="
        " Path(sys.argv[6])\nroot_inputs = loops.maintained_inputs(root,"
        " exclude=build)\nstaged = loops.maintained_inputs(build,"
        " staged=True)\ninputs = {}\nfor name, digest in staged.items():\n   "
        " inputs[name] = {'source': root_inputs.get(name, digest),"
        " 'instrumented': digest}\nmanifest = (build /"
        " 'manifest.txt').read_bytes()\ngeneration = {\n    'index_sha256':"
        " loops.file_sha256(build / 'origins.ready'),\n    'checkpoint_sha256':"
        " loops.file_sha256(build / 'generation-inputs.json'),\n    'modules':"
        " {},\n}\ncontract = loops.execution_contract(\n    root, build,"
        " inputs, mojo=[str(driver)],\n   "
        " suites=['tests/test_fixture.mojo'])\nreceipt = {\n    'schema':"
        " 'constant-loops-v2', 'python': __import__('sys').version,\n   "
        " 'compiler': 'Mojo fixture', 'flags': '-I .',\n    'manifest_sha256':"
        " loops.sha256(manifest),\n    'root_inputs': root_inputs, 'inputs':"
        " inputs,\n    'generation': generation, 'execution':"
        " contract,\n}\nenvelope = {'receipt': receipt,\n            'sha256':"
        " loops.sha256(loops.canonical(receipt))}\n(build /"
        " 'loop-proofs.json').write_bytes(loops.canonical(envelope) +"
        " b'\\n')\nexpected = loops.expected_capture_command(\n    contract,"
        " 'tests/test_fixture.mojo', 'raw')\ncommand ="
        " [loops._expand_path(word, root, build) for word in"
        " expected]\ncoverage_io.preflight(command, out, err, build /"
        " 'loop-proofs.json', root)\ncoverage_io.bind_finished(command, out,"
        " err, build / 'loop-proofs.json', root)\n(build.parent.parent /"
        " 'python-bind.json').write_bytes(\n    (err.with_name(err.name +"
        " '.proof.json')).read_bytes())\n(err.with_name(err.name +"
        " '.proof.json')).unlink()\n(build /"
        " 'command.txt').write_text('\\n'.join(command) + '\\n')\n"
    )


def _tree(parent: String) raises -> String:
    """Copy the proof tools into a small repository."""
    var root = parent + "/repo"
    var build = root + "/stage"
    makedirs(root + "/tools", exist_ok=True)
    makedirs(build + "/tests", exist_ok=True)
    var repo = realpath(".")
    for name in [
        "coverage_loop_proofs.py",
        "cache_key.py",
        "coverage_toolchain_identity.py",
        "coverage_io.py",
        "tool.sh",
    ]:
        Path(root + "/tools/" + name).write_text(_text(repo + "/tools/" + name))
    Path(root + "/Makefile").write_text("all:\n")
    Path(root + "/driver").write_text("compiler\n")
    Path(build + "/tests/test_fixture.mojo").write_text(
        "def main():\n    pass\n"
    )
    Path(build + "/manifest.txt").write_text("L tests/test_fixture 1\n")
    Path(build + "/origins.ready").write_text("")
    Path(build + "/generation-inputs.json").write_text("{}\n")
    Path(build + "/test_fixture.out").write_text("hello\n")
    Path(build + "/test_fixture.txt.gz").write_text("probes\n")
    return root


def _command(path: String) raises -> List[String]:
    """Read one command word from each line."""
    var words = List[String]()
    var text = _text(path)
    var start = 0
    var data = text.as_bytes()
    for index in range(len(data)):
        if data[index] == 10:
            if index > start:
                words.append(String(text[byte=start:index]))
            start = index + 1
    return words^


def _mojo(
    mode: String, root: String, build: String, command: List[String]
) raises -> Int:
    """Run one proof mode."""
    var arguments = List[String]()
    arguments.append("sh")
    arguments.append("tools/tool.sh")
    arguments.append(tool_mojo())
    arguments.append("coverage_io")
    arguments.append(mode)
    arguments.append("--out")
    arguments.append(build + "/test_fixture.out")
    arguments.append("--err")
    arguments.append(build + "/test_fixture.txt.gz")
    arguments.append("--loop-proof")
    arguments.append(build + "/loop-proofs.json")
    arguments.append("--loop-proof-root")
    arguments.append(root)
    arguments.append("--")
    for word in command:
        arguments.append(word)
    var ran = run_program(arguments, 30.0, merge_errors=False)
    if ran.status != 0:
        raise Error(ran.errors + ran.output)
    return ran.status


def test_proof_check_matches_python() raises:
    var parent = mkdtemp(prefix="coverage-proof-")
    try:
        var root = _tree(parent)
        var build = root + "/stage"
        var script = parent + "/oracle.py"
        Path(script).write_text(_oracle())
        var sealed = run_program(
            [
                "python3",
                script,
                realpath("tools"),
                root,
                build,
                root + "/driver",
                build + "/test_fixture.out",
                build + "/test_fixture.txt.gz",
            ],
            30.0,
            merge_errors=False,
        )
        if sealed.status != 0:
            raise Error(sealed.errors + sealed.output)
        var command = _command(build + "/command.txt")
        assert_equal(
            _mojo("preflight", root, build, command),
            0,
        )
        assert_equal(_mojo("bind", root, build, command), 0)
        _same(
            _text(parent + "/python-bind.json"),
            _text(build + "/test_fixture.txt.gz.proof.json"),
        )
    finally:
        _cleanup(parent)


def test_a_changed_command_is_refused() raises:
    var parent = mkdtemp(prefix="coverage-proof-")
    try:
        var root = _tree(parent)
        var build = root + "/stage"
        var script = parent + "/oracle.py"
        Path(script).write_text(_oracle())
        var sealed = run_program(
            [
                "python3",
                script,
                realpath("tools"),
                root,
                build,
                root + "/driver",
                build + "/test_fixture.out",
                build + "/test_fixture.txt.gz",
            ],
            30.0,
            merge_errors=False,
        )
        if sealed.status != 0:
            raise Error(sealed.errors + sealed.output)
        var command = _command(build + "/command.txt")
        command.append("extra")
        var arguments = List[String]()
        arguments.append("sh")
        arguments.append("tools/tool.sh")
        arguments.append(tool_mojo())
        arguments.append("coverage_io")
        arguments.append("preflight")
        arguments.append("--out")
        arguments.append(build + "/test_fixture.out")
        arguments.append("--err")
        arguments.append(build + "/test_fixture.txt.gz")
        arguments.append("--loop-proof")
        arguments.append(build + "/loop-proofs.json")
        arguments.append("--loop-proof-root")
        arguments.append(root)
        arguments.append("--")
        for word in command:
            arguments.append(word)
        var ran = run_program(arguments, 30.0, merge_errors=False)
        assert_equal(ran.status, 1)
        assert_true(
            ran.errors.find(
                "Capture command differs from its sealed execution contract"
            )
            >= 0
        )
    finally:
        _cleanup(parent)


def test_duplicate_receipt_key_is_refused() raises:
    var parent = mkdtemp(prefix="coverage-proof-")
    try:
        var root = parent + "/repo"
        makedirs(root, exist_ok=True)
        Path(root + "/stage").write_text("")
        var proof = root + "/loop-proofs.json"
        Path(proof).write_text(
            '{"receipt":{"schema":"constant-loops-v2"},"receipt":{}}\n'
        )
        var ran = run_program(
            [
                "sh",
                "tools/tool.sh",
                tool_mojo(),
                "coverage_io",
                "preflight",
                "--out",
                root + "/test_fixture.out",
                "--err",
                root + "/test_fixture.txt.gz",
                "--loop-proof",
                proof,
                "--loop-proof-root",
                root,
                "--",
                "true",
            ],
            20.0,
            merge_errors=False,
        )
        assert_equal(ran.status, 1)
        assert_true(ran.errors.find("Duplicate receipt key: receipt") >= 0)
    finally:
        _cleanup(parent)


def main() raises:
    """Build the capture tool, then run the tests."""
    var built = run_program(
        ["sh", "tools/tool.sh", tool_mojo(), "--build", "coverage_io"],
        120.0,
    )
    if built.status != 0:
        raise Error(built.output + built.errors)
    TestSuite.discover_tests[__functions_in_module()]().run()
