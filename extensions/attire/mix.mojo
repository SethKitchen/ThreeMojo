# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""A crowd's clothes: an outfit for each person, picked by a seed.

A crowd in one outfit looks like a uniform. `mixed_outfit` gives each
seed an outfit of its own, in three choices:

1. A calling, which says what a person wears: a peasant, a goodwife, an
   archer, a monk, a merchant, a noblewoman, a man-at-arms or a knight.
   Common callings come up more often than rare ones.
2. The dyes of each garment, from the calling's palette. The poor wear
   undyed wool and the dyes of common plants. The rich wear kermes
   crimson, deep woad and saffron. Armor is bright steel or blackened.
3. Small choices: a hood or a bare head, a belt or none.

`calling_outfit` gives the outfit of one calling for a seed. The same
seed gives the same outfit, on every machine.

| Calling | Garments |
|---|---|
| `PEASANT` | shirt, breeches over hose, tunic, boots; a hood and a belt by chance |
| `GOODWIFE` | shirt, gown, boots, a belt; a hood by chance |
| `ARCHER` | shirt, hose, gambeson, jerkin, belt, boots; a hood by chance |
| `MONK` | shirt, robe, hood, belt, boots |
| `MERCHANT` | shirt, hose, tunic, belt, boots; a hood by chance |
| `NOBLEWOMAN` | shirt, gown, belt, boots |
| `MAN_AT_ARMS` | `outfit_named("man-at-arms")`, a belt, and a surcoat by chance |
| `KNIGHT` | `outfit_named("knight")` and a belt, its surcoat in two rich dyes |

This is not a three.js port. See Extensions.

    var outfit = mixed_outfit(person_index)
    var dressed = dress(scene, assets, person, outfit)
"""

from core.ordinal import ordinal_label, ordinal_valid, require_valid
from extensions.attire.garment import (
    Garment,
    belt,
    boots,
    breeches,
    gambeson,
    gown,
    hood,
    hose,
    jerkin,
    robe,
    shirt,
    surcoat,
    tunic,
)
from extensions.attire.kinds import (
    PLATE,
    PRIMARY_DYE,
    SECONDARY_DYE,
    TRIM_DYE,
)
from extensions.attire.outfit import Outfit
from extensions.attire.preset import outfit_named
from render.framebuffer import Color

comptime PLAIN_DYES = 9
"""How many dyes `plain_dye` gives."""
comptime RICH_DYES = 6
"""How many dyes `rich_dye` gives."""


@fieldwise_init
struct Calling(Equatable, ImplicitlyCopyable, Writable):
    """What a person does, which says what they wear."""

    var value: Int
    """Its index among the named values."""

    def is_valid(self) -> Bool:
        """Return whether this is a named calling.

        Returns:
            True for `PEASANT` through `KNIGHT`.
        """
        return ordinal_valid(self.value, CALLING_COUNT - 1)


comptime PEASANT = Calling(0)
"""A man who works the land."""
comptime GOODWIFE = Calling(1)
"""A woman who keeps a house."""
comptime ARCHER = Calling(2)
"""A bowman in a padded coat and a leather jerkin."""
comptime MONK = Calling(3)
"""A monk in a robe and a hood."""
comptime MERCHANT = Calling(4)
"""A townsman in good wool."""
comptime NOBLEWOMAN = Calling(5)
"""A lady in a gown of rich dye."""
comptime MAN_AT_ARMS = Calling(6)
"""A soldier in mail."""
comptime KNIGHT = Calling(7)
"""A knight in a full harness of plate."""
comptime CALLING_COUNT = 8
"""How many callings there are."""


def _calling_names() -> List[String]:
    """Return the calling names, in order."""
    return [
        "peasant",
        "goodwife",
        "archer",
        "monk",
        "merchant",
        "noblewoman",
        "man-at-arms",
        "knight",
    ]


def calling_label(calling: Calling) -> String:
    """Return the name of a calling.

    Args:
        calling: A calling, named or not.

    Returns:
        Its name, as `"archer"`, or `"calling"` when it is not named.
    """
    return ordinal_label(
        calling.is_valid(), calling.value, _calling_names(), "calling"
    )


def calling_named(name: String) raises -> Calling:
    """Return the calling that `name` names.

    Args:
        name: A calling's name, as `calling_label` gives it.

    Returns:
        The named calling.

    Raises:
        Error: If `name` names no calling.
    """
    var names = _calling_names()
    for k in range(len(names)):  # pragma: no branch
        if names[k] == name:
            return Calling(k)
    raise Error("No calling is named " + name)


def require_calling(calling: Calling) raises:
    """Refuse a calling that is not named.

    Args:
        calling: The calling.

    Raises:
        Error: If the calling is not named.
    """
    require_valid(calling.is_valid(), "A calling must be a named one")


def plain_dye(index: Int) -> Color:
    """Return one of the dyes the poor wear.

    Args:
        index: Which dye. Any integer: it is taken modulo `PLAIN_DYES`.

    Returns:
        Madder red, woad blue, weld yellow, walnut brown, nettle green,
        gray wool, cream wool, russet or lichen purple.
    """
    var colors: List[Color] = [
        Color(150, 42, 34),
        Color(42, 72, 124),
        Color(196, 164, 64),
        Color(92, 62, 40),
        Color(70, 96, 52),
        Color(118, 114, 106),
        Color(214, 202, 176),
        Color(124, 62, 36),
        Color(92, 64, 92),
    ]
    return colors[index % PLAIN_DYES]


def rich_dye(index: Int) -> Color:
    """Return one of the dyes the rich wear.

    Args:
        index: Which dye. Any integer: it is taken modulo `RICH_DYES`.

    Returns:
        Kermes crimson, deep woad, verdigris green, saffron gold, black
        or murex violet.
    """
    var colors: List[Color] = [
        Color(156, 18, 38),
        Color(26, 40, 104),
        Color(28, 98, 82),
        Color(216, 162, 40),
        Color(30, 28, 32),
        Color(86, 30, 94),
    ]
    return colors[index % RICH_DYES]


def _mixed(seed: Int, salt: Int) -> Int:
    """Return a well-mixed non-negative integer from a seed and a salt.

    SplitMix64's finalizer, on the unsigned bits of both.
    """
    var x = (
        UInt64(seed) * 0x9E3779B97F4A7C15 + UInt64(salt) * 0xBF58476D1CE4E5B9
    )
    x = (x ^ (x >> 30)) * 0xBF58476D1CE4E5B9
    x = (x ^ (x >> 27)) * 0x94D049BB133111EB
    x = x ^ (x >> 31)
    return Int(x >> 1)


def _chance(seed: Int, salt: Int, percent: Int) -> Bool:
    """Return True for about `percent` in a hundred seeds."""
    return _mixed(seed, salt) % 100 < percent


def _dyed(var garment: Garment, primary: Color, trim: Color) -> Garment:
    """Return a garment dyed one color, its trim another."""
    for k in range(len(garment.dyes)):  # pragma: no branch
        garment.dyes[k] = primary
    garment.dyes[TRIM_DYE.value] = trim
    return garment^


def calling_outfit(calling: Calling, seed: Int) raises -> Outfit:
    """Return the outfit of a calling, dyed and chosen by a seed.

    Args:
        calling: A named calling.
        seed: Which dyes and which small choices. Any integer.

    Returns:
        The outfit.

    Raises:
        Error: If the calling is not named.
    """
    require_calling(calling)
    var plain = _mixed(seed, 1)
    var rich = _mixed(seed, 2)
    var outfit = Outfit()
    if calling == MAN_AT_ARMS or calling == KNIGHT:
        var name = String("knight")
        if calling == MAN_AT_ARMS:
            name = "man-at-arms"
        var base = outfit_named(name)
        # Bright steel, or blackened against rust.
        var steel = Color(198, 200, 206)
        if _chance(seed, 3, 30):
            steel = Color(70, 72, 80)
        for garment in base.garments:  # pragma: no branch
            var made = garment.copy()
            if made.fabric == PLATE:
                made = _dyed(made^, steel, steel)
            elif made.name == "surcoat":
                made.dyes[PRIMARY_DYE.value] = rich_dye(rich)
                made.dyes[SECONDARY_DYE.value] = rich_dye(rich + 3)
                made.dyes[TRIM_DYE.value] = rich_dye(rich + 3)
            elif made.name == "hose":
                made = _dyed(made^, plain_dye(plain), plain_dye(plain))
            outfit.add(made^)
        if calling == MAN_AT_ARMS and _chance(seed, 4, 50):
            var coat = surcoat()
            coat.dyes[PRIMARY_DYE.value] = plain_dye(plain + 1)
            coat.dyes[SECONDARY_DYE.value] = plain_dye(plain + 2)
            coat.dyes[TRIM_DYE.value] = plain_dye(plain + 2)
            outfit.add(coat^)
        outfit.add(belt())
        return outfit^
    outfit.add(shirt())
    if calling == MONK:
        outfit.add(_dyed(robe(), plain_dye(3 + plain % 3 * 2), plain_dye(3)))
        outfit.add(_dyed(hood(), plain_dye(3 + plain % 3 * 2), plain_dye(3)))
        outfit.add(belt())
        outfit.add(boots())
        return outfit^
    if calling == GOODWIFE or calling == NOBLEWOMAN:
        var dye = plain_dye(plain)
        var trim = plain_dye(plain + 6)
        if calling == NOBLEWOMAN:
            dye = rich_dye(rich)
            trim = rich_dye(rich + 3)
        outfit.add(_dyed(gown(), dye, trim))
        if calling == GOODWIFE and _chance(seed, 5, 50):
            outfit.add(_dyed(hood(), plain_dye(plain + 5), plain_dye(plain)))
    else:
        outfit.add(_dyed(hose(), plain_dye(plain + 3), plain_dye(plain + 3)))
        if calling == ARCHER:
            outfit.add(gambeson())
            outfit.add(_dyed(jerkin(), plain_dye(3), plain_dye(7)))
        else:
            if calling == PEASANT:
                outfit.add(
                    _dyed(breeches(), plain_dye(plain + 4), plain_dye(plain))
                )
            var trim = plain_dye(plain + 1)
            if calling == MERCHANT:
                trim = rich_dye(rich)
            outfit.add(_dyed(tunic(), plain_dye(plain), trim))
        if _chance(seed, 5, 40):
            outfit.add(_dyed(hood(), plain_dye(plain + 2), plain_dye(plain)))
    if calling != PEASANT or _chance(seed, 6, 60):
        outfit.add(belt())
    outfit.add(boots())
    return outfit^


def mixed_calling(seed: Int) -> Calling:
    """Return the calling a seed picks.

    Of each twenty seeds, about five are peasants, four goodwives, three
    archers, two monks, two merchants, one a noblewoman, two men-at-arms
    and one a knight.

    Args:
        seed: Any integer.

    Returns:
        A named calling.
    """
    var roll = _mixed(seed, 0) % 20
    var shares: List[Int] = [5, 4, 3, 2, 2, 1, 2, 1]
    var calling = 0
    for k in range(CALLING_COUNT):  # pragma: no branch
        if roll < shares[k]:
            calling = k
            break
        roll -= shares[k]
    return Calling(calling)


def mixed_outfit(seed: Int) raises -> Outfit:
    """Return an outfit for one person of a crowd.

    Args:
        seed: Which person. Any integer.

    Returns:
        The outfit of `mixed_calling(seed)`, dyed by the seed.

    Raises:
        Error: Never: every calling is named.
    """
    return calling_outfit(mixed_calling(seed), seed)
