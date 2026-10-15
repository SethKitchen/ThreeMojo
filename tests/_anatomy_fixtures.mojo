# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Synthetic probe records for the tests of the anatomy report tools.

No fixture runs the native probe. A catalog has the 134 named components of
the contract, each a 2 cm box at the knee origin, with its identity as its
label.
"""

from tools._json_tree import JsonTree
from tools.anatomy_validity import (
    Num,
    Prober,
    pair_region_counts,
    regions,
)


def segment_row(
    mut tree: JsonTree,
    name: String = "thigh",
    low: Float64 = 0.0,
    high: Float64 = 1.0,
    step: Float64 = 0.02,
) raises -> Int:
    """Return one valid segment record.

    Args:
        tree: The tree.
        name: The segment.
        low: The low cut plane, in meters.
        high: The high cut plane, in meters.
        step: The grid step, in meters.

    Returns:
        The record.

    Raises:
        Error: Never for a fresh tree.
    """
    var row = tree.object()
    tree.set_text(row, "record", "segment")
    tree.set_text(row, "segment", name)
    tree.set(row, "step_m", tree.number(step))
    tree.set(row, "mass_kg", tree.number(1.0))
    tree.set(row, "length_m", tree.number(1.0))
    tree.set(row, "center_m", tree.numbers([0.0, (low + high) / 2, 0.0]))
    tree.set(row, "low_m", tree.numbers([-0.1, low, -0.1]))
    tree.set(row, "high_m", tree.numbers([0.1, high, 0.1]))
    tree.set(
        row,
        "inertia_kg_m2",
        tree.numbers([0.1, 0.02, 0.1, 0.0, 0.0, 0.0]),
    )
    var accounts = tree.object()
    for region_name in regions():
        var region = tree.object()
        var muscle = region_name == "muscle"
        tree.set(region, "mass_kg", tree.number(1.0 if muscle else 0.0))
        tree.set(region, "volume_m3", tree.number(0.001 if muscle else 0.0))
        tree.set(accounts, region_name, region)
    tree.set(row, "regions", accounts)
    return row


def catalog_ids() -> List[Tuple[String, String]]:
    """Return each synthetic component identity and its family.

    Returns:
        The 134 components, in catalog order.
    """
    var found = List[Tuple[String, String]]()
    for region in ["leg", "foot"]:
        for family in pair_region_counts(region):
            for part in range(family[1]):
                var name: String
                if region == "leg" and family[0] == "bone":
                    name = ["femur", "tibia", "fibula", "patella"][part]
                elif family[0] == "knee":
                    name = ["cartilage", "medial", "lateral", "mcl", "lcl"][
                        part
                    ]
                else:
                    name = String(part)
                found.append((region + "/" + family[0] + "/" + name, family[0]))
    return found^


def catalog(mut tree: JsonTree) raises -> List[Int]:
    """Return the synthetic catalog records.

    Args:
        tree: The tree.

    Returns:
        The 134 component records.

    Raises:
        Error: Never for a fresh tree.
    """
    var rows = List[Int]()
    var ids = catalog_ids()
    for index in range(len(ids)):
        var row = tree.object()
        tree.set_text(row, "record", "component")
        tree.set(row, "index", tree.integer(index))
        tree.set_text(row, "component_id", ids[index][0])
        tree.set_text(row, "label", ids[index][0])
        tree.set_text(row, "family", ids[index][1])
        tree.set(row, "low_m", tree.numbers([0.0, 0.0, 0.0]))
        tree.set(row, "high_m", tree.numbers([0.02, 0.02, 0.02]))
        tree.set(row, "translation_m", tree.numbers([0.0, 0.0, 0.0]))
        rows.append(row)
    return rows^


def pair_record(
    mut tree: JsonTree, first: String, second: String
) raises -> Int:
    """Return a measured pair record with no overlap.

    Args:
        tree: The tree.
        first: The first identity, which is also its label.
        second: The second identity.

    Returns:
        The record.

    Raises:
        Error: Never for a fresh object.
    """
    var row = tree.object()
    tree.set_text(row, "record", "pair")
    tree.set_text(row, "first_id", first)
    tree.set_text(row, "second_id", second)
    tree.set_text(row, "first", first)
    tree.set_text(row, "second", second)
    tree.set(row, "samples", tree.integer(1))
    tree.set(row, "overlap_samples", tree.integer(0))
    tree.set(row, "bounds_gap_m", tree.integer(0))
    tree.set(row, "overlap_volume_m3", tree.integer(0))
    tree.set(row, "signed_field_witness_m", tree.number(0.1))
    return row


def is_legacy(
    first: Tuple[String, String], second: Tuple[String, String]
) -> String:
    """Return the legacy group of two synthetic components.

    Args:
        first: An identity and its family.
        second: Another identity and its family.

    Returns:
        `bones`, `knee`, or an empty string.
    """
    if first[1] == "bone" and second[1] == "bone":
        return "bones"
    var both_leg = first[0].startswith("leg/") and second[0].startswith("leg/")
    var knee = first[1] == "knee" or second[1] == "knee"
    var known = (first[1] == "knee" or first[1] == "bone") and (
        second[1] == "knee" or second[1] == "bone"
    )
    if (first[1] == "knee" and second[1] == "knee") or (
        knee and known and both_leg
    ):
        return "knee"
    return String()


def legacy_rows(mut tree: JsonTree, group: String) raises -> List[Int]:
    """Return the legacy pair records of one group, in catalog order.

    Args:
        tree: The tree.
        group: `bones` or `knee`.

    Returns:
        The records, before annotation.

    Raises:
        Error: Never for a fresh tree.
    """
    var ids = catalog_ids()
    var found = List[Int]()
    for i in range(len(ids)):
        for j in range(i + 1, len(ids)):
            if is_legacy(ids[i], ids[j]) == group:
                found.append(pair_record(tree, ids[i][0], ids[j][0]))
    return found^


def batch_rows(
    mut tree: JsonTree, part: String, swapped: Bool = False
) raises -> List[Int]:
    """Answer a pair batch request `i:start:stop`.

    Args:
        tree: The tree.
        part: The request.
        swapped: True to answer each pair in the wrong order.

    Returns:
        One record for each requested pair.

    Raises:
        Error: If the request is not three integers.
    """
    var fields = part.split(":")
    var i = Int(String(fields[0]))
    var ids = catalog_ids()
    var found = List[Int]()
    for j in range(Int(String(fields[1])), Int(String(fields[2]))):
        if swapped:
            found.append(pair_record(tree, ids[j][0], ids[i][0]))
        else:
            found.append(pair_record(tree, ids[i][0], ids[j][0]))
    return found^


struct CatalogProbe(Prober):
    """Answer catalog and batch requests from the synthetic catalog."""

    var failure: String
    """`empty_batch`, `wrong_identity`, or empty for correct answers."""
    var requests: Int
    """The number of requests answered."""

    def __init__(out self, failure: String = ""):
        """Answer correctly, or with one kind of failure.

        Args:
            failure: The failure, or empty.
        """
        self.failure = failure
        self.requests = 0

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
            mode: `pairs`.
            part: `catalog` or a batch request.
            step: Ignored.

        Returns:
            The records.

        Raises:
            Error: For another mode.
        """
        self.requests += 1
        if mode != "pairs":
            raise Error("unexpected mode " + mode)
        if part == "catalog":
            return catalog(tree)
        if self.failure == "empty_batch":
            return List[Int]()
        return batch_rows(tree, part, self.failure == "wrong_identity")
