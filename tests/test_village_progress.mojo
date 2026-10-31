# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""The player's progress: what it keeps, how it packs into bytes, and the
records it refuses."""

from extensions.village.combos import default_combos
from extensions.village.gathering import KINDS
from extensions.village.progress import (
    MAGIC_BYTES,
    MOST_KEPT,
    PROGRESS_VERSION,
    Progress,
    pack_progress,
    unpack_progress,
)
from extensions.village.skills import SKILLS
from extensions.village.styles import ARCHERY, MAGIC, SWORD, FightingStyle
from std.testing import (
    TestSuite,
    assert_equal,
    assert_raises,
    assert_true,
)


def _gained() raises -> Progress:
    """Return a progress with something in each group."""
    var p = Progress()
    p.experience[0] = 120
    p.experience[SKILLS - 1] = MOST_KEPT
    p.satchel[2] = 7
    p.mastery[3] = 400
    p.specialty = MAGIC
    p.style = ARCHERY
    return p^


def test_a_new_player_has_gained_nothing() raises:
    var p = Progress()
    p.check()
    assert_equal(len(p.experience), SKILLS)
    assert_equal(len(p.satchel), KINDS)
    assert_equal(len(p.mastery), len(default_combos()))
    assert_true(p.specialty == SWORD)
    assert_true(p.style == SWORD)


def test_a_progress_packs_and_comes_back() raises:
    var p = _gained()
    var bytes = pack_progress(p)
    var groups = SKILLS + KINDS + len(default_combos())
    assert_equal(len(bytes), MAGIC_BYTES + 3 + 3 + 4 * groups)
    assert_equal(Int(bytes[0]), 84)
    assert_equal(Int(bytes[MAGIC_BYTES]), PROGRESS_VERSION)
    var back = unpack_progress(bytes)
    assert_equal(back.experience[0], 120)
    assert_equal(back.experience[SKILLS - 1], MOST_KEPT)
    assert_equal(back.satchel[2], 7)
    assert_equal(back.mastery[3], 400)
    assert_true(back.specialty == MAGIC)
    assert_true(back.style == ARCHERY)


def test_an_older_record_reads_with_zero_for_the_rest() raises:
    var p = _gained()
    var bytes = pack_progress(p)
    # The same record, from a game that had no combos yet.
    var at = MAGIC_BYTES + 3 + 2 + 4 * (SKILLS + KINDS)
    var older = List[UInt8]()
    for k in range(at):
        older.append(bytes[k])
    older.append(0)
    var back = unpack_progress(older)
    assert_equal(back.experience[0], 120)
    assert_equal(back.mastery[3], 0)
    assert_equal(len(back.mastery), len(default_combos()))


def test_a_progress_refuses_what_it_cannot_hold() raises:
    var short = Progress()
    _ = short.experience.pop()
    with assert_raises(contains="skill"):
        short.check()
    var poor = Progress()
    _ = poor.satchel.pop()
    with assert_raises(contains="satchel"):
        poor.check()
    var unlearned = Progress()
    _ = unlearned.mastery.pop()
    with assert_raises(contains="combo"):
        unlearned.check()
    for group in range(3):
        var bad = Progress()
        if group == 0:
            bad.experience[1] = -1
        elif group == 1:
            bad.satchel[1] = MOST_KEPT + 1
        else:
            bad.mastery[1] = -5
        with assert_raises(contains="2,147,483,647"):
            _ = pack_progress(bad)
    var odd = Progress()
    odd.specialty = FightingStyle(6)
    with assert_raises(contains="styles"):
        odd.check()
    odd = Progress()
    odd.style = FightingStyle(-1)
    with assert_raises(contains="styles"):
        odd.check()


def test_a_packed_progress_refuses_bad_bytes() raises:
    var good = pack_progress(_gained())
    with assert_raises(contains="too short"):
        _ = unpack_progress([UInt8(84), UInt8(77)])
    var wrong = good.copy()
    wrong[1] = 0
    with assert_raises(contains="TMVP"):
        _ = unpack_progress(wrong)
    for version in [0, PROGRESS_VERSION + 1]:
        var later = good.copy()
        later[MAGIC_BYTES] = UInt8(version)
        with assert_raises(contains="version"):
            _ = unpack_progress(later)
    # It ends in the middle of a group, or before one.
    var cut = good.copy()
    _ = cut.pop()
    with assert_raises(contains="ends before its combos"):
        _ = unpack_progress(cut)
    var header = List[UInt8]()
    for k in range(MAGIC_BYTES + 3):
        header.append(good[k])
    with assert_raises(contains="ends before its skills"):
        _ = unpack_progress(header)
    # More skills than this game has.
    var more = good.copy()
    more[MAGIC_BYTES + 3] = UInt8(SKILLS + 1)
    with assert_raises(contains="more skills"):
        _ = unpack_progress(more)
    # Bytes after the combos.
    var long = good.copy()
    long.append(0)
    with assert_raises(contains="goes on"):
        _ = unpack_progress(long)
    # A style that is not one.
    var styled = good.copy()
    styled[MAGIC_BYTES + 1] = 9
    with assert_raises(contains="styles"):
        _ = unpack_progress(styled)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
