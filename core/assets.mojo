# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Everything a scene draws with, owned in one place.

Three stores arrived one at a time and for the same reason each time: meshes
share geometry, materials share textures, meshes share materials, and the thing
being shared has to be owned by exactly one owner. Passing all three to
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
from render.texture_store import TextureStore


struct Assets(Movable):
    """The geometry, materials and textures a scene draws with."""

    var geometries: GeometryStore
    var materials: MaterialStore
    var textures: TextureStore

    def __init__(out self):
        """Create empty stores."""
        self.geometries = GeometryStore()
        self.materials = MaterialStore()
        self.textures = TextureStore()
