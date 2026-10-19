# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""The kinds of a castle plan: tower shapes, roof forms, surfaces and the
limit states that an analysis checks."""
from core.ordinal import ordinal_valid, ordinal_label, require_valid


@fieldwise_init
struct TowerShape(Equatable, ImplicitlyCopyable, Writable):
    """The plan shape of a tower."""

    var value: Int

    def is_valid(self) -> Bool:
        """Return True if this names one of the 2 shapes.

        Returns:
            Whether the value is 0 to 1.
        """
        return ordinal_valid(self.value, 2 - 1)

    def name(self) -> String:
        """Return the shape's name, in lowercase.

        Returns:
            The name, or "unknown" for a value that is not valid.
        """
        var names: List[String] = ["round", "square"]
        return ordinal_label(self.is_valid(), self.value, names, "unknown")


# A cylinder: the radius is the outer radius.
comptime ROUND = TowerShape(0)
# A square prism: the radius is half the side.
comptime SQUARE = TowerShape(1)


@fieldwise_init
struct RoofForm(Equatable, ImplicitlyCopyable, Writable):
    """How a tower or a block is covered."""

    var value: Int

    def is_valid(self) -> Bool:
        """Return True if this names one of the 3 forms.

        Returns:
            Whether the value is 0 to 2.
        """
        return ordinal_valid(self.value, 3 - 1)

    def name(self) -> String:
        """Return the form's name, in lowercase.

        Returns:
            The name, or "unknown" for a value that is not valid.
        """
        var names: List[String] = ["cone", "gable", "parapet"]
        return ordinal_label(self.is_valid(), self.value, names, "unknown")


# A slate cone that rises to a point over a round tower.
comptime CONE = RoofForm(0)
# Two slate slopes that meet at a ridge along the long axis.
comptime GABLE = RoofForm(1)
# A flat roof behind a battlemented parapet of merlons and crenels.
comptime PARAPET = RoofForm(2)


@fieldwise_init
struct Surface(Equatable, ImplicitlyCopyable, Writable):
    """What a face of the scene is made of. It sets the color."""

    var value: Int

    def is_valid(self) -> Bool:
        """Return True if this names one of the 8 surfaces.

        Returns:
            Whether the value is 0 to 7.
        """
        return ordinal_valid(self.value, 8 - 1)

    def name(self) -> String:
        """Return the surface's name, in lowercase.

        Returns:
            The name, or "unknown" for a value that is not valid.
        """
        var names: List[String] = [
            "brick",
            "stone",
            "slate",
            "water",
            "lawn",
            "gravel",
            "trunk",
            "foliage",
        ]
        return ordinal_label(self.is_valid(), self.value, names, "unknown")


comptime BRICK = Surface(0)
# Pale dressed stone: string courses, copings and arch rings.
comptime STONE = Surface(1)
comptime SLATE = Surface(2)
comptime WATER = Surface(3)
comptime LAWN = Surface(4)
comptime GRAVEL = Surface(5)
comptime TRUNK = Surface(6)
# Leaves. Each tree carries its own autumn color.
comptime FOLIAGE = Surface(7)


def require_surface(surface: Surface) raises:
    """Refuse a surface that is not named.

    Nothing. The call returns when the surface is named.

    Args:
        surface: The surface to check.

    Raises:
        Error: If the surface is not named.
    """
    require_valid(surface.is_valid(), "A surface is not valid")


@fieldwise_init
struct LimitState(Equatable, ImplicitlyCopyable, Writable):
    """What an engineering check guards against."""

    var value: Int

    def is_valid(self) -> Bool:
        """Return True if this names one of the 6 limit states.

        Returns:
            Whether the value is 0 to 5.
        """
        return ordinal_valid(self.value, 6 - 1)

    def name(self) -> String:
        """Return the limit state's name, in lowercase.

        Returns:
            The name, or "unknown" for a value that is not valid.
        """
        var names: List[String] = [
            "overturning",
            "sliding",
            "bearing",
            "crushing",
            "tension",
            "arch_thrust",
        ]
        return ordinal_label(self.is_valid(), self.value, names, "unknown")


# The overturning moment is more than the restoring moment allows.
comptime OVERTURNING = LimitState(0)
# The horizontal force is more than friction on the base resists.
comptime SLIDING = LimitState(1)
# The base pressure is more than the ground carries.
comptime BEARING = LimitState(2)
# The masonry stress is more than its design strength.
comptime CRUSHING = LimitState(3)
# A joint opens: the resultant leaves the middle of the section.
comptime TENSION = LimitState(4)
# No line of thrust fits inside an arch ring.
comptime ARCH_THRUST = LimitState(5)


def require_tower_shape(shape: TowerShape) raises:
    """Refuse a tower shape that is not named.

    Nothing. The call returns when the shape is named.

    Args:
        shape: The shape to check.

    Raises:
        Error: If the shape is not named.
    """
    require_valid(shape.is_valid(), "A tower shape is not valid")


def require_roof_form(roof: RoofForm) raises:
    """Refuse a roof form that is not named.

    Nothing. The call returns when the form is named.

    Args:
        roof: The form to check.

    Raises:
        Error: If the form is not named.
    """
    require_valid(roof.is_valid(), "A roof form is not valid")


def require_limit_state(state: LimitState) raises:
    """Refuse a limit state that is not named.

    Nothing. The call returns when the state is named.

    Args:
        state: The state to check.

    Raises:
        Error: If the state is not named.
    """
    require_valid(state.is_valid(), "A limit state is not valid")
