# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""What each solid of a sculpt is made of, and which body segment it is.

A sculpt is drawn for the eye: a mane, a fleece and a bird's tail
coverts are solids like the trunk. Mass must not count them as flesh.
`tissue_of` sorts each solid by its surface part and its tag into soft
body, coat, keratin, antler, tooth, eye or a foreign object. `segment_of`
sorts each bone into the segment whose published density it takes.
"""

from extensions.animals.anatomy.body import (
    ANURAN,
    ARACHNID,
    MAMMAL,
    BodyPlan,
)
from extensions.animals.parts import EYEBALL, HORN, TEETH
from extensions.sdf.ids import SurfacePart, require_part


@fieldwise_init
struct BodyTissue(Equatable, ImplicitlyCopyable, Writable):
    """What one solid of a sculpt is made of."""

    var value: Int

    def is_valid(self) -> Bool:
        """Return whether this is a named tissue.

        Returns:
            True for the seven tissues.
        """
        return self.value >= 0 and self.value <= 6


# Skin, muscle, bone and viscera: the segment's density.
comptime SOFT_BODY = BodyTissue(0)
# Hair, wool and feathers: drawn, but not counted as flesh.
comptime COAT = BodyTissue(1)
# Hoof, claw, horn sheath and bill.
comptime KERATIN = BodyTissue(2)
# Antler: bone, grown and shed each year.
comptime ANTLER = BodyTissue(3)
# Teeth, tusks and fangs.
comptime TOOTH = BodyTissue(4)
# The eyeball.
comptime EYE = BodyTissue(5)
# Not the animal's: an ear tag.
comptime FOREIGN = BodyTissue(6)


@fieldwise_init
struct Segment(Equatable, ImplicitlyCopyable, Writable):
    """A body segment, for its density."""

    var value: Int

    def is_valid(self) -> Bool:
        """Return whether this is a named segment.

        Returns:
            True for the fifteen segments.
        """
        return self.value >= 0 and self.value < SEGMENT_COUNT


comptime HEAD = Segment(0)
comptime NECK = Segment(1)
comptime THORAX = Segment(2)
comptime ABDOMEN = Segment(3)
comptime PELVIS = Segment(4)
comptime UPPER_ARM = Segment(5)
comptime FOREARM = Segment(6)
comptime HAND = Segment(7)
comptime THIGH = Segment(8)
comptime SHANK = Segment(9)
comptime FOOT = Segment(10)
comptime TAIL = Segment(11)
# A fish's paired fin.
comptime FIN = Segment(12)
# An arthropod's leg or palp.
comptime LEG = Segment(13)
# A flight feather's bone: plumage only.
comptime PLUMAGE = Segment(14)
comptime SEGMENT_COUNT = 15

comptime _COAT_TAGS: List[StaticString] = [
    "beard",
    "breeches",
    "bristles",
    "cape",
    "cheekruff",
    "coverts",
    "cuff",
    "cushion",
    "elbowtuft",
    "feather",
    "fleece",
    "fluff",
    "forelock",
    "hackle",
    "hackles",
    "lock",
    "lockleg",
    "mane",
    "manecrest",
    "mantle",
    "primary",
    "rectrix",
    "ruff",
    "scapular",
    "scut",
    "secondary",
    "switch",
    "tailhair",
    "tassel",
    "trousers",
    "tuft",
    "undertail",
    "uppertail",
    "whisker",
    "woolarm",
    "woolbelly",
    "woolleg",
    "woolneck",
    "wooltail",
    "woolthigh",
]

comptime _KERATIN_TAGS: List[StaticString] = [
    "bill",
    "button",
    "claw",
    "claws",
    "ergot",
    "gonys",
    "hoof",
    "rattle",
]


def _stem(tag: String) -> String:
    # A feather's tag carries its layout after `@` or `#`.
    var bytes = tag.as_bytes()
    for i in range(len(bytes)):
        var c = Int(bytes[i])
        if c == ord("@") or c == ord("#"):
            return String(tag[byte=0:i])
    return tag


def _listed(tag: String, names: List[StaticString]) -> Bool:
    for name in names:  # pragma: no branch
        if tag == name:
            return True
    return False


def tissue_of(
    part: SurfacePart, tag: String, bone: String
) raises -> BodyTissue:
    """Return what a solid is made of.

    Args:
        part: The surface the solid is meshed in.
        tag: The solid's tag.
        bone: The name of the bone the solid rides.

    Returns:
        Its tissue.

    Raises:
        Error: If the surface part is unnamed.
    """
    require_part(part)
    if part == EYEBALL:
        return EYE
    if part == TEETH:
        return TOOTH
    var stem = _stem(tag)
    if part == HORN:
        if stem == "horn":
            return KERATIN
        return ANTLER
    if stem == "eartag":
        return FOREIGN
    if _listed(stem, materialize[_COAT_TAGS]()):
        return COAT
    if _listed(stem, materialize[_KERATIN_TAGS]()):
        return KERATIN
    if stem == "sole" and "hoof" in bone:
        return KERATIN
    return SOFT_BODY


def _base(name: String) -> String:
    # Drop a side suffix and the digits of a chain: `femur1L` is `femur`.
    var bytes = name.as_bytes()
    var end = len(bytes)
    if end == 0:
        return String()
    var last = Int(bytes[end - 1])
    if last == ord("L") or last == ord("R"):
        end -= 1
    var out = String()
    for i in range(end):
        var c = Int(bytes[i])
        var digit = c >= ord("0") and c <= ord("9")
        if not digit:
            out += chr(c)
    return out^


def segment_of(plan: BodyPlan, bone: String) raises -> Segment:
    """Return the segment a bone belongs to.

    Args:
        plan: The species' body plan.
        bone: The bone's name.

    Returns:
        Its segment.

    Raises:
        Error: If the plan is not named.
    """
    if not plan.is_valid():
        raise Error("A body plan must be named")
    var b = _base(bone)
    if plan == ARACHNID:
        if b == "prosoma" or b == "pedicel":
            return THORAX
        if b == "abdomen" or b == "spinnerets":
            return ABDOMEN
        if b == "head" or b == "chelicera" or b == "fang":
            return HEAD
        return LEG
    if b in ["pri", "sec", "rec"]:
        return PLUMAGE
    if b == "spine":
        # The quadruped rig runs spine1 to spine3 from the loin to the
        # ribs; a fish's or a snake's spine bones are all trunk.
        var tetrapod = plan == MAMMAL or plan == ANURAN
        if tetrapod and bone == "spine3":
            return THORAX
        return ABDOMEN
    if b == "chest":
        return THORAX
    if b == "pelvis":
        return PELVIS
    if b.startswith("neck"):
        return NECK
    if b in ["tail", "caudal"]:
        return TAIL
    if b in ["pectoral", "pelvic"]:
        return FIN
    if b in ["scapula", "humerus"]:
        return UPPER_ARM
    if b in ["radius", "ulna"]:
        return FOREARM
    if b in ["metacarpus", "fpaw", "fhoof", "hand"]:
        return HAND
    if b == "femur":
        return THIGH
    if b == "tibia":
        return SHANK
    if b in ["metatarsus", "hpaw", "hhoof", "tarsus", "toea", "toeb"]:
        return FOOT
    if b == "udder":
        return ABDOMEN
    return HEAD
