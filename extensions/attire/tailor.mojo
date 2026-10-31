# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Tops and bottoms cut and shaped as a tailor would: shirts with full
sleeves, skirts and aprons, doublets, waistcoats, coats and gowns.

| Garment | Slot | Layer | Fabric | Shape |
|---|---|---|---|---|
| `chemise` | torso | under | linen | scoop neck, bishop sleeves, to mid-thigh |
| `laced_shirt` | torso | under | linen | slit neck, bishop sleeves, to the hip |
| `skirt` | legs | mid | wool | skirted from the waist to the ankle, flare 0.28 |
| `apron` | waist | outer | linen | skirted, the front alone, to mid-calf |
| `laced_bodice` | torso | outer | wool | a square neck, from the waist to under the arms, no sleeves |
| `doublet` | torso | mid | wool | a high collar, puffed shoulders, to the hip |
| `waistcoat` | torso | mid | silk | a V neck, no sleeves, to below the waist |
| `frock_coat` | torso | outer | wool | a collar, to below the knee, open below the waist, flare 0.22 |
| `long_coat` | torso | outer | velvet | a collar, to below the knee, open down the front, flare 0.25 |
| `open_robe` | torso | over | velvet | open down the front, to the ankle, flare 0.3 |
| `ball_gown` | torso | mid | silk | square neck, puffed shoulders, sleeves to the elbow, to the floor, flare 0.6, a front panel |

The cuts and the sleeves are `Neckline`, `Opening` and `Sleeve`; see
`extensions.attire.opening`. A neckline or an opening shows the garment
under it: a waistcoat's V shows the shirt, and a frock coat's parted
skirts show the breeches. Each cut takes the trim dye along its edge.

Women wear a chemise under a laced bodice, a skirt and an apron, as a
farmwife or a goodwife does. Men wear a laced shirt over trousers or
breeches. A merchant or a courtier wears a doublet, or a waistcoat
under a frock coat. A royal wears an open robe; a lady a ball gown.

This is not a three.js port. See Extensions.

    var outfit = Outfit()
    outfit.add(chemise())
    outfit.add(skirt())
    outfit.add(apron())
"""

from extensions.attire.cover import Cover
from extensions.attire.garment import Garment
from extensions.attire.kinds import (
    BISHOP_SLEEVE,
    COLLAR_RUFFLE,
    CUFF_RUFFLES,
    FRONT_ONLY,
    FRONT_PANEL,
    LEGS_SLOT,
    LINEN,
    MID_LAYER,
    OPEN_BELOW,
    OPEN_FRONT,
    OUTER_LAYER,
    OVER_LAYER,
    PUFFED_SHOULDER,
    SCOOP_NECK,
    SECONDARY_DYE,
    SILK,
    SKIRTED,
    SLIT_NECK,
    SQUARE_NECK,
    TORSO_SLOT,
    TRIM_DYE,
    UNDER_LAYER,
    V_NECK,
    VELVET,
    WAIST_SLOT,
    WOOL,
)
from extensions.humanoid.rig.joints import (
    CHEST,
    HIPS,
    LEFT_FOREARM,
    LEFT_SHIN,
    LEFT_THIGH,
    LEFT_UPPER_ARM,
    NECK,
    RIGHT_FOREARM,
    RIGHT_SHIN,
    RIGHT_THIGH,
    RIGHT_UPPER_ARM,
    SPINE,
    Joint,
)
from render.framebuffer import Color
from units.si import MILLIMETER, Length

comptime UNBLEACHED = Color(226, 214, 190)
"""The color of undyed linen."""
comptime BLEACHED = Color(238, 234, 226)
"""The color of bleached linen."""
comptime GOLD_LACE = Color(214, 178, 96)
"""The color of gold lace and braid."""


def _both(
    mut cover: Cover, right: Joint, left: Joint, end: Float32, start: Float32
) raises:
    """Cover the same span of a joint on each side."""
    cover.reach_to(right, end, start)
    cover.reach_to(left, end, start)


def _trunk(mut cover: Cover, neck: Float32) raises:
    """Cover the hips, the spine, the chest and the neck to a share."""
    cover.reach_to(HIPS)
    cover.reach_to(SPINE)
    cover.reach_to(CHEST)
    cover.reach_to(NECK, neck)


def _sleeves(mut cover: Cover, forearm: Float32) raises:
    """Cover each upper arm, and each forearm to a share."""
    _both(cover, RIGHT_UPPER_ARM, LEFT_UPPER_ARM, 1, 0)
    _both(cover, RIGHT_FOREARM, LEFT_FOREARM, forearm, 0)


def chemise() raises -> Garment:
    """Return a woman's chemise of bleached linen, worn next to the skin.

    Its scoop neck shows the throat, and its full sleeves gather at the
    wrist.

    Returns:
        The garment.

    Raises:
        Error: If its cover is refused, which a tailor's garment's is not.
    """
    var cover = Cover()
    _trunk(cover, 0.08)
    _sleeves(cover, 0.9)
    _both(cover, RIGHT_THIGH, LEFT_THIGH, 0.45, 0)
    return Garment(
        "chemise",
        TORSO_SLOT,
        UNDER_LAYER,
        LINEN,
        cover^,
        BLEACHED,
        ease=Length(4, MILLIMETER),
        neckline=SCOOP_NECK,
        sleeve=BISHOP_SLEEVE,
        ruffles=CUFF_RUFFLES | COLLAR_RUFFLE,
    )


def laced_shirt() raises -> Garment:
    """Return a man's shirt of undyed linen, laced at the neck.

    Its neck is slit down the front, and its full sleeves gather at the
    wrist.

    Returns:
        The garment.

    Raises:
        Error: If its cover is refused, which a tailor's garment's is not.
    """
    var cover = Cover()
    _trunk(cover, 0.22)
    _sleeves(cover, 0.88)
    _both(cover, RIGHT_THIGH, LEFT_THIGH, 0.25, 0)
    return Garment(
        "laced shirt",
        TORSO_SLOT,
        UNDER_LAYER,
        LINEN,
        cover^,
        UNBLEACHED,
        ease=Length(5, MILLIMETER),
        neckline=SLIT_NECK,
        sleeve=BISHOP_SLEEVE,
    )


def skirt() raises -> Garment:
    """Return a long wool skirt from the waist to the ankle.

    Returns:
        The garment.

    Raises:
        Error: If its cover is refused, which a tailor's garment's is not.
    """
    var cover = Cover()
    cover.reach_to(HIPS, 1, 0.45)
    _both(cover, RIGHT_THIGH, LEFT_THIGH, 1, 0)
    _both(cover, RIGHT_SHIN, LEFT_SHIN, 0.85, 0)
    return Garment(
        "skirt",
        LEGS_SLOT,
        MID_LAYER,
        WOOL,
        cover^,
        Color(176, 132, 52),
        form=SKIRTED,
        flare=0.28,
    )


def apron() raises -> Garment:
    """Return a linen apron over the front of the skirt, to mid-calf.

    Returns:
        The garment.

    Raises:
        Error: If its cover is refused, which a tailor's garment's is not.
    """
    var cover = Cover()
    cover.reach_to(HIPS, 1, 0.5)
    _both(cover, RIGHT_THIGH, LEFT_THIGH, 1, 0)
    _both(cover, RIGHT_SHIN, LEFT_SHIN, 0.55, 0)
    return Garment(
        "apron",
        WAIST_SLOT,
        OUTER_LAYER,
        LINEN,
        cover^,
        BLEACHED,
        form=SKIRTED,
        flare=0.08,
        opening=FRONT_ONLY,
    )


def laced_bodice() raises -> Garment:
    """Return a wool bodice from the waist to under the arms, with a
    square neck and no sleeves, laced up the front.

    Returns:
        The garment.

    Raises:
        Error: If its cover is refused, which a tailor's garment's is not.
    """
    var cover = Cover()
    cover.reach_to(HIPS, 1, 0.55)
    cover.reach_to(SPINE)
    cover.reach_to(CHEST, 0.7)
    return Garment(
        "laced bodice",
        TORSO_SLOT,
        OUTER_LAYER,
        WOOL,
        cover^,
        Color(92, 56, 34),
        ease=Length(2, MILLIMETER),
        neckline=SQUARE_NECK,
    )


def doublet() raises -> Garment:
    """Return a fitted doublet to the hip, with a high collar, puffed
    shoulders, and a placket of lace down its front.

    Returns:
        The garment.

    Raises:
        Error: If its cover is refused, which a tailor's garment's is not.
    """
    var cover = Cover()
    _trunk(cover, 0.38)
    _sleeves(cover, 0.88)
    _both(cover, RIGHT_THIGH, LEFT_THIGH, 0.14, 0)
    var coat = Garment(
        "doublet",
        TORSO_SLOT,
        MID_LAYER,
        WOOL,
        cover^,
        Color(40, 52, 96),
        pattern=FRONT_PANEL,
        ease=Length(4, MILLIMETER),
        sleeve=PUFFED_SHOULDER,
    )
    coat.dyes[SECONDARY_DYE.value] = GOLD_LACE
    coat.dyes[TRIM_DYE.value] = GOLD_LACE
    return coat^


def waistcoat() raises -> Garment:
    """Return a silk waistcoat with a V neck and no sleeves, to below the
    waist.

    Returns:
        The garment.

    Raises:
        Error: If its cover is refused, which a tailor's garment's is not.
    """
    var cover = Cover()
    _trunk(cover, 0.05)
    _both(cover, RIGHT_THIGH, LEFT_THIGH, 0.12, 0)
    var vest = Garment(
        "waistcoat",
        TORSO_SLOT,
        MID_LAYER,
        SILK,
        cover^,
        Color(132, 24, 36),
        ease=Length(3, MILLIMETER),
        neckline=V_NECK,
    )
    vest.dyes[TRIM_DYE.value] = GOLD_LACE
    return vest^


def frock_coat() raises -> Garment:
    """Return a wool frock coat with a collar, to below the knee, closed
    to the waist and parted below it.

    Returns:
        The garment.

    Raises:
        Error: If its cover is refused, which a tailor's garment's is not.
    """
    var cover = Cover()
    _trunk(cover, 0.32)
    _sleeves(cover, 0.86)
    _both(cover, RIGHT_THIGH, LEFT_THIGH, 1, 0)
    _both(cover, RIGHT_SHIN, LEFT_SHIN, 0.3, 0)
    var coat = Garment(
        "frock coat",
        TORSO_SLOT,
        OUTER_LAYER,
        WOOL,
        cover^,
        Color(30, 30, 38),
        ease=Length(6, MILLIMETER),
        form=SKIRTED,
        flare=0.22,
        opening=OPEN_BELOW,
    )
    coat.dyes[TRIM_DYE.value] = GOLD_LACE
    return coat^


def long_coat() raises -> Garment:
    """Return a velvet coat with a collar, to below the knee, open down
    the front over a waistcoat.

    Returns:
        The garment.

    Raises:
        Error: If its cover is refused, which a tailor's garment's is not.
    """
    var cover = Cover()
    _trunk(cover, 0.32)
    _sleeves(cover, 0.86)
    _both(cover, RIGHT_THIGH, LEFT_THIGH, 1, 0)
    _both(cover, RIGHT_SHIN, LEFT_SHIN, 0.4, 0)
    var coat = Garment(
        "long coat",
        TORSO_SLOT,
        OUTER_LAYER,
        VELVET,
        cover^,
        Color(96, 18, 32),
        ease=Length(6, MILLIMETER),
        form=SKIRTED,
        flare=0.25,
        opening=OPEN_FRONT,
    )
    coat.dyes[TRIM_DYE.value] = GOLD_LACE
    return coat^


def open_robe() raises -> Garment:
    """Return a velvet robe open down the front, to the ankle.

    Returns:
        The garment.

    Raises:
        Error: If its cover is refused, which a tailor's garment's is not.
    """
    var cover = Cover()
    _trunk(cover, 0.3)
    _sleeves(cover, 0.86)
    _both(cover, RIGHT_THIGH, LEFT_THIGH, 1, 0)
    _both(cover, RIGHT_SHIN, LEFT_SHIN, 0.85, 0)
    var robe = Garment(
        "open robe",
        TORSO_SLOT,
        OVER_LAYER,
        VELVET,
        cover^,
        Color(120, 22, 40),
        ease=Length(8, MILLIMETER),
        form=SKIRTED,
        flare=0.3,
        opening=OPEN_FRONT,
    )
    robe.dyes[TRIM_DYE.value] = GOLD_LACE
    return robe^


def ball_gown() raises -> Garment:
    """Return a silk gown to the floor, wide in the skirt, with a square
    neck, puffed shoulders, sleeves to the elbow and a panel down its
    front.

    Returns:
        The garment.

    Raises:
        Error: If its cover is refused, which a tailor's garment's is not.
    """
    var cover = Cover()
    _trunk(cover, 0)
    _sleeves(cover, 0.4)
    _both(cover, RIGHT_THIGH, LEFT_THIGH, 1, 0)
    _both(cover, RIGHT_SHIN, LEFT_SHIN, 1, 0)
    var gown = Garment(
        "ball gown",
        TORSO_SLOT,
        MID_LAYER,
        SILK,
        cover^,
        Color(76, 44, 150),
        pattern=FRONT_PANEL,
        form=SKIRTED,
        flare=0.6,
        neckline=SQUARE_NECK,
        sleeve=PUFFED_SHOULDER,
        ruffles=CUFF_RUFFLES,
    )
    gown.dyes[SECONDARY_DYE.value] = Color(214, 206, 230)
    gown.dyes[TRIM_DYE.value] = Color(232, 226, 210)
    return gown^


def tailored() raises -> List[Garment]:
    """Return every garment of this module.

    Returns:
        The garments, in the order of the module's table.

    Raises:
        Error: If a garment's cover is refused, which none is.
    """
    return [
        chemise(),
        laced_shirt(),
        skirt(),
        apron(),
        laced_bodice(),
        doublet(),
        waistcoat(),
        frock_coat(),
        long_coat(),
        open_robe(),
        ball_gown(),
    ]
