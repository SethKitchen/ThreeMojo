# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""The arithmetic of three.js `examples/jsm/loaders/VRMLLoader.js`: how
it cuts faces into triangles, spreads colors and normals over them,
finds normals with a crease angle, extrudes a cross section along a
spine, builds an elevation grid, and paints a background sphere.

Each function works in JavaScript numbers, `Float64`, as three.js does.
Where three.js reads past the end of an array or at an index that is
not a whole number, it reads `undefined`, which becomes `NaN`. These
functions give `NaN` there too, and `loaders.vrml` refuses a geometry
that holds one. Each product that feeds a sum is rounded on its own, as
JavaScript rounds it.
"""

from geometries.earcut import triangulate_shape
from std.math import acos, cos, floor, isnan, pi, sin, sqrt
from std.utils.numerics import nan


comptime _UNDEFINED = nan[DType.float64]()


@no_inline
def product(a: Float64, b: Float64) -> Float64:
    """Return `a * b`, rounded before any sum uses it, as JavaScript rounds
    it.

    Args:
        a: A number.
        b: A number.

    Returns:
        The product.
    """
    return a * b


def item(data: List[Float64], index: Float64) -> Float64:
    """Return `data[ index ]` as JavaScript reads it: `NaN` for an index
    that is not a whole number in range.

    Args:
        data: The array.
        index: The index.

    Returns:
        The value, or `NaN`.
    """
    var whole = index == floor(index) and index >= 0
    if not whole:
        return _UNDEFINED
    if index >= Float64(len(data)):
        return _UNDEFINED
    return data[Int(index)]


def at(data: List[Float64], index: Int) -> Float64:
    """Return `data[ index ]`, or `NaN` past the end.

    Args:
        data: The array.
        index: The index, zero or more.

    Returns:
        The value, or `NaN`.
    """
    if index >= len(data):
        return _UNDEFINED
    return data[index]


def srgb_to_linear(c: Float64) -> Float64:
    """Return three.js's `SRGBToLinear`.

    Args:
        c: An sRGB channel.

    Returns:
        The linear channel.
    """
    # Mojo's power of a `NaN` is infinity, where JavaScript's is `NaN`.
    var small = c < 0.04045 or isnan(c)
    if small:
        return c * 0.0773993808
    return (product(c, 0.9478672986) + 0.0521327014) ** 2.4


def colors_to_linear(mut colors: List[Float64]):
    """Convert a color attribute from sRGB to linear, three.js's
    `convertColorsToLinearSRGB`: each value is read as the `Float32` the
    attribute holds.

    Args:
        colors: Three channels a vertex.
    """
    for i in range(len(colors)):
        colors[i] = srgb_to_linear(Float64(Float32(colors[i])))


def triangulate_face_index(index: List[Float64], ccw: Bool) -> List[Float64]:
    """Cut faces into fans, three.js's `triangulateFaceIndex`.

    Args:
        index: Faces of point indices, each ended by -1 or the end.
        ccw: False to turn each triangle over.

    Returns:
        Three indices a triangle.
    """
    var out = List[Float64]()
    var start = 0
    var i = 0
    var second = 1 if ccw else 2
    var third = 2 if ccw else 1
    while i < len(index):
        out.append(at(index, start))
        out.append(at(index, i + second))
        out.append(at(index, i + third))
        var ends = at(index, i + 3) == -1 or i + 3 >= len(index)
        if ends:
            i += 3
            start = i + 1
        i += 1
    return out^


def triangulate_face_data(
    data: List[Float64], index: List[Float64]
) -> List[Float64]:
    """Give each triangle its face's three values, three.js's
    `triangulateFaceData`.

    Args:
        data: Three values a face.
        index: The faces, as `triangulate_face_index` reads them.

    Returns:
        Three values a triangle.
    """
    var out = List[Float64]()
    var start = 0
    var i = 0
    while i < len(index):
        var stride = start * 3
        out.append(at(data, stride))
        out.append(at(data, stride + 1))
        out.append(at(data, stride + 2))
        var ends = at(index, i + 3) == -1 or i + 3 >= len(index)
        if ends:
            i += 3
            start += 1
        i += 1
    return out^


def flatten_data(data: List[Float64], index: List[Float64]) -> List[Float64]:
    """Pick three values for each index, three.js's `flattenData`.

    Args:
        data: Three values an entry.
        index: The entries to pick.

    Returns:
        Three values an index.
    """
    var out = List[Float64]()
    # The caller gives a list that is not empty. The loop always runs.
    for i in range(len(index)):  # pragma: no branch
        var stride = product(index[i], 3)
        out.append(item(data, stride))
        out.append(item(data, stride + 1))
        out.append(item(data, stride + 2))
    return out^


def expand_line_index(index: List[Float64]) -> List[Float64]:
    """Cut polylines into segments, three.js's `expandLineIndex`.

    Args:
        index: Polylines of point indices, each ended by -1 or the end.

    Returns:
        Two indices a segment.
    """
    var out = List[Float64]()
    var i = 0
    while i < len(index):
        out.append(index[i])
        out.append(at(index, i + 1))
        var ends = at(index, i + 2) == -1 or i + 2 >= len(index)
        if ends:
            i += 2
        i += 1
    return out^


def expand_line_data(
    data: List[Float64], index: List[Float64]
) -> List[Float64]:
    """Give each segment its polyline's three values, three.js's
    `expandLineData`.

    Args:
        data: Three values a polyline.
        index: The polylines, as `expand_line_index` reads them.

    Returns:
        Three values a segment.
    """
    var out = List[Float64]()
    var start = 0
    var i = 0
    while i < len(index):
        var stride = start * 3
        out.append(at(data, stride))
        out.append(at(data, stride + 1))
        out.append(at(data, stride + 2))
        var ends = at(index, i + 2) == -1 or i + 2 >= len(index)
        if ends:
            i += 2
            start += 1
        i += 1
    return out^


def from_indexed_data(
    coord_index: List[Float64],
    index: List[Float64],
    data: List[Float64],
    item_size: Int,
) -> List[Float64]:
    """Pick a vertex's values by a second index, three.js's
    `computeAttributeFromIndexedData`.

    Args:
        coord_index: The triangles or segments of points: only its length
            is read.
        index: The same shapes, of entries of `data`.
        data: `item_size` values an entry.
        item_size: Two or three.

    Returns:
        `item_size` values a vertex.
    """
    var out = List[Float64]()
    var i = 0
    while i < len(coord_index):
        # Three corners. The loop always runs.
        for k in range(3):  # pragma: no branch
            var base = product(at(index, i + k), Float64(item_size))
            # Two or three values. The loop always runs.
            for c in range(item_size):  # pragma: no branch
                out.append(item(data, base + Float64(c)))
        i += 3
    return out^


def from_face_data(
    index: List[Float64], face_data: List[Float64]
) -> List[Float64]:
    """Give each vertex its triangle's values, three.js's
    `computeAttributeFromFaceData`.

    Args:
        index: The triangles: only its length is read.
        face_data: Three values a triangle.

    Returns:
        Three values a vertex.
    """
    var out = List[Float64]()
    var i = 0
    var j = 0
    while i < len(index):
        # Three corners. The loop always runs.
        for _ in range(3):  # pragma: no branch
            # Three values. The loop always runs.
            for c in range(3):  # pragma: no branch
                out.append(at(face_data, j * 3 + c))
        i += 3
        j += 1
    return out^


def from_line_data(
    index: List[Float64], line_data: List[Float64]
) -> List[Float64]:
    """Give each vertex its segment's values, three.js's
    `computeAttributeFromLineData`.

    Args:
        index: The segments: only its length is read.
        line_data: Three values a segment.

    Returns:
        Three values a vertex.
    """
    var out = List[Float64]()
    var i = 0
    var j = 0
    while i < len(index):
        # Two ends. The loop always runs.
        for _ in range(2):  # pragma: no branch
            # Three values. The loop always runs.
            for c in range(3):  # pragma: no branch
                out.append(at(line_data, j * 3 + c))
        i += 2
        j += 1
    return out^


def to_non_indexed(
    indices: List[Float64], data: List[Float64], item_size: Int
) -> List[Float64]:
    """Copy each indexed vertex's values, three.js's
    `toNonIndexedAttribute` over a `Float32BufferAttribute`.

    Args:
        indices: The vertices to copy.
        data: `item_size` values an entry.
        item_size: The values an entry holds.

    Returns:
        `item_size` values an index, each rounded to a `Float32` as the
        attribute rounds it.
    """
    var out = List[Float64]()
    for i in range(len(indices)):
        var base = product(indices[i], Float64(item_size))
        # Two or three values. The loop always runs.
        for c in range(item_size):  # pragma: no branch
            out.append(Float64(Float32(item(data, base + Float64(c)))))
    return out^


struct _Vector(ImplicitlyCopyable):
    """A three.js `Vector3` in doubles."""

    var x: Float64
    var y: Float64
    var z: Float64

    def __init__(out self, x: Float64, y: Float64, z: Float64):
        """Hold three numbers."""
        self.x = x
        self.y = y
        self.z = z

    def length_sq(self) -> Float64:
        """Return three.js's `lengthSq`."""
        return (
            product(self.x, self.x)
            + product(self.y, self.y)
            + product(self.z, self.z)
        )

    def normalized(self) -> Self:
        """Return three.js's `normalize`, which multiplies by one over the
        length: a zero vector stays zero."""
        var length = sqrt(self.length_sq())
        var inverse = 1 / (length if length != 0 else Float64(1))
        return Self(self.x * inverse, self.y * inverse, self.z * inverse)

    def dot(self, other: Self) -> Float64:
        """Return three.js's `dot`."""
        return (
            product(self.x, other.x)
            + product(self.y, other.y)
            + product(self.z, other.z)
        )

    def angle_to(self, other: Self) -> Float64:
        """Return three.js's `angleTo`."""
        var denominator = sqrt(product(self.length_sq(), other.length_sq()))
        if denominator == 0:
            return pi / 2
        var theta = self.dot(other) / denominator
        return acos(min(max(theta, -1.0), 1.0))


def _point(coord: List[Float64], index: Int) -> _Vector:
    """Return point `index` of a list of three numbers a point."""
    return _Vector(coord[index * 3], coord[index * 3 + 1], coord[index * 3 + 2])


def normal_attribute(
    index: List[Float64], coord: List[Float64], crease_angle: Float64
) raises -> List[Float64]:
    """Find a normal for each vertex of each triangle, three.js's
    `computeNormalAttribute`.

    With a crease angle of zero each vertex takes its face's normal.
    Otherwise it takes the sum of the normals of each face at its point
    that is less than the crease angle from its own face's, normalized.

    Args:
        index: Three point indices a triangle.
        coord: Three numbers a point.
        crease_angle: The crease angle, in radians.

    Returns:
        Three values a vertex, each rounded to a `Float32`.

    Raises:
        Error: If an index names no point. three.js reads `NaN` for it.
    """
    var count = len(coord) // 3
    var faces = List[Int]()
    for i in range(len(index)):
        var value = index[i]
        var whole = value == floor(value) and value >= 0
        var inside = whole and value < Float64(count)
        if not inside:
            raise Error("VRML: an index names no point")
        faces.append(Int(value))
    var face_normals = List[_Vector]()
    # The faces at each point, in order.
    var at_point = List[List[Int]](length=count, fill=List[Int]())
    var f = 0
    while f * 3 < len(faces):
        var a = _point(coord, faces[f * 3])
        var b = _point(coord, faces[f * 3 + 1])
        var c = _point(coord, faces[f * 3 + 2])
        var cb = _Vector(c.x - b.x, c.y - b.y, c.z - b.z)
        var ab = _Vector(a.x - b.x, a.y - b.y, a.z - b.z)
        var cross = _Vector(
            product(cb.y, ab.z) - product(cb.z, ab.y),
            product(cb.z, ab.x) - product(cb.x, ab.z),
            product(cb.x, ab.y) - product(cb.y, ab.x),
        )
        face_normals.append(cross.normalized())
        # Three corners. The loop always runs.
        for k in range(3):  # pragma: no branch
            at_point[faces[f * 3 + k]].append(f)
        f += 1
    var out = List[Float64]()
    for face in range(len(face_normals)):
        # Three corners. The loop always runs.
        for k in range(3):  # pragma: no branch
            var n = _weighted(
                face_normals, at_point[faces[face * 3 + k]], face, crease_angle
            )
            out.append(Float64(Float32(n.x)))
            out.append(Float64(Float32(n.y)))
            out.append(Float64(Float32(n.z)))
    return out^


def _weighted(
    face_normals: List[_Vector],
    faces: List[Int],
    face: Int,
    crease_angle: Float64,
) -> _Vector:
    """Return three.js's `weightedNormal` of a vertex."""
    var own = face_normals[face]
    if crease_angle == 0:
        return own.normalized()
    var sum = _Vector(0, 0, 0)
    # A point is on its own face at least. The loop always runs.
    for other in faces:  # pragma: no branch
        var n = face_normals[other]
        if n.angle_to(own) < crease_angle:
            sum = _Vector(sum.x + n.x, sum.y + n.y, sum.z + n.z)
    return sum.normalized()


def elevation_grid(
    height: List[Float64],
    x_dimension: Int,
    z_dimension: Int,
    x_spacing: Float64,
    z_spacing: Float64,
    ccw: Bool,
) -> Tuple[List[Float64], List[Float64]]:
    """Return the points and the triangles of an elevation grid, as
    three.js's `buildElevationGridNode` makes them.

    three.js walks `zDimension` rows of `xDimension` points, and puts
    point `( i, j )` at `x = xSpacing * i`, `z = zSpacing * j`: the row
    along x and the column along z. This does the same.

    Args:
        height: One height a point.
        x_dimension: The points along x.
        z_dimension: The points along z.
        x_spacing: The spacing along x.
        z_spacing: The spacing along z.
        ccw: False to turn each triangle over.

    Returns:
        Three numbers a point, and three point indices a triangle.
    """
    var vertices = List[Float64]()
    for i in range(z_dimension):
        for j in range(x_dimension):
            vertices.append(product(x_spacing, Float64(i)))
            vertices.append(at(height, i * x_dimension + j))
            vertices.append(product(z_spacing, Float64(j)))
    var indices = List[Float64]()
    for i in range(x_dimension - 1):
        for j in range(z_dimension - 1):
            var a = Float64(i + j * x_dimension)
            var b = Float64(i + (j + 1) * x_dimension)
            var c = Float64((i + 1) + (j + 1) * x_dimension)
            var d = Float64((i + 1) + j * x_dimension)
            var order: List[Float64]
            if ccw:
                order = [a, c, b, c, a, d]
            else:
                order = [a, b, c, c, d, a]
            indices.extend(order^)
    return (vertices^, indices^)


def grid_values(
    data: List[Float64], x_dimension: Int, z_dimension: Int, per_vertex: Bool
) -> List[Float64]:
    """Return an elevation grid's colors or normals, three values each.

    Per vertex, it is one value a point, in the order the points are
    made. Per quad, it is six copies of a quad's value, in the order of
    the triangles, as three.js pushes them.

    Args:
        data: Three values a point or a quad.
        x_dimension: The points along x.
        z_dimension: The points along z.
        per_vertex: True for a value a point.

    Returns:
        The values, three each.
    """
    var out = List[Float64]()
    if per_vertex:
        for index in range(z_dimension * x_dimension):
            # Three values. The loop always runs.
            for c in range(3):  # pragma: no branch
                out.append(at(data, index * 3 + c))
        return out^
    for i in range(x_dimension - 1):
        for j in range(z_dimension - 1):
            var index = i + j * (x_dimension - 1)
            # Six corners. The loop always runs.
            for _ in range(6):  # pragma: no branch
                # Three values. The loop always runs.
                for c in range(3):  # pragma: no branch
                    out.append(at(data, index * 3 + c))
    return out^


def grid_uvs(
    tex_coord: List[Float64],
    has_tex_coord: Bool,
    x_dimension: Int,
    z_dimension: Int,
) -> List[Float64]:
    """Return an elevation grid's texture coordinates, one pair a point.

    Without a `TextureCoordinate` node three.js makes
    `( i / ( xDimension - 1 ), j / ( zDimension - 1 ) )`, with `i` the
    row and `j` the column, and so does this.

    Args:
        tex_coord: Two values a point.
        has_tex_coord: False to make them.
        x_dimension: The points along x.
        z_dimension: The points along z.

    Returns:
        Two values a point.
    """
    var out = List[Float64]()
    for i in range(z_dimension):
        for j in range(x_dimension):
            var index = i * x_dimension + j
            if has_tex_coord:
                out.append(at(tex_coord, index * 2))
                out.append(at(tex_coord, index * 2 + 1))
            else:
                out.append(Float64(i) / Float64(x_dimension - 1))
                out.append(Float64(j) / Float64(z_dimension - 1))
    return out^


def extrusion_points(
    cross_section: List[Float64],
    spine: List[Float64],
    scale: List[Float64],
    has_scale: Bool,
    orientation: List[Float64],
    has_orientation: Bool,
) -> List[Float64]:
    """Place the cross section at each spine point, three.js's
    `buildExtrusionNode`: scaled in x and z, turned about the orientation
    axis, which three.js does not normalize, then moved.

    Args:
        cross_section: Two numbers a point.
        spine: Three numbers a point.
        scale: Two numbers a spine point.
        has_scale: False for a scale of one.
        orientation: An axis and an angle a spine point.
        has_orientation: False for no turn.

    Returns:
        Three numbers a point.
    """
    var vertices = List[Float64]()
    var s = 0
    while s * 3 < len(spine):
        var sx = at(scale, s * 2) if has_scale else Float64(1)
        var sz = at(scale, s * 2 + 1) if has_scale else Float64(1)
        var ax = at(orientation, s * 4) if has_orientation else Float64(0)
        var ay = at(orientation, s * 4 + 1) if has_orientation else Float64(0)
        var az = at(orientation, s * 4 + 2) if has_orientation else Float64(1)
        var angle = at(orientation, s * 4 + 3) if has_orientation else Float64(
            0
        )
        var half = angle / 2
        var sine = sin(half)
        var qx = product(ax, sine)
        var qy = product(ay, sine)
        var qz = product(az, sine)
        var qw = cos(half)
        var k = 0
        while k < len(cross_section):
            var vx = product(cross_section[k], sx)
            var vy = product(Float64(0), Float64(1))
            var vz = product(cross_section[k + 1], sz)
            var tx = 2 * (product(qy, vz) - product(qz, vy))
            var ty = 2 * (product(qz, vx) - product(qx, vz))
            var tz = 2 * (product(qx, vy) - product(qy, vx))
            var rx = vx + product(qw, tx) + product(qy, tz) - product(qz, ty)
            var ry = vy + product(qw, ty) + product(qz, tx) - product(qx, tz)
            var rz = vz + product(qw, tz) + product(qx, ty) - product(qy, tx)
            vertices.append(rx + spine[s * 3])
            vertices.append(ry + spine[s * 3 + 1])
            vertices.append(rz + spine[s * 3 + 2])
            k += 2
        s += 1
    return vertices^


def extrusion_indices(
    cross_section: List[Float64],
    spine_count: Int,
    begin_cap: Bool,
    end_cap: Bool,
    ccw: Bool,
) raises -> List[Float64]:
    """Return the triangles of an extrusion, three.js's
    `buildExtrusionNode`: two a quad of the side, then the caps, cut by
    `ShapeUtils.triangulateShape`.

    Args:
        cross_section: Two numbers a point.
        spine_count: The spine points.
        begin_cap: True to close the first cross section.
        end_cap: True to close the last.
        ccw: False to turn each triangle over.

    Returns:
        Three point indices a triangle.

    Raises:
        Error: If `triangulate_shape` refuses the cross section.
    """
    var count = len(cross_section) // 2
    var n = len(cross_section)
    var closed = n >= 2 and (
        cross_section[0] == cross_section[n - 2]
        and cross_section[1] == cross_section[n - 1]
    )

    var indices = List[Float64]()
    for i in range(spine_count - 1):
        for j in range(count - 1):
            var a = j + i * count
            var b = (j + 1) + i * count
            var c = j + (i + 1) * count
            var d = (j + 1) + (i + 1) * count
            var wraps = j == count - 2 and closed
            if wraps:
                b = i * count
                d = (i + 1) * count
            var order: List[Int]
            if ccw:
                order = [a, b, c, c, b, d]
            else:
                order = [a, c, b, c, d, b]
            # Six corners. The loop always runs.
            for v in order:  # pragma: no branch
                indices.append(Float64(v))
    var capped = begin_cap or end_cap
    if not capped:
        return indices^
    var cap = triangulate_shape(cross_section)
    if begin_cap:
        var t = 0
        while t < len(cap):
            var second = cap[t + 1] if ccw else cap[t + 2]
            var third = cap[t + 2] if ccw else cap[t + 1]
            indices.append(Float64(cap[t]))
            indices.append(Float64(second))
            indices.append(Float64(third))
            t += 3
    if end_cap:
        var offset = count * (spine_count - 1)
        var t = 0
        while t < len(cap):
            var second = cap[t + 2] if ccw else cap[t + 1]
            var third = cap[t + 1] if ccw else cap[t + 2]
            indices.append(Float64(offset + cap[t]))
            indices.append(Float64(offset + second))
            indices.append(Float64(offset + third))
            t += 3
    return indices^


struct SurfaceData(Movable):
    """What three.js makes of a sphere or a box: points, normals, texture
    coordinates and an index."""

    var positions: List[Float64]
    var normals: List[Float64]
    var uvs: List[Float64]
    var index: List[Int]

    def __init__(out self):
        """Start empty."""
        self.positions = List[Float64]()
        self.normals = List[Float64]()
        self.uvs = List[Float64]()
        self.index = List[Int]()


def sphere_data(
    radius: Float64,
    width_segments: Int,
    height_segments: Int,
    phi_start: Float64 = 0,
    phi_length: Float64 = 2 * pi,
    theta_start: Float64 = 0,
    theta_length: Float64 = pi,
) -> SurfaceData:
    """Return three.js's `SphereGeometry`, each value rounded to a
    `Float32`.

    Args:
        radius: The radius.
        width_segments: Divisions around; at least three.
        height_segments: Divisions from top to bottom; at least two.
        phi_start: Where the sweep around starts.
        phi_length: How far it goes.
        theta_start: Where the sweep down starts.
        theta_length: How far it goes. three.js lets it go past the
            bottom, and so does this.

    Returns:
        The points, normals, texture coordinates and index.
    """
    var out = SurfaceData()
    var theta_end = min(theta_start + theta_length, pi)
    # At least two rows. The loop always runs.
    for iy in range(height_segments + 1):  # pragma: no branch
        var v = Float64(iy) / Float64(height_segments)
        var u_offset = Float64(0)
        var top = iy == 0 and theta_start == 0
        var bottom = iy == height_segments and theta_end == pi
        if top:
            u_offset = 0.5 / Float64(width_segments)
        elif bottom:
            u_offset = -0.5 / Float64(width_segments)
        # At least three columns. The loop always runs.
        for ix in range(width_segments + 1):  # pragma: no branch
            var u = Float64(ix) / Float64(width_segments)
            var phi = phi_start + product(u, phi_length)
            var theta = theta_start + product(v, theta_length)
            var vertex = _Vector(
                product(product(-radius, cos(phi)), sin(theta)),
                product(radius, cos(theta)),
                product(product(radius, sin(phi)), sin(theta)),
            )
            var normal = vertex.normalized()
            out.positions.extend(
                [
                    Float64(Float32(vertex.x)),
                    Float64(Float32(vertex.y)),
                    Float64(Float32(vertex.z)),
                ]
            )
            out.normals.extend(
                [
                    Float64(Float32(normal.x)),
                    Float64(Float32(normal.y)),
                    Float64(Float32(normal.z)),
                ]
            )
            out.uvs.append(Float64(Float32(u + u_offset)))
            out.uvs.append(Float64(Float32(1 - v)))
    var row = width_segments + 1
    # At least two rows. The loop always runs.
    for iy in range(height_segments):  # pragma: no branch
        # At least three columns. The loop always runs.
        for ix in range(width_segments):  # pragma: no branch
            var a = iy * row + ix + 1
            var b = iy * row + ix
            var c = (iy + 1) * row + ix
            var d = (iy + 1) * row + ix + 1
            var first = iy != 0 or theta_start > 0
            if first:
                out.index.extend([a, b, d])
            var second = iy != height_segments - 1 or theta_end < pi
            if second:
                out.index.extend([b, c, d])
    return out^


def paint_faces(
    sphere: SurfaceData,
    radius: Float64,
    angles: List[Float64],
    colors: List[Float64],
    top_down: Bool,
) -> List[Float64]:
    """Color a sphere's points from the angles and colors of a sky or a
    ground, three.js's `paintFaces`.

    A color is given at each angle from the top, or from the bottom for a
    ground, and a point takes the sRGB blend of the two around its
    height, made linear. A point outside every band takes the last color.

    Args:
        sphere: The sphere.
        radius: Its radius.
        angles: One fewer angle than there are colors, in radians.
        colors: Three sRGB values a color. The caller gives two colors or
            more.
        top_down: True for a sky, False for a ground.

    Returns:
        Three linear values a point, each rounded to a `Float32`. A point
        that no triangle names stays zero, as three.js leaves it.
    """
    var color_count = (len(colors) + 2) // 3
    var heights = List[Float64]()
    # The caller gives two colors or more. The loop always runs.
    for i in range(color_count):  # pragma: no branch
        var angle = Float64(0) if i == 0 else at(angles, i - 1)
        if not top_down:
            angle = pi - angle
        heights.append(product(cos(angle), radius))
    var out = List[Float64](length=len(sphere.positions), fill=0)
    # A sphere has triangles. The loop always runs.
    for index in sphere.index:  # pragma: no branch
        var y = sphere.positions[index * 3 + 1]
        var a = color_count - 2
        var t = Float64(1)
        # Two colors or more make one band at least. The loop always runs.
        for j in range(1, color_count):  # pragma: no branch
            var ya = heights[j - 1]
            var yb = heights[j]
            var inside = (y <= ya and y > yb) if top_down else (
                y >= ya and y < yb
            )
            if inside:
                a = j - 1
                t = abs(ya - y) / abs(ya - yb)
                break
        # Three channels. The loop always runs.
        for c in range(3):  # pragma: no branch
            var from_color = at(colors, a * 3 + c)
            var to_color = at(colors, (a + 1) * 3 + c)
            var blend = from_color + product(to_color - from_color, t)
            out[index * 3 + c] = Float64(Float32(srgb_to_linear(blend)))
    return out^


def has_nan(values: List[Float64]) -> Bool:
    """Return True if a list holds a `NaN`.

    Args:
        values: The list.

    Returns:
        True for a `NaN`.
    """
    for v in values:
        if isnan(v):
            return True
    return False


def box_data(width: Float64, height: Float64, depth: Float64) -> SurfaceData:
    """Return three.js's `BoxGeometry` of one segment a side, each value
    rounded to a `Float32`. Its faces are +x, -x, +y, -y, +z and -z.

    Args:
        width: The size along x.
        height: The size along y.
        depth: The size along z.

    Returns:
        The points, normals, texture coordinates and index.
    """
    var out = SurfaceData()
    # three.js's `buildPlane` arguments: the axes u, v and w, the
    # directions of u and v, and the sizes along u, v and w.
    var axes: List[Int] = [2, 1, 0, 2, 1, 0, 0, 2, 1, 0, 2, 1, 0, 1, 2, 0, 1, 2]
    var directions: List[Float64] = [-1, -1, 1, -1, 1, 1, 1, -1, 1, -1, -1, -1]
    var sizes: List[Float64] = [
        depth,
        height,
        width,
        depth,
        height,
        -width,
        width,
        depth,
        height,
        width,
        depth,
        -height,
        width,
        height,
        depth,
        width,
        height,
        -depth,
    ]
    # Six faces. The loop always runs.
    for face in range(6):  # pragma: no branch
        var u = axes[face * 3]
        var v = axes[face * 3 + 1]
        var w = axes[face * 3 + 2]
        var plane_width = sizes[face * 3]
        var plane_height = sizes[face * 3 + 1]
        var plane_depth = sizes[face * 3 + 2]
        var start = len(out.positions) // 3
        # Two rows. The loop always runs.
        for iy in range(2):  # pragma: no branch
            var y = product(Float64(iy), plane_height) - plane_height / 2
            # Two columns. The loop always runs.
            for ix in range(2):  # pragma: no branch
                var x = product(Float64(ix), plane_width) - plane_width / 2
                var vertex: List[Float64] = [0, 0, 0]
                vertex[u] = x * directions[face * 2]
                vertex[v] = y * directions[face * 2 + 1]
                vertex[w] = plane_depth / 2
                var normal: List[Float64] = [0, 0, 0]
                normal[w] = 1 if plane_depth > 0 else -1
                # Three axes. The loop always runs.
                for c in range(3):  # pragma: no branch
                    out.positions.append(Float64(Float32(vertex[c])))
                    out.normals.append(normal[c])
                out.uvs.append(Float64(ix))
                out.uvs.append(Float64(1 - iy))
        out.index.extend(
            [start, start + 2, start + 1, start + 2, start + 3, start + 1]
        )
    return out^


def cylinder_data(
    radius_top: Float64,
    radius_bottom: Float64,
    height: Float64,
    radial_segments: Int,
    open_ended: Bool,
) -> SurfaceData:
    """Return three.js's `CylinderGeometry` of one row, each value rounded
    to a `Float32`. A cone is a cylinder whose top radius is zero.

    Args:
        radius_top: The radius at the top.
        radius_bottom: The radius at the bottom.
        height: The height.
        radial_segments: Divisions around.
        open_ended: True for no caps.

    Returns:
        The points, normals, texture coordinates and index.
    """
    var out = SurfaceData()
    var half = height / 2
    var slope = (radius_bottom - radius_top) / height
    var row = radial_segments + 1
    # Two rows. The loop always runs.
    for y in range(2):  # pragma: no branch
        var v = Float64(y)
        var radius = product(v, radius_bottom - radius_top) + radius_top
        # Sixteen segments. The loop always runs.
        for x in range(row):  # pragma: no branch
            var u = Float64(x) / Float64(radial_segments)
            var theta = product(u, 2 * pi)
            var sine = sin(theta)
            var cosine = cos(theta)
            out.positions.append(Float64(Float32(radius * sine)))
            out.positions.append(Float64(Float32(product(-v, height) + half)))
            out.positions.append(Float64(Float32(radius * cosine)))
            var normal = _Vector(sine, slope, cosine).normalized()
            out.normals.append(Float64(Float32(normal.x)))
            out.normals.append(Float64(Float32(normal.y)))
            out.normals.append(Float64(Float32(normal.z)))
            out.uvs.append(Float64(Float32(u)))
            out.uvs.append(1 - v)
    # Sixteen segments. The loop always runs.
    for x in range(radial_segments):  # pragma: no branch
        var a = x
        var b = row + x
        var c = row + x + 1
        var d = x + 1
        if radius_top > 0:
            out.index.extend([a, b, d])
        if radius_bottom > 0:
            out.index.extend([b, c, d])
    if open_ended:
        return out^
    if radius_top > 0:
        _cap(out, radius_top, half, radial_segments, True)
    if radius_bottom > 0:
        _cap(out, radius_bottom, half, radial_segments, False)
    return out^


def _cap(
    mut out: SurfaceData,
    radius: Float64,
    half: Float64,
    radial_segments: Int,
    top: Bool,
):
    """Add a cylinder's cap, three.js's `generateCap`."""
    var sign = Float64(1) if top else Float64(-1)
    var center = len(out.positions) // 3
    # Sixteen segments. The loop always runs.
    for _ in range(radial_segments):  # pragma: no branch
        out.positions.extend([Float64(0), Float64(Float32(half * sign)), 0])
        out.normals.extend([Float64(0), sign, 0])
        out.uvs.extend([0.5, 0.5])
    var ring = center + radial_segments
    # Sixteen segments. The loop always runs.
    for x in range(radial_segments + 1):  # pragma: no branch
        var u = Float64(x) / Float64(radial_segments)
        var theta = product(u, 2 * pi)
        var cosine = cos(theta)
        var sine = sin(theta)
        out.positions.append(Float64(Float32(radius * sine)))
        out.positions.append(Float64(Float32(half * sign)))
        out.positions.append(Float64(Float32(radius * cosine)))
        out.normals.extend([Float64(0), sign, 0])
        out.uvs.append(Float64(Float32(product(cosine, 0.5) + 0.5)))
        out.uvs.append(
            Float64(Float32(product(product(sine, 0.5), sign) + 0.5))
        )
    # Sixteen segments. The loop always runs.
    for x in range(radial_segments):  # pragma: no branch
        var c = center + x
        var i = ring + x
        if top:
            out.index.extend([i, i + 1, c])
        else:
            out.index.extend([i + 1, i, c])
