# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""The player's progress, kept from one game to the next: the experience
of each skill, what the satchel holds, the mastery of each combo, the
specialty and the style in hand; and the world's: each errand, the spots
used up, where the player stands, the hour and the weather.

A `Progress` packs into bytes: see `pack_progress`. A game writes them to
a file as it ends, and reads them back as it begins, or keeps them
anywhere it likes. The combos that the
player knows are not kept: the levels teach them again.

| Part | Bytes |
|---|---|
| `PROGRESS_MAGIC`, the letters `TMVP` | 4 |
| `PROGRESS_VERSION` | 1 |
| The specialty, then the style in hand | 1 each |
| The count of skills, then each skill's experience | 1, then 4 each |
| The count of things the satchel holds, then each count | 1, then 4 each |
| The count of combos, then each combo's mastery | 1, then 4 each |
| The count of errands, then each errand's state | 1, then 4 each |
| The count of errands, then how many of each are done | 1, then 4 each |
| The count of spots used up, then each spot's place | 1, then 4 each |
| The count of numbers of the place, then each: the player's x and z in centimeters, and the hour in thousandths, each plus `PLACE_SHIFT`, and the weather | 1, then 4 each |

The world's part came with version 2. A record of version 1 reads with no
errand, no spot used up and no place: the game keeps its own.

Each count is a whole number from 0 to `MOST_KEPT`, kept with its lowest
byte first. A record from a game of fewer skills, things or combos reads
with zero for the rest, so a game that adds one reads the records of the
games before it. A record of more, or of a later version, is refused.
"""

from extensions.village.combos import default_combos
from extensions.village.gathering import KINDS
from extensions.village.skills import SKILLS
from extensions.village.styles import SWORD, FightingStyle

comptime PROGRESS_MAGIC = "TMVP"
"""The four letters that begin a packed progress."""
comptime MAGIC_BYTES = 4
"""How many bytes `PROGRESS_MAGIC` takes."""
comptime PROGRESS_VERSION = 2
"""The version of the packing that this module writes."""
comptime PLACE_SHIFT = 1073741824
"""What a packed place adds to each of its numbers, so a negative x or z
packs as a number of zero or more."""
comptime MOST_LISTED = 255
"""The most errands, spots or numbers of a place that a progress lists."""
comptime MOST_KEPT = 2147483647
"""The largest number a packed progress keeps: the largest of four bytes
with a sign."""


struct Progress(Copyable, Movable):
    """What a player keeps from one game to the next."""

    # Each skill's experience, each count of the satchel, and each
    # combo's mastery, in the order of `default_combos`.
    var experience: List[Int]
    var satchel: List[Int]
    var mastery: List[Int]
    # The style the player specializes in, and the style in hand.
    var specialty: FightingStyle
    var style: FightingStyle
    var errands: List[Int]
    """Each speaker's errand state, by its value. Empty keeps the game's."""
    var rounds: List[Int]
    """How many of each speaker's errands are done."""
    var spent: List[Int]
    """The place of each spot that is used up for good: a chest opened, a
    trinket taken."""
    var place: List[Int]
    """The player's x and z, in centimeters, the hour, in thousandths, each
    plus `PLACE_SHIFT`, and the weather's value. Empty keeps the game's."""

    def __init__(out self) raises:
        """Make the progress of a new player: nothing gained, and the sword.

        Raises:
            Error: Never: the combos build.
        """
        self.experience = List[Int](length=SKILLS, fill=0)
        self.satchel = List[Int](length=KINDS, fill=0)
        self.mastery = List[Int](length=len(default_combos()), fill=0)
        self.specialty = SWORD
        self.style = SWORD
        self.errands = List[Int]()
        self.rounds = List[Int]()
        self.spent = List[Int]()
        self.place = List[Int]()

    def check(self) raises:
        """Refuse a progress that this game cannot hold.

        Raises:
            Error: If it has not one experience for each skill, one count
                for each thing and one mastery for each combo; a number is
                not from 0 to `MOST_KEPT`; or the specialty or the style is
                not a style.
        """
        if len(self.experience) != SKILLS:
            raise Error("A progress must have each skill's experience")
        if len(self.satchel) != KINDS:
            raise Error("A progress must have each count of the satchel")
        if len(self.mastery) != len(default_combos()):
            raise Error("A progress must have each combo's mastery")
        var kept = (
            _kept(self.experience)
            and _kept(self.satchel)
            and _kept(self.mastery)
            and _kept(self.errands)
            and _kept(self.rounds)
            and _kept(self.spent)
            and _kept(self.place)
        )
        var longest = max(
            max(len(self.errands), len(self.rounds)),
            max(len(self.spent), len(self.place)),
        )
        if longest > MOST_LISTED:
            raise Error("A progress lists at most 255 of each")
        if len(self.place) != 0 and len(self.place) != 4:
            raise Error("A progress's place is four numbers, or none")
        if not kept:
            raise Error("A progress keeps numbers from 0 to 2,147,483,647")
        if not self.specialty.is_valid() or not self.style.is_valid():
            raise Error("A progress's specialty and style must be styles")


def _kept(group: List[Int]) -> Bool:
    """Return whether each number of a group is from 0 to `MOST_KEPT`."""
    for value in group:
        if not (value >= 0 and value <= MOST_KEPT):
            return False
    return True


def _magic() -> List[UInt8]:
    """Return the bytes of `PROGRESS_MAGIC`: T, M, V and P."""
    return [UInt8(84), UInt8(77), UInt8(86), UInt8(80)]


def _put(mut out: List[UInt8], value: Int):
    """Append a number's four bytes, the lowest first."""
    for k in range(4):
        out.append(UInt8((value >> (8 * k)) & 0xFF))


def _get(bytes: List[UInt8], at: Int) -> Int:
    """Read four bytes from `at` as a number, the lowest first."""
    var value = 0
    for k in range(4):
        value |= Int(bytes[at + k]) << (8 * k)
    return value


def _put_group(mut out: List[UInt8], group: List[Int]):
    """Append a group's count and its numbers."""
    out.append(UInt8(len(group)))
    for value in group:
        _put(out, value)


def pack_progress(progress: Progress) raises -> List[UInt8]:
    """Pack a player's progress: see the module's table.

    Args:
        progress: The progress.

    Returns:
        Its bytes.

    Raises:
        Error: If `Progress.check` refuses it.
    """
    progress.check()
    var out = _magic()
    out.append(UInt8(PROGRESS_VERSION))
    out.append(UInt8(progress.specialty.value))
    out.append(UInt8(progress.style.value))
    _put_group(out, progress.experience)
    _put_group(out, progress.satchel)
    _put_group(out, progress.mastery)
    _put_group(out, progress.errands)
    _put_group(out, progress.rounds)
    _put_group(out, progress.spent)
    _put_group(out, progress.place)
    return out^


def _read_group(
    bytes: List[UInt8], mut at: Int, mut group: List[Int], name: String
) raises:
    """Read a group's count and its numbers from `at` into `group`, and move
    `at` past them. A shorter group leaves the rest of `group` as it is."""
    if at >= len(bytes):
        raise Error("A packed progress ends before its " + name)
    var count = Int(bytes[at])
    at += 1
    if count > len(group):
        raise Error("A packed progress has more " + name + " than this game")
    if at + 4 * count > len(bytes):
        raise Error("A packed progress ends before its " + name)
    for k in range(count):
        group[k] = _get(bytes, at + 4 * k)
    at += 4 * count


def _read_list(
    bytes: List[UInt8], mut at: Int, name: String
) raises -> List[Int]:
    """Read a list's count and its numbers from `at`, and move `at` past
    them."""
    if at >= len(bytes):
        raise Error("A packed progress ends before its " + name)
    var count = Int(bytes[at])
    at += 1
    if at + 4 * count > len(bytes):
        raise Error("A packed progress ends before its " + name)
    var out = List[Int]()
    for k in range(count):
        out.append(_get(bytes, at + 4 * k))
    at += 4 * count
    return out^


def unpack_progress(bytes: List[UInt8]) raises -> Progress:
    """Read a player's progress from its bytes.

    Args:
        bytes: The bytes, from `pack_progress`.

    Returns:
        The progress. A group shorter than this game's reads with zero for
        the rest.

    Raises:
        Error: If the bytes do not begin with `PROGRESS_MAGIC`, are of a
            version before 1 or after this one, end early or go on after the progress, hold more
            skills, things or combos than this game, or hold a progress
            that `Progress.check` refuses.
    """
    if len(bytes) < MAGIC_BYTES + 3:
        raise Error("A packed progress is too short")
    var magic = _magic()
    for k in range(MAGIC_BYTES):  # pragma: no branch
        if bytes[k] != magic[k]:
            raise Error("A packed progress must begin with TMVP")
    var version = Int(bytes[MAGIC_BYTES])
    if not (version >= 1 and version <= PROGRESS_VERSION):
        raise Error("A packed progress is of a version this game cannot read")
    var out = Progress()
    out.specialty = FightingStyle(Int(bytes[MAGIC_BYTES + 1]))
    out.style = FightingStyle(Int(bytes[MAGIC_BYTES + 2]))
    var at = MAGIC_BYTES + 3
    _read_group(bytes, at, out.experience, "skills")
    _read_group(bytes, at, out.satchel, "things")
    _read_group(bytes, at, out.mastery, "combos")
    if version >= 2:
        out.errands = _read_list(bytes, at, "errands")
        out.rounds = _read_list(bytes, at, "errands")
        out.spent = _read_list(bytes, at, "spots")
        out.place = _read_list(bytes, at, "place")
    if at != len(bytes):
        raise Error("A packed progress goes on after its end")
    out.check()
    return out^
