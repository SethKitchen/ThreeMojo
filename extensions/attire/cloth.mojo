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
bone, and steps it with the animation. `Cloak.ride` moves a far cloak
with its bone as one piece, for no solve. `move_cloaks` moves a crowd's
cloaks: it steps the near ones at once, a run of whole cloaks on each
thread, and lets the far ones ride.

This is not a three.js port. See Extensions.

    var cloak = add_cloak(scene, assets, person, wool_cloak())
    mixer.update(scene, step)
    scene.update()
    cloak.step(scene, assets, step)
"""

from std.math import isfinite, pi, sin, sqrt

from core.assets import Assets
from core.buffer_attribute import BufferAttribute
from core.buffer_geometry import NORMAL, POSITION, BufferGeometry
from core.geometry_store import GeometryId
from core.object3d import NodeId, Object3D
from core.scene import Scene
from extensions.attire.dye import paint, DYE
from extensions.attire.fabric import dye_sheen, fabric_material
from extensions.attire.kinds import (
    SECONDARY_DYE,
    TRIM_DYE,
    WOOL,
    FabricKind,
    require_fabric_kind,
)
from extensions.attire.springs import SpringCollider, body_colliders, push_out
from extensions.attire.surface import SurfaceMaps
from extensions.humanoid.rig.game import GameHumanoid
from extensions.humanoid.rig.joints import (
    CHEST,
    LEFT_UPPER_ARM,
    NECK,
    RIGHT_UPPER_ARM,
)
from math.matrix4 import Matrix4
from math.vector3 import Vector3
from objects.mesh import Mesh
from render.framebuffer import Color
from render.tasks import TaskGroup
from units.si import Duration, Length, METER, SECOND

comptime MAX_COLORS = 62
"""The most colors the coloring can use; a grid's constraints need few."""
comptime TASK_CONSTRAINTS = 256
"""The fewest constraints a task takes, below which one thread is faster."""
comptime LINING_GAP = Float32(0.003)
"""How far inside a cloak's face its lining lies, in meters."""
comptime CLOAK_REACH = Float32(15.0)
"""How far from the camera `move_cloaks` steps a cloak, in meters, by
default."""
comptime TASK_PARTICLES = 256
"""The fewest particles a task settles, below which one thread is faster."""
comptime BOX_SLACK = Float32(1.0e-4)
"""How much a collider's box is grown past the capsule, in meters, so that
rounding never passes over a capsule that holds a particle."""
comptime CLEAR_PASSES = 3
"""The passes that push a new cloak's cloth out of its colliders."""
comptime CLOAK_FOLD_COLUMNS = 6
"""The fewest columns a cloak's fold takes."""
comptime CLOAK_FOLD = Float32(0.035)
"""How far a cloak's folds stand out of it at the hem, in meters on the
template."""


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
    var lows: List[Vector3]
    """The least corner of each collider's box, grown by the thickness."""
    var highs: List[Vector3]
    """The greatest corner of each collider's box, grown likewise."""

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
        self.lows = List[Vector3]()
        self.highs = List[Vector3]()

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

        Each capsule's box is grown by the settings' thickness as it is
        now: set the colliders again after the thickness changes.

        Args:
            starts: One end of each.
            ends: The other end of each.
            radii: Each one's radius.

        Raises:
            Error: If the lists differ in length.
        """
        if len(starts) != len(ends) or len(ends) != len(radii):
            raise Error("A collider needs two ends and a radius")
        # Each capsule's box, grown by the cloth's thickness and a hair
        # more: a particle outside it cannot touch the capsule.
        self.lows = List[Vector3](capacity=len(radii))
        self.highs = List[Vector3](capacity=len(radii))
        for c in range(len(radii)):
            var r = radii[c] + self.settings.thickness + BOX_SLACK
            var a = starts[c]
            var b = ends[c]
            self.lows.append(
                Vector3(min(a.x, b.x) - r, min(a.y, b.y) - r, min(a.z, b.z) - r)
            )
            self.highs.append(
                Vector3(max(a.x, b.x) + r, max(a.y, b.y) + r, max(a.z, b.z) + r)
            )
        self.starts = starts^
        self.ends = ends^
        self.radii = radii^

    def carry(mut self, move: Matrix4):
        """Move the whole cloth as one rigid piece.

        Each particle, its place a substep ago and each pin's target move
        alike, so the cloth keeps its shape and its velocity turns with
        it.

        Args:
            move: An affine move.
        """
        for k in range(self.count()):  # pragma: no branch
            self.points[k] = move.transform_point(self.points[k])
            self.previous[k] = move.transform_point(self.previous[k])
            self.targets[k] = move.transform_point(self.targets[k])

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
        self._advance(dt, workers)

    def _advance(mut self, dt: Float32, workers: Int):
        """Move the cloth one frame of `dt` seconds, checked."""
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
            var count = self.count()
            var tasks = min(workers, count // TASK_PARTICLES)
            if tasks <= 1:
                self._settle_run(0, count)
                continue
            var group = TaskGroup()
            for task in range(tasks):  # pragma: no branch
                group.create_task(
                    _settle_task(
                        Pointer(to=self).unsafe_origin_cast[MutAnyOrigin](),
                        task * count // tasks,
                        (task + 1) * count // tasks,
                    )
                )
            group.wait()

    def _settle_run(mut self, first: Int, past: Int):
        """Hold each free particle of a run to its tether, and push it out
        of each capsule.

        A particle writes only itself and reads only its pin, which never
        moves here, so runs of particles settle at once. A capsule whose
        box does not hold the particle is passed over: it could not move
        the particle.
        """
        for k in range(first, past):
            var pin = self.tethers[k]
            if pin < 0:
                continue
            var p = settle(self.points[k], self.points[pin], self.reaches[k])
            for c in range(len(self.radii)):
                var lo = self.lows[c]
                var hi = self.highs[c]
                var gap = max(
                    max(
                        max(lo.x - p.x, p.x - hi.x), max(lo.y - p.y, p.y - hi.y)
                    ),
                    max(lo.z - p.z, p.z - hi.z),
                )
                if gap > 0:
                    continue
                p = push_out(
                    p,
                    self.starts[c],
                    self.ends[c],
                    self.radii[c] + self.settings.thickness,
                )
            self.points[k] = p


__async def _settle_task(
    cloth: Pointer[ClothSolver, MutAnyOrigin],
    first: Int,
    past: Int,
):
    """Settle one run of a cloth's particles."""
    cloth[]._settle_run(first, past)


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
    """Across, at the shoulders, as far as the shoulders' joints."""
    var columns: Int
    """Particles across."""
    var rows: Int
    """Particles down."""
    var fabric: FabricKind
    """What it is made of."""
    var dye: Color
    """Its color, sRGB."""
    var trim: Optional[Color]
    """The color of its hem and its two edges, sRGB, or none."""
    var lining: Optional[Color]
    """The color of its inside, sRGB, or none for its dye."""
    var folds: Int
    """The folds across it, zero for a flat cloak."""
    var flare: Float32
    """How much wider its hem is than its top, as a share of its width."""
    var settings: ClothSettings
    """How it moves."""

    def __init__(
        out self,
        length: Length = Length(1.1, METER),
        width: Length = Length(0.5, METER),
        columns: Int = 25,
        rows: Int = 28,
        fabric: FabricKind = WOOL,
        dye: Color = Color(110, 24, 30),
        trim: Optional[Color] = None,
        folds: Int = 3,
        flare: Float32 = 1.0,
        lining: Optional[Color] = None,
    ):
        """Describe a cloak. A wool cloak to below the knee by default.

        Args:
            length: From the shoulders to the hem, on the template.
            width: Across at the shoulders, on the template.
            columns: Particles across, two or more.
            rows: Particles down, two or more.
            fabric: What it is made of.
            dye: Its color.
            trim: The color of its hem and its edges, or none.
            folds: The folds across it, zero or more, with six columns
                or more for each fold. Fewer columns would fold the cloth
                at every other one, and the hem would hang jagged.
            flare: How much wider its hem is than its top, zero or more.
                One, the default, makes the hem twice as wide: there is
                cloth to spare round the legs, so it falls in folds.
            lining: The color of its inside, or none for its dye.
        """
        self.length = length
        self.width = width
        self.columns = columns
        self.rows = rows
        self.fabric = fabric
        self.dye = dye
        self.trim = trim
        self.folds = folds
        self.flare = flare
        self.lining = lining
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
    var anchored: Matrix4
    """The anchor bone's place in the world when the cloak last moved."""

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
        var anchored: Matrix4,
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
            anchored: The anchor bone's place in the world now.
        """
        self.solver = solver^
        self.geometry = geometry
        self.node = node
        self.anchor = anchor
        self.locals = locals^
        self.pins = pins^
        self.colliders = colliders^
        self.index = index^
        self.anchored = anchored^

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
        self.follow(scene)
        self.solver.step(time, workers)
        assets.geometries.replace(self.geometry, self.mesh(assets))

    def follow(mut self, scene: Scene) raises:
        """Move the pins' targets and the colliders to where the bones are.

        `step` calls it. `move_cloaks` calls it for each cloak, then
        steps the cloths at once.

        Args:
            scene: The scene, updated.

        Raises:
            Error: If the scene is stale.
        """
        var bone = scene.world_matrix(self.anchor)
        for k in range(len(self.pins)):
            self.solver.pin(self.pins[k], bone.transform_point(self.locals[k]))
        self.anchored = bone^
        var starts = List[Vector3]()
        var ends = List[Vector3]()
        var radii = List[Float32]()
        for collider in self.colliders:
            var world = scene.world_matrix(collider.node)
            starts.append(world.transform_point(collider.start))
            ends.append(world.transform_point(collider.end))
            radii.append(collider.radius)
        self.solver.set_colliders(starts^, ends^, radii^)

    def ride(mut self, scene: Scene, mut assets: Assets) raises:
        """Move the cloak with its anchor bone as one rigid piece.

        A cloak far from the camera need not be stepped: riding costs a
        move of each particle, not a solve. It keeps its folds as they
        lay and swings on from them at the next `step`.

        Args:
            scene: The scene, updated.
            assets: The store of the cloak's mesh.

        Raises:
            Error: If the scene is stale.
        """
        var bone = scene.world_matrix(self.anchor)
        var back = self.anchored.copy()
        back.invert()
        var move = bone * back
        # A bone's move is affine; its inverse's rounding is not.
        for column in range(3):  # pragma: no branch
            move.put(3, column, 0)
        move.put(3, 3, 1)
        self.solver.carry(move)
        self.anchored = bone^
        assets.geometries.replace(self.geometry, self.mesh(assets))

    def mesh(self, assets: Assets) raises -> BufferGeometry:
        """Return the cloak's mesh at the cloth's present place.

        Args:
            assets: The store of the cloak's mesh.

        Returns:
            The mesh, with fresh positions and normals: the face, one
            vertex for each particle, then the lining.

        Raises:
            Error: If the mesh is not in the store.
        """
        var mesh = assets.geometries.get(self.geometry).clone()
        var count = self.solver.count()
        var flat = List[Float32](capacity=6 * count)
        for _ in range(2):  # pragma: no branch
            for p in self.solver.points:
                flat.append(p.x)
                flat.append(p.y)
                flat.append(p.z)
        mesh.set_attribute(String(POSITION), BufferAttribute(flat^, 3))
        mesh.compute_vertex_normals()
        # The lining's normals look in: it lies `LINING_GAP` along them,
        # inside the face. Its normals stay as they are.
        var lined = List[Float32](capacity=6 * count)
        for p in self.solver.points:
            lined.append(p.x)
            lined.append(p.y)
            lined.append(p.z)
        ref normals = mesh.attribute_view(String(NORMAL))
        for k in range(count):
            var p = self.solver.points[k] + normals.vector3(count + k) * (
                LINING_GAP
            )
            lined.append(p.x)
            lined.append(p.y)
            lined.append(p.z)
        mesh.set_attribute(String(POSITION), BufferAttribute(lined^, 3))
        return mesh^


def add_cloak(
    mut scene: Scene,
    mut assets: Assets,
    person: GameHumanoid,
    cut: CloakCut = CloakCut(),
    over: List[SpringCollider] = List[SpringCollider](),
) raises -> Cloak:
    """Hang a cloak from a person's shoulders.

    The cloak's top row wraps the back of the neck from one shoulder to
    the other and is pinned to the chest bone. The cloth starts as a half
    cone round the back, pushed out of the colliders; call `step` a few
    times at rest to let it settle onto the body. Its folds stand out of
    the cone, shallow at the neck and `CLOAK_FOLD` deep at the hem. The
    cloth keeps them, as a cloak gathered at the neck keeps its folds:
    each constraint keeps its length in the folded cloth. Its texture
    coordinates are in meters, so its fabric's weave lies on it as on a
    garment.

    Args:
        scene: The scene the person is in, updated.
        assets: The store for the cloak's mesh and look.
        person: The person.
        cut: The cloak's shape and look.
        over: The capsules it falls against. None gives the body's
            capsules; `dressed_colliders` gives capsules over the
            person's garments.

    Returns:
        The cloak.

    Raises:
        Error: If the cut is refused or the scene is stale.
    """
    require_fabric_kind(cut.fabric)
    if cut.folds < 0:
        raise Error("A cloak's folds must be zero or more")
    if cut.folds * CLOAK_FOLD_COLUMNS > cut.columns - 1:
        raise Error("A cloak needs six columns for each of its folds")
    if not (cut.flare >= 0 and cut.flare <= 10):
        raise Error("A cloak's flare must be zero through ten")
    var s = person.rig.stature / 1.8288
    var right = person.rig.joints[RIGHT_UPPER_ARM.value]
    var left = person.rig.joints[LEFT_UPPER_ARM.value]
    var chest = person.rig.joints[CHEST.value]
    var middle = (right + left) * 0.5
    var long = Float32(cut.length.to(METER)) * s
    var across = right - left
    # The top's ends lie on the shoulders at the widest, not past them.
    var width = min(Float32(cut.width.to(METER)) * s, across.length())
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
    # The top row's middle lies at the base of the neck, higher than its
    # ends on the shoulders, so the top edge falls from the neck along
    # the slope of the shoulders.
    var rise = max(Float32(0), person.rig.joints[NECK.value].y - centre.y)
    for r in range(cut.rows):  # pragma: no branch
        var fall = Float32(r) / Float32(cut.rows - 1)
        var spread = 1 + cut.flare * fall
        var deep = CLOAK_FOLD * s * (0.2 + 0.8 * fall)
        for c in range(cut.columns):  # pragma: no branch
            var t = Float32(c) / Float32(cut.columns - 1) * 2 - 1
            var round = sqrt(max(Float32(0), 1 - t * t))
            var p = (
                centre
                + across * (t * spread * width / 2)
                + back * (spread * wrap * (0.3 + 0.7 * round))
                + Vector3(0, rise * (1 - t * t) - long * fall, 0)
            )
            # Each fold stands out of the cone, away from its axis.
            var away = Vector3(p.x - centre.x, 0, p.z - centre.z)
            away.normalize()
            var phase = Float32(pi) * Float32(cut.folds) * (t + 1)
            p = p + away * (deep * sin(phase))
            grid[0][r * cut.columns + c] = root.transform_point(p)
    var colliders = over.copy()
    if len(colliders) == 0:
        colliders = body_colliders(person)
    # The cloth starts out of the colliders, its pins too: a pin is never
    # pushed, so a pin inside a mantle would hold the cloak inside it.
    var starts = List[Vector3]()
    var ends = List[Vector3]()
    for collider in colliders:  # pragma: no branch
        var world = scene.world_matrix(collider.node)
        starts.append(world.transform_point(collider.start))
        ends.append(world.transform_point(collider.end))
    for _ in range(CLEAR_PASSES):  # pragma: no branch
        for k in range(len(grid[0])):  # pragma: no branch
            for c in range(len(colliders)):  # pragma: no branch
                grid[0][k] = push_out(
                    grid[0][k],
                    starts[c],
                    ends[c],
                    colliders[c].radius + cut.settings.thickness,
                )
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
    var anchored = scene.world_matrix(anchor)
    var into = anchored.copy()
    into.invert()
    var locals = List[Vector3]()
    for p in pins:  # pragma: no branch
        locals.append(into.transform_point(points[p]))
    # The cloak is two sheets: its face, and its lining a little inside
    # it, wound the other way. Each shows from its own side alone.
    var count = len(points)
    var mesh = BufferGeometry()
    var flat = List[Float32]()
    var uv = List[Float32]()
    for _ in range(2):  # pragma: no branch
        for r in range(cut.rows):  # pragma: no branch
            for c in range(cut.columns):  # pragma: no branch
                var p = points[r * cut.columns + c]
                flat.append(p.x)
                flat.append(p.y)
                flat.append(p.z)
                uv.append(width * Float32(c) / Float32(cut.columns - 1))
                uv.append(long * Float32(r) / Float32(cut.rows - 1))
    mesh.set_attribute(String(POSITION), BufferAttribute(flat^, 3))
    mesh.set_attribute("uv", BufferAttribute(uv^, 2))
    # The face takes the dye and the lining its own. The hem and the two
    # edges take the trim's dye on both.
    var weights = List[Float32]()
    for layer in range(2):  # pragma: no branch
        for r in range(cut.rows):  # pragma: no branch
            for c in range(cut.columns):  # pragma: no branch
                var edge = (
                    c == 0 or c == cut.columns - 1 or r == cut.rows - 1
                ) and Bool(cut.trim)
                var body = Float32(0) if edge else Float32(1)
                weights.append(body if layer == 0 else Float32(0))
                weights.append(body if layer == 1 else Float32(0))
                weights.append(Float32(1) if edge else Float32(0))
                weights.append(0)
    mesh.set_attribute(String(DYE), BufferAttribute(weights^, 4))
    # `cloth_grid` winds each triangle down, then across, from the right
    # shoulder toward the left: so wound, it looks forward, into the
    # body. The face is wound the other way, to look back; the lining as
    # the grid is.
    ref triangles = grid[3]
    var index = List[Int](capacity=2 * len(triangles))
    for t in range(len(triangles) // 3):  # pragma: no branch
        index.append(triangles[3 * t])
        index.append(triangles[3 * t + 2])
        index.append(triangles[3 * t + 1])
    for k in triangles:  # pragma: no branch
        index.append(count + k)
    mesh.set_index(index^)
    var dyes = List[Color](length=4, fill=cut.dye)
    if cut.trim:
        dyes[TRIM_DYE.value] = cut.trim.value()
    if cut.lining:
        dyes[SECONDARY_DYE.value] = cut.lining.value()
    paint(mesh, dyes)
    var look = fabric_material(cut.fabric, Color(255, 255, 255))
    dye_sheen(look, cut.dye)
    var maps = SurfaceMaps()
    maps.apply(look, assets, cut.fabric)
    var node = scene.add(Object3D())
    var geometry = assets.geometries.add(mesh^)
    scene.add_mesh(Mesh(geometry, assets.materials.add(look), node))
    var cloak = Cloak(
        solver^,
        geometry,
        node,
        anchor,
        locals^,
        pins^,
        colliders^,
        grid[3].copy(),
        anchored^,
    )
    # The lining stands in from the face from the first frame.
    assets.geometries.replace(geometry, cloak.mesh(assets))
    return cloak^


__async def _advance_task(
    cloaks: MutPointer[Cloak, MutAnyOrigin],
    near: MutPointer[Int, MutAnyOrigin],
    first: Int,
    past: Int,
    dt: Float32,
):
    """Step the cloths of a run of the near cloaks, one thread each."""
    for k in range(first, past):  # pragma: no branch
        cloaks[unsafe_offset=near[unsafe_offset=k]].solver._advance(dt, 1)


def move_cloaks(
    mut cloaks: List[Cloak],
    scene: Scene,
    mut assets: Assets,
    time: Duration,
    camera: Vector3,
    workers: Int = 1,
    reach: Length = Length(CLOAK_REACH, METER),
) raises:
    """Move a crowd's cloaks one frame: the near ones at once, on threads.

    A cloak whose anchor bone lies farther than `reach` from the camera
    rides its bone, as `Cloak.ride` says. Each near cloak follows its
    bones, and then the near cloaks' cloths step at once, a run of whole
    cloaks on each thread. A small cloth gains little from threads of its
    own; a crowd of them gains one thread's worth each.

    Args:
        cloaks: The cloaks.
        scene: The scene, updated.
        assets: The store of the cloaks' meshes.
        time: The frame's length.
        camera: Where the camera is, in the world.
        workers: Threads that step the near cloaks, one or more.
        reach: How far from the camera a cloak is stepped.

    Raises:
        Error: If the scene is stale, a step is refused, there are no
            workers, or `reach` is not positive and finite.
    """
    var meters = Float32(reach.to(METER))
    if not (isfinite(meters) and meters > 0):
        raise Error("A cloak's reach must be positive and finite")
    if workers < 1:
        raise Error("A cloth needs one or more workers")
    var dt = Float32(time.to(SECOND))
    if not (dt > 0 and dt < 1e6):
        raise Error("A cloth's step must be above zero")
    var near = List[Int]()
    for k in range(len(cloaks)):
        var at = scene.world_matrix(cloaks[k].anchor).transform_point(
            Vector3(0, 0, 0)
        )
        if (at - camera).length() > meters:
            cloaks[k].ride(scene, assets)
            continue
        cloaks[k].solver.settings.check()
        cloaks[k].follow(scene)
        near.append(k)
    var tasks = min(workers, len(near))
    if tasks > 0:
        var group = TaskGroup()
        for task in range(tasks):  # pragma: no branch
            group.create_task(
                _advance_task(
                    cloaks.unsafe_ptr().unsafe_origin_cast[MutAnyOrigin](),
                    near.unsafe_ptr().unsafe_origin_cast[MutAnyOrigin](),
                    task * len(near) // tasks,
                    (task + 1) * len(near) // tasks,
                    dt,
                )
            )
        group.wait()
    for k in near:
        assets.geometries.replace(cloaks[k].geometry, cloaks[k].mesh(assets))
