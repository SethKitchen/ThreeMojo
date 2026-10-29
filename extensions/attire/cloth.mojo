# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Cloth that falls, swings and drapes over the body: a cloak or a cape.

The solver is extended position-based dynamics, XPBD (Macklin, Müller
and Chentanez 2016), stepped as "Small Steps in Physics Simulation"
(Macklin et al. 2019) steps it: each frame is cut into substeps, and
each substep makes one pass over the constraints.

- Each particle moves on by its velocity and falls under gravity.
- Each constraint keeps two particles at their rest distance. Its
  compliance, in meters per newton, says how far it gives; zero is
  rigid. Structural and shear constraints keep the cloth from
  stretching; bending constraints, between particles two apart, keep it
  from folding sharply.
- A pinned particle follows its target, which a caller moves with the
  body. A free particle is tethered to the nearest pinned one, never
  farther from it than at rest: the long range attachments of Kim,
  Chentanez and Müller-Fischer (2012), which keep a garment from
  stretching under its own weight.
- A free particle is pushed out of each collider, a capsule on a bone.

The constraints are colored so that no two of one color share a
particle (Fratarcangeli, Tibaldo and Pellacini 2016). The constraints of
one color are solved at once, each on its own two particles, so the
pass gives the same result, bit for bit, on one thread or on many. A
GPU kernel can run the same schedule.

`Cloak` hangs a cloak from a person's shoulders, pinned to the chest
bone, and steps it with the animation.

This is not a three.js port. See Extensions.

    var cloak = add_cloak(scene, assets, person, wool_cloak())
    mixer.update(scene, step)
    scene.update()
    cloak.step(scene, assets, step)
"""

from std.math import sqrt

from core.assets import Assets
from core.buffer_attribute import BufferAttribute
from core.buffer_geometry import POSITION, BufferGeometry
from core.geometry_store import GeometryId
from core.object3d import NodeId, Object3D
from core.scene import Scene
from extensions.attire.dye import paint, DYE
from extensions.attire.fabric import fabric_material
from extensions.attire.kinds import FabricKind, WOOL, require_fabric_kind
from extensions.attire.springs import SpringCollider, body_colliders, push_out
from extensions.humanoid.rig.game import GameHumanoid
from extensions.humanoid.rig.joints import (
    CHEST,
    LEFT_UPPER_ARM,
    RIGHT_UPPER_ARM,
)
from materials.material import DOUBLE_SIDE
from math.vector3 import Vector3
from objects.mesh import Mesh
from render.framebuffer import Color
from render.tasks import TaskGroup
from units.si import Duration, Length, METER, SECOND

comptime MAX_COLORS = 62
"""The most colors the coloring can use; a grid's constraints need few."""
comptime TASK_CONSTRAINTS = 256
"""The fewest constraints a task takes, below which one thread is faster."""


struct ClothSettings(Copyable, ImplicitlyCopyable, Movable):
    """How a cloth moves."""

    var substeps: Int
    """Substeps a frame, each one pass over the constraints."""
    var gravity: Vector3
    """Gravity, in meters per second squared."""
    var damping: Float32
    """The share of its velocity a particle loses each substep."""
    var stretch: Float32
    """The compliance of the structural and shear constraints, m/N."""
    var bend: Float32
    """The compliance of the bending constraints, m/N."""
    var thickness: Float32
    """How far the cloth is kept off a collider, in meters."""

    def __init__(out self):
        """Take settings for a wool cloak at thirty frames a second."""
        self.substeps = 10
        self.gravity = Vector3(0, -9.81, 0)
        self.damping = 0.004
        self.stretch = 0.0
        self.bend = 2e-4
        self.thickness = 0.012

    def check(self) raises:
        """Refuse settings the solver cannot use.

        Raises:
            Error: If the substeps are not one through a thousand, or the
                damping, a compliance or the thickness is out of range.
        """
        if self.substeps < 1 or self.substeps > 1000:
            raise Error("A cloth needs one through a thousand substeps")
        if not (self.damping >= 0 and self.damping < 1):
            raise Error("A cloth's damping must be at least zero, below one")
        if not (self.stretch >= 0 and self.stretch < 1):
            raise Error("A cloth's stretch compliance must be zero or more")
        if not (self.bend >= 0 and self.bend < 1):
            raise Error("A cloth's bend compliance must be zero or more")
        if not (self.thickness >= 0 and self.thickness < 1):
            raise Error("A cloth's thickness must be zero or more")


def color_constraints(
    pairs: List[Int], particles: Int
) raises -> List[List[Int]]:
    """Color constraints so that no two of one color share a particle.

    Each constraint takes the lowest color neither of its particles has
    yet: a greedy coloring.

    Args:
        pairs: Two particles per constraint.
        particles: How many particles there are.

    Returns:
        The constraints of each color.

    Raises:
        Error: If a pair names a particle out of range, or the
            constraints need more than `MAX_COLORS` colors.
    """
    var used = List[Int](length=particles, fill=0)
    var colors = List[List[Int]]()
    for c in range(len(pairs) // 2):
        var i = pairs[2 * c]
        var j = pairs[2 * c + 1]
        if i < 0 or j < 0 or i >= particles or j >= particles:
            raise Error("A cloth constraint names a particle out of range")
        var taken = used[i] | used[j]
        var color = 0
        while (taken >> color) & 1 == 1:
            color += 1
        if color >= MAX_COLORS:
            raise Error("A cloth's constraints need too many colors")
        while len(colors) <= color:
            colors.append(List[Int]())
        colors[color].append(c)
        used[i] |= 1 << color
        used[j] |= 1 << color
    return colors^


def glide(start: Vector3, target: Vector3, share: Float32) -> Vector3:
    """Return where a pinned particle is, a share of the way to its target.

    Shared by `ClothSolver` and `GpuCloth`.

    Args:
        start: Where it was at the start of the step.
        target: Where it is to be at the end of the step.
        share: How far through the step, zero through one.

    Returns:
        The particle's place.
    """
    return start + (target - start) * share


def predict(
    point: Vector3, previous: Vector3, damping: Float32, fall: Vector3
) -> Vector3:
    """Return where a free particle goes in one substep, before the
    constraints move it: on along its damped velocity, and down.

    Shared by `ClothSolver` and `GpuCloth`.

    Args:
        point: Where it is.
        previous: Where it was a substep ago.
        damping: The share of its velocity lost each substep.
        fall: Gravity times the substep's length squared.

    Returns:
        The particle's predicted place.
    """
    var velocity = (point - previous) * (1 - damping)
    return point + velocity + fall


def relax_pair(
    a: Vector3,
    b: Vector3,
    weight_a: Float32,
    weight_b: Float32,
    rest: Float32,
    compliance: Float32,
    scale: Float32,
) -> Tuple[Vector3, Vector3]:
    """Settle one distance constraint: XPBD with its multiplier starting
    at zero, as one pass a substep has it.

    Shared by `ClothSolver` and `GpuCloth`.

    Args:
        a: One particle.
        b: The other particle.
        weight_a: The inverse mass of `a`, zero if it is pinned.
        weight_b: The inverse mass of `b`.
        rest: The constraint's rest distance, in meters.
        compliance: The constraint's compliance.
        scale: One over the substep's length squared.

    Returns:
        The two particles' new places. They do not move when they meet or
        when both are pinned.
    """
    var d = b - a
    var length = d.length()
    var total = weight_a + weight_b
    if length <= 1e-9 or total <= 0:
        return (a, b)
    var gap = length - rest
    var step = -gap / (total + compliance * scale)
    var n = d * (1 / length)
    return (a - n * (step * weight_a), b + n * (step * weight_b))


def settle(point: Vector3, anchor: Vector3, reach: Float32) -> Vector3:
    """Return a particle held within its reach of the pin it is tethered to.

    Shared by `ClothSolver` and `GpuCloth`.

    Args:
        point: The particle.
        anchor: Its pin.
        reach: How far it may stand from the pin, in meters.

    Returns:
        The particle, or the point at its reach toward it.
    """
    var away = point - anchor
    var length = away.length()
    if length > reach:
        return anchor + away * (reach / length)
    return point


struct ClothSolver(Movable):
    """A cloth's particles, its constraints, and how it moves."""

    var points: List[Vector3]
    """Where each particle is."""
    var previous: List[Vector3]
    """Where each particle was a substep ago."""
    var weights: List[Float32]
    """Each particle's inverse mass: zero for a pinned one."""
    var targets: List[Vector3]
    """Where each pinned particle is to be at the end of the step."""
    var pairs: List[Int]
    """Two particles per constraint."""
    var rests: List[Float32]
    """Each constraint's rest distance, in meters."""
    var bending: List[Bool]
    """Whether each constraint is a bending one."""
    var colors: List[List[Int]]
    """The constraints of each color."""
    var tethers: List[Int]
    """For each particle, its nearest pinned particle; itself when the cloth
    has no pin; -1 for a pinned particle."""
    var reaches: List[Float32]
    """For each particle, how far it may stand from that pin."""
    var settings: ClothSettings
    """How the cloth moves."""
    var starts: List[Vector3]
    """One end of each collider, in world space."""
    var ends: List[Vector3]
    """The other end of each collider."""
    var radii: List[Float32]
    """Each collider's radius."""

    def __init__(
        out self,
        var points: List[Vector3],
        pinned: List[Bool],
        var pairs: List[Int],
        var bending: List[Bool],
        settings: ClothSettings,
    ) raises:
        """Make a cloth at rest, as it is given.

        Args:
            points: Each particle's place.
            pinned: Whether each particle is pinned.
            pairs: Two particles per constraint.
            bending: Whether each constraint is a bending one.
            settings: How it moves.

        Raises:
            Error: If the lists do not match, the settings do not check,
                or the constraints cannot be colored.
        """
        settings.check()
        var count = len(points)
        if len(pinned) != count:
            raise Error("A cloth needs one pin flag per particle")
        if len(pairs) != 2 * len(bending):
            raise Error("A cloth needs two particles per constraint")
        self.colors = color_constraints(pairs, count)
        self.weights = List[Float32](capacity=count)
        for k in range(count):
            self.weights.append(Float32(0) if pinned[k] else Float32(1))
        self.rests = List[Float32](capacity=len(bending))
        for c in range(len(bending)):
            self.rests.append(
                (points[pairs[2 * c + 1]] - points[pairs[2 * c]]).length()
            )
        # Tether each free particle to its nearest pin, at rest.
        self.tethers = List[Int](length=count, fill=-1)
        self.reaches = List[Float32](length=count, fill=0)
        for k in range(count):
            if pinned[k]:
                continue
            var best = -1
            var closest = Float32(1e30)
            for p in range(count):  # pragma: no branch
                if not pinned[p]:
                    continue
                var d = (points[k] - points[p]).length()
                if d < closest:
                    closest = d
                    best = p
            # A cloth with no pin tethers each free particle to itself,
            # at no reach: it stays where it is, and the colliders still
            # push it out.
            if best < 0:
                best = k
                closest = 0
            self.tethers[k] = best
            self.reaches[k] = closest
        self.previous = points.copy()
        self.targets = points.copy()
        self.points = points^
        self.pairs = pairs^
        self.bending = bending^
        self.settings = settings
        self.starts = List[Vector3]()
        self.ends = List[Vector3]()
        self.radii = List[Float32]()

    def count(self) -> Int:
        """Return how many particles the cloth has.

        Returns:
            The particle count.
        """
        return len(self.points)

    def set_colliders(
        mut self,
        var starts: List[Vector3],
        var ends: List[Vector3],
        var radii: List[Float32],
    ) raises:
        """Set the capsules the cloth falls against, in world space.

        Args:
            starts: One end of each.
            ends: The other end of each.
            radii: Each one's radius.

        Raises:
            Error: If the lists differ in length.
        """
        if len(starts) != len(ends) or len(ends) != len(radii):
            raise Error("A collider needs two ends and a radius")
        self.starts = starts^
        self.ends = ends^
        self.radii = radii^

    def pin(mut self, particle: Int, target: Vector3) raises:
        """Move a pinned particle's target.

        Args:
            particle: A pinned particle.
            target: Where it is to be at the end of the next step.

        Raises:
            Error: If the particle is out of range or not pinned.
        """
        if particle < 0 or particle >= self.count():
            raise Error("No cloth particle has that index")
        if self.weights[particle] != 0:
            raise Error("Only a pinned particle has a target")
        self.targets[particle] = target

    def _relax(mut self, constraint: Int, scale: Float32):
        """Settle one constraint with `relax_pair`."""
        var i = self.pairs[2 * constraint]
        var j = self.pairs[2 * constraint + 1]
        var compliance = self.settings.stretch
        if self.bending[constraint]:
            compliance = self.settings.bend
        var moved = relax_pair(
            self.points[i],
            self.points[j],
            self.weights[i],
            self.weights[j],
            self.rests[constraint],
            compliance,
            scale,
        )
        self.points[i] = moved[0]
        self.points[j] = moved[1]

    def _relax_run(mut self, color: Int, first: Int, past: Int, scale: Float32):
        """Settle a run of one color's constraints."""
        for k in range(first, past):  # pragma: no branch
            self._relax(self.colors[color][k], scale)

    def step(mut self, time: Duration, workers: Int = 1) raises:
        """Move the cloth one frame.

        Args:
            time: The frame's length, above zero.
            workers: Threads that settle each color at once, one or more.

        Raises:
            Error: If the settings do not check, the time is not above
                zero, or there are no workers.
        """
        self.settings.check()
        var dt = Float32(time.to(SECOND))
        if not (dt > 0 and dt < 1e6):
            raise Error("A cloth's step must be above zero")
        if workers < 1:
            raise Error("A cloth needs one or more workers")
        var substeps = self.settings.substeps
        var h = dt / Float32(substeps)
        # A compliance alpha works as alpha / h^2 in a substep of h.
        var scale = 1 / (h * h)
        var fall = self.settings.gravity * (h * h)
        var from_pins = self.points.copy()
        for s in range(substeps):  # pragma: no branch
            var share = Float32(s + 1) / Float32(substeps)
            for k in range(self.count()):
                var now = self.points[k]
                if self.weights[k] == 0:
                    self.points[k] = glide(from_pins[k], self.targets[k], share)
                else:
                    self.points[k] = predict(
                        now, self.previous[k], self.settings.damping, fall
                    )
                self.previous[k] = now
            for color in range(len(self.colors)):
                var size = len(self.colors[color])
                var tasks = min(workers, size // TASK_CONSTRAINTS)
                if tasks <= 1:
                    self._relax_run(color, 0, size, scale)
                    continue
                var group = TaskGroup()
                for task in range(tasks):  # pragma: no branch
                    group.create_task(
                        _relax_task(
                            Pointer(to=self).unsafe_origin_cast[MutAnyOrigin](),
                            color,
                            task * size // tasks,
                            (task + 1) * size // tasks,
                            scale,
                        )
                    )
                group.wait()
            for k in range(self.count()):
                var pin = self.tethers[k]
                if pin < 0:
                    continue
                self.points[k] = settle(
                    self.points[k], self.points[pin], self.reaches[k]
                )
                for c in range(len(self.radii)):
                    self.points[k] = push_out(
                        self.points[k],
                        self.starts[c],
                        self.ends[c],
                        self.radii[c] + self.settings.thickness,
                    )


__async def _relax_task(
    cloth: Pointer[ClothSolver, MutAnyOrigin],
    color: Int,
    first: Int,
    past: Int,
    scale: Float32,
):
    cloth[]._relax_run(color, first, past, scale)


def _at(r: Int, c: Int, columns: Int) -> Int:
    """Return the particle in row `r` and column `c` of a grid."""
    return r * columns + c


def cloth_grid(
    corner: Vector3, across: Vector3, down: Vector3, columns: Int, rows: Int
) raises -> Tuple[List[Vector3], List[Int], List[Bool], List[Int]]:
    """Return a rectangle of cloth: its particles, its constraints and its
    triangles.

    Args:
        corner: The top left particle.
        across: The step from one column to the next.
        down: The step from one row to the next.
        columns: Particles across, two or more.
        rows: Particles down, two or more.

    Returns:
        The particles, row by row; two particles per constraint; whether
        each constraint bends; and three particles per triangle.

    Raises:
        Error: If there are fewer than two columns or rows.
    """
    if columns < 2 or rows < 2:
        raise Error("A cloth needs two or more columns and rows")
    var points = List[Vector3]()
    for r in range(rows):  # pragma: no branch
        for c in range(columns):  # pragma: no branch
            points.append(corner + across * Float32(c) + down * Float32(r))
    var pairs = List[Int]()
    var bending = List[Bool]()
    var triangles = List[Int]()

    for r in range(rows):  # pragma: no branch
        for c in range(columns):  # pragma: no branch
            if c + 1 < columns:
                pairs.append(_at(r, c, columns))
                pairs.append(_at(r, c + 1, columns))
                bending.append(False)
            if r + 1 < rows:
                pairs.append(_at(r, c, columns))
                pairs.append(_at(r + 1, c, columns))
                bending.append(False)
            if c + 1 < columns and r + 1 < rows:
                pairs.append(_at(r, c, columns))
                pairs.append(_at(r + 1, c + 1, columns))
                bending.append(False)
                pairs.append(_at(r, c + 1, columns))
                pairs.append(_at(r + 1, c, columns))
                bending.append(False)
                triangles.append(_at(r, c, columns))
                triangles.append(_at(r + 1, c, columns))
                triangles.append(_at(r, c + 1, columns))
                triangles.append(_at(r, c + 1, columns))
                triangles.append(_at(r + 1, c, columns))
                triangles.append(_at(r + 1, c + 1, columns))
            if c + 2 < columns:
                pairs.append(_at(r, c, columns))
                pairs.append(_at(r, c + 2, columns))
                bending.append(True)
            if r + 2 < rows:
                pairs.append(_at(r, c, columns))
                pairs.append(_at(r + 2, c, columns))
                bending.append(True)
    return (points^, pairs^, bending^, triangles^)


struct CloakCut(Copyable, Movable):
    """The shape and the look of a cloak."""

    var length: Length
    """From the shoulders to the hem."""
    var width: Length
    """Across, at the shoulders."""
    var columns: Int
    """Particles across."""
    var rows: Int
    """Particles down."""
    var fabric: FabricKind
    """What it is made of."""
    var dye: Color
    """Its color, sRGB."""
    var settings: ClothSettings
    """How it moves."""

    def __init__(
        out self,
        length: Length = Length(1.1, METER),
        width: Length = Length(0.5, METER),
        columns: Int = 13,
        rows: Int = 20,
        fabric: FabricKind = WOOL,
        dye: Color = Color(110, 24, 30),
    ):
        """Describe a cloak. A wool cloak to below the knee by default.

        Args:
            length: From the shoulders to the hem, on the template.
            width: Across at the shoulders, on the template.
            columns: Particles across, two or more.
            rows: Particles down, two or more.
            fabric: What it is made of.
            dye: Its color.
        """
        self.length = length
        self.width = width
        self.columns = columns
        self.rows = rows
        self.fabric = fabric
        self.dye = dye
        self.settings = ClothSettings()


struct Cloak(Movable):
    """A cloak on a person: its cloth, its mesh and its pins."""

    var solver: ClothSolver
    """The cloth."""
    var geometry: GeometryId
    """The mesh that draws it, in world space."""
    var node: NodeId
    """The node of that mesh, which does not move."""
    var anchor: NodeId
    """The bone its top row is pinned to."""
    var locals: List[Vector3]
    """Each pinned particle's place in the anchor bone's frame."""
    var pins: List[Int]
    """The pinned particles."""
    var colliders: List[SpringCollider]
    """The capsules it falls against."""
    var index: List[Int]
    """Three particles per triangle."""

    def __init__(
        out self,
        var solver: ClothSolver,
        geometry: GeometryId,
        node: NodeId,
        anchor: NodeId,
        var locals: List[Vector3],
        var pins: List[Int],
        var colliders: List[SpringCollider],
        var index: List[Int],
    ):
        """Hold a cloak's parts.

        Args:
            solver: The cloth.
            geometry: Its mesh's geometry.
            node: Its mesh's node.
            anchor: The bone it is pinned to.
            locals: Each pin's place in that bone's frame.
            pins: The pinned particles.
            colliders: What it falls against.
            index: Its triangles.
        """
        self.solver = solver^
        self.geometry = geometry
        self.node = node
        self.anchor = anchor
        self.locals = locals^
        self.pins = pins^
        self.colliders = colliders^
        self.index = index^

    def step(
        mut self,
        scene: Scene,
        mut assets: Assets,
        time: Duration,
        workers: Int = 1,
    ) raises:
        """Move the cloak one frame with the body.

        Call it after the animation has moved the bones and the scene
        has been updated.

        Args:
            scene: The scene, updated.
            assets: The store of the cloak's mesh.
            time: The frame's length.
            workers: Threads that settle the cloth.

        Raises:
            Error: If the scene is stale or the step is refused.
        """
        var bone = scene.world_matrix(self.anchor)
        for k in range(len(self.pins)):
            self.solver.pin(self.pins[k], bone.transform_point(self.locals[k]))
        var starts = List[Vector3]()
        var ends = List[Vector3]()
        var radii = List[Float32]()
        for collider in self.colliders:
            var world = scene.world_matrix(collider.node)
            starts.append(world.transform_point(collider.start))
            ends.append(world.transform_point(collider.end))
            radii.append(collider.radius)
        self.solver.set_colliders(starts^, ends^, radii^)
        self.solver.step(time, workers)
        assets.geometries.replace(self.geometry, self.mesh(assets))

    def mesh(self, assets: Assets) raises -> BufferGeometry:
        """Return the cloak's mesh at the cloth's present place.

        Args:
            assets: The store of the cloak's mesh.

        Returns:
            The mesh, with fresh positions and normals.

        Raises:
            Error: If the mesh is not in the store.
        """
        var mesh = assets.geometries.get(self.geometry).clone()
        var flat = List[Float32](capacity=3 * self.solver.count())
        for p in self.solver.points:
            flat.append(p.x)
            flat.append(p.y)
            flat.append(p.z)
        mesh.set_attribute(String(POSITION), BufferAttribute(flat^, 3))
        mesh.compute_vertex_normals()
        return mesh^


def add_cloak(
    mut scene: Scene,
    mut assets: Assets,
    person: GameHumanoid,
    cut: CloakCut = CloakCut(),
) raises -> Cloak:
    """Hang a cloak from a person's shoulders.

    The cloak's top row wraps the back of the neck from one shoulder to
    the other and is pinned to the chest bone. The cloth starts as a half
    cone round the back; call `step` a few times at rest to let it settle
    onto the body.

    Args:
        scene: The scene the person is in, updated.
        assets: The store for the cloak's mesh and look.
        person: The person.
        cut: The cloak's shape and look.

    Returns:
        The cloak.

    Raises:
        Error: If the cut is refused or the scene is stale.
    """
    require_fabric_kind(cut.fabric)
    var s = person.rig.stature / 1.8288
    var right = person.rig.joints[RIGHT_UPPER_ARM.value]
    var left = person.rig.joints[LEFT_UPPER_ARM.value]
    var chest = person.rig.joints[CHEST.value]
    var middle = (right + left) * 0.5
    var width = Float32(cut.width.to(METER)) * s
    var long = Float32(cut.length.to(METER)) * s
    var across = right - left
    across = across * (1 / across.length())
    var top = Vector3(middle.x, middle.y, chest.z) - across * (width / 2)
    var root = scene.world_matrix(person.root)
    var grid = cloth_grid(
        top,
        across * (width / Float32(cut.columns - 1)),
        Vector3(0, -long / Float32(cut.rows - 1), 0),
        cut.columns,
        cut.rows,
    )
    # The top row wraps the back of the neck, from one shoulder round to
    # the other. Each row below takes the same curve round the back, a
    # little wider and farther back as it falls, as a cloak that hangs
    # from the shoulders does: a half cone round the body.
    var back = Vector3(0, 0, -1)
    var wrap = 0.13 * s
    var centre = Vector3(middle.x, middle.y + 0.04 * s, chest.z)
    for r in range(cut.rows):  # pragma: no branch
        var fall = Float32(r) / Float32(cut.rows - 1)
        var spread = 1 + 0.35 * fall
        for c in range(cut.columns):  # pragma: no branch
            var t = Float32(c) / Float32(cut.columns - 1) * 2 - 1
            var round = sqrt(max(Float32(0), 1 - t * t))
            var p = (
                centre
                + across * (t * spread * width / 2)
                + back * (spread * wrap * (0.3 + 0.7 * round))
                + Vector3(0, -long * fall, 0)
            )
            grid[0][r * cut.columns + c] = root.transform_point(p)
    var points = grid[0].copy()
    var pinned = List[Bool](length=len(points), fill=False)
    var pins = List[Int]()
    for c in range(cut.columns):  # pragma: no branch
        pinned[c] = True
        pins.append(c)
    var solver = ClothSolver(
        points.copy(), pinned, grid[1].copy(), grid[2].copy(), cut.settings
    )
    var anchor = person.bones[CHEST.value]
    var into = scene.world_matrix(anchor)
    into.invert()
    var locals = List[Vector3]()
    for p in pins:  # pragma: no branch
        locals.append(into.transform_point(points[p]))
    var mesh = BufferGeometry()
    var flat = List[Float32]()
    var uv = List[Float32]()
    for r in range(cut.rows):  # pragma: no branch
        for c in range(cut.columns):  # pragma: no branch
            var p = points[r * cut.columns + c]
            flat.append(p.x)
            flat.append(p.y)
            flat.append(p.z)
            uv.append(Float32(c) / Float32(cut.columns - 1))
            uv.append(Float32(r) / Float32(cut.rows - 1))
    mesh.set_attribute(String(POSITION), BufferAttribute(flat^, 3))
    mesh.set_attribute("uv", BufferAttribute(uv^, 2))
    var weights = List[Float32]()
    for _ in range(len(points)):  # pragma: no branch
        weights.append(1)
        weights.append(0)
        weights.append(0)
        weights.append(0)
    mesh.set_attribute(String(DYE), BufferAttribute(weights^, 4))
    mesh.set_index(grid[3].copy())
    mesh.compute_vertex_normals()
    paint(mesh, List[Color](length=4, fill=cut.dye))
    var look = fabric_material(cut.fabric, Color(255, 255, 255))
    look.side = DOUBLE_SIDE
    var node = scene.add(Object3D())
    var geometry = assets.geometries.add(mesh^)
    scene.add_mesh(Mesh(geometry, assets.materials.add(look), node))
    return Cloak(
        solver^,
        geometry,
        node,
        anchor,
        locals^,
        pins^,
        body_colliders(person),
        grid[3].copy(),
    )
