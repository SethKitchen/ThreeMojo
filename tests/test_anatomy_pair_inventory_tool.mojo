# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Complete pair accounting and strict native/report protocol controls.

The catalog is synthetic: 134 named components with 2 cm boxes. A fixture
prober answers the catalog and batch requests.
"""

from std.collections import Set
from std.testing import (
    TestSuite,
    assert_equal,
    assert_false,
    assert_raises,
    assert_true,
)

from tests._anatomy_fixtures import (
    CatalogProbe,
    catalog,
    legacy_rows,
    pair_record,
)
from tools._json_tree import JsonTree
from tools.anatomy_validity import (
    Component,
    Num,
    PlanEntry,
    annotate_diagnostics,
    collect_pair_diagnostics,
    diagnostic_findings,
    pair_batches,
    pair_identity,
    pair_plan,
    validate_catalog,
    validate_pair_row,
)


def _components() raises -> List[Component]:
    """Return the validated synthetic catalog."""
    var tree = JsonTree()
    return validate_catalog(tree, catalog(tree))


def _change(mut tree: JsonTree, rows: List[Int], name: String) raises:
    """Apply one catalog mutation."""
    if name == "pop":
        return
    if name == "bool index":
        tree.set_flag(rows[0], "index", True)
    elif name == "same identity":
        tree.set(rows[1], "component_id", tree.item(rows[0], "component_id"))
    elif name == "same label":
        tree.set(rows[1], "label", tree.item(rows[0], "label"))
    elif name == "nan bound":
        var nan = Float64.MAX * 2 - Float64.MAX * 2
        tree.set(rows[0], "low_m", tree.numbers([nan, 0, 0]))
    elif name == "flat box":
        tree.set(rows[0], "high_m", tree.numbers([0, 0, 0]))
    elif name == "family":
        tree.set_text(rows[0], "family", "unknown")
    elif name == "list family":
        tree.set(rows[0], "family", tree.array())
    elif name == "identity":
        tree.set_text(rows[len(rows) - 1], "component_id", "foot/lymphatic/999")
    elif name == "leg translation":
        tree.set(rows[5], "translation_m", tree.numbers([1, 0, 0]))
    elif name == "ankle":
        tree.set(rows[len(rows) - 1], "translation_m", tree.numbers([1, 0, 0]))
    elif name == "text identity":
        tree.set(rows[0], "component_id", tree.integer(1))
    elif name == "empty label":
        tree.set_text(rows[0], "label", "")


def test_complete_catalog_contract_refuses_incomplete_or_ambiguous_fields() raises:
    assert_equal(len(_components()), 134)
    for name in [
        "pop",
        "bool index",
        "same identity",
        "same label",
        "nan bound",
        "flat box",
        "family",
        "list family",
        "identity",
        "leg translation",
        "ankle",
        "text identity",
        "empty label",
    ]:
        var tree = JsonTree()
        var rows = catalog(tree)
        if name == "pop":
            _ = rows.pop()
        _change(tree, rows, name)
        with assert_raises():
            _ = validate_catalog(tree, rows)


def _count(plan: List[PlanEntry], group: String) -> Int:
    """Return the number of plan entries of a legacy group."""
    var count = 0
    for entry in plan:
        if entry.legacy_group == group:
            count += 1
    return count


def test_all_8911_pairs_have_stable_identity_and_exact_class_accounting() raises:
    var rows = _components()
    var plan = pair_plan(rows, "full")
    assert_equal(len(plan), 134 * 133 // 2)
    var identities = Set[String]()
    for entry in plan:
        identities.add(entry.pair_id)
        assert_equal(entry.status, "checked")
    assert_equal(len(identities), len(plan))
    assert_equal(_count(plan, "bones"), 435)
    assert_equal(_count(plan, "knee"), 30)
    assert_equal(
        pair_identity(rows[0], rows[1]), pair_identity(rows[1], rows[0])
    )
    var renamed = rows[0].copy()
    renamed.label = "a new display name"
    assert_equal(
        pair_identity(rows[0], rows[1]), pair_identity(renamed, rows[1])
    )
    var representative = pair_plan(rows, "representative")
    var all_classes = Set[String]()
    for entry in plan:
        all_classes.add(entry.klass)
    var checked = Set[String]()
    var omitted = False
    for entry in representative:
        assert_true(entry.status != "unsupported")
        if entry.status == "checked":
            checked.add(entry.klass)
        else:
            omitted = True
            assert_equal(
                entry.reason, "representative run; executable in full scope"
            )
    assert_true(all_classes == checked)
    assert_true(omitted)
    with assert_raises(contains="unknown pair scope"):
        _ = pair_plan(rows, "unchecked")


def _selected(rows: List[Component]) raises -> Set[String]:
    """Return the representative leg muscle pairs."""
    var found = Set[String]()
    for entry in pair_plan(rows, "representative"):
        if (
            entry.status == "checked"
            and entry.klass == "muscle|muscle"
            and entry.first_id.startswith("leg/")
            and entry.second_id.startswith("leg/")
        ):
            found.add(entry.pair_id)
    return found^


def _one(identity: String) -> Set[String]:
    """Return a set of one identity."""
    var found = Set[String]()
    found.add(identity)
    return found^


def test_representative_selects_the_largest_intersection_not_the_first_pair() raises:
    var rows = _components()
    for index in range(len(rows)):
        rows[index].high = [0.001, 0.001, 0.001]
    var muscles = List[Int]()
    for index in range(len(rows)):
        if rows[index].family == "muscle" and rows[
            index
        ].component_id.startswith("leg/"):
            muscles.append(index)
    var a = muscles[0]
    var b = muscles[1]
    var c = muscles[2]
    rows[a].high = [0.06, 0.06, 0.06]
    rows[b].high = [0.02, 0.02, 0.02]
    rows[c].high = [0.04, 0.04, 0.04]
    # The later A/C pair intersects in a 4 cm cube; A/B has only 2 cm.
    assert_true(_selected(rows) == _one(pair_identity(rows[a], rows[c])))
    rows[b].high = [0.05, 0.05, 0.05]
    rows[c].high = [0.03, 0.03, 0.03]
    assert_true(_selected(rows) == _one(pair_identity(rows[a], rows[b])))
    # Equal maximum boxes retain the first pair in catalog order.
    rows[b].high = [0.04, 0.04, 0.04]
    rows[c].high = [0.04, 0.04, 0.04]
    assert_true(_selected(rows) == _one(pair_identity(rows[a], rows[b])))


def test_batches_are_exhaustive_bounded_and_never_drop_large_pairs() raises:
    var rows = _components()
    var plan = pair_plan(rows, "full")
    var batches = pair_batches(plan, rows, Num(5, True))
    var order = List[Int]()
    for batch in batches:
        assert_true(len(batch) <= 16)
        for index in batch:
            order.append(index)
    assert_equal(len(order), 8911 - 435 - 30)
    var expected = List[Int]()
    for index in range(len(plan)):
        if plan[index].legacy_group.byte_length() == 0:
            expected.append(index)
    assert_true(order == expected)
    # A Boolean step cannot reach this typed function at all.
    var nan = Float64.MAX * 2 - Float64.MAX * 2
    for step in [0.0, 1.0, 21.0, nan]:
        with assert_raises():
            _ = pair_batches(plan, rows, Num(step, False))
    for index in range(len(rows)):
        rows[index].high = [1.0, 1.0, 1.0]
    with assert_raises(contains="work budget"):
        _ = pair_batches(plan, rows, Num(2, True))


def _with(mut tree: JsonTree, base: Int, key: String, value: Int) raises -> Int:
    """Return a copy of a record with one member changed."""
    var row = tree.clone(base)
    tree.set(row, key, value)
    return row


def test_probe_protocol_retains_unknowns_and_refuses_invalid_evidence() raises:
    var rows = _components()
    var a = rows[0].copy()
    var b = rows[1].copy()
    var tree = JsonTree()
    var base = pair_record(tree, a.component_id, b.component_id)
    var valid = validate_pair_row(tree, tree.clone(base), a, b)
    assert_false(tree.flag(tree.item(valid, "allowlist_applied")))
    assert_true(
        tree.is_int(tree.item(valid, "allowed_positive_overlap_volume_m3"))
    )
    assert_equal(
        tree.value(tree.item(valid, "allowed_positive_overlap_volume_m3")), 0
    )
    var disjoint = b.copy()
    disjoint.low = [0.02, 0.0, 0.0]
    disjoint.high = [0.04, 0.02, 0.02]
    var empty = _with(tree, base, "samples", tree.integer(0))
    tree.set(empty, "signed_field_witness_m", tree.integer(0))
    var zero = validate_pair_row(tree, empty, a, disjoint)
    assert_true(tree.is_null(tree.item(zero, "signed_field_witness_m")))
    var inf = Float64.MAX * 2
    var changes = List[Tuple[String, Int]]()
    changes.append(("first_id", tree.string("missing")))
    changes.append(("samples", tree.boolean(True)))
    changes.append(("samples", tree.integer(2_000_001)))
    changes.append(("samples", tree.integer(-1)))
    changes.append(("overlap_samples", tree.integer(2)))
    changes.append(("bounds_gap_m", tree.integer(-1)))
    changes.append(("overlap_volume_m3", tree.number(inf)))
    changes.append(("overlap_volume_m3", tree.integer(1)))
    changes.append(("overlap_samples", tree.integer(1)))
    changes.append(("samples", tree.integer(0)))
    changes.append(("bounds_gap_m", tree.integer(1)))
    changes.append(("signed_field_witness_m", tree.number(-0.1)))
    for change in changes:
        with assert_raises():
            _ = validate_pair_row(
                tree, _with(tree, base, change[0], change[1]), a, b
            )
    var both = _with(tree, base, "samples", tree.integer(0))
    tree.set(both, "signed_field_witness_m", tree.integer(0))
    with assert_raises(contains="inconsistent"):
        _ = validate_pair_row(tree, both, a, b)
    var overlap = _with(tree, base, "overlap_samples", tree.integer(1))
    tree.set(overlap, "overlap_volume_m3", tree.number(1e-9))
    tree.set(overlap, "signed_field_witness_m", tree.number(-1e-4))
    var measured = validate_pair_row(tree, overlap, a, b)
    var groups = tree.object()
    var array = tree.array()
    tree.append(array, measured)
    tree.set(groups, "lower_limb_tissues", array)
    var findings = diagnostic_findings(tree, groups)
    assert_true(
        tree.is_text(
            tree.item(tree.at(findings, 0), "kind"),
            "unallowlisted_sampled_overlap",
        )
    )


def _legacy(mut tree: JsonTree) raises -> Int:
    """Return the annotated legacy bone and knee diagnostics."""
    var groups = tree.object()
    for group in ["bones", "knee"]:
        var array = tree.array()
        for row in legacy_rows(tree, group):
            tree.append(array, row)
        tree.set(groups, group, array)
    return annotate_diagnostics(tree, groups)


def test_collect_requires_every_measurement_and_preserves_legacy_ids() raises:
    for scope in ["full", "representative"]:
        var tree = JsonTree()
        var old = _legacy(tree)
        var original = tree.clone(old)
        var prober = CatalogProbe()
        var collected = collect_pair_diagnostics(
            tree, prober, "probe", Num(5, True), scope, old
        )
        assert_true(tree.equal(old, original))
        var inventory = collected[1]
        assert_equal(tree.value(tree.item(inventory, "total_pairs")), 8911)
        assert_equal(
            tree.flag(tree.item(inventory, "all_catalog_pairs_checked")),
            scope == "full",
        )
        var checked = 0
        for entry in tree.items(tree.item(inventory, "pairs")):
            if tree.is_text(tree.item(entry, "status"), "checked"):
                checked += 1
            var klass = tree.text(tree.item(entry, "class"))
            if klass == "bone|bone" or klass == "knee|knee":
                assert_true(tree.has(entry, "diagnostic_id"))
        assert_equal(checked, len(collected[0]) + 465)
        assert_equal(
            tree.length(
                tree.item(inventory, "positive_volume_attachment_allowances")
            ),
            0,
        )
        var classes = tree.item(inventory, "classes")
        var total = 0
        for counts in tree.items(classes):
            total += Int(tree.value(tree.item(counts, "checked")))
            total += Int(tree.value(tree.item(counts, "intentionally_omitted")))
        assert_equal(total, 8911)
    for failure in [
        "missing_legacy",
        "extra_legacy",
        "empty_batch",
        "wrong_identity",
    ]:
        var tree = JsonTree()
        var old = _legacy(tree)
        if failure == "missing_legacy":
            _ = tree.drop_last(tree.item(old, "bones"))
        elif failure == "extra_legacy":
            var extra = pair_record(tree, "leg/bone/femur", "foot/lymphatic/3")
            tree.set_text(extra, "pair_id", "extra")
            tree.append(tree.item(old, "bones"), extra)
        var prober = CatalogProbe(failure)
        with assert_raises():
            _ = collect_pair_diagnostics(
                tree, prober, "probe", Num(5, True), "representative", old
            )


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
