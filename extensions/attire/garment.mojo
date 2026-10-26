# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""One garment: where it goes, what it is made of, what it covers.

A garment names its slot and its layer, its fabric, its cover, how it
follows the bones, and its four dyes in a pattern. It holds no mesh.
`dress` makes its mesh from the skin of the person who wears it.

The wardrobe below gives a set of medieval garments and armor, from the
skin out:

| Garment | Slot | Layer | Fabric | Articulation |
|---|---|---|---|---|
| `shirt` | torso | under | linen | flexible |
| `hose` | legs | under | wool | flexible |
| `tunic` | torso | mid | wool | flexible |
| `gambeson` | torso | mid | padding | flexible |
| `hauberk` | torso | outer | mail, brass at the hems | flexible |
| `coif` | head | outer | mail | flexible |
| `hood` | head | over | wool | flexible |
| `boots` | feet | outer | leather | flexible |
| `gloves` | hands | outer | leather | flexible |
| `cuirass` | torso | armor | plate | rigid on the chest |
| `fauld` | waist | armor | plate | four lames from the hips |
| `pauldrons` | shoulders | armor | plate | three lames from the chest |
| `vambraces` | arms | armor | plate | rigid on each forearm |
| `greaves` | legs | armor | plate | rigid on each shin |
| `bascinet` | head | armor | plate | rigid on the head |
| `surcoat` | torso | over | linen | flexible, per pale |

This is not a three.js port. See Extensions.

    var mail = hauberk()
    mail.dyes[PRIMARY_DYE.value] = Color(190, 190, 196)
"""

from extensions.attire.cover import Cover
from extensions.attire.kinds import (
    ARMOR_LAYER,
    ARMS_SLOT,
    DYE_CHANNEL_COUNT,
    FEET_SLOT,
    FLEXIBLE,
    HANDS_SLOT,
    HEAD_SLOT,
    LAMED,
    LEATHER,
    LEGS_SLOT,
    LINEN,
    MAIL,
    MID_LAYER,
    TRIM_DYE,
    OUTER_LAYER,
    OVER_LAYER,
    PADDING,
    PARTY,
    PLATE,
    RIGID,
    SHOULDERS_SLOT,
    SOLID,
    TORSO_SLOT,
    UNDER_LAYER,
    WAIST_SLOT,
    WOOL,
    Articulation,
    DyePattern,
    FabricKind,
    Layer,
    Slot,
    require_articulation,
    require_dye_pattern,
    require_fabric_kind,
    require_layer,
    require_slot,
)
from extensions.humanoid.rig.joints import (
    CHEST,
    HEAD,
    HIPS,
    LEFT_FOOT,
    LEFT_FOREARM,
    LEFT_HAND,
    LEFT_SHIN,
    LEFT_THIGH,
    LEFT_TOES,
    LEFT_UPPER_ARM,
    NECK,
    RIGHT_FOOT,
    RIGHT_FOREARM,
    RIGHT_HAND,
    RIGHT_SHIN,
    RIGHT_THIGH,
    RIGHT_TOES,
    RIGHT_UPPER_ARM,
    SPINE,
    Joint,
    require_joint,
)
from render.framebuffer import Color
from units.si import CENTIMETER, METER, MILLIMETER, Length

comptime NO_ANCHOR = Joint(-1)
"""No anchor: a rigid garment rides each vertex's heaviest bone."""
comptime MAX_LAMES = 12
"""The most lames a garment can have."""


struct Garment(Copyable, Movable):
    """One garment, before it is made for a body."""

    var name: String
    """What the garment is called, as its mesh is named."""
    var slot: Slot
    """Where it goes."""
    var layer: Layer
    """How far from the skin it sits."""
    var fabric: FabricKind
    """What it is made of."""
    var cover: Cover
    """What it covers."""
    var articulation: Articulation
    """How it follows the bones."""
    var anchor: Joint
    """The bone a rigid garment rides, or the top bone of lames.
    `NO_ANCHOR` makes a rigid garment ride each vertex's heaviest bone."""
    var lames: Int
    """How many bands of plate a lamed garment has."""
    var pattern: DyePattern
    """How its dyes lie over it."""
    var dyes: List[Color]
    """Its four dyes, primary, secondary, trim and accent, in sRGB."""
    var drape: Int
    """Smoothing passes of its shell, or -1 for its fabric's own."""
    var ease: Length
    """How much looser than its fabric's clearance it is cut."""

    def __init__(
        out self,
        name: String,
        slot: Slot,
        layer: Layer,
        fabric: FabricKind,
        var cover: Cover,
        dye: Color,
        articulation: Articulation = FLEXIBLE,
        anchor: Joint = NO_ANCHOR,
        lames: Int = 0,
        pattern: DyePattern = SOLID,
        drape: Int = -1,
        ease: Length = Length(0, METER),
    ):
        """Describe a garment, dyed one color.

        Args:
            name: What it is called.
            slot: Where it goes.
            layer: How far from the skin it sits.
            fabric: What it is made of.
            cover: What it covers.
            dye: The color of all four dye channels.
            articulation: How it follows the bones. Flexible by default.
            anchor: The bone it rides, or `NO_ANCHOR`.
            lames: How many bands of plate, for a lamed garment.
            pattern: How its dyes lie. Solid by default.
            drape: Smoothing passes of its shell, or -1 for its fabric's.
            ease: How much looser than its fabric's clearance it is cut.
        """
        self.name = name
        self.slot = slot
        self.layer = layer
        self.fabric = fabric
        self.cover = cover^
        self.articulation = articulation
        self.anchor = anchor
        self.lames = lames
        self.pattern = pattern
        self.dyes = List[Color](length=DYE_CHANNEL_COUNT, fill=dye)
        self.drape = drape
        self.ease = ease

    def check(self) raises:
        """Refuse a garment that cannot be made.

        Raises:
            Error: If a kind is not named, a lamed garment has no anchor
                or not two through `MAX_LAMES` lames, an anchor is not a
                named joint, there are not four dyes, the drape is
                below -1, or the ease is negative or not finite.
        """
        require_slot(self.slot)
        require_layer(self.layer)
        require_fabric_kind(self.fabric)
        require_articulation(self.articulation)
        require_dye_pattern(self.pattern)
        if self.anchor != NO_ANCHOR:
            require_joint(self.anchor)
        if self.articulation == LAMED:
            if self.anchor == NO_ANCHOR:
                raise Error("Lames need an anchor bone")
            if self.lames < 2 or self.lames > MAX_LAMES:
                raise Error("A lamed garment needs two through twelve lames")
        if len(self.dyes) != DYE_CHANNEL_COUNT:
            raise Error("A garment needs four dyes")
        if self.drape < -1:
            raise Error("A drape is -1, for the fabric's, or zero or more")
        if not (self.ease.value >= 0 and self.ease.value < 1):
            raise Error("An ease must be at least zero and below a meter")


def _both(
    mut cover: Cover, right: Joint, left: Joint, end: Float32, start: Float32
) raises:
    """Cover the same span of a joint on each side.

    Args:
        cover: The cover.
        right: The joint on the right.
        left: The same joint on the left.
        end: Where the span ends.
        start: Where it starts.

    Raises:
        Error: If the span is refused.
    """
    cover.reach_to(right, end, start)
    cover.reach_to(left, end, start)


def _trunk(mut cover: Cover) raises:
    """Cover the hips, the spine and the chest.

    Args:
        cover: The cover.

    Raises:
        Error: Never: the spans are whole.
    """
    cover.reach_to(HIPS)
    cover.reach_to(SPINE)
    cover.reach_to(CHEST)


def shirt() raises -> Garment:
    """Return a long-sleeved linen shirt, next to the skin.

    Its sleeves end short of the wrist, where the hand's skin reaches up
    over the forearm.

    Returns:
        The garment.

    Raises:
        Error: If its cover is refused, which a wardrobe garment's is not.
    """
    var cover = Cover()
    _trunk(cover)
    cover.reach_to(NECK, 0.2)
    _both(cover, RIGHT_UPPER_ARM, LEFT_UPPER_ARM, 1, 0)
    _both(cover, RIGHT_FOREARM, LEFT_FOREARM, 0.82, 0)
    _both(cover, RIGHT_THIGH, LEFT_THIGH, 0.2, 0)
    return Garment(
        "shirt", TORSO_SLOT, UNDER_LAYER, LINEN, cover^, Color(236, 228, 208)
    )


def hose() raises -> Garment:
    """Return wool hose, from the waist to the toes.

    Returns:
        The garment.

    Raises:
        Error: If its cover is refused, which a wardrobe garment's is not.
    """
    var cover = Cover()
    cover.reach_to(HIPS, 0.55)
    for joint in [  # pragma: no branch
        RIGHT_THIGH,
        RIGHT_SHIN,
        RIGHT_FOOT,
        RIGHT_TOES,
    ]:
        cover.reach_to(joint)
    for joint in [  # pragma: no branch
        LEFT_THIGH,
        LEFT_SHIN,
        LEFT_FOOT,
        LEFT_TOES,
    ]:
        cover.reach_to(joint)
    return Garment(
        "hose", LEGS_SLOT, UNDER_LAYER, WOOL, cover^, Color(70, 52, 40)
    )


def tunic() raises -> Garment:
    """Return a wool tunic with elbow sleeves and a short skirt.

    Returns:
        The garment.

    Raises:
        Error: If its cover is refused, which a wardrobe garment's is not.
    """
    var cover = Cover()
    _trunk(cover)
    cover.reach_to(NECK, 0.12)
    _both(cover, RIGHT_UPPER_ARM, LEFT_UPPER_ARM, 1, 0)
    _both(cover, RIGHT_FOREARM, LEFT_FOREARM, 0.55, 0)
    _both(cover, RIGHT_THIGH, LEFT_THIGH, 0.35, 0)
    return Garment(
        "tunic", TORSO_SLOT, MID_LAYER, WOOL, cover^, Color(40, 70, 120)
    )


def gambeson() raises -> Garment:
    """Return a quilted gambeson with a standing collar.

    Returns:
        The garment.

    Raises:
        Error: If its cover is refused, which a wardrobe garment's is not.
    """
    var cover = Cover()
    _trunk(cover)
    cover.reach_to(NECK, 0.45)
    _both(cover, RIGHT_UPPER_ARM, LEFT_UPPER_ARM, 1, 0)
    _both(cover, RIGHT_FOREARM, LEFT_FOREARM, 0.82, 0)
    _both(cover, RIGHT_THIGH, LEFT_THIGH, 0.3, 0)
    return Garment(
        "gambeson", TORSO_SLOT, MID_LAYER, PADDING, cover^, Color(218, 206, 178)
    )


def hauberk() raises -> Garment:
    """Return a mail hauberk with three-quarter sleeves.

    Returns:
        The garment.

    Raises:
        Error: If its cover is refused, which a wardrobe garment's is not.
    """
    var cover = Cover()
    _trunk(cover)
    cover.reach_to(NECK, 0.3)
    _both(cover, RIGHT_UPPER_ARM, LEFT_UPPER_ARM, 1, 0)
    _both(cover, RIGHT_FOREARM, LEFT_FOREARM, 0.8, 0)
    _both(cover, RIGHT_THIGH, LEFT_THIGH, 0.45, 0)
    var mail = Garment(
        "hauberk", TORSO_SLOT, OUTER_LAYER, MAIL, cover^, Color(120, 122, 128)
    )
    # Many hauberks end in a row of brass rings.
    mail.dyes[TRIM_DYE.value] = Color(176, 132, 62)
    return mail^


def coif() raises -> Garment:
    """Return a mail coif, open at the face.

    Returns:
        The garment.

    Raises:
        Error: If its cover is refused, which a wardrobe garment's is not.
    """
    var cover = Cover()
    cover.reach_to(NECK)
    cover.reach_to(HEAD)
    cover.face_open = True
    return Garment(
        "coif", HEAD_SLOT, OUTER_LAYER, MAIL, cover^, Color(120, 122, 128)
    )


def hood() raises -> Garment:
    """Return a wool hood, open at the face.

    Returns:
        The garment.

    Raises:
        Error: If its cover is refused, which a wardrobe garment's is not.
    """
    var cover = Cover()
    cover.reach_to(NECK)
    cover.reach_to(HEAD)
    cover.face_open = True
    # A hood hangs loose round the head.
    return Garment(
        "hood",
        HEAD_SLOT,
        OVER_LAYER,
        WOOL,
        cover^,
        Color(52, 70, 44),
        drape=8,
        ease=Length(1.8, CENTIMETER),
    )


def boots() raises -> Garment:
    """Return leather boots to the middle of the shin.

    Returns:
        The garment.

    Raises:
        Error: If its cover is refused, which a wardrobe garment's is not.
    """
    var cover = Cover()
    _both(cover, RIGHT_SHIN, LEFT_SHIN, 1, 0.45)
    _both(cover, RIGHT_FOOT, LEFT_FOOT, 1, 0)
    _both(cover, RIGHT_TOES, LEFT_TOES, 1, 0)
    # Stiff leather spans the toes.
    return Garment(
        "boots",
        FEET_SLOT,
        OUTER_LAYER,
        LEATHER,
        cover^,
        Color(84, 54, 32),
        drape=24,
        ease=Length(5, MILLIMETER),
    )


def gloves() raises -> Garment:
    """Return leather gloves with a short cuff.

    Returns:
        The garment.

    Raises:
        Error: If its cover is refused, which a wardrobe garment's is not.
    """
    var cover = Cover()
    _both(cover, RIGHT_HAND, LEFT_HAND, 1, 0)
    _both(cover, RIGHT_FOREARM, LEFT_FOREARM, 1, 0.75)
    return Garment(
        "gloves", HANDS_SLOT, OUTER_LAYER, LEATHER, cover^, Color(62, 42, 30)
    )


def cuirass() raises -> Garment:
    """Return a steel cuirass, breast and back, rigid on the chest.

    Returns:
        The garment.

    Raises:
        Error: If its cover is refused, which a wardrobe garment's is not.
    """
    var cover = Cover()
    cover.reach_to(HIPS, 1, 0.35)
    cover.reach_to(SPINE)
    cover.reach_to(CHEST)
    return Garment(
        "cuirass",
        TORSO_SLOT,
        ARMOR_LAYER,
        PLATE,
        cover^,
        Color(198, 200, 206),
        articulation=RIGID,
        anchor=CHEST,
    )


def fauld() raises -> Garment:
    """Return a fauld of four lames below the cuirass.

    Returns:
        The garment.

    Raises:
        Error: If its cover is refused, which a wardrobe garment's is not.
    """
    var cover = Cover()
    cover.reach_to(HIPS, 0.4)
    _both(cover, RIGHT_THIGH, LEFT_THIGH, 0.32, 0)
    return Garment(
        "fauld",
        WAIST_SLOT,
        ARMOR_LAYER,
        PLATE,
        cover^,
        Color(198, 200, 206),
        articulation=LAMED,
        anchor=HIPS,
        lames=4,
    )


def pauldrons() raises -> Garment:
    """Return a pair of pauldrons of three lames over the shoulders.

    Returns:
        The garment.

    Raises:
        Error: If its cover is refused, which a wardrobe garment's is not.
    """
    var cover = Cover()
    _both(cover, RIGHT_UPPER_ARM, LEFT_UPPER_ARM, 0.45, 0)
    return Garment(
        "pauldrons",
        SHOULDERS_SLOT,
        ARMOR_LAYER,
        PLATE,
        cover^,
        Color(198, 200, 206),
        articulation=LAMED,
        anchor=CHEST,
        lames=3,
    )


def vambraces() raises -> Garment:
    """Return a pair of vambraces, rigid on each forearm.

    Returns:
        The garment.

    Raises:
        Error: If its cover is refused, which a wardrobe garment's is not.
    """
    var cover = Cover()
    _both(cover, RIGHT_FOREARM, LEFT_FOREARM, 0.9, 0.12)
    return Garment(
        "vambraces",
        ARMS_SLOT,
        ARMOR_LAYER,
        PLATE,
        cover^,
        Color(198, 200, 206),
        articulation=RIGID,
    )


def greaves() raises -> Garment:
    """Return a pair of greaves, rigid on each shin.

    Returns:
        The garment.

    Raises:
        Error: If its cover is refused, which a wardrobe garment's is not.
    """
    var cover = Cover()
    _both(cover, RIGHT_SHIN, LEFT_SHIN, 0.92, 0.08)
    return Garment(
        "greaves",
        LEGS_SLOT,
        ARMOR_LAYER,
        PLATE,
        cover^,
        Color(198, 200, 206),
        articulation=RIGID,
    )


def bascinet() raises -> Garment:
    """Return an open-faced bascinet, rigid on the head.

    Returns:
        The garment.

    Raises:
        Error: If its cover is refused, which a wardrobe garment's is not.
    """
    var cover = Cover()
    cover.reach_to(HEAD)
    cover.face_open = True
    return Garment(
        "bascinet",
        HEAD_SLOT,
        ARMOR_LAYER,
        PLATE,
        cover^,
        Color(198, 200, 206),
        articulation=RIGID,
        anchor=HEAD,
    )


def surcoat() raises -> Garment:
    """Return a sleeveless linen surcoat, dyed per pale.

    Returns:
        The garment.

    Raises:
        Error: If its cover is refused, which a wardrobe garment's is not.
    """
    var cover = Cover()
    _trunk(cover)
    cover.reach_to(NECK, 0.1)
    _both(cover, RIGHT_THIGH, LEFT_THIGH, 0.5, 0)
    var coat = Garment(
        "surcoat",
        TORSO_SLOT,
        OVER_LAYER,
        LINEN,
        cover^,
        Color(160, 24, 32),
        pattern=PARTY,
    )
    coat.dyes[1] = Color(232, 196, 64)
    coat.dyes[2] = Color(232, 196, 64)
    return coat^


def wardrobe() raises -> List[Garment]:
    """Return every garment of the wardrobe.

    Returns:
        The garments, in the order of the module's table.

    Raises:
        Error: If a garment's cover is refused, which none is.
    """
    return [
        shirt(),
        hose(),
        tunic(),
        gambeson(),
        hauberk(),
        coif(),
        hood(),
        boots(),
        gloves(),
        cuirass(),
        fauld(),
        pauldrons(),
        vambraces(),
        greaves(),
        bascinet(),
        surcoat(),
    ]
