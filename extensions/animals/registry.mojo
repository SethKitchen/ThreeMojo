# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""The species, and what each one supplies to the build.

Each species module supplies the same nine things: its morphs, a
variation, a rig, a sculpt, an eye, an eye look, a palette, a painter
and a base cell size. This module picks the module a `SpeciesId` names.
"""

from extensions.animals.coat import CoatSample, EyeLook, Paint, Palette
from extensions.animals.kit import EyeSpec
from extensions.animals.options import AnimalOptions, AnimalRandom
from extensions.animals.rig import Rig
from extensions.sdf.field import SdfModel
from extensions.animals.species.bear import (
    CELL as BEAR_CELL,
    HEAD_O as BEAR_HEAD,
    bear_eye,
    bear_look,
    bear_paint,
    bear_palette,
    bear_rig,
    bear_sculpt,
    bear_traits,
    bear_variant_names,
)
from extensions.animals.species.boar import (
    CELL as BOAR_CELL,
    HEAD_O as BOAR_HEAD,
    boar_eye,
    boar_look,
    boar_paint,
    boar_palette,
    boar_rig,
    boar_sculpt,
    boar_traits,
    boar_variant_names,
)
from extensions.animals.species.cat import (
    CELL as CAT_CELL,
    HEAD_O as CAT_HEAD,
    cat_eye,
    cat_look,
    cat_paint,
    cat_palette,
    cat_rig,
    cat_sculpt,
    cat_traits,
    cat_variant_names,
)
from extensions.animals.species.cheetah import (
    CELL as CHEETAH_CELL,
    HEAD_O as CHEETAH_HEAD,
    cheetah_eye,
    cheetah_look,
    cheetah_paint,
    cheetah_palette,
    cheetah_rig,
    cheetah_sculpt,
    cheetah_traits,
    cheetah_variant_names,
)
from extensions.animals.species.chicken import (
    CELL as CHICKEN_CELL,
    HEAD_O as CHICKEN_HEAD,
    chicken_eye,
    chicken_look,
    chicken_paint,
    chicken_palette,
    chicken_rig,
    chicken_sculpt,
    chicken_traits,
    chicken_variant_names,
)
from extensions.animals.species.cow import (
    CELL as COW_CELL,
    HEAD_O as COW_HEAD,
    cow_eye,
    cow_look,
    cow_paint,
    cow_palette,
    cow_rig,
    cow_sculpt,
    cow_traits,
    cow_variant_names,
)
from extensions.animals.species.crow import (
    CELL as CROW_CELL,
    HEAD_O as CROW_HEAD,
    crow_eye,
    crow_look,
    crow_paint,
    crow_palette,
    crow_rig,
    crow_sculpt,
    crow_traits,
    crow_variant_names,
)
from extensions.animals.species.deer import (
    CELL as DEER_CELL,
    HEAD_O as DEER_HEAD,
    deer_eye,
    deer_look,
    deer_paint,
    deer_palette,
    deer_rig,
    deer_sculpt,
    deer_traits,
    deer_variant_names,
)
from extensions.animals.species.dog import (
    CELL as DOG_CELL,
    HEAD_O as DOG_HEAD,
    dog_eye,
    dog_look,
    dog_paint,
    dog_palette,
    dog_rig,
    dog_sculpt,
    dog_traits,
    dog_variant_names,
)
from extensions.animals.species.eagle import (
    CELL as EAGLE_CELL,
    HEAD_O as EAGLE_HEAD,
    eagle_eye,
    eagle_look,
    eagle_paint,
    eagle_palette,
    eagle_rig,
    eagle_sculpt,
    eagle_traits,
    eagle_variant_names,
)
from extensions.animals.species.fish import (
    CELL as FISH_CELL,
    HEAD_O as FISH_HEAD,
    fish_eye,
    fish_look,
    fish_paint,
    fish_palette,
    fish_rig,
    fish_sculpt,
    fish_traits,
    fish_variant_names,
)
from extensions.animals.species.fox import (
    CELL as FOX_CELL,
    HEAD_O as FOX_HEAD,
    fox_eye,
    fox_look,
    fox_paint,
    fox_palette,
    fox_rig,
    fox_sculpt,
    fox_traits,
    fox_variant_names,
)
from extensions.animals.species.frog import (
    CELL as FROG_CELL,
    HEAD_O as FROG_HEAD,
    frog_eye,
    frog_look,
    frog_paint,
    frog_palette,
    frog_rig,
    frog_sculpt,
    frog_traits,
    frog_variant_names,
)
from extensions.animals.species.goat import (
    CELL as GOAT_CELL,
    HEAD_O as GOAT_HEAD,
    goat_eye,
    goat_look,
    goat_paint,
    goat_palette,
    goat_rig,
    goat_sculpt,
    goat_traits,
    goat_variant_names,
)
from extensions.animals.species.horse import (
    CELL as HORSE_CELL,
    HEAD_O as HORSE_HEAD,
    horse_eye,
    horse_look,
    horse_paint,
    horse_palette,
    horse_rig,
    horse_sculpt,
    horse_traits,
    horse_variant_names,
)
from extensions.animals.species.lion import (
    CELL as LION_CELL,
    HEAD_O as LION_HEAD,
    lion_eye,
    lion_look,
    lion_paint,
    lion_palette,
    lion_rig,
    lion_sculpt,
    lion_traits,
    lion_variant_names,
)
from extensions.animals.species.pig import (
    CELL as PIG_CELL,
    HEAD_O as PIG_HEAD,
    pig_eye,
    pig_look,
    pig_paint,
    pig_palette,
    pig_rig,
    pig_sculpt,
    pig_traits,
    pig_variant_names,
)
from extensions.animals.species.rabbit import (
    CELL as RABBIT_CELL,
    HEAD_O as RABBIT_HEAD,
    rabbit_eye,
    rabbit_look,
    rabbit_paint,
    rabbit_palette,
    rabbit_rig,
    rabbit_sculpt,
    rabbit_traits,
    rabbit_variant_names,
)
from extensions.animals.species.rat import (
    CELL as RAT_CELL,
    HEAD_O as RAT_HEAD,
    rat_eye,
    rat_look,
    rat_paint,
    rat_palette,
    rat_rig,
    rat_sculpt,
    rat_traits,
    rat_variant_names,
)
from extensions.animals.species.shark import (
    CELL as SHARK_CELL,
    HEAD_O as SHARK_HEAD,
    shark_eye,
    shark_look,
    shark_paint,
    shark_palette,
    shark_rig,
    shark_sculpt,
    shark_traits,
    shark_variant_names,
)
from extensions.animals.species.sheep import (
    CELL as SHEEP_CELL,
    HEAD_O as SHEEP_HEAD,
    sheep_eye,
    sheep_look,
    sheep_paint,
    sheep_palette,
    sheep_rig,
    sheep_sculpt,
    sheep_traits,
    sheep_variant_names,
)
from extensions.animals.species.snake import (
    CELL as SNAKE_CELL,
    HEAD_O as SNAKE_HEAD,
    snake_eye,
    snake_look,
    snake_paint,
    snake_palette,
    snake_rig,
    snake_sculpt,
    snake_traits,
    snake_variant_names,
)
from extensions.animals.species.spider import (
    CELL as SPIDER_CELL,
    HEAD_O as SPIDER_HEAD,
    spider_eye,
    spider_look,
    spider_paint,
    spider_palette,
    spider_rig,
    spider_sculpt,
    spider_traits,
    spider_variant_names,
)
from extensions.animals.species.wolf import (
    CELL as WOLF_CELL,
    HEAD_O as WOLF_HEAD,
    wolf_eye,
    wolf_look,
    wolf_paint,
    wolf_palette,
    wolf_rig,
    wolf_sculpt,
    wolf_traits,
    wolf_variant_names,
)
from extensions.animals.traits import Traits
from extensions.sdf.vector import V3

# How many species there are.
comptime SPECIES_COUNT = 24


@fieldwise_init
struct SpeciesId(Equatable, ImplicitlyCopyable, Writable):
    """Which species an animal is. The order is procedural-animals'."""

    var value: Int

    def is_valid(self) -> Bool:
        """Return True if this names one of the species.

        Returns:
            Whether the value is from zero to `SPECIES_COUNT - 1`.
        """
        return self.value >= 0 and self.value < SPECIES_COUNT


comptime BEAR = SpeciesId(0)
comptime BOAR = SpeciesId(1)
comptime CAT = SpeciesId(2)
comptime CHEETAH = SpeciesId(3)
comptime CHICKEN = SpeciesId(4)
comptime COW = SpeciesId(5)
comptime CROW = SpeciesId(6)
comptime DEER = SpeciesId(7)
comptime DOG = SpeciesId(8)
comptime EAGLE = SpeciesId(9)
comptime FISH = SpeciesId(10)
comptime FOX = SpeciesId(11)
comptime FROG = SpeciesId(12)
comptime GOAT = SpeciesId(13)
comptime HORSE = SpeciesId(14)
comptime LION = SpeciesId(15)
comptime PIG = SpeciesId(16)
comptime RABBIT = SpeciesId(17)
comptime RAT = SpeciesId(18)
comptime SHARK = SpeciesId(19)
comptime SHEEP = SpeciesId(20)
comptime SNAKE = SpeciesId(21)
comptime SPIDER = SpeciesId(22)
comptime WOLF = SpeciesId(23)


def require_species(id: SpeciesId) raises:
    """Refuse a species id that names no species.

    Args:
        id: The species.

    Raises:
        Error: If `id` is not valid.
    """
    if not id.is_valid():
        raise Error("Species id names no species")


def species_names() -> List[String]:
    """Return every species' common name, in `SpeciesId` order.

    Returns:
        The names.
    """
    return [
        String("bear"),
        String("boar"),
        String("cat"),
        String("cheetah"),
        String("chicken"),
        String("cow"),
        String("crow"),
        String("deer"),
        String("dog"),
        String("eagle"),
        String("fish"),
        String("fox"),
        String("frog"),
        String("goat"),
        String("horse"),
        String("lion"),
        String("pig"),
        String("rabbit"),
        String("rat"),
        String("shark"),
        String("sheep"),
        String("snake"),
        String("spider"),
        String("wolf"),
    ]


def species_name(id: SpeciesId) raises -> String:
    """Return a species' common name.

    Args:
        id: The species.

    Returns:
        Its name, such as `wolf`.

    Raises:
        Error: If `id` is not valid.
    """
    require_species(id)
    return species_names()[id.value]


def species_of(name: String) raises -> SpeciesId:
    """Return the species a common name names.

    Args:
        name: The name, such as `wolf`.

    Returns:
        The species.

    Raises:
        Error: If no species has that name.
    """
    var names = species_names()
    for i in range(len(names)):  # pragma: no branch
        if names[i] == name:
            return SpeciesId(i)
    raise Error("No species is named " + name)


def species_variants(id: SpeciesId) raises -> List[String]:
    """Return a species' color morphs, in the order `Variant` indexes.

    Args:
        id: The species.

    Returns:
        The morph names.

    Raises:
        Error: If `id` is not valid, or the species refuses its input.
    """
    require_species(id)
    if id.value == 0:
        return bear_variant_names()
    elif id.value == 1:
        return boar_variant_names()
    elif id.value == 2:
        return cat_variant_names()
    elif id.value == 3:
        return cheetah_variant_names()
    elif id.value == 4:
        return chicken_variant_names()
    elif id.value == 5:
        return cow_variant_names()
    elif id.value == 6:
        return crow_variant_names()
    elif id.value == 7:
        return deer_variant_names()
    elif id.value == 8:
        return dog_variant_names()
    elif id.value == 9:
        return eagle_variant_names()
    elif id.value == 10:
        return fish_variant_names()
    elif id.value == 11:
        return fox_variant_names()
    elif id.value == 12:
        return frog_variant_names()
    elif id.value == 13:
        return goat_variant_names()
    elif id.value == 14:
        return horse_variant_names()
    elif id.value == 15:
        return lion_variant_names()
    elif id.value == 16:
        return pig_variant_names()
    elif id.value == 17:
        return rabbit_variant_names()
    elif id.value == 18:
        return rat_variant_names()
    elif id.value == 19:
        return shark_variant_names()
    elif id.value == 20:
        return sheep_variant_names()
    elif id.value == 21:
        return snake_variant_names()
    elif id.value == 22:
        return spider_variant_names()
    return wolf_variant_names()


def species_traits(
    id: SpeciesId, mut r: AnimalRandom, options: AnimalOptions
) raises -> Traits:
    """Draw one individual of a species.

    Args:
        id: The species.
        r: The individual's stream.
        options: The caller's options.

    Returns:
        The traits.

    Raises:
        Error: If `id` is not valid, or the species refuses its input.
    """
    require_species(id)
    if id.value == 0:
        return bear_traits(r, options)
    elif id.value == 1:
        return boar_traits(r, options)
    elif id.value == 2:
        return cat_traits(r, options)
    elif id.value == 3:
        return cheetah_traits(r, options)
    elif id.value == 4:
        return chicken_traits(r, options)
    elif id.value == 5:
        return cow_traits(r, options)
    elif id.value == 6:
        return crow_traits(r, options)
    elif id.value == 7:
        return deer_traits(r, options)
    elif id.value == 8:
        return dog_traits(r, options)
    elif id.value == 9:
        return eagle_traits(r, options)
    elif id.value == 10:
        return fish_traits(r, options)
    elif id.value == 11:
        return fox_traits(r, options)
    elif id.value == 12:
        return frog_traits(r, options)
    elif id.value == 13:
        return goat_traits(r, options)
    elif id.value == 14:
        return horse_traits(r, options)
    elif id.value == 15:
        return lion_traits(r, options)
    elif id.value == 16:
        return pig_traits(r, options)
    elif id.value == 17:
        return rabbit_traits(r, options)
    elif id.value == 18:
        return rat_traits(r, options)
    elif id.value == 19:
        return shark_traits(r, options)
    elif id.value == 20:
        return sheep_traits(r, options)
    elif id.value == 21:
        return snake_traits(r, options)
    elif id.value == 22:
        return spider_traits(r, options)
    return wolf_traits(r, options)


def species_rig(id: SpeciesId, t: Traits) raises -> Rig:
    """Return a species' skeleton in bind pose.

    Args:
        id: The species.
        t: The individual.

    Returns:
        The rig.

    Raises:
        Error: If `id` is not valid, or the species refuses its input.
    """
    require_species(id)
    if id.value == 0:
        return bear_rig(t)
    elif id.value == 1:
        return boar_rig(t)
    elif id.value == 2:
        return cat_rig(t)
    elif id.value == 3:
        return cheetah_rig(t)
    elif id.value == 4:
        return chicken_rig(t)
    elif id.value == 5:
        return cow_rig(t)
    elif id.value == 6:
        return crow_rig(t)
    elif id.value == 7:
        return deer_rig(t)
    elif id.value == 8:
        return dog_rig(t)
    elif id.value == 9:
        return eagle_rig(t)
    elif id.value == 10:
        return fish_rig(t)
    elif id.value == 11:
        return fox_rig(t)
    elif id.value == 12:
        return frog_rig(t)
    elif id.value == 13:
        return goat_rig(t)
    elif id.value == 14:
        return horse_rig(t)
    elif id.value == 15:
        return lion_rig(t)
    elif id.value == 16:
        return pig_rig(t)
    elif id.value == 17:
        return rabbit_rig(t)
    elif id.value == 18:
        return rat_rig(t)
    elif id.value == 19:
        return shark_rig(t)
    elif id.value == 20:
        return sheep_rig(t)
    elif id.value == 21:
        return snake_rig(t)
    elif id.value == 22:
        return spider_rig(t)
    return wolf_rig(t)


def species_sculpt(id: SpeciesId, mut m: SdfModel, rig: Rig, t: Traits) raises:
    """Sculpt one individual of a species.

    Args:
        id: The species.
        m: The sculpt to add to.
        rig: The individual's reference rig.
        t: The individual.

    Raises:
        Error: If `id` is not valid, or the species refuses its input.
    """
    require_species(id)
    if id.value == 0:
        bear_sculpt(m, rig, t)
    elif id.value == 1:
        boar_sculpt(m, rig, t)
    elif id.value == 2:
        cat_sculpt(m, rig, t)
    elif id.value == 3:
        cheetah_sculpt(m, rig, t)
    elif id.value == 4:
        chicken_sculpt(m, rig, t)
    elif id.value == 5:
        cow_sculpt(m, rig, t)
    elif id.value == 6:
        crow_sculpt(m, rig, t)
    elif id.value == 7:
        deer_sculpt(m, rig, t)
    elif id.value == 8:
        dog_sculpt(m, rig, t)
    elif id.value == 9:
        eagle_sculpt(m, rig, t)
    elif id.value == 10:
        fish_sculpt(m, rig, t)
    elif id.value == 11:
        fox_sculpt(m, rig, t)
    elif id.value == 12:
        frog_sculpt(m, rig, t)
    elif id.value == 13:
        goat_sculpt(m, rig, t)
    elif id.value == 14:
        horse_sculpt(m, rig, t)
    elif id.value == 15:
        lion_sculpt(m, rig, t)
    elif id.value == 16:
        pig_sculpt(m, rig, t)
    elif id.value == 17:
        rabbit_sculpt(m, rig, t)
    elif id.value == 18:
        rat_sculpt(m, rig, t)
    elif id.value == 19:
        shark_sculpt(m, rig, t)
    elif id.value == 20:
        sheep_sculpt(m, rig, t)
    elif id.value == 21:
        snake_sculpt(m, rig, t)
    elif id.value == 22:
        spider_sculpt(m, rig, t)
    else:
        wolf_sculpt(m, rig, t)


def species_head_origin(id: SpeciesId) raises -> V3:
    """Return where a species' head-local frame sits.

    Args:
        id: The species.

    Returns:
        The head origin in reference space.

    Raises:
        Error: If `id` is not valid, or the species refuses its input.
    """
    require_species(id)
    if id.value == 0:
        return BEAR_HEAD
    elif id.value == 1:
        return BOAR_HEAD
    elif id.value == 2:
        return CAT_HEAD
    elif id.value == 3:
        return CHEETAH_HEAD
    elif id.value == 4:
        return CHICKEN_HEAD
    elif id.value == 5:
        return COW_HEAD
    elif id.value == 6:
        return CROW_HEAD
    elif id.value == 7:
        return DEER_HEAD
    elif id.value == 8:
        return DOG_HEAD
    elif id.value == 9:
        return EAGLE_HEAD
    elif id.value == 10:
        return FISH_HEAD
    elif id.value == 11:
        return FOX_HEAD
    elif id.value == 12:
        return FROG_HEAD
    elif id.value == 13:
        return GOAT_HEAD
    elif id.value == 14:
        return HORSE_HEAD
    elif id.value == 15:
        return LION_HEAD
    elif id.value == 16:
        return PIG_HEAD
    elif id.value == 17:
        return RABBIT_HEAD
    elif id.value == 18:
        return RAT_HEAD
    elif id.value == 19:
        return SHARK_HEAD
    elif id.value == 20:
        return SHEEP_HEAD
    elif id.value == 21:
        return SNAKE_HEAD
    elif id.value == 22:
        return SPIDER_HEAD
    return WOLF_HEAD


def species_eye(id: SpeciesId, t: Traits) raises -> EyeSpec:
    """Return a species' left eye.

    Args:
        id: The species.
        t: The individual.

    Returns:
        The eye, head-local.

    Raises:
        Error: If `id` is not valid, or the species refuses its input.
    """
    require_species(id)
    if id.value == 0:
        return bear_eye(t)
    elif id.value == 1:
        return boar_eye(t)
    elif id.value == 2:
        return cat_eye(t)
    elif id.value == 3:
        return cheetah_eye(t)
    elif id.value == 4:
        return chicken_eye(t)
    elif id.value == 5:
        return cow_eye(t)
    elif id.value == 6:
        return crow_eye(t)
    elif id.value == 7:
        return deer_eye(t)
    elif id.value == 8:
        return dog_eye(t)
    elif id.value == 9:
        return eagle_eye(t)
    elif id.value == 10:
        return fish_eye(t)
    elif id.value == 11:
        return fox_eye(t)
    elif id.value == 12:
        return frog_eye(t)
    elif id.value == 13:
        return goat_eye(t)
    elif id.value == 14:
        return horse_eye(t)
    elif id.value == 15:
        return lion_eye(t)
    elif id.value == 16:
        return pig_eye(t)
    elif id.value == 17:
        return rabbit_eye(t)
    elif id.value == 18:
        return rat_eye(t)
    elif id.value == 19:
        return shark_eye(t)
    elif id.value == 20:
        return sheep_eye(t)
    elif id.value == 21:
        return snake_eye(t)
    elif id.value == 22:
        return spider_eye(t)
    return wolf_eye(t)


def species_look(id: SpeciesId, t: Traits) raises -> EyeLook:
    """Return a species' eye colors.

    Args:
        id: The species.
        t: The individual.

    Returns:
        The look.

    Raises:
        Error: If `id` is not valid, or the species refuses its input.
    """
    require_species(id)
    if id.value == 0:
        return bear_look(t)
    elif id.value == 1:
        return boar_look(t)
    elif id.value == 2:
        return cat_look(t)
    elif id.value == 3:
        return cheetah_look(t)
    elif id.value == 4:
        return chicken_look(t)
    elif id.value == 5:
        return cow_look(t)
    elif id.value == 6:
        return crow_look(t)
    elif id.value == 7:
        return deer_look(t)
    elif id.value == 8:
        return dog_look(t)
    elif id.value == 9:
        return eagle_look(t)
    elif id.value == 10:
        return fish_look(t)
    elif id.value == 11:
        return fox_look(t)
    elif id.value == 12:
        return frog_look(t)
    elif id.value == 13:
        return goat_look(t)
    elif id.value == 14:
        return horse_look(t)
    elif id.value == 15:
        return lion_look(t)
    elif id.value == 16:
        return pig_look(t)
    elif id.value == 17:
        return rabbit_look(t)
    elif id.value == 18:
        return rat_look(t)
    elif id.value == 19:
        return shark_look(t)
    elif id.value == 20:
        return sheep_look(t)
    elif id.value == 21:
        return snake_look(t)
    elif id.value == 22:
        return spider_look(t)
    return wolf_look(t)


def species_palette(id: SpeciesId, t: Traits) raises -> Palette:
    """Return one individual's palette.

    Args:
        id: The species.
        t: The individual.

    Returns:
        The palette.

    Raises:
        Error: If `id` is not valid, or the species refuses its input.
    """
    require_species(id)
    if id.value == 0:
        return bear_palette(t)
    elif id.value == 1:
        return boar_palette(t)
    elif id.value == 2:
        return cat_palette(t)
    elif id.value == 3:
        return cheetah_palette(t)
    elif id.value == 4:
        return chicken_palette(t)
    elif id.value == 5:
        return cow_palette(t)
    elif id.value == 6:
        return crow_palette(t)
    elif id.value == 7:
        return deer_palette(t)
    elif id.value == 8:
        return dog_palette(t)
    elif id.value == 9:
        return eagle_palette(t)
    elif id.value == 10:
        return fish_palette(t)
    elif id.value == 11:
        return fox_palette(t)
    elif id.value == 12:
        return frog_palette(t)
    elif id.value == 13:
        return goat_palette(t)
    elif id.value == 14:
        return horse_palette(t)
    elif id.value == 15:
        return lion_palette(t)
    elif id.value == 16:
        return pig_palette(t)
    elif id.value == 17:
        return rabbit_palette(t)
    elif id.value == 18:
        return rat_palette(t)
    elif id.value == 19:
        return shark_palette(t)
    elif id.value == 20:
        return sheep_palette(t)
    elif id.value == 21:
        return snake_palette(t)
    elif id.value == 22:
        return spider_palette(t)
    return wolf_palette(t)


def species_paint(
    id: SpeciesId,
    pal: Palette,
    t: Traits,
    tag: String,
    bone: String,
    s: CoatSample,
) raises -> Paint:
    """Paint one vertex of a species.

    Args:
        id: The species.
        pal: The individual's palette.
        t: The individual.
        tag: The tag of the solid the vertex lies on.
        bone: The bone that solid rides.
        s: The vertex.

    Returns:
        The paint.

    Raises:
        Error: If `id` is not valid, or the species refuses its input.
    """
    require_species(id)
    if id.value == 0:
        return bear_paint(pal, t, tag, bone, s)
    elif id.value == 1:
        return boar_paint(pal, t, tag, bone, s)
    elif id.value == 2:
        return cat_paint(pal, t, tag, bone, s)
    elif id.value == 3:
        return cheetah_paint(pal, t, tag, bone, s)
    elif id.value == 4:
        return chicken_paint(pal, t, tag, bone, s)
    elif id.value == 5:
        return cow_paint(pal, t, tag, bone, s)
    elif id.value == 6:
        return crow_paint(pal, t, tag, bone, s)
    elif id.value == 7:
        return deer_paint(pal, t, tag, bone, s)
    elif id.value == 8:
        return dog_paint(pal, t, tag, bone, s)
    elif id.value == 9:
        return eagle_paint(pal, t, tag, bone, s)
    elif id.value == 10:
        return fish_paint(pal, t, tag, bone, s)
    elif id.value == 11:
        return fox_paint(pal, t, tag, bone, s)
    elif id.value == 12:
        return frog_paint(pal, t, tag, bone, s)
    elif id.value == 13:
        return goat_paint(pal, t, tag, bone, s)
    elif id.value == 14:
        return horse_paint(pal, t, tag, bone, s)
    elif id.value == 15:
        return lion_paint(pal, t, tag, bone, s)
    elif id.value == 16:
        return pig_paint(pal, t, tag, bone, s)
    elif id.value == 17:
        return rabbit_paint(pal, t, tag, bone, s)
    elif id.value == 18:
        return rat_paint(pal, t, tag, bone, s)
    elif id.value == 19:
        return shark_paint(pal, t, tag, bone, s)
    elif id.value == 20:
        return sheep_paint(pal, t, tag, bone, s)
    elif id.value == 21:
        return snake_paint(pal, t, tag, bone, s)
    elif id.value == 22:
        return spider_paint(pal, t, tag, bone, s)
    return wolf_paint(pal, t, tag, bone, s)


def species_cell(id: SpeciesId) raises -> Float64:
    """Return a species' finest cell size, at the `HERO` tier.

    Args:
        id: The species.

    Returns:
        The cell size in meters, for the reference adult.

    Raises:
        Error: If `id` is not valid, or the species refuses its input.
    """
    require_species(id)
    if id.value == 0:
        return BEAR_CELL
    elif id.value == 1:
        return BOAR_CELL
    elif id.value == 2:
        return CAT_CELL
    elif id.value == 3:
        return CHEETAH_CELL
    elif id.value == 4:
        return CHICKEN_CELL
    elif id.value == 5:
        return COW_CELL
    elif id.value == 6:
        return CROW_CELL
    elif id.value == 7:
        return DEER_CELL
    elif id.value == 8:
        return DOG_CELL
    elif id.value == 9:
        return EAGLE_CELL
    elif id.value == 10:
        return FISH_CELL
    elif id.value == 11:
        return FOX_CELL
    elif id.value == 12:
        return FROG_CELL
    elif id.value == 13:
        return GOAT_CELL
    elif id.value == 14:
        return HORSE_CELL
    elif id.value == 15:
        return LION_CELL
    elif id.value == 16:
        return PIG_CELL
    elif id.value == 17:
        return RABBIT_CELL
    elif id.value == 18:
        return RAT_CELL
    elif id.value == 19:
        return SHARK_CELL
    elif id.value == 20:
        return SHEEP_CELL
    elif id.value == 21:
        return SNAKE_CELL
    elif id.value == 22:
        return SPIDER_CELL
    return WOLF_CELL
