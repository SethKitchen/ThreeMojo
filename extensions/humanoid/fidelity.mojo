# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Separate a humanoid's visual recipe from engineering capabilities.

The versioned recipe retains canonical SI inputs, not canonical geometry
or physical properties. It cannot certify anatomy, correspondence or an
asset's source. Visual realism never grants an engineering capability.
A producer must change its revision when its geometry or mapping changes.
"""

from core.user_data import UserData
from extensions.humanoid.genome import GENE_COUNT
from extensions.humanoid.spec import MAX_STATURE, MIN_STATURE, HumanoidSpec
from std.math import isfinite
from std.memory import bitcast

comptime FIDELITY_KEY = "threemojo_humanoid_fidelity"
comptime FIDELITY_SCHEMA = 1
# These are recipe versions, not upstream commit or checksum claims.
comptime CANONICAL_RECIPE = "threemojo-canonical-inputs-v1"
comptime GAME_RECIPE = "threemojo-game-skin-19-joints-v1"
comptime SCAN_RECIPE = "threemojo-ict-identity-expression-v1"


@fieldwise_init
struct HumanoidUse(Equatable, ImplicitlyCopyable, Writable):
    """A requested capability, independent of mesh quality.

    Args:
        value: A named capability's value.

    Returns:
        A typed capability request.

    Raises:
        None: Boundaries refuse unnamed values.
    """

    var value: Int

    def is_valid(self) -> Bool:
        """Return whether this capability is named.

        Returns:
            True for visual or engineering use.

        """
        return self == VISUAL_USE or self == ENGINEERING_USE


comptime VISUAL_USE = HumanoidUse(0)
comptime ENGINEERING_USE = HumanoidUse(1)


def require_humanoid_use(use: HumanoidUse) raises:
    """Refuse unsupported engineering use, even for the best visual mesh.

    Args:
        use: The requested capability.

    Raises:
        Error: If the capability is unnamed or engineering is requested.
    """
    if not use.is_valid():
        raise Error("Humanoid use must be a named capability")
    if use == ENGINEERING_USE:
        raise Error(
            "Engineering use is unsupported: visual identity, jaw, dental, "
            "skin-weight and LOD correspondence are not validated"
        )


def canonical_inputs(spec: HumanoidSpec) raises -> UserData:
    """Copy the complete accepted spec into a versioned SI recipe.

    Exact Float32 bit strings distinguish even adjacent input values.
    This function does not evaluate canonical geometry or mass.

    Args:
        spec: The immutable-by-value input recipe.

    Returns:
        Stature in meters, typed template values and all 43 gene values.

    Raises:
        Error: If the spec is outside its software input domain.
    """
    if not isfinite(spec.stature.value):
        raise Error("Canonical inputs require finite stature")
    if spec.stature.value < MIN_STATURE.value:
        raise Error("Canonical inputs require stature in the software range")
    if spec.stature.value > MAX_STATURE.value:
        raise Error("Canonical inputs require stature in the software range")
    if not spec.sex.is_valid():
        raise Error("Canonical inputs require a named sex")
    if not spec.athleticism.is_valid():
        raise Error("Canonical inputs require named athleticism")
    if not spec.genome.is_valid():
        raise Error("Canonical inputs require a valid genome")
    var data = UserData()
    data.set_number("schema_version", 1)
    data.set_number("stature_m", Float64(spec.stature.value))
    data.set_string(
        "stature_float32_bits",
        String(bitcast[DType.uint32](spec.stature.value)),
    )
    data.set_number("sex", Float64(spec.sex.value))
    data.set_number("athleticism", Float64(spec.athleticism.value))
    var genes = UserData()
    var bits = UserData()
    for at in range(GENE_COUNT):  # pragma: no branch
        genes.set_number(String(at), Float64(spec.genome.expressions[at]))
        bits.set_string(
            String(at),
            String(bitcast[DType.uint32](spec.genome.expressions[at])),
        )
    data.set_json("genes", genes.to_json())
    data.set_json("gene_float32_bits", bits.to_json())
    return data^


def humanoid_provenance(
    spec: HumanoidSpec,
    visual_settings: UserData,
    canonical_revision: String,
    visual_revision: String,
    asset_revision: String,
) raises -> UserData:
    """Return a fail-closed creation recipe for glTF node or scene extras.

    Revisions identify the producer's source and topology. They are caller
    assertions, not verified hashes or proof of a license. Use an explicit
    unknown marker when the converted asset has no pinned source manifest.
    Local coordinates are meters, right-handed, y-up, pelvis-origin.
    Parent and animation transforms remain in glTF nodes and channels.

    Args:
        spec: Canonical SI inputs, copied independently of visual settings.
        visual_settings: Every geometry, rig and appearance build option.
        canonical_revision: Canonical source or recipe revision.
        visual_revision: Visual topology, rig and mapping revision.
        asset_revision: Converted model revision or an unknown marker.

    Returns:
        A versioned record with an exact recipe fingerprint and explicit
        unsupported physical capabilities. No physical model is embedded.

    Raises:
        Error: If the spec or any revision is missing or invalid.
    """
    if canonical_revision == "":
        raise Error("Fidelity provenance needs a canonical revision")
    if visual_revision == "":
        raise Error("Fidelity provenance needs a visual revision")
    if asset_revision == "":
        raise Error("Fidelity provenance needs an asset revision")
    var recipe = UserData()
    recipe.set_number("schema_version", FIDELITY_SCHEMA)
    recipe.set_string("canonical_revision", canonical_revision)
    recipe.set_string("visual_revision", visual_revision)
    recipe.set_string("asset_revision", asset_revision)
    recipe.set_json("canonical_inputs", canonical_inputs(spec).to_json())
    recipe.set_json("visual_settings", visual_settings.to_json())
    recipe.set_string("length_unit", "meter")
    recipe.set_string("handedness", "right")
    recipe.set_string("up_axis", "+y")
    recipe.set_string("right_axis", "+x")
    recipe.set_string("anterior_axis", "+z")
    recipe.set_string("origin", "pelvis-frame-origin")
    recipe.set_string(
        "transform_scope",
        "local-rest; node and animation transforms remain separate",
    )
    var record = UserData()
    record.set_number("schema_version", FIDELITY_SCHEMA)
    record.set_json("recipe", recipe.to_json())
    # This is a lossless recipe key. It is not a cryptographic asset hash.
    record.set_string("recipe_fingerprint", recipe.to_json())
    record.set_boolean("visual_use", True)
    record.set_boolean("engineering_use", False)
    record.set_boolean("canonical_geometry_embedded", False)
    record.set_boolean("physical_properties_embedded", False)
    record.set_boolean("source_manifest_verified", False)
    record.set_string(
        "identity_mapping",
        "visual-only; canonical skull and tissue coupling unsupported",
    )
    record.set_string(
        "expression_jaw_mapping",
        "visual-only; canonical jaw mechanics unsupported",
    )
    record.set_string(
        "dental_mapping",
        "unsupported; authored and scanned dentitions remain separate",
    )
    record.set_string(
        "skin_weight_mapping",
        "animation-only; physical tissue mapping unsupported",
    )
    record.set_string(
        "lod_mapping",
        (
            "visual-only; canonical mass and contact geometry must remain"
            " independent"
        ),
    )
    record.set_string(
        "invalidation",
        (
            "spec, settings, source, topology, rig or transform change requires"
            " a new recipe"
        ),
    )
    return record^


def require_bake_provenance(stored: UserData, expected: UserData) raises:
    """Refuse missing, stale or edited humanoid provenance before reuse.

    This checks a creation recipe, not the current mesh bytes. Callers must
    separately verify content digests when accepting externally edited files.
    It never upgrades an artifact to an engineering model.

    Args:
        stored: Extras loaded from the humanoid root or scene.
        expected: The freshly built expected provenance record.

    Raises:
        Error: If the record is absent or differs in any field.
    """
    if not stored.has(String(FIDELITY_KEY)):
        raise Error("Humanoid bake has no fidelity provenance; rebuild it")
    if stored.json(String(FIDELITY_KEY)) != expected.to_json():
        raise Error("Humanoid bake provenance is stale or changed; rebuild it")
