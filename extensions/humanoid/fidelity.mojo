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

from core.user_data import UserData, user_data_of
from extensions.humanoid.athleticism import Athleticism
from extensions.humanoid.genome import GENE_COUNT, Genome
from extensions.humanoid.sex import Sex
from extensions.humanoid.spec import MAX_STATURE, MIN_STATURE, HumanoidSpec
from loaders.json import parse_json
from std.math import isfinite
from std.memory import bitcast
from units.si import Length, METER

comptime FIDELITY_KEY = "threemojo_humanoid_fidelity"
# Version 2 adds the transform matrix and the content fingerprints.
comptime FIDELITY_SCHEMA = 2
comptime FINGERPRINT_ALGORITHM = (
    "fnv1a-64 over normalized UTF-8 JSON; not cryptographic"
)
# The canonical frame is the local rest frame: a column-major 4x4 identity.
comptime CANONICAL_TO_LOCAL_REST = "[1,0,0,0,0,1,0,0,0,0,1,0,0,0,0,1]"
comptime _FNV_OFFSET = UInt64(0xCBF29CE484222325)
comptime _FNV_PRIME = UInt64(0x100000001B3)
comptime _HEX: List[String] = [
    "0",
    "1",
    "2",
    "3",
    "4",
    "5",
    "6",
    "7",
    "8",
    "9",
    "a",
    "b",
    "c",
    "d",
    "e",
    "f",
]
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


def json_fingerprint(text: String) -> String:
    """Return the 64-bit FNV-1a fingerprint of JSON text.

    The fingerprint detects a changed recipe. It is not a cryptographic
    hash and does not prove the source of an asset.

    Args:
        text: Normalized JSON text, as `UserData` writes it.

    Returns:
        Sixteen lowercase hexadecimal digits.
    """
    var hash = _FNV_OFFSET
    for byte in text.as_bytes():  # pragma: no branch
        hash = (hash ^ UInt64(byte)) * _FNV_PRIME
    var hex = materialize[_HEX]()
    var digits = String()
    for at in range(16):  # pragma: no branch
        var nibble = Int((hash >> UInt64(60 - 4 * at)) & 0xF)
        digits += hex[nibble]
    return digits^


def _normalized(text: String) raises -> String:
    """Return JSON text in the one form that `UserData` writes.

    Args:
        text: One JSON value.

    Returns:
        The same value as normalized text.

    Raises:
        Error: If the text is not one JSON value.
    """
    var data = UserData()
    data.set_json("value", text)
    return data.json("value")


def spec_fingerprint(spec: HumanoidSpec) raises -> String:
    """Return the fingerprint of a spec's complete canonical inputs.

    Args:
        spec: The canonical input recipe.

    Returns:
        The fingerprint of `canonical_inputs(spec)`.

    Raises:
        Error: If the spec is outside its software input domain.
    """
    return json_fingerprint(_normalized(canonical_inputs(spec).to_json()))


def settings_fingerprint(visual_settings: UserData) raises -> String:
    """Return the fingerprint of every visual quality and build option.

    Args:
        visual_settings: The triangle budget, details, style and materials.

    Returns:
        The fingerprint of the settings' normalized JSON.

    Raises:
        Error: If the settings do not form a JSON object.
    """
    return json_fingerprint(_normalized(visual_settings.to_json()))


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
    The canonical-to-local-rest transform is an explicit identity matrix.
    Parent and animation transforms remain in glTF nodes and channels.
    The record holds fingerprints of the spec, the visual settings and
    the complete recipe.

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
    recipe.set_json("canonical_to_local_rest", String(CANONICAL_TO_LOCAL_REST))
    recipe.set_string(
        "matrix_layout", "column-major 4x4; translation in meters"
    )
    var record = UserData()
    record.set_number("schema_version", FIDELITY_SCHEMA)
    record.set_json("recipe", recipe.to_json())
    # This is a lossless recipe key. It is not a cryptographic asset hash.
    record.set_string("recipe_fingerprint", recipe.to_json())
    record.set_string("fingerprint_algorithm", String(FINGERPRINT_ALGORITHM))
    record.set_string(
        "spec_fingerprint", json_fingerprint(recipe.json("canonical_inputs"))
    )
    record.set_string(
        "visual_settings_fingerprint",
        json_fingerprint(recipe.json("visual_settings")),
    )
    record.set_string("recipe_digest", json_fingerprint(record.json("recipe")))
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


def _template_input(inputs: UserData, key: String) raises -> Int:
    """Read one named binary template without truncating or overflowing."""
    var value = inputs.json(key)
    if value == "0":
        return 0
    if value == "1":
        return 1
    raise Error(
        "Humanoid bake canonical inputs are stale or changed; rebuild it"
    )


def _spec_from_canonical(inputs: UserData) raises -> HumanoidSpec:
    """Read exact input bits and refuse any inconsistent canonical field."""
    var gene_document = parse_json(inputs.json("gene_float32_bits"))
    var genes = user_data_of(gene_document, gene_document.root())
    var genome = Genome()
    for at in range(GENE_COUNT):  # pragma: no branch
        genome.expressions[at] = bitcast[DType.float32](
            UInt32(Int(genes.string(String(at))))
        )
    var spec = HumanoidSpec(
        Length(
            bitcast[DType.float32](
                UInt32(Int(inputs.string("stature_float32_bits")))
            ),
            METER,
        ),
        Sex(_template_input(inputs, "sex")),
        Athleticism(_template_input(inputs, "athleticism")),
        genome,
    )
    if inputs.to_json() != _normalized(canonical_inputs(spec).to_json()):
        raise Error(
            "Humanoid bake canonical inputs are stale or changed; rebuild it"
        )
    return spec


def stored_provenance(stored: UserData) raises -> UserData:
    """Return a bake's provenance record after checking its fingerprints.

    The check recomputes each fingerprint and the complete schema record.
    It refuses missing fields, edited capability claims and inconsistent
    recipes. It does not authenticate a recipe rewritten with its hashes.

    Args:
        stored: Extras loaded from the humanoid root or scene.

    Returns:
        The stored provenance record.

    Raises:
        Error: If the record is absent, malformed, of another schema,
            incomplete or inconsistent with its own fingerprints.
    """
    if not stored.has(String(FIDELITY_KEY)):
        raise Error("Humanoid bake has no fidelity provenance; rebuild it")
    var document = parse_json(stored.json(String(FIDELITY_KEY)))
    var record = user_data_of(document, document.root())
    if not record.has("schema_version"):
        raise Error("Humanoid bake provenance has no schema; rebuild it")
    if record.json("schema_version") != String(FIDELITY_SCHEMA):
        raise Error(
            "Humanoid bake provenance schema is unsupported; rebuild it"
        )
    for key in [  # pragma: no branch
        "recipe",
        "spec_fingerprint",
        "visual_settings_fingerprint",
        "recipe_digest",
    ]:
        if not record.has(key):
            raise Error("Humanoid bake provenance is incomplete; rebuild it")
    var recipe_document = parse_json(record.json("recipe"))
    var recipe = user_data_of(recipe_document, recipe_document.root())
    for key in [  # pragma: no branch
        "schema_version",
        "canonical_revision",
        "visual_revision",
        "asset_revision",
        "canonical_inputs",
        "visual_settings",
        "length_unit",
        "handedness",
        "up_axis",
        "right_axis",
        "anterior_axis",
        "origin",
        "transform_scope",
        "canonical_to_local_rest",
        "matrix_layout",
    ]:
        if not recipe.has(key):
            raise Error("Humanoid bake recipe is incomplete; rebuild it")
    var consistent = json_fingerprint(record.json("recipe")) == record.string(
        "recipe_digest"
    )
    consistent = consistent and json_fingerprint(
        recipe.json("canonical_inputs")
    ) == record.string("spec_fingerprint")
    consistent = consistent and json_fingerprint(
        recipe.json("visual_settings")
    ) == record.string("visual_settings_fingerprint")
    if not consistent:
        raise Error(
            "Humanoid bake fingerprints do not match its recipe; rebuild it"
        )
    var input_document = parse_json(recipe.json("canonical_inputs"))
    var inputs = user_data_of(input_document, input_document.root())
    var settings_document = parse_json(recipe.json("visual_settings"))
    var settings = user_data_of(settings_document, settings_document.root())
    var expected = humanoid_provenance(
        _spec_from_canonical(inputs),
        settings,
        recipe.string("canonical_revision"),
        recipe.string("visual_revision"),
        recipe.string("asset_revision"),
    )
    if record.to_json() != expected.to_json():
        raise Error("Humanoid bake provenance is stale or changed; rebuild it")
    return record^


def require_current_spec(stored: UserData, spec: HumanoidSpec) raises:
    """Refuse a bake that does not represent the current spec.

    The check compares the exact canonical inputs, not only fingerprints.
    It ignores visual settings and revisions.

    Args:
        stored: Extras loaded from the humanoid root or scene.
        spec: The spec that the caller expects the bake to represent.

    Raises:
        Error: If the record is refused by `stored_provenance`, or if the
            bake represents a different spec.
    """
    var record = stored_provenance(stored)
    var recipe_document = parse_json(record.json("recipe"))
    var recipe = user_data_of(recipe_document, recipe_document.root())
    var current = _normalized(canonical_inputs(spec).to_json())
    if recipe.json("canonical_inputs") != current:
        raise Error("Humanoid bake represents a different spec; rebuild it")


def require_bake_provenance(stored: UserData, expected: UserData) raises:
    """Refuse missing, stale or edited humanoid provenance before reuse.

    This checks a creation recipe, not the current mesh bytes. Callers must
    separately verify content digests when accepting externally edited files.
    It never upgrades an artifact to an engineering model.

    Args:
        stored: Extras loaded from the humanoid root or scene.
        expected: The freshly built expected provenance record.

    Raises:
        Error: If the record is refused by `stored_provenance`, if the spec
            or visual settings changed, or if any other field differs.
    """
    var record = stored_provenance(stored)
    if record.string("spec_fingerprint") != expected.string("spec_fingerprint"):
        raise Error("Humanoid bake spec fingerprint is stale; rebuild it")
    if record.string("visual_settings_fingerprint") != expected.string(
        "visual_settings_fingerprint"
    ):
        raise Error("Humanoid bake visual settings are stale; rebuild it")
    if stored.json(String(FIDELITY_KEY)) != expected.to_json():
        raise Error("Humanoid bake provenance is stale or changed; rebuild it")
