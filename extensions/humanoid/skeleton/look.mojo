# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Looks for the named hydrated tissues of the limb.

Each tissue has a Phong look and a physically based one. The physical
looks take a roughness, an index of refraction and, where the tissue
has one, a sheen or a clear coat. They need an environment or a lamp
and read best tone mapped. The maps are visual approximations.

    var map = muscle_albedo(64)
    var paint = muscle_physical(store.add(map))
"""

from extensions.humanoid.genome import MELANIN, Genome, check_genome
from core.assets import Assets
from extensions.humanoid.skeleton.complexion import (
    MIN_MAP,
    hair_albedo,
    hair_tone,
    iris_albedo,
    skin_albedo_pixels,
    skin_glow,
    skin_relief,
    skin_tone,
)
from materials.material import (
    DOUBLE_SIDE,
    Material,
    MaterialId,
    phong_material,
    physical_material,
)
from extensions.humanoid.skeleton.head.skin.tint import THINNESS
from materials.nodes import (
    NODE_FLOAT,
    NodeGraph,
    NodeProgram,
    THICKNESS_AMBIENT_NODE,
    THICKNESS_ATTENUATION_NODE,
    THICKNESS_COLOR_NODE,
    THICKNESS_DISTORTION_NODE,
    THICKNESS_POWER_NODE,
    THICKNESS_SCALE_NODE,
)
from math.vector2 import Vector2
from render.framebuffer import Color
from render.srgb import SRGB
from render.texture import REPEAT, Texture
from render.texture_store import NO_TEXTURE, TextureId

comptime MIN_SOFT_LOOK = 8
comptime MAX_SOFT_LOOK = 256


def cartilage_phong() raises -> Material:
    """Return a Phong material for articular cartilage.

    The color is pearlescent glistening white/ivory, like wet hyaline cartilage.
    The surface is double-sided and opaque so it reads as tissue instead of colored glass.

    Returns:
        A `PHONG` material.

    Raises:
        Error: If the Phong constructor refuses the values.
    """
    return phong_material(
        Color(240, 242, 245),
        specular=Color(255, 255, 255),
        shininess=36.0,
        side=DOUBLE_SIDE,
    )


def meniscus_phong() raises -> Material:
    """Return a Phong material for a meniscus.

    The color is natural fibrocartilaginous off-white / light cream. Shininess is low.

    Returns:
        A `PHONG` material.

    Raises:
        Error: If the Phong constructor refuses the values.
    """
    return phong_material(
        Color(230, 226, 215),
        specular=Color(140, 135, 125),
        shininess=12.0,
    )


def ligament_phong() raises -> Material:
    """Return a Phong material for a collateral ligament.

    The color is pale fibrous silvery-tan connective tissue. Shininess is low.

    Returns:
        A `PHONG` material.

    Raises:
        Error: If the Phong constructor refuses the values.
    """
    return phong_material(
        Color(228, 222, 206),
        specular=Color(160, 155, 140),
        shininess=16.0,
    )


def muscle_albedo(size: Int = 64) raises -> Texture:
    """Return a red muscle texture with fine longitudinal fibers.

    Args:
        size: Width and height in texels. Eight through 256, 64 by default.

    Returns:
        An sRGB texture that tiles around a muscle belly.

    Raises:
        Error: If `size` is less than eight or more than 256.
    """
    if size < MIN_SOFT_LOOK:
        raise Error("A muscle map needs a size of at least eight")
    if size > MAX_SOFT_LOOK:
        raise Error("A muscle map's size cannot exceed 256")
    var pixels = List[UInt8]()
    for y in range(size):  # pragma: no branch
        for x in range(size):  # pragma: no branch
            var lane = x % 8
            var fiber = Float32(0.10)
            if lane < 2:
                fiber = Float32(1)
            elif lane > 5:
                fiber = Float32(0.45)
            var grain = Float32((x * 17 + y * 31 + (x * y) % 13) & 7) / Float32(
                7
            )
            pixels.append(UInt8(Int(Float32(150) + 24 * fiber + 7 * grain)))
            pixels.append(UInt8(Int(Float32(42) + 10 * fiber + 4 * grain)))
            pixels.append(UInt8(Int(Float32(36) + 7 * fiber + 3 * grain)))
            pixels.append(255)
    return Texture(size, size, pixels^, REPEAT, color_space=SRGB)


def muscle_phong(map: TextureId = NO_TEXTURE) raises -> Material:
    """Return a Phong material for skeletal muscle.

    The color is red muscle belly, like dissected skeletal muscle.

    Args:
        map: Id of a muscle albedo texture, or `NO_TEXTURE`.

    Returns:
        A `PHONG` material.

    Raises:
        Error: If the Phong constructor refuses the values.
    """
    var color = Color(176, 54, 44)
    if map != NO_TEXTURE:
        color = Color(255, 255, 255)
    return phong_material(
        color, map=map, specular=Color(180, 110, 100), shininess=22.0
    )


def tendon_phong() raises -> Material:
    """Return a Phong material for tendon and fascia.

    The color is pale fibrous connective tissue.

    Returns:
        A `PHONG` material.

    Raises:
        Error: If the Phong constructor refuses the values.
    """
    return phong_material(
        Color(214, 200, 176),
        specular=Color(180, 172, 158),
        shininess=24.0,
    )


def artery_phong() raises -> Material:
    """Return a Phong material for an artery.

    The color is saturated arterial red.

    Returns:
        A `PHONG` material.

    Raises:
        Error: If the Phong constructor refuses the values.
    """
    return phong_material(
        Color(168, 28, 42),
        specular=Color(190, 90, 90),
        shininess=28.0,
    )


def vein_phong() raises -> Material:
    """Return a Phong material for a vein.

    The color is deep venous blue.

    Returns:
        A `PHONG` material.

    Raises:
        Error: If the Phong constructor refuses the values.
    """
    return phong_material(
        Color(52, 74, 142),
        specular=Color(110, 130, 180),
        shininess=26.0,
    )


def lymph_phong() raises -> Material:
    """Return a Phong material for lymph nodes and trunks.

    The color is pale yellow-green lymph.

    Returns:
        A `PHONG` material.

    Raises:
        Error: If the Phong constructor refuses the values.
    """
    return phong_material(
        Color(196, 208, 154),
        specular=Color(170, 180, 140),
        shininess=16.0,
    )


def nerve_phong() raises -> Material:
    """Return a Phong material for a peripheral nerve.

    The color is pale dissected nerve.

    Returns:
        A `PHONG` material.

    Raises:
        Error: If the Phong constructor refuses the values.
    """
    return phong_material(
        Color(236, 220, 158),
        specular=Color(200, 190, 150),
        shininess=20.0,
    )


def skin_albedo(size: Int = 64, genome: Genome = Genome()) raises -> Texture:
    """Return a tiling skin texture in the tone `genome` asks for.

    It carries blotches of redness and pigment, pores, and the freckles
    and moles the genome asks for. See `skin_albedo_pixels`.

    Args:
        size: Width and height in texels. Eight through 256, 64 by default.
        genome: Reads the skin's genes. The template genome by default.

    Returns:
        An sRGB texture that tiles around a limb.

    Raises:
        Error: If `size` is less than eight or more than 256, or if
            `genome` is not valid.
    """
    if size < MIN_SOFT_LOOK:
        raise Error("A skin map needs a size of at least eight")
    if size > MAX_SOFT_LOOK:
        raise Error("A skin map's size cannot exceed 256")
    return Texture(
        size, size, skin_albedo_pixels(size, genome), REPEAT, color_space=SRGB
    )


def skin_phong(
    map: TextureId = NO_TEXTURE,
    genome: Genome = Genome(),
    tinted: Bool = False,
) raises -> Material:
    """Return a Phong material for dermis.

    The color is the tone `genome` asks for. With a map the color is
    white so the albedo arrives unshifted.

    Args:
        map: Id of a skin albedo texture, or `NO_TEXTURE`.
        genome: Reads the skin's genes. The template genome by default.
        tinted: Whether the mesh's `color` attribute tints the skin, as
            `tint_head_skin` writes it. Every mesh the material paints
            then needs one.

    Returns:
        A `PHONG` material.

    Raises:
        Error: If the Phong constructor refuses the values, or if
            `genome` is not valid.
    """
    var color = skin_tone(genome)
    if map != NO_TEXTURE:
        color = Color(255, 255, 255)
    var material = phong_material(
        color,
        map=map,
        specular=Color(58, 50, 46),
        shininess=18.0,
        side=DOUBLE_SIDE,
    )
    material.vertex_colors = tinted
    return material^


def hair_phong(genome: Genome = Genome()) raises -> Material:
    """Return a Phong material for a keratin hair shaft.

    The color is the hair tone `genome` asks for: medium brown on the
    template genome.

    Args:
        genome: Reads the hair's genes. The template genome by default.

    Returns:
        A `PHONG` material.

    Raises:
        Error: If the Phong constructor refuses the values, or if
            `genome` is not valid.
    """
    return phong_material(
        hair_tone(genome),
        specular=Color(96, 84, 72),
        shininess=40.0,
    )


def hair_physical(
    genome: Genome = Genome(),
    map: TextureId = NO_TEXTURE,
    depth: Float32 = 1,
) raises -> Material:
    """Return a physically based material for a mass of hair.

    Hair is a bundle of glossy cylinders. Its highlight stretches across
    the shafts, which an anisotropic lobe stands in for, and the light
    that passes between the shafts softens it, which a sheen stands in
    for.

    Args:
        genome: Reads the hair's genes. The template genome by default.
        map: Id of a `hair_albedo` texture, or `NO_TEXTURE`.
        depth: How much of the light reaches it, zero through one. One
            by default; about a half for the mass of hair under
            `hair_cards`, which the hairs over it shade.

    Returns:
        A `PHYSICAL` material.

    Raises:
        Error: If the physical constructor refuses the values, or if
            `genome` is not valid, or `depth` is out of range.
    """
    if depth < 0 or depth > 1:
        raise Error("A hair's depth runs zero through one")
    var tone = hair_tone(genome)
    var color = tone
    if map != NO_TEXTURE:
        color = Color(255, 255, 255)
    color = Color(
        UInt8(Float32(color.r) * depth),
        UInt8(Float32(color.g) * depth),
        UInt8(Float32(color.b) * depth),
    )
    return physical_material(
        color,
        map=map,
        roughness=0.5,
        ior=1.55,
        specular_intensity=0.5,
        sheen=0.6,
        sheen_color=tone,
        sheen_roughness=0.5,
        anisotropy=0.6,
    )


def eye_physical(map: TextureId = NO_TEXTURE) raises -> Material:
    """Return a physically based material for an eyeball.

    The cornea and the tear film are wet and smooth: a strong clear
    coat over a softer body gives the eye its bright glint.

    Args:
        map: Id of an `iris_albedo` texture, or `NO_TEXTURE` for a
            white sclera.

    Returns:
        A `PHYSICAL` material.

    Raises:
        Error: If the physical constructor refuses the values.
    """
    return physical_material(
        Color(255, 255, 255),
        map=map,
        roughness=0.35,
        ior=1.376,
        clearcoat=1.0,
        clearcoat_roughness=0.03,
    )


def muscle_physical(map: TextureId = NO_TEXTURE) raises -> Material:
    """Return a physically based material for skeletal muscle.

    Muscle is wet. Its epimysium is a thin glossy film over a rough
    fibrous body, so a soft lobe carries a sharper clear coat.

    Args:
        map: Id of a muscle albedo texture, or `NO_TEXTURE`.

    Returns:
        A `PHYSICAL` material.

    Raises:
        Error: If the physical constructor refuses the values.
    """
    var color = Color(176, 54, 44)
    if map != NO_TEXTURE:
        color = Color(255, 255, 255)
    return physical_material(
        color,
        map=map,
        roughness=0.55,
        ior=1.37,
        clearcoat=0.35,
        clearcoat_roughness=0.3,
    )


def tendon_physical() raises -> Material:
    """Return a physically based material for tendon and fascia.

    Tendon's collagen runs in parallel bundles, which gives it a silvery
    sheen along its length.

    Returns:
        A `PHYSICAL` material.

    Raises:
        Error: If the physical constructor refuses the values.
    """
    return physical_material(
        Color(214, 200, 176),
        roughness=0.45,
        ior=1.40,
        sheen=0.5,
        sheen_color=Color(235, 230, 220),
        sheen_roughness=0.4,
    )


def ligament_physical() raises -> Material:
    """Return a physically based material for ligament.

    Returns:
        A `PHYSICAL` material with the look of `tendon_physical`, a shade
        darker.

    Raises:
        Error: If the physical constructor refuses the values.
    """
    return physical_material(
        Color(198, 184, 160),
        roughness=0.5,
        ior=1.40,
        sheen=0.4,
        sheen_color=Color(225, 220, 208),
        sheen_roughness=0.45,
    )


def cartilage_physical() raises -> Material:
    """Return a physically based material for articular cartilage.

    Hyaline cartilage is smooth and wet: a low roughness and a clear
    coat over a pale blue-white body.

    Returns:
        A `PHYSICAL` material.

    Raises:
        Error: If the physical constructor refuses the values.
    """
    return physical_material(
        Color(206, 214, 222),
        roughness=0.3,
        ior=1.38,
        clearcoat=0.6,
        clearcoat_roughness=0.15,
    )


def skin_physical(
    map: TextureId = NO_TEXTURE,
    genome: Genome = Genome(),
    relief: TextureId = NO_TEXTURE,
    tinted: Bool = False,
) raises -> Material:
    """Return a physically based material for dermis.

    Skin reflects about three percent at normal incidence, an index of
    refraction near 1.4. Its oily film is glossier than the tissue under
    it, which a faint clear coat stands in for. Light that enters it
    scatters and leaves warm and soft at grazing angles. The renderer
    has no subsurface scattering, so a sheen in the color `skin_glow`
    gives stands in for that rim.

    Args:
        map: Id of a skin albedo texture, or `NO_TEXTURE`.
        genome: Reads the skin's genes. The template genome by default.
        relief: Id of a `skin_relief` height map, or `NO_TEXTURE`.
        tinted: Whether the mesh's `color` attribute tints the skin, as
            `tint_head_skin` writes it. Every mesh the material paints
            then needs one.

    Returns:
        A `PHYSICAL` material.

    Raises:
        Error: If the physical constructor refuses the values, or if
            `genome` is not valid.
    """
    var color = skin_tone(genome)
    if map != NO_TEXTURE:
        color = Color(255, 255, 255)
    var bump = Float32(1)
    if relief != NO_TEXTURE:
        bump = Float32(0.35)
    var material = physical_material(
        color,
        map=map,
        roughness=0.56,
        ior=1.40,
        specular_intensity=0.5,
        clearcoat=0.06,
        clearcoat_roughness=0.4,
        sheen=0.45,
        sheen_color=skin_glow(genome),
        sheen_roughness=0.55,
        bump_map=relief,
        bump_scale=bump,
        side=DOUBLE_SIDE,
    )
    material.vertex_colors = tinted
    return material^


def skin_scatter(genome: Genome = Genome()) raises -> NodeProgram:
    """Return the node program that lets light through thin skin.

    It makes a physical skin three.js's `MeshSSSNodeMaterial`: a lamp
    behind an ear, a nostril or the edge of a cheek shows through it,
    deep red, because red light travels farthest in blood-filled
    tissue. Melanin absorbs some of it on its way, so darker skin lets
    less through. The mesh has no thickness map, so the light through
    is scaled by the mesh's `thinness` attribute, which
    `tint_head_skin` writes: one at the rim of an ear, less at the
    nostrils, the lips and the lids, and nothing where the attribute
    is missing.

    Args:
        genome: Reads `MELANIN`. The template genome by default.

    Returns:
        A compiled node program to store in `Assets.programs` and name
        in the skin material's `nodes`.

    Raises:
        Error: If `genome` is not valid or the graph refuses a node.
    """
    check_genome(genome, "skin")
    var dark = (genome.get(MELANIN) + 1) / 2
    var through = Float32(1) - Float32(0.6) * dark
    var graph = NodeGraph()
    var red = graph.vec3(0.6 * through, 0.1 * through, 0.05 * through)
    var thin = graph.attribute(String(THINNESS), NODE_FLOAT)
    graph.set_output(THICKNESS_COLOR_NODE, graph.mul(red, thin))
    graph.set_output(THICKNESS_DISTORTION_NODE, graph.float(0.25))
    graph.set_output(THICKNESS_AMBIENT_NODE, graph.float(0.02))
    graph.set_output(THICKNESS_ATTENUATION_NODE, graph.float(0.5))
    graph.set_output(THICKNESS_POWER_NODE, graph.float(3.0))
    graph.set_output(THICKNESS_SCALE_NODE, graph.float(4.0))
    return graph.compile()


@fieldwise_init
struct Complexion(ImplicitlyCopyable):
    """The looks one person's genome asks for, stored in an `Assets`.

    `skin` is tinted: every mesh it paints needs a `color` attribute,
    which the head's and the body's skins carry. `hair` is the mass of
    the scalp's hair, in shade, for the strands of `add_groom` to lie
    on.
    """

    var skin: MaterialId
    var hair: MaterialId
    var eyes: MaterialId


# How much light reaches the mass of the scalp's hair under its cards.
comptime HAIR_DEPTH = Float32(0.65)


def add_complexion(
    mut assets: Assets,
    genome: Genome,
    whole_body: Bool = False,
    size: Int = 512,
) raises -> Complexion:
    """Store a person's skin, hair and eye looks and return their ids.

    The skin's color map is `size` texels square, 512 by default, and
    its relief and the hair's map are half that. The color map and its
    relief
    tile several times across the mesh, so a pore is a fraction of a
    millimeter on the face and a freckle is round. A whole
    body's skin is taller than a head's, so it tiles more times up it.
    The skin lets light through where it is thin; see `skin_scatter`.

    Args:
        assets: The store that receives the textures and the materials.
        genome: The person's genome.
        whole_body: True for the body's skin from the head down; False
            for the head's alone.
        size: The skin color map's width and height in texels, eight
            through 512. A smaller map is faster to make and blurrier.

    Returns:
        The three material ids.

    Raises:
        Error: If `genome` is not valid, if `size` is out of range, or a
            store refuses an entry.
    """
    var half = max(MIN_MAP, size // 2)
    # Each tile is about as wide around the skin as it is tall, so a
    # pore is round: a head is about one and a half times as far round
    # as it is tall, and a body's trunk half as far round.
    var around = Float32(4)
    var up = Float32(2.5)
    var relief_around = Float32(7)
    var relief_up = Float32(5)
    if whole_body:
        around = Float32(7)
        up = Float32(14)
        relief_around = Float32(14)
        relief_up = Float32(28)
    var albedo = Texture(
        size, size, skin_albedo_pixels(size, genome), REPEAT, color_space=SRGB
    )
    albedo.repeat = Vector2(around, up)
    var relief = skin_relief(half)
    relief.repeat = Vector2(relief_around, relief_up)
    var strands = hair_albedo(half, genome)
    strands.repeat = Vector2(6, 2)
    var look = skin_physical(
        assets.textures.add(albedo^),
        genome,
        assets.textures.add(relief^),
        tinted=True,
    )
    look.nodes = assets.programs.add(skin_scatter(genome))
    var skin = assets.materials.add(look^)
    var hair = assets.materials.add(
        hair_physical(genome, assets.textures.add(strands^), HAIR_DEPTH)
    )
    var eyes = assets.materials.add(
        eye_physical(assets.textures.add(iris_albedo(64, genome)))
    )
    return Complexion(skin, hair, eyes)
