# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""The owner of every texture in a scene.

The third store, after `GeometryStore` and `MaterialStore`, and the same shape
for the same reason: an image is large, several materials will want the same
one, and exactly one thing should own it. A `Material` names its texture by id
rather than holding it, so two materials differing only in colour cost one copy
of the image between them rather than two.

Append-only. Nothing here reference-counts or reuses an id, because nothing yet
removes a texture — and an id that cannot dangle needs no generation counter to
prove it. When deletion arrives, that is the moment to add one.

The blank texture is always id `NO_TEXTURE`, which is not an id at all but the
absence of one; see `materials.material`.
"""

from render.texture import Texture

# An index into a `TextureStore`.
comptime TextureId = Int


struct TextureStore(Movable):
    """Owns textures and hands out ids naming them."""

    var textures: List[Texture]

    def __init__(out self):
        """Create an empty store."""
        self.textures = List[Texture]()

    def count(self) -> Int:
        """Return how many textures the store holds."""
        return len(self.textures)

    def add(mut self, var texture: Texture) -> TextureId:
        """Take ownership of `texture` and return the id naming it.

        Args:
            texture: The image to store; moved in, not copied.

        Returns:
            Its id, valid for the life of the store.
        """
        self.textures.append(texture^)
        return len(self.textures) - 1

    def get(
        self, id: TextureId
    ) raises -> ref[origin_of(self.textures[0])] Texture:
        """Return a borrowed view of the texture with that id.

        Copies nothing, as `GeometryStore.get` does not: binding the result
        with `var` is a compile error rather than a silent copy of every
        texel. Bind it with `ref`.

        Args:
            id: Which texture to read.

        Returns:
            A reference to it, valid as long as the store is.

        Raises:
            Error: If no texture has that id.
        """
        if id < 0 or id >= len(self.textures):
            raise Error("No texture has that id")
        return self.textures[id]
