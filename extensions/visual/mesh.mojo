# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""A builder of triangle meshes with normals, texture coordinates and colors.

Points are in a z-up engineering frame, in meters: x east, y north, z up.
`MeshBuilder` turns them into the y-up frame three.js draws in, with
(x, y, z) becoming (x, z, -y), as it adds them.

Texture coordinates are world coordinates in meters, projected along the
axis the face is most nearly normal to. A texture that repeats once per
`n` meters then lies at the same scale on every face, with no seams
between faces that meet.

- `triangle` and `quad` add flat faces.
- `prism` extrudes a polygon of a section along a straight run, and
  `loft` sweeps it between two placements, for mitered corners.
- `heightfield` adds a smooth surface over a grid of heights.
"""

from std.math import cos, isfinite, pi, sin, sqrt
from core.buffer_attribute import BufferAttribute
from core.buffer_geometry import BufferGeometry, COLOR, NORMAL, POSITION, UV
from generators.utils import Vec3d
from geometries.earcut import earcut


struct MeshBuilder(Movable):
    """Triangles under construction, in a z-up frame."""

    var positions: List[Float32]
    var normals: List[Float32]
    var uvs: List[Float32]
    var colors: List[Float32]

    def __init__(out self):
        """Start with no triangles."""
        self.positions = List[Float32]()
        self.normals = List[Float32]()
        self.uvs = List[Float32]()
        self.colors = List[Float32]()

    def count(self) -> Int:
        """Return how many triangles there are.

        Returns:
            The triangle count.
        """
        return len(self.positions) // 9

    def _vertex(mut self, p: Vec3d, n: Vec3d, face: Vec3d, color: Vec3d):
        """Add one vertex, with texture coordinates from the face normal."""
        self.positions.append(Float32(p.x))
        self.positions.append(Float32(p.z))
        self.positions.append(Float32(-p.y))
        self.normals.append(Float32(n.x))
        self.normals.append(Float32(n.z))
        self.normals.append(Float32(-n.y))
        var ax = abs(face.x)
        var ay = abs(face.y)
        var az = abs(face.z)
        if az >= ax and az >= ay:
            self.uvs.append(Float32(p.x))
            self.uvs.append(Float32(p.y))
        elif ax >= ay:
            self.uvs.append(Float32(p.y))
            self.uvs.append(Float32(p.z))
        else:
            self.uvs.append(Float32(p.x))
            self.uvs.append(Float32(p.z))
        self.colors.append(Float32(color.x))
        self.colors.append(Float32(color.y))
        self.colors.append(Float32(color.z))

    def triangle(mut self, a: Vec3d, b: Vec3d, c: Vec3d, color: Vec3d):
        """Add a flat triangle, wound counterclockwise seen from its front.

        A triangle of no area is skipped.

        Args:
            a: The first corner.
            b: The second corner.
            c: The third corner.
            color: The linear color, each channel zero to one.
        """
        var cross = (b - a).cross(c - a)
        var length = sqrt(cross.dot(cross))
        if not (length > 1e-12):
            return
        var n = cross * (1.0 / length)
        self._vertex(a, n, n, color)
        self._vertex(b, n, n, color)
        self._vertex(c, n, n, color)

    def smooth_triangle(
        mut self,
        a: Vec3d,
        b: Vec3d,
        c: Vec3d,
        na: Vec3d,
        nb: Vec3d,
        nc: Vec3d,
        ca: Vec3d,
        cb: Vec3d,
        cc: Vec3d,
    ):
        """Add a triangle with a normal and a color at each corner.

        Args:
            a: The first corner.
            b: The second corner.
            c: The third corner.
            na: The normal at a.
            nb: The normal at b.
            nc: The normal at c.
            ca: The color at a.
            cb: The color at b.
            cc: The color at c.
        """
        var cross = (b - a).cross(c - a)
        var length = sqrt(cross.dot(cross))
        if not (length > 1e-12):
            return
        var face = cross * (1.0 / length)
        self._vertex(a, na, face, ca)
        self._vertex(b, nb, face, cb)
        self._vertex(c, nc, face, cc)

    def quad(mut self, a: Vec3d, b: Vec3d, c: Vec3d, d: Vec3d, color: Vec3d):
        """Add a flat quad as two triangles, a-b-c and a-c-d.

        Args:
            a: The first corner.
            b: The second corner.
            c: The third corner.
            d: The fourth corner.
            color: The linear color.
        """
        self.triangle(a, b, c, color)
        self.triangle(a, c, d, color)

    def prism(
        mut self,
        section: List[Tuple[Float64, Float64]],
        start: Vec3d,
        end: Vec3d,
        across: Vec3d,
        color: Vec3d,
        caps: Bool = True,
    ) raises:
        """Extrude a section polygon along a straight run.

        A section point (u, v) lies at start + u across + v up, where up is
        the z axis. The run goes from `start` to `end`.

        Args:
            section: The polygon, counterclockwise in (u, v), not crossing
                itself.
            start: Where the run starts.
            end: Where it ends.
            across: The unit direction of u.
            color: The linear color.
            caps: Whether to close the two ends.

        Raises:
            Error: If the section has fewer than three points or a value
                is not finite.
        """
        self.loft(section, start, across, section, end, across, color, caps)

    def loft(
        mut self,
        section: List[Tuple[Float64, Float64]],
        start: Vec3d,
        start_across: Vec3d,
        end_section: List[Tuple[Float64, Float64]],
        end: Vec3d,
        end_across: Vec3d,
        color: Vec3d,
        caps: Bool = True,
    ) raises:
        """Sweep a section polygon between two placements.

        At the start a section point (u, v) lies at start + u start_across
        + v up; at the end, the matching point of `end_section` lies at
        end + u end_across + v up. Unequal `across` vectors cut the ends on
        a skew, as a mitered corner needs: for a miter, `across` runs along
        the miter line and is longer than one by 1 / cos of half the turn.
        Unequal sections taper the sweep, as a sloping wall top needs.

        Args:
            section: The polygon at the start, counterclockwise in (u, v),
                not crossing itself.
            start: The section's origin at the start.
            start_across: The u direction and scale at the start.
            end_section: The polygon at the end, point for point.
            end: The section's origin at the end.
            end_across: The u direction and scale at the end.
            color: The linear color.
            caps: Whether to close the two ends.

        Raises:
            Error: If a section has fewer than three points, the two differ
                in length, or a value is not finite.
        """
        var n = len(section)
        if n < 3:
            raise Error("A prism section needs at least three points")
        if len(end_section) != n:
            raise Error("A loft's two sections need the same points")
        # A section has three points at least, so these loops always run.
        for i in range(n):  # pragma: no branch
            if not (
                isfinite(section[i][0])
                and isfinite(section[i][1])
                and isfinite(end_section[i][0])
                and isfinite(end_section[i][1])
            ):
                raise Error("A prism section must be finite")
        var up = Vec3d(0, 0, 1)
        var at_start = List[Vec3d]()
        var at_end = List[Vec3d]()
        for i in range(n):  # pragma: no branch
            at_start.append(
                start + start_across * section[i][0] + up * section[i][1]
            )
            at_end.append(
                end + end_across * end_section[i][0] + up * end_section[i][1]
            )
        # The sides face outward when the section is counterclockwise
        # and the run follows across x up.
        var forward = start_across.cross(up).dot(end - start) > 0
        for i in range(n):  # pragma: no branch
            var j = (i + 1) % n
            if forward:
                self.quad(at_start[i], at_start[j], at_end[j], at_end[i], color)
            else:
                self.quad(at_start[i], at_end[i], at_end[j], at_start[j], color)
        if caps:
            for i in range(1, n - 1):  # pragma: no branch
                if forward:
                    self.triangle(
                        at_start[0], at_start[i + 1], at_start[i], color
                    )
                    self.triangle(at_end[0], at_end[i], at_end[i + 1], color)
                else:
                    self.triangle(
                        at_start[0], at_start[i], at_start[i + 1], color
                    )
                    self.triangle(at_end[0], at_end[i + 1], at_end[i], color)

    def oriented(
        mut self, a: Vec3d, b: Vec3d, c: Vec3d, facing: Vec3d, color: Vec3d
    ):
        """Add a flat triangle turned so its front faces a direction.

        Args:
            a: The first corner.
            b: The second corner.
            c: The third corner.
            facing: The direction the front should face.
            color: The linear color.
        """
        if (b - a).cross(c - a).dot(facing) < 0:
            self.triangle(a, c, b, color)
        else:
            self.triangle(a, b, c, color)

    def plate(
        mut self,
        outline: List[Tuple[Float64, Float64]],
        holes: List[List[Tuple[Float64, Float64]]],
        origin: Vec3d,
        a_axis: Vec3d,
        b_axis: Vec3d,
        depth: Vec3d,
        color: Vec3d,
    ) raises:
        """Add a flat plate with holes through it.

        A plate point (a, b) lies at origin + a a_axis + b b_axis on the
        front face, which faces away from `depth`, and that plus `depth` on
        the back face. The holes' walls are closed, so a pipe can pass
        through a wall.

        Args:
            outline: The plate's outline, in either winding.
            holes: Each hole's outline, inside the plate.
            origin: The origin of the front face.
            a_axis: The direction and scale of a.
            b_axis: The direction and scale of b.
            depth: From the front face to the back face.
            color: The linear color.

        Raises:
            Error: If the outline has fewer than three points or earcut
                refuses the polygon.
        """
        if len(outline) < 3:
            raise Error("A plate needs at least three points")
        var rings = List[List[Tuple[Float64, Float64]]]()
        rings.append(_wound(outline, True))
        for h in holes:
            rings.append(_wound(h, False))
        var data = List[Float64]()
        var starts = List[Int]()
        var points = List[Tuple[Float64, Float64]]()
        # The outline is the first ring, so the loops over the rings always
        # run.
        for r in range(len(rings)):  # pragma: no branch
            if r > 0:
                starts.append(len(points))
            for p in rings[r]:
                data.append(p[0])
                data.append(p[1])
                points.append(p)
        var tris = earcut(data, starts)
        var front = depth * -1.0
        for t in range(len(tris) // 3):
            var pa = points[tris[3 * t]]
            var pb = points[tris[3 * t + 1]]
            var pc = points[tris[3 * t + 2]]
            var a = origin + a_axis * pa[0] + b_axis * pa[1]
            var b = origin + a_axis * pb[0] + b_axis * pb[1]
            var c = origin + a_axis * pc[0] + b_axis * pc[1]
            self.oriented(a, b, c, front, color)
            self.oriented(a + depth, b + depth, c + depth, depth, color)
        # earcut refuses a ring of no points, so each ring here has some.
        for r in rings:  # pragma: no branch
            var n = len(r)
            for i in range(n):  # pragma: no branch
                var p = r[i]
                var q = r[(i + 1) % n]
                # Outward from the material: right of the travel for a
                # counterclockwise outline and a clockwise hole.
                var facing = a_axis * (q[1] - p[1]) - b_axis * (q[0] - p[0])
                var a = origin + a_axis * p[0] + b_axis * p[1]
                var b = origin + a_axis * q[0] + b_axis * q[1]
                self.oriented(a, b, b + depth, facing, color)
                self.oriented(a, b + depth, a + depth, facing, color)

    def tube(
        mut self,
        start: Vec3d,
        end: Vec3d,
        outer: Float64,
        inner: Float64,
        segments: Int,
        color: Vec3d,
        inside_color: Vec3d,
    ) raises:
        """Add a round tube, such as a pipe barrel, with smooth sides.

        Args:
            start: The center of one end.
            end: The center of the other end.
            outer: The outside radius.
            inner: The bore radius; zero for a solid rod.
            segments: Facets around; three or more.
            color: The outside and end color.
            inside_color: The bore's color.

        Raises:
            Error: If the radii or the segments are not valid, or the ends
                are the same point.
        """
        if segments < 3:
            raise Error("A tube needs at least three segments")
        if not (outer > 0 and inner >= 0 and inner < outer):
            raise Error("A tube's radii must have 0 <= inner < outer")
        var axis = end - start
        var length = sqrt(axis.dot(axis))
        if not (length > 1e-12):
            raise Error("A tube's ends must differ")
        var along = axis * (1.0 / length)
        var back = along * -1.0
        var helper = Vec3d(0, 0, 1) if abs(along.z) < 0.9 else Vec3d(1, 0, 0)
        var e1 = along.cross(helper).normalized()
        var e2 = along.cross(e1).normalized()
        # There are three segments at least, so the loop always runs.
        for k in range(segments):  # pragma: no branch
            var t0 = 2 * pi * Float64(k) / Float64(segments)
            var t1 = 2 * pi * Float64(k + 1) / Float64(segments)
            var r0 = e1 * cos(t0) + e2 * sin(t0)
            var r1 = e1 * cos(t1) + e2 * sin(t1)
            var a = start + r0 * outer
            var b = start + r1 * outer
            self.smooth_triangle(
                a, b, b + axis, r0, r1, r1, color, color, color
            )
            self.smooth_triangle(
                a, b + axis, a + axis, r0, r1, r0, color, color, color
            )
            if inner > 0:
                var ia = start + r0 * inner
                var ib = start + r1 * inner
                var n0 = r0 * -1.0
                var n1 = r1 * -1.0
                self.smooth_triangle(
                    ia,
                    ib + axis,
                    ib,
                    n0,
                    n1,
                    n1,
                    inside_color,
                    inside_color,
                    inside_color,
                )
                self.smooth_triangle(
                    ia,
                    ia + axis,
                    ib + axis,
                    n0,
                    n0,
                    n1,
                    inside_color,
                    inside_color,
                    inside_color,
                )
                self.oriented(a, b, ib, back, color)
                self.oriented(a, ib, ia, back, color)
                self.oriented(a + axis, b + axis, ib + axis, along, color)
                self.oriented(a + axis, ib + axis, ia + axis, along, color)
            else:
                self.oriented(start, a, b, back, color)
                self.oriented(end, a + axis, b + axis, along, color)

    def heightfield(
        mut self,
        origin: Vec3d,
        step_x: Float64,
        step_y: Float64,
        columns: Int,
        rows: Int,
        heights: List[Float64],
        colors: List[Vec3d],
    ) raises:
        """Add a smooth surface over a grid of heights.

        Grid point (i, j) is at origin + (i step_x, j step_y, height). Its
        normal comes from central differences.

        Args:
            origin: The corner of the grid; its z is added to every height.
            step_x: The spacing along x.
            step_y: The spacing along y.
            columns: Points along x, two or more.
            rows: Points along y, two or more.
            heights: One height per point, row after row.
            colors: One color per point, or none for white.

        Raises:
            Error: If the grid is smaller than 2 by 2, the spacings are not
                positive, the point count does not fit, or the lists are
                the wrong length.
        """
        if columns < 2 or rows < 2:
            raise Error("A heightfield needs at least 2 by 2 points")
        if not (step_x > 0 and step_y > 0):
            raise Error("A heightfield's spacing must be positive")
        # A grid of 2^32 by 2^32 wraps the point count to zero, so an
        # empty height list looks complete and the loops do not finish.
        if columns > Int.MAX // rows:
            raise Error("A heightfield is larger than this port builds")
        if len(heights) != columns * rows:
            raise Error("A heightfield needs one height per point")
        if len(colors) != 0 and len(colors) != columns * rows:
            raise Error("A heightfield needs one color per point, or none")
        var points = List[Vec3d]()
        var normals = List[Vec3d]()
        # The grid is 2 by 2 points at least, so these loops always run.
        for j in range(rows):  # pragma: no branch
            for i in range(columns):  # pragma: no branch
                var k = j * columns + i
                points.append(
                    origin
                    + Vec3d(
                        Float64(i) * step_x, Float64(j) * step_y, heights[k]
                    )
                )
        for j in range(rows):  # pragma: no branch
            for i in range(columns):  # pragma: no branch
                var il = max(i - 1, 0)
                var ir = min(i + 1, columns - 1)
                var jd = max(j - 1, 0)
                var ju = min(j + 1, rows - 1)
                var dzdx = (
                    heights[j * columns + ir] - heights[j * columns + il]
                ) / (Float64(ir - il) * step_x)
                var dzdy = (
                    heights[ju * columns + i] - heights[jd * columns + i]
                ) / (Float64(ju - jd) * step_y)
                normals.append(Vec3d(-dzdx, -dzdy, 1).normalized())
        var white = Vec3d(1, 1, 1)
        for j in range(rows - 1):  # pragma: no branch
            for i in range(columns - 1):  # pragma: no branch
                var a = j * columns + i
                var b = a + 1
                var c = a + columns + 1
                var d = a + columns
                var ca = colors[a] if len(colors) > 0 else white
                var cb = colors[b] if len(colors) > 0 else white
                var cc = colors[c] if len(colors) > 0 else white
                var cd = colors[d] if len(colors) > 0 else white
                self.smooth_triangle(
                    points[a],
                    points[b],
                    points[c],
                    normals[a],
                    normals[b],
                    normals[c],
                    ca,
                    cb,
                    cc,
                )
                self.smooth_triangle(
                    points[a],
                    points[c],
                    points[d],
                    normals[a],
                    normals[c],
                    normals[d],
                    ca,
                    cc,
                    cd,
                )

    def geometry(self) raises -> BufferGeometry:
        """Return the triangles as a geometry.

        Returns:
            A geometry with position, normal, uv and color attributes.

        Raises:
            Error: If an attribute cannot be made.
        """
        var g = BufferGeometry()
        g.set_attribute(
            String(POSITION), BufferAttribute(self.positions.copy(), 3)
        )
        g.set_attribute(String(NORMAL), BufferAttribute(self.normals.copy(), 3))
        g.set_attribute(String(UV), BufferAttribute(self.uvs.copy(), 2))
        g.set_attribute(String(COLOR), BufferAttribute(self.colors.copy(), 3))
        return g^


def _wound(
    ring: List[Tuple[Float64, Float64]], counterclockwise: Bool
) -> List[Tuple[Float64, Float64]]:
    """Return a ring wound the given way."""
    var area = Float64(0)
    var n = len(ring)
    for i in range(n):
        var p = ring[i]
        var q = ring[(i + 1) % n]
        area += p[0] * q[1] - q[0] * p[1]
    if (area > 0) == counterclockwise:
        return ring.copy()
    # A ring wound the wrong way has an area, so it has three points at
    # least and the loop always runs.
    var out = List[Tuple[Float64, Float64]]()
    for i in range(n):  # pragma: no branch
        out.append(ring[n - 1 - i])
    return out^
