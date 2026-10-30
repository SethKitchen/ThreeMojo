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
cowl round the head, or a taut band round the body.

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
            True for `LINEN` through `PLATE`.
        """
        return ordinal_valid(self.value, FABRIC_KIND_COUNT - 1)

    def is_metal(self) -> Bool:
        """Return whether this fabric is metal.

        Returns:
            True for `MAIL` and `PLATE`.
        """
        return self == MAIL or self == PLATE


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
"""Hammered steel."""
comptime FABRIC_KIND_COUNT = 8
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
            `mail` or `plate`.

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
            True for `SOLID` through `QUARTERLY`.
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
comptime DYE_PATTERN_COUNT = 4
"""How many dye patterns there are."""


def _pattern_names() -> List[String]:
    """Return the pattern names, in order."""
    return ["solid", "party", "stripes", "quarterly"]


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
        name: `solid`, `party`, `stripes` or `quarterly`.

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
            True for `FITTED`, `SKIRTED`, `SHOD`, `COWLED` and `BANDED`.
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
comptime FORM_COUNT = 5
"""How many forms there are."""


def _form_names() -> List[String]:
    """Return the form names, in order."""
    return ["fitted", "skirted", "shod", "cowled", "banded"]


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
        name: `fitted`, `skirted`, `shod`, `cowled` or `banded`.

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
            True for `NO_BUMP`, `MAIL_RINGS`, `QUILTING` and `TWILL`.
        """
        return ordinal_valid(self.value, BUMP_COUNT - 1)


comptime NO_BUMP = Bump(0)
"""A smooth surface: leather and plate."""
comptime MAIL_RINGS = Bump(1)
"""The riveted rings of mail."""
comptime QUILTING = Bump(2)
"""The diamond quilting of a gambeson."""
comptime TWILL = Bump(3)
"""The two-over-two twill of woven cloth."""
comptime BUMP_COUNT = 4
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
