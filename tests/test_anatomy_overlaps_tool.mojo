# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Check the #595 overlap evidence, its bindings and its classification.

The repaired evidence must match the current source and tool bindings.
Small source trees separately check changed inputs. The unrepaired
localization stays pinned to its recorded bytes.
"""

from std.collections import Set
from std.pathlib import Path
from std.testing import (
    TestSuite,
    assert_equal,
    assert_false,
    assert_raises,
    assert_true,
)

from tests._tree import Tree
from tools._json_tree import NOTHING, JsonTree
from tools._sha256 import sha256_hex
from tools.anatomy_overlaps import (
    SCHEMA_VERSION,
    check_witness,
    classes,
    classification,
    issue_595_pairs,
    legacy_groups,
    legacy_pair_ids,
    refuse_tool_change,
    rules,
    status,
    steps_mm,
    sweep,
    tool_sha256,
    witness_request,
)
from tools.anatomy_validity import (
    Component,
    Num,
    Prober,
    source_digest,
    validate_catalog,
)

comptime CURRENT = "docs/validation/anatomy-overlaps-595.json"
"""The repaired evidence."""
comptime BEFORE = "docs/validation/anatomy-overlaps-595-before.json"
"""The localization of the unrepaired template. Its source is the commit
that added the witness probe and changed no anatomy."""
comptime BEFORE_SHA256 = (
    "fd1f2d1de0c62b4a8a78a69cf0ec8a099da542c6958441c71f68fcb5a1aeb03e"
)
"""The unrepaired localization's file digest."""
comptime BEFORE_SOURCE_SHA256 = (
    "d984741bb8496a606e68649a5f6428107baa195e0aaca99ddf470985fdf06529"
)
"""The unrepaired localization's source digest."""


def _names(entries: List[Tuple[String, String]]) -> Set[String]:
    """Return the first members of some pairs."""
    var found = Set[String]()
    for entry in entries:
        found.add(entry[0])
    return found^


def check_record(tree: JsonTree, report: Int) raises -> Int:
    """Refuse evidence whose shape or status does not follow its samples.

    Args:
        tree: The tree.
        report: The evidence.

    Returns:
        The evidence.

    Raises:
        Error: For another schema or grid, an untracked issue pair, a
            missing grid, an unknown rule or class, or a status that does
            not follow the samples.
    """
    var widths = tree.item(report, "steps_mm")
    var steps = steps_mm()
    var same = tree.is_number(
        tree.item(report, "schema_version"), Float64(SCHEMA_VERSION)
    ) and tree.length(widths) == len(steps)
    if same:
        for index in range(len(steps)):
            if not tree.is_number(tree.at(widths, index), steps[index].value):
                same = False
    if not same:
        raise Error("overlap evidence has a different schema or grid")
    var listed = Set[String]()
    for pair in tree.items(tree.item(report, "pairs")):
        if tree.truthy(tree.item(pair, "listed_in_issue_595")):
            listed.add(tree.text(tree.item(pair, "pair_id")))
    var issue = Set[String]()
    for pair in issue_595_pairs():
        issue.add(pair)
    if listed != issue:
        raise Error("overlap evidence does not track every issue pair")
    var rule_names = _names(rules())
    var class_names = _names(classes())
    for pair in tree.items(tree.item(report, "pairs")):
        var grids = tree.items(tree.item(pair, "grids"))
        if len(grids) != len(steps):
            raise Error("a tracked pair is missing a grid width")
        if (
            not tree.text(tree.item(pair, "interface_rule")) in rule_names
            or not tree.text(tree.item(pair, "classification")) in class_names
        ):
            raise Error("a tracked pair has an unknown rule or class")
        for grid in grids:
            if tree.value(tree.item(grid, "samples")) > 0 and tree.is_null(
                tree.item(grid, "witness_point_m")
            ):
                raise Error("a sampled pair has no witness point")
            if (tree.value(tree.item(grid, "overlap_samples")) > 0) != tree.has(
                grid, "hit_center_low_m"
            ):
                raise Error("common-interior cells and their box disagree")
        if not tree.is_text(tree.item(pair, "status"), status(tree, grids)):
            raise Error("a pair status does not follow its samples")
    return report


def check_current(path: String, root: String) raises:
    """The live evidence must match the current source and tool.

    Args:
        path: The evidence file.
        root: The repository root.

    Raises:
        Error: For invalid evidence or a stale source or tool binding.
    """
    var tree = JsonTree()
    var report = check_record(tree, tree.parse(Path(path).read_text()))
    if not tree.is_text(
        tree.path(report, ["build_provenance", "source_sha256"]),
        source_digest(root),
    ):
        raise Error(
            "overlap evidence has a stale source binding; regenerate with"
            " mojo run -I . tools/anatomy_overlaps.mojo --build --output"
            " docs/validation/anatomy-overlaps-595.json"
        )
    if not tree.is_text(tree.item(report, "tool_sha256"), tool_sha256(root)):
        raise Error("overlap evidence has a stale tool binding")


def check_before(mut tree: JsonTree, path: String) raises -> Int:
    """The unrepaired localization is pinned to its recorded source.

    Args:
        tree: The tree for the evidence.
        path: The evidence file.

    Returns:
        The evidence.

    Raises:
        Error: If the bytes or the source binding changed.
    """
    var data = Path(path).read_bytes()
    if sha256_hex(data) != BEFORE_SHA256:
        raise Error("pinned overlap localization checksum changed")
    var report = check_record(tree, tree.parse(String(from_utf8=Span(data))))
    if not tree.is_text(
        tree.path(report, ["build_provenance", "source_sha256"]),
        BEFORE_SOURCE_SHA256,
    ):
        raise Error("pinned overlap localization source binding changed")
    return report


def test_tool_changes_during_execution_refuse_publication() raises:
    refuse_tool_change("same", "same", "same")
    with assert_raises(contains="overlap tool changed"):
        refuse_tool_change("before", "before", "after")
    with assert_raises(contains="overlap tool changed"):
        refuse_tool_change("during", "before", "before")


struct Replay(Prober):
    """Answer each legacy group request with copies of saved records."""

    var saved: JsonTree
    """The saved records."""
    var groups: Dict[String, List[Int]]
    """Each group's saved records."""

    def __init__(out self):
        """Start with no records."""
        self.saved = JsonTree()
        self.groups = Dict[String, List[Int]]()

    def rows(
        mut self,
        mut tree: JsonTree,
        probe: String,
        mode: String,
        part: String,
        step: Num,
    ) raises -> List[Int]:
        """Answer one request.

        Args:
            tree: The tree for the records.
            probe: Ignored.
            mode: A legacy group.
            part: Ignored.
            step: Ignored.

        Returns:
            Copies of the group's saved records.

        Raises:
            Error: For a group with no records.
        """
        var found = List[Int]()
        for row in self.groups[mode]:
            found.append(tree.adopt(self.saved, row))
        return found^


def test_each_grid_requires_the_complete_legacy_pair_inventory() raises:
    var tree = JsonTree()
    var template = tree.parse(
        Path("docs/validation/anatomy-template-report.json").read_text()
    )
    var rows = List[Int]()
    for row in tree.items(
        tree.path(template, ["pair_inventory", "components"])
    ):
        rows.append(tree.clone(row))
    var catalog = validate_catalog(tree, rows)
    var expected = legacy_pair_ids(catalog)
    assert_equal(len(expected[0]), 435)
    assert_equal(len(expected[1]), 30)
    assert_equal(len(expected[2]), 67)
    var replay = Replay()
    for group in legacy_groups():
        var saved = List[Int]()
        for row in tree.items(tree.path(template, ["diagnostics", group])):
            if tree.is_text(tree.item(row, "record"), "pair"):
                saved.append(replay.saved.adopt(tree, row))
        replay.groups[group] = saved^
    var work = JsonTree()
    var swept = sweep(work, replay, "probe", catalog)
    assert_equal(len(swept[0]), 532)
    # Missing a pair at every grid must fail, including a pair outside the
    # issue's original 36 and with no sampled overlap.
    var issue = Set[String]()
    for pair in issue_595_pairs():
        issue.add(pair)
    for group in legacy_groups():
        var saved = replay.groups[group].copy()
        var index = 0
        while (
            replay.saved.text(replay.saved.item(saved[index], "pair_id"))
            in issue
        ):
            index += 1
        var fewer = saved.copy()
        _ = fewer.pop(index)
        replay.groups[group] = fewer^
        with assert_raises(contains="pair inventory"):
            var other = JsonTree()
            _ = sweep(other, replay, "probe", catalog)
        replay.groups[group] = saved^


def test_every_issue_pair_has_a_rule_and_a_class() raises:
    var pairs = issue_595_pairs()
    var distinct = Set[String]()
    var counts: List[Int] = [0, 0, 0]
    for pair in pairs:
        distinct.add(pair)
        var group = String(pair.split("/")[1])
        counts[0 if group == "bones" else (1 if group == "knee" else 2)] += 1
    assert_equal(len(distinct), 36)
    assert_equal(counts[0], 21)
    assert_equal(counts[1], 14)
    assert_equal(counts[2], 1)
    var known = classification()
    for pair in pairs:
        assert_true(pair in known, pair)
    var rule_names = _names(rules())
    var class_names = _names(classes())
    for entry in known.items():
        assert_true(entry.value.rule in rule_names)
        assert_true(entry.value.kind in class_names)
        assert_true(entry.value.note.byte_length() > 0)


def _grid(mut tree: JsonTree, overlap: Int, refined: Float64) raises -> Int:
    """Return a witness grid record."""
    var grid = tree.object()
    tree.set(grid, "overlap_samples", tree.integer(overlap))
    tree.set(grid, "refined_field_witness_m", tree.number(refined))
    return grid


def test_status_follows_samples_and_refinement() raises:
    var tree = JsonTree()
    var clear = _grid(tree, 0, 2e-9)
    assert_equal(status(tree, [clear, clear]), "no_common_interior_sampled")
    assert_equal(
        status(tree, [clear, _grid(tree, 1, 2e-9)]), "common_interior_found"
    )
    assert_equal(
        status(tree, [clear, _grid(tree, 0, -1e-9)]), "common_interior_found"
    )
    var bare = tree.object()
    tree.set(bare, "overlap_samples", tree.integer(0))
    assert_equal(status(tree, [bare]), "no_common_interior_sampled")


def _row(mut tree: JsonTree, first: String, second: String) raises -> Int:
    """Return a pair record with an identity."""
    var row = tree.object()
    tree.set_text(row, "first", first)
    tree.set_text(row, "second", second)
    tree.set_text(row, "pair_id", "x")
    return row


def test_witness_requests_name_supported_pairs_only() raises:
    var tree = JsonTree()
    var labels = Dict[String, Int]()
    labels["tibia"] = 1
    labels["foot/talus"] = 9
    var request = witness_request(
        tree, "bones", _row(tree, "foot/talus", "tibia"), labels
    )
    assert_equal(request[0], "pairs")
    assert_equal(request[1], "witness:1:9")
    request = witness_request(
        tree, "spine", _row(tree, "cervical/2", "cervical/3"), labels
    )
    assert_equal(request[0], "spine-witness")
    assert_equal(request[1], "cervical/2")
    for second in ["cervical/2/disc", "cervical/5", "thoracolumbar/0"]:
        with assert_raises(contains="no localization for spine pair x"):
            _ = witness_request(
                tree, "spine", _row(tree, "cervical/2", second), labels
            )
    with assert_raises(contains="no localization"):
        _ = witness_request(tree, "spine", _row(tree, "sacrum", "x"), labels)
    with assert_raises(contains="'femur'"):
        _ = witness_request(tree, "bones", _row(tree, "femur", "tibia"), labels)


def _witness(mut tree: JsonTree) raises -> Int:
    """Return a measured witness record."""
    var row = tree.object()
    tree.set(row, "samples", tree.integer(10))
    tree.set(row, "overlap_samples", tree.integer(1))
    tree.set(row, "overlap_volume_m3", tree.number(1e-7))
    tree.set(row, "signed_field_witness_m", tree.number(-1e-4))
    return row


def test_a_witness_pass_must_repeat_its_grid() raises:
    var tree = JsonTree()
    var row = _witness(tree)
    _ = check_witness(tree, tree.clone(row), row)
    var keys: List[String] = [
        "samples",
        "overlap_samples",
        "overlap_volume_m3",
        "signed_field_witness_m",
    ]
    var values: List[Int] = [
        tree.integer(9),
        tree.integer(0),
        tree.number(2e-7),
        tree.number(-2e-4),
    ]
    for index in range(len(keys)):
        var record = tree.clone(row)
        tree.set(record, keys[index], values[index])
        with assert_raises():
            _ = check_witness(tree, record, row)


def test_current_evidence_is_repaired() raises:
    var tree = JsonTree()
    var report = check_record(tree, tree.parse(Path(CURRENT).read_text()))
    for pair in tree.items(tree.item(report, "pairs")):
        assert_true(
            tree.is_text(
                tree.item(pair, "status"), "no_common_interior_sampled"
            ),
            tree.text(tree.item(pair, "pair_id")),
        )
    for counts in tree.items(
        tree.item(report, "pairs_with_sampled_common_interior")
    ):
        for group in legacy_groups():
            assert_true(tree.is_number(tree.item(counts, group), 0))


def test_unrepaired_localization_is_pinned_and_shows_each_issue_pair() raises:
    var tree = JsonTree()
    var report = check_before(tree, BEFORE)
    var pairs = Dict[String, Int]()
    for pair in tree.items(tree.item(report, "pairs")):
        pairs[tree.text(tree.item(pair, "pair_id"))] = pair
    for pair_id in issue_595_pairs():
        var pair = pairs[pair_id]
        assert_true(
            tree.is_text(tree.item(pair, "status"), "common_interior_found")
        )
        var five = tree.at(tree.item(pair, "grids"), 0)
        assert_true(tree.value(tree.item(five, "overlap_samples")) > 0)
        assert_true(tree.value(tree.item(five, "refined_field_witness_m")) < 0)
    # The 5 mm sample counts that #595 quotes.
    var quoted: List[Tuple[String, Int]] = [
        ("canonical/bones/foot/talus|tibia", 14),
        ("canonical/bones/foot/first_metatarsal|foot/medial_cuneiform", 17),
        ("canonical/knee/femur|knee/mcl", 28),
        ("canonical/knee/knee/lcl|tibia", 2),
        ("canonical/spine/cervical/2|cervical/3", 1),
    ]
    for entry in quoted:
        var five = tree.at(tree.item(pairs[entry[0]], "grids"), 0)
        assert_equal(
            Int(tree.value(tree.item(five, "overlap_samples"))), entry[1]
        )
    var text = Path("docs/validation/anatomy-overlaps-595.md").read_text()
    assert_true(text.find(BEFORE_SOURCE_SHA256) >= 0)


def _mutate(mut tree: JsonTree, report: Int, mutation: Int) raises:
    """Apply one evidence mutation."""
    var pairs = tree.item(report, "pairs")
    var first = tree.at(pairs, 0)
    if mutation == 0:
        tree.set(report, "steps_mm", tree.numbers([5.0, 3.0]))
    elif mutation == 1:
        _ = tree.drop_last(pairs)
    elif mutation == 2:
        tree.set_text(first, "status", "common_interior_found")
    elif mutation == 3:
        tree.set_text(first, "interface_rule", "allowance")
    elif mutation == 4:
        _ = tree.drop_last(tree.item(first, "grids"))
    elif mutation == 5:
        var grid = tree.at(tree.item(first, "grids"), 0)
        tree.set(grid, "overlap_samples", tree.integer(1))
    elif mutation == 6:
        var grid = tree.at(tree.item(first, "grids"), 0)
        tree.set_null(grid, "witness_point_m")


def test_changed_evidence_is_rejected() raises:
    var tree = JsonTree()
    var original = tree.parse(Path(CURRENT).read_text())
    for mutation in range(7):
        var report = tree.clone(original)
        _mutate(tree, report, mutation)
        with assert_raises():
            _ = check_record(tree, report)
    var root = Tree()
    root.write("before.json", Path(BEFORE).read_text() + " ")
    with assert_raises(contains="checksum"):
        var other = JsonTree()
        _ = check_before(other, root.root + "/before.json")
    root.close()


def test_the_evidence_binding_follows_source_and_tool() raises:
    # A small tree stands in for the repository: the evidence binds its
    # source digest and this tool's digest.
    var root = Tree()
    root.write("tools/anatomy_probe.mojo", "def main(): pass")
    root.write("tools/anatomy_validity.mojo", "report logic")
    root.write("tools/_imports.mojo", "resolver")
    root.write("tools/anatomy_overlaps.mojo", "overlap tool")
    root.write("docs/validation/anatomy-provenance.json", '{"parameters": []}')
    var tree = JsonTree()
    var report = tree.parse(Path(CURRENT).read_text())
    tree.set_text(
        tree.item(report, "build_provenance"),
        "source_sha256",
        source_digest(root.root),
    )
    tree.set_text(report, "tool_sha256", tool_sha256(root.root))
    root.write("current.json", tree.dumps(report))
    check_current(root.root + "/current.json", root.root)
    root.write("tools/anatomy_overlaps.mojo", "changed tool")
    with assert_raises(contains="stale tool"):
        check_current(root.root + "/current.json", root.root)
    root.write("tools/anatomy_validity.mojo", "changed logic")
    with assert_raises(contains="stale source"):
        check_current(root.root + "/current.json", root.root)
    root.close()


def test_current_evidence_matches_the_source_and_tool_bindings() raises:
    check_current(CURRENT, ".")


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
