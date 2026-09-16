# Geometry

`core/buffer_geometry.mojo`, `core/buffer_attribute.mojo`, `core/geometry_store.mojo` and `geometries/`. A `BufferGeometry` holds named vertex attributes and an optional index. It can compute its own normals and bounds. Builders make boxes, spheres, planes, circles, rings, cylinders, cones, tori, torus knots, the four regular polyhedra and capsules.

three.js: `BufferGeometry`, `BufferAttribute`, `computeVertexNormals`, `computeBoundingBox`, `computeBoundingSphere`, `BoxGeometry`, `SphereGeometry`, `PlaneGeometry`, `CircleGeometry`, `RingGeometry`, `CylinderGeometry`, `ConeGeometry`, `TorusGeometry`, `TorusKnotGeometry`, `PolyhedronGeometry`, `TetrahedronGeometry`, `OctahedronGeometry`, `IcosahedronGeometry`, `DodecahedronGeometry`, `CapsuleGeometry`.

## BufferAttribute

A flat `List[Float32]` with an item size. `BufferAttribute(data, 3)` holds vectors of three floats.

| Member | Meaning |
|---|---|
| `count() -> Int` | The number of items. |
| `component(index, offset) -> Float32` | One float of one item. |
| `vector3(index) -> Vector3` | One item as a vector. Item size must be three. |

## BufferGeometry

| Member | Meaning |
|---|---|
| `set_attribute(name, attribute)` | Add or replace an attribute. |
| `attribute_view(name) -> ref BufferAttribute` | Borrow an attribute. Bind it with `ref`. |
| `clone_attribute(name) -> BufferAttribute` | Copy an attribute. |
| `has_attribute(name) -> Bool` | Whether the attribute exists. |
| `set_index(index)` | Set the triangle index. An empty list clears it. |
| `vertex_count() -> Int` | The number of vertices in `position`. |
| `triangle_count() -> Int` | The number of triangles. |
| `corner(triangle, corner) -> Vector3` | A corner position. |
| `corner_index(triangle, corner) -> Int` | Which vertex that corner is. |
| `compute_vertex_normals()` | Set `normal` from the triangles. |
| `bounding_box() -> Box3` | The box around the vertices. |
| `bounding_sphere() -> Sphere` | A sphere around the vertices, centered on that box. |

Attribute names are the constants `POSITION`, `NORMAL` and `UV`. A geometry needs `position`. It needs `normal` for smooth shading and `uv` for a texture.

`compute_vertex_normals` averages the normals of the triangles a vertex is in, weighted by their areas. A shared vertex shades smoothly. A vertex used once shades flat. A vertex no triangle uses keeps a zero normal, as in three.js.

The bounds are computed each time they are asked for. Nothing is cached. See [Math](Math#box3-sphere-and-plane) for `Box3` and `Sphere`.

## GeometryStore

`assets.geometries.add(geometry)` stores a geometry and returns a `GeometryId`. `get(id)` borrows it. Many meshes share one geometry. See [Meshes and assets](Meshes-and-assets).

## Box

```mojo
var solid = cube(Length(1.0, METER))
var brick = box(Length(2.0, METER), Length(1.0, METER), Length(0.5, METER))
```

A box has twenty-four vertices, four per face. Each face carries its own normal and texture coordinates. The whole image covers each face once.

## Sphere

```mojo
var ball = sphere(Length(1.0, METER), 24, 16)   # segments around, rings down
```

A latitude and longitude sphere. Each normal points away from the center, so shading is smooth. `u` runs once around the equator. `v` runs from one at the north pole to zero at the south pole. It needs at least three segments and two rings.

## Plane

```mojo
var sheet = plane(Length(2.0, METER), Length(1.0, METER))        # one quad
var grid = plane(Length(20.0, METER), Length(20.0, METER), 4, 4)  # sixteen quads
```

A rectangle in the xy plane, facing +z, centered on the origin. The vertex order, winding and texture coordinates match three.js. Turn the node a quarter turn about x to make a floor.

The texture coordinates run once across the rectangle. To tile an image, rewrite the `uv` attribute, as `examples/floor.mojo` does.

## Circle

```mojo
var disk = circle(Length(1.0, METER), 32)                                       # a full disk
var slice = circle(Length(1.0, METER), 8, Angle(90.0, DEGREE), Angle(180.0, DEGREE))  # a pie slice
```

A disk in the xy plane, facing +z, centered on the origin. Vertex zero is the center. The rim follows it, one vertex per segment and one more to close the seam. Each triangle runs from a rim vertex to the next one and back to the center.

The third argument is where the rim starts, counter-clockwise from +x. The fourth is how far it sweeps. A full turn is the default. A shorter sweep makes a pie slice.

The texture coordinates map the square around the disk onto the image. The center is `(0.5, 0.5)`. A pie slice shows its part of the image.

## Ring

```mojo
var washer = ring(Length(0.5, METER), Length(1.0, METER), 32, 1)   # segments around, then across
var arc = ring(Length(0.5, METER), Length(1.0, METER), 16, 1, Angle(0.0, DEGREE), Angle(90.0, DEGREE))
```

A flat ring in the xy plane, facing +z, centered on the origin. The first radius is the hole. The second is the outer edge. Vertices run in rows from the inner edge outwards, one per segment around and one more for the seam. The start angle and the sweep work as they do for the circle. A shorter sweep makes an arc.

The texture coordinates map the square around the outer edge onto the image, as the circle's do.

A ring with no hole is a disk. Use `circle` for it.

## Cylinder

```mojo
var can = cylinder(Length(1.0, METER), Length(1.0, METER), Length(2.0, METER), 32, 1)  # top radius, bottom radius, height
var bucket = cylinder(Length(0.8, METER), Length(1.2, METER), Length(2.0, METER))
var pipe = cylinder(Length(1.0, METER), Length(1.0, METER), Length(2.0, METER), 32, 1, open_ended=True)
```

A cylinder stands on the y axis, centered on the origin. The first radius is at the top and the second at the bottom. Different radii make a frustum. The side comes first, in rows from the top down, one vertex per segment around and one more for the seam. A cap follows at each end unless `open_ended` is true. Each cap has one center vertex per segment, as in three.js.

The side's triangles come column by column, in three.js's order. The caps are the only closing faces. A partial sweep leaves its two cut faces open, as in three.js.

Side normals lean with the side, so a frustum shades smoothly. Cap normals point along the axis. `u` runs once around the side. `v` runs from one at the top to zero at the bottom. Each cap maps the square around it onto the image.

The sweep starts at +z and runs toward +x, as in three.js. The circle starts at +x instead. A shorter sweep makes a section with open sides.

## Cone

```mojo
var spike = cone(Length(1.0, METER), Length(2.0, METER), 32)
```

A cone is a cylinder with a top radius of zero. Its point is at +y. The point has one vertex per segment, each with its own normal. A cylinder with a bottom radius of zero is a cone the other way up. An end with no radius gets no cap.

## Torus

```mojo
var ring = torus(Length(2.0, METER), Length(0.5, METER), 12, 48)   # radius, tube, around the tube, along it
var bend = torus(Length(2.0, METER), Length(0.5, METER), 12, 48, Angle(90.0, DEGREE))
```

A tube bent around a circle in the xy plane, centered on the origin. The first radius runs from the center to the middle of the tube. The second is the tube's own. Vertices run in rows, one row per step around the tube, one vertex per step along it and one more for the seam. Each normal points away from the middle of the tube, so the shading is smooth. `u` runs along the tube and `v` around it.

The arc runs from +x toward +y. A full turn is the default. A shorter arc makes a bent pipe with open ends.

## Torus knot

```mojo
var trefoil = torus_knot(Length(2.0, METER), Length(0.4, METER), 64, 8, 2, 3)   # radius, tube, along, around, p, q
```

A tube bent around a knot that winds `p` times around the axis and `q` times through the hole. The curve is three.js's. It lies between half and one and a half of the radius from the axis. Vertices run in rings along the curve, one vertex per step around the tube and one more for the seam. Each ring is built in three.js's frame, so a texture lands as it does there.

## Polyhedra

```mojo
var die = tetrahedron(Length(1.0, METER))
var gem = octahedron(Length(1.0, METER))
var ball = icosahedron(Length(1.0, METER), 3)       # detail three: a geodesic sphere
var dome = dodecahedron(Length(1.0, METER))
var own = polyhedron(vertices, indices, Length(1.0, METER), detail)
```

A polyhedron is a list of vertices and a list of triangles over them. Every vertex is pushed out to the radius. `detail` cuts each edge that many times, so each face becomes `(detail + 1)` squared triangles, on the way to a sphere. The four regular solids have three.js's vertices and faces in three.js's order.

The geometry is not indexed. Each triangle owns its three vertices. At a detail of zero the normals are flat, one per face. At a detail of one or more each normal points away from the center. Texture coordinates are longitude and latitude, with the seam repaired per face as three.js repairs it. A coordinate can exceed one on a face that straddles the seam.

## Capsule

```mojo
var pill = capsule(Length(0.5, METER), Length(2.0, METER), 4, 16)   # radius, length, cap rows, around
```

A cylinder with a hemisphere on each end, standing on the y axis and centered on the origin. The length is the straight side between the caps. A length of zero is a sphere. Vertices run in columns, one per step around, from the bottom pole to the top. `u` runs around and `v` runs up the profile, from zero at the bottom pole to one at the top.

The normals come from the profile exactly. On a cap they run along its radius, and on the side straight out. The caps and the side meet without a crease. The half of each cell against a pole that has no area is left out.

## Errors

- A negative or zero extent raises.
- A sphere with too few segments or rings raises.
- A plane with fewer than one segment raises.
- A circle needs a positive radius and at least three segments.
- A ring needs a positive inner radius, a larger outer radius, three segments around and one across.
- A cylinder needs a positive height, radii that are not negative and not both zero, three segments around and one down the side.
- A cone needs a positive radius and a positive height.
- A torus needs positive radii and three segments each way.
- A torus knot needs positive radii, three segments each way, and `p` and `q` of at least one.
- A polyhedron needs a positive radius, a detail of zero or more, whole vertices and faces, and faces that name vertices it has.
- A capsule needs a positive radius, a length of zero or more, one cap row, three segments around and one row up its side.
- A sweep must be positive and at most one turn.
- An index entry beyond the last vertex raises.
- `compute_vertex_normals`, `bounding_box` and `bounding_sphere` raise on a geometry with no positions.
