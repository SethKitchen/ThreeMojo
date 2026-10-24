# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""A field of grass in clusters, culled and thinned by distance.

**Why clusters.** A field of millions of blades is too much to keep and too
much to draw. A GPU-driven renderer cuts it into clusters, also called
meshlets. A compute pass tests each cluster against the view and picks
its level of detail, and only the clusters that stay are drawn. This
module does the same work on the CPU, before the draw:

1. `GrassField` cuts a square field into square clusters, and keeps only
   a bound and a seed for each. It stores no blade.
2. `select` gives each cluster a `ClusterFate` and a level. A cluster
   past the reach of the last level is `BEYOND`, and the ground's own
   color stands in for it. A cluster whose bound is outside the view is
   `CULLED`. The rest are `DRAWN`, at the first level whose reach holds
   them.
3. `build` grows a drawn cluster's blades again from its seed, bends them
   by the wind, and bakes them into one geometry.

**Why a level is a prefix.** The blades of a cluster are a stream: blade
`i` belongs to tuft `i % tufts`, and its place and shape come from a hash
of the cluster and `i`. So the first `n` blades are an even sample of the
whole cluster, with a few blades in every tuft. A level that keeps a
fraction `keep` of the blades builds the first `keep * blades` of the
stream. Nothing is sorted and nothing is stored, and the near blades of a
far level are the same blades as those of a near level.

**Why a thinned level is wider.** A level that keeps fewer blades widens
each by `keep ** -0.7`. The field keeps most of its cover, and a far
blade stays wider than a pixel, so it does not flicker in and out.
"""

from core.buffer_geometry import BufferGeometry
from extensions.vegetation.blade import Blade, BladeMesh, blade_triangles
from extensions.vegetation.checks import (
    require_between,
    require_count_between,
)
from extensions.vegetation.ground import Ground
from extensions.vegetation.kinds import (
    BEYOND,
    CULLED,
    DRAWN,
    DRY_GRASS,
    GRASS,
    POPPY,
    SEED_HEAD,
    BROADLEAF,
    BUTTERCUP,
    ClusterFate,
    PlantKind,
)
from extensions.vegetation.noise import hash01, value_noise
from extensions.vegetation.wind import Wind
from math.bounds import Sphere
from math.frustum import Frustum
from math.vector3 import Vector3
from std.math import ceil, cos, pi, pow, sin, sqrt
from units.si import DEGREE, METER, RADIAN, Angle, Duration, Length

# How a thinned level widens its blades: by `keep ** -COVER_EXPONENT`.
comptime COVER_EXPONENT = Float32(0.7)
# The most clusters a field can have.
comptime MAX_CLUSTERS = 1 << 20
# The width of a poppy's stem.
comptime STEM_WIDTH = Length(0.003, METER)
# How much taller than the grass round it a poppy stands, and a stalk
# with a seed head. A stalk stands above even short grass.
comptime POPPY_LIFT = Float32(1.15)
comptime BUTTERCUP_LIFT = Float32(0.9)
comptime SEED_LIFT = Float32(1.45)
# The height of short grass, as a fraction of the meadow's full height,
# and how tall the tallest tuft is, as a multiple of it.
comptime SHORT_GRASS = Float32(0.22)
comptime TALLEST_TUFT = Float32(1.3)
# The mean length of a broad leaf.
comptime LEAF_LENGTH = Float32(0.2)
# The share of the tufts that wind and rain have laid over: their blades
# arch over and lie, `LODGED_CURL` times as curled as a standing tuft's,
# up to `LODGED_MOST` degrees.
comptime LODGED = Float32(0.14)
comptime LODGED_CURL = Float32(2.4)
comptime LODGED_MOST = Float32(115)
# How wide a patch of one shade of green is, in meters.
comptime HUE_PATCH = Float32(3.5)
# How much a full gust brightens a blade's tip: a bent blade shows its lit
# face, so the gusts roll across the field as bands of light.
comptime GUST_GLINT = Float32(1.0)
# How far a blade's curl can turn from straight out of its tuft, in
# radians.
comptime SPLAY_JITTER = Float32(0.7)


struct LodBand(ImplicitlyCopyable):
    """One level of detail: how far it reaches, what fraction of the
    blades it keeps, and how many segments each blade has."""

    # The furthest a cluster's nearest point can be for this level.
    var reach: Length
    # The fraction of the blades this level builds, above 0 and up to 1.
    var keep: Float32
    # The segments of each blade, from 1 to 8.
    var segments: Int

    def __init__(out self, reach: Length, keep: Float32, segments: Int):
        """Create a level. `check` says whether it can be used.

        Args:
            reach: The furthest a cluster's nearest point can be.
            keep: The fraction of the blades it builds.
            segments: The segments of each blade.
        """
        self.reach = reach
        self.keep = keep
        self.segments = segments

    def check(self) raises:
        """Refuse a level that cannot be used.

        Raises:
            Error: If the reach is not from 0 to 100 kilometers, the keep
                is not from 0.001 to 1, or the segments are not from 1
                to 8.
        """
        require_between(
            self.reach.to(METER),
            0,
            1.0e5,
            "A level must reach from 0 to 100 kilometers",
        )
        require_between(
            self.keep, 0.001, 1, "A level must keep from 0.001 to 1"
        )
        require_count_between(
            self.segments, 1, 8, "A level must have from 1 to 8 segments"
        )

    def widen(self) -> Float32:
        """Return what this level multiplies each blade's width by.

        Returns:
            `keep ** -COVER_EXPONENT`: one for a level that keeps every
            blade, and more for a level that keeps fewer.
        """
        return pow(self.keep, -COVER_EXPONENT)


def default_bands() -> List[LodBand]:
    """Return the four levels of a meadow seen from head height.

    Returns:
        Every blade with four segments to 7 meters, 40 percent with three
        to 18 meters, 13 percent with two to 40 meters, and 4 percent with
        one to 85 meters.
    """
    return [
        LodBand(Length(7.0, METER), 1.0, 4),
        LodBand(Length(18.0, METER), 0.4, 3),
        LodBand(Length(40.0, METER), 0.13, 2),
        LodBand(Length(85.0, METER), 0.04, 1),
    ]


struct FieldParameters(Copyable, Movable):
    """What a grass field grows, and where."""

    # Which blades to grow.
    var seed: Int
    # The side of the square field, centered on the origin.
    var span: Length
    # The side of one square cluster.
    var cluster_size: Length
    # How many blades grow on a square meter of full cover.
    var density: Float32
    # How many blades a tuft has at full detail.
    var tuft_blades: Int
    # How far a tuft's blades spread from its middle.
    var tuft_radius: Length
    # The mean height of a blade on full cover.
    var height: Length
    # How far a blade's height can differ from the mean, as a fraction.
    var height_spread: Float32
    # The mean width of a blade at its root.
    var width: Length
    # The mean rest bend of a blade's tip.
    var curl: Angle
    # The fraction of the blades that are dry, where the ground is dry.
    var dry_share: Float32
    # The fraction of the tufts that hold a poppy, in a poppy drift.
    var poppy_share: Float32
    # The fraction of the blades that are stalks with seed heads.
    var seed_share: Float32
    # The fraction of the tufts that hold a broad-leaf plant, where weeds
    # grow most.
    var broadleaf_share: Float32
    # The fraction of the tufts that hold a buttercup, where weeds grow
    # most.
    var buttercup_share: Float32
    # The levels of detail, nearest first.
    var bands: List[LodBand]

    def __init__(out self):
        """Create the parameters of a lush meadow of tall grass."""
        self.seed = 1
        self.span = Length(120.0, METER)
        self.cluster_size = Length(4.0, METER)
        self.density = 700
        self.tuft_blades = 12
        self.tuft_radius = Length(0.09, METER)
        self.height = Length(0.55, METER)
        self.height_spread = 0.45
        self.width = Length(0.013, METER)
        self.curl = Angle(52.0, DEGREE)
        self.dry_share = 0.08
        self.poppy_share = 0.9
        self.seed_share = 0.012
        self.broadleaf_share = 0.25
        self.buttercup_share = 0.12
        self.bands = default_bands()

    def check(self) raises:
        """Refuse parameters that cannot grow a field.

        Raises:
            Error: If the span is not from 1 meter to 10 kilometers, the
                cluster is not from 25 centimeters to the span, the field
                has more than `MAX_CLUSTERS` clusters, the density is not
                from 0.01 to 100,000, a tuft has not from 1 to 64 blades,
                the tuft radius is not from 0 to 1 meter, the height is
                not from 1 centimeter to 2 meters, the spread is not from 0
                to 0.9, the width is not from 0.5 millimeter to 10
                centimeters, the curl is not from 0 to 75 degrees, a share
                is not from 0 to 1, there is no level, a level is refused,
                or the levels do not reach further and keep no more as
                they go.
        """
        require_between(
            self.span.to(METER),
            1,
            1.0e4,
            "A field must be from 1 meter to 10 kilometers across",
        )
        require_between(
            self.cluster_size.to(METER),
            0.25,
            self.span.to(METER),
            "A cluster must be from 25 centimeters to the field across",
        )
        var side = self.clusters_across()
        require_count_between(
            side * side,
            1,
            MAX_CLUSTERS,
            "A field must have at most 1,048,576 clusters",
        )
        require_between(
            self.density,
            0.01,
            1.0e5,
            "A field must grow from 0.01 to 100,000 blades a square meter",
        )
        require_count_between(
            self.tuft_blades, 1, 64, "A tuft must have from 1 to 64 blades"
        )
        require_between(
            self.tuft_radius.to(METER),
            0,
            1,
            "A tuft must spread from 0 to 1 meter",
        )
        require_between(
            self.height.to(METER),
            0.01,
            2,
            "Grass must be from 1 centimeter to 2 meters tall",
        )
        require_between(
            self.height_spread, 0, 0.9, "A height spread must be from 0 to 0.9"
        )
        require_between(
            self.width.to(METER),
            0.0005,
            0.1,
            "A blade must be from 0.5 millimeter to 10 centimeters wide",
        )
        require_between(
            self.curl.to(DEGREE), 0, 75, "A curl must be from 0 to 75 degrees"
        )
        require_between(
            self.dry_share, 0, 1, "The dry share must be from 0 to 1"
        )
        require_between(
            self.poppy_share, 0, 1, "The poppy share must be from 0 to 1"
        )
        require_between(
            self.seed_share, 0, 1, "The seed share must be from 0 to 1"
        )
        require_between(
            self.broadleaf_share,
            0,
            1,
            "The broad-leaf share must be from 0 to 1",
        )
        require_between(
            self.buttercup_share,
            0,
            1,
            "The buttercup share must be from 0 to 1",
        )
        require_count_between(
            len(self.bands), 1, 16, "A field must have from 1 to 16 levels"
        )
        for index in range(len(self.bands)):  # pragma: no branch
            self.bands[index].check()
            if index == 0:
                continue
            ref before = self.bands[index - 1]
            ref band = self.bands[index]
            if band.reach.value <= before.reach.value:
                raise Error("Each level must reach further than the one before")
            if band.keep > before.keep:
                raise Error("Each level must keep no more than the one before")

    def clusters_across(self) -> Int:
        """Return how many clusters go across one side of the field.

        Returns:
            The span over the cluster size, rounded up.
        """
        return Int(ceil(self.span.to(METER) / self.cluster_size.to(METER)))


@fieldwise_init
struct GrassCluster(ImplicitlyCopyable):
    """One square of the field: where it is, its bound, and how many
    blades and tufts it grows at full detail."""

    # The corner with the least x and z, in meters.
    var corner_x: Float32
    var corner_z: Float32
    # The middle of the bound, in meters.
    var center: Vector3
    # The radius of the bound, in meters. It holds every blade, bent as
    # far as a wind can bend it.
    var radius: Float32
    # How many blades the full level grows, and how many tufts they share.
    var blades: Int
    var tufts: Int

    def bound(self) -> Sphere:
        """Return the cluster's bounding sphere.

        Returns:
            The sphere that holds every blade of the cluster.
        """
        return Sphere(self.center, self.radius)


@fieldwise_init
struct ClusterChoice(ImplicitlyCopyable):
    """What a frame does with one cluster, and at which level."""

    var fate: ClusterFate
    # The level a drawn cluster is built at. Zero for the other fates.
    var band: Int


@fieldwise_init
struct FieldStats(ImplicitlyCopyable, Writable):
    """What one frame of a field drew, and what it left out."""

    var clusters: Int
    var drawn: Int
    var culled: Int
    var beyond: Int
    # The drawn clusters whose level grew no blade, where the ground is
    # bare. They are hidden.
    var empty: Int
    var blades: Int
    var triangles: Int

    def tally(mut self, fate: ClusterFate):
        """Count one cluster's fate.

        Args:
            fate: What the frame did with the cluster.
        """
        self.clusters += 1
        if fate == DRAWN:
            self.drawn += 1
        elif fate == CULLED:
            self.culled += 1
        else:
            self.beyond += 1


def no_stats() -> FieldStats:
    """Return the stats of a frame that has seen no cluster.

    Returns:
        All counts zero.
    """
    return FieldStats(0, 0, 0, 0, 0, 0, 0)


struct GrassField(Movable):
    """A square field of grass in clusters, on rolling ground."""

    var parameters: FieldParameters
    var ground: Ground
    var clusters: List[GrassCluster]

    def __init__(
        out self, var parameters: FieldParameters, ground: Ground
    ) raises:
        """Lay a field out in clusters. No blade is grown yet.

        Args:
            parameters: What the field grows.
            ground: The ground it grows on.

        Raises:
            Error: If `parameters.check` or `ground.check` refuses a value.
        """
        parameters.check()
        ground.check()
        self.parameters = parameters^
        self.ground = ground
        self.clusters = List[GrassCluster]()
        var side = self.parameters.clusters_across()
        var size = self.parameters.cluster_size.to(METER)
        var start = -self.parameters.span.to(METER) * 0.5
        var blades = max(
            1, Int(self.parameters.density * size * size + Float32(0.5))
        )
        var tufts = max(1, blades // self.parameters.tuft_blades)
        var tallest = self._tallest()
        var reach = size * Float32(0.7072) + self.parameters.tuft_radius.to(
            METER
        )
        self.clusters.reserve(side * side)
        for row in range(side):  # pragma: no branch
            for col in range(side):  # pragma: no branch
                var x0 = start + Float32(col) * size
                var z0 = start + Float32(row) * size
                var low = Float32(1.0e30)
                var high = Float32(-1.0e30)
                for k in range(9):  # pragma: no branch
                    var y = ground.height_at(
                        x0 + size * Float32(k % 3) * 0.5,
                        z0 + size * Float32(k // 3) * 0.5,
                    )
                    low = min(low, y)
                    high = max(high, y)
                # The ground can bulge between the nine samples.
                var margin = ground.hill_height.to(METER) * 0.25
                var across = reach + tallest
                var up = (high - low) * 0.5 + tallest + margin
                self.clusters.append(
                    GrassCluster(
                        x0,
                        z0,
                        Vector3(
                            x0 + size * 0.5, (low + high) * 0.5, z0 + size * 0.5
                        ),
                        sqrt(across * across + up * up),
                        blades,
                        tufts,
                    )
                )

    def full_blades(self) -> Int:
        """Return how many blades the field holds at full detail.

        Returns:
            The sum of every cluster's stream. Some of them do not grow,
            where the ground is bare.
        """
        var total = 0
        for index in range(len(self.clusters)):  # pragma: no branch
            total += self.clusters[index].blades
        return total

    def _tallest(self) -> Float32:
        """Return the tallest a blade can be, in meters."""
        return (
            self.parameters.height.to(METER)
            * TALLEST_TUFT
            * (1 + 0.5 * self.parameters.height_spread)
            * max(POPPY_LIFT, SEED_LIFT)
        )

    def band_for(self, distance: Length) -> Optional[Int]:
        """Return the first level whose reach holds a distance.

        Args:
            distance: How far a cluster's nearest point is.

        Returns:
            The level's index, or None past the last reach.
        """
        for index in range(len(self.parameters.bands)):  # pragma: no branch
            if distance.value <= self.parameters.bands[index].reach.value:
                return index
        return None

    def choose(
        self, index: Int, eye: Vector3, frustum: Frustum
    ) raises -> ClusterChoice:
        """Return what a frame does with one cluster.

        Args:
            index: The cluster.
            eye: Where the camera is, in meters.
            frustum: What the camera sees, in world space.

        Returns:
            `BEYOND` past the last reach, `CULLED` outside the view, and
            otherwise `DRAWN` at its level.

        Raises:
            Error: If there is no such cluster.
        """
        if index < 0 or index >= len(self.clusters):
            raise Error("A field has no cluster of that number")
        ref cluster = self.clusters[index]
        var near = max(
            Float32(0), (cluster.center - eye).length() - cluster.radius
        )
        var band = self.band_for(Length(near, METER))
        if not band:
            return ClusterChoice(BEYOND, 0)
        if not frustum.intersects_sphere(cluster.bound()):
            return ClusterChoice(CULLED, 0)
        return ClusterChoice(DRAWN, band.value())

    def select(
        self, eye: Vector3, frustum: Frustum
    ) raises -> List[ClusterChoice]:
        """Return what a frame does with every cluster, in order.

        Args:
            eye: Where the camera is, in meters.
            frustum: What the camera sees, in world space.

        Returns:
            One choice a cluster.

        Raises:
            Error: Never for a field this built.
        """
        var choices = List[ClusterChoice]()
        choices.reserve(len(self.clusters))
        for index in range(len(self.clusters)):  # pragma: no branch
            choices.append(self.choose(index, eye, frustum))
        return choices^

    def kept(self, index: Int, band: Int) raises -> Int:
        """Return how many blades of a cluster's stream a level builds.

        Some of them may not grow, where the ground is bare.

        Args:
            index: The cluster.
            band: The level.

        Returns:
            `keep * blades`, rounded up, at least one.

        Raises:
            Error: If there is no such cluster or level.
        """
        if index < 0 or index >= len(self.clusters):
            raise Error("A field has no cluster of that number")
        if band < 0 or band >= len(self.parameters.bands):
            raise Error("A field has no level of that number")
        var blades = self.clusters[index].blades
        var keep = self.parameters.bands[band].keep
        return max(1, min(blades, Int(ceil(keep * Float32(blades)))))

    def grow(self, index: Int, blade: Int) raises -> Optional[Blade]:
        """Grow one blade of a cluster's stream.

        Args:
            index: The cluster.
            blade: The blade's place in the stream, zero or more.

        Returns:
            The blade, or None where the ground is too bare for its tuft.

        Raises:
            Error: If there is no such cluster, or `blade` is negative.
        """
        if index < 0 or index >= len(self.clusters):
            raise Error("A field has no cluster of that number")
        if blade < 0:
            raise Error("A blade's place in the stream cannot be negative")
        ref p = self.parameters
        ref cluster = self.clusters[index]
        var seed = p.seed * 7919
        var tuft = blade % cluster.tufts
        var size = p.cluster_size.to(METER)
        var tx = cluster.corner_x + hash01(index, 2 * tuft, seed + 1) * size
        var tz = cluster.corner_z + hash01(index, 2 * tuft + 1, seed + 1) * size
        var cover = self.ground.cover(tx, tz)
        if hash01(index, tuft, seed + 3) >= cover:
            return None
        var key = blade * 16
        var turn = Float32(2) * Float32(pi)
        var spread = turn * hash01(index, key, seed + 5)
        var reach = p.tuft_radius.to(METER) * sqrt(
            hash01(index, key + 1, seed + 5)
        )
        var x = tx + cos(spread) * reach
        var z = tz + sin(spread) * reach
        # Each tuft is a plant of its own: its height, the width of its
        # blades, how far they droop, their color and their sway are its
        # own. Its blades vary round them.
        var traits = seed + 9
        var tall = SHORT_GRASS + (1 - SHORT_GRASS) * self.ground.tallness(
            tx, tz
        )
        var height = (
            p.height.to(METER)
            * tall
            * (0.75 + (TALLEST_TUFT - 0.75) * hash01(index, tuft, traits))
            * (1 + p.height_spread * (hash01(index, key + 2, seed + 5) - 0.5))
            * (0.55 + 0.45 * cover)
        )
        var broad = hash01(index, tuft, traits + 1)
        var width = (
            p.width.to(METER)
            * (0.55 + 1.3 * broad * broad)
            * (0.8 + 0.4 * hash01(index, key + 3, seed + 5))
        )
        var curl = (
            p.curl.to(DEGREE)
            * (0.45 + 1.1 * hash01(index, tuft, traits + 2))
            * (0.7 + 0.6 * hash01(index, key + 4, seed + 5))
        )
        if hash01(index, tuft, traits + 5) < LODGED:
            curl = min(curl * LODGED_CURL, LODGED_MOST)
        # A patch of the meadow is a deeper or a yellower green, and each
        # tuft and blade differs within it.
        var hue = value_noise(tx / HUE_PATCH, tz / HUE_PATCH, seed + 13)
        var shade = min(
            Float32(1),
            max(
                Float32(0),
                0.6 * hash01(index, tuft, traits + 3)
                + 0.15 * hash01(index, key + 7, seed + 5)
                + 0.8 * (hue - 0.5)
                + 0.12,
            ),
        )
        var phase = 0.8 * hash01(index, tuft, traits + 4) + 0.2 * hash01(
            index, key + 6, seed + 5
        )
        # The chance is a blade's and not a tuft's, so every level keeps
        # the same mix of kinds.
        var pick = hash01(index, key + 8, seed + 5)
        var kind = GRASS
        var poppy = p.poppy_share / Float32(p.tuft_blades)
        var weed = p.broadleaf_share / Float32(p.tuft_blades)
        var flower = p.buttercup_share / Float32(p.tuft_blades)
        if pick < poppy * self.ground.bloom(tx, tz):
            kind = POPPY
            height *= POPPY_LIFT
            width = STEM_WIDTH.to(METER)
            curl *= 0.3
        elif pick > 1 - p.dry_share * (0.3 + 1.4 * self.ground.dryness(x, z)):
            kind = DRY_GRASS
        elif hash01(index, key + 9, seed + 5) < p.seed_share:
            kind = SEED_HEAD
            height = height / (0.55 + 0.45 * cover) * SEED_LIFT / tall
            width = STEM_WIDTH.to(METER)
            curl *= 0.25
        elif hash01(index, key + 10, seed + 5) < weed * self.ground.weeds(x, z):
            kind = BROADLEAF
            height = LEAF_LENGTH * (
                0.6 + 0.8 * hash01(index, key + 11, seed + 5)
            )
            width = height * 0.5
        elif hash01(index, key + 12, seed + 5) < flower * self.ground.weeds(
            x, z
        ):
            kind = BUTTERCUP
            height *= BUTTERCUP_LIFT
            width = STEM_WIDTH.to(METER)
            curl *= 0.3
        # The blade curls out of its tuft, as the blades of a real tuft
        # fan out from the crown: its face turns a quarter turn back from
        # the way out, give or take `SPLAY_JITTER`.
        var facing = (
            spread
            - Float32(pi) * 0.5
            + SPLAY_JITTER * (hash01(index, key + 5, seed + 5) * 2 - 1)
        )
        return Blade(
            Vector3(x, self.ground.height_at(x, z), z),
            Angle(facing, RADIAN),
            Length(height, METER),
            Length(width, METER),
            Angle(curl, DEGREE),
            phase,
            shade,
            kind,
        )

    def build(
        self, index: Int, band: Int, wind: Wind, time: Duration
    ) raises -> Optional[BufferGeometry]:
        """Grow a cluster at a level, bend it by the wind, and bake it.

        Args:
            index: The cluster.
            band: The level.
            wind: The wind that bends the blades.
            time: The time since the wind began.

        Returns:
            One geometry in world space, with `position`, `normal`, `color`
            and an index. None if no blade of the level grows.

        Raises:
            Error: If there is no such cluster or level.
        """
        var count = self.kept(index, band)
        ref level = self.parameters.bands[band]
        var mesh = BladeMesh()
        mesh.reserve(count, level.segments)
        var widen = level.widen()
        for blade in range(count):  # pragma: no branch
            var grown = self.grow(index, blade)
            if not grown:
                continue
            ref placed = grown.value()
            var gust = wind.gust(placed.root.x, placed.root.z, time)
            var bend = wind.tip_bend(
                placed.root.x, placed.root.z, gust, placed.phase, time
            )
            mesh.add(placed, level.segments, bend, widen, GUST_GLINT * gust)
        if mesh.triangle_count() == 0:
            return None
        return mesh^.geometry()


def cluster_triangles(geometry: BufferGeometry) -> Int:
    """Return how many triangles a built cluster has.

    Args:
        geometry: A geometry `GrassField.build` returned.

    Returns:
        The triangle count.
    """
    return len(geometry.index) // 3
