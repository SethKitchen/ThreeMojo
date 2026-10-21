# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Immutable parts, source-bound report integration and unsupported paths.

These tests port the Python tool's tests. The expected texts and digests
are the Python tool's own outputs for the same inputs, so a pass shows
byte-identical snapshots, derivatives and command-line text.
"""

from std.os import listdir, remove, rmdir
from std.pathlib import Path
from std.tempfile import mkdtemp
from std.testing import (
    TestSuite,
    assert_equal,
    assert_false,
    assert_raises,
    assert_true,
)

from tools._python_json import (
    MISSING,
    PY_DICT,
    PY_LIST,
    PY_NONE,
    PyJson,
    dumps_canonical,
    loads,
    py_equal,
)
from tools.humanoid_fidelity import (
    DESCRIPTION,
    Frame,
    Y_UP,
    Y_UP_TEXT,
    Z_UP,
    Z_UP_TEXT,
    _write_snapshot,
    adapt_part,
    canonical_bytes,
    digest,
    finite,
    frame_rotation,
    identity,
    make_snapshot,
    read_snapshot,
    report_properties,
    rotation,
    run,
    transform_inertia,
    transform_point,
    validate_derivative,
    validate_snapshot,
    vector,
    visual_derivative,
    write_snapshot,
    y_to_z,
    z_to_y,
)

comptime EVIDENCE = "docs/validation/anatomy-template-report.json"
"""The current anatomy producer's report."""
comptime LABELS = [
    "dermis",
    "cortical_apparent",
    "trabecular_apparent",
    "marrow_fat_proxy",
    "muscle",
    "tendon",
    "unresolved_fat_proxy",
]
"""The seven exclusive accounting regions of the synthetic report."""
comptime SNAPSHOT_DIGEST = (
    "b052384e6dd218801b3c52bffe61d57b79ed420b74ee792bbc83b102715b7ea1"
)
"""The Python tool's digest of the synthetic snapshot."""
comptime HELD_DIGEST = (
    "1218804c983bcddfbc256181798ebfd4765ececf2e5fdf07b67d66d3bcdb9522"
)
"""The Python tool's digest of the snapshot that holds the evidence."""


# --- Fixtures -------------------------------------------------------------------------


def _report_text() -> String:
    """Return the synthetic schema-version-1 report as JSON text."""
    var labels = materialize[LABELS]()
    var quoted = List[String]()
    for label in labels:
        quoted.append('"' + String(label) + '"')
    var segments = List[String]()
    for name in ["thigh", "shank", "foot"]:
        var grids = List[String]()
        for step in ["0.02", "0.01", "0.005"]:
            var regions = List[String]()
            for label in labels:
                var dermis = String(label) == "dermis"
                regions.append(
                    '"'
                    + String(label)
                    + '": {"mass_kg": '
                    + ("2" if dermis else "0")
                    + ', "volume_m3": '
                    + ("0.001" if dermis else "0")
                    + "}"
                )
            grids.append(
                '{"record": "segment", "segment": "'
                + name
                + '", "mass_kg": 2, "center_m": [1, 2, 3], "inertia_kg_m2":'
                ' [3, 4, 5, 0.2, 0.3, 0.4], "step_m": '
                + step
                + ', "length_m": 1, "low_m": [0, 0, 0], "high_m": [4, 4, 4],'
                ' "regions": {'
                + ", ".join(regions)
                + "}}"
            )
        segments.append(
            '"'
            + name
            + '": {"grids": ['
            + ", ".join(grids)
            + '], "sampling_sensitivity": {}}'
        )
    return (
        '{"schema_version": 1, "result_label": "template estimate",'
        ' "build_provenance": {"synthetic": true}, "source_file_sha256": {},'
        ' "report_logic_sha256": "synthetic-control", "inventory_sha256":'
        ' "synthetic-control", "follow_ups": [], "spec": {}, "controls": {},'
        ' "composition": {}, "diagnostics": {}, "geometry_findings": [],'
        ' "provenance_inventory": {}, "segments": {'
        + ", ".join(segments)
        + '}, "gate": {"engineering_validated": false}, "accounting":'
        ' {"exclusive_density_precedence": ['
        + ", ".join(quoted)
        + ']}, "tensor_convention": {"order": ["xx", "yy", "zz", "xy", "xz",'
        ' "yz"], "reference": "center of mass", "off_diagonal": "negative'
        ' products of inertia"}, "diagnostic_limits": {}, "frame": {"origin":'
        ' "tibiofemoral joint line", "x": "body-right", "y": "proximal", "z":'
        ' "anterior"}}'
    )


def _report() raises -> PyJson:
    """Return the synthetic schema-version-1 report."""
    return PyJson.parse(_report_text())


comptime PARTS = (
    '[{"part_id": "synthetic/triangle", "tissue_label":'
    ' "unresolved_fat_proxy", "frame": "'
    + Y_UP_TEXT
    + '", "origin_label": "synthetic origin", "vertices_m": [[0, 0, 0], [1,'
    ' 0, 0], [0, 1, 0]], "triangles": [[0, 1, 2]], "physical_properties":'
    ' {"mass_kg": 2, "center_m": [0, 0, 0], "frame": "'
    + Y_UP_TEXT
    + '", "origin_label": "synthetic origin", "inertia_kg_m2": [3, 4, 5, 0.2,'
    ' 0.3, 0.4], "tensor_reference": "center-of-mass",'
    ' "source_report_record": "synthetic-control"}}]'
)
"""The synthetic canonical parts."""


def _snapshot() raises -> PyJson:
    """Return the synthetic snapshot."""
    return make_snapshot(
        PyJson.parse('{"stature_m": 1.8288}'),
        "synthetic-canonical-v1",
        PyJson.parse(PARTS),
        _report(),
        "synthetic origin",
    )


def _part() raises -> PyJson:
    """Return the synthetic snapshot's first part."""
    var snapshot = _snapshot()
    return snapshot.subtree(_at(snapshot, ["parts", "0"]))


def _evidence() raises -> PyJson:
    """Return the current producer's report."""
    return loads(Path(EVIDENCE).read_bytes())


def _at(doc: PyJson, path: List[String]) raises -> Int:
    """Return the node at a path of keys and list positions."""
    var node = doc.root
    for step in path:
        if doc.kind(node) == PY_LIST:
            node = doc.item(node, Int(step))
        else:
            node = doc.at(node, step)
    return node


def _put(mut doc: PyJson, path: List[String], text: String) raises:
    """Set the value at a path to a JSON value."""
    var parent = path.copy()
    var last = parent.pop()
    var holder = _at(doc, parent)
    var value = doc.adopt(PyJson.parse(text), PyJson.parse(text).root)
    if doc.kind(holder) == PY_LIST:
        doc.set_item(holder, Int(last), value)
    else:
        doc.set(holder, last, value)


def _drop(mut doc: PyJson, path: List[String]) raises:
    """Delete the member at a path."""
    var parent = path.copy()
    var last = parent.pop()
    doc.remove(_at(doc, parent), last)


def _text(doc: PyJson) raises -> String:
    """Return the canonical text of a document."""
    return dumps_canonical(doc, doc.root)


def _same(doc: PyJson, text: String) raises -> Bool:
    """Return whether a document equals JSON text, as Python's `==` says."""
    var other = PyJson.parse(text)
    return py_equal(doc, doc.root, other, other.root)


def _equal_nodes(a: PyJson, x: Int, b: PyJson, y: Int) raises -> Bool:
    """Return Python's `==` of two nodes."""
    return py_equal(a, x, b, y)


struct Scratch(Movable):
    """A temporary directory, removed with its files."""

    var path: String
    """The directory."""

    def __init__(out self) raises:
        """Make the directory."""
        self.path = mkdtemp(prefix="threemojo-fidelity-")

    def keep(self):
        """Keep the directory to this point; a test calls this last."""
        pass

    def __deinit__(deinit self):
        """Remove the directory and its files."""
        try:
            for name in listdir(self.path):
                remove(self.path + "/" + name)
            rmdir(self.path)
        except:
            pass


# --- The current anatomy report ----------------------------------------------------------


def test_current_producer_sampled_properties_are_copied_without_recalculation() raises:
    var evidence = _evidence()
    assert_equal(
        evidence.text(evidence.get(evidence.root, "schema_version")), "2"
    )
    var before = _text(evidence)
    var digests: List[String] = [
        "2ba875a081dd0800504c694df2092724790bf3a5de32e7cb7eb9aeec10a766f8",
        "dc7f05ce558828da903399d3f965e18634611d281ce73d36a41fa2daeb47178f",
        "1e0f1cac220a6823905c9da381289e824ac822b76a43a88c3973c36294b39ee4",
        "477b22e2d1ea444fe3eaf264ec76c1cb487903ef407331d988983a336e5186c3",
        "d7c0147412090f7e103e6030515c92799531ca93eb6622af0dad03497c41f33f",
        "ba5745aafc34c66f222fc3c5f95ae11328de88f425780ce845030b174c3c01d3",
        "88b04a679f5bb9df64bbd8880b6c15fb3b323506acf97eff10837b09fbd3014e",
        "d230b766176ce674deb61e60bf0dc2a42539ed5df0c06b0f48797de74e3a0dcd",
        "abc949ac3e79f2e135aa8a66493c6bebff85e873c3700c7b1183bed5532a6038",
    ]
    var frame = _at(evidence, ["frame"])
    var count = 0
    for segment in ["thigh", "shank", "foot"]:
        for index in range(3):
            var row = _at(
                evidence, ["segments", segment, "grids", String(index)]
            )
            var copied = report_properties(evidence, segment, index)
            assert_equal(digest(copied), digests[count])
            count += 1
            for key in [
                "mass_kg",
                "center_m",
                "inertia_kg_m2",
                "regions",
                "step_m",
            ]:
                assert_true(
                    _equal_nodes(
                        copied,
                        copied.at(copied.root, key),
                        evidence,
                        evidence.at(row, key),
                    ),
                    key,
                )
            assert_equal(copied.text(_at(copied, ["frame"])), Y_UP_TEXT)
            assert_true(
                _equal_nodes(
                    copied,
                    _at(copied, ["origin_label"]),
                    evidence,
                    evidence.at(frame, "origin"),
                )
            )
            assert_true(
                _equal_nodes(
                    copied,
                    _at(copied, ["source_report_frame"]),
                    evidence,
                    frame,
                )
            )
            assert_equal(
                copied.text(_at(copied, ["tensor_reference"])), "center-of-mass"
            )
            assert_equal(
                copied.text(_at(copied, ["source_report_record"])),
                "segments/" + segment + "/grids/" + String(index),
            )
            _put(copied, ["regions", "dermis", "mass_kg"], "-1")
            _put(copied, ["center_m", "0"], "999")
    assert_equal(_text(evidence), before)


def test_current_report_snapshot_retains_all_evidence_and_unsupported_mappings() raises:
    var evidence = _evidence()
    var part = _part()
    # This supplied triangle has no claimed correspondence to a sampled
    # region. Attaching the report must not invent physical properties.
    _put(part, ["physical_properties"], "null")
    var parts = PyJson()
    parts.root = parts.new_list()
    parts.append(parts.root, parts.adopt(part, part.root))
    var held = make_snapshot(
        evidence.subtree(_at(evidence, ["spec"])),
        "current-producer-control",
        parts,
        evidence,
        "synthetic origin",
    )
    assert_equal(held.text(_at(held, ["schema_version"])), "1")
    assert_true(
        _equal_nodes(
            held,
            _at(held, ["canonical_validity_report"]),
            evidence,
            evidence.root,
        )
    )
    assert_false(held.flag(_at(held, ["engineering_validated"])))
    assert_equal(
        held.kind(_at(held, ["parts", "0", "physical_properties"])), PY_NONE
    )
    assert_equal(digest(held), HELD_DIGEST)
    var scratch = Scratch()
    var path = scratch.path + "/canonical.json"
    var key = write_snapshot(path, held)
    assert_equal(key, HELD_DIGEST)
    var read = read_snapshot(path, key)
    assert_true(_equal_nodes(read, read.root, held, held.root))
    var asset = scratch.path + "/visual.glb"
    Path(asset).write_text("synthetic visual bytes")
    var recipe = PyJson.parse('{"source": "current-producer-control"}')
    var manifest = visual_derivative(held, asset, recipe)
    assert_equal(
        _text(manifest),
        '{"canonical_snapshot_sha256":"'
        + HELD_DIGEST
        + '","dental_representations":["authored-canonical",'
        '"scanned-expression"],"engineering_use":false,"mappings":{'
        '"dental":"unsupported","expression_jaw":"unsupported","eyes":'
        '"unsupported","identity":"unsupported","lod":"unsupported",'
        '"skin_weights":"unsupported"},"recipe":{"source":'
        '"current-producer-control"},"recipe_sha256":'
        '"f8dc6182cd561ced1e3f95b7f4dca7d2e2f7754d1b0b1781ad9aa3ee247b5f00",'
        '"schema_version":1,"visual_asset_sha256":'
        '"550b9c459f747e3e5664c05fc1ad8f55ba8c18b77fbf8a2f7b2e837bab003f69"}',
    )
    _put(manifest, ["mappings", "dental"], '"supported"')
    with assert_raises(contains="stale or altered"):
        validate_derivative(manifest, held, asset, recipe)
    scratch.keep()


def test_unknown_or_untyped_report_versions_are_refused() raises:
    var sources = List[PyJson]()
    sources.append(_report())
    sources.append(_evidence())
    for index in range(len(sources)):
        ref source = sources[index]
        var kept = source.get(source.root, "schema_version")
        for version in [
            "null",
            "-1",
            "0",
            "3",
            "true",
            "1.0",
            "2.0",
            '"2"',
            "[]",
            "{}",
        ]:
            _put(source, ["schema_version"], version)
            with assert_raises(contains="versioned canonical validity report"):
                _ = report_properties(source, "thigh", 0)
        source.set(source.root, "schema_version", kept)
        _ = report_properties(source, "thigh", 0)
    var missing = _report()
    _drop(missing, ["schema_version"])
    with assert_raises(contains="versioned canonical validity report"):
        _ = report_properties(missing, "thigh", 0)


def test_current_report_requires_its_complete_common_envelope() raises:
    var evidence = _evidence()
    var root = evidence.root
    for key in [
        "gate",
        "build_provenance",
        "source_file_sha256",
        "spec",
        "frame",
        "tensor_convention",
        "controls",
        "segments",
        "composition",
        "diagnostics",
        "diagnostic_limits",
        "accounting",
        "provenance_inventory",
        "follow_ups",
        "geometry_findings",
        "result_label",
        "report_logic_sha256",
        "inventory_sha256",
    ]:
        var kept = evidence.at(root, key)
        evidence.remove(root, key)
        with assert_raises():
            _ = report_properties(evidence, "thigh", 0)
        evidence.set(root, key, kept)
    _ = report_properties(evidence, "thigh", 0)
    var frame = PyJson.parse(
        '{"origin": "tibiofemoral joint line", "x": "body-right", "y":'
        ' "distal", "z": "anterior"}'
    )
    var convention = evidence.subtree(evidence.at(root, "tensor_convention"))
    _put(convention, ["reference"], '"origin"')
    var cases: List[Tuple[String, String]] = [
        ("gate", '{"engineering_validated": true}'),
        ("frame", _text(frame)),
        ("tensor_convention", _text(convention)),
    ]
    for case_ in cases:
        var kept = evidence.at(root, case_[0])
        _put(evidence, [case_[0]], case_[1])
        with assert_raises():
            _ = report_properties(evidence, "thigh", 0)
        evidence.set(root, case_[0], kept)


def test_version_two_requires_its_diagnostic_envelope() raises:
    var evidence = _evidence()
    var root = evidence.root
    for key in ["diagnostic_frames", "pair_inventory"]:
        var kept = evidence.at(root, key)
        for value in ["null", "[]", "{}"]:
            _put(evidence, [key], value)
            with assert_raises():
                _ = report_properties(evidence, "thigh", 0)
        evidence.remove(root, key)
        with assert_raises():
            _ = report_properties(evidence, "thigh", 0)
        evidence.set(root, key, kept)
    var inventory = evidence.at(root, "pair_inventory")
    var version = evidence.at(inventory, "schema_version")
    for value in ["null", "true", "1.0", "0", "2", '"1"']:
        _put(evidence, ["pair_inventory", "schema_version"], value)
        with assert_raises(contains="inventory schema"):
            _ = report_properties(evidence, "thigh", 0)
    evidence.set(inventory, "schema_version", version)
    for key in [
        "classes",
        "components",
        "pairs",
        "additional_checked_diagnostics",
        "positive_volume_attachment_allowances",
        "unknowns",
        "excluded_domains",
        "frame_id",
    ]:
        var kept = evidence.at(inventory, key)
        _put(evidence, ["pair_inventory", key], "null")
        with assert_raises():
            _ = report_properties(evidence, "thigh", 0)
        evidence.set(inventory, key, kept)
    _put(evidence, ["pair_inventory", "frame_id"], '"unknown"')
    with assert_raises(contains="coordinate frame"):
        _ = report_properties(evidence, "thigh", 0)


# --- Transforms ---------------------------------------------------------------------------


def test_full_tensor_rotation_and_reference_shift() raises:
    assert_true(_same(frame_rotation(Y_UP, Z_UP), _text(y_to_z())))
    assert_true(_same(frame_rotation(Z_UP, Y_UP), _text(z_to_y())))
    assert_true(_same(frame_rotation(Y_UP, Y_UP), _text(identity())))
    assert_true(_same(y_to_z(), "[[1, 0, 0], [0, 0, -1], [0, 1, 0]]"))
    assert_true(Y_UP.is_valid())
    assert_false(Frame(2).is_valid())
    assert_true(
        _same(
            transform_point(PyJson.parse("[1, 2, 3]"), y_to_z()), "[1, -3, 2]"
        )
    )
    var before = PyJson.parse("[3, 4, 5, 0.2, 0.3, 0.4]")
    var transformed = transform_inertia(
        PyJson.parse("2"),
        PyJson.parse("[1, 2, 3]"),
        before,
        y_to_z(),
        PyJson.parse("[4, 5, 6]"),
    )
    assert_equal(
        _text(transformed),
        (
            '{"center_m":[5.0,2.0,8.0],"inertia_kg_m2":[3.0,5.0,4.0,-0.3,0.2,'
            '-0.4],"mass_kg":2,"reference_m":[5.0,2.0,8.0]}'
        ),
    )
    var back = transform_inertia(
        PyJson.parse("2"),
        transformed.subtree(_at(transformed, ["center_m"])),
        transformed.subtree(_at(transformed, ["inertia_kg_m2"])),
        z_to_y(),
        PyJson.parse("[-4, -6, 5]"),
    )
    assert_equal(
        _text(back),
        (
            '{"center_m":[1.0,2.0,3.0],"inertia_kg_m2":[3.0,4.0,5.0,0.2,0.3,0.4],'
            '"mass_kg":2,"reference_m":[1.0,2.0,3.0]}'
        ),
    )
    assert_true(
        _equal_nodes(back, _at(back, ["inertia_kg_m2"]), before, before.root)
    )
    var shifted = transform_inertia(
        PyJson.parse("2"),
        PyJson.parse("[1, 2, 3]"),
        before,
        identity(),
        reference_m=PyJson.parse("[0, 0, 0]"),
    )
    assert_equal(
        _text(shifted),
        (
            '{"center_m":[1.0,2.0,3.0],"inertia_kg_m2":[29.0,24.0,15.0,-3.8,'
            '-5.7,-11.6],"mass_kg":2,"reference_m":[0,0,0]}'
        ),
    )
    # An independent sum of point-mass contributions checks every term.
    var turn = PyJson.parse(
        "[[0.9323273456060345, -0.361615431964962, 0], [0.361615431964962,"
        " 0.9323273456060345, 0], [0, 0, 1]]"
    )
    var expected = List[Float64](length=6, fill=0.0)
    for point in [
        "[1, 0, 0]",
        "[-1, 0, 0]",
        "[0, 2, 1]",
        "[0, -2, -1]",
    ]:
        var moved = transform_point(
            PyJson.parse(point), turn, PyJson.parse("[1, 3, -2]")
        )
        var x = moved.number(_at(moved, ["0"]))
        var y = moved.number(_at(moved, ["1"]))
        var z = moved.number(_at(moved, ["2"]))
        var terms: List[Float64] = [
            y * y + z * z,
            x * x + z * z,
            x * x + y * y,
            -x * y,
            -x * z,
            -y * z,
        ]
        for index in range(6):
            expected[index] += terms[index]
    var actual = transform_inertia(
        PyJson.parse("4"),
        PyJson.parse("[0, 0, 0]"),
        PyJson.parse("[10, 4, 10, 0, 0, -4]"),
        turn,
        PyJson.parse("[1, 3, -2]"),
        PyJson.parse("[0, 0, 0]"),
    )
    for index in range(6):
        var value = actual.number(_at(actual, ["inertia_kg_m2", String(index)]))
        assert_true(abs(value - expected[index]) < 5e-13)
    assert_equal(
        _text(actual),
        (
            '{"center_m":[1.0,3.0,-2.0],"inertia_kg_m2":[61.215405676188766,'
            "24.784594323811238,50.0,-9.977136265115565,9.446461727859848,"
            '20.270690617575863],"mass_kg":4,"reference_m":[0,0,0]}'
        ),
    )
    assert_equal(
        _text(
            transform_point(
                PyJson.parse("[0.1, 0.2, 0.3]"),
                turn,
                PyJson.parse("[1e-3, 2.5, -7]"),
            )
        ),
        "[0.021909648167611054,2.722627012317703,-6.7]",
    )


def test_part_adapter_moves_geometry_and_physics_together() raises:
    var part = _part()
    var before = _text(part)
    var out = adapt_part(
        part,
        Y_UP,
        Z_UP,
        PyJson.parse("[1, 2, 3]"),
        target_origin_label=String("translated origin"),
    )
    assert_equal(
        _text(out),
        '{"frame":"'
        + Z_UP_TEXT
        + '","origin_label":"translated origin","part_id":'
        '"synthetic/triangle","physical_properties":{"center_m":[1.0,2.0,3.0],'
        '"frame":"'
        + Z_UP_TEXT
        + '","inertia_kg_m2":[3.0,5.0,4.0,-0.3,0.2,-0.4],"mass_kg":2,'
        '"origin_label":"translated origin","reference_m":[1.0,2.0,3.0],'
        '"source_report_record":"synthetic-control","tensor_reference":'
        '"center-of-mass"},"source_frame":"'
        + Y_UP_TEXT
        + '","source_origin_label":"synthetic origin","tissue_label":'
        '"unresolved_fat_proxy","translation_m":[1,2,3],"triangles":[[0,1,2]],'
        '"vertices_m":[[1.0,2.0,3.0],[2.0,2.0,3.0],[1.0,2.0,4.0]]}',
    )
    var back = adapt_part(
        out,
        Z_UP,
        Y_UP,
        PyJson.parse("[-1, -3, 2]"),
        target_origin_label=String("synthetic origin"),
    )
    assert_true(
        _equal_nodes(
            back, _at(back, ["vertices_m"]), part, _at(part, ["vertices_m"])
        )
    )
    var zero = PyJson.parse("[0, 0, 0]")
    assert_true(
        _equal_nodes(
            back,
            _at(back, ["physical_properties", "center_m"]),
            zero,
            zero.root,
        )
    )
    assert_true(
        _equal_nodes(
            back,
            _at(back, ["physical_properties", "inertia_kg_m2"]),
            part,
            _at(part, ["physical_properties", "inertia_kg_m2"]),
        )
    )
    var shifted = adapt_part(
        part,
        Y_UP,
        Y_UP,
        PyJson.parse("[1, 2, 3]"),
        PyJson.parse("[0, 0, 0]"),
        String("translated origin"),
    )
    assert_equal(
        shifted.text(_at(shifted, ["physical_properties", "tensor_reference"])),
        "explicit-target-reference",
    )
    assert_true(
        _text(shifted).find('"inertia_kg_m2":[29.0,24.0,15.0,-3.8,-5.7,-11.6]')
        > 0
    )
    with assert_raises(contains="tensor about the COM"):
        _ = adapt_part(shifted, Y_UP, Z_UP)
    _put(part, ["physical_properties"], "null")
    var bare = adapt_part(part, Y_UP, Z_UP)
    assert_equal(bare.kind(_at(bare, ["physical_properties"])), PY_NONE)
    assert_equal(_text(_part()), before)


def test_frame_and_origin_contradictions_are_refused() raises:
    var part = _part()
    var z_up = adapt_part(part, Y_UP, Z_UP)
    var z_parts = PyJson()
    z_parts.root = z_parts.new_list()
    z_parts.append(z_parts.root, z_parts.adopt(z_up, z_up.root))
    var inputs = PyJson.parse('{"stature_m": 1.8288}')
    with assert_raises(contains="part frame"):
        _ = make_snapshot(
            inputs, "synthetic", z_parts, _report(), "synthetic origin"
        )
    with assert_raises(contains="source frame"):
        _ = adapt_part(z_up, Y_UP, Z_UP)
    var back = adapt_part(z_up, Z_UP, Y_UP)
    var back_parts = PyJson()
    back_parts.root = back_parts.new_list()
    back_parts.append(back_parts.root, back_parts.adopt(back, back.root))
    var restored = make_snapshot(
        inputs, "synthetic", back_parts, _report(), "synthetic origin"
    )
    assert_true(
        _equal_nodes(
            restored,
            _at(restored, ["parts", "0", "vertices_m"]),
            part,
            _at(part, ["vertices_m"]),
        )
    )
    var physical: List[Tuple[String, String]] = [
        ("frame", '"' + Z_UP_TEXT + '"'),
        ("origin_label", '"different"'),
    ]
    for case_ in physical:
        var bad = _snapshot()
        _put(bad, ["parts", "0", "physical_properties", case_[0]], case_[1])
        with assert_raises():
            validate_snapshot(bad)
        var bad_part = bad.subtree(_at(bad, ["parts", "0"]))
        with assert_raises():
            _ = adapt_part(bad_part, Y_UP, Z_UP)
    var whole: List[Tuple[String, String]] = [
        ("frame", "null"),
        ("origin_label", '"different"'),
    ]
    for case_ in whole:
        var bad = _snapshot()
        _put(bad, ["parts", "0", case_[0]], case_[1])
        with assert_raises():
            validate_snapshot(bad)
    with assert_raises(contains="target origin"):
        _ = adapt_part(part, Y_UP, Z_UP, PyJson.parse("[1, 0, 0]"))
    with assert_raises():
        _ = adapt_part(PyJson(), Y_UP, Z_UP)
    var no_physics = part.copy()
    _put(no_physics, ["physical_properties"], "null")
    _put(no_physics, ["vertices_m", "0"], "[1e308, 0, 0]")
    with assert_raises():
        _ = adapt_part(
            no_physics,
            Y_UP,
            Y_UP,
            PyJson.parse("[1e308, 0, 0]"),
            target_origin_label=String("overflow"),
        )
    with assert_raises():
        _ = transform_point(
            PyJson.parse("[1e308, 0, 0]"),
            identity(),
            PyJson.parse("[1e308, 0, 0]"),
        )


def test_report_structure_frame_and_tensor_semantics_are_required() raises:
    for key in [
        "build_provenance",
        "segments",
        "accounting",
        "tensor_convention",
        "diagnostic_limits",
        "frame",
        "follow_ups",
        "result_label",
    ]:
        var broken = _report()
        _put(broken, [key], "null")
        with assert_raises():
            _ = report_properties(broken, "thigh", 0)
    var conventions: List[Tuple[String, String]] = [
        ("reference", '"global origin"'),
        ("order", '["xx", "yy", "zz", "yz", "xz", "xy"]'),
        ("off_diagonal", '"positive products of inertia"'),
    ]
    for case_ in conventions:
        var broken = _report()
        _put(broken, ["tensor_convention", case_[0]], case_[1])
        with assert_raises(contains="tensor"):
            _ = report_properties(broken, "thigh", 0)
    var broken = _report()
    _put(broken, ["frame", "y"], '"distal"')
    with assert_raises(contains="coordinate frame"):
        _ = report_properties(broken, "thigh", 0)
    broken = _report()
    _drop(broken, ["segments", "foot"])
    with assert_raises():
        _ = report_properties(broken, "thigh", 0)
    broken = _report()
    _put(broken, ["accounting", "exclusive_density_precedence"], '["one"]')
    with assert_raises():
        _ = report_properties(broken, "thigh", 0)
    for entry in [
        "null",
        '{"grids": null, "sampling_sensitivity": {}}',
        '{"grids": [], "sampling_sensitivity": {}}',
    ]:
        broken = _report()
        _put(broken, ["segments", "thigh"], entry)
        with assert_raises():
            _ = report_properties(broken, "thigh", 0)
    var rows: List[Tuple[String, String]] = [
        ("record", '"wrong"'),
        ("mass_kg", "0"),
        ("inertia_kg_m2", "[]"),
        ("regions", "{}"),
    ]
    for case_ in rows:
        broken = _report()
        _put(broken, ["segments", "thigh", "grids", "0", case_[0]], case_[1])
        with assert_raises():
            _ = report_properties(broken, "thigh", 0)
    for value in ["null", '{"mass_kg": -1, "volume_m3": 0}']:
        broken = _report()
        _put(
            broken,
            ["segments", "thigh", "grids", "0", "regions", "dermis"],
            value,
        )
        with assert_raises():
            _ = report_properties(broken, "thigh", 0)


def test_bad_transforms_and_numbers_are_refused() raises:
    for bad in ["true", '"x"', "NaN", "Infinity"]:
        with assert_raises(contains="finite and numeric"):
            _ = finite(PyJson.parse(bad))
    assert_equal(_text(finite(PyJson.parse("-0.0"))), "-0.0")
    for bad in ["null", "[1, 2]", "[1, false, 3]"]:
        with assert_raises():
            _ = vector(PyJson.parse(bad))
    for bad in [
        "null",
        "[1, 2]",
        "[[1, 0, 0], [1, 0, 0], [1, 0, 0]]",
        "[[1, 0, 0], [0, 1, 0], [0, 0, -1]]",
    ]:
        with assert_raises():
            _ = rotation(PyJson.parse(bad))
    assert_true(_same(rotation(z_to_y()), _text(z_to_y())))
    with assert_raises(contains="typed frames"):
        _ = frame_rotation(Frame(7), Z_UP)
    with assert_raises(contains="typed frames"):
        _ = frame_rotation(Y_UP, Frame(-1))
    with assert_raises(contains="negative"):
        _ = transform_inertia(
            PyJson.parse("-1"),
            PyJson.parse("[0, 0, 0]"),
            PyJson.parse("[0, 0, 0, 0, 0, 0]"),
            identity(),
        )
    with assert_raises(contains="six entries"):
        _ = transform_inertia(
            PyJson.parse("1"),
            PyJson.parse("[0, 0, 0]"),
            PyJson.parse("[0, 0, 0, 0, 0]"),
            identity(),
        )
    with assert_raises(contains="finite and numeric"):
        _ = transform_inertia(
            PyJson.parse("1e308"),
            PyJson.parse("[1e308, 1e308, 1e308]"),
            PyJson.parse("[0, 0, 0, 0, 0, 0]"),
            identity(),
            reference_m=PyJson.parse("[0, 0, 0]"),
        )
    # Python's `finite` converts an int to a float and overflows.
    with assert_raises(contains="OverflowError: int too large"):
        _ = finite(PyJson.parse("1" + "0" * 400))


# --- Snapshots ---------------------------------------------------------------------------


def test_snapshot_copy_and_immutable_bytes() raises:
    var original = _snapshot()
    validate_snapshot(original)
    assert_false(original.flag(_at(original, ["engineering_validated"])))
    assert_equal(digest(original), SNAPSHOT_DIGEST)
    assert_equal(len(canonical_bytes(original)), 6254)
    var scratch = Scratch()
    var path = scratch.path + "/canonical.json"
    var key = write_snapshot(path, original)
    assert_equal(key, SNAPSHOT_DIGEST)
    assert_equal(write_snapshot(path, original), key)
    var read = read_snapshot(path, key)
    assert_true(_equal_nodes(read, read.root, original, original.root))
    var changed = original.copy()
    _put(changed, ["parts", "0", "vertices_m", "0", "0"], "2")
    with assert_raises(contains="immutable"):
        _ = write_snapshot(path, changed)
    with assert_raises(contains="content changed"):
        _ = read_snapshot(path, "wrong")
    # Exporters receive a copy. Editing it cannot change disk evidence.
    _put(original, ["parts", "0", "physical_properties", "mass_kg"], "10")
    var again = read_snapshot(path, key)
    assert_equal(
        again.text(
            _at(again, ["parts", "0", "physical_properties", "mass_kg"])
        ),
        "2",
    )
    assert_equal(len(listdir(scratch.path)), 1)
    scratch.keep()


def test_interrupted_snapshot_write_leaves_no_file() raises:
    var scratch = Scratch()
    var path = scratch.path + "/canonical.json"
    with assert_raises(contains="disk full"):
        _ = _write_snapshot(path, _snapshot(), True)
    assert_equal(len(listdir(scratch.path)), 0)
    # The versioned path stays free, so a retry succeeds.
    assert_equal(write_snapshot(path, _snapshot()), digest(_snapshot()))
    scratch.keep()


def test_stale_geometry_identity_lod_assets_and_sources() raises:
    var canonical = _snapshot()
    var unchanged = _text(canonical)
    var scratch = Scratch()
    var asset = scratch.path + "/visual.glb"
    Path(asset).write_text("synthetic visual bytes")
    var recipe = PyJson.parse(
        '{"spec": {"identity": [-1, -1, -1, -1, -1, -1, -1, -1]}, "triangles":'
        ' 20, "source": "v1"}'
    )
    var manifest = visual_derivative(canonical, asset, recipe)
    validate_derivative(manifest, canonical, asset, recipe)
    assert_equal(
        _text(manifest),
        '{"canonical_snapshot_sha256":"'
        + SNAPSHOT_DIGEST
        + '","dental_representations":["authored-canonical",'
        '"scanned-expression"],"engineering_use":false,"mappings":{'
        '"dental":"unsupported","expression_jaw":"unsupported","eyes":'
        '"unsupported","identity":"unsupported","lod":"unsupported",'
        '"skin_weights":"unsupported"},"recipe":{"source":"v1","spec":'
        '{"identity":[-1,-1,-1,-1,-1,-1,-1,-1]},"triangles":20},'
        '"recipe_sha256":'
        '"c63319d86287f713f70c97f76436e9f054ca79bec84626df828783a0321b93fd",'
        '"schema_version":1,"visual_asset_sha256":'
        '"550b9c459f747e3e5664c05fc1ad8f55ba8c18b77fbf8a2f7b2e837bab003f69"}',
    )
    var changes: List[Tuple[String, String]] = [
        ("triangles", "10"),
        ("source", '"v2"'),
        ("spec", '{"identity": [1, 1, 1, 1, 1, 1, 1, 1]}'),
    ]
    for case_ in changes:
        var changed = recipe.copy()
        _put(changed, [case_[0]], case_[1])
        with assert_raises(contains="stale or altered"):
            validate_derivative(manifest, canonical, asset, changed)
    for at in range(8):
        for extreme in ["-1", "1"]:
            var weights = List[String](length=8, fill="0")
            weights[at] = extreme
            var current = visual_derivative(
                canonical,
                asset,
                PyJson.parse('{"identity": [' + ", ".join(weights) + "]}"),
            )
            assert_false(current.flag(_at(current, ["engineering_use"])))
            assert_equal(
                current.text(_at(current, ["canonical_snapshot_sha256"])),
                SNAPSHOT_DIGEST,
            )
    assert_equal(_text(canonical), unchanged)
    var changed = canonical.copy()
    _put(changed, ["parts", "0", "triangles"], "[[2, 1, 0]]")
    with assert_raises():
        validate_derivative(manifest, changed, asset, recipe)
    _put(manifest, ["engineering_use"], "true")
    with assert_raises():
        validate_derivative(manifest, canonical, asset, recipe)
    _put(manifest, ["engineering_use"], "false")
    validate_derivative(manifest, canonical, asset, recipe)
    Path(asset).write_text("changed")
    with assert_raises():
        validate_derivative(manifest, canonical, asset, recipe)
    with assert_raises(contains="explicit recipe"):
        _ = visual_derivative(canonical, asset, PyJson.parse("{}"))
    scratch.keep()


def test_report_properties_copy_the_exact_authoritative_row() raises:
    var evidence = _report()
    var copied = report_properties(evidence, "thigh", 0)
    assert_equal(
        _text(copied),
        '{"center_m":[1,2,3],"frame":"'
        + Y_UP_TEXT
        + '","inertia_kg_m2":[3,4,5,0.2,0.3,0.4],"mass_kg":2,"origin_label":'
        '"tibiofemoral joint line","regions":{"cortical_apparent":{"mass_kg":'
        '0,"volume_m3":0},"dermis":{"mass_kg":2,"volume_m3":0.001},'
        '"marrow_fat_proxy":{"mass_kg":0,"volume_m3":0},"muscle":{"mass_kg":'
        '0,"volume_m3":0},"tendon":{"mass_kg":0,"volume_m3":0},'
        '"trabecular_apparent":{"mass_kg":0,"volume_m3":0},'
        '"unresolved_fat_proxy":{"mass_kg":0,"volume_m3":0}},'
        '"source_report_frame":{"origin":"tibiofemoral joint line","x":'
        '"body-right","y":"proximal","z":"anterior"},"source_report_record":'
        '"segments/thigh/grids/0","step_m":0.02,"tensor_reference":'
        '"center-of-mass"}',
    )
    _put(evidence, ["segments", "thigh", "grids", "0", "mass_kg"], "7")
    assert_equal(copied.text(_at(copied, ["mass_kg"])), "2")
    var cases: List[Tuple[String, Int]] = [
        ("unknown", 0),
        ("thigh", -1),
        ("thigh", 4),
        ("foot", 9),
    ]
    for case_ in cases:
        with assert_raises():
            _ = report_properties(evidence, case_[0], case_[1])


def test_cli_reports_verified_bytes_or_a_controlled_error() raises:
    var scratch = Scratch()
    var path = scratch.path + "/canonical.json"
    var key = write_snapshot(path, _snapshot())
    var passed = run([path, "--sha256", key], "humanoid_fidelity.mojo", 80)
    assert_equal(passed.status, 0)
    assert_equal(
        passed.output,
        (
            "Canonical snapshot bytes and SI packaging verified; engineering"
            " use remains unsupported.\n"
        ),
    )
    var failed = run([path, "--sha256", "stale"], "humanoid_fidelity.mojo", 80)
    assert_equal(failed.status, 2)
    assert_equal(
        failed.errors,
        (
            "Canonical snapshot validation failed: canonical snapshot content"
            " changed\n"
        ),
    )
    var missing = run(
        [scratch.path + "/none.json", "--sha256", key],
        "humanoid_fidelity.mojo",
        80,
    )
    assert_true(
        missing.errors.find("[Errno 2] No such file or directory: '") > 0
    )
    # The usage, the help and the argument errors are argparse's.
    var usage = "usage: humanoid_fidelity.py [-h] --sha256 SHA256 snapshot\n"
    var none = run(List[String](), "humanoid_fidelity.py", 80)
    assert_equal(none.status, 2)
    assert_equal(
        none.errors,
        usage
        + "humanoid_fidelity.py: error: the following arguments are required:"
        " snapshot, --sha256\n",
    )
    var help = run(["-h"], "humanoid_fidelity.py", 80)
    assert_equal(help.status, 0)
    assert_equal(
        help.output,
        usage
        + "\nImmutable canonical SI snapshots and explicit visual derivatives."
        " This\nboundary packages supplied canonical geometry; it does not"
        " reconstruct anatomy\nfrom a visual mesh or certify the geometry."
        " Keep the complete #289 report as\nevidence. No raw probe row is an"
        " engineering validity certificate. The CLI\nuses local files only and"
        " never fetches or rehosts source assets.\n\npositional arguments:\n "
        " snapshot\n\noptions:\n  -h, --help       show this help message and"
        " exit\n  --sha256 SHA256\n",
    )
    var narrow = run(["-h"], "humanoid_fidelity.py", 40)
    assert_true(
        narrow.output.startswith(
            "usage: humanoid_fidelity.py [-h]\n                           "
            " --sha256\n"
        )
    )
    assert_true(
        narrow.output.endswith(
            "  -h, --help      show this help\n                  message and"
            " exit\n  --sha256 SHA256\n"
        )
    )
    # Each case is space-separated arguments and the error.
    var cases: List[Tuple[String, String]] = [
        ("--sha256", "argument --sha256: expected one argument"),
        ("a b --sha256 c", "unrecognized arguments: b"),
        ("-h=1", "argument -h/--help: ignored explicit argument '1'"),
        ("--=x", "ambiguous option: --=x could match --help, --sha256"),
        ("x", "the following arguments are required: --sha256"),
    ]
    for case_ in cases:
        var words = List[String]()
        for word in case_[0].split(" "):
            words.append(String(word))
        var refused = run(words, "humanoid_fidelity.py", 80)
        assert_equal(refused.status, 2)
        assert_equal(
            refused.errors,
            usage + "humanoid_fidelity.py: error: " + case_[1] + "\n",
        )
    var joined = run(["--sha=" + key, path], "humanoid_fidelity.py", 80)
    assert_equal(joined.status, 0)
    assert_true(DESCRIPTION.startswith("Immutable canonical SI snapshots"))
    scratch.keep()


def test_malformed_snapshots_fail_closed() raises:
    var cases: List[Tuple[String, String]] = [
        ("schema_version", "2"),
        ("schema_version", "true"),
        ("units", "{}"),
        ("frame", '"' + Z_UP_TEXT + '"'),
        ("origin_m", "[0]"),
        ("origin_label", '""'),
        ("source_revision", '""'),
        ("canonical_inputs", "{}"),
        ("engineering_validated", "true"),
        ("parts", "[]"),
        ("canonical_validity_report", "{}"),
        (
            "canonical_validity_report",
            '{"schema_version": 1, "gate": {"engineering_validated": true}}',
        ),
    ]
    with assert_raises(contains="must be an object"):
        validate_snapshot(PyJson.parse("[]"))
    var invalid = _snapshot()
    _put(invalid, ["parts"], "[null]")
    with assert_raises():
        validate_snapshot(invalid)
    for case_ in cases:
        var bad = _snapshot()
        _put(bad, [case_[0]], case_[1])
        with assert_raises():
            validate_snapshot(bad)
    var doubled = _snapshot()
    var parts = _at(doubled, ["parts"])
    doubled.append(parts, doubled.copy_node(doubled.item(parts, 0)))
    with assert_raises(contains="unique"):
        validate_snapshot(doubled)
    var part_cases: List[Tuple[String, String]] = [
        ("part_id", '""'),
        ("tissue_label", '""'),
        ("vertices_m", "[]"),
        ("triangles", "[]"),
        ("triangles", "[[0, 1]]"),
        ("triangles", "[[0, 1, 9]]"),
        ("triangles", "[[0, 1, true]]"),
        ("physical_properties", "{}"),
    ]
    for case_ in part_cases:
        var bad = _snapshot()
        _put(bad, ["parts", "0", case_[0]], case_[1])
        with assert_raises():
            validate_snapshot(bad)
    var bare = _snapshot()
    _put(bare, ["parts", "0", "physical_properties"], "null")
    validate_snapshot(bare)
    var inputs = PyJson.parse('{"x": 1}')
    var reports: List[String] = ["{}", '{"schema_version": 1}']
    var granted = _report()
    _put(granted, ["gate"], '{"engineering_validated": true}')
    reports.append(_text(granted))
    for text in reports:
        with assert_raises():
            _ = make_snapshot(
                inputs,
                "v1",
                PyJson.parse(PARTS),
                PyJson.parse(text),
                "test origin",
            )
    # A complete report is copied, with all unresolved limitations intact.
    var evidence = _report()
    _put(
        evidence,
        ["diagnostic_limits", "missing"],
        '["eye fit", "tissue clearance"]',
    )
    var held = make_snapshot(
        inputs, "v1", PyJson.parse(PARTS), evidence, "synthetic origin"
    )
    _put(evidence, ["diagnostic_limits"], "{}")
    assert_true(
        _same(
            held.subtree(
                _at(
                    held,
                    [
                        "canonical_validity_report",
                        "diagnostic_limits",
                        "missing",
                    ],
                )
            ),
            '["eye fit", "tissue clearance"]',
        )
    )
    assert_equal(held.length(_at(held, ["parts"])), 1)


# --- Python's JSON text ------------------------------------------------------------------


def test_json_reading_keeps_python_errors_and_values() raises:
    var refused: List[Tuple[String, String]] = [
        ("[1,", "Expecting value: line 1 column 4 (char 3)"),
        (
            '{"a":1,}',
            (
                "Expecting property name enclosed in double quotes: line 1"
                " column 8 (char 7)"
            ),
        ),
        ('{"a" 1}', "Expecting ':' delimiter: line 1 column 6 (char 5)"),
        ("[1 2]", "Expecting ',' delimiter: line 1 column 4 (char 3)"),
        ('"abc', "Unterminated string starting at: line 1 column 1 (char 0)"),
        ('"a\\x"', "Invalid \\escape: line 1 column 3 (char 2)"),
        ('"\\u12"', "Invalid \\uXXXX escape: line 1 column 3 (char 2)"),
        ("[1]x", "Extra data: line 1 column 4 (char 3)"),
        ("\n\n  [1,\n  x]", "Expecting value: line 4 column 3 (char 10)"),
        (
            '"é\x01"',
            "Invalid control character at: line 1 column 3 (char 2)",
        ),
    ]
    for case_ in refused:
        with assert_raises(contains=case_[1]):
            _ = PyJson.parse(case_[0])
    var bad_utf8: List[UInt8] = [0x22, 0xE2, 0x82, 0x22]
    with assert_raises(
        contains=(
            "'utf-8' codec can't decode bytes in position 1-2: invalid"
            " continuation byte"
        )
    ):
        _ = loads(bad_utf8)
    var wide: List[UInt8] = [0xFF, 0xFE, 0x5B, 0x00, 0x31, 0x00, 0x5D, 0x00]
    assert_equal(_text(loads(wide)), "[1]")
    var values = PyJson.parse(
        '{"b": [1.0, 2.50, 1e22, 1e23, 123456789012345678901234567890,'
        ' 0.30000000000000004, -0, -0.0, 1E-7, "\\ud834\\udd1e\\u00e9\\ud800"],'
        ' "a": 1, "a": 2}'
    )
    assert_equal(
        _text(values),
        (
            '{"a":2,"b":[1.0,2.5,1e+22,1e+23,123456789012345678901234567890,'
            '0.30000000000000004,0,-0.0,1e-07,"\\ud834\\udd1e\\u00e9\\ud800"]}'
        ),
    )
    with assert_raises(contains="Out of range float values are not JSON"):
        _ = _text(PyJson.parse('{"b": NaN, "a": [Infinity]}'))
    with assert_raises(contains="compliant: inf"):
        _ = _text(PyJson.parse('{"b": NaN, "a": [Infinity]}'))
    assert_true(_same(PyJson.parse("[1, true, 2.0]"), "[1.0, 1, 2]"))
    assert_false(_same(PyJson.parse("[NaN]"), "[NaN]"))
    assert_equal(PyJson.parse("{}").kind(PyJson.parse("{}").root), PY_DICT)
    assert_equal(MISSING, -1)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
