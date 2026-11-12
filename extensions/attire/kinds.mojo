# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""The named kinds of the attire system.

A slot says where a garment goes. A layer says how far from the skin it
sits: padding under mail under plate. A fabric kind selects the look and
the physical constants. A dye channel and a dye pattern say how a
garment takes color. A wear kind names one channel of dirt, blood, wet
or damage. A form says how a garment's shell is shaped where it does not
follow the skin: a skirt round both legs, a last round each foot, a
cowl round the head, a taut band round the body, or a hat or a helmet
shaped round the head, or a dome over each shoulder. A headwear kind
says which hat or helmet.

Each kind is a type, so a bare integer does not compile. A value that
is not named is still constructible, and the boundary that reads it
refuses it.

This is not a three.js port. See Extensions.

    var layer = layer_named("armor")
    require_layer(layer)
"""

from core.ordinal import ordinal_label, ordinal_valid, require_valid


@fieldwise_init
struct Slot(Equatable, ImplicitlyCopyable, Writable):
    """Where on the body a garment goes."""

    var value: Int
    """Its index among the named values."""

    def is_valid(self) -> Bool:
        """Return whether this is a named slot.

        Returns:
            True for `HEAD_SLOT` through `BACK_SLOT`.
        """
        return ordinal_valid(self.value, SLOT_COUNT - 1)


comptime HEAD_SLOT = Slot(0)
"""The head: a coif, a hood, a helmet."""
comptime NECK_SLOT = Slot(1)
"""The neck: a collar, a gorget."""
comptime SHOULDERS_SLOT = Slot(2)
"""The shoulders: pauldrons, a mantle."""
comptime TORSO_SLOT = Slot(3)
"""The torso: a shirt, a tunic, a hauberk, a cuirass."""
comptime ARMS_SLOT = Slot(4)
"""The arms: vambraces, rerebraces."""
comptime HANDS_SLOT = Slot(5)
"""The hands: gloves, gauntlets."""
comptime WAIST_SLOT = Slot(6)
"""The waist: a belt, a fauld."""
comptime LEGS_SLOT = Slot(7)
"""The legs: hose, greaves, cuisses."""
comptime FEET_SLOT = Slot(8)
"""The feet: boots, sabatons."""
comptime BACK_SLOT = Slot(9)
"""The back: a cloak, a quiver."""
comptime SLOT_COUNT = 10
"""How many slots there are."""


def _slot_names() -> List[String]:
    """Return the slot names, in order."""
    return [
        "head",
        "neck",
        "shoulders",
        "torso",
        "arms",
        "hands",
        "waist",
        "legs",
        "feet",
        "back",
    ]


def slot_label(slot: Slot) -> String:
    """Return the name of a slot.

    Args:
        slot: A slot, named or not.

    Returns:
        Its name, as `"torso"`, or `"slot"` when it is not named.
    """
    return ordinal_label(slot.is_valid(), slot.value, _slot_names(), "slot")


def require_slot(slot: Slot) raises:
    """Refuse a slot that is not named.

    Args:
        slot: The slot.

    Raises:
        Error: If the slot is not named.
    """
    require_valid(slot.is_valid(), "A slot must be a named slot")


@fieldwise_init
struct Layer(Comparable, Equatable, ImplicitlyCopyable, Writable):
    """How far from the skin a garment sits. A higher layer is outside a
    lower one."""

    var value: Int
    """Its index among the named values."""

    def is_valid(self) -> Bool:
        """Return whether this is a named layer.

        Returns:
            True for `UNDER_LAYER` through `OVER_LAYER`.
        """
        return ordinal_valid(self.value, LAYER_COUNT - 1)

    def __lt__(self, other: Self) -> Bool:
        """Return whether this layer is under `other`.

        Args:
            other: The layer to compare with.

        Returns:
            True when this layer is closer to the skin.
        """
        return self.value < other.value


comptime UNDER_LAYER = Layer(0)
"""Next to the skin: a shirt, braies, hose."""
comptime MID_LAYER = Layer(1)
"""Over the under layer: a tunic, a gambeson."""
comptime OUTER_LAYER = Layer(2)
"""Mail and leather over the padding."""
comptime ARMOR_LAYER = Layer(3)
"""Plate over the mail."""
comptime OVER_LAYER = Layer(4)
"""Over everything: a surcoat, a tabard, a cloak."""
comptime LAYER_COUNT = 5
"""How many layers there are."""


def _layer_names() -> List[String]:
    """Return the layer names, in order."""
    return ["under", "mid", "outer", "armor", "over"]


def layer_label(layer: Layer) -> String:
    """Return the name of a layer.

    Args:
        layer: A layer, named or not.

    Returns:
        Its name, as `"armor"`, or `"layer"` when it is not named.
    """
    return ordinal_label(layer.is_valid(), layer.value, _layer_names(), "layer")


def layer_named(name: String) raises -> Layer:
    """Return the layer that `name` names.

    Args:
        name: `under`, `mid`, `outer`, `armor` or `over`.

    Returns:
        The named layer.

    Raises:
        Error: If `name` names no layer.
    """
    var names = _layer_names()
    for k in range(len(names)):  # pragma: no branch
        if names[k] == name:
            return Layer(k)
    raise Error("A layer must be under, mid, outer, armor or over, not " + name)


def require_layer(layer: Layer) raises:
    """Refuse a layer that is not named.

    Args:
        layer: The layer.

    Raises:
        Error: If the layer is not named.
    """
    require_valid(layer.is_valid(), "A layer must be a named layer")


@fieldwise_init
struct FabricKind(Equatable, ImplicitlyCopyable, Writable):
    """What a garment is made of."""

    var value: Int
    """Its index among the named values."""

    def is_valid(self) -> Bool:
        """Return whether this is a named fabric kind.

        Returns:
            True for `LINEN` through `SCALE`.
        """
        return ordinal_valid(self.value, FABRIC_KIND_COUNT - 1)

    def is_metal(self) -> Bool:
        """Return whether this fabric is metal.

        Returns:
            True for `MAIL`, `PLATE` and `SCALE`.
        """
        return self == MAIL or self == PLATE or self == SCALE


comptime LINEN = FabricKind(0)
"""Woven flax: shirts, braies, surcoats."""
comptime WOOL = FabricKind(1)
"""Woven wool: tunics, hose, hoods, cloaks."""
comptime SILK = FabricKind(2)
"""Woven silk."""
comptime VELVET = FabricKind(3)
"""Velvet, with a pile that shines in a sheen."""
comptime LEATHER = FabricKind(4)
"""Tanned hide: boots, gloves, belts."""
comptime PADDING = FabricKind(5)
"""Quilted layers of linen round a filling: a gambeson or an arming coat."""
comptime MAIL = FabricKind(6)
"""Riveted rings of iron or steel."""
comptime PLATE = FabricKind(7)
"""Hammered metal, steel unless a garment names another."""
comptime FUR = FabricKind(8)
"""A pelt with its hair on: a mantle, a barbarian's kilt, boots' cuffs."""
comptime FELT = FabricKind(9)
"""Wool matted into a stiff cloth: hats and caps."""
comptime STRAW = FabricKind(10)
"""Plaited straw: a farmer's hat."""
comptime SCALE = FabricKind(11)
"""Small plates of metal laced in rows to a backing, each row over the
row below, as a fish's scales lie."""
comptime FABRIC_KIND_COUNT = 12
"""How many fabric kinds there are."""


def _fabric_names() -> List[String]:
    """Return the fabric kind names, in order."""
    return [
        "linen",
        "wool",
        "silk",
        "velvet",
        "leather",
        "padding",
        "mail",
        "plate",
        "fur",
        "felt",
        "straw",
        "scale",
    ]


def fabric_label(kind: FabricKind) -> String:
    """Return the name of a fabric kind.

    Args:
        kind: A fabric kind, named or not.

    Returns:
        Its name, as `"mail"`, or `"fabric"` when it is not named.
    """
    return ordinal_label(kind.is_valid(), kind.value, _fabric_names(), "fabric")


def fabric_named(name: String) raises -> FabricKind:
    """Return the fabric kind that `name` names.

    Args:
        name: `linen`, `wool`, `silk`, `velvet`, `leather`, `padding`,
            `mail`, `plate`, `fur`, `felt`, `straw` or `scale`.

    Returns:
        The named fabric kind.

    Raises:
        Error: If `name` names no fabric kind.
    """
    var names = _fabric_names()
    for k in range(len(names)):  # pragma: no branch
        if names[k] == name:
            return FabricKind(k)
    raise Error("No fabric kind is named " + name)


def require_fabric_kind(kind: FabricKind) raises:
    """Refuse a fabric kind that is not named.

    Args:
        kind: The fabric kind.

    Raises:
        Error: If the kind is not named.
    """
    require_valid(kind.is_valid(), "A fabric kind must be a named kind")


@fieldwise_init
struct DyeChannel(Equatable, ImplicitlyCopyable, Writable):
    """One of the four colors a garment takes."""

    var value: Int
    """Its index among the named values."""

    def is_valid(self) -> Bool:
        """Return whether this is a named channel.

        Returns:
            True for `PRIMARY_DYE` through `ACCENT_DYE`.
        """
        return ordinal_valid(self.value, DYE_CHANNEL_COUNT - 1)


comptime PRIMARY_DYE = DyeChannel(0)
"""The garment's main color."""
comptime SECONDARY_DYE = DyeChannel(1)
"""The second color of a pattern."""
comptime TRIM_DYE = DyeChannel(2)
"""The color along each hem."""
comptime ACCENT_DYE = DyeChannel(3)
"""A color for a caller's own use."""
comptime DYE_CHANNEL_COUNT = 4
"""How many dye channels a garment has."""


def require_dye_channel(channel: DyeChannel) raises:
    """Refuse a dye channel that is not named.

    Args:
        channel: The channel.

    Raises:
        Error: If the channel is not named.
    """
    require_valid(channel.is_valid(), "A dye channel must be a named channel")


@fieldwise_init
struct DyePattern(Equatable, ImplicitlyCopyable, Writable):
    """How the dye channels lie over a garment."""

    var value: Int
    """Its index among the named values."""

    def is_valid(self) -> Bool:
        """Return whether this is a named pattern.

        Returns:
            True for `SOLID` through `BANDED_SLEEVES`.
        """
        return ordinal_valid(self.value, DYE_PATTERN_COUNT - 1)


comptime SOLID = DyePattern(0)
"""The primary dye everywhere, with the trim dye at each hem."""
comptime PARTY = DyePattern(1)
"""Per pale: the primary dye on the right side, the secondary on the left."""
comptime STRIPES = DyePattern(2)
"""Bands of the primary and secondary dye round the body."""
comptime QUARTERLY = DyePattern(3)
"""Four quarters: primary and secondary, crossed at the waist."""
comptime CHEVRON = DyePattern(4)
"""A band in the secondary dye like an inverted V, its point on the
chest."""
comptime CROSS = DyePattern(5)
"""An upright cross in the secondary dye, crossed on the chest."""
comptime SALTIRE = DyePattern(6)
"""A diagonal cross in the secondary dye, crossed on the chest."""
comptime BEND = DyePattern(7)
"""A diagonal band in the secondary dye, from the wearer's right
shoulder down to the left hip."""
comptime PALY = DyePattern(8)
"""Upright bands of the primary and secondary dye."""
comptime CHECKY = DyePattern(9)
"""A checkerboard of the primary and secondary dye."""
comptime FRONT_PANEL = DyePattern(10)
"""A panel down the front in the secondary dye, narrow over the chest and
widening down a skirt, as a stomacher and a petticoat show."""
comptime SLEEVES = DyePattern(11)
"""The sleeves in the secondary dye, the body in the primary."""
comptime BANDED_SLEEVES = DyePattern(12)
"""Sleeves banded in the primary and secondary dye, the body in the
primary."""
comptime DYE_PATTERN_COUNT = 13
"""How many dye patterns there are."""


def _pattern_names() -> List[String]:
    """Return the pattern names, in order."""
    return [
        "solid",
        "party",
        "stripes",
        "quarterly",
        "chevron",
        "cross",
        "saltire",
        "bend",
        "paly",
        "checky",
        "front panel",
        "sleeves",
        "banded sleeves",
    ]


def pattern_label(pattern: DyePattern) -> String:
    """Return the name of a dye pattern.

    Args:
        pattern: A pattern, named or not.

    Returns:
        Its name, as `"party"`, or `"pattern"` when it is not named.
    """
    return ordinal_label(
        pattern.is_valid(), pattern.value, _pattern_names(), "pattern"
    )


def pattern_named(name: String) raises -> DyePattern:
    """Return the dye pattern that `name` names.

    Args:
        name: A pattern's name, as `pattern_label` gives it.

    Returns:
        The named pattern.

    Raises:
        Error: If `name` names no pattern.
    """
    var names = _pattern_names()
    for k in range(len(names)):  # pragma: no branch
        if names[k] == name:
            return DyePattern(k)
    raise Error("No dye pattern is named " + name)


def require_dye_pattern(pattern: DyePattern) raises:
    """Refuse a dye pattern that is not named.

    Args:
        pattern: The pattern.

    Raises:
        Error: If the pattern is not named.
    """
    require_valid(pattern.is_valid(), "A dye pattern must be a named pattern")


@fieldwise_init
struct WearKind(Equatable, ImplicitlyCopyable, Writable):
    """One channel of the marks a garment takes in use."""

    var value: Int
    """Its index among the named values."""

    def is_valid(self) -> Bool:
        """Return whether this is a named wear channel.

        Returns:
            True for `DIRT` through `DAMAGE`.
        """
        return ordinal_valid(self.value, WEAR_KIND_COUNT - 1)


comptime DIRT = WearKind(0)
"""Mud and dust."""
comptime BLOOD = WearKind(1)
"""Blood."""
comptime WET = WearKind(2)
"""Water."""
comptime DAMAGE = WearKind(3)
"""Scorching and wear."""
comptime WEAR_KIND_COUNT = 4
"""How many wear channels a garment has."""


def require_wear_kind(kind: WearKind) raises:
    """Refuse a wear channel that is not named.

    Args:
        kind: The channel.

    Raises:
        Error: If the channel is not named.
    """
    require_valid(kind.is_valid(), "A wear kind must be a named channel")


@fieldwise_init
struct Articulation(Equatable, ImplicitlyCopyable, Writable):
    """How a garment follows the bones under it."""

    var value: Int
    """Its index among the named values."""

    def is_valid(self) -> Bool:
        """Return whether this is a named articulation.

        Returns:
            True for `FLEXIBLE`, `RIGID` and `LAMED`.
        """
        return ordinal_valid(self.value, ARTICULATION_COUNT - 1)


comptime FLEXIBLE = Articulation(0)
"""It bends as the skin under it bends: cloth, leather and mail."""
comptime RIGID = Articulation(1)
"""Each vertex rides one bone wholly, as a plate does."""
comptime LAMED = Articulation(2)
"""Bands of plate, each riding a bone more than the band above it: the lames
of a fauld, a tasset or a pauldron."""
comptime ARTICULATION_COUNT = 3
"""How many articulations there are."""


def _articulation_names() -> List[String]:
    """Return the articulation names, in order."""
    return ["flexible", "rigid", "lamed"]


def articulation_label(articulation: Articulation) -> String:
    """Return the name of an articulation.

    Args:
        articulation: An articulation, named or not.

    Returns:
        Its name, as `"lamed"`, or `"articulation"` when it is not named.
    """
    return ordinal_label(
        articulation.is_valid(),
        articulation.value,
        _articulation_names(),
        "articulation",
    )


def articulation_named(name: String) raises -> Articulation:
    """Return the articulation that `name` names.

    Args:
        name: `flexible`, `rigid` or `lamed`.

    Returns:
        The named articulation.

    Raises:
        Error: If `name` names no articulation.
    """
    var names = _articulation_names()
    for k in range(len(names)):  # pragma: no branch
        if names[k] == name:
            return Articulation(k)
    raise Error("No articulation is named " + name)


def require_articulation(articulation: Articulation) raises:
    """Refuse an articulation that is not named.

    Args:
        articulation: The articulation.

    Raises:
        Error: If the articulation is not named.
    """
    require_valid(
        articulation.is_valid(), "An articulation must be a named one"
    )


@fieldwise_init
struct Form(Equatable, ImplicitlyCopyable, Writable):
    """How a garment's shell is shaped where it does not follow the skin."""

    var value: Int
    """Its index among the named values."""

    def is_valid(self) -> Bool:
        """Return whether this is a named form.

        Returns:
            True for `FITTED`, `SKIRTED`, `SHOD`, `COWLED`, `BANDED`,
            `HATTED` and `DOMED`.
        """
        return ordinal_valid(self.value, FORM_COUNT - 1)


comptime FITTED = Form(0)
"""It follows the skin everywhere: a shirt, hose, a coif."""
comptime SKIRTED = Form(1)
"""Below the hips it hangs as one skirt round both legs: a tunic, a
hauberk, a surcoat, a fauld."""
comptime SHOD = Form(2)
"""It closes each foot in a smooth last, over the toes and the arch: a
boot or a shoe."""
comptime COWLED = Form(3)
"""Above the neck it closes round the head in one loose cowl, open at the
face: a hood."""
comptime BANDED = Form(4)
"""It is drawn as a taut band round the body where its cover lies, level
at its top and its bottom: a belt."""
comptime HATTED = Form(5)
"""It is drawn as a hat or a helmet shaped round the head, which its
headwear kind names: a great helm, a crown, a wizard's hat."""
comptime DOMED = Form(6)
"""It closes each shoulder in one smooth dome, standing well off it: great
pauldrons."""
comptime FORM_COUNT = 7
"""How many forms there are."""


def _form_names() -> List[String]:
    """Return the form names, in order."""
    return [
        "fitted",
        "skirted",
        "shod",
        "cowled",
        "banded",
        "hatted",
        "domed",
    ]


def form_label(form: Form) -> String:
    """Return the name of a form.

    Args:
        form: A form, named or not.

    Returns:
        Its name, as `"skirted"`, or `"form"` when it is not named.
    """
    return ordinal_label(form.is_valid(), form.value, _form_names(), "form")


def form_named(name: String) raises -> Form:
    """Return the form that `name` names.

    Args:
        name: `fitted`, `skirted`, `shod`, `cowled`, `banded`, `hatted`
            or `domed`.

    Returns:
        The named form.

    Raises:
        Error: If `name` names no form.
    """
    var names = _form_names()
    for k in range(len(names)):  # pragma: no branch
        if names[k] == name:
            return Form(k)
    raise Error("No form is named " + name)


def require_form(form: Form) raises:
    """Refuse a form that is not named.

    Args:
        form: The form.

    Raises:
        Error: If the form is not named.
    """
    require_valid(form.is_valid(), "A form must be a named one")


@fieldwise_init
struct Bump(Equatable, ImplicitlyCopyable, Writable):
    """Which bump map a fabric's surface takes."""

    var value: Int
    """Its index among the named values."""

    def is_valid(self) -> Bool:
        """Return whether this is a named bump map.

        Returns:
            True for `NO_BUMP` through `SCALES`.
        """
        return ordinal_valid(self.value, BUMP_COUNT - 1)


comptime NO_BUMP = Bump(0)
"""A smooth surface: plate and felt."""
comptime MAIL_RINGS = Bump(1)
"""The riveted rings of mail."""
comptime QUILTING = Bump(2)
"""The diamond quilting of a gambeson."""
comptime TWILL = Bump(3)
"""The two-over-two twill of woven cloth."""
comptime FUR_LOCKS = Bump(4)
"""The locks of a pelt's hair."""
comptime PLAIT = Bump(5)
"""Flat straws plaited over and under each other."""
comptime GRAIN = Bump(6)
"""The pebbled grain of tanned leather."""
comptime SCALES = Bump(7)
"""Rows of rounded scales, each row over the row below."""
comptime BUMP_COUNT = 8
"""How many bump maps there are, the smooth one with them."""


def require_bump(bump: Bump) raises:
    """Refuse a bump map that is not named.

    Args:
        bump: The bump map.

    Raises:
        Error: If the bump map is not named.
    """
    require_valid(bump.is_valid(), "A bump map must be a named one")


def slot_named(name: String) raises -> Slot:
    """Return the slot that `name` names.

    Args:
        name: `head`, `neck`, `shoulders`, `torso`, `arms`, `hands`,
            `waist`, `legs`, `feet` or `back`.

    Returns:
        The named slot.

    Raises:
        Error: If `name` names no slot.
    """
    var names = _slot_names()
    for k in range(len(names)):  # pragma: no branch
        if names[k] == name:
            return Slot(k)
    raise Error("No slot is named " + name)


@fieldwise_init
struct Headwear(Equatable, ImplicitlyCopyable, Writable):
    """Which hat or helmet a `HATTED` garment is drawn as."""

    var value: Int
    """Its index among the named values."""

    def is_valid(self) -> Bool:
        """Return whether this is a named headwear kind.

        Returns:
            True for `NO_HEADWEAR` through `CIRCLET`.
        """
        return ordinal_valid(self.value, HEADWEAR_COUNT - 1)

    def keeps_hair(self) -> Bool:
        """Return whether the hair shows under it.

        Returns:
            False for a great helm, which closes the head; True for the
            rest, which leave the hair below their brim or band.
        """
        return self != GREAT_HELM

    def is_open(self) -> Bool:
        """Return whether the hair shows over its top.

        Returns:
            True for a crown and a circlet, which are bands; False for
            the rest, which close over the head.
        """
        return self == CROWN or self == CIRCLET


comptime NO_HEADWEAR = Headwear(0)
"""Not a hat: the garment is shaped by its form."""
comptime GREAT_HELM = Headwear(1)
"""A closed helmet over the whole head, with a slit for the eyes."""
comptime HALF_HELM = Headwear(2)
"""An open helmet over the crown, with a bar down the nose."""
comptime HORNED_HELM = Headwear(3)
"""An open helmet with a horn on each side."""
comptime WIZARD_HAT = Headwear(4)
"""A tall pointed hat with a wide brim, its tip bent back."""
comptime STRAW_HAT = Headwear(5)
"""A low round hat with a wide brim."""
comptime FEATHERED_CAP = Headwear(6)
"""A peaked cap, its brim turned up behind, with a feather."""
comptime CROWN = Headwear(7)
"""A band of metal with points, set with stones."""
comptime CIRCLET = Headwear(8)
"""A thin band of metal round the brow, with one stone."""
comptime HEADWEAR_COUNT = 9
"""How many headwear kinds there are, no headwear with them."""


def _headwear_names() -> List[String]:
    """Return the headwear names, in order."""
    return [
        "none",
        "great helm",
        "half helm",
        "horned helm",
        "wizard hat",
        "straw hat",
        "feathered cap",
        "crown",
        "circlet",
    ]


def headwear_label(headwear: Headwear) -> String:
    """Return the name of a headwear kind.

    Args:
        headwear: A headwear kind, named or not.

    Returns:
        Its name, as `"crown"`, or `"headwear"` when it is not named.
    """
    return ordinal_label(
        headwear.is_valid(), headwear.value, _headwear_names(), "headwear"
    )


def headwear_named(name: String) raises -> Headwear:
    """Return the headwear kind that `name` names.

    Args:
        name: A headwear kind's name, as `headwear_label` gives it.

    Returns:
        The named headwear kind.

    Raises:
        Error: If `name` names no headwear kind.
    """
    var names = _headwear_names()
    for k in range(len(names)):  # pragma: no branch
        if names[k] == name:
            return Headwear(k)
    raise Error("No headwear is named " + name)


def require_headwear(headwear: Headwear) raises:
    """Refuse a headwear kind that is not named.

    Args:
        headwear: The headwear kind.

    Raises:
        Error: If the kind is not named.
    """
    require_valid(headwear.is_valid(), "A headwear kind must be a named one")


@fieldwise_init
struct Neckline(Equatable, ImplicitlyCopyable, Writable):
    """How a garment is cut at the front of the neck."""

    var value: Int
    """Its index among the named values."""

    def is_valid(self) -> Bool:
        """Return whether this is a named neckline.

        Returns:
            True for `ROUND_NECK` through `SLIT_NECK`.
        """
        return ordinal_valid(self.value, NECKLINE_COUNT - 1)


comptime ROUND_NECK = Neckline(0)
"""Round the base of the neck, as the cover cuts it."""
comptime V_NECK = Neckline(1)
"""A V down the front, to the top of the chest."""
comptime SQUARE_NECK = Neckline(2)
"""Square across the top of the chest, as a gown's is."""
comptime SCOOP_NECK = Neckline(3)
"""A wide, low curve across the chest, as a chemise's is."""
comptime SLIT_NECK = Neckline(4)
"""A narrow slit down the front from the neck, as a laced shirt's is."""
comptime NECKLINE_COUNT = 5
"""How many necklines there are."""


def _neckline_names() -> List[String]:
    """Return the neckline names, in order."""
    return ["round", "v", "square", "scoop", "slit"]


def neckline_label(neckline: Neckline) -> String:
    """Return the name of a neckline.

    Args:
        neckline: A neckline, named or not.

    Returns:
        Its name, as `"square"`, or `"neckline"` when it is not named.
    """
    return ordinal_label(
        neckline.is_valid(), neckline.value, _neckline_names(), "neckline"
    )


def neckline_named(name: String) raises -> Neckline:
    """Return the neckline that `name` names.

    Args:
        name: A neckline's name, as `neckline_label` gives it.

    Returns:
        The named neckline.

    Raises:
        Error: If `name` names no neckline.
    """
    var names = _neckline_names()
    for k in range(len(names)):  # pragma: no branch
        if names[k] == name:
            return Neckline(k)
    raise Error("No neckline is named " + name)


def require_neckline(neckline: Neckline) raises:
    """Refuse a neckline that is not named.

    Args:
        neckline: The neckline.

    Raises:
        Error: If the neckline is not named.
    """
    require_valid(neckline.is_valid(), "A neckline must be a named one")


@fieldwise_init
struct Opening(Equatable, ImplicitlyCopyable, Writable):
    """Where a garment is open, so the garment under it shows."""

    var value: Int
    """Its index among the named values."""

    def is_valid(self) -> Bool:
        """Return whether this is a named opening.

        Returns:
            True for `CLOSED` through `FRONT_ONLY`.
        """
        return ordinal_valid(self.value, OPENING_COUNT - 1)


comptime CLOSED = Opening(0)
"""Closed all round."""
comptime OPEN_FRONT = Opening(1)
"""Open down the front from the neck to the hem, as an open robe is."""
comptime OPEN_BELOW = Opening(2)
"""Closed to the waist and open below it, its skirts parted, as a frock
coat's are."""
comptime FRONT_ONLY = Opening(3)
"""The front alone, as an apron or a tabard's front is."""
comptime OPENING_COUNT = 4
"""How many openings there are."""


def _opening_names() -> List[String]:
    """Return the opening names, in order."""
    return ["closed", "open front", "open below", "front only"]


def opening_label(opening: Opening) -> String:
    """Return the name of an opening.

    Args:
        opening: An opening, named or not.

    Returns:
        Its name, as `"open below"`, or `"opening"` when it is not named.
    """
    return ordinal_label(
        opening.is_valid(), opening.value, _opening_names(), "opening"
    )


def opening_named(name: String) raises -> Opening:
    """Return the opening that `name` names.

    Args:
        name: An opening's name, as `opening_label` gives it.

    Returns:
        The named opening.

    Raises:
        Error: If `name` names no opening.
    """
    var names = _opening_names()
    for k in range(len(names)):  # pragma: no branch
        if names[k] == name:
            return Opening(k)
    raise Error("No opening is named " + name)


def require_opening(opening: Opening) raises:
    """Refuse an opening that is not named.

    Args:
        opening: The opening.

    Raises:
        Error: If the opening is not named.
    """
    require_valid(opening.is_valid(), "An opening must be a named one")


@fieldwise_init
struct Sleeve(Equatable, ImplicitlyCopyable, Writable):
    """How full a garment's sleeves are."""

    var value: Int
    """Its index among the named values."""

    def is_valid(self) -> Bool:
        """Return whether this is a named sleeve.

        Returns:
            True for `FITTED_SLEEVE` through `PUFFED_SHOULDER`.
        """
        return ordinal_valid(self.value, SLEEVE_COUNT - 1)


comptime FITTED_SLEEVE = Sleeve(0)
"""As the arm is, at the garment's ease."""
comptime BISHOP_SLEEVE = Sleeve(1)
"""Full round the forearm and gathered at the cuff, as a chemise's and a
peasant shirt's are."""
comptime PUFFED_SHOULDER = Sleeve(2)
"""Puffed round the top of the arm, as a gown's and a doublet's are."""
comptime SLEEVE_COUNT = 3
"""How many sleeves there are."""


def _sleeve_names() -> List[String]:
    """Return the sleeve names, in order."""
    return ["fitted", "bishop", "puffed shoulder"]


def sleeve_label(sleeve: Sleeve) -> String:
    """Return the name of a sleeve.

    Args:
        sleeve: A sleeve, named or not.

    Returns:
        Its name, as `"bishop"`, or `"sleeve"` when it is not named.
    """
    return ordinal_label(
        sleeve.is_valid(), sleeve.value, _sleeve_names(), "sleeve"
    )


def sleeve_named(name: String) raises -> Sleeve:
    """Return the sleeve that `name` names.

    Args:
        name: A sleeve's name, as `sleeve_label` gives it.

    Returns:
        The named sleeve.

    Raises:
        Error: If `name` names no sleeve.
    """
    var names = _sleeve_names()
    for k in range(len(names)):  # pragma: no branch
        if names[k] == name:
            return Sleeve(k)
    raise Error("No sleeve is named " + name)


def require_sleeve(sleeve: Sleeve) raises:
    """Refuse a sleeve that is not named.

    Args:
        sleeve: The sleeve.

    Raises:
        Error: If the sleeve is not named.
    """
    require_valid(sleeve.is_valid(), "A sleeve must be a named one")


@fieldwise_init
struct Design(Equatable, ImplicitlyCopyable, Writable):
    """A design woven or embroidered over a garment's dyes."""

    var value: Int
    """Its index among the named values."""

    def is_valid(self) -> Bool:
        """Return whether this is a named design.

        Returns:
            True for `PLAIN` through `HIDE`.
        """
        return ordinal_valid(self.value, DESIGN_COUNT - 1)

    def is_tonal(self) -> Bool:
        """Return whether the design is in the dye's own tones alone.

        Returns:
            True for damask, herringbone and hide, which lighten and
            darken whatever dye lies under them; False for the rest.
        """
        return self == DAMASK or self == HERRINGBONE or self == HIDE

    def is_colored(self) -> Bool:
        """Return whether the design lays dyes of its own over the cloth.

        Returns:
            True for brocade, tartan, pinstripe, diaper, floral and
            check; False for plain and the tonal designs.
        """
        return self.is_valid() and self != PLAIN and not self.is_tonal()

    def braids_trim(self) -> Bool:
        """Return whether the design's garment wears a braid on its trim.

        Returns:
            True for damask, brocade, diaper and floral, the designs of
            fine cloth; False for the rest.
        """
        return (
            self == DAMASK
            or self == BROCADE
            or self == DIAPER
            or self == FLORAL
        )


comptime PLAIN = Design(0)
"""No design: the dyes alone."""
comptime DAMASK = Design(1)
"""Medallions in an ogee lattice, woven a shade lighter than the dye."""
comptime BROCADE = Design(2)
"""Medallions in an ogee lattice, woven in the trim's dye over the dye."""
comptime TARTAN = Design(3)
"""Bands of the dye, the secondary and the trim crossing in a twill."""
comptime PINSTRIPE = Design(4)
"""Thin stripes of the trim's dye down the cloth."""
comptime DIAPER = Design(5)
"""A lattice of diamonds in the trim's dye, a dot in each."""
comptime FLORAL = Design(6)
"""Small flowers of the trim's dye strewn over the cloth."""
comptime CHECK = Design(7)
"""Small checks of the dye, the trim's dye, and a blend where they
cross."""
comptime HERRINGBONE = Design(8)
"""A zigzag twill, a shade lighter and darker than the dye."""
comptime HIDE = Design(9)
"""The mottle and creases of tanned hide, a shade either side of the
dye."""
comptime DESIGN_COUNT = 10
"""How many designs there are."""


def _design_names() -> List[String]:
    """Return the design names, in order."""
    return [
        "plain",
        "damask",
        "brocade",
        "tartan",
        "pinstripe",
        "diaper",
        "floral",
        "check",
        "herringbone",
        "hide",
    ]


def design_label(design: Design) -> String:
    """Return the name of a design.

    Args:
        design: A design, named or not.

    Returns:
        Its name, as `"brocade"`, or `"design"` when it is not named.
    """
    return ordinal_label(
        design.is_valid(), design.value, _design_names(), "design"
    )


def design_named(name: String) raises -> Design:
    """Return the design that `name` names.

    Args:
        name: A design's name, as `design_label` gives it.

    Returns:
        The named design.

    Raises:
        Error: If `name` names no design.
    """
    var names = _design_names()
    for k in range(len(names)):  # pragma: no branch
        if names[k] == name:
            return Design(k)
    raise Error("No design is named " + name)


def require_design(design: Design) raises:
    """Refuse a design that is not named.

    Args:
        design: The design.

    Raises:
        Error: If the design is not named.
    """
    require_valid(design.is_valid(), "A design must be a named one")


@fieldwise_init
struct Ruffles(Equatable, ImplicitlyCopyable, Writable):
    """Where a garment wears a frill: at its cuffs, its collar or its hem,
    or a union of them."""

    var value: Int
    """One bit for each place: one the cuffs, two the collar, four the
    hem."""

    def is_valid(self) -> Bool:
        """Return whether this is a union of the named places.

        Returns:
            True for zero through seven.
        """
        return ordinal_valid(self.value, RUFFLES_COUNT - 1)

    def __or__(self, other: Self) -> Self:
        """Return the union of two sets of places.

        Args:
            other: Another set.

        Returns:
            The places either names.
        """
        return Self(self.value | other.value)

    def has(self, place: Self) -> Bool:
        """Return whether every place of `place` is one of these.

        Args:
            place: A place, or a union of them.

        Returns:
            True when this set holds all of them.
        """
        return place.value != 0 and (self.value & place.value) == place.value


comptime NO_RUFFLES = Ruffles(0)
"""No frill."""
comptime CUFF_RUFFLES = Ruffles(1)
"""A frill at the end of each sleeve, falling over the hand."""
comptime COLLAR_RUFFLE = Ruffles(2)
"""A frill round the neckline, standing up and out."""
comptime HEM_RUFFLE = Ruffles(4)
"""A flounce along the hem, below it."""
comptime RUFFLES_COUNT = 8
"""How many sets of places there are."""


def _ruffles_names() -> List[String]:
    """Return the names of the sets of places, in order."""
    var places: List[String] = ["cuffs", "collar", "hem"]
    var names: List[String] = ["none"]
    for value in range(1, RUFFLES_COUNT):  # pragma: no branch
        var name = String()
        for bit in range(3):
            if value & (1 << bit):
                if name:
                    name += "+"
                name += places[bit]
        names.append(name)
    return names^


def ruffles_label(ruffles: Ruffles) -> String:
    """Return the name of a set of places.

    Args:
        ruffles: A set, named or not.

    Returns:
        Its name, as `"cuffs+collar"`, or `"ruffles"` when it is not
        named.
    """
    return ordinal_label(
        ruffles.is_valid(), ruffles.value, _ruffles_names(), "ruffles"
    )


def ruffles_named(name: String) raises -> Ruffles:
    """Return the set of places that `name` names.

    Args:
        name: A name, as `ruffles_label` gives it.

    Returns:
        The named set.

    Raises:
        Error: If `name` names no set.
    """
    var names = _ruffles_names()
    for k in range(len(names)):  # pragma: no branch
        if names[k] == name:
            return Ruffles(k)
    raise Error("No ruffles are named " + name)


def require_ruffles(ruffles: Ruffles) raises:
    """Refuse a set of places that is not named.

    Args:
        ruffles: The set.

    Raises:
        Error: If the set is not named.
    """
    require_valid(ruffles.is_valid(), "Ruffles must be a named set")
