# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""More armor: a platebody, plate legs, a plate skirt, mail, a shirt of
scales, great pauldrons, leather bracers, and three helmets.

| Garment | Slot | Layer | Fabric | Articulation | Form |
|---|---|---|---|---|---|
| `platebody` | torso | armor | plate | five lames from the chest | fitted |
| `plate_legs` | legs | armor | plate | rigid on each thigh and shin | fitted |
| `plate_skirt` | waist | armor | plate | six lames from the hips | skirted, flare 0.18 |
| `arm_harness` | arms | armor | plate | rigid on each upper arm and forearm | fitted |
| `great_pauldrons` | shoulders | armor | plate | four lames from the chest | domed |
| `chain_shirt` | torso | outer | mail, short sleeves | flexible | skirted, flare 0.1 |
| `scale_shirt` | torso | armor | scale, short sleeves | flexible | skirted, flare 0.12 |
| `mail_chausses` | legs | outer | mail | flexible | fitted |
| `bracers` | arms | outer | leather | flexible | fitted |
| `great_helm` | head | armor | plate | rigid on the head | hatted, a great helm |
| `half_helm` | head | armor | plate | rigid on the head | hatted, a half helm |
| `horned_helm` | head | armor | plate, ivory horns | rigid on the head | hatted, a horned helm |

A platebody is a breastplate and its lames down to the hips: the top
lame rides the chest, and each lame below it bends more with the spine
and the hips. Plate legs ride the thigh above the knee and the shin
below it, so they part at the knee as a cuisse and a greave do. A plate
skirt is a fauld that reaches to the middle of the thigh in six lames,
as tassets do. Great pauldrons close each shoulder in a dome that stands
well off it, as the large pauldrons of a heroic harness do; see
`extensions.attire.dome`.

Each garment is steel; `forged` makes it of another metal. A plate
garment replaces the wardrobe's garment in its slot and layer: plate
legs replace greaves, a platebody a cuirass, and a plate skirt a fauld.

This is not a three.js port. See Extensions.

    var outfit = Outfit()
    outfit.add(forged(platebody(), BLUED, GOLD))
    outfit.add(forged(great_helm(), BLUED, GOLD))
"""

from extensions.attire.cover import Cover
from extensions.attire.garment import Garment
from extensions.attire.kinds import (
    ACCENT_DYE,
    ARMOR_LAYER,
    ARMS_SLOT,
    DOMED,
    GREAT_HELM,
    HALF_HELM,
    HATTED,
    HEAD_SLOT,
    HORNED_HELM,
    LAMED,
    LEATHER,
    LEGS_SLOT,
    MAIL,
    OUTER_LAYER,
    PLATE,
    RIGID,
    SCALE,
    SHOULDERS_SLOT,
    SKIRTED,
    TORSO_SLOT,
    TRIM_DYE,
    WAIST_SLOT,
    Headwear,
)
from extensions.humanoid.rig.joints import (
    CHEST,
    HEAD,
    HIPS,
    LEFT_FOOT,
    LEFT_FOREARM,
    LEFT_SHIN,
    LEFT_THIGH,
    LEFT_TOES,
    LEFT_UPPER_ARM,
    NECK,
    RIGHT_FOOT,
    RIGHT_FOREARM,
    RIGHT_SHIN,
    RIGHT_THIGH,
    RIGHT_TOES,
    RIGHT_UPPER_ARM,
    SPINE,
    Joint,
)
from render.framebuffer import Color

comptime STEEL_DYE = Color(198, 200, 206)
"""The dye of bright steel."""
comptime MAIL_DYE = Color(120, 122, 128)
"""The dye of mail."""
comptime IVORY = Color(226, 214, 186)
"""The color of a horned helm's horns."""


def _both(
    mut cover: Cover, right: Joint, left: Joint, end: Float32, start: Float32
) raises:
    """Cover the same span of a joint on each side."""
    cover.reach_to(right, end, start)
    cover.reach_to(left, end, start)


def platebody() raises -> Garment:
    """Return a breastplate and backplate with lames down to the hips.

    Returns:
        The garment.

    Raises:
        Error: If its cover is refused, which an armory garment's is not.
    """
    var cover = Cover()
    cover.reach_to(HIPS, 1, 0.3)
    cover.reach_to(SPINE)
    cover.reach_to(CHEST)
    cover.reach_to(NECK, 0.12)
    _both(cover, RIGHT_UPPER_ARM, LEFT_UPPER_ARM, 0.12, 0)
    return Garment(
        "platebody",
        TORSO_SLOT,
        ARMOR_LAYER,
        PLATE,
        cover^,
        STEEL_DYE,
        articulation=LAMED,
        anchor=CHEST,
        lames=5,
    )


def plate_legs() raises -> Garment:
    """Return plate over each thigh and shin, parted at the knee.

    Returns:
        The garment.

    Raises:
        Error: If its cover is refused, which an armory garment's is not.
    """
    var cover = Cover()
    _both(cover, RIGHT_THIGH, LEFT_THIGH, 1, 0.12)
    _both(cover, RIGHT_SHIN, LEFT_SHIN, 0.92, 0)
    return Garment(
        "plate legs",
        LEGS_SLOT,
        ARMOR_LAYER,
        PLATE,
        cover^,
        STEEL_DYE,
        articulation=RIGID,
    )


def plate_skirt() raises -> Garment:
    """Return a skirt of six lames from the hips to the middle of the
    thigh.

    Returns:
        The garment.

    Raises:
        Error: If its cover is refused, which an armory garment's is not.
    """
    var cover = Cover()
    cover.reach_to(HIPS, 0.4)
    _both(cover, RIGHT_THIGH, LEFT_THIGH, 0.6, 0)
    return Garment(
        "plate skirt",
        WAIST_SLOT,
        ARMOR_LAYER,
        PLATE,
        cover^,
        STEEL_DYE,
        articulation=LAMED,
        anchor=HIPS,
        lames=6,
        form=SKIRTED,
        flare=0.18,
    )


def arm_harness() raises -> Garment:
    """Return plate over each upper arm and forearm, parted at the elbow.

    Returns:
        The garment.

    Raises:
        Error: If its cover is refused, which an armory garment's is not.
    """
    var cover = Cover()
    _both(cover, RIGHT_UPPER_ARM, LEFT_UPPER_ARM, 1, 0.3)
    _both(cover, RIGHT_FOREARM, LEFT_FOREARM, 0.88, 0)
    return Garment(
        "arm harness",
        ARMS_SLOT,
        ARMOR_LAYER,
        PLATE,
        cover^,
        STEEL_DYE,
        articulation=RIGID,
    )


def great_pauldrons() raises -> Garment:
    """Return large pauldrons of four lames, standing off the shoulders.

    Returns:
        The garment.

    Raises:
        Error: If its cover is refused, which an armory garment's is not.
    """
    var cover = Cover()
    _both(cover, RIGHT_UPPER_ARM, LEFT_UPPER_ARM, 0.6, 0)
    cover.reach_to(CHEST, 1, 0.9)
    return Garment(
        "great pauldrons",
        SHOULDERS_SLOT,
        ARMOR_LAYER,
        PLATE,
        cover^,
        STEEL_DYE,
        articulation=LAMED,
        anchor=CHEST,
        lames=4,
        form=DOMED,
    )


def chain_shirt() raises -> Garment:
    """Return a shirt of mail with short sleeves, to the hips.

    Returns:
        The garment.

    Raises:
        Error: If its cover is refused, which an armory garment's is not.
    """
    var cover = Cover()
    cover.reach_to(HIPS)
    cover.reach_to(SPINE)
    cover.reach_to(CHEST)
    cover.reach_to(NECK, 0.2)
    _both(cover, RIGHT_UPPER_ARM, LEFT_UPPER_ARM, 0.55, 0)
    _both(cover, RIGHT_THIGH, LEFT_THIGH, 0.18, 0)
    return Garment(
        "chain shirt",
        TORSO_SLOT,
        OUTER_LAYER,
        MAIL,
        cover^,
        MAIL_DYE,
        form=SKIRTED,
        flare=0.1,
    )


def scale_shirt() raises -> Garment:
    """Return a shirt of scales with short sleeves, to the middle of the
    thigh.

    It is armor: it takes the platebody's slot and layer, over a
    gambeson.

    Returns:
        The garment.

    Raises:
        Error: If its cover is refused, which an armory garment's is not.
    """
    var cover = Cover()
    cover.reach_to(HIPS)
    cover.reach_to(SPINE)
    cover.reach_to(CHEST)
    cover.reach_to(NECK, 0.15)
    _both(cover, RIGHT_UPPER_ARM, LEFT_UPPER_ARM, 0.45, 0)
    _both(cover, RIGHT_THIGH, LEFT_THIGH, 0.4, 0)
    return Garment(
        "scale shirt",
        TORSO_SLOT,
        ARMOR_LAYER,
        SCALE,
        cover^,
        STEEL_DYE,
        form=SKIRTED,
        flare=0.12,
    )


def mail_chausses() raises -> Garment:
    """Return mail over the legs and the feet.

    Returns:
        The garment.

    Raises:
        Error: If its cover is refused, which an armory garment's is not.
    """
    var cover = Cover()
    cover.reach_to(HIPS, 0.5)
    for joint in [  # pragma: no branch
        RIGHT_THIGH,
        RIGHT_SHIN,
        RIGHT_FOOT,
        RIGHT_TOES,
        LEFT_THIGH,
        LEFT_SHIN,
        LEFT_FOOT,
        LEFT_TOES,
    ]:
        cover.reach_to(joint)
    return Garment(
        "mail chausses", LEGS_SLOT, OUTER_LAYER, MAIL, cover^, MAIL_DYE
    )


def bracers() raises -> Garment:
    """Return a leather bracer on each forearm.

    Returns:
        The garment.

    Raises:
        Error: If its cover is refused, which an armory garment's is not.
    """
    var cover = Cover()
    _both(cover, RIGHT_FOREARM, LEFT_FOREARM, 0.85, 0.3)
    return Garment(
        "bracers",
        ARMS_SLOT,
        OUTER_LAYER,
        LEATHER,
        cover^,
        Color(92, 60, 36),
        drape=8,
    )


def _helm(name: String, headwear: Headwear) raises -> Garment:
    """Return a plate helmet over the head, rigid on it."""
    var cover = Cover()
    cover.reach_to(HEAD)
    return Garment(
        name,
        HEAD_SLOT,
        ARMOR_LAYER,
        PLATE,
        cover^,
        STEEL_DYE,
        articulation=RIGID,
        anchor=HEAD,
        form=HATTED,
        headwear=headwear,
    )


def great_helm() raises -> Garment:
    """Return a great helm, closed over the head, with brass trim.

    Returns:
        The garment.

    Raises:
        Error: If its cover is refused, which an armory garment's is not.
    """
    var helm = _helm("great helm", GREAT_HELM)
    helm.dyes[TRIM_DYE.value] = Color(176, 132, 62)
    return helm^


def half_helm() raises -> Garment:
    """Return a half helm over the crown, with a bar down the nose.

    Returns:
        The garment.

    Raises:
        Error: If its cover is refused, which an armory garment's is not.
    """
    return _helm("half helm", HALF_HELM)


def horned_helm() raises -> Garment:
    """Return a half helm with a horn of ivory on each side.

    Returns:
        The garment.

    Raises:
        Error: If its cover is refused, which an armory garment's is not.
    """
    var helm = _helm("horned helm", HORNED_HELM)
    helm.dyes[ACCENT_DYE.value] = IVORY
    return helm^


def armory() raises -> List[Garment]:
    """Return every garment of this module.

    Returns:
        The garments, in the order of the module's table.

    Raises:
        Error: If a garment's cover is refused, which none is.
    """
    return [
        platebody(),
        plate_legs(),
        plate_skirt(),
        arm_harness(),
        great_pauldrons(),
        chain_shirt(),
        scale_shirt(),
        mail_chausses(),
        bracers(),
        great_helm(),
        half_helm(),
        horned_helm(),
    ]
