# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Localize and classify canonical sampled overlaps (#595). Evidence, never
clearance.

    mojo run -I . tools/anatomy_overlaps.mojo --build --output FILE

The tool checks every legacy bone, knee and neighboring-spine pair at three
grid widths. It localizes each pair that #595 lists and each pair with a
sampled common interior at any width. A localization records the grid
witness, the box of common-interior cell centers and two local refinements
around the witness. A negative refined value is a point inside both canonical
fields. A nonnegative value does not prove clearance elsewhere. No acceptance
threshold is applied, because none is established.

Use --build once, then reuse the source-bound probe. Each probe execution has
the unchanged five-second runtime limit. The tool works on the repository in
the current directory.
"""

from std.collections import Set
from std.os.path import realpath
from std.sys import argv, exit, stderr

from tools._json_tree import NOTHING, JsonTree
from tools._sha256 import sha256_hex
from tools.anatomy_validity import (
    Component,
    NativeProbe,
    Num,
    Prober,
    Spec,
    _read_bytes,
    annotate_diagnostics,
    display_path,
    file_sha256,
    legacy_pair_group,
    parse_options,
    prepare_probe,
    py_repr,
    resolve_path,
    sidecar,
    source_snapshot,
    validate_catalog,
    verify_report_inputs,
    write_report,
)

comptime TOOL = "tools/anatomy_overlaps.mojo"
"""This tool, which the evidence binds."""
comptime SCHEMA_VERSION = 1
"""The evidence schema version."""
comptime ISSUE = "https://github.com/SethKitchen/ThreeMojo/issues/595"
"""The issue the evidence answers."""
comptime PROGRAM = "anatomy_overlaps.mojo"
"""The program name in usage messages."""
comptime USAGE = (
    "usage: anatomy_overlaps.mojo [-h] [--build] [--mojo MOJO] [--probe"
    " PROBE]\n                             --output OUTPUT\n"
)
"""The usage text, as `argparse` wraps it."""
comptime HELP = (
    "\nLocalize and classify canonical sampled overlaps (#595). Evidence,"
    " never\nclearance. The tool checks every legacy bone, knee and"
    " neighboring-spine pair at\nthree grid widths. It localizes each pair"
    " that #595 lists and each pair with a\nsampled common interior at any"
    " width. A localization records the grid witness,\nthe box of"
    " common-interior cell centers and two local refinements around the\n"
    "witness. A negative refined value is a point inside both canonical"
    " fields. A\nnonnegative value does not prove clearance elsewhere. No"
    " acceptance threshold is\napplied, because none is established. Use"
    " --build once, then reuse the source-\nbound probe. Each probe"
    " execution has the unchanged five-second runtime limit.\nThe tool"
    " works on the repository in the current directory.\n\noptions:\n  -h,"
    " --help       show this help message and exit\n  --build\n  --mojo"
    " MOJO\n  --probe PROBE\n  --output OUTPUT\n"
)
"""The help text after the usage."""


def steps_mm() -> List[Num]:
    """Return the three grid widths, in millimeters.

    Returns:
        5, 3 and 2 mm, as floats.
    """
    return [Num(5.0, False), Num(3.0, False), Num(2.0, False)]


def legacy_groups() -> List[String]:
    """Return the legacy diagnostic groups, in probe order.

    Returns:
        `bones`, `knee` and `spine`.
    """
    return ["bones", "knee", "spine"]


def issue_595_pairs() -> List[String]:
    """Return the 36 pairs that #595 lists from the 5 mm canonical report of
    #289/#592.

    Returns:
        The pair identities.
    """
    return [
        "canonical/bones/foot/talus|tibia",
        "canonical/bones/foot/calcaneus|foot/talus",
        "canonical/bones/foot/navicular|foot/talus",
        "canonical/bones/foot/calcaneus|foot/cuboid",
        "canonical/bones/foot/intermediate_cuneiform|foot/navicular",
        "canonical/bones/foot/cuboid|foot/lateral_cuneiform",
        "canonical/bones/foot/intermediate_cuneiform|foot/medial_cuneiform",
        "canonical/bones/foot/first_metatarsal|foot/medial_cuneiform",
        "canonical/bones/foot/medial_cuneiform|foot/second_metatarsal",
        "canonical/bones/foot/intermediate_cuneiform|foot/lateral_cuneiform",
        "canonical/bones/foot/intermediate_cuneiform|foot/second_metatarsal",
        "canonical/bones/foot/lateral_cuneiform|foot/third_metatarsal",
        "canonical/bones/foot/first_metatarsal|foot/second_metatarsal",
        "canonical/bones/foot/first_metatarsal|foot/hallux_proximal_phalanx",
        "canonical/bones/foot/second_metatarsal|foot/third_metatarsal",
        (
            "canonical/bones/foot/second_metatarsal|"
            "foot/second_toe_proximal_phalanx"
        ),
        "canonical/bones/foot/third_metatarsal|foot/third_toe_proximal_phalanx",
        (
            "canonical/bones/foot/hallux_distal_phalanx|"
            "foot/hallux_proximal_phalanx"
        ),
        (
            "canonical/bones/foot/third_toe_middle_phalanx|"
            "foot/third_toe_proximal_phalanx"
        ),
        (
            "canonical/bones/foot/fourth_toe_middle_phalanx|"
            "foot/fourth_toe_proximal_phalanx"
        ),
        (
            "canonical/bones/foot/fifth_toe_middle_phalanx|"
            "foot/fifth_toe_proximal_phalanx"
        ),
        "canonical/knee/femur|knee/cartilage",
        "canonical/knee/femur|knee/medial",
        "canonical/knee/femur|knee/lateral",
        "canonical/knee/femur|knee/mcl",
        "canonical/knee/femur|knee/lcl",
        "canonical/knee/knee/cartilage|tibia",
        "canonical/knee/knee/medial|tibia",
        "canonical/knee/knee/mcl|tibia",
        "canonical/knee/knee/lcl|tibia",
        "canonical/knee/fibula|knee/lcl",
        "canonical/knee/knee/cartilage|patella",
        "canonical/knee/knee/cartilage|knee/medial",
        "canonical/knee/knee/mcl|knee/medial",
        "canonical/knee/knee/lateral|knee/lcl",
        "canonical/spine/cervical/2|cervical/3",
    ]


def rules() -> List[Tuple[String, String]]:
    """Return the interface rules and their text.

    Each one makes the later field give way to the earlier field, so the two
    share no interior. None of them is a volume allowance.

    Returns:
        Each rule and its description, in order.
    """
    return [
        (
            "foot_articulation_precedence",
            (
                "A foot bone gives way to each articulating foot bone before it"
                " in the segment accounting order."
            ),
        ),
        ("talus_yields_to_tibia", "The talus gives way to the placed tibia."),
        (
            "fibula_yields_to_tibia",
            "The fibula gives way to the placed tibia.",
        ),
        (
            "knee_tissue_precedence",
            (
                "Knee tissues give way to the leg bones, then to the cartilage,"
                " then to the menisci, in that order."
            ),
        ),
        (
            "cervical_pillar_endplane_extent",
            "Each cervical articular pillar ends at its body endplane levels.",
        ),
    ]


def classes() -> List[Tuple[String, String]]:
    """Return the classes of the observed common interiors.

    A class is a judgment about the authored representation. It is not a
    measured biological tolerance.

    Returns:
        Each class and its description, in order.
    """
    return [
        (
            "unintended_articular_interior",
            (
                "Two bones meet at a joint. Real bones there are separated by"
                " articular surfaces; the template has no joint space. A common"
                " interior is a construction error."
            ),
        ),
        (
            "unintended_layer_interior",
            (
                "A tissue layer lies on a bone or on another tissue. A common"
                " interior double-counts the same space."
            ),
        ),
        (
            "attachment_representation",
            (
                "An authored ligament end or attached tissue lies at an"
                " attachment landmark inside the other field. The attachment is"
                " real anatomy; the shared volume is not. It becomes a"
                " zero-volume interface."
            ),
        ),
        (
            "unintended_path_interior",
            (
                "A ligament path passes through a bone or tissue that it does"
                " not attach to at that place."
            ),
        ),
    ]


@fieldwise_init
struct Classification(Copyable, Movable):
    """The rule, class and note of one tracked pair."""

    var rule: String
    """The interface rule."""
    var kind: String
    """The class."""
    var note: String
    """What the witness shows."""


def classification() -> Dict[String, Classification]:
    """Return the rule, class and note of every classified pair.

    Returns:
        Each pair identity and its classification.
    """
    var found = Dict[String, Classification]()
    var knee = String("knee_tissue_precedence")
    var layer = String("unintended_layer_interior")
    var attachment = String("attachment_representation")
    var path = String("unintended_path_interior")
    var articular = String("unintended_articular_interior")
    found["canonical/bones/foot/talus|tibia"] = Classification(
        "talus_yields_to_tibia",
        articular,
        (
            "Talocrural joint. The witness lies at the medial malleolus over"
            " the talar body."
        ),
    )
    found["canonical/bones/fibula|tibia"] = Classification(
        "fibula_yields_to_tibia",
        articular,
        (
            "Proximal tibiofibular joint. Found at 3 and 2 mm only; the 5 mm"
            " grid missed it."
        ),
    )
    found["canonical/knee/femur|knee/cartilage"] = Classification(
        knee,
        layer,
        (
            "The femoral cartilage lens extends into the condyles and the"
            " trochlea."
        ),
    )
    found["canonical/knee/knee/cartilage|tibia"] = Classification(
        knee, layer, "The tibial cartilage lens extends into the plateau."
    )
    found["canonical/knee/knee/cartilage|patella"] = Classification(
        knee, layer, "The patellar cartilage lens extends into the patella."
    )
    found["canonical/knee/femur|knee/medial"] = Classification(
        knee,
        layer,
        "The medial meniscus tube reaches into the medial femoral condyle.",
    )
    found["canonical/knee/femur|knee/lateral"] = Classification(
        knee,
        layer,
        "The lateral meniscus tube reaches into the lateral femoral condyle.",
    )
    found["canonical/knee/knee/medial|tibia"] = Classification(
        knee, layer, "The medial meniscus tube reaches into the tibial plateau."
    )
    found["canonical/knee/knee/cartilage|knee/medial"] = Classification(
        knee,
        layer,
        "The medial meniscus and the plateau cartilage occupy the same space.",
    )
    found["canonical/knee/knee/cartilage|knee/lateral"] = Classification(
        knee,
        layer,
        (
            "Found at 2 mm only. The lateral meniscus and the plateau cartilage"
            " occupy the same space."
        ),
    )
    found["canonical/knee/femur|knee/mcl"] = Classification(
        knee,
        attachment,
        (
            "The MCL femoral end lies at its authored epicondyle landmark"
            " inside the femur."
        ),
    )
    found["canonical/knee/femur|knee/lcl"] = Classification(
        knee,
        attachment,
        (
            "The LCL femoral end lies at its authored epicondyle landmark"
            " inside the femur."
        ),
    )
    found["canonical/knee/fibula|knee/lcl"] = Classification(
        knee,
        attachment,
        "The LCL fibular end is authored at the fibular head center.",
    )
    found["canonical/knee/knee/mcl|knee/medial"] = Classification(
        knee,
        attachment,
        (
            "The deep MCL attaches to the medial meniscus. The template has one"
            " MCL band and no deep layer, so the overlap is not a measured"
            " attachment volume."
        ),
    )
    found["canonical/knee/knee/mcl|tibia"] = Classification(
        knee,
        path,
        (
            "The witness lies near the joint line, far above the authored"
            " tibial attachment."
        ),
    )
    found["canonical/knee/knee/lcl|tibia"] = Classification(
        knee, path, "The LCL does not attach to the tibia."
    )
    found["canonical/knee/knee/lateral|knee/lcl"] = Classification(
        knee, path, "The LCL does not attach to the lateral meniscus."
    )
    found["canonical/knee/knee/cartilage|knee/mcl"] = Classification(
        knee,
        path,
        (
            "Found at 2 mm only. The MCL path passes through the medial"
            " cartilage lens."
        ),
    )
    found["canonical/knee/knee/cartilage|knee/lcl"] = Classification(
        knee,
        path,
        (
            "Found at 2 mm only. The LCL path passes through the lateral"
            " cartilage lens."
        ),
    )
    for pair in [
        "calcaneus|foot/talus",
        "navicular|foot/talus",
        "calcaneus|foot/cuboid",
        "intermediate_cuneiform|foot/navicular",
        "cuboid|foot/lateral_cuneiform",
        "intermediate_cuneiform|foot/medial_cuneiform",
        "first_metatarsal|foot/medial_cuneiform",
        "medial_cuneiform|foot/second_metatarsal",
        "intermediate_cuneiform|foot/lateral_cuneiform",
        "intermediate_cuneiform|foot/second_metatarsal",
        "lateral_cuneiform|foot/third_metatarsal",
        "first_metatarsal|foot/second_metatarsal",
        "first_metatarsal|foot/hallux_proximal_phalanx",
        "second_metatarsal|foot/third_metatarsal",
        "second_metatarsal|foot/second_toe_proximal_phalanx",
        "third_metatarsal|foot/third_toe_proximal_phalanx",
        "hallux_distal_phalanx|foot/hallux_proximal_phalanx",
        "third_toe_middle_phalanx|foot/third_toe_proximal_phalanx",
        "fourth_toe_middle_phalanx|foot/fourth_toe_proximal_phalanx",
        "fifth_toe_middle_phalanx|foot/fifth_toe_proximal_phalanx",
        "medial_cuneiform|foot/navicular",
        "lateral_cuneiform|foot/navicular",
        "fourth_metatarsal|foot/lateral_cuneiform",
        "fourth_metatarsal|foot/third_metatarsal",
        "fourth_metatarsal|foot/fourth_toe_proximal_phalanx",
        "fifth_metatarsal|foot/fifth_toe_proximal_phalanx",
        "second_toe_middle_phalanx|foot/second_toe_proximal_phalanx",
        "second_toe_distal_phalanx|foot/second_toe_middle_phalanx",
        "third_toe_distal_phalanx|foot/third_toe_middle_phalanx",
        "fourth_toe_distal_phalanx|foot/fourth_toe_middle_phalanx",
        "fifth_toe_distal_phalanx|foot/fifth_toe_middle_phalanx",
    ]:
        found["canonical/bones/foot/" + pair] = Classification(
            "foot_articulation_precedence",
            articular,
            "Articulating foot bones.",
        )
    for n in range(2, 7):
        found[
            "canonical/spine/cervical/"
            + String(n)
            + "|cervical/"
            + String(n + 1)
        ] = Classification(
            "cervical_pillar_endplane_extent",
            articular,
            (
                "Facet region. The rounded pillar ends crossed the disc space"
                " into the next pillar."
            ),
        )
    return found^


def tool_sha256(root: String) raises -> String:
    """Return this tool's SHA-256.

    Args:
        root: The repository root.

    Returns:
        The hexadecimal digest.

    Raises:
        Error: If the tool cannot be read.
    """
    return file_sha256(root + "/" + TOOL)


def _sorted_join(a: String, b: String) -> String:
    """Return two names in order, joined by `|`."""
    if b < a:
        return b + "|" + a
    return a + "|" + b


def legacy_pair_ids(catalog: List[Component]) raises -> List[Set[String]]:
    """Return the complete legacy pair contract from the checked catalog.

    Args:
        catalog: The validated components.

    Returns:
        The pair identities of `bones`, `knee` and `spine`, in that order.

    Raises:
        Error: If the counts are not 435, 30 and 67.
    """
    var expected = List[Set[String]]()
    for _ in range(3):
        expected.append(Set[String]())
    for index in range(len(catalog)):
        for other in range(index + 1, len(catalog)):
            var group = legacy_pair_group(catalog[index], catalog[other])
            if group.byte_length() > 0:
                var slot = 0 if group == "bones" else 1
                expected[slot].add(
                    "canonical/"
                    + group
                    + "/"
                    + _sorted_join(
                        catalog[index].label.replace(" ", "_"),
                        catalog[other].label.replace(" ", "_"),
                    )
                )
    for region in ["thoracolumbar", "cervical"]:
        var first = 0 if region == "thoracolumbar" else 2
        var stop = 17 if region == "thoracolumbar" else 8
        for index in range(first, stop):
            var body = region + "/" + String(index)
            var disc = body + "/disc"
            expected[2].add("canonical/spine/" + _sorted_join(body, disc))
            if region == "thoracolumbar" and index == 16:
                continue
            var below = String(
                "thoracolumbar/0"
            ) if region == "cervical" and index == 7 else region + "/" + String(
                index + 1
            )
            expected[2].add("canonical/spine/" + _sorted_join(body, below))
            expected[2].add("canonical/spine/" + _sorted_join(below, disc))
    if (
        len(expected[0]) != 435
        or len(expected[1]) != 30
        or len(expected[2]) != 67
    ):
        raise Error("legacy pair catalog does not match the 532-pair contract")
    return expected^


struct Found(Copyable, Movable):
    """One legacy pair at every grid width."""

    var group: String
    """The legacy group."""
    var rows: List[Int]
    """The pair record at each width, in `steps_mm` order."""

    def __init__(out self, group: String):
        """Start a pair with no records.

        Args:
            group: The legacy group.
        """
        self.group = group
        self.rows = List[Int]()


def sweep[
    P: Prober
](
    mut tree: JsonTree,
    mut prober: P,
    probe: String,
    catalog: List[Component],
) raises -> Tuple[List[String], Dict[String, Found]]:
    """Return every legacy pair record at each grid width.

    Args:
        tree: The tree for the records.
        prober: The probe runner.
        probe: The probe path.
        catalog: The validated components.

    Returns:
        The pair identities in first-seen order, and each pair's records.

    Raises:
        Error: If a grid's pair inventory differs from the contract, or a
            pair is missing at one width.
    """
    var order = List[String]()
    var found = Dict[String, Found]()
    var expected = legacy_pair_ids(catalog)
    var steps = steps_mm()
    for step in steps:
        var groups = tree.object()
        for mode in legacy_groups():
            var rows = tree.array()
            for row in prober.rows(tree, probe, mode, "none", step):
                tree.append(rows, row)
            tree.set(groups, mode, rows)
        _ = annotate_diagnostics(tree, groups)
        var names = legacy_groups()
        for slot in range(len(names)):
            var group = names[slot]
            var rows = tree.items(tree.item(groups, group))
            var observed = Set[String]()
            for row in rows:
                if tree.is_text(tree.item(row, "record"), "pair"):
                    observed.add(tree.text(tree.item(row, "pair_id")))
            if observed != expected[slot]:
                raise Error(
                    group
                    + " diagnostic pair inventory differs at "
                    + step.text()
                    + " mm"
                )
            for row in rows:
                if tree.is_text(tree.item(row, "record"), "pair"):
                    var pair = tree.text(tree.item(row, "pair_id"))
                    if not pair in found:
                        found[pair] = Found(group)
                        order.append(pair)
                    found[pair].rows.append(row)
    for pair in order:
        if len(found[pair].rows) != len(steps):
            raise Error("a legacy pair is missing at one grid width")
    return (order^, found^)


def witness_request(
    tree: JsonTree, group: String, row: Int, labels: Dict[String, Int]
) raises -> Tuple[String, String]:
    """Return the probe mode and part that localize one legacy pair.

    Args:
        tree: The tree.
        group: The legacy group.
        row: The pair record.
        labels: Each component label and its catalog index.

    Returns:
        The mode and the part.

    Raises:
        Error: For a spine pair that is not two neighboring bodies, or a
            label that is not in the catalog.
    """
    if group == "spine":
        var first = tree.text(tree.item(row, "first"))
        var second = tree.item(row, "second")
        var slash = first.find("/")
        var region = String(first[byte=:slash]) if slash >= 0 else first
        var number = (
            String(first[byte = slash + 1 :]) if slash >= 0 else String()
        )
        var digits = number.byte_length() > 0
        for byte in number.as_bytes():
            if byte < 48 or byte > 57:
                digits = False
        if (
            not (region == "cervical" or region == "thoracolumbar")
            or not digits
            or not tree.is_text(second, region + "/" + String(Int(number) + 1))
        ):
            raise Error(
                "no localization for spine pair "
                + tree.text(tree.item(row, "pair_id"))
            )
        return ("spine-witness", first)
    var first = tree.text(tree.item(row, "first"))
    var second = tree.text(tree.item(row, "second"))
    var i = labels.get(first)
    if not i:
        raise Error(py_repr(first))
    var j = labels.get(second)
    if not j:
        raise Error(py_repr(second))
    var low = min(i.value(), j.value())
    var high = max(i.value(), j.value())
    return ("pairs", "witness:" + String(low) + ":" + String(high))


def check_witness(tree: JsonTree, record: Int, row: Int) raises -> Int:
    """The witness pass must repeat the diagnostic grid exactly.

    Args:
        tree: The tree.
        record: The witness record.
        row: The diagnostic pair record.

    Returns:
        The witness record.

    Raises:
        Error: If the witness pass changed a count, the volume or the field
            witness.
    """
    for key in ["samples", "overlap_samples", "overlap_volume_m3"]:
        if not tree.equal(tree.item(record, key), tree.item(row, key)):
            raise Error("witness pass changed " + key)
    if tree.truthy(tree.item(row, "samples")) and not tree.equal(
        tree.item(record, "signed_field_witness_m"),
        tree.item(row, "signed_field_witness_m"),
    ):
        raise Error("witness pass changed the field witness")
    return record


def status(tree: JsonTree, grids: List[Int]) raises -> String:
    """Name what the samples show, without a clearance claim.

    Args:
        tree: The tree.
        grids: The witness records of one pair.

    Returns:
        `common_interior_found` or `no_common_interior_sampled`.

    Raises:
        Error: For a record without a numeric `overlap_samples`.
    """
    for grid in grids:
        if tree.value(tree.item(grid, "overlap_samples")) > 0:
            return "common_interior_found"
    var refined = List[Int]()
    for grid in grids:
        var value = tree.get(grid, "refined_field_witness_m")
        if not tree.is_null(value):
            refined.append(value)
    for value in refined:
        if tree.value(value) < 0:
            return "common_interior_found"
    return "no_common_interior_sampled"


def _py_list(items: List[String]) -> String:
    """Return `repr()` of a list of strings."""
    var out = String("[")
    for index in range(len(items)):
        if index > 0:
            out += ", "
        out += py_repr(items[index])
    return out + "]"


def _text_object(
    mut tree: JsonTree, entries: List[Tuple[String, String]]
) raises -> Int:
    """Return an object of string members."""
    var node = tree.object()
    for entry in entries:
        tree.set_text(node, entry[0], entry[1])
    return node


def build[
    P: Prober
](
    mut tree: JsonTree,
    mut prober: P,
    probe: String,
    provenance: Int,
    spec: Spec,
    root: String,
) raises -> Int:
    """Localize every tracked pair and assemble the evidence.

    Args:
        tree: The tree for the evidence.
        prober: The probe runner.
        probe: The probe path.
        provenance: The probe provenance record.
        spec: The template.
        root: The repository root.

    Returns:
        The evidence object.

    Raises:
        Error: For an invalid catalog or inventory, an unclassified overlap,
            or a witness pass that disagrees with its grid.
    """
    var catalog = validate_catalog(
        tree, prober.rows(tree, probe, "pairs", "catalog", Num(5, True))
    )
    var labels = Dict[String, Int]()
    for index in range(len(catalog)):
        labels[catalog[index].label] = tree.int_value(
            tree.item(catalog[index].node, "index")
        )
    var swept = sweep(tree, prober, probe, catalog)
    var found = swept[1].copy()
    var missing = List[String]()
    var tracked = Set[String]()
    for pair in issue_595_pairs():
        tracked.add(pair)
        if not pair in found:
            missing.append(pair)
    if len(missing) > 0:
        raise Error(
            "issue pairs are not in the legacy diagnostics: "
            + _py_list(missing)
        )
    for pair in swept[0]:
        for row in found[pair].rows:
            if tree.value(tree.item(row, "overlap_samples")) > 0:
                tracked.add(pair)
    var ordered = List[String]()
    for pair in tracked:
        ordered.append(pair)
    sort(ordered)
    var issue = Set[String]()
    for pair in issue_595_pairs():
        issue.add(pair)
    var known = classification()
    var steps = steps_mm()
    var pairs = tree.array()
    for pair in ordered:
        if not pair in known:
            raise Error("unclassified sampled overlap: " + pair)
        var entry = found[pair].copy()
        var grids = List[Int]()
        for position in range(len(steps)):
            var row = entry.rows[position]
            var request = witness_request(tree, entry.group, row, labels)
            var records = prober.rows(
                tree, probe, request[0], request[1], steps[position]
            )
            if len(records) != 1 or not tree.is_text(
                tree.get(records[0], "record"), "witness"
            ):
                raise Error("witness probe returned the wrong record count")
            var record = check_witness(tree, records[0], row)
            _ = tree.item(record, "record")
            _ = tree.pop(record, "record")
            for key in ["first", "second", "first_id", "second_id"]:
                _ = tree.pop(record, key)
            grids.append(record)
        var rule = known[pair].copy()
        var first_row = entry.rows[0]
        var item = tree.object()
        tree.set_text(item, "pair_id", pair)
        tree.set_text(item, "group", entry.group)
        tree.set(item, "first", tree.clone(tree.item(first_row, "first")))
        tree.set(item, "second", tree.clone(tree.item(first_row, "second")))
        tree.set(item, "frame_id", tree.clone(tree.item(first_row, "frame_id")))
        tree.set_flag(item, "listed_in_issue_595", pair in issue)
        tree.set_text(item, "classification", rule.kind)
        tree.set_text(item, "interface_rule", rule.rule)
        tree.set_text(item, "note", rule.note)
        var array = tree.array()
        for grid in grids:
            tree.append(array, grid)
        tree.set(item, "grids", array)
        tree.set_text(item, "status", status(tree, grids))
        tree.append(pairs, item)
    var counts = tree.object()
    for position in range(len(steps)):
        var tally = tree.object()
        for group in legacy_groups():
            var count = 0
            for pair in swept[0]:
                if (
                    found[pair].group == group
                    and tree.value(
                        tree.item(found[pair].rows[position], "overlap_samples")
                    )
                    > 0
                ):
                    count += 1
            tree.set(tally, group, tree.integer(count))
        tree.set(counts, steps[position].text(), tally)
    var result = tree.object()
    tree.set(result, "schema_version", tree.integer(SCHEMA_VERSION))
    tree.set_text(result, "issue", ISSUE)
    tree.set_text(
        result,
        "result_label",
        "template geometry evidence; not clearance or biomechanical validation",
    )
    tree.set(result, "build_provenance", provenance)
    tree.set_text(result, "tool_sha256", tool_sha256(root))
    var spec_node = tree.object()
    tree.set(spec_node, "stature_m", tree.number(spec.stature_m))
    tree.set_text(spec_node, "sex", spec.sex)
    tree.set_text(spec_node, "side", spec.side)
    tree.set_text(spec_node, "athleticism", spec.athleticism)
    tree.set(result, "spec", spec_node)
    var widths = tree.array()
    for step in steps:
        tree.append(widths, step.put(tree))
    tree.set(result, "steps_mm", widths)
    tree.set(result, "checked_pairs_per_step", tree.integer(len(swept[0])))
    tree.set(result, "pairs_with_sampled_common_interior", counts)
    tree.set_text(
        result,
        "reproduction",
        "mojo run -I . tools/anatomy_overlaps.mojo --build --output <file>",
    )
    tree.set(result, "interface_rules", _text_object(tree, rules()))
    tree.set(result, "classes", _text_object(tree, classes()))
    tree.set(result, "pairs", pairs)
    tree.set(
        result,
        "limits",
        tree.strings(
            [
                (
                    "A refined witness searches two cubes around the grid"
                    " witness only. It is not a global minimum."
                ),
                (
                    "A negative field value is a point inside both canonical"
                    " fields. It is not a penetration depth."
                ),
                (
                    "No sampled common interior does not prove clearance."
                    " Thin overlap can lie between samples."
                ),
                (
                    "Field values are float32. Interfaces between differently"
                    " placed frames are exact only to coordinate roundoff."
                ),
                (
                    "Lower-limb tissue pairs from #596 are outside this"
                    " localization. The template report retains their"
                    " findings."
                ),
                (
                    "No clinical, engineering or biological acceptance"
                    " threshold is applied."
                ),
            ]
        ),
    )
    return result


def default_spec() -> Spec:
    """Return the canonical template the evidence measures.

    Returns:
        The 1.8288 m male, right side, untoned template.
    """
    return Spec(1.8288, "male", "right", "untoned")


def refuse_tool_change(built: String, before: String, after: String) raises:
    """Refuse evidence when the tool changed while it ran.

    Args:
        built: The tool digest the evidence records.
        before: The tool digest read before the build.
        after: The tool digest read after the build.

    Raises:
        Error: If the digests differ.
    """
    if built != before or after != before:
        raise Error(
            "overlap tool changed during execution; rerun before reporting"
        )


def run(arguments: List[String]) raises -> Tuple[Int, String, String]:
    """Run the tool from the repository root.

    Args:
        arguments: The arguments, without the program name.

    Returns:
        The exit status, the standard output and the standard error.

    Raises:
        Error: Never for a localization failure, which is a message and
            status 1.
    """
    var options = parse_options(
        arguments, PROGRAM, USAGE, HELP, report_options=False
    )
    if options.status == -1:
        return (0, options.message, String())
    if options.status != 0:
        return (options.status, String(), options.message)
    try:
        var root = realpath(".")
        var spec = default_spec()
        var tree = JsonTree()
        var probe = resolve_path(options.probe)
        var provenance = prepare_probe(
            tree, root, probe, options.mojo, options.build
        )
        var snapshot = source_snapshot(root)
        var metadata = _read_bytes(sidecar(probe))
        var digest = tool_sha256(root)
        var prober = NativeProbe(spec, root, False)
        var result = build(tree, prober, probe, provenance, spec, root)
        verify_report_inputs(root, probe, tree, provenance, snapshot, metadata)
        refuse_tool_change(
            tree.text(tree.item(result, "tool_sha256")),
            digest,
            tool_sha256(root),
        )
        write_report(options.output, tree.dumps(result) + "\n")
    except error:
        return (
            1,
            String(),
            "anatomy overlap localization failed: " + String(error) + "\n",
        )
    return (
        0,
        display_path(options.output) + ": localized evidence; not clearance\n",
        String(),
    )


def main() raises:
    """Run the tool and exit with its status.

    Raises:
        Error: Never; a failure is a message and a status.
    """
    var given = argv()
    var arguments = List[String]()
    for index in range(1, len(given)):
        arguments.append(String(given[index]))
    var outcome = run(arguments)
    print(outcome[1], end="")
    print(outcome[2], end="", file=stderr)
    exit(outcome[0])
