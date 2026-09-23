# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""The owners of every 3D texture and every array texture in a scene.

Two stores beside `TextureStore`, of the same shape and for the same
reason: a volume is large, and exactly one thing should own it. They are
their own stores because a `TextureId` names an image sampled by two
coordinates, and these are sampled by three; see `render.volume_texture`.
A `LUTPass` names its lookup table by `Data3DTextureId`.

Append-only, as `TextureStore` is: nothing removes a texture, so an id
cannot dangle. `NO_DATA_3D_TEXTURE` and `NO_DATA_ARRAY_TEXTURE` are the
absence of one.
"""

from render.volume_texture import Data3DTexture, DataArrayTexture


@fieldwise_init
struct Data3DTextureId(Equatable, ImplicitlyCopyable, Writable):
    """Which texture in a `Data3DTextureStore`, as a type rather than a
    bare int.

    See `core.object3d.NodeId` for why these are wrapped.
    """

    var value: Int


@fieldwise_init
struct DataArrayTextureId(Equatable, ImplicitlyCopyable, Writable):
    """Which texture in a `DataArrayTextureStore`, as a type rather than a
    bare int.

    See `core.object3d.NodeId` for why these are wrapped.
    """

    var value: Int


# What a pass holds when it names no 3D texture.
comptime NO_DATA_3D_TEXTURE = Data3DTextureId(-1)
# What a holder holds when it names no array texture.
comptime NO_DATA_ARRAY_TEXTURE = DataArrayTextureId(-1)


struct Data3DTextureStore(Movable):
    """Owns 3D textures and hands out ids naming them."""

    var textures: List[Data3DTexture]

    def __init__(out self):
        """Create an empty store."""
        self.textures = List[Data3DTexture]()

    def count(self) -> Int:
        """Return how many 3D textures the store holds."""
        return len(self.textures)

    def add(mut self, var texture: Data3DTexture) -> Data3DTextureId:
        """Take ownership of `texture` and return the id naming it.

        Args:
            texture: The texture to store; moved in, not copied.

        Returns:
            Its id, valid for the life of the store.
        """
        self.textures.append(texture^)
        return Data3DTextureId(len(self.textures) - 1)

    def get(
        self, id: Data3DTextureId
    ) raises -> ref[origin_of(self.textures[0])] Data3DTexture:
        """Return a borrowed view of the 3D texture with that id.

        Copies nothing. Bind the result with `ref`.

        Args:
            id: Which texture to read.

        Returns:
            A reference to it, valid as long as the store is.

        Raises:
            Error: If no 3D texture has that id.
        """
        if id.value < 0 or id.value >= len(self.textures):
            raise Error("No 3D texture has that id")
        return self.textures[id.value]


struct DataArrayTextureStore(Movable):
    """Owns array textures and hands out ids naming them."""

    var textures: List[DataArrayTexture]

    def __init__(out self):
        """Create an empty store."""
        self.textures = List[DataArrayTexture]()

    def count(self) -> Int:
        """Return how many array textures the store holds."""
        return len(self.textures)

    def add(mut self, var texture: DataArrayTexture) -> DataArrayTextureId:
        """Take ownership of `texture` and return the id naming it.

        Args:
            texture: The texture to store; moved in, not copied.

        Returns:
            Its id, valid for the life of the store.
        """
        self.textures.append(texture^)
        return DataArrayTextureId(len(self.textures) - 1)

    def get(
        self, id: DataArrayTextureId
    ) raises -> ref[origin_of(self.textures[0])] DataArrayTexture:
        """Return a borrowed view of the array texture with that id.

        Copies nothing. Bind the result with `ref`.

        Args:
            id: Which texture to read.

        Returns:
            A reference to it, valid as long as the store is.

        Raises:
            Error: If no array texture has that id.
        """
        if id.value < 0 or id.value >= len(self.textures):
            raise Error("No array texture has that id")
        return self.textures[id.value]
