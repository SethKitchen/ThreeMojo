# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Everything a scene draws with, owned in one place.

Four stores arrived one at a time and for the same reason each time: meshes
share geometry, materials share textures, meshes share materials, materials
and skies share cube textures, and the thing being shared has to be owned by
exactly one owner. Passing all three to
`Renderer.render` alongside the scene and the mesh list made a six-argument
call out of what is really two ideas — where things are, and what they are made
of. This is the second idea.

It is deliberately a plain holder rather than a manager. The stores are public
because they *are* the interface: `assets.geometries.add(cube(...))` says what
it does, and a wrapper method per store would be three more things to test that
only forward. What `Assets` buys is the signature, and a single place to hand
around when a renderer, an exporter or a test all need the same resources.

three.js has no equivalent, because JavaScript objects reference each other
directly and ownership never has to be stated. Here it does.
"""

from core.geometry_store import GeometryStore
from materials.material import MaterialStore
from render.cube_texture_store import CubeTextureStore
from render.texture_store import TextureStore
from render.volume_texture_store import (
    Data3DTextureStore,
    DataArrayTextureStore,
)


struct Assets(Movable):
    """The geometry, materials, textures, cube textures, 3D textures and
    array textures a scene draws with."""

    var geometries: GeometryStore
    var materials: MaterialStore
    var textures: TextureStore
    # The environments: what a material reflects and what a scene's sky
    # is made of. Their own store because a cube texture is six textures
    # sampled by direction, and a `TextureId` names one image sampled by
    # place; see `render.cube_texture`.
    var cube_textures: CubeTextureStore
    # The textures with depth: volumes sampled by three coordinates, and
    # stacks of images sampled by a layer; see `render.volume_texture`.
    var data_3d_textures: Data3DTextureStore
    var data_array_textures: DataArrayTextureStore

    def __init__(out self):
        """Create empty stores."""
        self.geometries = GeometryStore()
        self.materials = MaterialStore()
        self.textures = TextureStore()
        self.cube_textures = CubeTextureStore()
        self.data_3d_textures = Data3DTextureStore()
        self.data_array_textures = DataArrayTextureStore()
