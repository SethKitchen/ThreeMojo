# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md

"""Check the runtime-boundary record and bound files.

    carla_runtime_boundary_gate --protected-bundle
    carla_runtime_boundary_gate --migration PATH
    carla_runtime_boundary_gate --bytes PATH --sha HEX [--token HEX] --label TEXT
    carla_runtime_boundary_gate --bytes-all DIR
    carla_runtime_boundary_gate --checked-edges DIR
    carla_runtime_boundary_gate --checked-labeled DIR
    carla_runtime_boundary_gate --steps DIR
    carla_runtime_boundary_gate --extend --path TEXT --step-sha HEX --edge-sha HEX --step-token HEX --edge-token HEX
    carla_runtime_boundary_gate --extends PATH
    carla_runtime_boundary_gate --extended PATH

The program checks the bytes it is given. It does not read the repository
and it does not restore a historical source. The caller does that first.
A directory checks every listed file in order. `--extends` checks every
listed step in order.
"""

from std.pathlib import Path
from std.sys import argv, exit, stderr

from tests._python_tokens import token_sha256
from tools._migration_records import migration_records
from tools._runtime_edge import emit_json, extend_runtime_edges
from tools._bound_consumer_messages import bound_consumer_messages
from tools._merged_edge import merged_edges
from tools._python_json import (
    MISSING,
    PY_BOOL,
    PY_DICT,
    PY_INT,
    PY_LIST,
    PY_STR,
    PyJson,
    py_equal,
)
from tools._sha256 import sha256_hex


comptime _MIGRATION_SHA256 = (
    "992854b1191bd365fca3e5e8d3a7fc751ac2eb3196b33684e04ebad833baab00"
)


def _fail(message: String) raises:
    """Raise one runtime-boundary failure.

    Args:
        message: The reason, without the prefix.

    Raises:
        Error: Always.
    """
    raise Error("reviewed runtime boundary successor: " + message)


def _module(index: Int) -> String:
    """Return one reviewed module path.

    Args:
        index: The path position, from 0 through 3.

    Returns:
        The repository path.
    """
    if index == 0:
        return "extensions/carla/cameras.mojo"
    if index == 1:
        return "extensions/carla/lane_invasion.mojo"
    if index == 2:
        return "extensions/carla/sensor_manager.mojo"
    return "extensions/carla/world.mojo"


def _test_name(index: Int) -> String:
    """Return one bound test path.

    Args:
        index: The path position, from 0 through 11.

    Returns:
        The repository path.
    """
    if index == 0:
        return "tests/test_carla_sensors.mojo"
    if index == 1:
        return "tests/test_carla_sensors_world.mojo"
    if index == 2:
        return "tests/test_carla_world_signals.mojo"
    if index == 3:
        return "tests/compile_fail/carla_event_camera_time_rejects_float32_duration.mojo"
    if index == 4:
        return "tests/compile_fail/carla_event_camera_time_rejects_length.mojo"
    if index == 5:
        return "tests/compile_fail/carla_event_camera_time_rejects_raw_float64.mojo"
    if index == 6:
        return "tests/compile_fail/carla_lane_invasion_time_rejects_float32_duration.mojo"
    if index == 7:
        return "tests/compile_fail/carla_lane_invasion_time_rejects_length.mojo"
    if index == 8:
        return "tests/compile_fail/carla_lane_invasion_time_rejects_raw_float64.mojo"
    if index == 9:
        return "tests/compile_fail/carla_light_search_distance_rejects_duration.mojo"
    if index == 10:
        return "tests/compile_fail/carla_light_search_distance_rejects_float32_length.mojo"
    return "tests/compile_fail/carla_light_search_distance_rejects_raw_float64.mojo"


def _keys_match(doc: PyJson, node: Int, count: Int, tests: Bool) -> Bool:
    """Return whether an object has one reviewed key set.

    Args:
        doc: The record.
        node: The object, or `MISSING`.
        count: The number of reviewed keys.
        tests: True for the bound tests, false for the modules.

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
        var name = _test_name(index) if tests else _module(index)
        if doc.get(node, name) == MISSING:
            return False
        index += 1
    return True


def _require_edge(doc: PyJson, edge: Int, name: String) raises:
    """Require the four edge digests and a real change.

    Args:
        doc: The record.
        edge: The edge object.
        name: The module path, used in the failure text.

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
        _fail("malformed edge: " + name)


def runtime_boundary_record(migration: Span[UInt8, _]) raises:
    """Require the runtime-boundary record.

    Args:
        migration: The successor record bytes.

    Raises:
        Error: The record scope, tests, or an edge changed.
    """
    if sha256_hex(migration) != _MIGRATION_SHA256:
        _fail("unreviewed exact edge")
    var doc = PyJson.parse(String(from_utf8_lossy=migration))
    var schema = doc.get(doc.root, "schema")
    var issue = doc.get(doc.root, "issue")
    var three = PyJson.parse("333")
    if (
        schema == MISSING
        or doc.kind(schema) != PY_INT
        or doc.text(schema) != "1"
        or issue == MISSING
        or not py_equal(doc, issue, three, three.root)
        or not _keys_match(doc, doc.get(doc.root, "edges"), 4, False)
    ):
        _fail("unexpected successor scope")
    if not _keys_match(doc, doc.get(doc.root, "correctness_tests"), 12, True):
        _fail("unexpected correctness test set")
    var edges = doc.get(doc.root, "edges")
    var index = 0
    while index < 4:
        var name = _module(index)
        var edge = doc.get(edges, name)
        if edge == MISSING or doc.kind(edge) != PY_DICT:
            _fail("malformed edge: " + name)
        _require_edge(doc, edge, name)
        index += 1


def runtime_boundary_bytes(
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
    if token_sha256(String(from_utf8_lossy=payload)) != expected_token:
        _fail(label)


def runtime_boundary_bytes_all(directory: String) raises:
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
        runtime_boundary_bytes(
            Path(directory + "/" + doc.text(doc.at(item, "name"))).read_bytes(),
            doc.text(doc.at(item, "sha")),
            token,
            doc.text(doc.at(item, "label")),
        )
        index += 1


def runtime_boundary_checked_edges(directory: String) raises -> String:
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
    runtime_boundary_bytes_all(directory)
    return merged_edges(Path(directory + "/labels.json").read_text())


def runtime_boundary_checked_edges_with_messages(
    directory: String,
) raises -> String:
    """Read the consumer messages, then check every file digest.

    Args:
        directory: A directory with `labels.json` and one file per item.
            Each item has `name`, `sha`, `path`, and `edge`. `token` is
            optional. The consumer message supplies `label`.

    Returns:
        JSON with `edges` and `messages`. The edges keep their path first.

    Raises:
        Error: A digest changed, or an edge cannot be read. The messages
            are read before the digests.
    """
    var messages = bound_consumer_messages()
    var parsed = PyJson.parse(messages)
    var prefix = parsed.text(parsed.at(parsed.root, "runtime_consumer"))
    var labels = Path(directory + "/labels.json").read_text()
    var doc = PyJson.parse(labels)
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
        var path = doc.text(doc.at(item, "path"))
        runtime_boundary_bytes(
            Path(directory + "/" + doc.text(doc.at(item, "name"))).read_bytes(),
            doc.text(doc.at(item, "sha")),
            token,
            prefix + path,
        )
        index += 1
    return '{"edges":' + merged_edges(labels) + ',"messages":' + messages + "}"


def _known_module(name: String) -> Bool:
    """Return whether the path is one reviewed boundary module.

    Args:
        name: The step path.

    Returns:
        True for one of the four reviewed modules.
    """
    var index = 0
    while index < 4:
        if name == _module(index):
            return True
        index += 1
    return False


def boundary_steps(directory: String) raises:
    """Require every view-step path to be a reviewed module.

    Args:
        directory: A directory whose `labels.json` is a list of paths.

    Raises:
        Error: A path is outside the boundary, or the list cannot be read.
    """
    var doc = PyJson.parse(Path(directory + "/labels.json").read_text())
    if doc.kind(doc.root) != PY_LIST:
        _fail("runtime view step outside the boundary scope")
    var index = 0
    var count = doc.length(doc.root)
    while index < count:
        var name = doc.text(doc.item(doc.root, index))
        if not _known_module(name):
            _fail("runtime view step outside the boundary scope")
        index += 1


def boundary_extend(
    step_sha: String,
    edge_sha: String,
    step_token: String,
    edge_token: String,
    path: String,
) raises:
    """Require a view step to start where the edge ends.

    Args:
        step_sha: The step's before digest.
        edge_sha: The edge's after digest.
        step_token: The step's before token digest.
        edge_token: The edge's after token digest.
        path: The module path, used in the failure text.

    Raises:
        Error: The step does not extend the edge.
    """
    if step_sha != edge_sha or step_token != edge_token:
        _fail("runtime view step does not extend the edge: " + path)


def runtime_boundary_extended_edges(payload: String) raises -> String:
    """Decide every edge, then require each extension to meet that edge.

    Args:
        payload: JSON with `steps` and `items`. Each item has `path` and `edge`.

    Returns:
        A JSON list of edge decisions, in item order.

    Raises:
        Error: A step is missing a digest, or a step does not extend its edge.
    """
    var decisions = extend_runtime_edges(payload)
    var doc = PyJson.parse(payload)
    var decided = PyJson.parse(decisions)
    var steps = doc.at(doc.root, "steps")
    var items = doc.at(doc.root, "items")
    var count = decided.length(decided.root)
    var index = 0
    while index < count:
        var decision = decided.item(decided.root, index)
        var extend_node = decided.at(decision, "extend")
        if decided.kind(extend_node) == PY_BOOL and decided.flag(extend_node):
            var item = doc.item(items, index)
            var path = doc.text(doc.at(item, "path"))
            var edge = doc.at(item, "edge")
            var step = doc.at(steps, path)
            boundary_extend(
                doc.text(doc.at(step, "before_sha256")),
                doc.text(doc.at(edge, "after_sha256")),
                doc.text(doc.at(step, "before_token_sha256")),
                doc.text(doc.at(edge, "after_token_sha256")),
                path,
            )
        index += 1
    return decisions


def boundary_extends(payload: String) raises:
    """Require each view step to start where its edge ends.

    Args:
        payload: A JSON list. Each item has `path`, `step_sha`, `edge_sha`,
            `step_token`, and `edge_token`.

    Raises:
        Error: A step does not extend its edge, or the payload is not a
            JSON list.
    """
    var doc = PyJson.parse(payload)
    if doc.kind(doc.root) != PY_LIST:
        _fail("malformed extend list")
    var index = 0
    var count = doc.length(doc.root)
    while index < count:
        var item = doc.item(doc.root, index)
        boundary_extend(
            doc.text(doc.at(item, "step_sha")),
            doc.text(doc.at(item, "edge_sha")),
            doc.text(doc.at(item, "step_token")),
            doc.text(doc.at(item, "edge_token")),
            doc.text(doc.at(item, "path")),
        )
        index += 1


def runtime_boundary_modules() raises -> String:
    """Return the four runtime-boundary module paths.

    Returns:
        A JSON list in reviewed order.

    Raises:
        Error: The list cannot be written.
    """
    var doc = PyJson()
    var names = doc.new_list()
    var index = 0
    while index < 4:
        doc.append(names, doc.new_str(_module(index)))
        index += 1
    doc.root = names
    return doc.dumps()


def runtime_boundary_edges_after_steps(payload: String) raises -> String:
    """Check the view steps, then the module paths, then the extensions.

    Args:
        payload: JSON with `steps` and `edges`. `steps` maps a module path
            to its digests. `edges` maps every boundary module to its edge.

    Returns:
        JSON with `modules` and `decisions`, in module order.

    Raises:
        Error: A view step is outside the boundary, an edge key is missing,
            or a step does not extend its edge. The view steps are checked
            before the module paths. A missing edge is reported before an
            extension check.
    """
    var doc = PyJson.parse(payload)
    var steps = doc.at(doc.root, "steps")
    if doc.kind(steps) != PY_DICT:
        _fail("runtime view step outside the boundary scope")
    var index = 0
    var step_count = doc.length(steps)
    while index < step_count:
        if not _known_module(doc.key(steps, index)):
            _fail("runtime view step outside the boundary scope")
        index += 1
    var modules_text = runtime_boundary_modules()
    var modules = PyJson.parse(modules_text)
    var edges = doc.at(doc.root, "edges")
    var items = doc.new_list()
    var count = modules.length(modules.root)
    index = 0
    while index < count:
        var path = modules.text(modules.item(modules.root, index))
        var edge = doc.at(edges, path)
        var item = doc.new_dict()
        doc.set(item, "path", doc.new_str(path))
        doc.set(item, "edge", doc.copy_node(edge))
        doc.append(items, item)
        index += 1
    var body = doc.new_dict()
    doc.set(body, "steps", doc.copy_node(steps))
    doc.set(body, "items", items)
    var decisions = runtime_boundary_extended_edges(emit_json(doc, body))
    return '{"modules":' + modules_text + ',"decisions":' + decisions + "}"


def runtime_boundary_tests() raises -> String:
    """Return the bound tests and the compile-fail fixtures.

    Returns:
        JSON with `tests` and `fixtures` in reviewed order.

    Raises:
        Error: The lists cannot be written.
    """
    var doc = PyJson()
    var spec = doc.new_dict()
    var tests = doc.new_list()
    var fixtures = doc.new_list()
    var index = 0
    while index < 12:
        var path = _test_name(index)
        doc.append(tests, doc.new_str(path))
        if index >= 3:
            doc.append(fixtures, doc.new_str(path))
        index += 1
    doc.set(spec, "tests", tests)
    doc.set(spec, "fixtures", fixtures)
    doc.root = spec
    return doc.dumps()


def runtime_protected_bundle() raises -> String:
    """Read the runtime migration record, then the modules and tests.

    Returns:
        JSON with `migration`, `modules`, and `tests`. The migration
        record is read before the modules. The tests are read last.

    Raises:
        Error: A list cannot be written. The migration record is read
            before the modules and the tests.
    """
    var records = PyJson.parse(migration_records())
    var migration = records.subtree(records.at(records.root, "runtime")).dumps()
    var modules = runtime_boundary_modules()
    var tests = runtime_boundary_tests()
    return (
        '{"migration":'
        + migration
        + ',"modules":'
        + modules
        + ',"tests":'
        + tests
        + "}"
    )


def _usage():
    """Print the command usage and stop."""
    print(
        (
            "usage: carla_runtime_boundary_gate --migration PATH"
            " | --bytes PATH --sha HEX [--token HEX] --label TEXT"
            " | --bytes-all DIR | --checked-edges DIR | --steps DIR"
            " | --extend --path TEXT"
            " --step-sha HEX"
            " --edge-sha HEX --step-token HEX --edge-token HEX"
            " | --extends PATH"
        ),
        file=stderr,
    )
    exit(2)


def main() raises:
    """Check a runtime-boundary record or file and print nothing on success.

    Raises:
        Error: The command is invalid.
    """
    var arguments = argv()
    if len(arguments) == 2 and arguments[1] == "--protected-bundle":
        try:
            print(runtime_protected_bundle(), end="")
        except error:
            print(String(error), file=stderr)
            exit(1)
        return
    if len(arguments) == 3 and arguments[1] == "--after-steps":
        try:
            print(
                runtime_boundary_edges_after_steps(
                    Path(arguments[2]).read_text()
                ),
                end="",
            )
        except error:
            print(String(error), file=stderr)
            exit(1)
        return
    if len(arguments) == 3 and arguments[1] == "--checked-labeled":
        try:
            print(
                runtime_boundary_checked_edges_with_messages(arguments[2]),
                end="",
            )
        except error:
            print(String(error), file=stderr)
            exit(1)
        return
    var migration = String("")
    var payload = String("")
    var digest = String("")
    var token = String("")
    var label = String("")
    var steps = String("")
    var bytes_all = String("")
    var checked_edges = String("")
    var extend = False
    var module_path = String("")
    var step_sha = String("")
    var edge_sha = String("")
    var step_token = String("")
    var edge_token = String("")
    var extends = String("")
    var extended = String("")
    var index = 1
    while index < len(arguments):
        var word = arguments[index]
        if word == "--extend":
            extend = True
            index += 1
            continue
        if (
            word == "--migration"
            or word == "--bytes"
            or word == "--sha"
            or word == "--token"
            or word == "--label"
            or word == "--steps"
            or word == "--bytes-all"
            or word == "--checked-edges"
            or word == "--path"
            or word == "--step-sha"
            or word == "--edge-sha"
            or word == "--step-token"
            or word == "--edge-token"
            or word == "--extends"
            or word == "--extended"
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
            elif word == "--steps":
                steps = value
            elif word == "--bytes-all":
                bytes_all = value
            elif word == "--checked-edges":
                checked_edges = value
            elif word == "--path":
                module_path = value
            elif word == "--step-sha":
                step_sha = value
            elif word == "--edge-sha":
                edge_sha = value
            elif word == "--step-token":
                step_token = value
            elif word == "--edge-token":
                edge_token = value
            elif word == "--extends":
                extends = value
            else:
                extended = value
            index += 2
            continue
        _usage()
    var modes = 0
    if migration.byte_length() > 0:
        modes += 1
    if payload.byte_length() > 0:
        modes += 1
    if steps.byte_length() > 0:
        modes += 1
    if bytes_all.byte_length() > 0:
        modes += 1
    if checked_edges.byte_length() > 0:
        modes += 1
    if extend:
        modes += 1
    if extends.byte_length() > 0:
        modes += 1
    if extended.byte_length() > 0:
        modes += 1
    if modes != 1:
        _usage()
    if payload.byte_length() > 0 and (
        digest.byte_length() == 0 or label.byte_length() == 0
    ):
        _usage()
    if extend and (
        module_path.byte_length() == 0
        or step_sha.byte_length() == 0
        or edge_sha.byte_length() == 0
        or step_token.byte_length() == 0
        or edge_token.byte_length() == 0
    ):
        _usage()
    try:
        if steps.byte_length() > 0:
            boundary_steps(steps)
            return
        if extend:
            boundary_extend(
                step_sha, edge_sha, step_token, edge_token, module_path
            )
            return
        if extended.byte_length() > 0:
            print(
                runtime_boundary_extended_edges(Path(extended).read_text()),
                end="",
            )
            return
        if extends.byte_length() > 0:
            boundary_extends(Path(extends).read_text())
            return
        if migration.byte_length() > 0:
            runtime_boundary_record(Path(migration).read_bytes())
        elif checked_edges.byte_length() > 0:
            print(runtime_boundary_checked_edges(checked_edges), end="")
        elif bytes_all.byte_length() > 0:
            runtime_boundary_bytes_all(bytes_all)
        else:
            runtime_boundary_bytes(
                Path(payload).read_bytes(), digest, token, label
            )
    except error:
        print(String(error), file=stderr)
        exit(1)
