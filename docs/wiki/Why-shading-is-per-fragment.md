# Why shading is per fragment

Every fragment interpolates the normal, normalizes it again, and sums the lights itself. Shading at the corners and interpolating the color, which is Gouraud shading, gives a coarse sphere a crease along every edge.

## Gouraud's limit

A triangle shaded at its corners can only be as round as its corners. A highlight that lands between two vertices is lost. A lamp close to a surface lights the corners and nothing in between.

## What travels

The normal travels to the fragment, and so does the world position. The fragment does three steps:

```
interpolate the normal  ->  make it unit length again  ->  sum the lights
```

## The middle step matters

The average of two unit vectors is shorter than either. Two normals 45 degrees apart average to a vector 0.92 long. An interpolated normal used as it is dims the middle of every triangle. The result is neither Gouraud nor Phong but a third, wrong thing.

`tests/test_rasterizer.mojo` pins this with a triangle whose two leaning corners each catch cos(45) of the light. The point between them catches all of it. Without the renormalization it catches cos(45) too.

## Both backends

`Lighting.intensity_at` on the host and `_arriving` in the kernel do the same sum. A parity test with a colored ambient and a colored lamp holds them together, so a swapped channel cannot hide.

## What it cost

Every earlier example is flat-faced, and for a constant normal the two methods agree. Four of seven images were byte for byte unchanged. Three differed in one byte each, by one, from a reassociated multiply. A larger change would have meant a bug.

## Point lights

A point light needs the fragment's position as well as its normal. That is why `RasterVertex.world` exists and why the GPU vertex has sixteen floats. `falloff` is one function that both rasterizers call.
