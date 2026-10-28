# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md

"""Check the render-actor reuse record and bound files.

    carla_render_actor_gate --migration PATH
    carla_render_actor_gate --bytes PATH --sha HEX [--token HEX] --label TEXT
    carla_render_actor_gate --bytes-all DIR
    carla_render_actor_gate --checked-edges DIR

The program checks the bytes it is given. It does not read the repository
and it does not restore a historical source. The caller does that first.
A directory checks every listed file in order.
"""

from std.pathlib import Path
from std.sys import argv, exit, stderr

from tests._python_tokens import token_sha256
from tools._merged_edge import merged_edges
from tools._python_json import (
    MISSING,
    PY_DICT,
    PY_INT,
    PY_LIST,
    PY_STR,
    PyJson,
    py_equal,
)
from tools._sha256 import sha256_hex


comptime _MIGRATION_SHA256 = (
    "c4d146fe145289a1ad443956d2941d1e90186d448b8056f8be97d72f4f672771"
)
comptime _MODULE = "extensions/carla/render_actors.mojo"


def _fail(message: String) raises:
    """Raise one render-actor failure.

    Args:
        message: The reason, without the prefix.

    Raises:
        Error: Always.
    """
    raise Error("reviewed render actor reuse successor: " + message)


def _test_name(index: Int) -> String:
    """Return one bound test path.

    Args:
        index: The path position, from 0 through 2.

    Returns:
        The repository path.
    """
    if index == 0:
        return "tests/test_carla_render_reuse.mojo"
    if index == 1:
        return "tests/test_carla_model_cache.mojo"
    return "tests/test_carla_walker_render_motion.mojo"


def _keys_match(doc: PyJson, node: Int, count: Int, tests: Bool) -> Bool:
    """Return whether an object has one reviewed key set.

    Args:
        doc: The record.
        node: The object, or `MISSING`.
        count: The number of reviewed keys.
        tests: True for the bound tests, false for the module edge.

    Returns:
        True when the keys are exactly that set.
    """
    if (
        node == MISSING
        or doc.kind(node) != PY_DICT
        or doc.length(node) != count
    ):
        return False
    var index = 0
    while index < count:
        var name = _test_name(index) if tests else _MODULE
        if doc.get(node, name) == MISSING:
            return False
        index += 1
    return True


def _require_edge(doc: PyJson, edge: Int) raises:
    """Require the four edge digests and a real change.

    Args:
        doc: The record.
        edge: The edge object.

    Raises:
        Error: The edge is malformed.
    """
    var before = doc.get(edge, "before_sha256")
    var after = doc.get(edge, "after_sha256")
    var before_token = doc.get(edge, "before_token_sha256")
    var after_token = doc.get(edge, "after_token_sha256")
    if (
        doc.length(edge) != 4
        or before == MISSING
        or after == MISSING
        or before_token == MISSING
        or after_token == MISSING
        or doc.kind(before) != PY_STR
        or doc.kind(after) != PY_STR
        or doc.text(before) == doc.text(after)
    ):
        _fail("malformed edge: " + _MODULE)


def render_actor_record(migration: Span[UInt8, _]) raises:
    """Require the render-actor reuse record.

    Args:
        migration: The successor record bytes.

    Raises:
        Error: The record scope, tests, or edge changed.
    """
    if sha256_hex(migration) != _MIGRATION_SHA256:
        _fail("unreviewed exact edge")
    var doc = PyJson.parse(String(from_utf8_lossy=migration))
    var schema = doc.get(doc.root, "schema")
    var issue = doc.get(doc.root, "issue")
    var three = PyJson.parse("306")
    if (
        schema == MISSING
        or doc.kind(schema) != PY_INT
        or doc.text(schema) != "1"
        or issue == MISSING
        or not py_equal(doc, issue, three, three.root)
        or not _keys_match(doc, doc.get(doc.root, "edges"), 1, False)
    ):
        _fail("unexpected successor scope")
    if not _keys_match(doc, doc.get(doc.root, "correctness_tests"), 3, True):
        _fail("unexpected correctness test set")
    var edges = doc.get(doc.root, "edges")
    var edge = doc.get(edges, _MODULE)
    if edge == MISSING or doc.kind(edge) != PY_DICT:
        _fail("malformed edge: " + _MODULE)
    _require_edge(doc, edge)


def render_actor_bytes(
    payload: Span[UInt8, _],
    expected_sha: String,
    expected_token: String,
    label: String,
) raises:
    """Require one file digest, and its token digest when given.

    Args:
        payload: The file bytes.
        expected_sha: The required SHA-256 hex digest.
        expected_token: The required token digest. Empty skips that check.
        label: The failure reason, without the prefix.

    Raises:
        Error: A digest changed, or the source cannot be tokenized.
    """
    if sha256_hex(payload) != expected_sha:
        _fail(label)
    if expected_token.byte_length() == 0:
        return
    var text = String(from_utf8_lossy=payload)
    if token_sha256(text) != expected_token:
        _fail(label)


def render_actor_bytes_all(directory: String) raises:
    """Require each listed file digest, in order.

    Args:
        directory: A directory with `labels.json` and one file per item.
            Each item has `name`, `sha`, and `label`. `token` is optional.

    Raises:
        Error: A digest changed, a listed file is absent, or the list is
            not a JSON list.
    """
    var doc = PyJson.parse(Path(directory + "/labels.json").read_text())
    if doc.kind(doc.root) != PY_LIST:
        _fail("malformed byte list")
    var index = 0
    var count = doc.length(doc.root)
    while index < count:
        var item = doc.item(doc.root, index)
        var token_node = doc.get(item, "token")
        var token = String("")
        if token_node != MISSING:
            token = doc.text(token_node)
        render_actor_bytes(
            Path(directory + "/" + doc.text(doc.at(item, "name"))).read_bytes(),
            doc.text(doc.at(item, "sha")),
            token,
            doc.text(doc.at(item, "label")),
        )
        index += 1


def render_actor_checked_edges(directory: String) raises -> String:
    """Check every file digest, then write each path on its edge.

    Args:
        directory: A directory with `labels.json` and one file per item.
            Each item has `name`, `sha`, `label`, `path`, and `edge`.
            `token` is optional.

    Returns:
        The edges with each path written first, in the same order.

    Raises:
        Error: A digest changed, or an edge cannot be read.
    """
    render_actor_bytes_all(directory)
    return merged_edges(Path(directory + "/labels.json").read_text())


def render_actor_paths() raises -> String:
    """Return the render-actor module and its bound tests.

    Returns:
        JSON with `modules` and `tests` in reviewed order.

    Raises:
        Error: The lists cannot be written.
    """
    var doc = PyJson()
    var spec = doc.new_dict()
    var modules = doc.new_list()
    doc.append(modules, doc.new_str(_MODULE))
    doc.set(spec, "modules", modules)
    var tests = doc.new_list()
    var index = 0
    while index < 3:
        doc.append(tests, doc.new_str(_test_name(index)))
        index += 1
    doc.set(spec, "tests", tests)
    doc.root = spec
    return doc.dumps()


def _usage():
    """Print the command usage and stop."""
    print(
        (
            "usage: carla_render_actor_gate --migration PATH"
            " | --bytes PATH --sha HEX [--token HEX] --label TEXT"
            " | --bytes-all DIR | --checked-edges DIR"
        ),
        file=stderr,
    )
    exit(2)


def main() raises:
    """Check a render-actor record or its files and print nothing on success.

    Raises:
        Error: The command is invalid.
    """
    var migration = String("")
    var payload = String("")
    var digest = String("")
    var token = String("")
    var label = String("")
    var bytes_all = String("")
    var checked_edges = String("")
    var arguments = argv()
    var index = 1
    while index < len(arguments):
        var word = arguments[index]
        if (
            word == "--migration"
            or word == "--bytes"
            or word == "--sha"
            or word == "--token"
            or word == "--label"
            or word == "--bytes-all"
            or word == "--checked-edges"
        ):
            if index + 1 >= len(arguments):
                _usage()
            var value = arguments[index + 1]
            if word == "--migration":
                migration = value
            elif word == "--bytes":
                payload = value
            elif word == "--sha":
                digest = value
            elif word == "--token":
                token = value
            elif word == "--label":
                label = value
            elif word == "--bytes-all":
                bytes_all = value
            else:
                checked_edges = value
            index += 2
            continue
        _usage()
    var modes = 0
    if migration.byte_length() > 0:
        modes += 1
    if payload.byte_length() > 0:
        modes += 1
    if bytes_all.byte_length() > 0:
        modes += 1
    if checked_edges.byte_length() > 0:
        modes += 1
    if modes != 1:
        _usage()
    if payload.byte_length() > 0 and (
        digest.byte_length() == 0 or label.byte_length() == 0
    ):
        _usage()
    try:
        if migration.byte_length() > 0:
            render_actor_record(Path(migration).read_bytes())
        elif checked_edges.byte_length() > 0:
            print(render_actor_checked_edges(checked_edges), end="")
        elif bytes_all.byte_length() > 0:
            render_actor_bytes_all(bytes_all)
        else:
            render_actor_bytes(Path(payload).read_bytes(), digest, token, label)
    except error:
        print(String(error), file=stderr)
        exit(1)
