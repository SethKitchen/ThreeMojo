# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""New dyes on a dressed person, without dressing them again.

`dress` makes each garment's shell, cuts it, hangs its skirt and lays its
frills and fur: most of a quarter second for a person. The colors come
last, from the four dyes, and each vertex keeps its share of each dye in
its `dye` attribute. So `redye` paints a dressed outfit in new dyes in a
few milliseconds:

1. It paints each part of each garment from its `dye` and `wear`
   attributes, as `paint` does, in the dyes `design_dyes` gives.
2. A part drawn with a design in colors takes a new texture in the new
   dyes, from `DesignMaps.designed`. A tonal design and a braid are
   shades, so they serve every dye.
3. A fur shell is drawn darker the lower it stands, as `fur_shade` says.
4. Each part's sheen takes the new primary dye, as `dye_sheen` gives it.

The outfit must hold the garments the person was dressed in, in the same
order, with the same designs. Only their dyes can differ. A crowd can
then dress a few bodies and paint each many ways.

This is not a three.js port. See Extensions.

    var dressed = dress(scene, assets, person, outfit)
    outfit.garments[2].dyes[PRIMARY_DYE.value] = crimson
    redye(scene, assets, dressed, outfit)
"""

from core.assets import Assets
from core.buffer_attribute import BufferAttribute
from core.buffer_geometry import COLOR
from core.scene import Scene
from extensions.attire.design import DesignMaps, design_dyes, worn_design
from extensions.attire.dye import paint
from extensions.attire.fabric import dye_sheen
from extensions.attire.fur import fur_shade
from extensions.attire.kinds import PRIMARY_DYE
from extensions.attire.outfit import Dressed, Outfit
from render.srgb import SRGB
from render.texture_store import NO_TEXTURE


def redye(
    mut scene: Scene, mut assets: Assets, dressed: Dressed, outfit: Outfit
) raises:
    """Paint a dressed outfit in new dyes.

    Args:
        scene: The scene the person is in.
        assets: The store of the outfit's geometry, materials and
            textures.
        dressed: What `dress` gave for the outfit.
        outfit: The same garments, in the same order and with the same
            designs, in new dyes.

    Raises:
        Error: If the outfit does not check or does not hold one garment
            for each of the dressed garments, or a part has no dye
            weights.
    """
    outfit.check()
    if len(outfit.garments) != len(dressed.parts):
        raise Error("Redye an outfit with the garments it was dressed in")
    var designs = DesignMaps()
    for g in range(len(outfit.garments)):  # pragma: no branch
        ref garment = outfit.garments[g]
        var design = worn_design(garment.design, garment.fabric)
        var dyes = design_dyes(design, garment.dyes)
        var shells = 0
        for mesh in dressed.parts[g]:
            if (
                assets.materials.get(
                    scene.skinned_meshes[mesh].material
                ).alpha_test
                > 0
            ):
                shells += 1
        var shell = 0
        for mesh in dressed.parts[g]:
            ref skinned = scene.skinned_meshes[mesh]
            var piece = assets.geometries.get(skinned.geometry).clone()
            paint(piece, dyes)
            var look = assets.materials.get(skinned.material)
            if look.alpha_test > 0:
                # A fur shell: darker the lower it stands.
                var shade = fur_shade(shell, shells)
                var colors = piece.clone_attribute(String(COLOR))
                for v in range(colors.count()):  # pragma: no branch
                    for c in range(3):  # pragma: no branch
                        colors.set_component(
                            v, c, colors.component(v, c) * shade
                        )
                piece.set_attribute(String(COLOR), colors^)
                shell += 1
            elif (
                design.is_colored()
                and look.map != NO_TEXTURE
                and assets.textures.get(look.map).color_space == SRGB
            ):
                # The designed part: its texture is drawn in the dyes.
                look.map = designs.designed(assets, design, garment.dyes)
            dye_sheen(look, garment.dyes[PRIMARY_DYE.value])
            assets.geometries.replace(skinned.geometry, piece^)
            assets.materials.materials[skinned.material.value] = look^
