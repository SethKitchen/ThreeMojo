# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md

"""Check the rounded LINE singleton migration record.

    carla_singleton_gate --migration PATH
    carla_singleton_gate --text PATH --decoded PATH
    carla_singleton_gate --graphs DIR
    carla_singleton_gate --source-graphs PATH
    carla_singleton_gate --import-scopes PATH
    carla_singleton_gate --declaration-graphs PATH
    carla_singleton_gate --restored-graphs PATH
    carla_singleton_gate --selector PATH --wanted PATH

The program checks the bytes it is given. It does not read the repository
and it does not restore a historical source. The caller does that first.
"""

from std.pathlib import Path
from std.sys import argv, exit, stderr

from tests._python_tokens import (
    import_scope_prefixes,
    significant_graph_pairs,
    significant_match_flags,
    token_sha256,
)
from tools._lane_declarations import (
    checked_declaration_graphs,
    restored_declaration_graphs,
)
from tools._python_json import MISSING, PY_LIST, PyJson, py_equal
from tools._sha256 import sha256_hex


comptime _MIGRATION_SHA256 = (
    "e4a0eb6c9e527dd66b2b803ee69754334feecc9bea33ce001cdf584d3a693506"
)


def _fail(message: String) raises:
    """Raise one singleton-record failure.

    Args:
        message: The reason, without the prefix.

    Raises:
        Error: Always.
    """
    raise Error("rounded LINE singleton contract: " + message)


def singleton_record(migration: Span[UInt8, _]) raises:
    """Require the rounded LINE singleton migration.

    Args:
        migration: The successor record bytes.

    Raises:
        Error: The digest or the schema changed.
    """
    if sha256_hex(migration) != _MIGRATION_SHA256:
        _fail("unreviewed migration record")
    var doc = PyJson.parse(String(from_utf8_lossy=migration))
    var schema = doc.get(doc.root, "schema")
    var one = PyJson.parse("1")
    if schema == MISSING or not py_equal(doc, schema, one, one.root):
        _fail("wrong schema")


def singleton_views(text: String, decoded: String) raises:
    """Require the text view and the decoded byte view to share one token.

    Args:
        text: The text read from the lane source.
        decoded: The same file decoded from its bytes.

    Raises:
        Error: The token digests disagree.
    """
    if token_sha256(text) != token_sha256(decoded):
        _fail("consumer lane source text/bytes disagree")


def singleton_path(actual: String, expected: String) raises:
    """Require the selector predecessor path.

    Args:
        actual: The path the selector record reports.
        expected: The path the singleton record requested.

    Raises:
        Error: The paths disagree.
    """
    if actual != expected:
        _fail("wrong selector predecessor path")


def singleton_source_graphs(payload: String) raises:
    """Compare each rounded LINE source pair by its significant tokens.

    Args:
        payload: A JSON list. Each item has `label`, `actual`, and `source`.

    Raises:
        Error: A source cannot be tokenized, or a token list changed.
    """
    significant_graph_pairs(
        payload,
        "rounded LINE singleton contract: ",
        "consumer import scope changed",
    )


def checked_import_scopes(payload: String) raises -> String:
    """Extract every import scope, then check it when the lane scope matches.

    Args:
        payload: JSON with `texts`, `expected`, and `labels`. `lane` is the
            optional index whose scope can request a restore.

    Returns:
        `restore` is false when every graph matches. It is true, with the
        extracted `prefixes`, when the lane scope differs.

    Raises:
        Error: A scope cannot be read, or a non-lane graph changed.
    """
    var doc = PyJson.parse(payload)
    var prefixes_text = import_scope_prefixes(
        doc.subtree(doc.at(doc.root, "texts")).dumps()
    )
    var prefixes = PyJson.parse(prefixes_text)
    var lane = doc.get(doc.root, "lane")
    if lane != MISSING:
        var at = Int(doc.text(lane))
        var match_doc = PyJson()
        var match_rows = match_doc.new_list()
        var pair = match_doc.new_dict()
        match_doc.set(
            pair,
            "actual",
            match_doc.new_str(prefixes.text(prefixes.item(prefixes.root, at))),
        )
        match_doc.set(
            pair,
            "source",
            match_doc.new_str(
                doc.text(doc.item(doc.at(doc.root, "expected"), at))
            ),
        )
        match_doc.append(match_rows, pair)
        match_doc.root = match_rows
        var flags = PyJson.parse(significant_match_flags(match_doc.dumps()))
        if flags.text(flags.item(flags.root, 0)) != "true":
            return '{"restore":true,"prefixes":' + prefixes_text + "}"
    var graphs = PyJson()
    var rows = graphs.new_list()
    var expected = doc.at(doc.root, "expected")
    var labels = doc.at(doc.root, "labels")
    var count = prefixes.length(prefixes.root)
    var index = 0
    while index < count:
        var row = graphs.new_dict()
        graphs.set(
            row, "label", graphs.new_str(doc.text(doc.item(labels, index)))
        )
        graphs.set(
            row,
            "actual",
            graphs.new_str(prefixes.text(prefixes.item(prefixes.root, index))),
        )
        graphs.set(
            row,
            "source",
            graphs.new_str(doc.text(doc.item(expected, index))),
        )
        graphs.append(rows, row)
        index += 1
    graphs.root = rows
    significant_graph_pairs(
        graphs.dumps(),
        "rounded LINE singleton contract: ",
        "consumer import scope changed",
    )
    return '{"restore":false}'


def singleton_checked_declarations(payload: String) raises -> String:
    """Read every declaration, then check every graph when each selected one matches.

    Args:
        payload: A JSON list. Each item has `source`, `name`, `owner`, `graph`,
            and `label`. `expected` is optional.

    Returns:
        `restore` is false when every graph matches. It is true, with
        `declared` and `flags`, when a selected declaration differs.

    Raises:
        Error: A function cannot be read, or a graph changed while every selected declaration matches.
    """
    return checked_declaration_graphs(
        payload,
        "rounded LINE singleton contract: ",
        "consumer import scope changed",
    )


def singleton_restored_graphs(payload: String) raises:
    """Read each restored declaration, then compare every source graph.

    Args:
        payload: JSON with `restores` and `graphs`. Each restore has
            `index`, `source`, `name`, and `owner`. Each graph has
            `label`, `actual`, and `source`.

    Raises:
        Error: A function cannot be read, a source cannot be tokenized, or a token list changed.
    """
    restored_declaration_graphs(
        payload,
        "rounded LINE singleton contract: ",
        "consumer import scope changed",
    )


def singleton_graphs(directory: String) raises:
    """Require each consumer token list to match its record.

    Args:
        directory: A directory whose `labels.json` lists the comparisons in order.

    Raises:
        Error: A token list changed, or the list cannot be read.
    """
    var doc = PyJson.parse(Path(directory + "/labels.json").read_text())
    if doc.kind(doc.root) != PY_LIST:
        _fail("consumer import scope changed")
    var index = 0
    var count = doc.length(doc.root)
    while index < count:
        var row = doc.item(doc.root, index)
        var label = doc.text(doc.at(row, "label"))
        if doc.text(doc.at(row, "actual")) != doc.text(doc.at(row, "expected")):
            _fail(label)
        index += 1


def _usage():
    """Print the command usage and stop."""
    print(
        (
            "usage: carla_singleton_gate --migration PATH"
            " | --text PATH --decoded PATH | --graphs DIR"
            " | --source-graphs PATH"
            " | --import-scopes PATH"
            " | --declaration-graphs PATH"
            " | --restored-graphs PATH"
            " | --selector PATH --wanted PATH"
        ),
        file=stderr,
    )
    exit(2)


def main() raises:
    """Check the singleton record and print nothing on success.

    Raises:
        Error: The command is invalid.
    """
    var migration = String("")
    var text = String("")
    var decoded = String("")
    var graphs = String("")
    var source_graphs = String("")
    var import_scopes = String("")
    var declaration_graphs = String("")
    var restored_graphs = String("")
    var selector = String("")
    var wanted = String("")
    var arguments = argv()
    var index = 1
    while index < len(arguments):
        var word = arguments[index]
        if (
            word == "--migration"
            or word == "--text"
            or word == "--decoded"
            or word == "--graphs"
            or word == "--source-graphs"
            or word == "--import-scopes"
            or word == "--declaration-graphs"
            or word == "--restored-graphs"
            or word == "--selector"
            or word == "--wanted"
        ):
            if index + 1 >= len(arguments):
                _usage()
            var value = arguments[index + 1]
            if word == "--migration":
                migration = value
            elif word == "--text":
                text = value
            elif word == "--decoded":
                decoded = value
            elif word == "--graphs":
                graphs = value
            elif word == "--source-graphs":
                source_graphs = value
            elif word == "--import-scopes":
                import_scopes = value
            elif word == "--declaration-graphs":
                declaration_graphs = value
            elif word == "--restored-graphs":
                restored_graphs = value
            elif word == "--selector":
                selector = value
            else:
                wanted = value
            index += 2
            continue
        _usage()
    var modes = 0
    if migration.byte_length() > 0:
        modes += 1
    if text.byte_length() > 0 or decoded.byte_length() > 0:
        modes += 1
    if graphs.byte_length() > 0:
        modes += 1
    if source_graphs.byte_length() > 0:
        modes += 1
    if import_scopes.byte_length() > 0:
        modes += 1
    if declaration_graphs.byte_length() > 0:
        modes += 1
    if restored_graphs.byte_length() > 0:
        modes += 1
    if selector.byte_length() > 0 or wanted.byte_length() > 0:
        modes += 1
    if (
        modes != 1
        or (text.byte_length() == 0) != (decoded.byte_length() == 0)
        or (selector.byte_length() == 0) != (wanted.byte_length() == 0)
    ):
        _usage()
    try:
        if source_graphs.byte_length() > 0:
            singleton_source_graphs(Path(source_graphs).read_text())
            return
        if import_scopes.byte_length() > 0:
            print(
                checked_import_scopes(Path(import_scopes).read_text()), end=""
            )
            return
        if declaration_graphs.byte_length() > 0:
            print(
                singleton_checked_declarations(
                    Path(declaration_graphs).read_text()
                ),
                end="",
            )
            return
        if restored_graphs.byte_length() > 0:
            singleton_restored_graphs(Path(restored_graphs).read_text())
            return
        if graphs.byte_length() > 0:
            singleton_graphs(graphs)
            return
        if text.byte_length() > 0:
            singleton_views(Path(text).read_text(), Path(decoded).read_text())
            return
        if selector.byte_length() > 0:
            singleton_path(Path(selector).read_text(), Path(wanted).read_text())
            return
        singleton_record(Path(migration).read_bytes())
    except error:
        print(String(error), file=stderr)
        exit(1)
