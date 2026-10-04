# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Build an animal: procedural-animals' `core/build/pipeline.js`.

`create_animal` draws one individual from a species and a seed, builds
its rig and sculpt, and warps both to its proportions. `mesh_animal`
poses the sculpt, meshes each surface, paints the coat and bakes the
light the animal's own body blocks.

The pipeline differs from procedural-animals in three ways, each for
quality:

- A pose moves the sculpt's primitives with their bones, and the posed
  field is meshed again. procedural-animals skins one mesh with dual
  quaternions, which thins a joint as it bends. A re-meshed joint keeps
  its volume and its smooth blend.
- Occlusion is baked from the distance field into the vertex colors.
  The software renderer has no screen-space occlusion, and creases such
  as the armpit, the groin and the eye socket read flat without it.
- Each eyeball is its own surface, meshed at a finer cell, and painted
  with a pupil, an iris with radial fibers, a limbal ring and a sclera.
"""

from core.buffer_attribute import BufferAttribute
from core.buffer_geometry import (
    COLOR,
    NORMAL,
    POSITION,
    BufferGeometry,
    MaterialIndex,
)
from extensions.animals.coat import (
    EYE,
    FEATHER,
    FUR,
    SURFACE_CLASS_COUNT,
    CoatSample,
    EyeLook,
    Paint,
    Palette,
    mix3,
    paint_eye,
)
from extensions.sdf.ids import (
    CONE,
    ELLIPSOID,
    FIN,
    SURFACE_PART_COUNT,
    SurfacePart,
)
from extensions.animals.parts import EYEBALL
from extensions.animals.kit import (
    EyeSpec,
    eye_frame_of,
)
from extensions.sdf.mesher import (
    SurfaceMesh,
    merge,
    mesh_part,
)
from extensions.animals.noise import fbm3
from extensions.animals.options import (
    AnimalOptions,
    body_random,
    check_options,
)
from extensions.animals.registry import (
    SpeciesId,
    require_species,
    species_cell,
    species_eye,
    species_head_origin,
    species_look,
    species_paint,
    species_palette,
    species_rig,
    species_sculpt,
    species_traits,
)
from extensions.animals.rig import Pose, Rig
from extensions.sdf.field import (
    Primitive,
    SdfModel,
)
from extensions.animals.traits import Traits
from extensions.sdf.vector import (
    Rigid,
    V3,
    dot,
    length,
    smoothstep,
)
from extensions.animals.warp import scale_warp
from materials.material import LAMBERT, PHONG, Material
from render.framebuffer import Color
from render.tasks import TaskGroup
from std.math import sqrt
from std.sys import num_logical_cores
from units.si import METER, Length

# How many fine cells an eyeball's radius spans, at least.
comptime EYE_CELLS = 6.0
# How many Newton steps undo the proportion warps.
comptime UNWARP_STEPS = 4
# How many samples along the normal the occlusion bake takes.
comptime OCCLUSION_SAMPLES = 5


struct Animal(Movable):
    """One individual, ready to pose and mesh.

    `rig` and `model` are the individual's: the reference rig and sculpt
    warped to its proportions and size. `reference` is the sculpt before
    the warps, which the coat is painted in.
    """

    var species: SpeciesId
    var options: AnimalOptions
    var traits: Traits
    var rig: Rig
    var model: SdfModel
    var palette: Palette
    var eye: EyeSpec
    var look: EyeLook
    var cell: Float64
    var eye_cell: Float64

    def __init__(
        out self,
        species: SpeciesId,
        options: AnimalOptions,
        var traits: Traits,
        var rig: Rig,
        var model: SdfModel,
        var palette: Palette,
        eye: EyeSpec,
        look: EyeLook,
        cell: Float64,
        eye_cell: Float64,
    ):
        """Gather the parts of one individual.

        Args:
            species: The species.
            options: The caller's options.
            traits: The drawn traits.
            rig: The individual's rig.
            model: The individual's sculpt.
            palette: The individual's palette.
            eye: The species' eye.
            look: The eye colors.
            cell: The body's fine cell size, in meters.
            eye_cell: The eyeballs' fine cell size, in meters.
        """
        self.species = species
        self.options = options
        self.traits = traits^
        self.rig = rig^
        self.model = model^
        self.palette = palette^
        self.eye = eye
        self.look = look
        self.cell = cell
        self.eye_cell = eye_cell

    def bind_pose(self) -> Pose:
        """Return the pose the animal was sculpted in.

        Returns:
            A pose that turns no bone.
        """
        return Pose(len(self.rig.bones))


def _inflate_thin(mut model: SdfModel, res: Float64, thickness: Float64):
    # Thin solids, such as ears and tail tips, are inflated at the coarse
    # tiers so they do not vanish between samples.
    if res < 1.9:
        return
    var t = thickness * res
    for i in range(len(model.prims)):
        ref p = model.prims[i]
        if not p.thin or p.carve:
            continue
        if p.kind == ELLIPSOID:
            p.r = V3(max(p.r.x, t), max(p.r.y, t), max(p.r.z, t))
        elif p.kind == FIN:
            p.r = V3(max(p.r.x, t), max(p.r.y, min(t, p.r.x)), 0.0)


def create_animal(species: SpeciesId, options: AnimalOptions) raises -> Animal:
    """Draw one individual and build its rig and sculpt.

    Args:
        species: The species.
        options: The seed, quality, sex, age and morph.

    Returns:
        The individual, in bind pose.

    Raises:
        Error: If the species or an option is not valid, or the species
            refuses the requested morph.
    """
    require_species(species)
    check_options(options)
    var r = body_random(options.seed)
    var t = species_traits(species, r, options)
    var size = t.get("size")
    t.warps.add(scale_warp(size))
    var reference_rig = species_rig(species, t)
    var reference = SdfModel()
    species_sculpt(species, reference, reference_rig, t)
    var res = options.quality.resolution()
    _inflate_thin(reference, res, t.get("minThick", 0.0035))
    var eye = species_eye(species, t)
    var head = species_head_origin(species)
    var head_bone = reference_rig.bone("head")
    for s in [1.0, -1.0]:  # pragma: no branch
        var ef = eye_frame_of(eye, head, s)
        _ = reference.ell(
            "eyeball",
            head_bone,
            ef.c,
            V3(eye.r, eye.r, eye.r),
            axis=ef.z,
            up=ef.y,
            k=0.0,
            part=EYEBALL,
        )
    var model = t.warps.warp_model(reference)
    var rig = t.warps.warp_rig(reference_rig)
    var cell = species_cell(species) * res * size
    var eye_cell = min(cell, eye.r * size / EYE_CELLS)
    var palette = species_palette(species, t)
    var look = species_look(species, t)
    return Animal(
        species,
        options,
        t^,
        rig^,
        model^,
        palette^,
        eye,
        look,
        cell,
        eye_cell,
    )


def primitive_box(p: Primitive, outline: List[Float64]) -> Tuple[V3, V3]:
    """Return a box that holds one primitive.

    Args:
        p: The primitive.
        outline: The model's fin outlines.

    Returns:
        The least and the greatest corner.
    """
    var reach: Float64
    var c = p.c
    var d = p.c
    if p.kind == ELLIPSOID:
        reach = max(p.r.x, max(p.r.y, p.r.z))
    elif p.kind == CONE:
        reach = max(p.r.x, p.r.y)
        d = p.b
    elif p.kind == FIN:
        var far = 0.0
        for i in range(
            p.first * 2, (p.first + p.count) * 2
        ):  # pragma: no branch
            far = max(far, abs(outline[i]))
        reach = far * 1.5 + p.r.x * 2.0
    else:
        reach = p.r.x * 2.0 + max(abs(p.lo), abs(p.hi))
    var low = V3(
        min(c.x, d.x) - reach, min(c.y, d.y) - reach, min(c.z, d.z) - reach
    )
    var high = V3(
        max(c.x, d.x) + reach, max(c.y, d.y) + reach, max(c.z, d.z) + reach
    )
    return (low, high)


def part_box(model: SdfModel, part: List[Int]) -> Tuple[V3, V3]:
    """Return a box that holds the solids of one surface, with room for
    their blends.

    Args:
        model: The sculpt.
        part: The surface's primitives.

    Returns:
        The least and the greatest corner.
    """
    var low = V3(1e9, 1e9, 1e9)
    var high = V3(-1e9, -1e9, -1e9)
    var k = 0.0
    for i in part:
        ref p = model.prims[i]
        k = max(k, p.k)
        if p.carve:
            continue
        var box = primitive_box(p, model.outline)
        low = V3(
            min(low.x, box[0].x), min(low.y, box[0].y), min(low.z, box[0].z)
        )
        high = V3(
            max(high.x, box[1].x), max(high.y, box[1].y), max(high.z, box[1].z)
        )
    var pad = V3(k, k, k)
    return (low - pad, high + pad)


def mesh_animal(
    animal: Animal, pose: Pose, workers: Int = 1
) raises -> BufferGeometry:
    """Pose, mesh and paint one animal.

    Args:
        animal: The individual.
        pose: How its bones are turned. See `Animal.bind_pose`.
        workers: How many threads mesh it. Zero or less means one per
            logical core. The mesh is the same for any count.

    Returns:
        The mesh, with positions, normals and linear vertex colors. Its
        groups are the surface classes, by `SurfaceClass` value, so a
        mesh with `animal_materials` draws fur matte and the nose and the
        eyes glossy.

    Raises:
        Error: If the pose is for another rig, or a surface is empty.
    """
    var world = pose.world(animal.rig)
    var posed = animal.model.moved(world)
    var inverse = List[Rigid](capacity=len(world))
    for w in world:
        inverse.append(w.inverse())
    var threads = workers if workers > 0 else num_logical_cores()
    var surface = SurfaceMesh()
    var parts = List[Int]()
    for part in range(SURFACE_PART_COUNT):  # pragma: no branch
        var ids = posed.part_list(SurfacePart(part))
        if len(ids) == 0:
            continue
        var box = part_box(posed, ids)
        if box[0].x > box[1].x:
            # Only carvers: nothing to mesh.
            continue
        var cell = animal.eye_cell if part == EYEBALL.value else animal.cell
        var piece = mesh_part(
            posed,
            ids,
            box[0],
            box[1],
            Length(Float32(cell), METER),
            workers=threads,
        )
        for _ in range(piece.vertex_count()):
            parts.append(part)
        merge(surface, piece)
    var count = surface.vertex_count()
    if count == 0:
        raise Error("The animal's sculpt made no surface")
    var occlusion = bake_occlusion(
        posed,
        surface,
        animal.cell / animal.options.quality.resolution(),
        threads,
    )
    var colors = List[Float32](length=count * 3, fill=0.0)
    var classes = List[Int](length=count, fill=0)
    var unit = animal.cell / animal.options.quality.resolution()
    for v in range(count):  # pragma: no branch
        var slot = surface.vertex_block[v]
        var start = surface.list_start[slot]
        var p = surface.vertex(v)
        var pair = posed.nearest_pair_span(
            surface.lists, start, start + surface.list_count[slot], p
        )
        var n = surface.normal(v)
        var paint = _paint(animal, posed, inverse, pair[0], p, n, parts[v])
        if pair[1] >= 0:
            # Near a joint the colors of the two bones blend over the
            # solids' blend radius, as their surfaces do.
            var d1 = posed.distance(pair[0], p)
            var d2 = posed.distance(pair[1], p)
            var reach = max(posed.prims[pair[0]].k, posed.prims[pair[1]].k)
            var w = 0.5 * (1.0 - smoothstep(0.0, max(reach, 1e-6), d2 - d1))
            if w > 0.01:
                var other = _paint(
                    animal, posed, inverse, pair[1], p, n, parts[v]
                )
                if other.surface == paint.surface:
                    paint.color = mix3(paint.color, other.color, w)
        var hair = paint.surface == FUR or paint.surface == FEATHER
        if hair:
            var bone = posed.prims[pair[0]].bone.value
            n = fur_normal(n, inverse[bone].apply(p), world[bone], unit)
            surface.normals[v * 3] = Float32(n.x)
            surface.normals[v * 3 + 1] = Float32(n.y)
            surface.normals[v * 3 + 2] = Float32(n.z)
        var ao = occlusion[v] if paint.surface != EYE else 1.0
        colors[v * 3] = Float32(paint.color.x * ao)
        colors[v * 3 + 1] = Float32(paint.color.y * ao)
        colors[v * 3 + 2] = Float32(paint.color.z * ao)
        classes[v] = paint.surface.value
    return _geometry(surface, colors^, classes)


def fur_normal(n: V3, bind: V3, world: Rigid, unit: Float64) -> V3:
    """Return a normal tilted by fur clumps.

    The clumps are fractal noise in the bind pose, a few cells across and
    stretched along the body, so they ride the skin. The noise's slope
    tilts the normal across the surface, which Lambert shading draws as
    a combed texture.

    Args:
        n: The surface normal, posed.
        bind: The vertex in the bind pose.
        world: Its bone's transform from bind to posed.
        unit: The species' finest cell, in meters.

    Returns:
        The tilted unit normal.
    """
    var f = 1.0 / (5.0 * unit)
    var q = V3(bind.x * f, bind.y * f, bind.z * f * 0.25)
    var e = 0.35
    var base = fbm3(q, 2)
    var g = V3(
        fbm3(q + V3(e, 0.0, 0.0), 2) - base,
        fbm3(q + V3(0.0, e, 0.0), 2) - base,
        fbm3(q + V3(0.0, 0.0, e), 2) - base,
    ) * (1.0 / e)
    var tilt = world.turn(g)
    var across = tilt - n * dot(tilt, n)
    var out = n + across * 0.3
    var l = length(out)
    return out * (1.0 / l) if l > 0.0 else n


def _paint(
    animal: Animal,
    posed: SdfModel,
    inverse: List[Rigid],
    near: Int,
    p: V3,
    n: V3,
    part: Int,
) raises -> Paint:
    var prim = posed.prims[near] if near >= 0 else posed.prims[0]
    var back = inverse[prim.bone.value]
    var bind = back.apply(p)
    var reference = _unwarp(animal.traits, bind)
    var d = p - prim.c
    var local = V3(dot(d, prim.ax), dot(d, prim.ay), dot(d, prim.az))
    var sample = CoatSample(
        reference,
        back.turn(n),
        local,
        prim.tag.value,
        prim.bone.value,
        SurfacePart(part),
    )
    if part == EYEBALL.value:
        return paint_eye(
            animal.look,
            local,
            prim.r.x,
            animal.eye.iris_r * prim.r.x / animal.eye.r,
        )
    return species_paint(
        animal.species,
        animal.palette,
        animal.traits,
        posed.tags[prim.tag.value],
        animal.rig.bones[prim.bone.value].name,
        sample,
    )


def _unwarp(t: Traits, q: V3) -> V3:
    # Undo the proportion warps by fixed-point steps. The size scales
    # every warp, so each step divides by it; the rest are small and
    # smooth, so the steps converge fast.
    var k = 1.0 / t.get("size")
    var p = q * k
    for _ in range(UNWARP_STEPS):  # pragma: no branch
        p = p - (t.warps.apply(p) - q) * (0.9 * k)
    return p


def bake_occlusion(
    model: SdfModel, surface: SurfaceMesh, unit: Float64, workers: Int
) raises -> List[Float64]:
    """Return how much of the open air each vertex sees, from the field.

    Each vertex samples the field at five distances along its normal. A
    sample nearer to the body than its own distance from the vertex is
    blocked. This is Inigo Quilez's distance field occlusion.

    Args:
        model: The posed sculpt.
        surface: The meshed surface.
        unit: The species' finest cell, in meters. The farthest sample is
            sixteen of them.
        workers: How many threads share the work.

    Returns:
        One factor per vertex, from about 0.35 in a deep crease to one in
        the open.

    Raises:
        Error: If the surface has no vertices.
    """
    var count = surface.vertex_count()
    if count == 0:
        raise Error("There is nothing to occlude")
    var solids = List[Int]()
    for i in range(len(model.prims)):
        if model.prims[i].part != EYEBALL:
            solids.append(i)
    var reach = 16.0 * unit
    var out = List[Float64](length=count, fill=1.0)
    var tasks = max(1, min(workers, count))
    var group = TaskGroup()
    for task in range(tasks):  # pragma: no branch
        group.create_task(
            _occlusion_task(
                Pointer(to=model).unsafe_origin_cast[ImmutAnyOrigin](),
                Pointer(to=surface).unsafe_origin_cast[ImmutAnyOrigin](),
                Pointer(to=solids).unsafe_origin_cast[MutAnyOrigin](),
                out.unsafe_ptr().unsafe_origin_cast[MutAnyOrigin](),
                reach,
                task * count // tasks,
                (task + 1) * count // tasks,
            )
        )
    group.wait()
    _ = len(solids)
    return out^


async def _occlusion_task(
    model: Pointer[SdfModel, ImmutAnyOrigin],
    surface: Pointer[SurfaceMesh, ImmutAnyOrigin],
    solids: Pointer[List[Int], MutAnyOrigin],
    shade: MutPointer[Float64, MutAnyOrigin],
    reach: Float64,
    first: Int,
    past: Int,
):
    """Bake the occlusion of a run of vertices.

    The solids near each run are culled once per block of vertices.
    """
    var last_slot = -1
    var near = List[Int]()
    for v in range(first, past):  # pragma: no branch
        var slot = surface[].vertex_block[v]
        var p = surface[].vertex(v)
        if slot != last_slot:
            near = model[].cull(solids[], p, reach * 2.0, 0.0)
            last_slot = slot
        var n = surface[].normal(v)
        var blocked = 0.0
        var total = 0.0
        var weight = 1.0
        for i in range(OCCLUSION_SAMPLES):  # pragma: no branch
            var h = reach * Float64(i + 1) / Float64(OCCLUSION_SAMPLES)
            var d = model[].eval_list(near, p + n * h)
            blocked += weight * min(max((h - d) / h, 0.0), 1.0)
            total += weight
            weight *= 0.75
        var open = 1.0 - blocked / total
        shade[unsafe_offset=v] = 0.35 + 0.65 * open * sqrt(open)


def _geometry(
    surface: SurfaceMesh, var colors: List[Float32], classes: List[Int]
) raises -> BufferGeometry:
    """Gather the surface into a geometry, its triangles grouped by class."""
    var g = BufferGeometry()
    g.set_attribute(
        String(POSITION), BufferAttribute(surface.positions.copy(), 3)
    )
    g.set_attribute(String(NORMAL), BufferAttribute(surface.normals.copy(), 3))
    g.set_attribute(String(COLOR), BufferAttribute(colors^, 3))
    var buckets = List[List[Int]]()
    for _ in range(SURFACE_CLASS_COUNT):  # pragma: no branch
        buckets.append(List[Int]())
    var idx = surface.indices.copy()
    for t in range(0, len(idx), 3):
        # A triangle wears the class most of its corners have, and the
        # first corner's when all three differ.
        var a = classes[idx[t]]
        var b = classes[idx[t + 1]]
        var c = classes[idx[t + 2]]
        var k = b if b == c else a
        buckets[k].append(idx[t])
        buckets[k].append(idx[t + 1])
        buckets[k].append(idx[t + 2])
    var index = List[Int]()
    var starts = List[Int]()
    for k in range(SURFACE_CLASS_COUNT):  # pragma: no branch
        starts.append(len(index))
        index.extend(buckets[k].copy())
    g.set_index(index^)
    for k in range(SURFACE_CLASS_COUNT):  # pragma: no branch
        var end = starts[k + 1] if k + 1 < SURFACE_CLASS_COUNT else len(g.index)
        if end > starts[k]:
            g.add_group(starts[k], end - starts[k], MaterialIndex(k))
    return g^


def animal_materials() raises -> List[Material]:
    """Return one material per surface class, in `SurfaceClass` order.

    Each takes its color from the vertex colors. Fur and feathers are
    matte. Skin has a soft sheen. The nose and wet skin have a tight
    highlight. Keratin, scales and chitin are glossy, and the eye is the
    glossiest.

    Returns:
        Nine materials, for a mesh's material list.

    Raises:
        Error: If a material refuses its settings.
    """
    var white = Color(255, 255, 255)
    var out = List[Material]()
    out.append(Material(white, kind=LAMBERT, vertex_colors=True))
    out.append(
        Material(
            white,
            kind=PHONG,
            specular=Color(28, 26, 24),
            shininess=12.0,
            vertex_colors=True,
        )
    )
    out.append(
        Material(
            white,
            kind=PHONG,
            specular=Color(70, 70, 72),
            shininess=38.0,
            vertex_colors=True,
        )
    )
    out.append(
        Material(
            white,
            kind=PHONG,
            specular=Color(90, 90, 92),
            shininess=60.0,
            vertex_colors=True,
        )
    )
    out.append(
        Material(
            white,
            kind=PHONG,
            specular=Color(60, 58, 54),
            shininess=30.0,
            vertex_colors=True,
        )
    )
    out.append(
        Material(
            white,
            kind=PHONG,
            specular=Color(50, 52, 50),
            shininess=40.0,
            vertex_colors=True,
        )
    )
    out.append(
        Material(
            white,
            kind=PHONG,
            specular=Color(80, 80, 80),
            shininess=50.0,
            vertex_colors=True,
        )
    )
    out.append(Material(white, kind=LAMBERT, vertex_colors=True))
    out.append(
        Material(
            white,
            kind=PHONG,
            specular=Color(200, 200, 205),
            shininess=140.0,
            vertex_colors=True,
        )
    )
    return out^
