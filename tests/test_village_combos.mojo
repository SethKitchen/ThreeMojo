# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Combos: their keys, the beat, the string a player makes, the combos a
level teaches, and the mastery that ranks them up."""

from extensions.village.combat import (
    DODGE,
    HEAVY,
    LIGHT_ONE,
    Fighter,
    FighterParameters,
)
from extensions.village.combos import (
    BASIC,
    BEAT_EARLY,
    BEAT_LATE,
    BLEED,
    COMBO_EFFECTS,
    COMBO_GAP,
    COMBO_KEYS,
    COMBO_TIERS,
    DODGE_BEAT,
    DODGE_KEY,
    EXPERT,
    GUARD_KEY,
    HEAVY_KEY,
    JUMP_KEY,
    LIGHT_KEY,
    MARK,
    MASTER,
    MAX_RANK,
    MOST_KEYS,
    NO_EFFECT,
    RANK_POWER,
    Combo,
    ComboBook,
    ComboEffect,
    ComboKey,
    ComboTier,
    ComboTracker,
    default_combos,
    effect_name,
    key_name,
    on_beat,
    rank_mastery,
    rank_of,
    tier_name,
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
from std.testing import (
    TestSuite,
    assert_almost_equal,
    assert_equal,
    assert_false,
    assert_raises,
    assert_true,
)
from units.si import SECOND, Duration


def _run(mut fighter: Fighter, seconds: Float32) raises:
    """Move a fighter on by some time, in steps of a 120th of a second."""
    var steps = Int(seconds * 120 + 0.5)
    for _ in range(steps):
        fighter.update(Duration(Float32(1) / 120, SECOND))


def _string(pattern: String) raises -> ComboTracker:
    """Return a tracker that holds a pattern's keys: letters apart by
    spaces, each ending in `*` when it was on the beat."""
    var letters: List[String] = ["L", "H", "D", "J", "G"]
    var tracker = ComboTracker()
    for word in pattern.split(" "):
        for k in range(len(letters)):
            if String(word[byte=0:1]) == letters[k]:
                tracker.press(ComboKey(k), word.endswith("*"))
    return tracker^


def test_keys_and_tiers_know_their_values() raises:
    for value in [-1, COMBO_KEYS]:
        assert_false(ComboKey(value).is_valid())
    for value in [0, COMBO_KEYS - 1]:
        assert_true(ComboKey(value).is_valid())
    for value in [-1, COMBO_TIERS]:
        assert_false(ComboTier(value).is_valid())
    for value in [0, COMBO_TIERS - 1]:
        assert_true(ComboTier(value).is_valid())
    assert_equal(key_name(LIGHT_KEY), "L")
    assert_equal(key_name(GUARD_KEY), "G")
    with assert_raises(contains="five"):
        _ = key_name(ComboKey(5))
    assert_equal(tier_name(BASIC), "BASIC")
    assert_equal(tier_name(MASTER), "MASTER")
    with assert_raises(contains="four"):
        _ = tier_name(ComboTier(4))
    for value in [-1, COMBO_EFFECTS]:
        assert_false(ComboEffect(value).is_valid())
    for value in [0, COMBO_EFFECTS - 1]:
        assert_true(ComboEffect(value).is_valid())
    assert_equal(effect_name(NO_EFFECT), "")
    assert_equal(effect_name(BLEED), "BLEED")
    assert_equal(effect_name(MARK), "MARK")
    with assert_raises(contains="eight"):
        _ = effect_name(ComboEffect(8))
    with assert_raises(contains="eight"):
        _ = Combo("ODD", SWORD, "L H", HEAVY, BASIC, 1, 1, ComboEffect(9))
    assert_true(
        Combo("PLAIN", SWORD, "L H", HEAVY, BASIC, 1, 1).effect == NO_EFFECT
    )


def test_a_combo_reads_its_pattern() raises:
    var combo = Combo("TEST", SWORD, "L  L* D J G H*", HEAVY, EXPERT, 6, 2)
    assert_equal(len(combo.keys), 6)
    assert_true(combo.keys[2] == DODGE_KEY)
    assert_true(combo.keys[3] == JUMP_KEY)
    assert_true(combo.keys[4] == GUARD_KEY)
    assert_false(combo.beats[0])
    assert_true(combo.beats[1])
    assert_true(combo.beats[5])
    assert_equal(combo.pattern(), "L L* D J G H*")


def test_a_combo_refuses_what_cannot_be_made() raises:
    with assert_raises(contains="style"):
        _ = Combo("", FightingStyle(6), "L H", HEAVY, BASIC, 1, 1)
    with assert_raises(contains="tier"):
        _ = Combo("", SWORD, "L H", HEAVY, ComboTier(4), 1, 1)
    with assert_raises(contains="attack"):
        _ = Combo("", SWORD, "L H", DODGE, BASIC, 1, 1)
    with assert_raises(contains="level"):
        _ = Combo("", SWORD, "L H", HEAVY, BASIC, 0, 1)
    with assert_raises(contains="level"):
        _ = Combo("", SWORD, "L H", HEAVY, BASIC, 11, 1)
    with assert_raises(contains="power"):
        _ = Combo("", SWORD, "L H", HEAVY, BASIC, 1, 0.4)
    with assert_raises(contains="power"):
        _ = Combo("", SWORD, "L H", HEAVY, BASIC, 1, 6)
    with assert_raises(contains="letters"):
        _ = Combo("", SWORD, "L X", HEAVY, BASIC, 1, 1)
    with assert_raises(contains="letters"):
        _ = Combo("", SWORD, "L HH", HEAVY, BASIC, 1, 1)
    with assert_raises(contains="letters"):
        _ = Combo("", SWORD, "L H**", HEAVY, BASIC, 1, 1)
    with assert_raises(contains="2 to 8"):
        _ = Combo("", SWORD, "L", HEAVY, BASIC, 1, 1)
    with assert_raises(contains="2 to 8"):
        _ = Combo("", SWORD, "L L L L L L L L L", HEAVY, BASIC, 1, 1)
    with assert_raises(contains="first"):
        _ = Combo("", SWORD, "L* H", HEAVY, BASIC, 1, 1)


def test_the_beat_is_as_a_blow_lands() raises:
    var f = Fighter(FighterParameters())
    assert_false(on_beat(f))
    _ = f.request(LIGHT_ONE)
    _run(f, 0.1)
    assert_false(on_beat(f))
    var end = f.active_end()
    f.clock = end - BEAT_EARLY + 0.01
    assert_true(on_beat(f))
    f.clock = end + BEAT_LATE - 0.01
    assert_true(on_beat(f))
    f.clock = end + BEAT_LATE + 0.01
    assert_false(on_beat(f))
    var g = Fighter(FighterParameters())
    _ = g.request(DODGE)
    assert_false(on_beat(g))
    g.clock = g.length() - DODGE_BEAT + 0.01
    assert_true(on_beat(g))


def test_a_tracker_keeps_a_string_of_keys() raises:
    var tracker = ComboTracker()
    tracker.press(LIGHT_KEY, False)
    tracker.update(COMBO_GAP / 2)
    tracker.press(LIGHT_KEY, True)
    assert_equal(len(tracker.keys), 2)
    # A key long after the last starts a new string.
    tracker.gap = COMBO_GAP + 0.1
    tracker.press(HEAVY_KEY, False)
    assert_equal(len(tracker.keys), 1)
    # A string with no key for the gap ends.
    tracker.update(COMBO_GAP + 0.1)
    assert_equal(len(tracker.keys), 0)
    # It keeps the last keys only.
    for _ in range(MOST_KEYS + 3):
        tracker.press(LIGHT_KEY, False)
    assert_equal(len(tracker.keys), MOST_KEYS)
    assert_equal(len(tracker.beats), MOST_KEYS)
    with assert_raises(contains="five"):
        tracker.press(ComboKey(7), False)


def test_a_string_ends_in_a_combo_with_its_beats() raises:
    var combo = Combo("", SWORD, "L L* H*", HEAVY, EXPERT, 6, 1)
    assert_true(_string("L L L* H*").ends_with(combo))
    assert_true(_string("L* L* H*").ends_with(combo))
    # Too short, another key, or a key off the beat.
    assert_false(_string("L* H*").ends_with(combo))
    assert_false(_string("L D* H*").ends_with(combo))
    assert_false(_string("L L H*").ends_with(combo))
    assert_false(_string("L L* H").ends_with(combo))


def test_a_string_goes_part_of_the_way_into_a_combo() raises:
    var combo = Combo("", SWORD, "L L* H* D", HEAVY, EXPERT, 6, 1)
    assert_equal(_string("H L L*").progress(combo), 2)
    assert_equal(_string("L L* H*").progress(combo), 3)
    assert_equal(_string("H H L").progress(combo), 1)
    assert_equal(_string("L L H").progress(combo), 0)
    assert_equal(_string("D D").progress(combo), 0)
    # The whole combo is no progress: it is made.
    assert_equal(_string("L L* H* D").progress(combo), 0)


def test_every_style_has_its_combos() raises:
    var combos = default_combos()
    var styles: List[FightingStyle] = [
        SWORD,
        HAND_TO_HAND,
        AXE,
        MACE,
        MAGIC,
        ARCHERY,
    ]
    for style in styles:
        var basic = 0
        var master = 0
        var count = 0
        for combo in combos:
            if combo.style != style:
                continue
            count += 1
            if combo.tier == BASIC:
                basic += 1
                assert_true(combo.level <= 2)
            if combo.tier == MASTER:
                master += 1
                assert_equal(combo.level, 9)
        assert_equal(basic, 2)
        assert_equal(master, 2)
        assert_equal(count, 10)


def test_a_level_teaches_its_styles_combos() raises:
    var book = ComboBook(SWORD)
    var first = book.teach(SWORD, 1)
    assert_equal(len(first), 1)
    assert_equal(book.combos[first[0]].name, "RISING STRIKE")
    # Again, it teaches nothing new.
    assert_equal(len(book.teach(SWORD, 1)), 0)
    assert_equal(len(book.teach(SWORD, 10)), 9)
    assert_equal(len(book.known(SWORD)), 10)
    assert_equal(len(book.known(AXE)), 0)
    # A master combo is only the specialty's.
    _ = book.teach(AXE, 10)
    for k in book.known(AXE):
        assert_false(book.combos[k].tier == MASTER)
    with assert_raises(contains="specialty"):
        _ = ComboBook(FightingStyle(6))


def test_mastery_ranks_a_combo_up() raises:
    assert_equal(rank_mastery(1), 0)
    assert_equal(rank_mastery(2), 40)
    assert_equal(rank_mastery(5), 400)
    assert_equal(rank_of(0), 1)
    assert_equal(rank_of(39), 1)
    assert_equal(rank_of(40), 2)
    assert_equal(rank_of(10000), MAX_RANK)
    var book = ComboBook(SWORD)
    var index = book.teach(SWORD, 1)[0]
    assert_equal(book.rank(index), 1)
    assert_almost_equal(book.power(index), 1, atol=1e-6)
    assert_false(book.practice(index, 39))
    assert_true(book.practice(index, 1))
    assert_equal(book.rank(index), 2)
    assert_almost_equal(book.power(index), 1 + RANK_POWER, atol=1e-6)
    with assert_raises(contains="negative"):
        _ = book.practice(index, -1)
    with assert_raises(contains="no such"):
        _ = book.rank(-1)
    with assert_raises(contains="no such"):
        _ = book.rank(len(book.combos))


def test_the_book_finds_the_longest_combo_a_string_ends_in() raises:
    var book = ComboBook(SWORD)
    _ = book.teach(SWORD, 10)
    var short = book.match(_string("L H"), SWORD)
    assert_equal(book.combos[short].name, "CROSS CUT")
    var long = book.match(_string("L L L H"), SWORD)
    assert_equal(book.combos[long].name, "TEMPEST")
    assert_equal(book.match(_string("H H H"), SWORD), -1)
    # Another style's combos do not count.
    assert_equal(book.match(_string("L L L L"), SWORD), -1)
    _ = book.teach(HAND_TO_HAND, 3)
    var flurry = book.match(_string("L L L L"), HAND_TO_HAND)
    assert_equal(book.combos[flurry].name, "FLURRY")


def test_an_empty_book_teaches_and_knows_nothing() raises:
    var book = ComboBook(SWORD)
    book.combos = List[Combo]()
    book.learned = List[Bool]()
    book.mastery = List[Int]()
    assert_equal(len(book.teach(SWORD, 99)), 0)
    assert_equal(len(book.known(SWORD)), 0)
    assert_equal(book.match(_string("L H"), SWORD), -1)


def test_every_combo_can_be_made_from_its_keys() raises:
    var styles: List[FightingStyle] = [
        SWORD,
        HAND_TO_HAND,
        AXE,
        MACE,
        MAGIC,
        ARCHERY,
    ]
    for style in styles:
        # The specialty knows every combo of its style.
        var book = ComboBook(style)
        _ = book.teach(style, 10)
        for index in book.known(style):
            ref combo = book.combos[index]
            var tracker = ComboTracker()
            for k in range(len(combo.keys)):
                tracker.press(combo.keys[k], combo.beats[k])
                var found = book.match(tracker, style)
                if k < len(combo.keys) - 1:
                    assert_equal(found, -1)
                else:
                    assert_equal(found, index)


def test_a_tie_goes_to_the_beat_and_a_longer_combo_holds_back() raises:
    var book = ComboBook(SWORD)
    book.combos = [
        Combo("BEAT", SWORD, "L L* H*", HEAVY, EXPERT, 1, 1),
        Combo("PLAIN", SWORD, "L L H", HEAVY, BASIC, 1, 1),
        Combo("SHORT", SWORD, "L H", HEAVY, BASIC, 1, 1),
        Combo("LONG", SWORD, "D L* L* H*", HEAVY, EXPERT, 1, 1),
    ]
    book.learned = [True, True, True, True]
    book.mastery = [0, 0, 0, 0]
    # On the beat, the combo that asks for the beat wins the tie.
    assert_equal(book.match(_string("L L* H*"), SWORD), 0)
    assert_equal(book.match(_string("L L H"), SWORD), 1)
    # With the keys on their way to a longer combo, beats and all, the
    # shorter waits; off the beat, it does not.
    assert_equal(book.match(_string("D L* L* H*"), SWORD), 3)
    assert_equal(book.match(_string("D L* L*"), SWORD), -1)
    book.combos[1] = Combo("PLAIN", SWORD, "L L", HEAVY, BASIC, 1, 1)
    assert_equal(book.match(_string("D L* L*"), SWORD), -1)
    assert_equal(book.match(_string("D L L"), SWORD), 1)


def test_the_book_lists_the_routes_furthest_first() raises:
    var book = ComboBook(SWORD)
    _ = book.teach(SWORD, 10)
    var routes = book.routes(_string("L L"), SWORD)
    assert_true(len(routes) >= 2)
    var tracker = _string("L L")
    var first = tracker.progress(book.combos[routes[0]])
    var last = tracker.progress(book.combos[routes[len(routes) - 1]])
    assert_true(first >= last)
    assert_equal(len(book.routes(_string("H H H"), SWORD)), 0)
    assert_equal(len(book.routes(_string("L"), MAGIC)), 0)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
