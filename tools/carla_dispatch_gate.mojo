# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md

"""Check the curve support and dispatch migration record.

    carla_dispatch_gate --migration PATH
    carla_dispatch_gate --bytes PATH --sha HEX --label TEXT
    carla_dispatch_gate --tokens DIR
    carla_dispatch_gate --declaration-tokens PATH
    carla_dispatch_gate --edge HEX --expected HEX
    carla_dispatch_gate --graphs DIR
    carla_dispatch_gate --source-graphs PATH
    carla_dispatch_gate --pins DIR

The program checks the bytes it is given. It does not read the repository
and it does not restore a historical source. The caller does that first.
A pin directory checks every listed file in order.
"""

from std.pathlib import Path
from std.sys import argv, exit, stderr

from tests._python_tokens import significant_graph_pairs, token_sha256
from tools._lane_declarations import declaration_token_checks
from tools._python_json import MISSING, PY_DICT, PY_LIST, PyJson, py_equal
from tools._sha256 import sha256_hex


comptime _MIGRATION_SHA256 = (
    "1a6d7794bf0869a1e717685e556d8400e075ab97917ce8d855da6bd61c3ee19f"
)


def _fail(message: String) raises:
    """Raise one support/dispatch failure.

    Args:
        message: The reason, without the prefix.

    Raises:
        Error: Always.
    """
    raise Error("curve support/dispatch contract: " + message)


def _source_name(index: Int) -> String:
    """Return one reviewed source path.

    Args:
        index: The path position, 0 or 1.

    Returns:
        The repository path.
    """
    if index == 0:
        return "extensions/carla/curve_minimizer_support.mojo"
    return "extensions/carla/curve_sample_dispatch.mojo"


def _sources_match(doc: PyJson, node: Int) -> Bool:
    """Return whether the source keys are the reviewed set.

    Args:
        doc: The record.
        node: The sources object.

    Returns:
        True when the keys are exactly the two reviewed paths.
    """
    if node == MISSING or doc.kind(node) != PY_DICT or doc.length(node) != 2:
        return False
    var index = 0
    while index < 2:
        if doc.get(node, _source_name(index)) == MISSING:
            return False
        index += 1
    return True


def dispatch_record(migration: Span[UInt8, _]) raises:
    """Require the support and dispatch migration.

    Args:
        migration: The successor record bytes.

    Raises:
        Error: The digest, the schema, or the source set changed.
    """
    if sha256_hex(migration) != _MIGRATION_SHA256:
        _fail("unreviewed migration record")
    var doc = PyJson.parse(String(from_utf8_lossy=migration))
    var schema = doc.get(doc.root, "schema")
    var one = PyJson.parse("1")
    if schema == MISSING or not py_equal(doc, schema, one, one.root):
        _fail("wrong successor schema or source set")
    if not _sources_match(doc, doc.get(doc.root, "sources")):
        _fail("wrong successor schema or source set")


def dispatch_pin(
    payload: Span[UInt8, _], expected: String, label: String
) raises:
    """Require one historical pin digest.

    Args:
        payload: The pin file bytes.
        expected: The required SHA-256 hex digest.
        label: The repository path, used in the failure text.

    Raises:
        Error: The digest changed.
    """
    if sha256_hex(payload) != expected:
        _fail("standalone historical pin input changed: " + label)


def dispatch_pins(directory: String) raises:
    """Require each listed pin digest, in order.

    Args:
        directory: A directory with `labels.json` and one file per item.
            Each item has `name`, `sha`, and `label`.

    Raises:
        Error: A digest changed, a listed file is absent, or the list is
            not a JSON list.
    """
    var doc = PyJson.parse(Path(directory + "/labels.json").read_text())
    if doc.kind(doc.root) != PY_LIST:
        _fail("malformed pin list")
    var index = 0
    var count = doc.length(doc.root)
    while index < count:
        var item = doc.item(doc.root, index)
        dispatch_pin(
            Path(directory + "/" + doc.text(doc.at(item, "name"))).read_bytes(),
            doc.text(doc.at(item, "sha")),
            doc.text(doc.at(item, "label")),
        )
        index += 1


def dispatch_declaration_tokens(payload: String) raises:
    """Read each declaration and require its recorded token digest.

    Args:
        payload: A JSON list. Each item has `source`, `name`, `owner`, `token`, and `label`.

    Raises:
        Error: A function cannot be read, or a token digest changed.
    """
    declaration_token_checks(payload, "curve support/dispatch contract: ")


def dispatch_tokens(directory: String) raises:
    """Require each text to have its recorded token digest.

    Args:
        directory: A directory with `labels.json` and `N.text` files.

    Raises:
        Error: A token digest changed, or the directory cannot be read.
    """
    var doc = PyJson.parse(Path(directory + "/labels.json").read_text())
    if doc.kind(doc.root) != PY_LIST:
        _fail("complete successor changed")
    var index = 0
    var count = doc.length(doc.root)
    while index < count:
        var row = doc.item(doc.root, index)
        var label = doc.text(doc.at(row, "label"))
        var expected = doc.text(doc.at(row, "token"))
        var text = Path(directory + "/" + String(index) + ".text").read_text()
        if token_sha256(text) != expected:
            _fail(label)
        index += 1


def dispatch_edge(recorded: String, expected: String) raises:
    """Require the raw predecessor token to match the caller.

    Args:
        recorded: The raw-cut record's before token.
        expected: The token the caller already holds.

    Raises:
        Error: The tokens differ.
    """
    if recorded != expected:
        _fail("raw predecessor edge mismatch")


def dispatch_source_graphs(payload: String) raises:
    """Compare each dispatch source pair by its significant tokens.

    Args:
        payload: A JSON list. Each item has `label`, `actual`, and `source`.

    Raises:
        Error: A source cannot be tokenized, or a token list changed.
    """
    significant_graph_pairs(
        payload,
        "curve support/dispatch contract: ",
        "successor operations changed",
    )


def dispatch_graphs(directory: String) raises:
    """Require each operation graph to match its recorded token list.

    Args:
        directory: A directory whose `labels.json` lists the graphs in order.

    Raises:
        Error: A token list changed, or the list cannot be read.
    """
    var doc = PyJson.parse(Path(directory + "/labels.json").read_text())
    if doc.kind(doc.root) != PY_LIST:
        _fail("successor operations changed")
    var index = 0
    var count = doc.length(doc.root)
    while index < count:
        var row = doc.item(doc.root, index)
        var label = doc.text(doc.at(row, "label"))
        if doc.text(doc.at(row, "actual")) != doc.text(doc.at(row, "expected")):
            _fail(label)
        index += 1


def _protected_name(index: Int) -> String:
    """Return one protected dependency path.

    Args:
        index: The path position, from 0 through 4.

    Returns:
        The repository path.
    """
    if index == 0:
        return "extensions/carla/curve_interval.mojo"
    if index == 1:
        return "extensions/carla/curve_sum2.mojo"
    if index == 2:
        return "extensions/carla/curve_bounds.mojo"
    if index == 3:
        return "extensions/carla/map.mojo"
    return "extensions/carla/lane_refinement.mojo"


def dispatch_paths() raises -> String:
    """Return the dispatch sources and the protected dependency paths.

    Returns:
        JSON with `sources` and `protected` in reviewed order.

    Raises:
        Error: The lists cannot be written.
    """
    var doc = PyJson()
    var spec = doc.new_dict()
    var sources = doc.new_list()
    var index = 0
    while index < 2:
        doc.append(sources, doc.new_str(_source_name(index)))
        index += 1
    doc.set(spec, "sources", sources)
    var protected = doc.new_list()
    index = 0
    while index < 5:
        doc.append(protected, doc.new_str(_protected_name(index)))
        index += 1
    doc.set(spec, "protected", protected)
    doc.root = spec
    return doc.dumps()


def _usage():
    """Print the command usage and stop."""
    print(
        (
            "usage: carla_dispatch_gate --migration PATH"
            " | --bytes PATH --sha HEX --label TEXT | --tokens DIR"
            " | --declaration-tokens PATH"
            " | --edge HEX --expected HEX | --graphs DIR"
            " | --source-graphs PATH | --pins DIR"
        ),
        file=stderr,
    )
    exit(2)


def main() raises:
    """Check the support and dispatch record and print nothing on success.

    Raises:
        Error: The command is invalid.
    """
    var migration = String("")
    var payload = String("")
    var digest = String("")
    var label = String("")
    var tokens = String("")
    var declaration_tokens = String("")
    var edge = String("")
    var expected = String("")
    var graphs = String("")
    var source_graphs = String("")
    var pins = String("")
    var arguments = argv()
    var index = 1
    while index < len(arguments):
        var word = arguments[index]
        if (
            word == "--migration"
            or word == "--bytes"
            or word == "--sha"
            or word == "--label"
            or word == "--tokens"
            or word == "--declaration-tokens"
            or word == "--edge"
            or word == "--expected"
            or word == "--graphs"
            or word == "--source-graphs"
            or word == "--pins"
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
            elif word == "--label":
                label = value
            elif word == "--tokens":
                tokens = value
            elif word == "--declaration-tokens":
                declaration_tokens = value
            elif word == "--edge":
                edge = value
            elif word == "--expected":
                expected = value
            elif word == "--graphs":
                graphs = value
            elif word == "--source-graphs":
                source_graphs = value
            else:
                pins = value
            index += 2
            continue
        _usage()
    var modes = 0
    if migration.byte_length() > 0:
        modes += 1
    if payload.byte_length() > 0:
        modes += 1
    if tokens.byte_length() > 0:
        modes += 1
    if declaration_tokens.byte_length() > 0:
        modes += 1
    if edge.byte_length() > 0 or expected.byte_length() > 0:
        modes += 1
    if graphs.byte_length() > 0:
        modes += 1
    if source_graphs.byte_length() > 0:
        modes += 1
    if pins.byte_length() > 0:
        modes += 1
    if modes != 1:
        _usage()
    if (edge.byte_length() == 0) != (expected.byte_length() == 0):
        _usage()
    if payload.byte_length() > 0 and (
        digest.byte_length() == 0 or label.byte_length() == 0
    ):
        _usage()
    try:
        if source_graphs.byte_length() > 0:
            dispatch_source_graphs(Path(source_graphs).read_text())
            return
        if graphs.byte_length() > 0:
            dispatch_graphs(graphs)
            return
        if pins.byte_length() > 0:
            dispatch_pins(pins)
            return
        if edge.byte_length() > 0:
            dispatch_edge(edge, expected)
            return
        if declaration_tokens.byte_length() > 0:
            dispatch_declaration_tokens(Path(declaration_tokens).read_text())
            return
        if tokens.byte_length() > 0:
            dispatch_tokens(tokens)
            return
        if migration.byte_length() > 0:
            dispatch_record(Path(migration).read_bytes())
        else:
            dispatch_pin(Path(payload).read_bytes(), digest, label)
    except error:
        print(String(error), file=stderr)
        exit(1)
