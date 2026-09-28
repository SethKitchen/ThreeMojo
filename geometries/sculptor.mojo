# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Sculpting tools on a mesh, from three.js `examples/jsm/misc/Sculptor.js`,
itself adapted from SculptGL by Stéphane Ginier (MIT; see
THIRD-PARTY-NOTICES.md).

A `Sculptor` takes one mesh of a scene. It welds the mesh's geometry into
a `SculptorMesh`, stores a new geometry of positions, normals and an index
in the assets, and points the mesh at it. The source geometry is not
changed. Each stroke then moves the vertices near where a ray meets the
surface, and writes them back to that geometry.

```mojo
var sculptor = Sculptor(scene, assets, 0)
sculptor.set_tool(SCULPT_INFLATE)
_ = sculptor.stroke_from_ray(scene, assets, ray, Length(0.5, METER))
_ = sculptor.stroke_from_ray(scene, assets, ray2, Length(0.5, METER))
sculptor.end_stroke()
```

A pointer works too. `connect` gives the size of the view, and
`pointer_down`, `pointer_move` and `pointer_up` take its coordinates in
pixels with the camera. The drag and scale tools need a pointer, as in
three.js: they move with the pointer, not along a ray.

With `detail` above zero, a stroke also changes the topology: it splits
edges longer than a share of the brush's radius and collapses the short
ones. `set_detail(0)` keeps the vertices and faces as they are.

**Where this differs.** three.js dispatches `start`, `change` and `end`
events; here they are appended to `events`, to read and clear. three.js
listens to a DOM element and captures the pointer; here the caller passes
each pointer event. three.js keeps spare room in the geometry's buffers,
with update ranges for the upload, and grows the bounding box and sphere
as vertices move; here each write replaces the attributes and the index at
their exact length, and the bounds are computed when asked. A pointer's
ray comes from `unproject_point`, in `Float32`, where three.js unprojects
in doubles.
"""

from cameras.camera import Camera, project_point, unproject_point
from controls.input import PRIMARY, PointerButton
from core.assets import Assets
from core.buffer_attribute import BufferAttribute
from core.buffer_geometry import BufferGeometry, NORMAL, POSITION
from core.geometry_store import GeometryId
from core.scene import Scene
from geometries.sculptor_mesh import SculptorMesh
from geometries.sculptor_tools import (
    area_center,
    area_normal,
    decimation_pass,
    get_front_vertices,
    subdivision_pass,
    tool_brush,
    tool_crease,
    tool_drag,
    tool_flatten,
    tool_inflate,
    tool_pinch,
    tool_scale,
    tool_smooth,
)
from geometries.sculptor_utils import (
    Point3,
    intersection_ray_triangle,
    point_of,
    ray_point,
)
from math.ray import Ray
from math.vector3 import Vector3
from std.math import floor, inf, isfinite, sqrt
from units.si import Length, METER

# The largest `Float32`, three.js's `MAX_FLOAT32`.
comptime MAX_FLOAT32 = 3.4028234663852886e38
# How far apart, as a share of the brush size, a pointer stroke stamps.
comptime STAMP_SPACING_RATIO = 0.15
# The ratio of the split length to the collapse length, squared: above
# two, so a split edge is not collapsed again.
comptime TOPOLOGY_HYSTERESIS2 = 2.05 * 2.05
# How far from uniform a mesh's scale may be, as a share of the largest.
comptime UNIFORM_SCALE_TOLERANCE = 1e-10
# How far above the plane the clay tool builds, as a share of the radius.
comptime CLAY_OFFSET_RATIO = 0.1
# JavaScript's `Number.EPSILON`.
comptime _EPSILON = 2.220446049250313e-16


@fieldwise_init
struct SculptTool(Equatable, ImplicitlyCopyable, Writable):
    """Which tool a sculptor strokes with, three.js's tool name, as a type
    rather than a string.

    The type stops a bare integer at compile time; it does not stop
    `SculptTool(9)`, which `Sculptor.set_tool` refuses.
    """

    var value: Int

    def is_valid(self) -> Bool:
        """Return True if this is one of three.js's nine tools.

        Returns:
            Whether the value names a tool.
        """
        return self.value >= 0 and self.value <= 8


# three.js's `'clay'`, the default: flattens toward a plane a little above
# the surface, so it builds up.
comptime SCULPT_CLAY = SculptTool(0)
# three.js's `'brush'`: raises the surface along the normal at the hit.
comptime SCULPT_BRUSH = SculptTool(1)
# three.js's `'inflate'`: moves each vertex along its own normal.
comptime SCULPT_INFLATE = SculptTool(2)
# three.js's `'smooth'`: moves each vertex toward its neighbors' mean.
comptime SCULPT_SMOOTH = SculptTool(3)
# three.js's `'flatten'`: moves the surface toward a plane.
comptime SCULPT_FLATTEN = SculptTool(4)
# three.js's `'pinch'`: moves the surface toward the center.
comptime SCULPT_PINCH = SculptTool(5)
# three.js's `'crease'`: pinches and pushes the center in.
comptime SCULPT_CREASE = SculptTool(6)
# three.js's `'drag'`: moves the surface with the pointer.
comptime SCULPT_DRAG = SculptTool(7)
# three.js's `'scale'`: moves the surface out as the pointer moves right.
comptime SCULPT_SCALE = SculptTool(8)


@fieldwise_init
struct SculptorEventKind(Equatable, ImplicitlyCopyable, Writable):
    """What happened to a sculptor, three.js's event type, as a type rather
    than a string."""

    var value: Int

    def is_valid(self) -> Bool:
        """Return True if this is `start`, `change` or `end`.

        Returns:
            Whether the value names an event.
        """
        return self.value >= 0 and self.value <= 2


# three.js's `'start'`: a stroke began.
comptime SCULPT_START = SculptorEventKind(0)
# three.js's `'change'`: the geometry was written.
comptime SCULPT_CHANGE = SculptorEventKind(1)
# three.js's `'end'`: a stroke ended.
comptime SCULPT_END = SculptorEventKind(2)


@fieldwise_init
struct _ToolSettings(ImplicitlyCopyable):
    """One tool's size, strength and direction, three.js's
    `TOOL_DEFAULTS` entry."""

    var size: Float64
    var strength: Float64
    var negative: Bool


def _tool_defaults() -> List[_ToolSettings]:
    """Return three.js's `TOOL_DEFAULTS`, in `SculptTool` order."""
    return [
        _ToolSettings(50, 0.5, False),
        _ToolSettings(50, 0.5, False),
        _ToolSettings(50, 0.3, False),
        _ToolSettings(50, 0.75, False),
        _ToolSettings(50, 0.75, True),
        _ToolSettings(50, 0.75, False),
        _ToolSettings(25, 0.75, True),
        _ToolSettings(150, 0.5, False),
        _ToolSettings(50, 0.5, False),
    ]


def _validate_unit_interval(name: String, value: Float64) raises -> Float64:
    """Refuse a value outside zero to one, three.js's
    `validateUnitInterval`."""
    if not isfinite(value) or value < 0 or value > 1:
        raise Error(
            "Sculptor: " + name + " must be a finite number between 0 and 1."
        )
    return value


def _validate_ray_tool(tool: SculptTool) raises:
    """Refuse the tools that need a pointer, three.js's
    `validateRayTool`."""
    if tool == SCULPT_DRAG or tool == SCULPT_SCALE:
        raise Error(
            "Sculptor: The drag and scale tools require pointer movement and"
            " cannot be used with stroke_from_ray()."
        )


def _compact_dirty_vertices(mut vertices: List[Int], vertex_count: Int) -> Bool:
    """Sort the dirty vertices and drop repeats and the ones past the end,
    three.js's `compactDirtyVertices`.

    Returns:
        Whether any are left.
    """
    sort(vertices)
    var kept = List[Int]()
    for vertex in vertices:
        if vertex >= vertex_count:
            break
        if len(kept) > 0 and kept[len(kept) - 1] == vertex:
            continue
        kept.append(vertex)
    vertices = kept^
    return len(vertices) > 0


def _inverse(e: List[Float64]) -> List[Float64]:
    """Return a 4x4 matrix's inverse, column-major, in three.js's
    `Matrix4.invert` order of operations. The caller has checked the matrix
    is invertible."""
    var n11 = e[0]
    var n21 = e[1]
    var n31 = e[2]
    var n41 = e[3]
    var n12 = e[4]
    var n22 = e[5]
    var n32 = e[6]
    var n42 = e[7]
    var n13 = e[8]
    var n23 = e[9]
    var n33 = e[10]
    var n43 = e[11]
    var n14 = e[12]
    var n24 = e[13]
    var n34 = e[14]
    var n44 = e[15]
    var t1 = n11 * n22 - n21 * n12
    var t2 = n11 * n32 - n31 * n12
    var t3 = n11 * n42 - n41 * n12
    var t4 = n21 * n32 - n31 * n22
    var t5 = n21 * n42 - n41 * n22
    var t6 = n31 * n42 - n41 * n32
    var t7 = n13 * n24 - n23 * n14
    var t8 = n13 * n34 - n33 * n14
    var t9 = n13 * n44 - n43 * n14
    var t10 = n23 * n34 - n33 * n24
    var t11 = n23 * n44 - n43 * n24
    var t12 = n33 * n44 - n43 * n34
    var det = t1 * t12 - t2 * t11 + t3 * t10 + t4 * t9 - t5 * t8 + t6 * t7
    var d = 1 / det
    return [
        (n22 * t12 - n32 * t11 + n42 * t10) * d,
        (n31 * t11 - n21 * t12 - n41 * t10) * d,
        (n24 * t6 - n34 * t5 + n44 * t4) * d,
        (n33 * t5 - n23 * t6 - n43 * t4) * d,
        (n32 * t9 - n12 * t12 - n42 * t8) * d,
        (n11 * t12 - n31 * t9 + n41 * t8) * d,
        (n34 * t3 - n14 * t6 - n44 * t2) * d,
        (n13 * t6 - n33 * t3 + n43 * t2) * d,
        (n12 * t11 - n22 * t9 + n42 * t7) * d,
        (n21 * t9 - n11 * t11 - n41 * t7) * d,
        (n14 * t5 - n24 * t3 + n44 * t1) * d,
        (n23 * t3 - n13 * t5 - n43 * t1) * d,
        (n22 * t8 - n12 * t10 - n32 * t7) * d,
        (n11 * t10 - n21 * t8 + n31 * t7) * d,
        (n24 * t2 - n14 * t4 - n34 * t1) * d,
        (n13 * t4 - n23 * t2 + n33 * t1) * d,
    ]


def _apply_matrix(e: List[Float64], p: Point3) -> Point3:
    """Return a point transformed and divided by w, three.js's
    `Vector3.applyMatrix4`."""
    var w = 1 / (e[3] * p.x + e[7] * p.y + e[11] * p.z + e[15])
    return Point3(
        (e[0] * p.x + e[4] * p.y + e[8] * p.z + e[12]) * w,
        (e[1] * p.x + e[5] * p.y + e[9] * p.z + e[13]) * w,
        (e[2] * p.x + e[6] * p.y + e[10] * p.z + e[14]) * w,
    )


def _transform_direction(e: List[Float64], p: Point3) -> Point3:
    """Return a direction transformed and made unit, three.js's
    `Vector3.transformDirection`."""
    var x = e[0] * p.x + e[4] * p.y + e[8] * p.z
    var y = e[1] * p.x + e[5] * p.y + e[9] * p.z
    var z = e[2] * p.x + e[6] * p.y + e[10] * p.z
    var length = sqrt(x * x + y * y + z * z)
    var inverse = 1 / (length if length != 0 else 1.0)
    return Point3(x * inverse, y * inverse, z * inverse)


def _prefix[T: Copyable](values: List[T], count: Int) -> List[T]:
    """Return a copy of the first `count` values."""
    var out = List[T](capacity=count)
    for i in range(count):  # pragma: no branch
        out.append(values[i].copy())
    return out^


def _point(v: Vector3) -> Point3:
    """Return a vector widened to doubles."""
    return Point3(Float64(v.x), Float64(v.y), Float64(v.z))


def _vector(p: Point3) -> Vector3:
    """Return a point rounded to a `Vector3`."""
    return Vector3(Float32(p.x), Float32(p.y), Float32(p.z))


def _dist2(a: Point3, b: Point3) -> Float64:
    """Return the squared distance, three.js's `distanceToSquared`."""
    var dx = a.x - b.x
    var dy = a.y - b.y
    var dz = a.z - b.z
    return dx * dx + dy * dy + dz * dz


struct Sculptor(Movable):
    """Sculpts one mesh of a scene with adaptive topology, three.js's
    `Sculptor`.

    The mesh must wear one material, and its world matrix must scale
    uniformly, by more than zero, without shear.
    """

    # The mesh's place in `scene.meshes`.
    var mesh: Int
    # The geometry the sculptor writes, which the mesh now draws.
    var geometry: GeometryId
    # Whether pointer events sculpt. Strokes from a ray do either way.
    var enabled: Bool
    # What happened, oldest first; see `SculptorEventKind`.
    var events: List[SculptorEventKind]
    var _tool_settings: List[_ToolSettings]
    var _tool: SculptTool
    var _size: Float64
    var _strength: Float64
    var _negative: Bool
    var _detail: Float64
    var _sculpt_mesh: SculptorMesh
    var _sculpting: Bool
    var _active_pointer: Optional[Int]
    var _last_pointer_x: Float64
    var _last_pointer_y: Float64
    var _hit_face: Int
    var _ray_origin: Point3
    var _ray_direction: Point3
    var _hit_point: Point3
    var _hit_normal: Point3
    var _local_radius2: Float64
    var _world_radius2: Float64
    var _drag_direction: Point3
    # The view's rectangle, three.js's `getBoundingClientRect()`: left,
    # top, width and height, in pixels. Empty while disconnected.
    var _rect: List[Float64]
    var _last_topology_version: Int
    var _last_buffer_version: Int
    var _dirty_vertices: List[Int]
    var _geometry_synced: Bool
    # The mesh's world matrix and its inverse, column-major, in doubles.
    var _matrix_world: List[Float64]
    var _matrix_inverse: List[Float64]

    def __init__(
        out self, mut scene: Scene, mut assets: Assets, mesh: Int
    ) raises:
        """Weld a mesh's geometry and give the mesh a sculptable copy.

        Args:
            scene: The scene; its mesh is pointed at the new geometry.
            assets: The geometry store; the new geometry is added to it.
            mesh: The mesh's place in `scene.meshes`.

        Raises:
            Error: If there is no such mesh, it wears more than one
                material, its geometry is not in `assets`, or
                `SculptorMesh.init_from_geometry` refuses the geometry.
        """
        if mesh < 0 or mesh >= len(scene.meshes):
            raise Error("Sculptor: mesh must be a Mesh with a BufferGeometry.")
        if scene.meshes[mesh].is_multi_material():
            raise Error("Sculptor: Multi-material meshes are not supported.")
        self.mesh = mesh
        self.enabled = True
        self.events = List[SculptorEventKind]()
        self._tool_settings = _tool_defaults()
        self._tool = SCULPT_CLAY
        self._size = self._tool_settings[0].size
        self._strength = self._tool_settings[0].strength
        self._negative = self._tool_settings[0].negative
        self._detail = 0.75
        self._sculpt_mesh = SculptorMesh()
        ref source = assets.geometries.get(scene.meshes[mesh].geometry)
        self._sculpt_mesh.init_from_geometry(source)
        var geometry = BufferGeometry()
        geometry.name = source.name
        geometry.user_data = source.user_data.copy()
        self.geometry = assets.geometries.add(geometry^)
        scene.meshes[mesh].geometry = self.geometry
        self._sculpting = False
        self._active_pointer = None
        self._last_pointer_x = 0
        self._last_pointer_y = 0
        self._hit_face = -1
        self._ray_origin = Point3(0, 0, 0)
        self._ray_direction = Point3(0, 0, 0)
        self._hit_point = Point3(0, 0, 0)
        self._hit_normal = Point3(0, 0, 0)
        self._local_radius2 = 0
        self._world_radius2 = 0
        self._drag_direction = Point3(0, 0, 0)
        self._rect = List[Float64]()
        self._last_topology_version = -1
        self._last_buffer_version = -1
        self._dirty_vertices = List[Int]()
        self._geometry_synced = False
        self._matrix_world = List[Float64]()
        self._matrix_inverse = List[Float64]()
        self._sync_geometry(assets)

    # --- the view ------------------------------------------------------------

    def connect(
        mut self, left: Float64, top: Float64, width: Float64, height: Float64
    ):
        """Take pointer events in a view, three.js's `connect`. A view
        already connected is disconnected first.

        Args:
            left: The view's left edge, in pixels.
            top: Its top edge.
            width: Its width.
            height: Its height.
        """
        if self.is_connected():
            self.disconnect()
        self._rect = [left, top, width, height]

    def disconnect(mut self):
        """Stop taking pointer events and end the stroke, three.js's
        `disconnect`."""
        self.end_stroke()
        if not self.is_connected():
            return
        self._rect = List[Float64]()
        self._clear_hit()

    def dispose(mut self):
        """Disconnect, three.js's `dispose`. The mesh and its geometry are
        kept."""
        self.disconnect()

    def is_connected(self) -> Bool:
        """Return True while a view is connected.

        Returns:
            Whether `connect` was called since the last `disconnect`.
        """
        return len(self._rect) == 4

    def _get_rect(self) raises -> List[Float64]:
        """Return the view's rectangle, three.js's `_getRect`."""
        if not self.is_connected():
            raise Error(
                "Sculptor: connect() must be called before using pointer"
                " coordinates."
            )
        return self._rect.copy()

    def _unproject[
        C: Camera
    ](
        self,
        camera: C,
        scene: Scene,
        client_x: Float64,
        client_y: Float64,
        z: Float64,
    ) raises -> Point3:
        """Return the world point under a pixel at a depth, three.js's
        `_unproject`."""
        var rect = self._get_rect()
        var x = ((client_x - rect[0]) / rect[2]) * 2 - 1
        var y = -((client_y - rect[1]) / rect[3]) * 2 + 1
        return _point(
            unproject_point(
                Vector3(Float32(x), Float32(y), Float32(z)), camera, scene
            )
        )

    def _project[
        C: Camera
    ](self, camera: C, scene: Scene, point: Point3) raises -> Point3:
        """Return where a world point lands, in pixels and depth, three.js's
        `_project`."""
        var ndc = _point(project_point(_vector(point), camera, scene))
        var rect = self._get_rect()
        return Point3(
            (ndc.x * 0.5 + 0.5) * rect[2] + rect[0],
            (-ndc.y * 0.5 + 0.5) * rect[3] + rect[1],
            ndc.z,
        )

    def _update_pointer_ray[
        C: Camera
    ](
        mut self, camera: C, scene: Scene, client_x: Float64, client_y: Float64
    ) raises -> Bool:
        """Aim the ray through a pixel, in the mesh's space, three.js's
        `_updatePointerRay`: from the near plane toward a tenth of the way
        to the far one.

        Returns:
            Whether the ray has a direction.
        """
        var near = _apply_matrix(
            self._matrix_inverse,
            self._unproject(camera, scene, client_x, client_y, -1),
        )
        var far = _apply_matrix(
            self._matrix_inverse,
            self._unproject(camera, scene, client_x, client_y, -0.8),
        )
        self._ray_origin = near
        var dx = far.x - near.x
        var dy = far.y - near.y
        var dz = far.z - near.z
        var length = sqrt(dx * dx + dy * dy + dz * dz)
        # A pixel too far out unprojects to no number.
        var usable = isfinite(length) and length > 0
        if not usable:
            return False
        self._ray_direction = Point3(dx / length, dy / length, dz / length)
        return True

    def _update_mesh_matrix(mut self, mut scene: Scene) raises -> Float64:
        """Read the mesh's world matrix and invert it, three.js's
        `_updateMeshMatrix`.

        Returns:
            The mean squared scale of the three axes.

        Raises:
            Error: If the scale is not uniform, is zero, or shears.
        """
        scene.update()
        var world = scene.world_matrix(scene.meshes[self.mesh].node)
        var e = List[Float64](capacity=16)
        for i in range(16):  # pragma: no branch
            e.append(Float64(world.elements[i]))
        var sx2 = e[0] * e[0] + e[1] * e[1] + e[2] * e[2]
        var sy2 = e[4] * e[4] + e[5] * e[5] + e[6] * e[6]
        var sz2 = e[8] * e[8] + e[9] * e[9] + e[10] * e[10]
        var scale_max2 = max(max(sx2, sy2), sz2)
        var scale_min2 = min(min(sx2, sy2), sz2)
        var tolerance = scale_max2 * UNIFORM_SCALE_TOLERANCE
        var dot_xy = e[0] * e[4] + e[1] * e[5] + e[2] * e[6]
        var dot_xz = e[0] * e[8] + e[1] * e[9] + e[2] * e[10]
        var dot_yz = e[4] * e[8] + e[5] * e[9] + e[6] * e[10]
        if (
            scale_min2 <= _EPSILON
            or scale_max2 - scale_min2 > tolerance
            or abs(dot_xy) > tolerance
            or abs(dot_xz) > tolerance
            or abs(dot_yz) > tolerance
        ):
            raise Error(
                "Sculptor: The mesh must have a non-zero uniform world scale"
                " without shear."
            )
        self._matrix_world = e.copy()
        self._matrix_inverse = _inverse(e)
        return (sx2 + sy2 + sz2) / 3

    def _clear_hit(mut self):
        """Forget the hit, three.js's `_clearHit`."""
        self._hit_face = -1
        self._local_radius2 = 0
        self._world_radius2 = 0
        self._hit_point = Point3(0, 0, 0)
        self._hit_normal = Point3(0, 0, 0)

    def _pick_closest_face(mut self) -> Bool:
        """Find the nearest face the ray meets, three.js's
        `_pickClosestFace`.

        Returns:
            Whether the ray meets one.
        """
        var candidates = self._sculpt_mesh.intersect_ray(
            self._ray_origin, self._ray_direction
        )
        var distance = inf[DType.float64]()
        self._hit_face = -1
        for face in candidates:
            var hit = intersection_ray_triangle(
                self._ray_origin,
                self._ray_direction,
                point_of(
                    self._sculpt_mesh.vertices,
                    self._sculpt_mesh.faces[face * 3],
                ),
                point_of(
                    self._sculpt_mesh.vertices,
                    self._sculpt_mesh.faces[face * 3 + 1],
                ),
                point_of(
                    self._sculpt_mesh.vertices,
                    self._sculpt_mesh.faces[face * 3 + 2],
                ),
            )
            if hit >= 0 and hit < distance:
                distance = hit
                self._hit_point = ray_point(
                    self._ray_origin, self._ray_direction, hit
                )
                self._hit_face = face
        return self._hit_face != -1

    def _intersection_ray_mesh[
        C: Camera
    ](
        mut self,
        camera: C,
        mut scene: Scene,
        client_x: Float64,
        client_y: Float64,
    ) raises -> Bool:
        """Pick the surface under a pixel and size the brush there,
        three.js's `_intersectionRayMesh`.

        Returns:
            Whether the pointer's ray meets the mesh.
        """
        var rect = self._get_rect()
        if (
            not isfinite(client_x)
            or not isfinite(client_y)
            or not isfinite(rect[2])
            or not isfinite(rect[3])
            or rect[2] <= 0
            or rect[3] <= 0
        ):
            self._clear_hit()
            return False
        var scale2 = self._update_mesh_matrix(scene)
        return self._pointer_hit(camera, scene, client_x, client_y, scale2)

    def _pointer_hit[
        C: Camera
    ](
        mut self,
        camera: C,
        scene: Scene,
        client_x: Float64,
        client_y: Float64,
        scale2: Float64,
    ) raises -> Bool:
        """Pick the surface under a pixel with the matrices already read."""
        if (
            not self._update_pointer_ray(camera, scene, client_x, client_y)
            or not self._pick_closest_face()
        ):
            self._clear_hit()
            return False
        self._update_radii(camera, scene, scale2)
        return True

    def _update_radii[
        C: Camera
    ](mut self, camera: C, scene: Scene, scale2: Float64) raises:
        """Size the brush: the world distance that `size` pixels span at
        the hit, three.js's `_updateRadii`."""
        var world_point = _apply_matrix(self._matrix_world, self._hit_point)
        var screen = self._project(camera, scene, world_point)
        var radius_point = self._unproject(
            camera, scene, screen.x + self._size, screen.y, screen.z
        )
        self._world_radius2 = _dist2(world_point, radius_point)
        self._local_radius2 = self._world_radius2 / scale2

    def _pick_vertices_in_sphere(mut self, radius2: Float64) -> List[Int]:
        """Return the vertices inside the brush, and flag them, three.js's
        `_pickVerticesInSphere`."""
        var hit = self._hit_point
        var faces = self._sculpt_mesh.intersect_sphere(hit, radius2, True)
        var in_cells = self._sculpt_mesh.get_vertices_from_faces(faces)
        var flag = self._sculpt_mesh.next_sculpt_flag()
        var picked = List[Int]()
        for vertex in in_cells:  # pragma: no branch
            var p = point_of(self._sculpt_mesh.vertices, vertex)
            if _dist2(hit, p) < radius2:
                self._sculpt_mesh.vert_sculpt_flags[vertex] = flag
                picked.append(vertex)
        return picked^

    def _compute_picked_normal(mut self):
        """Set the hit's normal: the hit face's vertex normals, weighted by
        the inverse distance to each corner, three.js's
        `_computePickedNormal`."""
        var hit = self._hit_point
        var corners = List[Int]()
        var weights = List[Float64]()
        for k in range(3):  # pragma: no branch
            var vertex = self._sculpt_mesh.faces[self._hit_face * 3 + k]
            corners.append(vertex)
            var p = point_of(self._sculpt_mesh.vertices, vertex)
            weights.append(sqrt(_dist2(hit, p)))
        var n: Point3
        if weights[0] == 0 or weights[1] == 0 or weights[2] == 0:
            var at = 0 if weights[0] == 0 else (1 if weights[1] == 0 else 2)
            n = point_of(self._sculpt_mesh.normals, corners[at])
        else:
            var w1 = 1 / weights[0]
            var w2 = 1 / weights[1]
            var w3 = 1 / weights[2]
            var inverse_sum = 1 / (w1 + w2 + w3)
            var n1 = point_of(self._sculpt_mesh.normals, corners[0])
            var n2 = point_of(self._sculpt_mesh.normals, corners[1])
            var n3 = point_of(self._sculpt_mesh.normals, corners[2])
            n = Point3(
                (n1.x * w1 + n2.x * w2 + n3.x * w3) * inverse_sum,
                (n1.y * w1 + n2.y * w2 + n3.y * w3) * inverse_sum,
                (n1.z * w1 + n2.z * w2 + n3.z * w3) * inverse_sum,
            )
        var length = sqrt(n.x * n.x + n.y * n.y + n.z * n.z)
        self._hit_normal = (
            Point3(n.x / length, n.y / length, n.z / length) if length
            > 0 else n
        )

    def _dynamic_topology(mut self, picked: List[Int]) -> List[Int]:
        """Split long edges and collapse short ones in the brush, three.js's
        `_dynamicTopology`.

        Returns:
            The vertices to sculpt: the ones picked when the topology did
            not change, else the flagged ones about the change.
        """
        var hit = self._hit_point
        var hit_face = self._hit_face
        var radius2 = self._local_radius2
        # Keep edge targets above zero at the most detail.
        var edge_max2 = radius2 * (1.1 - self._detail) * 0.2
        # Keep the collapse length below half the split length.
        var edge_min2 = edge_max2 / TOPOLOGY_HYSTERESIS2
        ref mesh = self._sculpt_mesh
        var version = mesh.topology_version
        var start = picked.copy()
        if len(start) == 0:
            start = mesh.get_vertices_from_faces([hit_face])
        var faces = mesh.get_faces_from_vertices(start)
        faces = subdivision_pass(mesh, faces, hit, radius2, edge_max2)
        faces = decimation_pass(mesh, faces, hit, radius2, edge_min2)
        if mesh.topology_version == version:
            return picked.copy()
        var affected = mesh.get_vertices_from_faces(faces)
        # The faces about the smoothed vertices, for their normals, boxes
        # and cells.
        faces = mesh.get_faces_from_vertices(affected)
        affected = mesh.get_vertices_from_faces(faces)
        var in_radius = List[Int]()
        for vertex in affected:  # pragma: no branch
            if mesh.vert_sculpt_flags[vertex] == mesh.sculpt_flag:
                in_radius.append(vertex)
        mesh.update_topology(faces, affected)
        mesh.update_geometry(faces, affected)
        self._dirty_vertices.extend(affected^)
        return in_radius^

    def _apply_stroke(mut self, scale_delta: Float64 = 0) raises:
        """Stamp the tool once at the hit, three.js's `_applyStroke`."""
        var tool = self._tool
        var strength = self._strength
        var deforms = (
            strength != 0 or tool == SCULPT_DRAG or tool == SCULPT_SCALE
        )
        var remeshes = tool != SCULPT_SMOOTH and self._detail != 0
        if not deforms and not remeshes:
            return
        var radius2 = self._local_radius2
        var picked = self._pick_vertices_in_sphere(radius2)
        if remeshes:
            picked = self._dynamic_topology(picked)
        if not deforms or len(picked) == 0:
            return
        var hit = self._hit_point
        var hit_normal = self._hit_normal
        var drag = self._drag_direction
        var negative = self._negative
        if tool == SCULPT_CLAY or tool == SCULPT_FLATTEN:
            var front = get_front_vertices(
                self._sculpt_mesh, picked, self._ray_direction
            )
            var plane_normal = area_normal(self._sculpt_mesh, front)
            if not plane_normal:
                return
            var normal = plane_normal.value()
            var plane_point = area_center(self._sculpt_mesh, front)
            if tool == SCULPT_CLAY:
                var offset = (
                    sqrt(radius2)
                    * CLAY_OFFSET_RATIO
                    * (-1.0 if negative else 1.0)
                )
                plane_point = Point3(
                    plane_point.x + normal.x * offset,
                    plane_point.y + normal.y * offset,
                    plane_point.z + normal.z * offset,
                )
            tool_flatten(
                self._sculpt_mesh,
                picked,
                normal,
                plane_point,
                hit,
                radius2,
                strength,
                negative,
            )
        elif tool == SCULPT_BRUSH:
            tool_brush(
                self._sculpt_mesh,
                picked,
                hit_normal,
                hit,
                radius2,
                strength,
                negative,
            )
        elif tool == SCULPT_INFLATE:
            tool_inflate(
                self._sculpt_mesh, picked, hit, radius2, strength, negative
            )
        elif tool == SCULPT_SMOOTH:
            tool_smooth(self._sculpt_mesh, picked, strength)
        elif tool == SCULPT_PINCH:
            tool_pinch(
                self._sculpt_mesh, picked, hit, radius2, strength, negative
            )
        elif tool == SCULPT_CREASE:
            tool_crease(
                self._sculpt_mesh,
                picked,
                hit_normal,
                hit,
                radius2,
                strength,
                negative,
            )
        elif tool == SCULPT_DRAG:
            tool_drag(self._sculpt_mesh, picked, hit, radius2, drag)
        else:
            tool_scale(self._sculpt_mesh, picked, hit, radius2, scale_delta)
        var faces = self._sculpt_mesh.get_faces_from_vertices(picked)
        var affected = self._sculpt_mesh.get_vertices_from_faces(faces)
        self._sculpt_mesh.update_geometry(faces, affected)
        self._mark_vertices_dirty(affected)

    def _mark_vertices_dirty(mut self, vertices: List[Int]):
        """Note the vertices to write back, three.js's
        `_markVerticesDirty`."""
        self._dirty_vertices.extend(vertices.copy())

    def _sync_geometry(mut self, mut assets: Assets) raises:
        """Write the positions, the normals and the index to the geometry,
        and add a `change` event when anything changed since the last
        write, three.js's `_syncGeometry`."""
        var vertex_count = self._sculpt_mesh.nb_vertices
        var replaced = (
            self._sculpt_mesh.buffer_version != self._last_buffer_version
        )
        var dirty = _compact_dirty_vertices(self._dirty_vertices, vertex_count)
        var changed = self._geometry_synced and (
            replaced
            or dirty
            or self._sculpt_mesh.topology_version != self._last_topology_version
        )
        if (
            self.geometry.value < 0
            or self.geometry.value >= assets.geometries.count()
        ):
            raise Error("Sculptor: the sculpted geometry is not in the assets.")
        ref geometry = assets.geometries.geometries[self.geometry.value]
        geometry.set_attribute(
            String(POSITION),
            BufferAttribute(
                _prefix(self._sculpt_mesh.vertices, vertex_count * 3), 3
            ),
        )
        geometry.set_attribute(
            String(NORMAL),
            BufferAttribute(
                _prefix(self._sculpt_mesh.render_normals, vertex_count * 3), 3
            ),
        )
        geometry.set_index(
            _prefix(self._sculpt_mesh.triangles, self._sculpt_mesh.nb_faces * 3)
        )
        self._last_topology_version = self._sculpt_mesh.topology_version
        self._last_buffer_version = self._sculpt_mesh.buffer_version
        self._dirty_vertices = List[Int]()
        self._geometry_synced = True
        if changed:
            self.events.append(SCULPT_CHANGE)

    def get_geometry(self, assets: Assets) raises -> BufferGeometry:
        """Return a copy of the vertices and triangles, three.js's
        `getGeometry`. The caller owns it.

        Args:
            assets: The assets holding the sculpted geometry, for its name.

        Returns:
            A new geometry with `position`, `normal` and an index.

        Raises:
            Error: If the sculpted geometry is not in `assets`.
        """
        ref mesh = self._sculpt_mesh
        var vertex_length = mesh.nb_vertices * 3
        var geometry = BufferGeometry()
        geometry.name = assets.geometries.get(self.geometry).name
        geometry.set_attribute(
            String(POSITION),
            BufferAttribute(_prefix(mesh.vertices, vertex_length), 3),
        )
        geometry.set_attribute(
            String(NORMAL),
            BufferAttribute(_prefix(mesh.render_normals, vertex_length), 3),
        )
        geometry.set_index(_prefix(mesh.triangles, mesh.nb_faces * 3))
        return geometry^

    # --- strokes -------------------------------------------------------------

    def _intersection_from_ray(
        mut self, mut scene: Scene, ray: Ray, world_radius: Length
    ) raises -> Bool:
        """Pick where a world ray meets the mesh and size the brush,
        three.js's `_intersectionFromRay`.

        Returns:
            Whether the ray meets the mesh.
        """
        var radius = Float64(world_radius.value)
        if not isfinite(radius) or radius <= 0:
            raise Error(
                "Sculptor: worldRadius must be a finite number greater than 0."
            )
        var origin = _point(ray.origin)
        var direction = _point(ray.direction)
        var length_sq = (
            direction.x * direction.x
            + direction.y * direction.y
            + direction.z * direction.z
        )
        if (
            not isfinite(origin.x)
            or not isfinite(origin.y)
            or not isfinite(origin.z)
            or not isfinite(length_sq)
            or length_sq == 0
        ):
            raise Error(
                "Sculptor: origin and direction must contain finite values, and"
                " direction must be non-zero."
            )
        var scale2 = self._update_mesh_matrix(scene)
        var local_radius = radius / sqrt(scale2)
        if local_radius > MAX_FLOAT32:
            raise Error(
                "Sculptor: worldRadius is too large or too small for the mesh"
                " scale."
            )
        self._ray_origin = _apply_matrix(self._matrix_inverse, origin)
        self._ray_direction = _transform_direction(
            self._matrix_inverse, direction
        )
        if not self._pick_closest_face():
            self._clear_hit()
            return False
        self._world_radius2 = radius * radius
        self._local_radius2 = local_radius * local_radius
        return True

    def stroke_from_ray(
        mut self,
        mut scene: Scene,
        mut assets: Assets,
        ray: Ray,
        world_radius: Length,
    ) raises -> Bool:
        """Stamp the tool where a ray meets the mesh, beginning a stroke,
        three.js's `strokeFromRay`. Call `end_stroke` after the last stamp.

        Args:
            scene: The scene, updated for the mesh's world matrix.
            assets: The assets; the sculpted geometry is written.
            ray: The ray, in world space.
            world_radius: The brush's radius, in world units.

        Returns:
            Whether the ray met the mesh. False, and nothing picked, while a
            pointer stroke is on.

        Raises:
            Error: If the tool is drag or scale, which need a pointer, or
                `pick_from_ray` raises.
        """
        if self._active_pointer:
            return False
        _validate_ray_tool(self._tool)
        if not self.pick_from_ray(scene, ray, world_radius):
            return False
        self.begin_stroke()
        self._apply_stroke()
        self._sync_geometry(assets)
        return True

    def begin_stroke(mut self):
        """Begin a stroke and add a `start` event, three.js's
        `beginStroke`. Nothing happens while a stroke is on."""
        if self._sculpting:
            return
        self._sculpting = True
        self.events.append(SCULPT_START)

    def end_stroke(mut self):
        """End the stroke, rebalance the octree, and add an `end` event,
        three.js's `endStroke`. Nothing happens while idle."""
        if not self._sculpting:
            return
        self._active_pointer = None
        self._sculpting = False
        self._sculpt_mesh.balance_octree()
        self.events.append(SCULPT_END)

    def pick_from_ray(
        mut self, mut scene: Scene, ray: Ray, world_radius: Length
    ) raises -> Bool:
        """Pick where a ray meets the mesh without sculpting, three.js's
        `pickFromRay`.

        Args:
            scene: The scene, updated for the mesh's world matrix.
            ray: The ray, in world space.
            world_radius: The brush's radius, in world units.

        Returns:
            Whether the ray met the mesh.

        Raises:
            Error: If the radius is not a positive finite number, or too
                large for the mesh's scale; the ray is not finite or has no
                direction; or the mesh's scale is not uniform.
        """
        if not self._intersection_from_ray(scene, ray, world_radius):
            return False
        self._compute_picked_normal()
        return True

    # --- the pointer ---------------------------------------------------------

    def pick_from_pointer[
        C: Camera
    ](
        mut self,
        camera: C,
        mut scene: Scene,
        client_x: Float64,
        client_y: Float64,
    ) raises -> Bool:
        """Pick the surface under a pixel without sculpting, three.js's
        `pickFromPointer`.

        Args:
            camera: The camera the view is seen through.
            scene: The scene, updated first.
            client_x: The pixel's column, from the view's left.
            client_y: The pixel's row, from the view's top.

        Returns:
            Whether the pointer's ray met the mesh.

        Raises:
            Error: If no view is connected, the mesh's scale is not
                uniform, or the camera cannot be read.
        """
        if not self._intersection_ray_mesh(camera, scene, client_x, client_y):
            return False
        self._compute_picked_normal()
        return True

    def pointer_down[
        C: Camera
    ](
        mut self,
        camera: C,
        mut scene: Scene,
        client_x: Float64,
        client_y: Float64,
        pointer_id: Int = 1,
        button: PointerButton = PRIMARY,
        is_primary: Bool = True,
    ) raises:
        """Begin a stroke where a primary press meets the mesh, three.js's
        `pointerdown` handler.

        Args:
            camera: The camera the view is seen through.
            scene: The scene, updated first.
            client_x: The pixel's column, from the view's left.
            client_y: The pixel's row, from the view's top.
            pointer_id: Which pointer; the stroke follows only this one.
            button: Which button; only the primary one sculpts.
            is_primary: Whether this is the primary pointer.

        Raises:
            Error: If the button is invalid, no view is connected, the
                mesh's scale is not uniform, or the camera cannot be read.
        """
        if not button.is_valid():
            raise Error("Invalid pointer button: ", button.value)
        if (
            not self.enabled
            or button != PRIMARY
            or not is_primary
            or self._sculpting
        ):
            return
        if not self._intersection_ray_mesh(camera, scene, client_x, client_y):
            return
        self._compute_picked_normal()
        self._active_pointer = pointer_id
        self._last_pointer_x = client_x
        self._last_pointer_y = client_y
        self.begin_stroke()

    def pointer_move[
        C: Camera
    ](
        mut self,
        camera: C,
        mut scene: Scene,
        mut assets: Assets,
        client_x: Float64,
        client_y: Float64,
        pointer_id: Int = 1,
    ) raises:
        """Stamp along the pointer's path, three.js's `pointermove`
        handler. Drag moves the surface with the pointer, scale grows it as
        the pointer moves right, and the other tools stamp every 0.15 of
        the size along the way.

        Args:
            camera: The camera the view is seen through.
            scene: The scene, updated first.
            assets: The assets; the sculpted geometry is written.
            client_x: The pixel's column, from the view's left.
            client_y: The pixel's row, from the view's top.
            pointer_id: Which pointer.

        Raises:
            Error: If the mesh's scale is not uniform, or the camera
                cannot be read.
        """
        if (
            not self.enabled
            or not self._sculpting
            or not self._active_pointer
            or self._active_pointer.value() != pointer_id
        ):
            return
        if self._tool == SCULPT_DRAG:
            self._sculpt_stroke_drag(camera, scene, assets, client_x, client_y)
        elif self._tool == SCULPT_SCALE:
            self._sculpt_stroke_scale(assets, client_x, client_y)
        else:
            var sampled = self._sculpt_stroke(
                camera, scene, assets, client_x, client_y
            )
            # Keep the hit under the pointer between stamps.
            if not sampled and self._intersection_ray_mesh(
                camera, scene, client_x, client_y
            ):
                self._compute_picked_normal()

    def pointer_up(mut self, pointer_id: Int = 1):
        """End the stroke when its pointer lifts or is canceled, three.js's
        `pointerup` handler.

        Args:
            pointer_id: Which pointer.
        """
        if (
            Bool(self._active_pointer)
            and self._active_pointer.value() == pointer_id
        ):
            self.end_stroke()

    def _sculpt_stroke[
        C: Camera
    ](
        mut self,
        camera: C,
        mut scene: Scene,
        mut assets: Assets,
        client_x: Float64,
        client_y: Float64,
    ) raises -> Bool:
        """Stamp at even steps from the last pointer place to this one,
        three.js's `_sculptStroke`.

        Returns:
            Whether the last step was stamped at the pointer.
        """
        var dx = client_x - self._last_pointer_x
        var dy = client_y - self._last_pointer_y
        var distance = sqrt(dx * dx + dy * dy)
        var min_spacing = STAMP_SPACING_RATIO * self._size
        if distance <= min_spacing:
            return False
        # A pointer at no finite place stamps nothing, as in three.js.
        var count = Int(floor(distance / min_spacing)) if isfinite(
            distance
        ) else 0
        var step_x = dx / Float64(count)
        var step_y = dy / Float64(count)
        var x = self._last_pointer_x + step_x
        var y = self._last_pointer_y + step_y
        var stamped = 0
        var sampled = False
        var scale2 = self._update_mesh_matrix(scene)
        for i in range(count):  # pragma: no branch
            sampled = i == count - 1
            if not self._pointer_hit(camera, scene, x, y, scale2):
                break
            self._compute_picked_normal()
            self._apply_stroke()
            stamped += 1
            x += step_x
            y += step_y
        self._last_pointer_x = client_x
        self._last_pointer_y = client_y
        if stamped > 0:
            self._sync_geometry(assets)
        return sampled

    def _update_drag_direction[
        C: Camera
    ](
        mut self,
        camera: C,
        scene: Scene,
        client_x: Float64,
        client_y: Float64,
        scale2: Float64,
    ) raises -> Bool:
        """Move the hit to the nearest point of the new pointer ray, and
        keep the move as the drag, three.js's `_updateDragDirection`.

        Returns:
            Whether the pointer's ray has a direction.
        """
        if not self._update_pointer_ray(camera, scene, client_x, client_y):
            return False
        var hit = self._hit_point
        var o = self._ray_origin
        var d = self._ray_direction
        var px = hit.x - o.x
        var py = hit.y - o.y
        var pz = hit.z - o.z
        var denominator = d.x * d.x + d.y * d.y + d.z * d.z
        var projection = (
            d.x * px + d.y * py + d.z * pz
        ) / denominator if denominator > 0 else 0.0
        var moved = Point3(
            o.x + d.x * projection,
            o.y + d.y * projection,
            o.z + d.z * projection,
        )
        self._drag_direction = Point3(
            moved.x - hit.x, moved.y - hit.y, moved.z - hit.z
        )
        self._hit_point = moved
        self._update_radii(camera, scene, scale2)
        return True

    def _sculpt_stroke_drag[
        C: Camera
    ](
        mut self,
        camera: C,
        mut scene: Scene,
        mut assets: Assets,
        client_x: Float64,
        client_y: Float64,
    ) raises:
        """Drag the surface along the pointer's path, three.js's
        `_sculptStrokeDrag`."""
        var dx = client_x - self._last_pointer_x
        var dy = client_y - self._last_pointer_y
        var distance = sqrt(dx * dx + dy * dy)
        if distance == 0:
            return
        var min_spacing = STAMP_SPACING_RATIO * self._size
        var count = max(1, Int(floor(distance / min_spacing))) if isfinite(
            distance
        ) else 0
        var step_x = dx / Float64(count)
        var step_y = dy / Float64(count)
        var x = self._last_pointer_x + step_x
        var y = self._last_pointer_y + step_y
        var stamped = 0
        var scale2 = self._update_mesh_matrix(scene)
        for _ in range(count):  # pragma: no branch
            if not self._update_drag_direction(camera, scene, x, y, scale2):
                break
            self._compute_picked_normal()
            self._apply_stroke()
            stamped += 1
            x += step_x
            y += step_y
        self._last_pointer_x = client_x
        self._last_pointer_y = client_y
        if stamped > 0:
            self._sync_geometry(assets)

    def _sculpt_stroke_scale(
        mut self, mut assets: Assets, client_x: Float64, client_y: Float64
    ) raises:
        """Scale the surface by how far the pointer moved right, three.js's
        `_sculptStrokeScale`."""
        var scale_delta = client_x - self._last_pointer_x
        self._last_pointer_x = client_x
        self._last_pointer_y = client_y
        if scale_delta == 0:
            return
        self._apply_stroke(scale_delta)
        self._sync_geometry(assets)

    # --- settings ------------------------------------------------------------

    def get_tool(self) -> SculptTool:
        """Return the tool, three.js's `getTool`.

        Returns:
            The tool.
        """
        return self._tool

    def set_tool(mut self, value: SculptTool) raises:
        """Choose a tool, and take back its size, strength and direction,
        three.js's `setTool`.

        Args:
            value: The tool.

        Raises:
            Error: If the tool is not one of the nine.
        """
        if not value.is_valid():
            raise Error("Sculptor: Unknown tool ", value.value, ".")
        if value == self._tool:
            return
        var settings = self._tool_settings[value.value]
        self._tool = value
        self._size = settings.size
        self._strength = settings.strength
        self._negative = settings.negative

    def get_size(self) -> Float64:
        """Return the pointer brush's radius in pixels, three.js's
        `getSize`.

        Returns:
            The radius.
        """
        return self._size

    def set_size(mut self, value: Float64) raises:
        """Set the pointer brush's radius in pixels, for this tool,
        three.js's `setSize`.

        Args:
            value: From 5 to 500.

        Raises:
            Error: If the value is outside that range or not finite.
        """
        if not isfinite(value) or value < 5 or value > 500:
            raise Error(
                "Sculptor: size must be a finite number between 5 and 500"
                " pixels."
            )
        self._size = value
        self._tool_settings[self._tool.value].size = value

    def get_strength(self) -> Float64:
        """Return the tool's strength, three.js's `getStrength`.

        Returns:
            The strength.
        """
        return self._strength

    def set_strength(mut self, value: Float64) raises:
        """Set the tool's strength, three.js's `setStrength`. Zero stops
        the tool moving vertices, but not the adaptive topology. Drag and
        scale go by the pointer instead.

        Args:
            value: From 0 to 1.

        Raises:
            Error: If the value is outside that range or not finite.
        """
        self._strength = _validate_unit_interval("strength", value)
        self._tool_settings[self._tool.value].strength = value

    def get_negative(self) -> Bool:
        """Return whether the tool works the other way, three.js's
        `getNegative`.

        Returns:
            Whether it is turned around.
        """
        return self._negative

    def set_negative(mut self, value: Bool):
        """Set whether the tool works the other way, three.js's
        `setNegative`.

        Args:
            value: Whether to turn it around.
        """
        self._negative = value
        self._tool_settings[self._tool.value].negative = value

    def get_detail(self) -> Float64:
        """Return the adaptive topology's detail, three.js's `getDetail`.

        Returns:
            The detail; zero keeps the topology.
        """
        return self._detail

    def set_detail(mut self, value: Float64) raises:
        """Set the adaptive topology's detail, three.js's `setDetail`.
        More detail makes shorter edges, as a share of the brush's radius.
        Zero keeps the topology.

        Args:
            value: From 0 to 1.

        Raises:
            Error: If the value is outside that range or not finite.
        """
        self._detail = _validate_unit_interval("detail", value)

    def is_sculpting(self) -> Bool:
        """Return whether a stroke is on, three.js's `isSculpting`.

        Returns:
            Whether a stroke is on.
        """
        return self._sculpting

    def has_hit(self) -> Bool:
        """Return whether the last pick met the mesh, three.js's `hasHit`.

        Returns:
            Whether it met the mesh.
        """
        return self._hit_face >= 0

    def get_hit_point(self) -> Vector3:
        """Return the last hit, in the mesh's space, three.js's
        `getHitPoint`.

        Returns:
            The hit, or zero when there is none.
        """
        return _vector(self._hit_point)

    def get_hit_normal(self) -> Vector3:
        """Return the surface's unit normal at the last hit, in the mesh's
        space, three.js's `getHitNormal`.

        Returns:
            The normal, or zero when there is none.
        """
        return _vector(self._hit_normal)

    def get_world_radius(self) -> Length:
        """Return the brush's radius in world units, three.js's
        `getWorldRadius`.

        Returns:
            The radius, or zero when there is no hit.
        """
        return Length(Float32(sqrt(self._world_radius2)), METER)

    def sculpt_mesh(self) -> ref[origin_of(self._sculpt_mesh)] SculptorMesh:
        """Return the welded mesh the tools change.

        Returns:
            A reference to it.
        """
        return self._sculpt_mesh
