# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""A crowd's clothes: an outfit for each person, picked by a seed.

A crowd in one outfit looks like a uniform. `mixed_outfit` gives each
seed an outfit of its own, in three choices:

1. A calling, which says what a person wears: a peasant, a goodwife, an
   archer, a monk, a merchant, a noblewoman, a man-at-arms, a knight, a
   farmer, a barbarian, a royal, a wizard, a warlock, a ranger or a
   warrior in plate. Common callings come up more often than rare ones.
2. The dyes of each garment, from the calling's palette. The poor wear
   undyed wool and the dyes of common plants. The rich wear kermes
   crimson, deep woad and saffron. Armor is bright steel or blackened.
3. Small choices: a hood or a bare head, a belt or none, and a garment
   parti-colored or quartered: a merchant's tunic, a woman's gown, a
   company's surcoat.

`calling_outfit` gives the outfit of one calling for a seed, and
`dressed_as` for a person of either sex. `calling_hair` and
`calling_beard` pick the hairstyle and the beard that suit the calling,
and `calling_cloak` a cloak or none; see `extensions.attire.drape` to
hang it over the outfit. The first eight callings dress
as their calling's sex; the last seven have clothes for each. The same
seed gives the same outfit, on every machine.

| Calling | Garments |
|---|---|
| `PEASANT` | shirt, breeches over hose, tunic, boots; a hood and a belt by chance |
| `GOODWIFE` | shirt, gown, boots, a belt; a hood by chance |
| `ARCHER` | shirt, hose, gambeson, jerkin, belt, boots; a hood by chance |
| `MONK` | shirt, robe, hood, belt, boots |
| `MERCHANT` | shirt, hose, tunic, belt, boots; a hood by chance |
| `NOBLEWOMAN` | shirt, gown, belt, boots |
| `MAN_AT_ARMS` | `outfit_named("man-at-arms")`, a belt, and a surcoat by chance, quartered or bearing a cross or a saltire by chance |
| `KNIGHT` | `outfit_named("knight")` and a belt, its surcoat in two rich dyes, bearing arms by `heraldry` |
| `FARMER` | a shirt; a smock or a tunic over trousers, or a gown and a bodice; a straw hat by chance; boots |
| `BARBARIAN` | a fur kilt, fur boots, bracers and a belt; a fur mantle, a horned or half helm, or a shirt of scales by chance; a woman wears a jerkin or scales |
| `ROYAL` | a velvet robe or gown in a rich dye, a royal mantle edged in white fur, a sash, boots; a crown, or a circlet for some queens |
| `WIZARD` | a wizard's robe and hat in an arcane dye, trimmed in gold or silver, a sash, boots |
| `WARLOCK` | a black cassock trimmed in red; a hood or a dark mantle by chance; tall boots |
| `RANGER` | hose, a tunic in forest green, a jerkin by chance, bracers, tall boots, a belt, and a hood or a feathered cap |
| `WARRIOR` | a full harness of plate forged of one metal, gilt or brassed by chance: a platebody, or a shirt of scales by chance, plate legs, arm harness, pauldrons, gauntlets, sabatons, a plate skirt or a fauld under a platebody, and a helm |

This is not a three.js port. See Extensions.

    var outfit = mixed_outfit(person_index)
    var dressed = dress(scene, assets, person, outfit)
"""

from core.ordinal import ordinal_label, ordinal_valid, require_valid
from extensions.attire.apparel import (
    bodice,
    cassock,
    circlet,
    crown,
    feathered_cap,
    fur_boots,
    fur_kilt,
    fur_mantle,
    royal_mantle,
    sash,
    smock,
    straw_hat,
    tall_boots,
    trousers,
    wizard_hat,
    wizard_robe,
)
from extensions.attire.cloth import CloakCut
from extensions.attire.armory import (
    arm_harness,
    bracers,
    great_helm,
    great_pauldrons,
    half_helm,
    horned_helm,
    plate_legs,
    plate_skirt,
    platebody,
    scale_shirt,
)
from extensions.attire.garment import (
    Garment,
    fauld,
    forged,
    gauntlets,
    pauldrons,
    sabatons,
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
    ACCENT_DYE,
    BEND,
    CHECKY,
    CHEVRON,
    CROSS,
    FUR,
    PALY,
    SALTIRE,
    SOLID,
    DyePattern,
    PARTY,
    PLATE,
    PRIMARY_DYE,
    QUARTERLY,
    SECONDARY_DYE,
    STRIPES,
    TRIM_DYE,
    VELVET,
)
from extensions.attire.metal import (
    BLACKENED,
    BLUED,
    BRASS,
    BRONZE,
    COPPER,
    GOLD,
    IRON,
    SILVER,
    STEEL,
    Metal,
    metal_color,
)
from extensions.attire.outfit import Outfit
from extensions.attire.preset import outfit_named
from extensions.humanoid.sex import FEMALE, MALE, Sex
from extensions.humanoid.skeleton.head.hair.beard import (
    CHIN_STRAP,
    CLEAN_SHAVEN,
    FORKED_BEARD,
    FULL_BEARD,
    GOATEE,
    LONG_BEARD,
    MUSTACHE,
    MUTTON_CHOPS,
    SHORT_BEARD,
    STUBBLE,
    Beard,
)
from extensions.humanoid.skeleton.head.hair.styles import (
    BOB,
    BRAID,
    BUN,
    CROPPED,
    GROWN,
    HALF_UP,
    LONG,
    PIGTAILS,
    PONYTAIL,
    SLICKED,
    TOPKNOT,
    TWIN_BRAIDS,
    HairStyle,
)
from render.framebuffer import Color
from units.si import METER, Length

comptime PLAIN_DYES = 9
"""How many dyes `plain_dye` gives."""
comptime RICH_DYES = 6
"""How many dyes `rich_dye` gives."""
comptime FUR_DYES = 6
"""How many furs `fur_dye` gives."""
comptime FOREST_DYES = 5
"""How many dyes `forest_dye` gives."""
comptime ARCANE_DYES = 6
"""How many dyes `arcane_dye` gives."""
comptime SHADOW_DYES = 5
"""How many dyes `shadow_dye` gives."""


@fieldwise_init
struct Calling(Equatable, ImplicitlyCopyable, Writable):
    """What a person does, which says what they wear."""

    var value: Int
    """Its index among the named values."""

    def is_valid(self) -> Bool:
        """Return whether this is a named calling.

        Returns:
            True for `PEASANT` through `WARRIOR`.
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
comptime FARMER = Calling(8)
"""A man or a woman who farms, in work clothes and a straw hat."""
comptime BARBARIAN = Calling(9)
"""A warrior of the north, in furs."""
comptime ROYAL = Calling(10)
"""A king or a queen, in velvet and ermine, crowned."""
comptime WIZARD = Calling(11)
"""A wizard in a long robe and a pointed hat."""
comptime WARLOCK = Calling(12)
"""A warlock in black, hooded or mantled."""
comptime RANGER = Calling(13)
"""An outlaw of the forest, in green, with a feathered cap or a hood."""
comptime WARRIOR = Calling(14)
"""A warrior in a full harness of plate of any metal."""
comptime CALLING_COUNT = 15
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
        "farmer",
        "barbarian",
        "royal",
        "wizard",
        "warlock",
        "ranger",
        "warrior",
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


def fur_dye(index: Int) -> Color:
    """Return the color of one pelt.

    Args:
        index: Which pelt. Any integer: it is taken modulo `FUR_DYES`.

    Returns:
        Wolf gray, bear brown, fox red, snow white, black or tawny.
    """
    var colors: List[Color] = [
        Color(124, 120, 112),
        Color(80, 58, 42),
        Color(150, 84, 42),
        Color(226, 222, 212),
        Color(36, 34, 32),
        Color(168, 128, 82),
    ]
    return colors[index % FUR_DYES]


def forest_dye(index: Int) -> Color:
    """Return one of the greens and browns of the forest.

    Args:
        index: Which dye. Any integer: it is taken modulo `FOREST_DYES`.

    Returns:
        Lincoln green, dark forest green, olive, moss or russet brown.
    """
    var colors: List[Color] = [
        Color(46, 86, 40),
        Color(30, 58, 32),
        Color(90, 96, 48),
        Color(70, 94, 56),
        Color(112, 70, 40),
    ]
    return colors[index % FOREST_DYES]


def arcane_dye(index: Int) -> Color:
    """Return one of the dyes a wizard wears.

    Args:
        index: Which dye. Any integer: it is taken modulo `ARCANE_DYES`.

    Returns:
        Deep blue, violet, midnight, crimson, ash gray or teal.
    """
    var colors: List[Color] = [
        Color(32, 46, 122),
        Color(78, 40, 122),
        Color(26, 28, 60),
        Color(132, 22, 38),
        Color(102, 102, 110),
        Color(24, 92, 98),
    ]
    return colors[index % ARCANE_DYES]


def shadow_dye(index: Int) -> Color:
    """Return one of the dark dyes a warlock wears.

    Args:
        index: Which dye. Any integer: it is taken modulo `SHADOW_DYES`.

    Returns:
        Black, dark purple, blood red, deep green or charcoal.
    """
    var colors: List[Color] = [
        Color(26, 24, 28),
        Color(50, 22, 62),
        Color(92, 14, 24),
        Color(20, 42, 30),
        Color(52, 52, 58),
    ]
    return colors[index % SHADOW_DYES]


def warrior_metal(seed: Int) -> Metal:
    """Return the metal a warrior's harness is forged of.

    Of each twenty seeds, about six are steel, three iron, three
    blackened, two blued, two bronze, one copper, one brass, one silver
    and one gold.

    Args:
        seed: Any integer.

    Returns:
        A named metal.
    """
    var roll = _mixed(seed, 11) % 20
    var metals: List[Metal] = [
        STEEL,
        IRON,
        BLACKENED,
        BLUED,
        BRONZE,
        COPPER,
        BRASS,
        SILVER,
        GOLD,
    ]
    var shares: List[Int] = [6, 3, 3, 2, 2, 1, 1, 1, 1]
    var pick = 0
    for k in range(len(shares)):  # pragma: no branch
        if roll < shares[k]:
            pick = k
            break
        roll -= shares[k]
    return metals[pick]


def calling_sex(calling: Calling) -> Sex:
    """Return the sex a calling dresses as when none is asked for.

    Args:
        calling: A calling.

    Returns:
        `FEMALE` for a goodwife and a noblewoman; `MALE` for the rest.
    """
    if calling == GOODWIFE or calling == NOBLEWOMAN:
        return FEMALE
    return MALE


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


def heraldry(seed: Int, salt: Int) -> DyePattern:
    """Return the pattern a seed picks for a surcoat's arms.

    Of each twenty seeds, about four are plain, three parted per pale,
    three quartered and three bear a chevron; two each bear a cross or a
    saltire, and one each a bend, paly or checky.

    Args:
        seed: Any integer.
        salt: Keeps this pick apart from the seed's other picks.

    Returns:
        A named pattern.
    """
    var patterns: List[DyePattern] = [
        SOLID,
        SOLID,
        SOLID,
        SOLID,
        PARTY,
        PARTY,
        PARTY,
        QUARTERLY,
        QUARTERLY,
        QUARTERLY,
        CROSS,
        CROSS,
        SALTIRE,
        SALTIRE,
        CHEVRON,
        CHEVRON,
        BEND,
        PALY,
        CHECKY,
        CHEVRON,
    ]
    return patterns[_mixed(seed, salt) % len(patterns)]


def _dyed(var garment: Garment, primary: Color, trim: Color) -> Garment:
    """Return a garment dyed one color, its trim another."""
    for k in range(len(garment.dyes)):  # pragma: no branch
        garment.dyes[k] = primary
    garment.dyes[TRIM_DYE.value] = trim
    return garment^


def calling_outfit(calling: Calling, seed: Int) raises -> Outfit:
    """Return the outfit of a calling, dyed and chosen by a seed.

    The person dresses as `calling_sex` says.

    Args:
        calling: A named calling.
        seed: Which dyes and which small choices. Any integer.

    Returns:
        The outfit.

    Raises:
        Error: If the calling is not named.
    """
    return dressed_as(calling, calling_sex(calling), seed)


def dressed_as(calling: Calling, sex: Sex, seed: Int) raises -> Outfit:
    """Return the outfit of a calling for a person of a sex, by a seed.

    The first eight callings dress as their own: a goodwife and a
    noblewoman as women, the rest as men. Farmers, barbarians, royals,
    wizards, warlocks, rangers and warriors have clothes for each sex.

    Args:
        calling: A named calling.
        sex: `MALE` or `FEMALE`.
        seed: Which dyes and which small choices. Any integer.

    Returns:
        The outfit.

    Raises:
        Error: If the calling or the sex is not named.
    """
    require_calling(calling)
    require_valid(sex.is_valid(), "A sex must be MALE or FEMALE")
    if calling.value >= FARMER.value:
        return _archetype(calling, sex == FEMALE, seed)
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
                made.pattern = heraldry(seed, 77)
            elif made.name == "hose":
                made = _dyed(made^, plain_dye(plain), plain_dye(plain))
            outfit.add(made^)
        if calling == MAN_AT_ARMS and _chance(seed, 4, 50):
            var coat = surcoat()
            coat.dyes[PRIMARY_DYE.value] = plain_dye(plain + 1)
            coat.dyes[SECONDARY_DYE.value] = plain_dye(plain + 2)
            # Some companies wear their colors quartered, or a cross or
            # a saltire.
            if _chance(seed, 7, 30):
                coat.pattern = QUARTERLY
            elif _chance(seed, 78, 30):
                coat.pattern = CROSS if _chance(seed, 79, 50) else SALTIRE
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
        var dress = _dyed(gown(), dye, trim)
        # A gown can be parti-colored: a second dye on the left side.
        if _chance(seed, 8, 30):
            dress.pattern = PARTY
            dress.dyes[SECONDARY_DYE.value] = trim
        outfit.add(dress^)
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
            var coat = _dyed(tunic(), plain_dye(plain), trim)
            # Townsmen liked a tunic parti-colored, a dye on each side.
            if calling == MERCHANT and _chance(seed, 8, 40):
                coat.pattern = PARTY
                coat.dyes[SECONDARY_DYE.value] = plain_dye(plain + 4)
            outfit.add(coat^)
        if _chance(seed, 5, 40):
            outfit.add(_dyed(hood(), plain_dye(plain + 2), plain_dye(plain)))
    if calling != PEASANT or _chance(seed, 6, 60):
        outfit.add(belt())
    outfit.add(boots())
    return outfit^


def _farmer(woman: Bool, seed: Int) raises -> Outfit:
    """Return a farmer's work clothes."""
    var plain = _mixed(seed, 1)
    var outfit = Outfit()
    outfit.add(_dyed(shirt(), plain_dye(6), plain_dye(6)))
    if woman:
        outfit.add(_dyed(gown(), plain_dye(plain), plain_dye(_mixed(seed, 59))))
        if _chance(seed, 12, 50):
            var laced = plain_dye(_mixed(seed, 60))
            outfit.add(_dyed(bodice(), laced, laced))
    else:
        outfit.add(_dyed(trousers(), plain_dye(plain + 3), plain_dye(3)))
        if _chance(seed, 12, 50):
            outfit.add(_dyed(smock(), plain_dye(6), plain_dye(plain)))
        else:
            outfit.add(_dyed(tunic(), plain_dye(plain), plain_dye(plain + 1)))
    if _chance(seed, 13, 70):
        outfit.add(straw_hat())
    if _chance(seed, 14, 50):
        outfit.add(belt())
    outfit.add(boots())
    return outfit^


def _barbarian(woman: Bool, seed: Int) raises -> Outfit:
    """Return a barbarian's furs, bare-chested for a man."""
    var pelt = _mixed(seed, 1)
    var outfit = Outfit()
    var metal = IRON if _chance(seed, 16, 50) else BRONZE
    # Some wear a shirt of scales, more of the women than of the men.
    if _chance(seed, 82, 25 if woman else 15):
        outfit.add(forged(scale_shirt(), metal))
    elif woman:
        var hide = plain_dye(3) if _chance(seed, 61, 50) else fur_dye(1)
        outfit.add(_dyed(jerkin(), hide, hide))
    outfit.add(_dyed(fur_kilt(), fur_dye(pelt), fur_dye(pelt + 1)))
    outfit.add(_dyed(fur_boots(), fur_dye(pelt), fur_dye(pelt)))
    outfit.add(bracers())
    outfit.add(belt())
    if _chance(seed, 15, 60):
        var mantle = fur_dye(_mixed(seed, 62))
        outfit.add(_dyed(fur_mantle(), mantle, mantle))
    if _chance(seed, 17, 50):
        outfit.add(forged(horned_helm(), metal))
    elif _chance(seed, 18, 40):
        outfit.add(forged(half_helm(), metal))
    return outfit^


def _royal(woman: Bool, seed: Int) raises -> Outfit:
    """Return a king's or a queen's robes, mantle and crown."""
    var rich = _mixed(seed, 2)
    var outfit = Outfit()
    outfit.add(shirt())
    var robe = _dyed(
        wizard_robe() if not woman else gown(),
        rich_dye(rich),
        Color(236, 232, 222),
    )
    robe.name = "royal robe" if not woman else "royal gown"
    robe.fabric = VELVET
    # Some robes are parti-colored, a second rich dye on the left side.
    if _chance(seed, 38, 25):
        robe.pattern = PARTY
        robe.dyes[SECONDARY_DYE.value] = rich_dye(_mixed(seed, 39))
    outfit.add(robe^)
    if not woman:
        outfit.add(_dyed(hose(), rich_dye(rich + 3), rich_dye(rich + 3)))
    var mantle = royal_mantle()
    var cloak = rich_dye(_mixed(seed, 40))
    mantle.dyes[PRIMARY_DYE.value] = cloak
    mantle.dyes[SECONDARY_DYE.value] = cloak
    # Ermine, or a gold edge.
    if _chance(seed, 41, 30):
        mantle.dyes[TRIM_DYE.value] = Color(214, 170, 64)
    outfit.add(mantle^)
    var girdle = rich_dye(_mixed(seed, 42))
    outfit.add(_dyed(sash(), girdle, girdle))
    var gold = SILVER if _chance(seed, 19, 25) else GOLD
    var stone = rich_dye(_mixed(seed, 43))
    if woman and _chance(seed, 20, 40):
        var band = forged(circlet(), gold)
        band.dyes[ACCENT_DYE.value] = stone
        outfit.add(band^)
    else:
        var made = forged(crown(), gold)
        made.dyes[ACCENT_DYE.value] = stone
        outfit.add(made^)
    outfit.add(boots())
    return outfit^


def _wizard(woman: Bool, seed: Int) raises -> Outfit:
    """Return a wizard's robe and pointed hat, in an arcane dye."""
    var dye = arcane_dye(_mixed(seed, 3))
    var trim = Color(214, 170, 64) if _chance(seed, 21, 60) else Color(
        200, 204, 214
    )
    var outfit = Outfit()
    outfit.add(shirt())
    var robe = _dyed(wizard_robe(), dye, trim)
    # Some robes are banded in a second arcane dye.
    if _chance(seed, 44, 20):
        robe.pattern = STRIPES
        robe.dyes[SECONDARY_DYE.value] = arcane_dye(_mixed(seed, 45))
    outfit.add(robe^)
    var girdle = trim if _chance(seed, 46, 50) else arcane_dye(_mixed(seed, 47))
    outfit.add(_dyed(sash(), girdle, girdle))
    if woman and _chance(seed, 22, 25):
        outfit.add(forged(circlet(), SILVER))
    else:
        # A hat in the robe's dye, or in another.
        var crown_dye = dye
        if _chance(seed, 48, 35):
            crown_dye = arcane_dye(_mixed(seed, 49))
        outfit.add(_dyed(wizard_hat(), crown_dye, trim))
    if _chance(seed, 50, 20):
        outfit.add(_dyed(fur_mantle(), fur_dye(0), fur_dye(3)))
    outfit.add(boots())
    return outfit^


def _warlock(woman: Bool, seed: Int) raises -> Outfit:
    """Return a warlock's black cassock, and a hood, a mantle or dark
    pauldrons."""
    var dark = _mixed(seed, 4)
    var outfit = Outfit()
    outfit.add(_dyed(shirt(), shadow_dye(0), shadow_dye(0)))
    var edge = shadow_dye(_mixed(seed, 51))
    outfit.add(_dyed(cassock(), shadow_dye(dark), edge))
    var girdle = shadow_dye(_mixed(seed, 52))
    outfit.add(_dyed(sash(), girdle, girdle))
    if _chance(seed, 23, 60):
        outfit.add(_dyed(hood(), shadow_dye(dark), edge))
    elif woman and _chance(seed, 24, 50):
        outfit.add(forged(circlet(), BLACKENED))
    if _chance(seed, 53, 25):
        outfit.add(forged(great_pauldrons(), BLACKENED, GOLD))
    elif _chance(seed, 25, 50):
        var mantle = royal_mantle()
        mantle.name = "dark mantle"
        outfit.add(_dyed(mantle^, shadow_dye(dark + 1), edge))
    outfit.add(_dyed(tall_boots(), shadow_dye(0), shadow_dye(0)))
    return outfit^


def _ranger(woman: Bool, seed: Int) raises -> Outfit:
    """Return a ranger's greens of the forest."""
    var green = _mixed(seed, 5)
    var outfit = Outfit()
    outfit.add(shirt())
    var legs = forest_dye(_mixed(seed, 54))
    outfit.add(_dyed(hose(), legs, legs))
    var coat = _dyed(tunic(), forest_dye(green), forest_dye(green + 1))
    if woman:
        coat.flare = 0.32
    outfit.add(coat^)
    if _chance(seed, 26, 60):
        var hide = plain_dye(3) if _chance(seed, 55, 60) else plain_dye(7)
        outfit.add(_dyed(jerkin(), hide, plain_dye(7)))
    outfit.add(bracers())
    outfit.add(belt())
    var hooded = forest_dye(_mixed(seed, 56))
    if _chance(seed, 27, 50):
        var cap = feathered_cap()
        cap.dyes[PRIMARY_DYE.value] = hooded
        cap.dyes[SECONDARY_DYE.value] = hooded
        if _chance(seed, 28, 50):
            cap.dyes[ACCENT_DYE.value] = Color(232, 228, 214)
        outfit.add(cap^)
    else:
        outfit.add(_dyed(hood(), hooded, forest_dye(green)))
    if _chance(seed, 57, 20):
        outfit.add(_dyed(fur_mantle(), fur_dye(_mixed(seed, 58)), fur_dye(1)))
    outfit.add(tall_boots())
    return outfit^


def _warrior(woman: Bool, seed: Int) raises -> Outfit:
    """Return a full harness of plate, forged of one metal."""
    var metal = warrior_metal(seed)
    var trim = Optional[Metal](None)
    if _chance(seed, 29, 25):
        trim = GOLD
    elif _chance(seed, 30, 25):
        trim = BRASS
    var outfit = Outfit()
    outfit.add(shirt())
    outfit.add(_dyed(hose(), plain_dye(_mixed(seed, 1)), plain_dye(3)))
    outfit.add(gambeson())
    # The legs first: a skirt over them hangs clear of their plate.
    outfit.add(forged(plate_legs(), metal, trim))
    # A shirt of scales, to the thigh, or a platebody and a skirt of plate.
    var scaled = _chance(seed, 81, 30)
    if scaled:
        outfit.add(forged(scale_shirt(), metal, trim))
    else:
        outfit.add(forged(platebody(), metal, trim))
    outfit.add(forged(arm_harness(), metal, trim))
    if _chance(seed, 31, 50):
        outfit.add(forged(great_pauldrons(), metal, trim))
    else:
        outfit.add(forged(pauldrons(), metal, trim))
    # A shirt of scales reaches the thigh: it needs no skirt of plate.
    if not scaled:
        if _chance(seed, 32, 50):
            outfit.add(forged(plate_skirt(), metal, trim))
        else:
            outfit.add(forged(fauld(), metal, trim))
    outfit.add(forged(gauntlets(), metal, trim))
    outfit.add(forged(sabatons(), metal, trim))
    var helm = _mixed(seed, 33) % 10
    if helm < 4:
        outfit.add(forged(great_helm(), metal, trim))
    elif helm < 7 or not woman:
        outfit.add(forged(half_helm(), metal, trim))
    if _chance(seed, 34, 30):
        var coat = surcoat()
        var rich = _mixed(seed, 2)
        coat.dyes[PRIMARY_DYE.value] = rich_dye(rich)
        coat.dyes[SECONDARY_DYE.value] = rich_dye(rich + 3)
        coat.dyes[TRIM_DYE.value] = rich_dye(rich + 3)
        coat.pattern = heraldry(seed, 80)
        outfit.add(coat^)
    outfit.add(belt())
    return outfit^


def _archetype(calling: Calling, woman: Bool, seed: Int) raises -> Outfit:
    """Return the outfit of one of the callings from `FARMER` on."""
    if calling == FARMER:
        return _farmer(woman, seed)
    if calling == BARBARIAN:
        return _barbarian(woman, seed)
    if calling == ROYAL:
        return _royal(woman, seed)
    if calling == WIZARD:
        return _wizard(woman, seed)
    if calling == WARLOCK:
        return _warlock(woman, seed)
    if calling == RANGER:
        return _ranger(woman, seed)
    return _warrior(woman, seed)


def _pick[T: Copyable](choices: List[T], seed: Int, salt: Int) -> T:
    """Return one of some choices, as a seed and a salt pick it."""
    return choices[_mixed(seed, salt) % len(choices)].copy()


def calling_hair(calling: Calling, sex: Sex, seed: Int) raises -> HairStyle:
    """Return the hairstyle a person of a calling wears, by a seed.

    | Callings | Women | Men |
    |---|---|---|
    | peasant, goodwife, farmer | bun, braid, ponytail, pigtails | grown, cropped |
    | noblewoman, royal | bun, braid, half up, long, topknot | slicked, grown, long |
    | barbarian | twin braids, braid, long | long, topknot, grown |
    | wizard, warlock, monk | long, half up, braid | long, slicked, cropped |
    | ranger, archer | braid, ponytail, twin braids | grown, ponytail, long |
    | man-at-arms, knight, warrior | braid, ponytail, bun, cropped | cropped, grown, slicked |
    | merchant | long, bun, bob, half up | grown, slicked, cropped |

    Args:
        calling: A named calling.
        sex: `MALE` or `FEMALE`.
        seed: Any integer.

    Returns:
        A designed or grown hairstyle.

    Raises:
        Error: If the calling or the sex is not named.
    """
    require_calling(calling)
    require_valid(sex.is_valid(), "A sex must be MALE or FEMALE")
    var woman = sex == FEMALE
    var styles: List[HairStyle]
    if calling == PEASANT or calling == GOODWIFE or calling == FARMER:
        styles = [BUN, BRAID, PONYTAIL, PIGTAILS] if woman else [
            GROWN,
            CROPPED,
        ]
    elif calling == NOBLEWOMAN or calling == ROYAL:
        styles = [BUN, BRAID, HALF_UP, LONG, TOPKNOT] if woman else [
            SLICKED,
            GROWN,
            LONG,
        ]
    elif calling == BARBARIAN:
        styles = [TWIN_BRAIDS, BRAID, LONG] if woman else [
            LONG,
            TOPKNOT,
            GROWN,
        ]
    elif calling == WIZARD or calling == WARLOCK or calling == MONK:
        styles = [LONG, HALF_UP, BRAID] if woman else [LONG, SLICKED, CROPPED]
    elif calling == RANGER or calling == ARCHER:
        styles = [BRAID, PONYTAIL, TWIN_BRAIDS] if woman else [
            GROWN,
            PONYTAIL,
            LONG,
        ]
    elif calling == MERCHANT:
        styles = [LONG, BUN, BOB, HALF_UP] if woman else [
            GROWN,
            SLICKED,
            CROPPED,
        ]
    else:
        styles = [BRAID, PONYTAIL, BUN, CROPPED] if woman else [
            CROPPED,
            GROWN,
            SLICKED,
        ]
    return _pick(styles, seed, 36)


def calling_beard(calling: Calling, sex: Sex, seed: Int) raises -> Beard:
    """Return the beard a person of a calling grows, by a seed.

    A woman is clean-shaven. A wizard grows a long or a full beard, a
    barbarian a forked, a full or a long one, and a royal a short or a
    full beard or a goatee. A warlock and a ranger favor a goatee, a
    soldier a clean chin, stubble or a chin strap, and the rest of the
    callings a mustache, stubble, mutton chops or a short beard.

    Args:
        calling: A named calling.
        sex: `MALE` or `FEMALE`.
        seed: Any integer.

    Returns:
        A named beard.

    Raises:
        Error: If the calling or the sex is not named.
    """
    require_calling(calling)
    require_valid(sex.is_valid(), "A sex must be MALE or FEMALE")
    if sex == FEMALE:
        return CLEAN_SHAVEN
    var beards: List[Beard]
    if calling == WIZARD:
        beards = [LONG_BEARD, LONG_BEARD, FULL_BEARD]
    elif calling == BARBARIAN:
        beards = [FORKED_BEARD, FULL_BEARD, LONG_BEARD]
    elif calling == ROYAL:
        beards = [SHORT_BEARD, FULL_BEARD, GOATEE]
    elif calling == WARLOCK or calling == RANGER:
        beards = [GOATEE, STUBBLE, CLEAN_SHAVEN, SHORT_BEARD]
    elif calling == MAN_AT_ARMS or calling == KNIGHT or calling == WARRIOR:
        beards = [CLEAN_SHAVEN, STUBBLE, CHIN_STRAP, SHORT_BEARD]
    elif calling == MONK:
        beards = [CLEAN_SHAVEN, FULL_BEARD]
    else:
        beards = [MUSTACHE, STUBBLE, MUTTON_CHOPS, SHORT_BEARD, CLEAN_SHAVEN]
    return _pick(beards, seed, 37)


@fieldwise_init
struct Arms(Copyable, ImplicitlyCopyable, Movable):
    """The arms a shield bears: a pattern, its two dyes and a rim."""

    var pattern: DyePattern
    """The pattern."""
    var field: Color
    """The primary dye, sRGB."""
    var charge: Color
    """The secondary dye, sRGB."""
    var rim: Color
    """The rim's color, sRGB."""


def calling_arms(calling: Calling, seed: Int) raises -> Optional[Arms]:
    """Return the arms a soldier of a calling bears on a shield, or none.

    A knight and a warrior bear the arms of their surcoat, in the same
    dyes and pattern by the same seed, whether or not they wear one this
    time. A man-at-arms bears his company's plain dyes, quartered or
    with a cross or a saltire by the same chances as his surcoat. A rim
    is the warrior's harness's trim metal, or its metal; a knight's is
    gold, and a man-at-arms's iron. The other callings bear none.

    Args:
        calling: A named calling.
        seed: Any integer: the seed of the person's outfit.

    Returns:
        The arms, or none.

    Raises:
        Error: If the calling is not named.
    """
    require_calling(calling)
    if calling == KNIGHT:
        var rich = _mixed(seed, 2)
        return Arms(
            heraldry(seed, 77),
            rich_dye(rich),
            rich_dye(rich + 3),
            metal_color(GOLD),
        )
    if calling == WARRIOR:
        var rich = _mixed(seed, 2)
        var rim = metal_color(warrior_metal(seed))
        if _chance(seed, 29, 25):
            rim = metal_color(GOLD)
        elif _chance(seed, 30, 25):
            rim = metal_color(BRASS)
        return Arms(heraldry(seed, 80), rich_dye(rich), rich_dye(rich + 3), rim)
    if calling == MAN_AT_ARMS:
        var plain = _mixed(seed, 1)
        var pattern = SOLID
        if _chance(seed, 7, 30):
            pattern = QUARTERLY
        elif _chance(seed, 78, 30):
            pattern = CROSS if _chance(seed, 79, 50) else SALTIRE
        return Arms(
            pattern,
            plain_dye(plain + 1),
            plain_dye(plain + 2),
            metal_color(IRON),
        )
    return None


comptime ERMINE = Color(236, 232, 222)
"""The white of an ermine edge."""
comptime GILT = Color(214, 170, 64)
"""The color of a gold edge."""
comptime SILVERED = Color(200, 204, 214)
"""The color of a silver edge."""


def _cloak_share(calling: Calling) -> Int:
    """Return how many of each hundred of a calling wear a cloak."""
    if calling == ROYAL:
        return 75
    if calling == WARLOCK or calling == RANGER:
        return 55
    if calling == KNIGHT:
        return 50
    if calling == WIZARD:
        return 45
    if calling == NOBLEWOMAN or calling == WARRIOR:
        return 40
    if calling == ARCHER or calling == BARBARIAN:
        return 35
    if calling == MERCHANT or calling == MONK:
        return 25
    return 15


def cloak_of(calling: Calling, seed: Int) raises -> CloakCut:
    """Return the cloak a calling wears, when it wears one, by a seed.

    | Callings | Cloak | Lining |
    |---|---|---|
    | royal | velvet in a rich dye to the ankle, edged in ermine or gold | gold, or a second rich dye |
    | noblewoman | velvet in a rich dye, edged in gold | ermine |
    | wizard | wool in an arcane dye to the ankle, edged in gold or silver | a second arcane dye |
    | warlock | wool in a shadow dye to the ankle, edged in a red | the same red |
    | knight, warrior, merchant | wool in a rich dye; a knight's is edged in a second | the second rich dye |
    | ranger, archer | wool in a forest dye | a second forest dye |
    | monk | wool in the plain dye of his robe, to the ankle | the same |
    | barbarian | a short cloak of fur | the hide |
    | the rest | plain wool, to the knee | the same |

    Each cloak's length and flare vary a little by the seed.

    Args:
        calling: A named calling.
        seed: Any integer. The same seed picks the dyes of the calling's
            outfit, so a monk's cloak matches his robe.

    Returns:
        The cloak's cut.

    Raises:
        Error: If the calling is not named.
    """
    require_calling(calling)
    var length = Float32(1.1)
    var cut = CloakCut()
    cut.dye = plain_dye(_mixed(seed, 63))
    if calling == ROYAL:
        length = 1.35
        cut.fabric = VELVET
        cut.dye = rich_dye(_mixed(seed, 64))
        cut.trim = ERMINE if _chance(seed, 65, 70) else GILT
        # Gold silk inside, or a second rich dye.
        cut.lining = GILT if _chance(seed, 74, 50) else rich_dye(
            _mixed(seed, 75)
        )
        cut.flare = 1.3
    elif calling == NOBLEWOMAN:
        length = 1.25
        cut.fabric = VELVET
        cut.dye = rich_dye(_mixed(seed, 64))
        cut.trim = GILT
        cut.lining = ERMINE
    elif calling == WIZARD:
        length = 1.3
        cut.dye = arcane_dye(_mixed(seed, 66))
        cut.trim = GILT if _chance(seed, 21, 60) else SILVERED
        cut.lining = arcane_dye(_mixed(seed, 76))
    elif calling == WARLOCK:
        length = 1.3
        cut.dye = shadow_dye(_mixed(seed, 67))
        cut.trim = Color(110, 18, 24)
        cut.lining = Color(110, 18, 24)
        cut.flare = 1.2
    elif calling == KNIGHT or calling == WARRIOR or calling == MERCHANT:
        var rich = _mixed(seed, 68)
        cut.dye = rich_dye(rich)
        cut.lining = rich_dye(rich + 3)
        if calling == KNIGHT:
            cut.trim = rich_dye(rich + 3)
    elif calling == RANGER or calling == ARCHER:
        var green = _mixed(seed, 69)
        cut.dye = forest_dye(green)
        cut.lining = forest_dye(green + 2)
        length = 1.0
    elif calling == MONK:
        length = 1.3
        cut.dye = plain_dye(3 + _mixed(seed, 1) % 3 * 2)
    elif calling == BARBARIAN:
        length = 0.8
        cut.fabric = FUR
        cut.dye = fur_dye(_mixed(seed, 70))
        # The hide shows inside.
        cut.lining = plain_dye(3)
        cut.flare = 0.7
    else:
        length = 0.9
    # Each cloak a little longer or shorter, and fuller or plainer.
    length *= 0.95 + 0.1 * Float32(_mixed(seed, 71) % 11) / 10
    cut.flare *= 0.85 + 0.3 * Float32(_mixed(seed, 72) % 11) / 10
    cut.length = Length(length, METER)
    return cut^


def calling_cloak(
    calling: Calling, sex: Sex, seed: Int
) raises -> Optional[CloakCut]:
    """Return the cloak a person of a calling wears, by a seed, or none.

    A royal wears one three times in four, a warlock and a ranger a
    little more than half the time, and a knight half the time. A wizard
    wears one nine times in twenty, a noblewoman and a warrior two times
    in five, an archer and a barbarian seven times in twenty, a merchant
    and a monk one time in four, and the rest three times in twenty.
    `cloak_of` says which cloak.

    Args:
        calling: A named calling.
        sex: `MALE` or `FEMALE`.
        seed: Any integer.

    Returns:
        The cloak's cut, or none.

    Raises:
        Error: If the calling or the sex is not named.
    """
    require_calling(calling)
    require_valid(sex.is_valid(), "A sex must be MALE or FEMALE")
    if not _chance(seed, 73, _cloak_share(calling)):
        return None
    return cloak_of(calling, seed)


def mixed_calling(seed: Int) -> Calling:
    """Return the calling a seed picks.

    Of each forty seeds, about eight are peasants, six goodwives, six
    farmers, three archers, three merchants, three men-at-arms, two
    monks, two rangers, and one each a noblewoman, a knight, a barbarian,
    a royal, a wizard, a warlock and a warrior.

    Args:
        seed: Any integer.

    Returns:
        A named calling.
    """
    var roll = _mixed(seed, 0) % 40
    var shares: List[Int] = [8, 6, 3, 2, 3, 1, 3, 1, 6, 1, 1, 1, 1, 2, 1]
    var calling = 0
    for k in range(CALLING_COUNT):  # pragma: no branch
        if roll < shares[k]:
            calling = k
            break
        roll -= shares[k]
    return Calling(calling)


def mixed_sex(seed: Int) -> Sex:
    """Return the sex of the person a seed picks.

    The first eight callings are their own sex, as `calling_sex` says. Of
    the farmers, barbarians, royals, wizards, warlocks, rangers and
    warriors, about two in five are women.

    Args:
        seed: Any integer.

    Returns:
        `MALE` or `FEMALE`.
    """
    var calling = mixed_calling(seed)
    if calling.value < FARMER.value:
        return calling_sex(calling)
    return FEMALE if _chance(seed, 35, 40) else MALE


def mixed_outfit(seed: Int) raises -> Outfit:
    """Return an outfit for one person of a crowd.

    Args:
        seed: Which person. Any integer.

    Returns:
        The outfit of `mixed_calling(seed)` for `mixed_sex(seed)`, dyed by
        the seed.

    Raises:
        Error: Never: every calling is named.
    """
    return dressed_as(mixed_calling(seed), mixed_sex(seed), seed)
