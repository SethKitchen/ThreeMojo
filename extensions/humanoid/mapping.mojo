# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Explicit canonical-to-visual mappings and their invalidation.

Each mapping names one path from canonical data to a visual asset:
identity, expression and jaw, eyes, dentition, skin weights and level of
detail. A mapping record holds a source fingerprint and a topology
fingerprint. A changed source version or a changed topology invalidates
the record, and `require_mapping` refuses it.

Every mapping is visual. None carries a tested physical correspondence,
so `require_physical_mapping` refuses each one. The dental mapping keeps
two representations: the authored `BONES` teeth and the scanned `MOUTH`
teeth. They stay separate until a tested correspondence exists.

This is not a three.js port. See Extensions.
"""

from core.user_data import UserData

comptime MAPPING_SCHEMA = 1


@fieldwise_init
struct MappingKind(Equatable, ImplicitlyCopyable, Writable):
    """One named canonical-to-visual mapping.

    The type stops a bare integer at compile time. A value that is not a
    named mapping is still constructible, and each boundary refuses it.

    Args:
        value: A named mapping's value.

    Returns:
        A typed mapping kind.

    Raises:
        None: Boundaries refuse unnamed values.
    """

    var value: Int

    def is_valid(self) -> Bool:
        """Return whether this mapping is named.

        Returns:
            True for `IDENTITY_MAP` through `LOD_MAP`.
        """
        return self.value >= IDENTITY_MAP.value and self.value <= LOD_MAP.value


# Face-shape genes to the scanned identity modes.
comptime IDENTITY_MAP = MappingKind(0)
# Expression weights to scanned skin, teeth, gums and tongue.
comptime EXPRESSION_JAW_MAP = MappingKind(1)
# Identity mode shifts to the eyeball centers.
comptime EYE_MAP = MappingKind(2)
# The authored and the scanned dentitions.
comptime DENTAL_MAP = MappingKind(3)
# Rig joints to skin weights on the visual meshes.
comptime SKIN_WEIGHT_MAP = MappingKind(4)
# A full-resolution visual mesh to its decimated level of detail.
comptime LOD_MAP = MappingKind(5)


def mapping_label(kind: MappingKind) -> String:
    """Return the stable name of a mapping.

    Args:
        kind: A mapping kind, named or not.

    Returns:
        A lowercase name such as `"identity"`, or `"mapping"` when
        `kind` is not named.
    """
    if not kind.is_valid():
        return "mapping"
    var names: List[String] = [
        "identity",
        "expression_jaw",
        "eyes",
        "dental",
        "skin_weights",
        "lod",
    ]
    return names[kind.value]


def named_mappings() -> List[MappingKind]:
    """Return every named mapping in a stable order.

    Returns:
        `IDENTITY_MAP` through `LOD_MAP`.
    """
    var kinds = List[MappingKind]()
    for value in range(LOD_MAP.value + 1):  # pragma: no branch
        kinds.append(MappingKind(value))
    return kinds^


def _scope(kind: MappingKind) -> String:
    """Return what a named mapping carries and what it does not."""
    if kind == IDENTITY_MAP:
        return (
            "face-shape genes weigh scanned identity modes; the canonical"
            " skull, mandible, muscles and masses do not follow"
        )
    if kind == EXPRESSION_JAW_MAP:
        return (
            "expression weights move scanned skin, teeth, gums and tongue;"
            " the canonical mandible and joint loads do not follow"
        )
    if kind == EYE_MAP:
        return (
            "identity mean shifts place the eyeballs; no orbit containment"
            " is guaranteed"
        )
    if kind == DENTAL_MAP:
        return (
            "authored BONES teeth and scanned MOUTH teeth remain two"
            " separate representations"
        )
    if kind == SKIN_WEIGHT_MAP:
        return (
            "rig joints weigh visual vertices for animation; no tissue or"
            " load transfer"
        )
    return (
        "decimation changes visual topology; canonical mass and contact"
        " geometry stay in the canonical record"
    )


def mapping_record(
    kind: MappingKind, source: String, topology: String
) raises -> UserData:
    """Return a versioned visual mapping record.

    Args:
        kind: The named mapping.
        source: The fingerprint of the mapping's source version, such as
            a verified asset SHA-256 or a rig revision.
        topology: The fingerprint of the topology that the mapping
            indexes.

    Returns:
        The mapping's name, fingerprints, scope and capabilities. Its
        physical correspondence is always unsupported.

    Raises:
        Error: If `kind` is not named or a fingerprint is empty.
    """
    if not kind.is_valid():
        raise Error("A humanoid mapping must be a named kind")
    if source == "" or topology == "":
        raise Error("A humanoid mapping needs source and topology fingerprints")
    var record = UserData()
    record.set_number("schema_version", MAPPING_SCHEMA)
    record.set_string("kind", mapping_label(kind))
    record.set_string("source_fingerprint", source)
    record.set_string("topology_fingerprint", topology)
    record.set_string("scope", _scope(kind))
    record.set_boolean("visual_use", True)
    record.set_boolean("physical_correspondence", False)
    if kind == DENTAL_MAP:
        record.set_json(
            "representations",
            '["authored-bones-teeth-field","scanned-mouth-teeth"]',
        )
    record.set_string(
        "invalidation",
        "a changed source or topology fingerprint invalidates this mapping",
    )
    return record^


def require_mapping(
    stored: UserData, kind: MappingKind, source: String, topology: String
) raises:
    """Refuse a mapping record that a changed source or topology invalidated.

    Args:
        stored: A mapping record, as loaded.
        kind: The mapping the caller expects.
        source: The current source fingerprint.
        topology: The current topology fingerprint.

    Raises:
        Error: If `kind` is not named, the record is of another kind or
            schema, its source or topology changed, or any other field
            was edited.
    """
    var expected = mapping_record(kind, source, topology)
    var label = mapping_label(kind)
    if not stored.has("kind") or stored.string("kind") != label:
        raise Error("Humanoid mapping is not the " + label + " mapping")
    if (
        not stored.has("source_fingerprint")
        or stored.string("source_fingerprint") != source
    ):
        raise Error("Humanoid " + label + " mapping source changed; rebuild it")
    if (
        not stored.has("topology_fingerprint")
        or stored.string("topology_fingerprint") != topology
    ):
        raise Error(
            "Humanoid " + label + " mapping topology changed; rebuild it"
        )
    if stored.to_json() != expected.to_json():
        raise Error("Humanoid " + label + " mapping was edited; rebuild it")


def require_physical_mapping(kind: MappingKind) raises:
    """Refuse every physical use of a visual mapping.

    No mapping has a tested physical correspondence. A future mapping can
    pass only with independent evidence and a new revision.

    Args:
        kind: The mapping a caller wants to use physically.

    Raises:
        Error: Always. The message names the mapping, or refuses an
            unnamed kind.
    """
    if not kind.is_valid():
        raise Error("A humanoid mapping must be a named kind")
    raise Error(
        "Physical "
        + mapping_label(kind)
        + " correspondence is unsupported: no tested canonical-to-visual"
        " map exists"
    )
