# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Which of thirty-two layers something is on, from three.js
`src/core/Layers.js`.

A node and a camera each carry a set of layers, and a camera draws a mesh
only if its node shares a layer with the camera. That is how one scene
serves two views: a minimap camera that sees the terrain and not the
effects, a picking pass that sees only what can be picked. A thing can be
on several layers at once, and a camera can watch several.

The set is a mask of thirty-two bits, as three.js's is, and a layer is the
number of a bit. Both start with layer zero alone, so nothing is hidden
until something asks to be: a scene that never mentions layers renders
exactly as it did before they existed.

A layer number outside zero to thirty-one is refused rather than masked
off: three.js wraps it silently, so `enable(32)` there enables layer zero,
which is the kind of mistake nothing reports.
"""


def _bit(layer: Int) raises -> UInt32:
    """Return the mask bit for one layer, refusing a layer that has none."""
    if layer < 0 or layer > 31:
        raise Error("A layer is a number from 0 to 31")
    return UInt32(1) << UInt32(layer)


@fieldwise_init
struct Layers(Equatable, ImplicitlyCopyable, Writable):
    """A set of layers, as a mask of thirty-two bits."""

    var mask: UInt32

    def __init__(out self):
        """Create a set holding layer zero alone, three.js's default."""
        self.mask = 1

    @staticmethod
    def all() -> Layers:
        """Return the set holding every layer.

        What `Lighting` resolves against when no camera is asking: every
        light, whatever layer it is on.
        """
        return Layers(UInt32.MAX)

    def set(mut self, layer: Int) raises:
        """Make `layer` the only layer in the set.

        Args:
            layer: The layer, 0 to 31.

        Raises:
            Error: If the layer is outside 0 to 31.
        """
        self.mask = _bit(layer)

    def enable(mut self, layer: Int) raises:
        """Add `layer` to the set.

        Args:
            layer: The layer, 0 to 31.

        Raises:
            Error: If the layer is outside 0 to 31.
        """
        self.mask |= _bit(layer)

    def disable(mut self, layer: Int) raises:
        """Remove `layer` from the set. The set can end up empty, and a
        camera watching no layer draws nothing.

        Args:
            layer: The layer, 0 to 31.

        Raises:
            Error: If the layer is outside 0 to 31.
        """
        self.mask &= ~_bit(layer)

    def toggle(mut self, layer: Int) raises:
        """Add `layer` if it is not in the set, else remove it.

        Args:
            layer: The layer, 0 to 31.

        Raises:
            Error: If the layer is outside 0 to 31.
        """
        self.mask ^= _bit(layer)

    def enable_all(mut self):
        """Put every layer in the set."""
        self.mask = 0xFFFFFFFF

    def disable_all(mut self):
        """Empty the set."""
        self.mask = 0

    def is_enabled(self, layer: Int) raises -> Bool:
        """Return True if `layer` is in the set.

        Args:
            layer: The layer, 0 to 31.

        Returns:
            Whether it is in the set.

        Raises:
            Error: If the layer is outside 0 to 31.
        """
        return (self.mask & _bit(layer)) != 0

    def test(self, other: Layers) -> Bool:
        """Return True if the two sets share any layer, three.js's `test`:
        the question a camera asks of a node.

        Args:
            other: The other set.

        Returns:
            Whether they overlap.
        """
        return (self.mask & other.mask) != 0
