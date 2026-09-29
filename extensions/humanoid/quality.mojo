# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""How finely a humanoid is meshed, as one named level.

A quality level sets how many triangles one humanoid holds. It sets two
things. The three `detail` values set how finely an assembly such as
`add_body` samples each solid. The triangle budget sets how many
triangles `fit_triangle_budget` then keeps for the whole body.

| Level    | Anatomy | Body skin | Hand skin | Triangle budget |
|----------|---------|-----------|-----------|-----------------|
| `LOW`    | 8       | 32        | 24        | 90,000          |
| `MEDIUM` | 10      | 40        | 32        | 200,000         |
| `HIGH`   | 12      | 48        | 40        | 450,000         |
| `XHIGH`  | 16      | 56        | 48        | 1,000,000       |

    var level = quality_named("medium")
    var first = len(scene.meshes)
    _ = add_body(scene, assets, parent, person, bone, cartilage,
        cartilage, ligament, muscle, tendon, BOTH,
        anatomy_detail(level), skin_detail(level),
        hand_skin_detail(level))
    fit_triangle_budget(scene, assets, first, triangle_budget(level))
"""


@fieldwise_init
struct Quality(Equatable, ImplicitlyCopyable, Writable):
    """A named mesh density for a humanoid.

    The type stops a bare integer at compile time. A value that is not
    one of the named levels is still constructible, and the boundary
    that reads it refuses it.
    """

    var value: Int

    def is_valid(self) -> Bool:
        """Return True if this is `LOW`, `MEDIUM`, `HIGH` or `XHIGH`."""
        return self == LOW or self == MEDIUM or self == HIGH or self == XHIGH


# The fewest triangles: under a hundred thousand for a whole body.
comptime LOW = Quality(0)
# About twice the triangles of `LOW`.
comptime MEDIUM = Quality(1)
# About twice the triangles of `MEDIUM`.
comptime HIGH = Quality(2)
# The most triangles: about a million for a whole body.
comptime XHIGH = Quality(3)


def _checked(quality: Quality) raises:
    """Refuse a quality that is not named.

    Args:
        quality: The level to check.

    Raises:
        Error: If `quality` is not a named level.
    """
    if not quality.is_valid():
        raise Error("Quality must be low, medium, high or xhigh")


def anatomy_detail(quality: Quality) raises -> Int:
    """Return the detail of each bone, ligament, muscle and vessel.

    Args:
        quality: The mesh level.

    Returns:
        Cells along each anatomical solid: 8, 10, 12 or 16.

    Raises:
        Error: If `quality` is not a named level.
    """
    _checked(quality)
    if quality == LOW:
        return 8
    if quality == MEDIUM:
        return 10
    if quality == HIGH:
        return 12
    return 16


def skin_detail(quality: Quality) raises -> Int:
    """Return the detail of a skin that covers the body or a limb.

    Args:
        quality: The mesh level.

    Returns:
        Cells along the skin: 32, 40, 48 or 56.

    Raises:
        Error: If `quality` is not a named level.
    """
    _checked(quality)
    if quality == LOW:
        return 32
    if quality == MEDIUM:
        return 40
    if quality == HIGH:
        return 48
    return 56


def hand_skin_detail(quality: Quality) raises -> Int:
    """Return the detail of the skin of one hand.

    Args:
        quality: The mesh level.

    Returns:
        Cells along the hand's skin: 24, 32, 40 or 48.

    Raises:
        Error: If `quality` is not a named level.
    """
    _checked(quality)
    if quality == LOW:
        return 24
    if quality == MEDIUM:
        return 32
    if quality == HIGH:
        return 40
    return 48


def triangle_budget(quality: Quality) raises -> Int:
    """Return how many triangles one whole humanoid keeps.

    Args:
        quality: The mesh level.

    Returns:
        90,000, 200,000, 450,000 or 1,000,000.

    Raises:
        Error: If `quality` is not a named level.
    """
    _checked(quality)
    if quality == LOW:
        return 90000
    if quality == MEDIUM:
        return 200000
    if quality == HIGH:
        return 450000
    return 1000000


def quality_named(name: String) raises -> Quality:
    """Return the level that `name` names.

    Args:
        name: `low`, `medium`, `high` or `xhigh`, in lower case.

    Returns:
        The named level.

    Raises:
        Error: If `name` names no level.
    """
    if name == "low":
        return LOW
    if name == "medium":
        return MEDIUM
    if name == "high":
        return HIGH
    if name == "xhigh":
        return XHIGH
    raise Error("Quality must be low, medium, high or xhigh, not " + name)


def quality_label(quality: Quality) raises -> String:
    """Return the name of `quality`, as `quality_named` reads it.

    Args:
        quality: The mesh level.

    Returns:
        `low`, `medium`, `high` or `xhigh`.

    Raises:
        Error: If `quality` is not a named level.
    """
    _checked(quality)
    if quality == LOW:
        return "low"
    if quality == MEDIUM:
        return "medium"
    if quality == HIGH:
        return "high"
    return "xhigh"
