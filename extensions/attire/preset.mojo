# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Outfits saved as text, and dressed bakes that remember their outfit.

A player saves a look, as a glamour plate or a wardrobe slot does in a
game, and puts it on again later, on the same body or on another one.
`outfit_json` writes an outfit as one JSON object, and `outfit_from_json`
reads it back. A garment's slot, layer, fabric, articulation and pattern
are written by name, its anchor by joint name, its dyes as sRGB bytes
and its cover as two lists of nineteen fractions, one per joint. Its form
is written by name and its flare as a number; a garment saved without
them is read as fitted, with no flare. Its metal and its headwear are
written by name; a garment saved without them is read as steel, with no
headwear. Its neckline, opening and sleeve are written by name; a
garment saved without them is read round-necked, closed and fitted. Its
design is written by name; a garment saved without one is read plain.
Its ruffles are written by name; a garment saved without them has none.

`outfit_named` gives three outfits ready to wear: a peasant's, a
man-at-arms's in mail, and a knight's full harness under a surcoat.

A dressed bake keeps the outfit beside its sealed provenance, in the
scene extras under `OUTFIT_KEY`, with the fingerprint of the spec it was
fitted to. `stored_outfit` gives the outfit back, and refuses it for
another body: a garment fitted to one body is made again for another.

This is not a three.js port. See Extensions.

    var text = outfit_json(outfit)
    var again = outfit_from_json(text)
    write_dressed_bake("out/knight.glb", scene, assets, record, outfit, spec)
"""

from animation.animation_clip import AnimationClip
from core.assets import Assets
from core.scene import Scene
from core.user_data import UserData, json_number_text, json_value_text
from exporters.gltf import GLB, GltfContainer, GltfExportOptions
from extensions.attire.cover import Cover
from extensions.attire.garment import (
    NO_ANCHOR,
    Garment,
    boots,
    coif,
    cuirass,
    fauld,
    gambeson,
    gauntlets,
    gloves,
    gorget,
    greaves,
    hauberk,
    hood,
    hose,
    pauldrons,
    sabatons,
    shirt,
    surcoat,
    tunic,
    vambraces,
)
from extensions.attire.kinds import (
    DYE_CHANNEL_COUNT,
    articulation_label,
    articulation_named,
    fabric_label,
    fabric_named,
    form_label,
    form_named,
    headwear_label,
    headwear_named,
    neckline_label,
    neckline_named,
    opening_label,
    opening_named,
    sleeve_label,
    sleeve_named,
    design_label,
    design_named,
    ruffles_label,
    ruffles_named,
    layer_label,
    layer_named,
    pattern_label,
    pattern_named,
    slot_label,
    slot_named,
)
from extensions.attire.metal import metal_label, metal_named
from extensions.attire.outfit import Outfit
from extensions.humanoid.bake import write_sealed_bake
from extensions.humanoid.fidelity import spec_fingerprint
from extensions.humanoid.rig.joints import (
    JOINT_COUNT,
    Joint,
    joint_label,
    named_joints,
)
from extensions.humanoid.spec import HumanoidSpec
from loaders.json import ARRAY, JsonDocument, parse_json
from render.framebuffer import Color
from units.si import Length, METER

comptime OUTFIT_VERSION = 1
"""The version of the outfit text this module writes and reads."""
comptime OUTFIT_KEY = "threemojo_outfit"
"""The scene extra a dressed bake keeps its outfit in."""


def outfit_named(name: String) raises -> Outfit:
    """Return a named outfit.

    | Name | Garments |
    |---|---|
    | `peasant` | shirt, hose, tunic, hood, boots |
    | `man-at-arms` | shirt, hose, gambeson, hauberk, coif, boots, gloves |
    | `knight` | the man-at-arms's, then cuirass, fauld, pauldrons, vambraces, greaves, surcoat, gorget, gauntlets and sabatons |

    Args:
        name: `peasant`, `man-at-arms` or `knight`.

    Returns:
        The outfit.

    Raises:
        Error: If `name` names no outfit.
    """
    var outfit = Outfit()
    if name == "peasant":
        for garment in [  # pragma: no branch
            shirt(),
            hose(),
            tunic(),
            hood(),
            boots(),
        ]:
            outfit.add(garment.copy())
        return outfit^
    if name != "man-at-arms" and name != "knight":
        raise Error("No outfit is named " + name)
    for garment in [  # pragma: no branch
        shirt(),
        hose(),
        gambeson(),
        hauberk(),
        coif(),
        boots(),
        gloves(),
    ]:
        outfit.add(garment.copy())
    if name == "knight":
        for garment in [  # pragma: no branch
            cuirass(),
            fauld(),
            pauldrons(),
            vambraces(),
            greaves(),
            surcoat(),
            gorget(),
            gauntlets(),
            sabatons(),
        ]:
            outfit.add(garment.copy())
    return outfit^


def joint_named(name: String) raises -> Joint:
    """Return the joint that `name` names, as `joint_label` writes it.

    Args:
        name: A joint's name, as `"rightShin"`.

    Returns:
        The joint.

    Raises:
        Error: If `name` names no joint.
    """
    for joint in named_joints():  # pragma: no branch
        if joint_label(joint) == name:
            return joint
    raise Error("No joint is named " + name)


def _numbers(values: List[Float32]) raises -> String:
    """Return a JSON array of numbers."""
    var text = String("[")
    for k in range(len(values)):  # pragma: no branch
        if k > 0:
            text += ","
        text += json_number_text(Float64(values[k]))
    return text + "]"


def garment_record(garment: Garment) raises -> UserData:
    """Return one garment as a JSON object.

    Args:
        garment: A garment that checks.

    Returns:
        Its record.

    Raises:
        Error: If the garment does not check.
    """
    garment.check()
    var record = UserData()
    record.set_string("name", garment.name)
    record.set_string("slot", slot_label(garment.slot))
    record.set_string("layer", layer_label(garment.layer))
    record.set_string("fabric", fabric_label(garment.fabric))
    record.set_string("articulation", articulation_label(garment.articulation))
    if garment.anchor == NO_ANCHOR:
        record.set_null("anchor")
    else:
        record.set_string("anchor", joint_label(garment.anchor))
    record.set_number("lames", Float64(garment.lames))
    record.set_string("pattern", pattern_label(garment.pattern))
    var dyes = String("[")
    for k in range(DYE_CHANNEL_COUNT):  # pragma: no branch
        var dye = garment.dyes[k]
        if k > 0:
            dyes += ","
        dyes += (
            "["
            + String(Int(dye.r))
            + ","
            + String(Int(dye.g))
            + ","
            + String(Int(dye.b))
            + "]"
        )
    record.set_json("dyes", dyes + "]")
    record.set_number("drape", Float64(garment.drape))
    record.set_meters("ease_m", garment.ease)
    record.set_boolean("face_open", garment.cover.face_open)
    record.set_string("form", form_label(garment.form))
    record.set_number("flare", Float64(garment.flare))
    record.set_string("metal", metal_label(garment.metal))
    record.set_string("headwear", headwear_label(garment.headwear))
    record.set_string("neckline", neckline_label(garment.neckline))
    record.set_string("opening", opening_label(garment.opening))
    record.set_string("sleeve", sleeve_label(garment.sleeve))
    record.set_string("design", design_label(garment.design))
    record.set_string("ruffles", ruffles_label(garment.ruffles))
    record.set_json("starts", _numbers(garment.cover.starts))
    record.set_json("ends", _numbers(garment.cover.ends))
    return record^


def outfit_json(outfit: Outfit) raises -> String:
    """Return an outfit as JSON text.

    Args:
        outfit: An outfit that checks.

    Returns:
        One JSON object: a version and a list of garments.

    Raises:
        Error: If the outfit does not check.
    """
    outfit.check()
    var garments = String("[")
    for k in range(len(outfit.garments)):
        if k > 0:
            garments += ","
        garments += garment_record(outfit.garments[k]).to_json()
    var record = UserData()
    record.set_number("version", Float64(OUTFIT_VERSION))
    record.set_json("garments", garments + "]")
    return record.to_json()


def _fractions(
    document: JsonDocument, node: Int, key: String
) raises -> List[Float32]:
    """Read a list of one fraction per joint."""
    var list = document.required_kind(
        node, key, ARRAY, "An outfit garment needs a list of " + key
    )
    if document.length(list) != JOINT_COUNT:
        raise Error("A garment's " + key + " must hold one value per joint")
    var values = List[Float32]()
    for k in range(JOINT_COUNT):  # pragma: no branch
        values.append(Float32(document.number(document.at(list, k))))
    return values^


def _field(document: JsonDocument, node: Int, key: String) raises -> Int:
    """Return a garment's field, which must be there."""
    return document.required(node, key, "An outfit garment needs " + key)


def _byte(document: JsonDocument, node: Int) raises -> UInt8:
    """Read one sRGB byte."""
    var value = document.integer(node)
    if value < 0 or value > 255:
        raise Error("A dye's channels must be 0 through 255")
    return UInt8(value)


def garment_from(document: JsonDocument, node: Int) raises -> Garment:
    """Read one garment from its JSON object.

    Args:
        document: The parsed outfit.
        node: The garment's object.

    Returns:
        The garment.

    Raises:
        Error: If a field is missing, of the wrong kind or out of range,
            or the garment does not check.
    """
    var starts = _fractions(document, node, "starts")
    var ends = _fractions(document, node, "ends")
    var cover = Cover()
    for k in range(JOINT_COUNT):  # pragma: no branch
        cover.reach_to(Joint(k), ends[k], starts[k])
    cover.face_open = document.boolean(_field(document, node, "face_open"))
    var dyes = document.required_kind(
        node, "dyes", ARRAY, "An outfit garment needs a list of dyes"
    )
    if document.length(dyes) != DYE_CHANNEL_COUNT:
        raise Error("A garment must hold four dyes")
    var colors = List[Color]()
    for k in range(DYE_CHANNEL_COUNT):  # pragma: no branch
        var dye = document.at(dyes, k)
        if document.length(dye) != 3:
            raise Error("A dye must hold three channels")
        colors.append(
            Color(
                _byte(document, document.at(dye, 0)),
                _byte(document, document.at(dye, 1)),
                _byte(document, document.at(dye, 2)),
            )
        )
    var anchor = NO_ANCHOR
    var anchored = _field(document, node, "anchor")
    if not document.is_null(anchored):
        anchor = joint_named(document.string(anchored))
    var garment = Garment(
        document.string(_field(document, node, "name")),
        slot_named(document.string(_field(document, node, "slot"))),
        layer_named(document.string(_field(document, node, "layer"))),
        fabric_named(document.string(_field(document, node, "fabric"))),
        cover^,
        colors[0],
        articulation=articulation_named(
            document.string(_field(document, node, "articulation"))
        ),
        anchor=anchor,
        lames=document.integer(_field(document, node, "lames")),
        pattern=pattern_named(
            document.string(_field(document, node, "pattern"))
        ),
        drape=document.integer(_field(document, node, "drape")),
        ease=Length(
            Float32(document.number(_field(document, node, "ease_m"))),
            METER,
        ),
        # An outfit saved before garments had forms is fitted, and one
        # saved before metals and headwear is steel and bareheaded.
        form=form_named(document.optional_string(node, "form", "fitted")),
        flare=Float32(document.optional_number(node, "flare", 0)),
        metal=metal_named(document.optional_string(node, "metal", "steel")),
        headwear=headwear_named(
            document.optional_string(node, "headwear", "none")
        ),
        # One saved before necklines, openings and sleeves is round-necked,
        # closed and fitted.
        neckline=neckline_named(
            document.optional_string(node, "neckline", "round")
        ),
        opening=opening_named(
            document.optional_string(node, "opening", "closed")
        ),
        sleeve=sleeve_named(document.optional_string(node, "sleeve", "fitted")),
        # One saved before designs is plain.
        design=design_named(document.optional_string(node, "design", "plain")),
        ruffles=ruffles_named(
            document.optional_string(node, "ruffles", "none")
        ),
    )
    garment.dyes = colors^
    garment.check()
    return garment^


def outfit_from_json(text: String) raises -> Outfit:
    """Read an outfit from JSON text.

    Args:
        text: An outfit, as `outfit_json` writes it.

    Returns:
        The outfit.

    Raises:
        Error: If the text is not an outfit of this version, or a garment
            is refused.
    """
    var document = parse_json(text)
    var root = document.root()
    var version = document.integer(
        document.required(root, "version", "An outfit needs a version")
    )
    if version != OUTFIT_VERSION:
        raise Error("This outfit is of version " + String(version))
    var garments = document.required_kind(
        root, "garments", ARRAY, "An outfit needs a list of garments"
    )
    var outfit = Outfit()
    for k in range(document.length(garments)):
        outfit.add(garment_from(document, document.at(garments, k)))
    return outfit^


def outfit_record(outfit: Outfit, spec: HumanoidSpec) raises -> UserData:
    """Return the record a dressed bake keeps: the outfit and the body it
    was fitted to.

    Args:
        outfit: An outfit that checks.
        spec: The body it was fitted to.

    Returns:
        A record with `spec_fingerprint` and `outfit`.

    Raises:
        Error: If the outfit does not check or the spec is refused.
    """
    var record = UserData()
    record.set_string("spec_fingerprint", spec_fingerprint(spec))
    record.set_json("outfit", outfit_json(outfit))
    return record^


def write_dressed_bake(
    path: String,
    scene: Scene,
    assets: Assets,
    record: UserData,
    outfit: Outfit,
    spec: HumanoidSpec,
    container: GltfContainer = GLB,
    animations: List[AnimationClip] = List[AnimationClip](),
    options: GltfExportOptions = GltfExportOptions(),
) raises:
    """Write a sealed bake of a dressed humanoid, with its outfit.

    The geometry digest covers every garment, so dress before you bake.

    Args:
        path: The `.glb` or `.gltf` file.
        scene: The scene, with the person dressed.
        assets: Its geometries, materials and textures.
        record: The unsealed provenance, as `humanoid_provenance` gives.
        outfit: The outfit the person wears.
        spec: The person's spec.
        container: `GLB`, `GLTF_EMBEDDED` or `GLTF_SEPARATE`.
        animations: The clips to write.
        options: The other export options. The outfit record replaces
            any scene extra under `OUTFIT_KEY`.

    Raises:
        Error: If the outfit does not check, or the bake is refused.
    """
    var written = options.copy()
    written.scene_user_data.set_json(
        String(OUTFIT_KEY), outfit_record(outfit, spec).to_json()
    )
    write_sealed_bake(
        path,
        scene,
        assets,
        record,
        container,
        animations=animations,
        options=written,
    )


def stored_outfit(stored: UserData, spec: HumanoidSpec) raises -> Outfit:
    """Return the outfit a dressed bake keeps, if it was fitted to `spec`.

    Args:
        stored: The loaded scene extras.
        spec: The body that is to wear it.

    Returns:
        The outfit.

    Raises:
        Error: If the extras hold no outfit, or it was fitted to another
            body, or it is malformed.
    """
    if not stored.has(String(OUTFIT_KEY)):
        raise Error("This bake keeps no outfit")
    var document = parse_json(stored.json(String(OUTFIT_KEY)))
    var root = document.root()
    var fitted = document.string(
        document.required(
            root, "spec_fingerprint", "An outfit record needs a fingerprint"
        )
    )
    if fitted != spec_fingerprint(spec):
        raise Error("This outfit was fitted to another body; dress again")
    var outfit = document.required(
        root, "outfit", "An outfit record needs an outfit"
    )
    return outfit_from_json(json_value_text(document, outfit))
