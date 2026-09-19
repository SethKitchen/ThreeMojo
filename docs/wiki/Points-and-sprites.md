# Points and sprites

`objects/points.mojo`, `objects/sprite.mojo`, `render/pointrule.mojo` and the point pass in both rasterizers. A point is a vertex drawn as a square of pixels. A sprite is a square in the scene that always faces the camera. The point is the third kind of primitive the renderer draws, beside the triangle and the segment. The sprite is two triangles.

![Sprites and points orbit a lit box](out/sprites.png)

three.js: `Points`, `PointsMaterial`, `Sprite`, `SpriteMaterial`, `sizeAttenuation`, `Sprite.center`, `gl_PointCoord`.

## Points

A `Points` names a geometry, a material and a node, as a `Mesh` does. Every vertex in the geometry's `position` attribute is one point.

```mojo
from materials.material import PointSize, points_material
from objects.points import Points

var dots = assets.materials.add(
    points_material(Color(255, 220, 120), size=PointSize(4.0))
)
scene.add_points(Points(cloud, dots, node))
```

| Member | Meaning |
|---|---|
| `Points(geometry, material, node)` | Points at a scene node. |
| `points.frustum_culled` | Whether the renderer can skip them when their bound is out of view. |
| `scene.add_points(points)` | Add them to a scene. |
| `renderer.prepare_points(scene, assets, camera)` | The points as raster vertices, one each, in draw order. |

### What a point is made of

A point geometry carries its points in the `position` attribute and no index buffer. An index buffer here is a triangle index, and a point per index entry would draw a shared vertex once per triangle. `prepare_points` refuses an indexed geometry.

### What a point is drawn with

`points_material`, three.js's `PointsMaterial`. It is a `BASIC` material with a size and an attenuation flag.

| Argument | three.js | Default | Meaning |
|---|---|---|---|
| `size` | `size` | `PointSize(1.0)` | How many pixels across each point is. |
| `size_attenuation` | `sizeAttenuation` | `True` | Whether a point shrinks with its distance from the camera. |
| `map` | `map` | `NO_TEXTURE` | The image drawn across each point. |
| `alpha_map` | `alphaMap` | `NO_TEXTURE` | A texture whose green channel thins each point. |
| `alpha_test` | `alphaTest` | `0.0` | The alpha a pixel must reach to be drawn. |
| `vertex_colors` | `vertexColors` | `False` | Whether the geometry's `color` attribute tints each point. |

`PointSize` is a type, not a bare float. A size is measured on the image in pixels. It is not a `Length` in the scene, and the type keeps the two apart.

A point has no surface. It has no normal, so `prepare_points` refuses a lit kind. It does have a coordinate of its own across its square, OpenGL's `gl_PointCoord`, so it can carry a map and an alpha map. The map is sampled at that coordinate as it is stored. A map whose own transform is not the identity is refused. The `SHADE_UV` view shows the coordinate.

The color, the opacity, the blending, the alpha test and the vertex colors all work as they do on a mesh. So does the [fog](Fog).

### Size with distance

With `size_attenuation` on, a point is `size` pixels across when it is as many meters from the camera as half the image is pixels tall. Nearer it grows. A point twice as far away is half the size. This is three.js's arithmetic: `size * (scale / -z)`, where `scale` is half the image height. Under an orthographic camera nothing shrinks with distance, and the flag changes nothing. `attenuated_size` in `render/pointrule.mojo` is the formula.

### The rule

A point is a square of pixels, `size` across, centered on where the point projects. A pixel is covered when its center lies inside the square. The square is half open. A pixel center on the left or top edge is in. One on the right or bottom edge is out. Two points a size apart share no pixel and leave no gap.

`render/pointrule.mojo` holds the rule. `covers` is the whole of it.

| Function | Answer |
|---|---|
| `attenuated_size(size, view_z, scale, perspective)` | How many pixels across a point is at one depth. |
| `covers(center, size, x, y)` | Whether the point covers one pixel. |
| `coord(center, size, x, y)` | The pixel's coordinate on the square, `v` counting up. |
| `first_covered(center, size)`, `last_covered(center, size)` | The bounds the CPU walks between, rounded outward. |
| `mip_level_of(size, width, height)` | Which level of a map a point reads. |

The CPU walks the square's bounding box and asks `covers` of every pixel. The kernel asks `covers` whether this pixel is inside. Both get the answer from one expression. See [Shared CPU and GPU code](Why-the-CPU-and-GPU-share-code).

A point is a square and not a disc, and it is not anti-aliased. That is what `gl_PointSize` draws. A round point is a square point with a round alpha map.

A point's map is read at one mip level for the whole point. The level comes from the size: a pixel's footprint in the map is one over the size along both axes.

### Clipping

A point is kept or thrown away whole. One whose center is outside the view volume is left out, as OpenGL leaves it out. A point just outside the view whose square reaches into it is not drawn.

## Sprites

A `Sprite` names a material and a node. It has no geometry, because every sprite has the same one: a unit square with the image across it.

```mojo
from materials.material import sprite_material
from objects.sprite import Sprite

var badge = assets.materials.add(sprite_material(map=picture))
scene.add_sprite(Sprite(badge, node))
```

| Member | Meaning |
|---|---|
| `Sprite(material, node)` | A sprite at a scene node. |
| `Sprite(material, node, center=Vector2(0, 0))` | With the node at the sprite's bottom left. |
| `sprite.frustum_culled` | Whether the renderer can skip it when its bound is out of view. |
| `scene.add_sprite(sprite)` | Add it to a scene. |

### Where a sprite is drawn

At its node's world position. Its width is the length of the world matrix's x column and its height the length of the y column, as three.js reads `modelMatrix`. So `node.set_scale(2, 1, 1)` makes a sprite two meters wide and one tall.

The square is built in camera space, so it lies flat to the image whatever the node is turned to. A node's rotation does nothing to a sprite.

`center` says which point of the square sits on the node, in the square's own coordinates. The default, a half and a half, puts the node in the middle. Zero and zero puts it at the bottom left.

### What a sprite is drawn with

`sprite_material`, three.js's `SpriteMaterial`. It is a `BASIC` material with a rotation.

| Argument | three.js | Default | Meaning |
|---|---|---|---|
| `color` | `color` | white | A tint over the image. |
| `map` | `map` | `NO_TEXTURE` | The image on the sprite. |
| `alpha_map` | `alphaMap` | `NO_TEXTURE` | A texture whose green channel thins the sprite. |
| `rotation` | `rotation` | zero | How far the sprite is turned about the line of sight, counterclockwise. |
| `size_attenuation` | `sizeAttenuation` | `True` | Whether the sprite shrinks with distance. |
| `alpha_test` | `alphaTest` | `0.0` | The alpha a pixel must reach to be drawn. |
| `transparent` | `transparent` | `True` | Whether the sprite blends. On by default, as three.js's is. |

The rotation is an `Angle`. A bare float is a compile error.

A sprite is unlit, as three.js's is. `Renderer.prepare` refuses a lit kind. A wireframe is refused too: a sprite is a picture, and its edges say nothing. Its map's own transform is applied as a mesh's is.

With `size_attenuation` off, the sprite keeps its size on the image as the node recedes. The scale is multiplied by the camera-space depth, which the perspective divide then divides out. A unit sprite then has the size on the image it would have one meter from the camera, whatever its distance. Under an orthographic camera the flag changes nothing.

### How a sprite is drawn

As two triangles, through the pipeline every triangle goes through. It is clipped, projected, filled by the triangle rule on either backend and sorted among the meshes by its depth. A blended sprite falls between the blended surfaces either side of it. A sprite needs no rule of its own where a point does. It is never culled for its facing: a negative scale turns it inside out, and both sides are drawn.

### Culling

A sprite's bound is the sphere around its unit square, carried by its world matrix, as three.js's `Sprite` carries its geometry's sphere. The bound is measured in the scene. A sprite that keeps its size on the image is culled by where its square would be with the attenuation on. Set `frustum_culled=False` on one that is left out wrongly.

## Three lists, one order

Points are prepared by their own pass into their own list, beside the triangles and the segments. `prepare_frame` makes all three lists and one order over them. Opaque runs come first, triangles, then segments, then points, each nearest first. Blended runs follow, all three kinds together, furthest first. See [Lines](Lines#two-lists-one-order).

`GpuRenderer.draw` takes the points as its own argument and walks the same order in one launch. See [GPU backend](GPU-backend).

## What raises

- Points or a sprite naming a node, a geometry or a material that is not there.
- A points geometry with no positions, or with an index buffer.
- A points material that is not `BASIC`, or that is a wireframe.
- A points map or alpha map whose transform is not the identity.
- A sprite material that is not `BASIC`, or that is a wireframe.
- A map or an alpha map that is not there, or an alpha map that is not stored as data.
- A point size that is not a positive number, or a rotation that is not finite, when the material is built.
- A size that is not the default, attenuation off, or a rotation on a kind that is not `BASIC`.
- A point whose size is not above zero, or whose material is lit, at the rasterizer boundary.
- A sprite center that is not finite.

## Limits

Points are not morphed and not skinned. three.js allows both. A points map is not transformed. A sprite has no per-sprite tint beyond its material's color.
