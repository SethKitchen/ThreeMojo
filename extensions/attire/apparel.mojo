# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""More clothes: work clothes, furs, robes, boots, and five hats.

| Garment | Slot | Layer | Fabric | Form |
|---|---|---|---|---|
| `smock` | torso | mid | linen, cut loose, to mid-thigh | skirted, flare 0.3 |
| `bodice` | torso | outer | velvet, laced over a gown | fitted |
| `trousers` | legs | mid | wool, cut loose, to the ankle | fitted |
| `fur_kilt` | waist | outer | fur, to above the knee | skirted, flare 0.25 |
| `fur_mantle` | shoulders | over | fur, round the shoulders | fitted |
| `royal_mantle` | shoulders | over | velvet, edged in white fur | fitted |
| `wizard_robe` | torso | mid | wool, cut loose, to the floor | skirted, flare 0.35 |
| `cassock` | torso | mid | wool, a high collar, to the ankles | skirted, flare 0.2 |
| `tall_boots` | feet | outer | leather, to the knee | shod |
| `fur_boots` | feet | outer | fur, to mid-shin | shod |
| `sash` | waist | over | silk | banded |
| `wizard_hat` | head | over | felt | hatted, a wizard's hat |
| `straw_hat` | head | over | straw | hatted, a straw hat |
| `feathered_cap` | head | over | felt, a red feather | hatted, a feathered cap |
| `crown` | head | over | gold plate, rubies | hatted, a crown |
| `circlet` | head | over | silver plate, a sapphire | hatted, a circlet |

Each hat rides the head. A great helm hides the hair; every hat here
leaves it below its brim or band.

This is not a three.js port. See Extensions.

    var outfit = Outfit()
    outfit.add(wizard_robe())
    outfit.add(wizard_hat())
"""

from extensions.attire.cover import Cover
from extensions.attire.garment import Garment, forged
from extensions.attire.kinds import (
    ACCENT_DYE,
    BANDED,
    CIRCLET,
    CROWN,
    FEATHERED_CAP,
    FEET_SLOT,
    FELT,
    FUR,
    HATTED,
    HEAD_SLOT,
    LEATHER,
    LEGS_SLOT,
    LINEN,
    MID_LAYER,
    OUTER_LAYER,
    OVER_LAYER,
    PLATE,
    RIGID,
    SHOD,
    SHOULDERS_SLOT,
    SILK,
    SKIRTED,
    STRAW,
    STRAW_HAT,
    TORSO_SLOT,
    TRIM_DYE,
    VELVET,
    WAIST_SLOT,
    WIZARD_HAT,
    WOOL,
    FabricKind,
    Headwear,
)
from extensions.attire.metal import GOLD, SILVER
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
from units.si import CENTIMETER, MILLIMETER, Length

comptime ERMINE = Color(236, 232, 222)
"""The white of the fur along a royal mantle's edge."""


def _both(
    mut cover: Cover, right: Joint, left: Joint, end: Float32, start: Float32
) raises:
    """Cover the same span of a joint on each side."""
    cover.reach_to(right, end, start)
    cover.reach_to(left, end, start)


def _trunk(mut cover: Cover) raises:
    """Cover the hips, the spine and the chest."""
    cover.reach_to(HIPS)
    cover.reach_to(SPINE)
    cover.reach_to(CHEST)


def smock() raises -> Garment:
    """Return a loose linen smock with long sleeves, to mid-thigh.

    Returns:
        The garment.

    Raises:
        Error: If its cover is refused, which an apparel garment's is not.
    """
    var cover = Cover()
    _trunk(cover)
    cover.reach_to(NECK, 0.15)
    _both(cover, RIGHT_UPPER_ARM, LEFT_UPPER_ARM, 1, 0)
    _both(cover, RIGHT_FOREARM, LEFT_FOREARM, 0.7, 0)
    _both(cover, RIGHT_THIGH, LEFT_THIGH, 0.5, 0)
    return Garment(
        "smock",
        TORSO_SLOT,
        MID_LAYER,
        LINEN,
        cover^,
        Color(206, 196, 168),
        drape=4,
        ease=Length(1.2, CENTIMETER),
        form=SKIRTED,
        flare=0.3,
    )


def bodice() raises -> Garment:
    """Return a velvet bodice from the waist to under the arms.

    Returns:
        The garment.

    Raises:
        Error: If its cover is refused, which an apparel garment's is not.
    """
    var cover = Cover()
    cover.reach_to(HIPS, 1, 0.75)
    cover.reach_to(SPINE)
    cover.reach_to(CHEST, 0.62)
    return Garment(
        "bodice",
        TORSO_SLOT,
        OUTER_LAYER,
        VELVET,
        cover^,
        Color(60, 30, 40),
        drape=10,
    )


def trousers() raises -> Garment:
    """Return loose wool trousers, from the waist to the ankle.

    Returns:
        The garment.

    Raises:
        Error: If its cover is refused, which an apparel garment's is not.
    """
    var cover = Cover()
    cover.reach_to(HIPS, 0.6)
    _both(cover, RIGHT_THIGH, LEFT_THIGH, 1, 0)
    _both(cover, RIGHT_SHIN, LEFT_SHIN, 0.9, 0)
    return Garment(
        "trousers",
        LEGS_SLOT,
        MID_LAYER,
        WOOL,
        cover^,
        Color(84, 70, 52),
        drape=3,
        ease=Length(8, MILLIMETER),
    )


def fur_kilt() raises -> Garment:
    """Return a kilt of fur, from the waist to above the knee.

    Returns:
        The garment.

    Raises:
        Error: If its cover is refused, which an apparel garment's is not.
    """
    var cover = Cover()
    cover.reach_to(HIPS, 0.45)
    _both(cover, RIGHT_THIGH, LEFT_THIGH, 0.5, 0)
    return Garment(
        "fur kilt",
        WAIST_SLOT,
        OUTER_LAYER,
        FUR,
        cover^,
        Color(112, 86, 60),
        form=SKIRTED,
        flare=0.25,
    )


def _mantle(name: String, fabric: FabricKind, dye: Color) raises -> Garment:
    """Return a mantle round the shoulders, high at the neck."""
    var cover = Cover()
    cover.reach_to(CHEST, 1, 0.7)
    cover.reach_to(NECK, 0.45)
    _both(cover, RIGHT_UPPER_ARM, LEFT_UPPER_ARM, 0.3, 0)
    return Garment(
        name,
        SHOULDERS_SLOT,
        OVER_LAYER,
        fabric,
        cover^,
        dye,
        drape=12,
        ease=Length(1.2, CENTIMETER),
    )


def fur_mantle() raises -> Garment:
    """Return a mantle of fur round the shoulders.

    Returns:
        The garment.

    Raises:
        Error: If its cover is refused, which an apparel garment's is not.
    """
    return _mantle("fur mantle", FUR, Color(96, 74, 54))


def royal_mantle() raises -> Garment:
    """Return a velvet mantle round the shoulders, edged in white fur.

    Returns:
        The garment.

    Raises:
        Error: If its cover is refused, which an apparel garment's is not.
    """
    var mantle = _mantle("royal mantle", VELVET, Color(140, 18, 36))
    mantle.dyes[TRIM_DYE.value] = ERMINE
    return mantle^


def wizard_robe() raises -> Garment:
    """Return a loose wool robe with long sleeves, to the floor.

    Returns:
        The garment.

    Raises:
        Error: If its cover is refused, which an apparel garment's is not.
    """
    var cover = Cover()
    _trunk(cover)
    cover.reach_to(NECK, 0.25)
    _both(cover, RIGHT_UPPER_ARM, LEFT_UPPER_ARM, 1, 0)
    _both(cover, RIGHT_FOREARM, LEFT_FOREARM, 1, 0)
    _both(cover, RIGHT_THIGH, LEFT_THIGH, 1, 0)
    _both(cover, RIGHT_SHIN, LEFT_SHIN, 0.95, 0)
    var robe = Garment(
        "wizard robe",
        TORSO_SLOT,
        MID_LAYER,
        WOOL,
        cover^,
        Color(38, 52, 112),
        drape=6,
        ease=Length(1.5, CENTIMETER),
        form=SKIRTED,
        flare=0.35,
    )
    robe.dyes[TRIM_DYE.value] = Color(214, 170, 64)
    return robe^


def cassock() raises -> Garment:
    """Return a close wool robe with a high collar, to the ankles.

    Returns:
        The garment.

    Raises:
        Error: If its cover is refused, which an apparel garment's is not.
    """
    var cover = Cover()
    _trunk(cover)
    cover.reach_to(NECK, 0.6)
    _both(cover, RIGHT_UPPER_ARM, LEFT_UPPER_ARM, 1, 0)
    _both(cover, RIGHT_FOREARM, LEFT_FOREARM, 0.9, 0)
    _both(cover, RIGHT_THIGH, LEFT_THIGH, 1, 0)
    _both(cover, RIGHT_SHIN, LEFT_SHIN, 0.85, 0)
    var robe = Garment(
        "cassock",
        TORSO_SLOT,
        MID_LAYER,
        WOOL,
        cover^,
        Color(30, 26, 34),
        drape=4,
        ease=Length(6, MILLIMETER),
        form=SKIRTED,
        flare=0.2,
    )
    robe.dyes[TRIM_DYE.value] = Color(110, 24, 40)
    return robe^


def _boots(
    name: String, fabric: FabricKind, start: Float32, dye: Color
) raises -> Garment:
    """Return boots from a point down the shin to the toes."""
    var cover = Cover()
    _both(cover, RIGHT_SHIN, LEFT_SHIN, 1, start)
    _both(cover, RIGHT_FOOT, LEFT_FOOT, 1, 0)
    _both(cover, RIGHT_TOES, LEFT_TOES, 1, 0)
    return Garment(
        name,
        FEET_SLOT,
        OUTER_LAYER,
        fabric,
        cover^,
        dye,
        drape=24,
        ease=Length(5, MILLIMETER),
        form=SHOD,
    )


def tall_boots() raises -> Garment:
    """Return leather boots to the knee.

    Returns:
        The garment.

    Raises:
        Error: If its cover is refused, which an apparel garment's is not.
    """
    return _boots("tall boots", LEATHER, 0.04, Color(70, 46, 28))


def fur_boots() raises -> Garment:
    """Return boots of fur to the middle of the shin.

    Returns:
        The garment.

    Raises:
        Error: If its cover is refused, which an apparel garment's is not.
    """
    return _boots("fur boots", FUR, 0.4, Color(100, 80, 58))


def sash() raises -> Garment:
    """Return a silk sash round the waist.

    Returns:
        The garment.

    Raises:
        Error: If its cover is refused, which an apparel garment's is not.
    """
    var cover = Cover()
    cover.reach_to(HIPS, 1, 0.8)
    cover.reach_to(SPINE, 0.18, 0)
    return Garment(
        "sash",
        WAIST_SLOT,
        OVER_LAYER,
        SILK,
        cover^,
        Color(170, 32, 40),
        drape=12,
        form=BANDED,
    )


def _hat(
    name: String, fabric: FabricKind, headwear: Headwear, dye: Color
) raises -> Garment:
    """Return a hat over the head, rigid on it."""
    var cover = Cover()
    cover.reach_to(HEAD)
    return Garment(
        name,
        HEAD_SLOT,
        OVER_LAYER,
        fabric,
        cover^,
        dye,
        articulation=RIGID,
        anchor=HEAD,
        form=HATTED,
        headwear=headwear,
    )


def wizard_hat() raises -> Garment:
    """Return a tall pointed felt hat with a wide brim.

    Returns:
        The garment.

    Raises:
        Error: If its cover is refused, which an apparel garment's is not.
    """
    var hat = _hat("wizard hat", FELT, WIZARD_HAT, Color(38, 52, 112))
    hat.dyes[TRIM_DYE.value] = Color(214, 170, 64)
    return hat^


def straw_hat() raises -> Garment:
    """Return a straw hat with a wide brim.

    Returns:
        The garment.

    Raises:
        Error: If its cover is refused, which an apparel garment's is not.
    """
    var hat = _hat("straw hat", STRAW, STRAW_HAT, Color(214, 182, 112))
    hat.dyes[TRIM_DYE.value] = Color(110, 64, 40)
    return hat^


def feathered_cap() raises -> Garment:
    """Return a peaked felt cap with a red feather.

    Returns:
        The garment.

    Raises:
        Error: If its cover is refused, which an apparel garment's is not.
    """
    var cap = _hat("feathered cap", FELT, FEATHERED_CAP, Color(52, 82, 40))
    cap.dyes[ACCENT_DYE.value] = Color(176, 30, 30)
    return cap^


def crown() raises -> Garment:
    """Return a crown of gold, set with rubies.

    Returns:
        The garment.

    Raises:
        Error: If its cover is refused, which an apparel garment's is not.
    """
    var made = forged(_hat("crown", PLATE, CROWN, Color(0, 0, 0)), GOLD)
    made.dyes[ACCENT_DYE.value] = Color(170, 16, 30)
    return made^


def circlet() raises -> Garment:
    """Return a circlet of silver, set with a sapphire.

    Returns:
        The garment.

    Raises:
        Error: If its cover is refused, which an apparel garment's is not.
    """
    var made = forged(_hat("circlet", PLATE, CIRCLET, Color(0, 0, 0)), SILVER)
    made.dyes[ACCENT_DYE.value] = Color(24, 50, 160)
    return made^


def apparel() raises -> List[Garment]:
    """Return every garment of this module.

    Returns:
        The garments, in the order of the module's table.

    Raises:
        Error: If a garment's cover is refused, which none is.
    """
    return [
        smock(),
        bodice(),
        trousers(),
        fur_kilt(),
        fur_mantle(),
        royal_mantle(),
        wizard_robe(),
        cassock(),
        tall_boots(),
        fur_boots(),
        sash(),
        wizard_hat(),
        straw_hat(),
        feathered_cap(),
        crown(),
        circlet(),
    ]
