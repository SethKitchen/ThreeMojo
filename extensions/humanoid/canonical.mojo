# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""A versioned canonical record, kept apart from every visual asset.

`canonical_record` evaluates canonical parts from a `HumanoidSpec` alone.
It never reads a visual mesh, a triangle budget, a material or a bake. So
visual widening, decimation and baking cannot change it. Each part has a
stable ID, tissue labels, a frame and SI geometry. Parts with sampled
properties carry them in SI units:

| Part | Geometry | Physical properties |
|---|---|---|
| Skull, mandible, authored teeth | Isosurface mesh fingerprints and bounds | Sampled bone-tissue mass and volumes; no tensor |
| Eyeballs | Mesh fingerprints, center and radius | None; no density is assigned |
| Thigh, shank and foot, each side | Integration bounds | Mass, center and full tensor about the center of mass, with region masses |

The values are template estimates. They are not validated for a real
person. The record does not cover the whole body or establish
convergence. Missing properties stay `null`; nothing is inferred from a
visual mesh or a guessed density.

This is not a three.js port. See Extensions.
"""

from core.buffer_geometry import POSITION, BufferGeometry
from core.user_data import UserData, json_number_text
from extensions.anatomy.tissue import cortical_tissue, trabecular_tissue
from extensions.humanoid.fidelity import (
    canonical_inputs,
    geometry_fingerprint,
    json_fingerprint,
    spec_fingerprint,
)
from extensions.humanoid.side import LEFT, RIGHT, BodySide
from extensions.humanoid.skeleton.head.bones.dimensions import (
    MANDIBLE,
    SKULL,
    TEETH,
    HeadBone,
)
from extensions.humanoid.skeleton.head.bones.geometry import (
    head_bone_from_dimensions,
)
from extensions.humanoid.skeleton.head.bones.mass import (
    head_bone_mass_from_dimensions,
)
from extensions.humanoid.skeleton.head.eyes import (
    eye_center,
    eye_radius,
    eyeball_mesh,
)
from extensions.humanoid.skeleton.head.frame import (
    HeadMuscleDimensions,
    head_muscle_dimensions,
)
from extensions.humanoid.skeleton.limb.inertia import (
    FOOT_SEGMENT,
    SHANK,
    THIGH,
    LimbSegment,
    segment_estimate,
)
from extensions.humanoid.skeleton.limb.regions import LimbRegion, region_label
from extensions.humanoid.spec import HumanoidSpec
from math.vector3 import Vector3
from units.si import (
    CUBIC_METER,
    KILOGRAM,
    KILOGRAM_SQUARE_METER,
    Length,
    METER,
    MILLIMETER,
)

comptime CANONICAL_RECORD_SCHEMA = 1
comptime CANONICAL_RECORD_REVISION = "threemojo-canonical-record-v1"
comptime CANONICAL_KEY = "threemojo_humanoid_canonical"
# Sampling of the record. A change is a new record revision.
comptime BONE_MESH_DETAIL = 16
comptime EYE_MESH_DETAIL = 12
comptime BONE_MASS_STEP = Length(5.0, MILLIMETER)
comptime SEGMENT_STEP = Length(20.0, MILLIMETER)
comptime PELVIS_FRAME = "right-handed-y-up-x-right-z-anterior"
comptime PELVIS_ORIGIN = "pelvis-frame-origin"
comptime LEG_FRAME = "right-handed-y-proximal-x-right-z-anterior"
comptime LEG_ORIGIN = "tibiofemoral-joint-line"


@fieldwise_init
struct CanonicalPart(Equatable, ImplicitlyCopyable, Writable):
    """One part of the canonical record.

    The type stops a bare integer at compile time. A value that is not a
    named part is still constructible, and each boundary refuses it.

    Args:
        value: A named part's value.

    Returns:
        A typed canonical part.

    Raises:
        None: Boundaries refuse unnamed values.
    """

    var value: Int

    def is_valid(self) -> Bool:
        """Return whether this part is named.

        Returns:
            True for `SKULL_PART` through `LEFT_FOOT_PART`.
        """
        return (
            self.value >= SKULL_PART.value
            and self.value <= LEFT_FOOT_PART.value
        )


comptime SKULL_PART = CanonicalPart(0)
comptime MANDIBLE_PART = CanonicalPart(1)
# The authored `BONES` dentition, not the scanned `MOUTH` teeth.
comptime AUTHORED_TEETH_PART = CanonicalPart(2)
comptime RIGHT_EYE_PART = CanonicalPart(3)
comptime LEFT_EYE_PART = CanonicalPart(4)
comptime RIGHT_THIGH_PART = CanonicalPart(5)
comptime RIGHT_SHANK_PART = CanonicalPart(6)
comptime RIGHT_FOOT_PART = CanonicalPart(7)
comptime LEFT_THIGH_PART = CanonicalPart(8)
comptime LEFT_SHANK_PART = CanonicalPart(9)
comptime LEFT_FOOT_PART = CanonicalPart(10)


def canonical_part_label(part: CanonicalPart) -> String:
    """Return the stable ID of a canonical part.

    Args:
        part: A canonical part, named or not.

    Returns:
        An ID such as `"head/skull"`, or `"canonical part"` when `part`
        is not named.
    """
    if not part.is_valid():
        return "canonical part"
    var names: List[String] = [
        "head/skull",
        "head/mandible",
        "head/teeth-authored",
        "head/eye-right",
        "head/eye-left",
        "leg-right/thigh",
        "leg-right/shank",
        "leg-right/foot",
        "leg-left/thigh",
        "leg-left/shank",
        "leg-left/foot",
    ]
    return names[part.value]


def named_canonical_parts() -> List[CanonicalPart]:
    """Return every named canonical part in a stable order.

    Returns:
        `SKULL_PART` through `LEFT_FOOT_PART`.
    """
    var parts = List[CanonicalPart]()
    for value in range(LEFT_FOOT_PART.value + 1):  # pragma: no branch
        parts.append(CanonicalPart(value))
    return parts^


def _array(values: List[Float32]) raises -> String:
    """Return SI values as a JSON array of exact Float32 values."""
    var text = String("[")
    for at in range(len(values)):  # pragma: no branch
        if at > 0:
            text += ","
        text += json_number_text(Float64(values[at]))
    return text + "]"


def _vector(value: Vector3) raises -> String:
    """Return a vector in meters as a JSON array."""
    return _array([value.x, value.y, value.z])


def _bounds(geometry: BufferGeometry) raises -> UserData:
    """Return a mesh's axis-aligned bounds in meters."""
    ref positions = geometry.attribute_view(String(POSITION))
    var low = positions.vector3(0)
    var high = low
    for vertex in range(positions.count()):  # pragma: no branch
        var p = positions.vector3(vertex)
        low = Vector3(min(low.x, p.x), min(low.y, p.y), min(low.z, p.z))
        high = Vector3(max(high.x, p.x), max(high.y, p.y), max(high.z, p.z))
    var bounds = UserData()
    bounds.set_json("low_m", _vector(low))
    bounds.set_json("high_m", _vector(high))
    return bounds^


def _bone_part(
    dimensions: HeadMuscleDimensions, bone: HeadBone, tissue: String
) raises -> UserData:
    """Return one head bone's mesh fingerprints and sampled mass."""
    var mesh = head_bone_from_dimensions(
        dimensions.head, bone, BONE_MESH_DETAIL
    )
    var geometry = geometry_fingerprint(mesh)
    geometry.set_string("kind", "isosurface-mesh")
    geometry.set_number("detail", Float64(BONE_MESH_DETAIL))
    var bounds = _bounds(mesh)
    geometry.set_json("low_m", bounds.json("low_m"))
    geometry.set_json("high_m", bounds.json("high_m"))
    var mass = head_bone_mass_from_dimensions(
        dimensions.head,
        bone,
        cortical_tissue(),
        trabecular_tissue(),
        BONE_MASS_STEP,
    )
    var physical = UserData()
    physical.set_number("mass_kg", Float64(mass.mass.to(KILOGRAM)))
    physical.set_number("envelope_m3", Float64(mass.envelope.to(CUBIC_METER)))
    physical.set_number(
        "cortical_region_m3", Float64(mass.cortical_region.to(CUBIC_METER))
    )
    physical.set_number(
        "trabecular_region_m3",
        Float64(mass.trabecular_region.to(CUBIC_METER)),
    )
    physical.set_number(
        "solid_tissue_m3", Float64(mass.solid_tissue.to(CUBIC_METER))
    )
    physical.set_number("step_m", Float64(BONE_MASS_STEP.to(METER)))
    physical.set_null("center_m")
    physical.set_null("inertia_kg_m2")
    physical.set_string("tensor", "unsupported; no sampled tensor")
    var part = UserData()
    part.set_json(
        "tissue_labels",
        '["' + tissue + '","cortical_tissue","trabecular_tissue"]',
    )
    part.set_string("frame", String(PELVIS_FRAME))
    part.set_string("origin_label", String(PELVIS_ORIGIN))
    part.set_json("geometry", geometry.to_json())
    part.set_json("physical_properties", physical.to_json())
    return part^


def _eye_part(
    dimensions: HeadMuscleDimensions, side: BodySide
) raises -> UserData:
    """Return one eyeball's mesh fingerprints; it has no density."""
    var mesh = eyeball_mesh(dimensions, side, EYE_MESH_DETAIL)
    var geometry = geometry_fingerprint(mesh)
    geometry.set_string("kind", "analytic-mesh")
    geometry.set_number("detail", Float64(EYE_MESH_DETAIL))
    geometry.set_json("center_m", _vector(eye_center(dimensions.head, side)))
    geometry.set_number("radius_m", Float64(eye_radius(dimensions.head)))
    var part = UserData()
    part.set_json("tissue_labels", '["eyeball-no-density-assigned"]')
    part.set_string("frame", String(PELVIS_FRAME))
    part.set_string("origin_label", String(PELVIS_ORIGIN))
    part.set_json("geometry", geometry.to_json())
    part.set_null("physical_properties")
    return part^


def _segment_part(
    spec: HumanoidSpec, segment: LimbSegment, side: BodySide
) raises -> UserData:
    """Return one leg segment's bounds and full sampled properties."""
    var estimate = segment_estimate(spec, segment, side, SEGMENT_STEP)
    var inertia = estimate.inertia
    var geometry = UserData()
    geometry.set_string("kind", "integration-bounds")
    geometry.set_json("low_m", _vector(estimate.low))
    geometry.set_json("high_m", _vector(estimate.high))
    var labels = String("[")
    var masses = UserData()
    var volumes = UserData()
    for value in range(7):  # pragma: no branch
        var region = LimbRegion(value)
        var label = region_label(region)
        if value > 0:
            labels += ","
        labels += '"' + label + '"'
        masses.set_number(
            label, Float64(estimate.region_mass(region).to(KILOGRAM))
        )
        volumes.set_number(
            label, Float64(estimate.region_volume(region).to(CUBIC_METER))
        )
    labels += "]"
    var physical = UserData()
    physical.set_number("mass_kg", Float64(inertia.mass.to(KILOGRAM)))
    physical.set_json("center_m", _vector(inertia.center))
    physical.set_json(
        "inertia_kg_m2",
        _array(
            [
                inertia.xx.to(KILOGRAM_SQUARE_METER),
                inertia.yy.to(KILOGRAM_SQUARE_METER),
                inertia.zz.to(KILOGRAM_SQUARE_METER),
                inertia.xy.to(KILOGRAM_SQUARE_METER),
                inertia.xz.to(KILOGRAM_SQUARE_METER),
                inertia.yz.to(KILOGRAM_SQUARE_METER),
            ]
        ),
    )
    physical.set_string("tensor_order", "xx,yy,zz,xy,xz,yz")
    physical.set_string("tensor_reference", "center-of-mass")
    physical.set_json("region_masses_kg", masses.to_json())
    physical.set_json("region_volumes_m3", volumes.to_json())
    physical.set_number("step_m", Float64(SEGMENT_STEP.to(METER)))
    var part = UserData()
    part.set_json("tissue_labels", labels)
    part.set_string("frame", String(LEG_FRAME))
    part.set_string("origin_label", String(LEG_ORIGIN))
    part.set_json("geometry", geometry.to_json())
    part.set_json("physical_properties", physical.to_json())
    return part^


def canonical_part_record(
    spec: HumanoidSpec, part: CanonicalPart
) raises -> UserData:
    """Return one canonical part's geometry, tissue labels and properties.

    Args:
        spec: The canonical inputs. No visual setting enters.
        part: The named part.

    Returns:
        The part's ID, tissue labels, frame, origin, SI geometry and SI
        physical properties, or `null` properties where none are sampled.

    Raises:
        Error: If `part` is not named or the spec is refused.
    """
    if not part.is_valid():
        raise Error("A canonical record part must be named")
    var record: UserData
    if part.value >= RIGHT_THIGH_PART.value:
        var segments = [THIGH, SHANK, FOOT_SEGMENT]
        var side = RIGHT
        if part.value >= LEFT_THIGH_PART.value:
            side = LEFT
        var segment = segments[(part.value - RIGHT_THIGH_PART.value) % 3]
        record = _segment_part(spec, segment, side)
    else:
        var dimensions = head_muscle_dimensions(spec)
        if part == SKULL_PART:
            record = _bone_part(dimensions, SKULL, "skull")
        elif part == MANDIBLE_PART:
            record = _bone_part(dimensions, MANDIBLE, "mandible")
        elif part == AUTHORED_TEETH_PART:
            record = _bone_part(dimensions, TEETH, "teeth-bone-tissue-proxy")
        elif part == RIGHT_EYE_PART:
            record = _eye_part(dimensions, RIGHT)
        else:
            record = _eye_part(dimensions, LEFT)
    record.set_string("part_id", canonical_part_label(part))
    return record^


def canonical_record(spec: HumanoidSpec) raises -> UserData:
    """Return the versioned canonical record of every named part.

    The record depends on the spec and this record revision only. It is
    independent of mesh budgets, visual widening, materials and bakes.

    Args:
        spec: The canonical inputs.

    Returns:
        The schema, revision, SI units, canonical inputs, every part and
        a digest of the parts. Engineering validity is always false.

    Raises:
        Error: If the spec is refused.
    """
    var inputs = canonical_inputs(spec)
    var parts = UserData()
    for part in named_canonical_parts():  # pragma: no branch
        parts.set_json(
            canonical_part_label(part),
            canonical_part_record(spec, part).to_json(),
        )
    var units = UserData()
    units.set_string("length", "meter")
    units.set_string("mass", "kilogram")
    units.set_string("volume", "cubic-meter")
    units.set_string("inertia", "kilogram-meter-squared")
    var record = UserData()
    record.set_number("schema_version", CANONICAL_RECORD_SCHEMA)
    record.set_string("revision", String(CANONICAL_RECORD_REVISION))
    record.set_json("units", units.to_json())
    record.set_json("canonical_inputs", inputs.to_json())
    record.set_string("spec_fingerprint", spec_fingerprint(spec))
    record.set_json("parts", parts.to_json())
    record.set_string("parts_digest", json_fingerprint(parts.to_json()))
    record.set_boolean("engineering_validated", False)
    record.set_string(
        "scope",
        (
            "template estimates of the listed parts; no whole-body, clinical"
            " or convergence claim"
        ),
    )
    return record^


def canonical_record_digest(record: UserData) -> String:
    """Return the fingerprint of a complete canonical record.

    Args:
        record: A record from `canonical_record`.

    Returns:
        Sixteen lowercase hexadecimal digits of its normalized JSON.
    """
    return json_fingerprint(record.to_json())


def require_canonical_record(stored: UserData, spec: HumanoidSpec) raises:
    """Refuse a canonical record that does not represent the spec exactly.

    The check evaluates the record again from the spec and compares every
    field. It never reads a visual mesh.

    Args:
        stored: A loaded canonical record.
        spec: The spec that the record must represent.

    Raises:
        Error: If the record has another schema or revision, represents
            another spec, or differs in any other field.
    """
    if not stored.has("schema_version") or stored.json(
        "schema_version"
    ) != String(CANONICAL_RECORD_SCHEMA):
        raise Error("Canonical record schema is unsupported; rebuild it")
    if not stored.has("revision") or stored.string("revision") != String(
        CANONICAL_RECORD_REVISION
    ):
        raise Error("Canonical record revision is stale; rebuild it")
    if not stored.has("spec_fingerprint") or stored.string(
        "spec_fingerprint"
    ) != spec_fingerprint(spec):
        raise Error("Canonical record represents a different spec")
    if stored.to_json() != canonical_record(spec).to_json():
        raise Error("Canonical record is stale or changed; rebuild it")
