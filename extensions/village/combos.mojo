# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Combos: strings of presses that end in a strong finisher, which a
player learns as a style's skill grows and masters with use.

**The keys.** Each press of the fight is a `ComboKey`: a light or a heavy
attack, a dodge, a jump, or a tap of the guard. A `ComboTracker` keeps the
last `MOST_KEYS` keys. A key more than `COMBO_GAP` after the one before it
starts a new string.

**The beat.** A key pressed as the move before it lands is on the beat:
from `BEAT_EARLY` before the end of an attack's active part to `BEAT_LATE`
after it, or in the last `DODGE_BEAT` of a dodge. See `on_beat`. A key that
a combo marks must be on the beat. So the basic combos ask only for the
keys, and the hardest ask for each key in time.

**The finisher.** When the keys end in a combo that the player knows, its
finisher starts in place of the key's own move, at the combo's power, and
free of its special points: see `Fighter.request`. The longest combo that
matches wins, so a short combo can end a long string.

**The tiers.** A `ComboTier` says how hard a combo is. The style's skill
level teaches each combo: a `BASIC` combo from level 1 or 2, and a `MASTER`
combo from level 9. Only the player's specialty teaches `MASTER` combos.

**Mastery.** Each finisher made gives `MAKE_MASTERY`, and each that lands
`LAND_MASTERY` more. A combo's rank rises from 1 to `MAX_RANK` as its
mastery grows: rank `r` needs `rank_mastery(r)`. Each rank over 1 adds
`RANK_POWER` of the combo's power. See `ComboBook`.
"""

from core.ordinal import ordinal_valid
from extensions.village.combat import (
    AIMED_SHOT,
    ARROW_RAIN,
    GROUND_WAVE,
    HEAVY,
    LEAP_SHOT,
    LIGHT_THREE,
    MEND,
    NOVA,
    PLUNGE,
    RISING_EDGE,
    SPELL_BLAST,
    VOLLEY,
    WHIRLWIND,
    CombatMove,
    DODGE,
    Fighter,
    is_attack,
)
from extensions.village.styles import (
    ARCHERY,
    AXE,
    HAND_TO_HAND,
    MACE,
    MAGIC,
    SWORD,
    FightingStyle,
)

comptime COMBO_KEYS = 5
"""How many kinds of combo key there are."""
comptime COMBO_TIERS = 4
"""How many tiers of combo there are."""
comptime MOST_KEYS = 8
"""How many keys a tracker keeps, and a combo has at most."""
comptime COMBO_GAP = Float32(1.0)
"""How long after a key the next key still adds to the string, in
seconds."""
comptime BEAT_EARLY = Float32(0.06)
"""How long before the end of an attack's active part a key is on the
beat, in seconds."""
comptime BEAT_LATE = Float32(0.16)
"""How long after the end of an attack's active part a key is on the
beat, in seconds."""
comptime DODGE_BEAT = Float32(0.22)
"""How long before the end of a dodge a key is on the beat, in seconds."""
comptime BEAT_BONUS = Float32(1.1)
"""How many times its damage an attack pressed on the beat does, in or out
of a combo."""
comptime MAX_RANK = 5
"""The highest rank of a combo."""
comptime RANK_POWER = Float32(0.1)
"""How much of a combo's power each rank over 1 adds."""
comptime MAKE_MASTERY = 2
"""The mastery of a combo's finisher made."""
comptime LAND_MASTERY = 3
"""The mastery of a combo's finisher that lands."""


@fieldwise_init
struct ComboKey(Equatable, ImplicitlyCopyable, Writable):
    """One press of a combo, as a type rather than a bare int."""

    var value: Int

    def is_valid(self) -> Bool:
        """Return whether this is one of the keys.

        Returns:
            True from `LIGHT_KEY` to `GUARD_KEY`.
        """
        return ordinal_valid(self.value, COMBO_KEYS - 1)


comptime LIGHT_KEY = ComboKey(0)
"""A light attack's press."""
comptime HEAVY_KEY = ComboKey(1)
"""A heavy attack's press."""
comptime DODGE_KEY = ComboKey(2)
"""A dodge's press."""
comptime JUMP_KEY = ComboKey(3)
"""A jump's press."""
comptime GUARD_KEY = ComboKey(4)
"""A tap of the guard."""


@fieldwise_init
struct ComboTier(Equatable, ImplicitlyCopyable, Writable):
    """How hard a combo is, as a type rather than a bare int."""

    var value: Int

    def is_valid(self) -> Bool:
        """Return whether this is one of the tiers.

        Returns:
            True from `BASIC` to `MASTER`.
        """
        return ordinal_valid(self.value, COMBO_TIERS - 1)


comptime BASIC = ComboTier(0)
"""A combo that anyone can make: two or three keys, none on the beat."""
comptime ADVANCED = ComboTier(1)
"""A combo of a dodge, a jump or a guard among its keys."""
comptime EXPERT = ComboTier(2)
"""A combo with keys on the beat."""
comptime MASTER = ComboTier(3)
"""A long combo with nearly every key on the beat. Only a specialty
teaches it."""


def key_name(key: ComboKey) raises -> String:
    """Return a key's letter for the display.

    Args:
        key: The key.

    Returns:
        "L", "H", "D", "J" or "G".

    Raises:
        Error: If the key is not one.
    """
    if not key.is_valid():
        raise Error("A combo key must be one of the five")
    var letters: List[String] = ["L", "H", "D", "J", "G"]
    return letters[key.value]


def tier_name(tier: ComboTier) raises -> String:
    """Return a tier's name, in capitals for the display.

    Args:
        tier: The tier.

    Returns:
        "BASIC", "ADVANCED", "EXPERT" or "MASTER".

    Raises:
        Error: If the tier is not one.
    """
    if not tier.is_valid():
        raise Error("A combo tier must be one of the four")
    var names: List[String] = ["BASIC", "ADVANCED", "EXPERT", "MASTER"]
    return names[tier.value]


struct Combo(Copyable, Movable):
    """A string of keys, and the finisher it ends in."""

    var name: String
    var style: FightingStyle
    var keys: List[ComboKey]
    # Whether each key must be on the beat.
    var beats: List[Bool]
    var finisher: CombatMove
    var tier: ComboTier
    # The style's skill level that teaches it, and how many times its
    # damage the finisher does at rank 1.
    var level: Int
    var power: Float32

    def __init__(
        out self,
        name: String,
        style: FightingStyle,
        pattern: String,
        finisher: CombatMove,
        tier: ComboTier,
        level: Int,
        power: Float32,
    ) raises:
        """Hold a combo, from a pattern of letters.

        Args:
            name: Its name, in capitals.
            style: The style it is made in.
            pattern: Its keys as letters, apart by spaces: `L`, `H`, `D`,
                `J` or `G`. A key that ends in `*` must be on the beat,
                such as "L L* H*".
            finisher: The move that it ends in.
            tier: How hard it is.
            level: The style's skill level that teaches it, from 1 to 10.
            power: How many times its damage the finisher does at rank 1,
                from 0.5 to 5.

        Raises:
            Error: If the style or the tier is not one; the pattern has a
                letter that is not a key, fewer than two keys, more than
                `MOST_KEYS`, or a first key on the beat; the finisher is
                not an attack; the level is not from 1 to 10; or the power
                is not from 0.5 to 5.
        """
        if not style.is_valid():
            raise Error("A combo's style must be one of the six")
        if not tier.is_valid():
            raise Error("A combo's tier must be one of the four")
        if not is_attack(finisher):
            raise Error("A combo's finisher must be an attack")
        if not (level >= 1 and level <= 10):
            raise Error("A combo's level must be from 1 to 10")
        if not (power >= 0.5 and power <= 5):
            raise Error("A combo's power must be from 0.5 to 5")
        self.name = name
        self.style = style
        self.keys = List[ComboKey]()
        self.beats = List[Bool]()
        self.finisher = finisher
        self.tier = tier
        self.level = level
        self.power = power
        var letters: List[String] = ["L", "H", "D", "J", "G"]
        for word in pattern.split(" "):  # pragma: no branch
            if word.byte_length() == 0:
                continue
            var beat = word.endswith("*")
            var letter = String(word[byte=0:1])
            var found = -1
            for k in range(COMBO_KEYS):  # pragma: no branch
                if letters[k] == letter:
                    found = k
            var plain = word.byte_length() == 1 or (
                beat and word.byte_length() == 2
            )
            if found < 0 or not plain:
                raise Error("A combo's pattern must be letters of its keys")
            self.keys.append(ComboKey(found))
            self.beats.append(beat)
        if not (len(self.keys) >= 2 and len(self.keys) <= MOST_KEYS):
            raise Error("A combo must have from 2 to 8 keys")
        if self.beats[0]:
            raise Error("A combo's first key cannot be on the beat")

    def pattern(self) raises -> String:
        """Return the combo's keys as letters, for the display.

        Returns:
            Such as "L L* H*": a key on the beat ends in `*`.

        Raises:
            Error: Never: each key is one.
        """
        var out = String()
        for k in range(len(self.keys)):  # pragma: no branch
            if k > 0:
                out += " "
            out += key_name(self.keys[k])
            if self.beats[k]:
                out += "*"
        return out^


def on_beat(fighter: Fighter) raises -> Bool:
    """Return whether a key pressed now is on the beat.

    Args:
        fighter: The fighter who presses.

    Returns:
        True from `BEAT_EARLY` before the end of an attack's active part to
        `BEAT_LATE` after it, and in the last `DODGE_BEAT` of a dodge.

    Raises:
        Error: Never: the move is one.
    """
    if fighter.move == DODGE:
        return fighter.clock >= fighter.length() - DODGE_BEAT
    if not is_attack(fighter.move):
        return False
    var end = fighter.active_end()
    return (
        fighter.clock >= end - BEAT_EARLY and fighter.clock <= end + BEAT_LATE
    )


struct ComboTracker(Copyable, Movable):
    """The keys of the string the player makes now."""

    var keys: List[ComboKey]
    var beats: List[Bool]
    # How long ago the last key was pressed, in seconds.
    var gap: Float32

    def __init__(out self):
        """Begin with no keys."""
        self.keys = List[ComboKey]()
        self.beats = List[Bool]()
        self.gap = 0

    def clear(mut self):
        """Forget the string's keys."""
        self.keys.clear()
        self.beats.clear()

    def press(mut self, key: ComboKey, beat: Bool) raises:
        """Add a key to the string.

        Args:
            key: The key.
            beat: Whether it was pressed on the beat: see `on_beat`.

        Raises:
            Error: If the key is not one.
        """
        if not key.is_valid():
            raise Error("A combo key must be one of the five")
        if self.gap > COMBO_GAP:
            self.clear()
        self.keys.append(key)
        self.beats.append(beat)
        if len(self.keys) > MOST_KEYS:
            _ = self.keys.pop(0)
            _ = self.beats.pop(0)
        self.gap = 0

    def update(mut self, seconds: Float32):
        """Let time pass: a string with no key for `COMBO_GAP` ends.

        Args:
            seconds: The frame's time.
        """
        self.gap += seconds
        if self.gap > COMBO_GAP:
            self.clear()

    def ends_with(self, combo: Combo) -> Bool:
        """Return whether the string ends in a combo's keys, each on the
        beat where the combo asks.

        Args:
            combo: The combo.

        Returns:
            True when the last keys are the combo's.
        """
        var count = len(combo.keys)
        var have = len(self.keys)
        if count > have:
            return False
        for k in range(count):  # pragma: no branch
            var at = have - count + k
            if self.keys[at] != combo.keys[k]:
                return False
            if combo.beats[k] and not self.beats[at]:
                return False
        return True

    def progress(self, combo: Combo) -> Int:
        """Return how far the string has gone into a combo.

        Args:
            combo: The combo.

        Returns:
            The most keys, fewer than the combo's, that both end the string
            and begin the combo, each on the beat where the combo asks; zero
            for none.
        """
        var most = min(len(combo.keys) - 1, len(self.keys))
        var size = most
        while size > 0:
            var ok = True
            for k in range(size):  # pragma: no branch
                var at = len(self.keys) - size + k
                if self.keys[at] != combo.keys[k]:
                    ok = False
                elif combo.beats[k] and not self.beats[at]:
                    ok = False
            if ok:
                return size
            size -= 1
        return 0


def rank_mastery(rank: Int) -> Int:
    """Return the mastery a combo needs to reach a rank.

    Args:
        rank: The rank, from 1.

    Returns:
        20 times `rank - 1` times `rank`: 0 for rank 1, 40 for rank 2 and
        400 for rank 5.
    """
    return 20 * (rank - 1) * rank


def rank_of(mastery: Int) -> Int:
    """Return the rank of a combo with some mastery.

    Args:
        mastery: The combo's mastery.

    Returns:
        The highest rank, up to `MAX_RANK`, whose mastery it has.
    """
    var rank = 1
    while rank < MAX_RANK and mastery >= rank_mastery(rank + 1):
        rank += 1
    return rank


def default_combos() raises -> List[Combo]:
    """Return every style's combos.

    Returns:
        Six to eight combos a style, from `BASIC` to `MASTER`: see the
        catalog of Village combos.

    Raises:
        Error: Never: each combo checks.
    """
    var out = List[Combo]()
    # The sword.
    out.append(Combo("RISING STRIKE", SWORD, "L L H", RISING_EDGE, BASIC, 1, 1))
    out.append(Combo("CROSS CUT", SWORD, "L H", HEAVY, BASIC, 2, 1.25))
    out.append(Combo("TEMPEST", SWORD, "L L L H", WHIRLWIND, ADVANCED, 3, 1.2))
    out.append(Combo("DASH CUT", SWORD, "D L", LIGHT_THREE, ADVANCED, 4, 1.5))
    out.append(Combo("RIPOSTE", SWORD, "G L", LIGHT_THREE, ADVANCED, 5, 1.8))
    out.append(
        Combo("RIVER OF STEEL", SWORD, "L L* H*", GROUND_WAVE, EXPERT, 6, 1.6)
    )
    out.append(
        Combo("SKY BREAKER", SWORD, "L L* J L H", PLUNGE, EXPERT, 7, 1.8)
    )
    out.append(
        Combo(
            "THOUSAND CUTS",
            SWORD,
            "L L* L* D L* L* H*",
            WHIRLWIND,
            MASTER,
            9,
            2.6,
        )
    )
    # Hand to hand.
    out.append(
        Combo("UPPERCUT", HAND_TO_HAND, "L L H", RISING_EDGE, BASIC, 1, 1)
    )
    out.append(Combo("BODY BLOW", HAND_TO_HAND, "L H", HEAVY, BASIC, 2, 1.3))
    out.append(
        Combo("FLURRY", HAND_TO_HAND, "L L L L", LIGHT_THREE, ADVANCED, 3, 1.5)
    )
    out.append(
        Combo("SPINNING HEEL", HAND_TO_HAND, "D H", WHIRLWIND, ADVANCED, 4, 1.3)
    )
    out.append(
        Combo(
            "RISING DRAGON",
            HAND_TO_HAND,
            "L L* L* H*",
            RISING_EDGE,
            EXPERT,
            6,
            1.9,
        )
    )
    out.append(
        Combo("EARTHSHAKER", HAND_TO_HAND, "J L H*", PLUNGE, EXPERT, 7, 1.7)
    )
    out.append(
        Combo(
            "STORM OF FISTS",
            HAND_TO_HAND,
            "L L* L* L* L* L* H*",
            WHIRLWIND,
            MASTER,
            9,
            2.8,
        )
    )
    # The axe.
    out.append(Combo("CLEAVER", AXE, "L L H", HEAVY, BASIC, 1, 1.2))
    out.append(Combo("HEWING ARC", AXE, "L H", WHIRLWIND, BASIC, 2, 1))
    out.append(Combo("TIMBER", AXE, "H H", HEAVY, ADVANCED, 3, 1.5))
    out.append(
        Combo("REAVER SPIN", AXE, "L L L H", WHIRLWIND, ADVANCED, 5, 1.4)
    )
    out.append(Combo("SPLITTER", AXE, "D H*", RISING_EDGE, EXPERT, 7, 1.8))
    out.append(
        Combo("WORLD SPLITTER", AXE, "L L* H* H*", GROUND_WAVE, MASTER, 9, 2.6)
    )
    # The mace.
    out.append(Combo("BONEBREAKER", MACE, "L H", HEAVY, BASIC, 1, 1.25))
    out.append(Combo("BELL RINGER", MACE, "L L H", RISING_EDGE, BASIC, 2, 1))
    out.append(Combo("QUAKE", MACE, "H H", GROUND_WAVE, ADVANCED, 4, 1.4))
    out.append(Combo("IRON TIDE", MACE, "L L L H", WHIRLWIND, ADVANCED, 5, 1.3))
    out.append(Combo("PILEDRIVER", MACE, "J H*", PLUNGE, EXPERT, 7, 2))
    out.append(
        Combo("JUDGMENT", MACE, "L L* H* G H*", GROUND_WAVE, MASTER, 9, 2.8)
    )
    # Magic.
    out.append(Combo("SPARK CHAIN", MAGIC, "L L L", SPELL_BLAST, BASIC, 1, 1.2))
    out.append(Combo("ARCANE RING", MAGIC, "L H", NOVA, BASIC, 2, 1))
    out.append(
        Combo("BLINK BLAST", MAGIC, "D L", SPELL_BLAST, ADVANCED, 3, 1.3)
    )
    out.append(Combo("SANCTUARY", MAGIC, "G H", MEND, ADVANCED, 5, 1.4))
    out.append(Combo("STARBURST", MAGIC, "L L* L* H*", NOVA, EXPERT, 7, 1.9))
    out.append(
        Combo("COMET", MAGIC, "L L* D L* H* H*", SPELL_BLAST, MASTER, 9, 3)
    )
    # Archery.
    out.append(
        Combo("PINNING SHOT", ARCHERY, "L L H", AIMED_SHOT, BASIC, 1, 1.2)
    )
    out.append(Combo("SCATTER", ARCHERY, "L H", VOLLEY, BASIC, 2, 1))
    out.append(
        Combo("EVASIVE SHOT", ARCHERY, "D L", LEAP_SHOT, ADVANCED, 3, 1.3)
    )
    out.append(
        Combo("PIERCING GALE", ARCHERY, "H H", AIMED_SHOT, ADVANCED, 5, 1.5)
    )
    out.append(
        Combo("HAILSTORM", ARCHERY, "L L* L* H*", ARROW_RAIN, EXPERT, 7, 1.6)
    )
    out.append(
        Combo(
            "HUNTER'S MOON", ARCHERY, "L L* D L* H*", AIMED_SHOT, MASTER, 9, 3
        )
    )
    return out^


struct ComboBook(Copyable, Movable):
    """The combos the player knows, and how well."""

    var combos: List[Combo]
    var learned: List[Bool]
    var mastery: List[Int]
    # The style the player specializes in: only it teaches `MASTER`
    # combos.
    var specialty: FightingStyle

    def __init__(out self, specialty: FightingStyle) raises:
        """Hold every style's combos, none learned yet.

        Args:
            specialty: The style the player specializes in.

        Raises:
            Error: If the specialty is not a style.
        """
        if not specialty.is_valid():
            raise Error("A specialty must be one of the six styles")
        self.combos = default_combos()
        self.learned = List[Bool](length=len(self.combos), fill=False)
        self.mastery = List[Int](length=len(self.combos), fill=0)
        self.specialty = specialty

    def teach(mut self, style: FightingStyle, level: Int) -> List[Int]:
        """Learn each combo of a style that its skill level teaches.

        Args:
            style: The style.
            level: The style's skill level.

        Returns:
            The combos newly learned. A `MASTER` combo is learned only in
            the specialty.
        """
        var out = List[Int]()
        for k in range(len(self.combos)):
            ref combo = self.combos[k]
            if combo.style != style or self.learned[k]:
                continue
            if combo.level > level:
                continue
            if combo.tier == MASTER and style != self.specialty:
                continue
            self.learned[k] = True
            out.append(k)
        return out^

    def known(self, style: FightingStyle) -> List[Int]:
        """Return the combos of a style that the player knows.

        Args:
            style: The style.

        Returns:
            Their indices.
        """
        var out = List[Int]()
        for k in range(len(self.combos)):
            if self.learned[k] and self.combos[k].style == style:
                out.append(k)
        return out^

    def rank(self, index: Int) raises -> Int:
        """Return a combo's rank.

        Args:
            index: The combo.

        Returns:
            Its rank, from 1 to `MAX_RANK`.

        Raises:
            Error: If there is no such combo.
        """
        if not (index >= 0 and index < len(self.combos)):
            raise Error("There is no such combo")
        return rank_of(self.mastery[index])

    def power(self, index: Int) raises -> Float32:
        """Return how many times its damage a combo's finisher does.

        Args:
            index: The combo.

        Returns:
            Its power, and `RANK_POWER` of it more for each rank over 1.

        Raises:
            Error: If there is no such combo.
        """
        var rank = self.rank(index)
        return self.combos[index].power * (1 + RANK_POWER * Float32(rank - 1))

    def practice(mut self, index: Int, amount: Int) raises -> Bool:
        """Give a combo mastery.

        Args:
            index: The combo.
            amount: How much, zero or more.

        Returns:
            Whether its rank rose.

        Raises:
            Error: If there is no such combo, or the amount is negative.
        """
        if amount < 0:
            raise Error("A combo's mastery must not be negative")
        var before = self.rank(index)
        self.mastery[index] += amount
        return self.rank(index) > before

    def match(self, tracker: ComboTracker, style: FightingStyle) -> Int:
        """Return the known combo that the tracker's string ends in.

        Args:
            tracker: The string.
            style: The style the player fights in.

        Returns:
            The longest such combo of the style, or -1 for none.
        """
        var best = -1
        var longest = 0
        for k in self.known(style):
            ref combo = self.combos[k]
            if len(combo.keys) > longest and tracker.ends_with(combo):
                longest = len(combo.keys)
                best = k
        return best

    def routes(self, tracker: ComboTracker, style: FightingStyle) -> List[Int]:
        """Return the known combos that the string is on its way to.

        Args:
            tracker: The string.
            style: The style the player fights in.

        Returns:
            The combos of the style with some progress, the furthest first.
        """
        var out = List[Int]()
        var made = List[Int]()
        for k in self.known(style):
            var done = tracker.progress(self.combos[k])
            if done == 0:
                continue
            var at = len(out)
            while at > 0 and made[at - 1] < done:
                at -= 1
            out.insert(at, k)
            made.insert(at, done)
        return out^
