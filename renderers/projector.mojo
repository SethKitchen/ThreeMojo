# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""A scene flattened into a sorted list of faces, lines and sprites, from
three.js `examples/jsm/renderers/Projector.js`.

`project_scene` is three.js's `Projector.projectScene`. It walks the scene
graph, keeps each visible light, and keeps each visible object whose
material is visible and that the frustum does not cull. It projects each
kept object's vertices to normalized device coordinates and gives:

- **Faces.** Each triangle of a mesh that is on screen and faces the
  camera, or any triangle of a double-sided material. A face keeps its
  three vertices, its normal in the model's space turned into the world's,
  its vertex normals and texture coordinates, and its first vertex's color.
- **Lines.** Each segment of a line, clipped to the near and far planes.
- **Sprites.** Each point of a `Points` object and each sprite whose
  center lies between the near and far planes, with its size on screen.

Each element's `z` is its depth: a face's mean, a line's farthest. With
sorting, the objects and then the elements are sorted by render order,
then far to near, then by id, as three.js's `painterSort` sorts them.

**The math.** three.js works in doubles; so does this, from the scene's
world matrices and the camera's matrices.

**Where three.js's quirks are kept.** A back-side material is culled as a
front-side one, as `checkBackfaceCulling` knows only double-sided. A line
loop draws no closing segment. A line's second clip point is moved toward
the first after the first has moved. A face's color is its first vertex's
color only, and only with vertex colors. A vertex normal, a texture
coordinate or a color past its attribute reads NaN. An indexed line pairs
its indices whatever its mode. A color attribute is read three numbers at
a time, whatever its item size.

**Where this port differs.** An object's id is its node's index, and the
objects of one node are taken meshes, lines, points and sprites in turn,
where three.js has one object a node. Instanced, batched and skinned meshes
and levels of detail are not projected. A face or a line that names a
vertex past its geometry is refused: three.js reads a vertex left over from
an earlier object, or throws.
"""

from core.assets import Assets
from core.buffer_geometry import BufferGeometry, COLOR, NORMAL, POSITION, UV
from core.geometry_store import GeometryId
from core.object3d import NO_PARENT, NodeId
from core.scene import Scene
from materials.material import DOUBLE_SIDE, Material, MaterialId
from math.matrix4 import Matrix4
from math.vector3 import Vector3
from objects.line import SEGMENTS
from std.math import nan, sqrt

comptime Vec = SIMD[DType.float64, 4]


struct RenderableKind(Equatable, ImplicitlyCopyable, Writable):
    """What a projected element is: a face, a line or a sprite, as a type
    rather than a bare int.

    three.js tells them apart by class. The type does not stop
    `RenderableKind(9)`, so `is_valid` names the three the projector
    makes.
    """

    var value: Int

    def __init__(out self, value: Int):
        """Wrap a kind number.

        Args:
            value: The kind.
        """
        self.value = value

    def __eq__(self, other: Self) -> Bool:
        """Return True for the same kind.

        Args:
            other: The other kind.

        Returns:
            Whether they are equal.
        """
        return self.value == other.value

    def is_valid(self) -> Bool:
        """Return True if this is one of the three kinds.

        Returns:
            Whether it is.
        """
        return self.value >= 0 and self.value <= 2

    def write_to(self, mut writer: Some[Writer]):
        """Write the kind's name.

        Args:
            writer: Where to write it.
        """
        if self.value == 0:
            writer.write("RENDERABLE_FACE")
        elif self.value == 1:
            writer.write("RENDERABLE_LINE")
        elif self.value == 2:
            writer.write("RENDERABLE_SPRITE")
        else:
            writer.write("RenderableKind(", self.value, ")")


# A triangle: three.js's `RenderableFace`.
comptime RENDERABLE_FACE = RenderableKind(0)
# A segment: three.js's `RenderableLine`.
comptime RENDERABLE_LINE = RenderableKind(1)
# A point or a sprite: three.js's `RenderableSprite`.
comptime RENDERABLE_SPRITE = RenderableKind(2)


@fieldwise_init
struct RenderableVertex(Copyable, Movable):
    """A projected vertex: where it is in the world, and on screen as
    x, y, z and w."""

    var world: Vec
    var screen: Vec


struct Renderable(Copyable, Movable):
    """One projected element, three.js's `RenderableFace`,
    `RenderableLine` or `RenderableSprite`."""

    var kind: RenderableKind
    # The node of the object it came from, three.js's `object.id`.
    var id: Int
    var node: NodeId
    var material: MaterialId
    var z: Float64
    var render_order: Int
    # A face's three vertices, or a line's two.
    var vertices: List[RenderableVertex]
    # A face's normal in the world, its vertex normals, and its texture
    # coordinates.
    var normal: Vec
    var vertex_normals: List[Vec]
    var uvs: List[Vec]
    # A face's color, or a line's two vertex colors, linear.
    var colors: List[Vec]
    # A sprite's center on screen, x and y from -1 to 1, and its size.
    var x: Float64
    var y: Float64
    var scale_x: Float64
    var scale_y: Float64
    # Whether a sprite is a point of a `Points` object, whose material's
    # size scales it: three.js's `material.isPointsMaterial`.
    var is_point: Bool

    def __init__(
        out self,
        kind: RenderableKind,
        id: Int,
        node: NodeId,
        material: MaterialId,
        render_order: Int,
    ):
        """Start an element with nothing projected.

        Args:
            kind: What it is.
            id: Its object's id.
            node: Its object's node.
            material: Its material.
            render_order: Its object's render order.
        """
        self.kind = kind
        self.id = id
        self.node = node
        self.material = material
        self.z = 0
        self.render_order = render_order
        self.vertices = List[RenderableVertex]()
        self.normal = Vec(0)
        self.vertex_normals = List[Vec]()
        self.uvs = List[Vec]()
        self.colors = [Vec(1, 1, 1, 0), Vec(1, 1, 1, 0)]
        self.x = 0
        self.y = 0
        self.scale_x = 0
        self.scale_y = 0
        self.is_point = False


@fieldwise_init
struct _Object(Copyable, Movable):
    """An object to project: which list it is in, its index there, its
    node, depth and render order."""

    # 0 a mesh, 1 a line, 2 points, 3 a sprite.
    var list: Int
    var index: Int
    var node: NodeId
    var z: Float64
    var render_order: Int


struct RenderData(Movable):
    """What `project_scene` gives: three.js's `renderData`."""

    # The visible lights, as indices into `Scene.lights`, in scene order.
    var lights: List[Int]
    var elements: List[Renderable]

    def __init__(out self):
        """Start with nothing."""
        self.lights = List[Int]()
        self.elements = List[Renderable]()


struct Matrix(ImplicitlyCopyable):
    """A 4 by 4 matrix of doubles, column-major, as three.js's `elements`
    holds it."""

    var e: List[Float64]

    def __init__(out self, matrix: Matrix4):
        """Widen a matrix.

        Args:
            matrix: The matrix.
        """
        self.e = List[Float64](capacity=16)
        for k in range(16):  # pragma: no branch
            self.e.append(Float64(matrix.elements[k]))

    def __init__(out self, *, var elements: List[Float64]):
        """Hold sixteen doubles.

        Args:
            elements: The elements, column-major.
        """
        self.e = elements^

    def __init__(out self, *, copy: Self):
        """Copy a matrix.

        Args:
            copy: The matrix.
        """
        self.e = copy.e.copy()

    def times(self, other: Self) -> Self:
        """Return `self * other`, three.js's `multiplyMatrices`.

        Args:
            other: The right-hand matrix.

        Returns:
            The product.
        """
        var out = List[Float64](length=16, fill=0)
        for c in range(4):  # pragma: no branch
            for r in range(4):  # pragma: no branch
                var s = Float64(0)
                for k in range(4):  # pragma: no branch
                    s += self.e[k * 4 + r] * other.e[c * 4 + k]
                out[c * 4 + r] = s
        return Self(elements=out^)

    def apply(self, v: Vec) -> Vec:
        """Return `self * (x, y, z, w)`, three.js's `Vector4.applyMatrix4`.

        Args:
            v: The vector.

        Returns:
            The product.
        """
        var out = Vec(0)
        for r in range(4):  # pragma: no branch
            out[r] = (
                self.e[r] * v[0]
                + self.e[4 + r] * v[1]
                + self.e[8 + r] * v[2]
                + self.e[12 + r] * v[3]
            )
        return out

    def point(self, v: Vec) -> Vec:
        """Return three.js's `Vector3.applyMatrix4`: the point transformed
        and divided by its w.

        Args:
            v: The point; its w is not read.

        Returns:
            The point.
        """
        var p = self.apply(Vec(v[0], v[1], v[2], 1))
        var w = 1 / p[3]
        return Vec(p[0] * w, p[1] * w, p[2] * w, 0)

    def normal_matrix(self) -> List[Float64]:
        """Return three.js's `Matrix3.getNormalMatrix`: the inverse
        transpose of the upper 3 by 3, or zeros for a singular one.

        Returns:
            Nine doubles, column-major.
        """
        # three.js's names: row, then column.
        var n11 = self.e[0]
        var n21 = self.e[1]
        var n31 = self.e[2]
        var n12 = self.e[4]
        var n22 = self.e[5]
        var n32 = self.e[6]
        var n13 = self.e[8]
        var n23 = self.e[9]
        var n33 = self.e[10]
        var t11 = n33 * n22 - n32 * n23
        var t12 = n32 * n13 - n33 * n12
        var t13 = n23 * n12 - n22 * n13
        var det = n11 * t11 + n21 * t12 + n31 * t13
        if det == 0:
            return List[Float64](length=9, fill=0)
        var s = 1 / det
        # `invert`, column-major, then `transpose`.
        return [
            t11 * s,
            t12 * s,
            t13 * s,
            (n31 * n23 - n33 * n21) * s,
            (n33 * n11 - n31 * n13) * s,
            (n21 * n13 - n23 * n11) * s,
            (n32 * n21 - n31 * n22) * s,
            (n31 * n12 - n32 * n11) * s,
            (n22 * n11 - n21 * n12) * s,
        ]

    def max_scale(self) -> Float64:
        """Return three.js's `getMaxScaleOnAxis`.

        Returns:
            The longest column of the upper 3 by 3.
        """
        var best = Float64(0)
        for c in range(3):  # pragma: no branch
            var x = self.e[c * 4]
            var y = self.e[c * 4 + 1]
            var z = self.e[c * 4 + 2]
            best = max(best, x * x + y * y + z * z)
        return sqrt(best)


def apply_normal(m: List[Float64], v: Vec) -> Vec:
    """Return a vector through a 3 by 3 matrix, normalized, as three.js's
    `applyMatrix3( ... ).normalize()` does.

    Args:
        m: The matrix, column-major.
        v: The vector.

    Returns:
        The unit vector, or NaNs for NaN.
    """
    var x = m[0] * v[0] + m[3] * v[1] + m[6] * v[2]
    var y = m[1] * v[0] + m[4] * v[1] + m[7] * v[2]
    var z = m[2] * v[0] + m[5] * v[1] + m[8] * v[2]
    var length = sqrt(x * x + y * y + z * z)
    var scale = 1 / (length if length != 0 else 1)
    return Vec(x * scale, y * scale, z * scale, 0)


def _painter_before(
    a_order: Int, a_z: Float64, a_id: Int, b_order: Int, b_z: Float64, b_id: Int
) -> Bool:
    """Return True if three.js's `painterSort` puts `b` before `a`.

    Args:
        a_order: The first's render order.
        a_z: Its depth.
        a_id: Its id.
        b_order: The second's render order.
        b_z: Its depth.
        b_id: Its id.

    Returns:
        Whether the second sorts strictly first.
    """
    if a_order != b_order:
        return b_order < a_order
    if a_z != b_z:
        return b_z > a_z
    return b_id < a_id


def _sort_objects(mut objects: List[_Object]):
    """Sort objects as three.js's stable sort with `painterSort` does.

    Args:
        objects: The objects.
    """
    for i in range(1, len(objects)):
        var j = i
        while j > 0 and _painter_before(
            objects[j - 1].render_order,
            objects[j - 1].z,
            Int(objects[j - 1].node.value),
            objects[j].render_order,
            objects[j].z,
            Int(objects[j].node.value),
        ):
            objects.swap_elements(j - 1, j)
            j -= 1


def _sort_elements(mut elements: List[Renderable]):
    """Sort elements as three.js's stable sort with `painterSort` does.

    Args:
        elements: The elements.
    """
    # A stable merge of runs: insertion into a sorted index list.
    var order = List[Int]()
    for i in range(len(elements)):
        var j = len(order)
        order.append(i)
        while j > 0 and _painter_before(
            elements[order[j - 1]].render_order,
            elements[order[j - 1]].z,
            elements[order[j - 1]].id,
            elements[i].render_order,
            elements[i].z,
            elements[i].id,
        ):
            order[j] = order[j - 1]
            j -= 1
        order[j] = i
    var sorted = List[Renderable](capacity=len(elements))
    for i in order:
        sorted.append(elements[i].copy())
    elements = sorted^


def _clip_line(mut s1: Vec, mut s2: Vec) -> Bool:
    """Clip a segment to the near and far planes, three.js's `clipLine`:
    the second point moves toward the first after the first has moved.

    Args:
        s1: The first point, in clip space.
        s2: The second.

    Returns:
        Whether any of the segment is left.
    """
    var alpha1 = Float64(0)
    var alpha2 = Float64(1)
    var near1 = s1[2] + s1[3]
    var near2 = s2[2] + s2[3]
    var far1 = -s1[2] + s1[3]
    var far2 = -s2[2] + s2[3]
    if near1 >= 0 and near2 >= 0 and far1 >= 0 and far2 >= 0:
        return True
    if (near1 < 0 and near2 < 0) or (far1 < 0 and far2 < 0):
        return False
    if near1 < 0:
        alpha1 = max(alpha1, near1 / (near1 - near2))
    elif near2 < 0:
        alpha2 = min(alpha2, near1 / (near1 - near2))
    if far1 < 0:
        alpha1 = max(alpha1, far1 / (far1 - far2))
    elif far2 < 0:
        alpha2 = min(alpha2, far1 / (far1 - far2))
    if alpha2 < alpha1:
        return False
    s1 = s1 + (s2 - s1) * alpha1
    s2 = s2 + (s1 - s2) * (1 - alpha2)
    return True


struct _Frustum:
    """Six planes from a view-projection matrix, three.js's
    `Frustum.setFromProjectionMatrix`, in doubles."""

    var planes: List[Vec]

    def __init__(out self, m: Matrix):
        """Build the planes.

        Args:
            m: The view-projection matrix.
        """
        var e = m.e.copy()
        var rows: List[Vec] = [
            Vec(e[3] - e[0], e[7] - e[4], e[11] - e[8], e[15] - e[12]),
            Vec(e[3] + e[0], e[7] + e[4], e[11] + e[8], e[15] + e[12]),
            Vec(e[3] + e[1], e[7] + e[5], e[11] + e[9], e[15] + e[13]),
            Vec(e[3] - e[1], e[7] - e[5], e[11] - e[9], e[15] - e[13]),
            Vec(e[3] - e[2], e[7] - e[6], e[11] - e[10], e[15] - e[14]),
            Vec(e[3] + e[2], e[7] + e[6], e[11] + e[10], e[15] + e[14]),
        ]
        self.planes = List[Vec]()
        for p in rows:  # pragma: no branch
            var n = sqrt(p[0] * p[0] + p[1] * p[1] + p[2] * p[2])
            self.planes.append(p * (1 / n))

    def sphere(self, center: Vec, radius: Float64) -> Bool:
        """Return three.js's `intersectsSphere`.

        Args:
            center: The center.
            radius: The radius.

        Returns:
            Whether the sphere touches the frustum.
        """
        for p in self.planes:  # pragma: no branch
            var d = (
                p[0] * center[0] + p[1] * center[1] + p[2] * center[2] + p[3]
            )
            if d < -radius:
                return False
        return True


def project_scene(
    mut scene: Scene,
    assets: Assets,
    projection: Matrix4,
    view: Matrix4,
    sort_objects: Bool = True,
    sort_elements: Bool = True,
) raises -> RenderData:
    """Project a scene, three.js's `Projector.projectScene`.

    Args:
        scene: The scene. Its world matrices are brought up to date.
        assets: Its geometries and materials.
        projection: The camera's projection matrix.
        view: The camera's view matrix, its world matrix's inverse.
        sort_objects: Sort the objects before they are projected.
        sort_elements: Sort the elements after.

    Returns:
        The lights and the elements.

    Raises:
        Error: If a geometry, a material or a node is not in the scene's
            stores.
    """
    scene.update()
    var projection64 = Matrix(projection)
    var view_projection = projection64.times(Matrix(view))
    var frustum = _Frustum(view_projection)
    var data = RenderData()
    var objects = List[_Object]()

    # three.js's `projectObject`: depth first, a hidden node hiding all
    # under it.
    # A light on no node, as an ambient light is, is always shown.
    for i in range(len(scene.lights)):
        if scene.lights[i].node == NO_PARENT:
            data.lights.append(i)
    var stack = List[NodeId]()
    var tops = scene.children(NO_PARENT)
    for k in range(len(tops) - 1, -1, -1):
        stack.append(tops[k])
    while len(stack) > 0:
        var node = stack.pop()
        var held = scene.get(node)
        if not held.visible:
            continue
        var world = Matrix(scene.world_matrix(node))
        var order = held.render_order
        var center = world.point(Vec(0))
        var depth = view_projection.point(
            Vec(world.e[12], world.e[13], world.e[14], 0)
        )[2]
        for i in range(len(scene.lights)):
            if scene.lights[i].node == node:
                data.lights.append(i)
        for list in range(4):  # pragma: no branch
            var count = len(scene.meshes)
            if list == 1:
                count = len(scene.lines)
            elif list == 2:
                count = len(scene.points)
            elif list == 3:
                count = len(scene.sprites)
            for i in range(count):
                var owner: NodeId
                var material: MaterialId
                var culled: Bool
                if list == 0:
                    owner = scene.meshes[i].node
                    material = scene.meshes[i].material
                    culled = scene.meshes[i].frustum_culled
                elif list == 1:
                    owner = scene.lines[i].node
                    material = scene.lines[i].material
                    culled = scene.lines[i].frustum_culled
                elif list == 2:
                    owner = scene.points[i].node
                    material = scene.points[i].material
                    culled = scene.points[i].frustum_culled
                else:
                    owner = scene.sprites[i].node
                    material = scene.sprites[i].material
                    culled = scene.sprites[i].frustum_culled
                if owner != node:
                    continue
                if not assets.materials.get(material).visible:
                    continue
                if culled:
                    var inside: Bool
                    if list == 3:
                        # three.js's `intersectsSprite`: a sphere around the
                        # quad, widened by how far its center is moved.
                        var moved = scene.sprites[i].center
                        var dx = 0.5 - Float64(moved.x)
                        var dy = 0.5 - Float64(moved.y)
                        inside = frustum.sphere(
                            center,
                            (0.7071067811865476 + sqrt(dx * dx + dy * dy))
                            * world.max_scale(),
                        )
                    else:
                        var geometry_id = scene.meshes[
                            i
                        ].geometry if list == 0 else (
                            scene.lines[i].geometry if list
                            == 1 else scene.points[i].geometry
                        )
                        var sphere = assets.geometries.get(
                            geometry_id
                        ).bounding_sphere()
                        var c = world.point(
                            Vec(
                                Float64(sphere.center.x),
                                Float64(sphere.center.y),
                                Float64(sphere.center.z),
                                0,
                            )
                        )
                        inside = frustum.sphere(
                            c, Float64(sphere.radius) * world.max_scale()
                        )
                    if not inside:
                        continue
                objects.append(_Object(list, i, node, depth, order))
        var kids = scene.children(node)
        for k in range(len(kids) - 1, -1, -1):
            stack.append(kids[k])
    if sort_objects:
        _sort_objects(objects)
    for object in objects:
        _project(scene, assets, object, projection64, view_projection, data)
    if sort_elements:
        _sort_elements(data.elements)
    return data^


def _positions(
    scene: Scene, assets: Assets, object: _Object
) raises -> List[Float64]:
    """Return an object's positions, three at a vertex, with a mesh's
    morph targets blended in as three.js's projector blends them.

    Args:
        scene: The scene.
        assets: The geometries.
        object: The object.

    Returns:
        The positions.

    Raises:
        Error: If the geometry is not in the store.
    """
    var geometry_id = scene.meshes[
        object.index
    ].geometry if object.list == 0 else (
        scene.lines[object.index].geometry if object.list
        == 1 else scene.points[object.index].geometry
    )
    ref geometry = assets.geometries.get(geometry_id)
    var out = List[Float64]()
    if not geometry.has_attribute(String(POSITION)):
        return out^
    var raw = geometry.attribute_view(String(POSITION)).packed()
    for v in raw:  # pragma: no branch
        out.append(Float64(v))
    if object.list != 0:
        return out^
    ref influences = scene.meshes[object.index].morph_influences
    var targets = geometry.morph_count()
    for t in range(targets):
        var weight = Float64(influences[t]) if t < len(influences) else 0
        if weight == 0:
            continue
        for i in range(0, len(raw) - 2, 3):  # pragma: no branch
            var p = geometry.morph_position(t, i // 3)
            var target: List[Float64] = [
                Float64(p.x),
                Float64(p.y),
                Float64(p.z),
            ]
            for c in range(3):  # pragma: no branch
                if geometry.morph_relative:
                    out[i + c] += target[c] * weight
                else:
                    out[i + c] += (target[c] - Float64(raw[i + c])) * weight
    return out^


def _floats(geometry: BufferGeometry, name: String) raises -> List[Float64]:
    """Return an attribute's numbers, or none if the geometry has none."""
    var out = List[Float64]()
    if geometry.has_attribute(name):
        for v in geometry.attribute_view(name).packed():  # pragma: no branch
            out.append(Float64(v))
    return out^


def _read(numbers: List[Float64], at: Int, count: Int) -> Vec:
    """Return `count` numbers from `at`, NaN past the end, as three.js's
    `fromArray` reads them; the rest zero."""
    var out = Vec(0)
    for k in range(count):  # pragma: no branch
        if at + k < len(numbers):
            out[k] = numbers[at + k]
        else:
            out[k] = nan[DType.float64]()
    return out


@fieldwise_init
struct _Vertex(Copyable, Movable):
    """A vertex of the object being projected, three.js's pooled
    `RenderableVertex`: its place in the model, the world and on screen,
    and whether it is inside the clip box."""

    var local: Vec
    var world: Vec
    var screen: Vec
    var visible: Bool


def _project_vertex(world: Matrix, view_projection: Matrix, p: Vec) -> _Vertex:
    """Project one vertex, three.js's `projectVertex`."""
    var w = world.point(p)
    var s = view_projection.apply(Vec(w[0], w[1], w[2], 1))
    var inv = 1 / s[3]
    s[0] *= inv
    s[1] *= inv
    s[2] *= inv
    var visible = (
        s[0] >= -1
        and s[0] <= 1
        and s[1] >= -1
        and s[1] <= 1
        and s[2] >= -1
        and s[2] <= 1
    )
    return _Vertex(p, w, s, visible)


def _face_on_screen(a: _Vertex, b: _Vertex, c: _Vertex) -> Bool:
    """Return three.js's `checkTriangleVisibility`: a corner inside the
    clip box, or a bounding box that touches it."""
    if a.visible or b.visible or c.visible:
        return True
    for k in range(3):  # pragma: no branch
        var low = min(a.screen[k], min(b.screen[k], c.screen[k]))
        var high = max(a.screen[k], max(b.screen[k], c.screen[k]))
        if high < -1 or low > 1:
            return False
    return True


def _faces_camera(a: _Vertex, b: _Vertex, c: _Vertex) -> Bool:
    """Return three.js's `checkBackfaceCulling`: the corners turn
    counterclockwise on screen."""
    var across = (c.screen[0] - a.screen[0]) * (b.screen[1] - a.screen[1])
    var up = (c.screen[1] - a.screen[1]) * (b.screen[0] - a.screen[0])
    return across - up < 0


def _corner(vertices: List[_Vertex], at: Int) raises -> _Vertex:
    """Return a vertex a face or a line names."""
    if at < 0 or at >= len(vertices):
        raise Error(
            "A projected face or line must name a vertex its geometry has"
        )
    return vertices[at].copy()


def _push_point(
    v: Vec,
    object: _Object,
    material: MaterialId,
    scale: Vector3,
    projection: Matrix,
    is_point: Bool,
    mut data: RenderData,
):
    """Add a sprite if its center is between the near and far planes,
    three.js's `pushPoint`."""
    var inv = 1 / v[3]
    var z = v[2] * inv
    if z < -1 or z > 1:
        return
    var sprite = Renderable(
        RENDERABLE_SPRITE,
        Int(object.node.value),
        object.node,
        material,
        object.render_order,
    )
    sprite.x = v[0] * inv
    sprite.y = v[1] * inv
    sprite.z = z
    var p = projection.e.copy()
    sprite.scale_x = Float64(scale.x) * abs(
        sprite.x - (v[0] + p[0]) / (v[3] + p[12])
    )
    sprite.scale_y = Float64(scale.y) * abs(
        sprite.y - (v[1] + p[5]) / (v[3] + p[13])
    )
    sprite.is_point = is_point
    data.elements.append(sprite^)


def _push_face(
    vertices: List[_Vertex],
    corners: List[Int],
    material_id: MaterialId,
    assets: Assets,
    object: _Object,
    normal_matrix: List[Float64],
    normals: List[Float64],
    colors: List[Float64],
    uvs: List[Float64],
    mut data: RenderData,
) raises:
    """Add a face if it is on screen and faces the camera, three.js's
    `pushTriangle`."""
    var v1 = _corner(vertices, corners[0])
    var v2 = _corner(vertices, corners[1])
    var v3 = _corner(vertices, corners[2])
    if not _face_on_screen(v1, v2, v3):
        return
    ref material = assets.materials.get(material_id)
    if material.side != DOUBLE_SIDE and not _faces_camera(v1, v2, v3):
        return
    var face = Renderable(
        RENDERABLE_FACE,
        Int(object.node.value),
        object.node,
        material_id,
        object.render_order,
    )
    face.z = (v1.screen[2] + v2.screen[2] + v3.screen[2]) / 3
    var e = v3.local - v2.local
    var f = v1.local - v2.local
    face.normal = apply_normal(
        normal_matrix,
        Vec(
            e[1] * f[2] - e[2] * f[1],
            e[2] * f[0] - e[0] * f[2],
            e[0] * f[1] - e[1] * f[0],
            0,
        ),
    )
    for k in range(3):  # pragma: no branch
        face.vertex_normals.append(
            apply_normal(normal_matrix, _read(normals, corners[k] * 3, 3))
        )
        face.uvs.append(_read(uvs, corners[k] * 2, 2))
    if material.vertex_colors:
        face.colors[0] = _read(colors, corners[0] * 3, 3)
    face.vertices.append(RenderableVertex(v1.world, v1.screen))
    face.vertices.append(RenderableVertex(v2.world, v2.screen))
    face.vertices.append(RenderableVertex(v3.world, v3.screen))
    data.elements.append(face^)


def _push_line(
    vertices: List[_Vertex],
    a: Int,
    b: Int,
    model_view_projection: Matrix,
    material_id: MaterialId,
    assets: Assets,
    object: _Object,
    colors: List[Float64],
    mut data: RenderData,
) raises:
    """Add what the near and far planes leave of a segment, three.js's
    `pushLine`."""
    var v1 = _corner(vertices, a)
    var v2 = _corner(vertices, b)
    var s1 = model_view_projection.apply(
        Vec(v1.local[0], v1.local[1], v1.local[2], 1)
    )
    var s2 = model_view_projection.apply(
        Vec(v2.local[0], v2.local[1], v2.local[2], 1)
    )
    if not _clip_line(s1, s2):
        return
    s1 = s1 * (1 / s1[3])
    s2 = s2 * (1 / s2[3])
    var line = Renderable(
        RENDERABLE_LINE,
        Int(object.node.value),
        object.node,
        material_id,
        object.render_order,
    )
    line.z = max(s1[2], s2[2])
    line.vertices.append(RenderableVertex(v1.world, s1))
    line.vertices.append(RenderableVertex(v2.world, s2))
    if assets.materials.get(material_id).vertex_colors:
        line.colors[0] = _read(colors, a * 3, 3)
        line.colors[1] = _read(colors, b * 3, 3)
    data.elements.append(line^)


def _index_at(index: List[Int], at: Int) -> Int:
    """Return an index, or -1 past the end."""
    return index[at] if at < len(index) else -1


def _project(
    mut scene: Scene,
    assets: Assets,
    object: _Object,
    projection: Matrix,
    view_projection: Matrix,
    mut data: RenderData,
) raises:
    """Project one object into faces, lines or sprites: the body of
    three.js's loop over `_renderData.objects`."""
    var world = Matrix(scene.world_matrix(object.node))
    var scale = scene.get(object.node).scale
    if object.list == 3:
        var at = view_projection.apply(
            Vec(world.e[12], world.e[13], world.e[14], 1)
        )
        _push_point(
            at,
            object,
            scene.sprites[object.index].material,
            scale,
            projection,
            False,
            data,
        )
        return
    var positions = _positions(scene, assets, object)
    if len(positions) == 0:
        return
    var model_view_projection = view_projection.times(world)
    if object.list == 2:
        var material = scene.points[object.index].material
        for i in range(0, len(positions), 3):  # pragma: no branch
            _push_point(
                model_view_projection.apply(
                    Vec(positions[i], positions[i + 1], positions[i + 2], 1)
                ),
                object,
                material,
                scale,
                projection,
                True,
                data,
            )
        return
    var vertices = List[_Vertex]()
    for i in range(0, len(positions), 3):  # pragma: no branch
        vertices.append(
            _project_vertex(
                world,
                view_projection,
                Vec(positions[i], positions[i + 1], positions[i + 2], 0),
            )
        )
    var geometry_id: GeometryId
    if object.list == 0:
        geometry_id = scene.meshes[object.index].geometry
    else:
        geometry_id = scene.lines[object.index].geometry
    ref geometry = assets.geometries.get(geometry_id)
    var colors = _floats(geometry, String(COLOR))
    if object.list == 1:
        var material = scene.lines[object.index].material
        var pairs = List[Int]()
        if len(geometry.index) > 0:
            for i in range(0, len(geometry.index), 2):  # pragma: no branch
                pairs.append(geometry.index[i])
                pairs.append(_index_at(geometry.index, i + 1))
        else:
            var step = 2 if scene.lines[object.index].mode == SEGMENTS else 1
            for i in range(0, len(vertices) - 1, step):
                pairs.append(i)
                pairs.append(i + 1)
        for i in range(0, len(pairs), 2):
            _push_line(
                vertices,
                pairs[i],
                pairs[i + 1],
                model_view_projection,
                material,
                assets,
                object,
                colors,
                data,
            )
        return
    var normals = _floats(geometry, String(NORMAL))
    var uvs = _floats(geometry, String(UV))
    var normal_matrix = world.normal_matrix()
    var indexed = len(geometry.index) > 0
    # A run of corners and its material: each group, or the whole geometry.
    var starts = List[Int]()
    var ends = List[Int]()
    var materials = List[MaterialId]()
    ref mesh = scene.meshes[object.index]
    for group in geometry.groups:
        var material = mesh.material
        if len(mesh.materials) > 0:
            var which = group.material_index.value
            if which >= len(mesh.materials):
                continue
            material = mesh.materials[which]
        starts.append(group.start)
        ends.append(group.start + group.count)
        materials.append(material)
    if len(geometry.groups) == 0:
        starts.append(0)
        ends.append(len(geometry.index) if indexed else len(vertices))
        materials.append(mesh.material)
    for run in range(len(starts)):  # pragma: no branch
        for i in range(starts[run], ends[run], 3):  # pragma: no branch
            var corners = List[Int]()
            for k in range(3):  # pragma: no branch
                if indexed:
                    corners.append(_index_at(geometry.index, i + k))
                else:
                    corners.append(i + k)
            _push_face(
                vertices,
                corners,
                materials[run],
                assets,
                object,
                normal_matrix,
                normals,
                colors,
                uvs,
                data,
            )
