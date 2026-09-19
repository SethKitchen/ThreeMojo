# Geometry

`core/buffer_geometry.mojo`, `core/buffer_attribute.mojo`, `core/geometry_store.mojo` and `geometries/`. A `BufferGeometry` holds named vertex attributes and an optional index. It can compute its own normals and bounds. Builders make boxes, spheres, planes, circles, rings, cylinders, cones, tori, torus knots, the four regular polyhedra, capsules, lathes and tubes. Two more fill a drawn [shape](Curves) in, and give it thickness. Two more read a surface back as the lines of its edges.

![A torus knot turns under a lamp](out/geometry.png)

three.js: `BufferGeometry`, `BufferAttribute`, `computeVertexNormals`, `computeBoundingBox`, `computeBoundingSphere`, `BoxGeometry`, `SphereGeometry`, `PlaneGeometry`, `CircleGeometry`, `RingGeometry`, `CylinderGeometry`, `ConeGeometry`, `TorusGeometry`, `TorusKnotGeometry`, `PolyhedronGeometry`, `TetrahedronGeometry`, `OctahedronGeometry`, `IcosahedronGeometry`, `DodecahedronGeometry`, `CapsuleGeometry`, `LatheGeometry`, `TubeGeometry`. Also `ShapeGeometry`, `ExtrudeGeometry` and `ShapeUtils.triangulateShape`.

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

Attribute names are the constants `POSITION`, `NORMAL`, `UV` and `COLOR`. A geometry needs `position`. It needs `normal` for smooth shading and `uv` for a texture. It needs `color`, three or four linear floats per vertex, for a material with `vertex_colors`. See [Materials](Materials#vertex-colors).

`compute_vertex_normals` averages the normals of the triangles a vertex is in, weighted by their areas. A shared vertex shades smoothly. A vertex used once shades flat. A vertex no triangle uses keeps a zero normal, as in three.js.

Faces are joined by index, not by position. The two vertices on either side of a texture seam keep separate normals, so a recomputed seamed sphere shows its seam, as in three.js. A builder's own normals are better. Replace them only on purpose.

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

The geometry is not indexed. Each triangle owns its three vertices. At a detail of zero the normals are flat, one per face. At a detail of one or more each normal points away from the center.

Texture coordinates are longitude and latitude, with the seam repaired per face as three.js repairs it. `v` is one at the top pole and zero at the bottom, as on the sphere. A coordinate can exceed one on a face that straddles the seam.

## Capsule

```mojo
var pill = capsule(Length(0.5, METER), Length(2.0, METER), 4, 16)   # radius, length, cap rows, around
```

A cylinder with a hemisphere on each end, standing on the y axis and centered on the origin. The length is the straight side between the caps. A length of zero is a sphere with one rim, not two. Vertices run in columns, one per step around, from the bottom pole to the top.

`u` runs around. `v` runs up the profile by distance along it, from zero at the bottom pole to one at the top. A texture stays put when the segment counts change.

The normals come from the profile exactly. On a cap they run along its radius, and on the side straight out. The caps and the side meet without a crease. The half of each cell against a pole that has no area is left out.

The sweep starts at +z, as the cylinder's does. three.js's current builder starts at -x and gives its pole vertices a half-step `u`. The shape is the same. A texture lands a quarter turn on.

## Lathe

```mojo
var vase = lathe(points, 24)                                        # a profile of Vector2, cells around
var half = lathe(points, 24, Angle(0.0, DEGREE), Angle(180.0, DEGREE))
```

A profile revolved around the y axis. Each point has `x` out from the axis and `y` along it, in meters. Vertices run in columns, one per step around, one vertex per point.

The normals come from the profile's segments, as in three.js. A corner faces the sum of its two segments' normals, each as long as its segment, made unit length. A longer segment pulls the corner its way. The first and last points face the way their own segment does.

A point on the axis is a pole. The half of each cell against it that has no area is left out. `u` runs around and `v` up the profile, one point per equal step. The sweep starts at +z, as the cylinder's does.

## Tube

```mojo
var pipe = tube(path, Length(0.2, METER), 8)                         # a path of Vector3, cells around
var loop = tube(path, Length(0.2, METER), 8, closed=True)
```

A tube of one radius swept along a path of points. Each point gets a ring, built in a frame that follows the path. The frames are three.js's parallel transport, so the tube does not twist where the path only bends. A closed path is given without repeating its first point. Its last ring repeats its first, and the twist the path built up is spread evenly back along it.

three.js samples its path from a curve. There are no curve types here yet, so the path is the points. `u` runs along the path by distance, the closing segment included. `v` runs around the tube.

## Shape

```mojo
var flat = shape_geometry(plate)                    # twelve runs a curve
var flat = shape_geometry(plate, 32)                # a finer sample
```

A [shape](Curves) filled in: a flat surface in the plane where z is zero, facing the positive z axis. The outline and its holes are sampled into points, and the points are cut into triangles. The texture coordinate of a vertex is the vertex, which is three.js's default generator.

Every other builder here is a grid. A shape is not, and cutting one up is the whole of `geometries/shape.mojo`.

### How it is cut up

By ear clipping. A corner of a loop is an ear when the triangle it makes with its two neighbors lies inside the loop. That triangle must hold no other corner. Clip that triangle off, and the loop has one corner fewer. Every simple loop has an ear at every step, so this always finishes.

A hole is a separate loop, and ear clipping knows one loop. So each hole is seamed into the outline first. Two points that can see each other are joined. The outline then runs out along that line, around the hole and back. Two points see each other when the line between them crosses no edge of the outline and no edge of any hole.

three.js casts a ray from the hole's rightmost point and fixes the cases that go wrong. This takes the shortest pair that can see each other, which has no cases to fix.

### Corners in a line are dropped

A straight edge sampled into eight runs leaves seven corners that turn by nothing. None of them can be an ear, so the clipping would stop with a row of them left. They describe one edge, and `triangulate` says so once.

`triangulate(shape, curve_segments)` returns the points, the triangles and where each contour starts, for a caller that needs more than a flat surface. `extrude` is that caller.

## Extrude

```mojo
var solid = extrude(plate, Length(2, METER))
var solid = extrude(plate, Length(2, METER), steps=4)
var solid = extrude(
    plate,
    Length(2, METER),
    bevel_enabled=True,
    bevel_thickness=Length(0.2, METER),
    bevel_size=Length(0.1, METER),
    bevel_segments=3,
)
```

A shape given thickness along the z axis, from zero to `depth`. The shape is filled in twice, once at each end, and every edge of every contour becomes a wall between them. A hole becomes a shaft through the solid.

The vertices are built in layers, each holding every contour point once at one height. `steps` cuts the walls up without changing the solid.

### The bevel

A bevel rounds the two edges off. It adds `bevel_segments` layers at each end. They reach `bevel_thickness` past the end face, and stand `bevel_size` out from the outline, by the sine and the cosine of a quarter turn.

three.js measures a bevel *out* from the shape drawn, and so does this. The two end faces are the outline itself, and the body between them stands proud of it all the way round. `bevel_offset` moves every layer out before the bevel is measured, the end faces included, which makes a lip rather than rounding an edge.

A corner moves along its miter, the line that keeps both of its edges parallel to where they were.

### The faces are flat

An extrusion has no index buffer, and its normals come from its triangles, so every vertex belongs to one face. A bevel of three segments is three flat bands. three.js does the same, and for the same reason: two walls that meet at a corner do not agree about the texture coordinate there.

A wall is measured along x or along y, whichever it runs further in, and up the negative of z. That is three.js's own generator.

three.js can also sweep a shape along a path, its `extrudePath`. That is not ported.

## Edges and wireframes

`geometries/edges.mojo` reads a surface of triangles and gives back a geometry of points, two per segment. Draw it with a [`Line`](Lines) in `SEGMENTS` mode.

```mojo
from geometries.edges import edges_geometry, wireframe_geometry
from objects.line import Line, SEGMENTS

var outline = assets.geometries.add(edges_geometry(cube(Length(1, METER))))
scene.add_line(Line(outline, ink, node, mode=SEGMENTS))
```

| Builder | What it keeps |
|---|---|
| `wireframe_geometry(geometry)` | Every edge, once each. |
| `edges_geometry(geometry, threshold)` | The edges that show the shape. |
| `triangle_edges(geometry)` | Each edge once, paired by vertex index. |
| `welded_points(geometry)` | Which welded point each vertex stands on. |

`edges_geometry` keeps an edge when the two faces meeting at it turn by at least `threshold`, and when it has one face and no neighbor. A cube keeps its twelve edges and drops the diagonal across each face. `threshold` is one degree unless said otherwise, as three.js defaults `thresholdAngle`.

`triangle_edges` is what a [wireframe material](Materials#wireframe) draws. It pairs by vertex index rather than by welded position, as three.js pairs the two rules. A wireframe is drawn from the mesh's own vertices, and two indices that stand at one place are still two vertices with their own colors. A cube has thirty edges by index and eighteen by position.

`edges_geometry` finds creases and boundaries, not silhouettes. It is given no camera, and its answer does not move when one does. What it keeps of a sphere depends on how finely the sphere is divided. Twenty-four segments turn fifteen degrees a facet, so the default threshold keeps most of those edges rather than none.

The comparison is inclusive. An edge turning exactly as far as the threshold is kept. `ANGLE_SLACK` is what makes that true in practice. An `Angle` holds radians as a `Float32`, so an authored 90 degrees has a cosine of −4.37e−8 rather than zero. Two perpendicular faces give a dot product of exactly zero. Without the slack a cube asked for its right angles lost all twelve.

### Welding first

Both weld by position before they pair. Two triangles that meet along an edge often hold two copies of each of its ends. A corner carries a normal and a texture coordinate as well as a position, and the two faces disagree about those. Pairing by vertex index would then find no shared edge anywhere.

`WELD` is the tolerance: a tenth of a millimeter, in meters. It is a distance and not a fraction, which is the bargain three.js makes with its four-decimal position hash. A geometry built at a scale far from one meter has to be welded at its own scale, and neither library does that for you.

A welded cube has eighteen unique edges, not thirty-six: twelve around the shape and one diagonal in each face.

## Morph targets

```mojo
var head = sphere(Length(1.0, METER), 24, 16)
head.add_morph_target(smiling)                 # a BufferAttribute of positions
head.add_morph_target(frowning, frown_normals) # positions and normals

var face = Mesh(assets.geometries.add(head^), skin, node)
face.set_morph_influence(0, 0.7)               # seven tenths of a smile
```

A morph target is a second set of positions for the same vertices. The mesh gives each one a weight, and the vertex drawn is the base vertex moved toward the targets by their weights. That is how a face smiles: one geometry, one target per expression, and a number per expression.

three.js: `BufferGeometry.morphAttributes`, `Mesh.morphTargetInfluences`, `morphTargetsRelative`.

| Member | Meaning |
|---|---|
| `geometry.add_morph_target(positions)` | Add a target that moves vertices only. |
| `geometry.add_morph_target(positions, normals)` | Add one that turns them too. |
| `geometry.morph_count() -> Int` | How many targets the geometry carries. |
| `geometry.has_morph_normals() -> Bool` | Whether the targets carry normals. |
| `geometry.morph_relative` | Whether a target holds destinations or offsets. |
| `mesh.set_morph_influence(target, weight)` | How much of one target to wear. |
| `mesh.morph_influence(target) -> Float32` | What it is wearing. |
| `mesh.is_morphed() -> Bool` | Whether any target is worn at all. |

The targets live on the geometry and the weights live on the mesh. That is what lets two meshes share one head and pull different faces. It is the same split that puts `position` on the geometry and the transform on the node.

### Targets add, they do not compound

Every target is measured from the *unmorphed* vertex, so wearing two of them at half each lands half way between both. Measuring each from where the last one left it would land somewhere neither names.

### Destinations or offsets

`morph_relative` is three.js's `morphTargetsRelative`. False, the default, means a target holds the finished positions and the mesh moves from the base toward them. True means it holds the offsets to add. Exporters write both.

### Normals

Either every target carries normals or none does. A geometry whose targets carry none keeps the base normal however far the positions move, which is what three.js's shader does when `morphAttributes.normal` is absent.

### What is drawn is what is picked

`core/deform.mojo` answers where a vertex is once its targets are worn, and both the renderer and the [raycaster](Raycasting) ask it. They did not always. Rendering wore the targets and picking did not, so a morphed mesh was drawn in one place and clicked in another.

### A worn mesh is not culled

A mesh wearing a target is not where its geometry's bounding sphere says it is, so the renderer does not measure it against the frustum. three.js culls it anyway, and clips morphed meshes at the edge of the view for exactly this reason.

Eight targets is this port's ceiling, not three.js's. Older three.js had the same number, from how many attribute slots a WebGL program has. Current three.js passes its targets in a texture and is bounded by memory. Eight is here because a mesh holds its weights in a fixed row rather than a list, which is what keeps a `Mesh` copyable.

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
- A lathe needs at least two points, one segment, and a sweep of at most one turn. No point can have a negative `x`, and no two consecutive points can be the same. A profile that turns straight back to the point before raises, because that corner has no normal.
- A tube needs at least two points, or three when closed, no two consecutive the same, a positive radius and three segments around. A path that returns to the point before the last raises, because that tangent is zero. A path that folds straight back on itself raises, because there is no axis to turn the frame about.
- A sweep must be positive and at most one turn.
- A morph target must cover every vertex, three numbers each, and a geometry holds at most eight.
- Either every morph target carries normals or none does.
- A morph influence must be a number, and there are eight of them.
- A shape's contour needs three corners and an area. A contour drawn in a line, or out and back, has neither.
- A shape's hole must lie inside its outline, and not inside another hole.
- An outline that crosses itself raises, because it has no inside and runs out of ears.
- An extrusion needs a positive depth, one step and one curve segment. A bevel needs a positive thickness, a size that is not negative, and one band.
- An index entry beyond the last vertex raises.
- `compute_vertex_normals`, `bounding_box` and `bounding_sphere` raise on a geometry with no positions.
