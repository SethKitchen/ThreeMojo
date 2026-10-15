# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Report guards, accounting composition, numerical labels and use gates.

No test runs the compiler or the native probe. A shell script stands in for
the compiler, and a fixture prober answers the probe requests.
"""

from std.math import sqrt
from std.os import makedirs
from std.pathlib import Path
from std.testing import (
    TestSuite,
    assert_almost_equal,
    assert_equal,
    assert_false,
    assert_raises,
    assert_true,
)

from tests._anatomy_fixtures import (
    batch_rows,
    catalog,
    legacy_rows,
    segment_row,
)
from tests._tree import Tree
from tools._json_tree import NOTHING, JsonTree, equal
from tools._process import run_program
from tools._sha256 import sha256_hex
from tools.anatomy_validity import (
    Num,
    Options,
    PAIR_FRAME,
    PINNED_TOOLCHAIN,
    Prober,
    SPINE_FRAME,
    annotate_diagnostics,
    build_flags,
    compose_segments,
    diagnostic_findings,
    file_sha256,
    finite,
    finite_tree,
    grid_steps,
    parse_options,
    prepare_probe,
    report,
    sampling_sensitivity,
    source_digest,
    tensor_checks,
    tensor_values,
    use_gate,
    uses,
    validate_segment,
)


def _nums(values: List[Float64]) -> List[Num]:
    """Return integral numbers."""
    var found = List[Num]()
    for value in values:
        found.append(Num(value, True))
    return found^


def test_non_finite_numbers_and_grid_requests() raises:
    var tree = JsonTree()
    var nan = Float64.MAX * 2 - Float64.MAX * 2
    var inf = Float64.MAX * 2
    for bad in [
        tree.boolean(True),
        tree.null(),
        tree.string("2"),
        tree.number(nan),
        tree.number(inf),
        tree.number(-inf),
        NOTHING,
    ]:
        with assert_raises(contains="fixture must be a finite number"):
            _ = finite(tree, bad, "fixture")
    var ordered = grid_steps(_nums([5, 20, 10]))
    assert_equal(len(ordered), 3)
    assert_equal(ordered[0].value, 20)
    assert_equal(ordered[1].value, 10)
    assert_equal(ordered[2].value, 5)
    assert_true(ordered[0].integral)
    var bad_lists: List[List[Float64]] = [
        [0, 10, 5],
        [1e-300, 10, 5],
        [inf, 10, 5],
        [nan, 10, 5],
        [21, 10, 5],
        [20, 10],
        [20, 10, 10],
        [2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12],
    ]
    for values in bad_lists:
        with assert_raises():
            _ = grid_steps(_nums(values))
    var nested = tree.object()
    var items = tree.array()
    tree.append(items, tree.number(nan))
    tree.set(nested, "nested", items)
    with assert_raises(contains="report number"):
        finite_tree(tree, nested)


def test_psd_checks_use_all_principal_minors() raises:
    assert_true(tensor_checks([0, 0, 0, 0, 0, 0]).positive_semidefinite)
    assert_true(tensor_checks([3, 4, 5, 1, 0.2, 0.1]).positive_semidefinite)
    var bad: List[List[Float64]] = [
        [-1, 1, 1, 0, 0, 0],
        [1, 1, 1, 2, 0, 0],
        [1, 1, 1, 0.9, 0.9, -0.9],
    ]
    for values in bad:
        assert_false(tensor_checks(values).positive_semidefinite)
    assert_false(tensor_checks([10, 1, 1, 0, 0, 0]).triangle_inequalities)
    # PSD inertia is not enough: this rotated tensor has principal moments
    # 2.8, .1, .1, although all coordinate diagonals equal 1.
    var impossible: List[Float64] = [1, 1, 1, 0.9, 0.9, 0.9]
    assert_true(tensor_checks(impossible).positive_semidefinite)
    assert_false(tensor_checks(impossible).triangle_inequalities)
    var tree = JsonTree()
    var row = segment_row(tree)
    tree.set(row, "inertia_kg_m2", tree.numbers(impossible))
    with assert_raises(contains="algebraic invariants"):
        _ = validate_segment(tree, row)
    with assert_raises(contains="six entries"):
        _ = tensor_checks([1, 2])
    with assert_raises(contains="six entries"):
        _ = tensor_values(tree, tree.numbers([1, 2]))
    with assert_raises(contains="has no len()"):
        _ = tensor_values(tree, tree.null())
    var keyed = tree.object()
    for key in ["a", "b", "c", "d", "e", "f"]:
        tree.set(keyed, key, tree.number(1))
    with assert_raises(contains="inertia must be a finite number"):
        _ = tensor_values(tree, keyed)


def _mutated(name: String) raises -> Tuple[JsonTree, Int]:
    """Return a segment record with one mutation."""
    var tree = JsonTree()
    var row = segment_row(tree)
    var accounts = tree.item(row, "regions")
    var muscle = tree.item(accounts, "muscle")
    if name == "record":
        tree.set_text(row, "record", "body")
    elif name == "segment":
        tree.set_text(row, "segment", "arm")
    elif name == "mass":
        tree.set(row, "mass_kg", tree.integer(0))
    elif name == "length":
        tree.set(row, "length_m", tree.integer(0))
    elif name == "step":
        tree.set(row, "step_m", tree.number(1e-30))
    elif name == "center":
        tree.set(row, "center_m", tree.numbers([0, 2, 0]))
    elif name == "low":
        tree.set(row, "low_m", tree.numbers([0, 1, 0]))
    elif name == "short center":
        tree.set(row, "center_m", tree.numbers([0]))
    elif name == "inertia":
        tree.set(row, "inertia_kg_m2", tree.numbers([-1, 1, 1, 0, 0, 0]))
    elif name == "missing region":
        _ = tree.pop(accounts, "dermis")
    elif name == "negative mass":
        tree.set(muscle, "mass_kg", tree.integer(-1))
    elif name == "extra mass":
        tree.set(muscle, "mass_kg", tree.integer(2))
    elif name == "volume":
        tree.set(muscle, "volume_m3", tree.integer(100))
    elif name == "region not an object":
        tree.set(accounts, "muscle", tree.array())
    return (tree^, row)


def test_region_accounting_must_be_complete_exclusive_and_finite() raises:
    var tree = JsonTree()
    assert_true(validate_segment(tree, segment_row(tree)).positive_semidefinite)
    for name in [
        "record",
        "segment",
        "mass",
        "length",
        "step",
        "center",
        "low",
        "short center",
        "inertia",
        "missing region",
        "negative mass",
        "extra mass",
        "volume",
        "region not an object",
    ]:
        var mutated = _mutated(name)
        with assert_raises():
            _ = validate_segment(mutated[0], mutated[1])


def _three(mut tree: JsonTree) raises -> List[Int]:
    """Return three adjoining cuts."""
    return [
        segment_row(tree, "foot", -1, 0),
        segment_row(tree, "shank", 0, 1),
        segment_row(tree, "thigh", 1, 2),
    ]


def test_composition_refuses_duplicates_gaps_and_overlap() raises:
    var tree = JsonTree()
    var rows = _three(tree)
    var total = compose_segments(tree, rows)
    assert_equal(tree.value(tree.item(total, "mass_kg")), 3)
    var center = tree.item(total, "center_m")
    assert_equal(tree.value(tree.at(center, 0)), 0)
    assert_equal(tree.value(tree.at(center, 1)), 0.5)
    assert_equal(tree.value(tree.at(center, 2)), 0)
    var inertia = tree.item(total, "inertia_kg_m2")
    assert_almost_equal(tree.value(tree.at(inertia, 0)), 2.3)
    assert_almost_equal(tree.value(tree.at(inertia, 1)), 0.06)
    assert_false(tree.flag(tree.item(total, "is_whole_body")))
    var bad: List[List[Int]] = [
        [rows[0], rows[1]],
        [rows[0], rows[1], rows[2], rows[0]],
        [rows[0], rows[0], rows[2]],
    ]
    for value in bad:
        with assert_raises(contains="exactly one thigh"):
            _ = compose_segments(tree, value)
    for delta in [-0.01, 0.01]:
        var other = JsonTree()
        var cuts = _three(other)
        var high = other.item(cuts[0], "high_m")
        other.replace(
            high, 1, other.number(other.value(other.at(high, 1)) + delta)
        )
        with assert_raises(contains="cut planes"):
            _ = compose_segments(other, cuts)
    var stepped = JsonTree()
    var cuts = _three(stepped)
    stepped.set(cuts[0], "step_m", stepped.number(0.01))
    with assert_raises(contains="same requested grid"):
        _ = compose_segments(stepped, cuts)
    var wider = JsonTree()
    cuts = _three(wider)
    var high = wider.item(cuts[0], "high_m")
    wider.replace(high, 0, wider.number(0.11))
    with assert_raises(contains="same limb envelope"):
        _ = compose_segments(wider, cuts)


def test_sensitivity_never_claims_an_error_bound() raises:
    var tree = JsonTree()
    var rows: List[Int] = [
        segment_row(tree, step=0.02),
        segment_row(tree, step=0.01),
        segment_row(tree, step=0.005),
    ]
    var result = sampling_sensitivity(tree, rows)
    assert_true(tree.is_null(tree.item(result, "error_bound")))
    assert_true(tree.is_null(tree.item(result, "observed_order")))
    assert_false(
        tree.flag(tree.item(result, "converged_to_physical_reference"))
    )
    var first = tree.at(tree.item(result, "comparisons"), 0)
    assert_equal(
        tree.value(tree.item(first, "tensor_delta_frobenius_kg_m2")), 0
    )
    var bad: List[List[Int]] = [
        [rows[0], rows[1]],
        [rows[2], rows[1], rows[0]],
        [rows[0], rows[0], rows[0]],
    ]
    for value in bad:
        with assert_raises():
            _ = sampling_sensitivity(tree, value)
    var tensor = tree.item(rows[0], "inertia_kg_m2")
    tree.replace(tensor, 3, tree.number(0.01))
    result = sampling_sensitivity(tree, rows)
    first = tree.at(tree.item(result, "comparisons"), 0)
    assert_almost_equal(
        tree.value(tree.item(first, "tensor_delta_frobenius_kg_m2")),
        sqrt(2.0) * 0.01,
    )
    # Ints stay ints, as Python's arithmetic keeps them.
    var whole = JsonTree()
    var integral = List[Int]()
    for step in [0.02, 0.01, 0.005]:
        var row = segment_row(whole, step=step)
        whole.set(row, "mass_kg", whole.integer(2))
        integral.append(row)
    result = sampling_sensitivity(whole, integral)
    first = whole.at(whole.item(result, "comparisons"), 0)
    assert_true(whole.is_int(whole.item(first, "mass_abs_delta_kg")))
    assert_true(whole.is_float(whole.item(first, "mass_relative_delta")))
    assert_true(
        whole.is_null(whole.item(first, "tensor_relative_frobenius_delta"))
        == False
    )


def test_only_template_and_fantasy_gates_are_enabled() raises:
    var tree = JsonTree()
    for use in uses():
        var gate = use_gate(tree, use)
        assert_equal(
            tree.flag(tree.item(gate, "permitted_as_labeled")),
            use == "template-estimate" or use == "game-fantasy",
        )
        assert_false(tree.flag(tree.item(gate, "engineering_validated")))
        assert_false(
            tree.flag(tree.item(gate, "clinical_or_safety_certification"))
        )
        assert_true(
            tree.is_null(tree.item(gate, "task_specific_acceptance_thresholds"))
        )
    with assert_raises(contains="unknown requested use"):
        _ = use_gate(tree, "certified")


def test_inventory_has_explicit_unknowns_and_bounded_allowlist() raises:
    var tree = JsonTree()
    var data = tree.parse(
        Path("docs/validation/anatomy-provenance.json").read_text()
    )
    for entry in tree.items(tree.item(data, "parameters")):
        for key in [
            "units",
            "classification",
            "supported_population",
            "empirical_range",
            "uncertainty",
            "unknowns",
        ]:
            assert_true(tree.has(entry, key), key)
        for source in tree.items(tree.item(entry, "source_files")):
            assert_true(Path(tree.text(source)).is_file(), tree.text(source))
    var found = False
    for rule in tree.items(tree.item(data, "intentional_overlap_allowlist")):
        if tree.is_text(
            tree.item(rule, "id"), "spine_endplane_boundary_contact"
        ):
            found = True
            assert_equal(
                tree.value(
                    tree.item(rule, "allowed_positive_overlap_volume_m3")
                ),
                0,
            )
    assert_true(found)
    assert_false(tree.flag(tree.item(data, "engineering_validated")))


def _pair(mut tree: JsonTree, first: String, second: String) raises -> Int:
    """Return a legacy pair record with two sampled hits."""
    var row = tree.object()
    tree.set_text(row, "record", "pair")
    tree.set_text(row, "first", first)
    tree.set_text(row, "second", second)
    tree.set(row, "overlap_samples", tree.integer(2))
    return row


def _group(mut tree: JsonTree, name: String, rows: List[Int]) raises -> Int:
    """Return a diagnostics object with one group."""
    var groups = tree.object()
    var array = tree.array()
    for row in rows:
        tree.append(array, row)
    tree.set(groups, name, array)
    return groups


def _endplane(mut tree: JsonTree, body: String) raises -> Int:
    """Return an endplane record."""
    var row = tree.object()
    tree.set_text(row, "record", "endplane")
    tree.set_text(row, "body", body)
    return row


def test_pair_ids_are_stable_and_never_exempt_positive_overlap() raises:
    var tree = JsonTree()
    var forward = _pair(tree, "foot/first metatarsal", "foot/medial cuneiform")
    var backward = _pair(tree, "foot/medial cuneiform", "foot/first metatarsal")
    _ = annotate_diagnostics(tree, _group(tree, "bones", [forward]))
    _ = annotate_diagnostics(tree, _group(tree, "bones", [backward]))
    assert_equal(
        tree.text(tree.item(forward, "pair_id")),
        tree.text(tree.item(backward, "pair_id")),
    )
    assert_equal(
        tree.text(tree.item(forward, "pair_id")),
        "canonical/bones/foot/first_metatarsal|foot/medial_cuneiform",
    )
    assert_false(tree.flag(tree.item(forward, "allowlist_applied")))
    assert_equal(tree.text(tree.item(forward, "frame_id")), PAIR_FRAME)
    var empty = _pair(tree, "a", "b")
    tree.set(empty, "samples", tree.integer(0))
    tree.set(empty, "overlap_samples", tree.integer(0))
    tree.set(empty, "signed_field_witness_m", tree.integer(0))
    _ = annotate_diagnostics(tree, _group(tree, "bones", [empty]))
    assert_true(tree.is_null(tree.item(empty, "signed_field_witness_m")))
    with assert_raises(contains="duplicate"):
        _ = annotate_diagnostics(
            tree,
            _group(
                tree, "bones", [_pair(tree, "a", "b"), _pair(tree, "a", "b")]
            ),
        )
    var unknown = tree.object()
    tree.set_text(unknown, "record", "unknown")
    with assert_raises(contains="unknown diagnostic record"):
        _ = annotate_diagnostics(tree, _group(tree, "bones", [unknown]))
    var end = _endplane(tree, "cervical/2")
    _ = annotate_diagnostics(tree, _group(tree, "spine", [end]))
    assert_equal(
        tree.text(tree.item(end, "endplane_id")),
        "canonical/spine/endplane/cervical/2",
    )
    assert_equal(tree.text(tree.item(end, "frame_id")), SPINE_FRAME)
    assert_true(tree.flag(tree.item(end, "next_body_sampled")))
    var lower = _endplane(tree, "thoracolumbar/16")
    tree.set(lower, "next_body_outside_field_m", tree.number(0.0))
    _ = annotate_diagnostics(tree, _group(tree, "spine", [lower]))
    assert_false(tree.flag(tree.item(lower, "next_body_sampled")))
    assert_true(tree.is_null(tree.item(lower, "next_body_outside_field_m")))
    var placeholder = _endplane(tree, "thoracolumbar/16")
    tree.set(placeholder, "next_body_outside_field_m", tree.number(0.1))
    with assert_raises(contains="placeholder"):
        _ = annotate_diagnostics(tree, _group(tree, "spine", [placeholder]))


def _end(mut tree: JsonTree) raises -> Int:
    """Return an endplane record that passes every check."""
    var row = _endplane(tree, "cervical/2")
    tree.set(row, "disc_gap_m", tree.number(0.001))
    tree.set(row, "body_disc_endplane_error_m", tree.number(0.0))
    tree.set(row, "next_body_disc_endplane_error_m", tree.number(0.0))
    for key in [
        "body_outside_field_m",
        "next_body_outside_field_m",
        "disc_outside_upper_field_m",
        "disc_outside_lower_field_m",
    ]:
        tree.set(row, key, tree.number(0.0001))
    tree.set_flag(row, "next_body_sampled", True)
    return row


def test_unallowlisted_overlap_and_incompatible_endplanes_are_visible() raises:
    var tree = JsonTree()
    var pair = _pair(tree, "bone", "disc")
    tree.set(pair, "overlap_samples", tree.integer(1))
    tree.set(pair, "overlap_volume_m3", tree.number(1e-9))
    assert_equal(
        tree.length(
            diagnostic_findings(tree, _group(tree, "spine", [_end(tree)]))
        ),
        0,
    )
    var findings = diagnostic_findings(tree, _group(tree, "spine", [pair]))
    assert_equal(
        tree.text(tree.item(tree.at(findings, 0), "kind")),
        "unallowlisted_sampled_overlap",
    )
    assert_true(tree.is_null(tree.item(tree.at(findings, 0), "pair_id")))
    for key in [
        "disc_gap_m",
        "body_outside_field_m",
        "next_body_outside_field_m",
        "disc_outside_upper_field_m",
        "disc_outside_lower_field_m",
    ]:
        var bad = _end(tree)
        tree.set(bad, key, tree.number(-0.001))
        var found = diagnostic_findings(tree, _group(tree, "spine", [bad]))
        assert_equal(tree.length(found), 1, key)
        assert_equal(
            tree.text(tree.item(tree.at(found, 0), "kind")),
            "incompatible_endplanes",
        )
    for key in [
        "body_disc_endplane_error_m",
        "next_body_disc_endplane_error_m",
    ]:
        var bad = _end(tree)
        tree.set(bad, key, tree.number(1e-3))
        assert_equal(
            tree.length(
                diagnostic_findings(tree, _group(tree, "spine", [bad]))
            ),
            1,
        )
    var lower = _end(tree)
    tree.set_text(lower, "body", "thoracolumbar/16")
    tree.set_null(lower, "next_body_outside_field_m")
    tree.set_flag(lower, "next_body_sampled", False)
    assert_equal(
        tree.length(diagnostic_findings(tree, _group(tree, "spine", [lower]))),
        0,
    )
    var missing = tree.object()
    tree.set_text(missing, "record", "missing")
    with assert_raises(contains="unknown diagnostic record"):
        _ = diagnostic_findings(tree, _group(tree, "spine", [missing]))


def _fixture(logic: String) raises -> Tree:
    """Return a minimal bindable tree."""
    var tree = Tree()
    tree.write("tools/anatomy_validity.mojo", logic)
    tree.write("tools/_imports.mojo", "resolver")
    tree.write("tools/anatomy_probe.mojo", "def main(): pass")
    tree.write("docs/validation/anatomy-provenance.json", '{"parameters": []}')
    return tree^


comptime FAKE_MOJO = """#!/bin/sh
if [ "$1" = "--version" ]; then echo 'Mojo 1.1.0 (8189361e)'; exit 0; fi
pwd > .build-cwd
for word in "$@"; do printf '%s\\n' "$word"; done > .build-args
eval "out=\\${$#}"
printf 'fixture binary' > "$out"
"""
"""A compiler stand-in: it reports the pinned version and writes a probe."""


def test_probe_build_uses_relative_pinned_invocation() raises:
    var files = _fixture("fixture")
    files.write("fake-mojo", FAKE_MOJO)
    _ = run_program(["chmod", "+x", files.root + "/fake-mojo"], 10)
    var tree = JsonTree()
    var record = prepare_probe(
        tree,
        files.root,
        files.root + "/.cache/probe",
        files.root + "/fake-mojo",
        True,
    )
    assert_equal(
        files.read(".build-args"),
        (
            "build\n--Werror\n--num-threads\n1\n-I\n.\ntools/anatomy_probe.mojo"
            "\n-o\n.cache/probe\n"
        ),
    )
    assert_equal(files.read(".build-cwd"), files.root + "\n")
    assert_equal(files.read(".cache/probe"), "fixture binary")
    assert_true(
        tree.is_text(
            tree.item(record, "source_sha256"), source_digest(files.root)
        )
    )
    assert_equal(
        tree.dumps(tree.item(record, "flags"), False),
        '["--Werror", "--num-threads", "1"]',
    )
    assert_equal(
        files.read(".cache/probe.provenance.json"), tree.dumps(record) + "\n"
    )
    # A compiler of another version is refused.
    files.write("old-mojo", "#!/bin/sh\necho 'Mojo 1.0.0 (old)'\n")
    _ = run_program(["chmod", "+x", files.root + "/old-mojo"], 10)
    with assert_raises(contains="pinned Mojo 1.1.0"):
        _ = prepare_probe(
            tree, files.root, files.root + "/p", files.root + "/old-mojo", True
        )
    with assert_raises(contains="No such file or directory"):
        _ = prepare_probe(
            tree, files.root, files.root + "/p", files.root + "/missing", True
        )
    files.close()


def _record(
    mut tree: JsonTree,
    toolchain: String,
    flags: Int,
    root: String,
    probe: String,
) raises -> Int:
    """Return a provenance record."""
    var record = tree.object()
    if toolchain != "-":
        tree.set_text(record, "toolchain", toolchain)
    else:
        tree.set_null(record, "toolchain")
    tree.set(record, "flags", flags)
    tree.set_text(record, "source_sha256", source_digest(root))
    tree.set_text(record, "binary_sha256", file_sha256(probe))
    return record


def test_source_bound_probe_rejects_missing_or_stale_evidence() raises:
    var files = _fixture("one")
    var probe = files.root + "/probe"
    var tree = JsonTree()
    with assert_raises(contains="build"):
        _ = prepare_probe(tree, files.root, probe, "mojo", False)
    files.write("probe", "binary")
    files.write("probe.provenance.json", "{}")
    with assert_raises(contains="exact pinned compiler"):
        _ = prepare_probe(tree, files.root, probe, "mojo", False)
    var good = _record(
        tree, PINNED_TOOLCHAIN, tree.strings(build_flags()), files.root, probe
    )
    files.write("probe.provenance.json", tree.dumps(good, False))
    var read = prepare_probe(tree, files.root, probe, "mojo", False)
    assert_true(tree.equal(read, good))
    var cases = List[Tuple[String, Int]]()
    cases.append(("-", tree.strings(build_flags())))
    cases.append(("Mojo 1.1.0 unknown", tree.strings(build_flags())))
    cases.append((PINNED_TOOLCHAIN, tree.array()))
    cases.append((PINNED_TOOLCHAIN, tree.null()))
    cases.append((PINNED_TOOLCHAIN, tree.strings(["--Werror"])))
    for entry in cases:
        var bad = _record(tree, entry[0], entry[1], files.root, probe)
        files.write("probe.provenance.json", tree.dumps(bad, False))
        with assert_raises(contains="exact pinned compiler"):
            _ = prepare_probe(tree, files.root, probe, "mojo", False)
    files.write("probe.provenance.json", tree.dumps(good, False))
    files.write("tools/anatomy_validity.mojo", "two")
    with assert_raises(contains="stale"):
        _ = prepare_probe(tree, files.root, probe, "mojo", False)
    files.close()


struct ReportProbe(Prober):
    """Answer every report request, and change one input at one stage."""

    var root: String
    """The fixture root."""
    var stage: String
    """The probe mode at which the input changes."""
    var mutation: String
    """The change."""
    var provenance: String
    """The provenance text, to rewrite with a newline."""

    def __init__(
        out self,
        root: String,
        stage: String,
        mutation: String,
        provenance: String,
    ):
        """Answer requests for one fixture.

        Args:
            root: The fixture root.
            stage: The mode at which the input changes.
            mutation: The change.
            provenance: The provenance text.
        """
        self.root = root
        self.stage = stage
        self.mutation = mutation
        self.provenance = provenance

    def _mutate(self) raises:
        """Change the input."""
        var root = self.root
        if self.mutation == "source":
            Path(root + "/bound.mojo").write_text("def changed(): pass")
        elif self.mutation == "new_source":
            # Beside the probe, it shadows the bound module.
            Path(root + "/tools/bound.mojo").write_text("def fixture(): pass")
        elif self.mutation == "removed_source":
            _ = run_program(["rm", "-f", root + "/bound.mojo"], 10)
        elif self.mutation == "logic":
            Path(root + "/tools/anatomy_validity.mojo").write_text(
                "changed logic"
            )
        elif self.mutation == "inventory":
            Path(root + "/docs/validation/anatomy-provenance.json").write_text(
                '{"parameters": [{"source_files": ["bound.mojo"]}],'
                ' "changed": true}'
            )
        elif self.mutation == "binary":
            Path(root + "/probe").write_text("changed binary")
        elif self.mutation == "metadata":
            # Even a semantically equal sidecar edit is an observed
            # replacement of bound evidence.
            Path(root + "/probe.provenance.json").write_text(
                self.provenance + "\n"
            )

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
            mode: The probe mode.
            part: The part or request.
            step: The grid step, in millimeters.

        Returns:
            The records.

        Raises:
            Error: Never for a known mode.
        """
        if mode == self.stage:
            self._mutate()
        if mode == "controls":
            var row = tree.object()
            tree.set_text(row, "record", "controls")
            tree.set_flag(row, "passed", True)
            return [row]
        if mode == "segment":
            var low = -1.0 if part == "foot" else (
                0.0 if part == "shank" else 1.0
            )
            return [segment_row(tree, part, low, low + 1, step.value / 1000)]
        if mode == "bones" or mode == "knee":
            return legacy_rows(tree, mode)
        if mode == "pairs":
            if part == "catalog":
                return catalog(tree)
            return batch_rows(tree, part)
        return List[Int]()


def _report_case(stage: String, mutation: String) raises:
    """Run the report once with one change at one stage."""
    var files = Tree()
    files.write("tools/anatomy_validity.mojo", "report fixture")
    files.write("tools/_imports.mojo", "resolver")
    files.write(
        "tools/anatomy_probe.mojo",
        "from bound import fixture\n\n\ndef main():\n    fixture()\n",
    )
    files.write("bound.mojo", "def fixture(): pass")
    var inventory_text = String(
        '{"parameters": [{"source_files": ["bound.mojo"]}]}'
    )
    files.write("docs/validation/anatomy-provenance.json", inventory_text)
    files.write("probe", "initial binary")
    var tree = JsonTree()
    var provenance = tree.object()
    tree.set_text(provenance, "toolchain", PINNED_TOOLCHAIN)
    tree.set(provenance, "flags", tree.strings(build_flags()))
    tree.set_text(provenance, "source_sha256", source_digest(files.root))
    tree.set_text(
        provenance, "binary_sha256", file_sha256(files.root + "/probe")
    )
    var provenance_text = tree.dumps(provenance, False)
    files.write("probe.provenance.json", provenance_text)
    var options = Options()
    options.probe = files.root + "/probe"
    options.mojo = "mojo"
    var prober = ReportProbe(files.root, stage, mutation, provenance_text)
    var output = JsonTree()
    if mutation == "none":
        var result = report(output, prober, options, files.root)
        assert_true(
            equal(
                output,
                output.item(result, "build_provenance"),
                tree,
                provenance,
            )
        )
        var expected = JsonTree()
        var inventory = expected.parse(inventory_text)
        assert_true(
            equal(
                output,
                output.item(result, "provenance_inventory"),
                expected,
                inventory,
            )
        )
        assert_true(
            output.is_text(
                output.path(result, ["source_file_sha256", "bound.mojo"]),
                file_sha256(files.root + "/bound.mojo"),
            )
        )
        assert_true(
            output.is_text(
                output.item(result, "inventory_sha256"),
                file_sha256(
                    files.root + "/docs/validation/anatomy-provenance.json"
                ),
            )
        )
        assert_true(
            output.is_text(
                output.item(result, "report_logic_sha256"),
                file_sha256(files.root + "/tools/anatomy_validity.mojo"),
            )
        )
        var pairs = output.item(result, "pair_inventory")
        assert_equal(output.value(output.item(pairs, "total_pairs")), 8911)
    else:
        with assert_raises(contains="inputs changed during execution"):
            _ = report(output, prober, options, files.root)
    files.close()


def test_report_rejects_observed_input_changes_at_the_controls() raises:
    # Exercise the real report and provenance path without compiling or
    # executing a native probe. Change the inputs at the first probe.
    for mutation in [
        "none",
        "source",
        "new_source",
        "removed_source",
        "logic",
        "inventory",
        "binary",
        "metadata",
    ]:
        _report_case("controls", mutation)


def test_report_rejects_observed_input_changes_at_the_spine() raises:
    # Change the inputs at the last diagnostic probe.
    for mutation in [
        "source",
        "new_source",
        "removed_source",
        "logic",
        "inventory",
        "binary",
        "metadata",
    ]:
        _report_case("spine", mutation)


def test_report_refuses_bad_requests_before_any_probe() raises:
    var options = Options()
    options.output = "unused"
    var prober = ReportProbe("/nonexistent", "", "none", "")
    var tree = JsonTree()
    options.steps_mm = _nums([1, 2, 3])
    with assert_raises(contains="between 2 and 20 mm"):
        _ = report(tree, prober, options, "/nonexistent")
    options.steps_mm = _nums([20, 10, 5])
    options.stature_m = 3
    with assert_raises(contains="software range"):
        _ = report(tree, prober, options, "/nonexistent")


def test_the_command_line_follows_argparse() raises:
    var parsed = parse_options(["--output", "x.json"])
    assert_equal(parsed.status, 0)
    assert_equal(parsed.output, "x.json")
    assert_equal(len(parsed.steps_mm), 3)
    assert_true(parsed.steps_mm[0].integral)
    parsed = parse_options(
        [
            "--out=x",
            "--steps-mm",
            "16",
            "8",
            "4",
            "--sex",
            "female",
            "--build",
            "--pair",
            "representative",
            "--stature-m",
            "1.63",
        ]
    )
    assert_equal(parsed.status, 0)
    assert_equal(parsed.output, "x")
    assert_true(parsed.build)
    assert_equal(parsed.sex, "female")
    assert_equal(parsed.pair_scope, "representative")
    assert_equal(parsed.stature_m, 1.63)
    assert_false(parsed.steps_mm[0].integral)
    assert_equal(parsed.steps_mm[2].value, 4)
    var arguments: List[List[String]] = [
        ["--sex", "x", "--output", "y"],
        ["--steps-mm", "a", "--output", "y"],
        ["--steps-mm"],
        List[String](),
        ["--output", "a", "b"],
        ["--s", "1", "--output", "y"],
        ["--output"],
    ]
    var messages: List[String] = [
        "argument --sex: invalid choice: 'x' (choose from 'male', 'female')",
        "argument --steps-mm: invalid float value: 'a'",
        "argument --steps-mm: expected at least one argument",
        "the following arguments are required: --output",
        "unrecognized arguments: b",
        (
            "ambiguous option: --s could match --steps-mm, --stature-m,"
            " --sex, --side"
        ),
        "argument --output: expected one argument",
    ]
    for index in range(len(arguments)):
        parsed = parse_options(arguments[index])
        assert_equal(parsed.status, 2)
        assert_true(parsed.message.startswith("usage: anatomy_validity.mojo"))
        assert_true(
            parsed.message.endswith(
                "anatomy_validity.mojo: error: " + messages[index] + "\n"
            ),
            parsed.message,
        )
    parsed = parse_options(["-h"])
    assert_equal(parsed.status, -1)
    assert_true(parsed.message.find("--pair-scope {full,representative}") > 0)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
