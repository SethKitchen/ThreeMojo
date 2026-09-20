# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""The owner of every cube texture in a scene.

The fourth store, after `GeometryStore`, `MaterialStore` and `TextureStore`,
and the same shape for the same reason: six images are large, a mirror ball
and a sky can share one set, and exactly one thing should own it. A
`Material` names its environment by id, and so does a `Scene` its background.

Append-only, as `TextureStore` is, and for the same reason: nothing removes
a cube texture, so an id cannot dangle.

`NO_CUBE_TEXTURE` lives here rather than with `Material` for the reason
`NO_TEXTURE` lives with its store: the absence of a cube texture is a fact
about cube textures. `SCENE_ENVIRONMENT` is the other value that is not an
id. A material naming it reflects whatever cube texture the scene's
`environment` names, which the renderer looks up when it prepares the
material; a corner never carries it, and both rasterizers refuse one that
does. See `core.scene`.
"""

from render.cube_texture import CubeTexture


@fieldwise_init
struct CubeTextureId(Equatable, ImplicitlyCopyable, Writable):
    """Which cube texture in a `CubeTextureStore`, as a type rather than a
    bare int.

    See `core.object3d.NodeId` for why these are wrapped.
    """

    var value: Int


# What a material holds when it reflects nothing, and what a scene holds
# when it has no environment. Not an id but the absence of one.
comptime NO_CUBE_TEXTURE = CubeTextureId(-1)
# What a material holds when it reflects the scene's `environment`,
# whichever cube texture that names when the frame is prepared. Not an id
# either: the renderer replaces it with the scene's before a corner is
# built, and a corner carrying it is refused.
comptime SCENE_ENVIRONMENT = CubeTextureId(-2)


struct CubeTextureStore(Movable):
    """Owns cube textures and hands out ids naming them."""

    var textures: List[CubeTexture]

    def __init__(out self):
        """Create an empty store."""
        self.textures = List[CubeTexture]()

    def count(self) -> Int:
        """Return how many cube textures the store holds."""
        return len(self.textures)

    def add(mut self, var texture: CubeTexture) -> CubeTextureId:
        """Take ownership of `texture` and return the id naming it.

        Args:
            texture: The cube texture to store; moved in, not copied.

        Returns:
            Its id, valid for the life of the store.
        """
        self.textures.append(texture^)
        return CubeTextureId(len(self.textures) - 1)

    def get(
        self, id: CubeTextureId
    ) raises -> ref[origin_of(self.textures[0])] CubeTexture:
        """Return a borrowed view of the cube texture with that id.

        Copies nothing, as `TextureStore.get` does not. Bind the result
        with `ref`.

        Args:
            id: Which cube texture to read.

        Returns:
            A reference to it, valid as long as the store is.

        Raises:
            Error: If no cube texture has that id. `NO_CUBE_TEXTURE` and
                `SCENE_ENVIRONMENT` name none.
        """
        if id.value < 0 or id.value >= len(self.textures):
            raise Error("No cube texture has that id")
        return self.textures[id.value]
