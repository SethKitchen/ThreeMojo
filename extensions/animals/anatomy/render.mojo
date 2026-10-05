# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Engineering mode: the skin, the skeleton and the muscles as layers.

Game mode is `mesh_animal`: a painted coat, fur normals and baked
shadows. Engineering mode draws what the numbers describe, in flat
tissue colors with no noise and no baked light:

- the skin: the sculpt without its coat, for a translucent material;
- the skeleton: a round cone along each bone, joint to joint;
- the muscles: each belly an ellipsoid of the muscle's own volume, `m /
  rho`, as long as its fibers are in the pose, so it thickens as it
  shortens; each tendon a cone along the rest of its path, thick enough
  to carry `F0` at 50 MPa.

Each bone's radius is a share of its length. The mammal long-bone
ratios use mid-shaft diameters and lengths from five cheetahs and three
greyhounds (Hudson2011a, Table 1; Hudson2011b, Table 1; source inputs
`FROM_TEXT`). Averaging the ratios and applying them to all mammals is
`DESIGN`: femur 0.0385, tibia 0.036, humerus 0.0456 and radius 0.0337.
Using each ratio at all sizes is also a DESIGN simplification. The
length and diameter exponents, `M^0.35` and `M^0.36` (Alexander1979,
`FROM_ABSTRACT`), differ; they do not establish an exact constant ratio.
The other bones' shares and the tendon stress are DESIGN values.
"""

from core.buffer_attribute import BufferAttribute
from core.buffer_geometry import (
    COLOR,
    NORMAL,
    POSITION,
    BufferGeometry,
    MaterialIndex,
)
from extensions.animals.anatomy.body import MAMMAL, BodyPlan, species_body
from extensions.animals.anatomy.muscles import AnimalMuscle
from extensions.animals.anatomy.tissue import (
    COAT,
    FIN,
    HEAD,
    LEG,
    PLUMAGE,
    THORAX,
    ABDOMEN,
    NECK,
    PELVIS,
    TAIL,
    segment_of,
    tissue_of,
)
from extensions.anatomy.mode import (
    ENGINEERING_MODE,
    AnatomyMode,
    require_mode,
)
from extensions.animals.anatomy.flex import fiber_ratio, flexed_animal
from extensions.animals.build import (
    Animal,
    animal_materials,
    mesh_animal,
    part_box,
)
from extensions.animals.rig import Pose
from extensions.sdf.field import SdfModel
from extensions.sdf.ids import CONE, BoneId, SURFACE_PART_COUNT, SurfacePart
from extensions.sdf.mesher import SurfaceMesh, merge, mesh_part
from extensions.sdf.vector import V3, length
from materials.material import LAMBERT, PHONG, Material
from render.framebuffer import Color
from std.math import pi, sqrt
from std.sys import num_logical_cores
from units.si import METER, Length

# Linear tissue colors.
comptime SKIN_COLOR = (0.62, 0.42, 0.33)
comptime BONE_COLOR = (0.78, 0.72, 0.55)
comptime MUSCLE_COLOR = (0.45, 0.04, 0.035)
comptime TENDON_COLOR = (0.86, 0.84, 0.76)
# A tendon carries its muscle's `F0` at this stress, in pascals.
comptime TENDON_STRESS = 50.0e6
# The engineering layers mesh this much finer than the game body.
comptime FINE = 0.6


# The layers' order in `anatomy_layers` and `anatomy_materials`.
comptime SKIN_LAYER = 0
comptime BONE_LAYER = 1
comptime MUSCLE_LAYER = 2


def _bone_share(plan: BodyPlan, name: String, segment: Int) -> Float64:
    if plan == MAMMAL:
        if name.startswith("femur"):
            return 0.0385
        if name.startswith("tibia"):
            return 0.036
        if name.startswith("humerus"):
            return 0.0456
        if name.startswith("radius"):
            return 0.0337
    if name == "head":
        return 0.17
    if segment == HEAD.value:
        return 0.06
    var axial = (
        segment == NECK.value
        or segment == THORAX.value
        or segment == ABDOMEN.value
        or segment == PELVIS.value
        or segment == TAIL.value
    )
    if axial:
        return 0.09
    if segment == LEG.value:
        return 0.12
    return 0.05


def skeleton_model(animal: Animal) raises -> SdfModel:
    """Return a round cone along each bone of the skeleton, in bind pose.

    Ears, tongues, lips, fins and flight feathers have no bone here.

    Args:
        animal: The individual.

    Returns:
        A sculpt whose solids ride their bones.

    Raises:
        Error: If the species is not named.
    """
    var plan = species_body(animal.species).plan
    var m = SdfModel()
    for i in range(len(animal.rig.bones)):  # pragma: no branch
        ref b = animal.rig.bones[i]
        var segment = segment_of(plan, b.name)
        var soft = False
        for stem in [
            "ear",
            "tongue",
            "lip",
            "whisker",
            "beard",
            "throat",
        ]:  # pragma: no branch
            soft = soft or b.name.startswith(stem)
        if soft or segment == PLUMAGE or segment == FIN:
            continue
        var a = animal.rig.j(b.head)
        var z = animal.rig.j(b.tail)
        var span = length(z - a)
        if span <= 0.0:
            continue
        var r = _bone_share(plan, b.name, segment.value) * span
        # The skull tapers from the braincase to the muzzle.
        var taper = 0.45 if b.name == "head" else 0.8
        _ = m.cone("bone", BoneId(i), a, z, r, taper * r, k=0.4 * r)
    return m^


def muscle_model(
    animal: Animal, muscles: List[AnimalMuscle], pose: Pose
) raises -> SdfModel:
    """Return the muscles and tendons in a pose, in world space.

    Args:
        animal: The individual, at its real size.
        muscles: Its muscles.
        pose: The pose.

    Returns:
        A sculpt already in the pose: its solids ride no bone's turn.

    Raises:
        Error: If the pose is for another rig.
    """
    var world = pose.world(animal.rig)
    var m = SdfModel()
    for muscle in muscles:
        var p = muscle.path(world)
        var head = p[1] - p[0]
        var span = length(head)
        var d = head * (1.0 / span)
        var fiber = fiber_ratio(muscle, world) * Float64(
            muscle.arch.fiber_length.value
        )
        # The belly fills the first stretch of the path, up to its fibers.
        var half = 0.5 * min(fiber, span)
        var volume = muscle.arch.volume_m3()
        var radius = sqrt(volume / (4.0 / 3.0 * pi * half))
        var up = V3(0.0, 1.0, 0.0) if abs(d.y) < 0.9 else V3(1.0, 0.0, 0.0)
        _ = m.ell(
            "belly",
            BoneId(0),
            p[0] + d * half,
            V3(radius, radius, half),
            axis=d,
            up=up,
            k=0.3 * radius,
        )
        var force = Float64(muscle.arch.max_force().value)
        var tendon = sqrt(force / TENDON_STRESS / pi)
        var start = p[0] + d * (2.0 * half)
        for k in range(1, len(p)):  # pragma: no branch
            var a = start if k == 1 else p[k - 1]
            if length(p[k] - a) > tendon:
                _ = m.cone(
                    "tendon", BoneId(0), a, p[k], tendon, tendon, k=tendon
                )
    return m^


def _layer(
    model: SdfModel,
    ids: List[Int],
    cell: Float64,
    threads: Int,
    tissue: Tuple[Float64, Float64, Float64],
    tendon: Tuple[Float64, Float64, Float64],
) raises -> BufferGeometry:
    var box = part_box(model, ids)
    var surface = mesh_part(
        model,
        ids,
        box[0],
        box[1],
        Length(Float32(cell), METER),
        workers=threads,
    )
    return _layer_geometry(model, surface, tissue, tendon)


def _layer_geometry(
    model: SdfModel,
    surface: SurfaceMesh,
    tissue: Tuple[Float64, Float64, Float64],
    tendon: Tuple[Float64, Float64, Float64],
) raises -> BufferGeometry:
    var count = surface.vertex_count()
    var colors = List[Float32](capacity=count * 3)
    for v in range(count):  # pragma: no branch
        var slot = surface.vertex_block[v]
        var start = surface.list_start[slot]
        var at = model.nearest_span(
            surface.lists,
            start,
            start + surface.list_count[slot],
            surface.vertex(v),
        )
        var c = tendon if model.prims[at].kind == CONE else tissue
        colors.append(Float32(c[0]))
        colors.append(Float32(c[1]))
        colors.append(Float32(c[2]))
    var g = BufferGeometry()
    g.set_attribute(
        String(POSITION), BufferAttribute(surface.positions.copy(), 3)
    )
    g.set_attribute(String(NORMAL), BufferAttribute(surface.normals.copy(), 3))
    g.set_attribute(String(COLOR), BufferAttribute(colors^, 3))
    var index = surface.indices.copy()
    var n = len(index)
    g.set_index(index^)
    g.add_group(0, n, MaterialIndex(0))
    return g^


def _skin_layer(
    animal: Animal, posed: SdfModel, threads: Int
) raises -> BufferGeometry:
    # Preserve the game's part boundaries. A jaw carver must not cut the
    # body, and surfaces that are separate must not form smooth unions.
    var surface = SurfaceMesh()
    for part in range(SURFACE_PART_COUNT):  # pragma: no branch
        var ids = List[Int]()
        for i in posed.part_list(SurfacePart(part)):
            ref p = posed.prims[i]
            var bone = animal.rig.bones[p.bone.value].name
            if tissue_of(p.part, posed.tags[p.tag.value], bone) != COAT:
                ids.append(i)
        if len(ids) == 0:
            continue
        var box = part_box(posed, ids)
        if box[0].x > box[1].x:
            continue
        var piece = mesh_part(
            posed,
            ids,
            box[0],
            box[1],
            Length(Float32(animal.cell), METER),
            workers=threads,
        )
        merge(surface, piece)
    return _layer_geometry(posed, surface, SKIN_COLOR, SKIN_COLOR)


def anatomy_layers(
    animal: Animal, muscles: List[AnimalMuscle], pose: Pose, workers: Int = 0
) raises -> List[BufferGeometry]:
    """Mesh the skin, the skeleton and the muscles of an individual.

    Args:
        animal: The individual, at its real size.
        muscles: Its muscles.
        pose: The pose.
        workers: How many threads mesh it. Zero or less means one per
            logical core.

    Returns:
        The skin, the skeleton and the muscles, at `SKIN_LAYER`,
        `BONE_LAYER` and `MUSCLE_LAYER`, each with flat linear vertex
        colors.

    Raises:
        Error: If the pose is for another rig, or the animal has no
            muscles to draw.
    """
    if len(muscles) == 0:
        raise Error("Engineering mode needs the animal's muscles")
    var threads = workers if workers > 0 else num_logical_cores()
    var world = pose.world(animal.rig)
    var cell = animal.cell * FINE
    # The skin: every solid but the coat, in its pose.
    var posed = animal.model.moved(world)
    var skin_layer = _skin_layer(animal, posed, threads)
    var bones = skeleton_model(animal).moved(world)
    var all_bones = List[Int]()
    for i in range(len(bones.prims)):  # pragma: no branch
        all_bones.append(i)
    var bone_layer = _layer(
        bones, all_bones, cell, threads, BONE_COLOR, BONE_COLOR
    )
    var flesh = muscle_model(animal, muscles, pose)
    var all_muscles = List[Int]()
    for i in range(len(flesh.prims)):  # pragma: no branch
        all_muscles.append(i)
    var muscle_layer = _layer(
        flesh, all_muscles, cell, threads, MUSCLE_COLOR, TENDON_COLOR
    )
    var out = List[BufferGeometry]()
    out.append(skin_layer^)
    out.append(bone_layer^)
    out.append(muscle_layer^)
    return out^


def anatomy_materials() raises -> List[Material]:
    """Return the materials of the three layers, in layer order.

    The skin is translucent, so the skeleton and the muscles show
    through it. All take their color from the vertex colors.

    Returns:
        Skin, bone and muscle materials.

    Raises:
        Error: If a material refuses its settings.
    """
    var white = Color(255, 255, 255)
    var out = List[Material]()
    out.append(
        Material(
            white,
            kind=LAMBERT,
            vertex_colors=True,
            opacity=0.28,
            transparent=True,
        )
    )
    out.append(
        Material(
            white,
            kind=PHONG,
            specular=Color(40, 38, 34),
            shininess=20.0,
            vertex_colors=True,
        )
    )
    out.append(
        Material(
            white,
            kind=PHONG,
            specular=Color(60, 50, 50),
            shininess=30.0,
            vertex_colors=True,
        )
    )
    return out^


def mesh_in_mode(
    animal: Animal,
    muscles: List[AnimalMuscle],
    pose: Pose,
    mode: AnatomyMode,
    workers: Int = 0,
) raises -> List[BufferGeometry]:
    """Mesh an individual in game mode or in engineering mode.

    Game mode gives one painted mesh, its muscle bellies shaped for the
    pose. Engineering mode gives the skin, the skeleton and the muscles.

    Args:
        animal: The individual.
        muscles: Its muscles. Game mode can take none.
        pose: The pose.
        mode: `GAME_MODE` or `ENGINEERING_MODE`.
        workers: How many threads mesh it. Zero or less means one per
            logical core.

    Returns:
        The meshes. Draw them with `materials_in_mode`.

    Raises:
        Error: If the mode is not named, or the layers cannot be meshed.
    """
    require_mode(mode)
    if mode == ENGINEERING_MODE:
        return anatomy_layers(animal, muscles, pose, workers)
    var out = List[BufferGeometry]()
    out.append(mesh_animal(flexed_animal(animal, muscles, pose), pose, workers))
    return out^


def materials_in_mode(mode: AnatomyMode) raises -> List[List[Material]]:
    """Return the materials of each mesh `mesh_in_mode` gives.

    Args:
        mode: `GAME_MODE` or `ENGINEERING_MODE`.

    Returns:
        One material list per mesh, in the same order.

    Raises:
        Error: If the mode is not named, or a material refuses its
            settings.
    """
    require_mode(mode)
    var out = List[List[Material]]()
    if mode == ENGINEERING_MODE:
        for m in anatomy_materials():  # pragma: no branch
            out.append([m.copy()])
        return out^
    out.append(animal_materials())
    return out^
