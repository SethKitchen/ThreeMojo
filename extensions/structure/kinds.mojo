# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""The kinds of a structural model.

Each node has six degrees of freedom: three translations along the global
x, y and z axes and three rotations about them. A `Dof` names one of
them. Its value is also its offset in the node's block of the global
vectors, so the degree of freedom `d` of node `n` is entry `6 n + d`.
"""


@fieldwise_init
struct Dof(Equatable, ImplicitlyCopyable, Writable):
    """One of the six degrees of freedom of a node."""

    var value: Int

    def is_valid(self) -> Bool:
        """Return True if this names one of the six degrees of freedom.

        Returns:
            Whether the value is 0 to 5.
        """
        return self.value >= 0 and self.value < 6

    def is_translation(self) -> Bool:
        """Return True if this is a translation.

        Returns:
            Whether the value is 0 to 2.
        """
        return self.value >= 0 and self.value < 3

    def is_rotation(self) -> Bool:
        """Return True if this is a rotation.

        Returns:
            Whether the value is 3 to 5.
        """
        return self.value >= 3 and self.value < 6


# Translation along global x.
comptime UX = Dof(0)
# Translation along global y.
comptime UY = Dof(1)
# Translation along global z, up.
comptime UZ = Dof(2)
# Rotation about global x, right-handed.
comptime RX = Dof(3)
# Rotation about global y, right-handed.
comptime RY = Dof(4)
# Rotation about global z, right-handed.
comptime RZ = Dof(5)
