# Why interpolation is perspective-correct

Color, normals, texture coordinates and world positions are interpolated through `1 / w`, not straight across the screen. Depth is not. Both choices are what a graphics API does, for the same reasons.

## Screen weights are not surface weights

Perspective squeezes the far half of a triangle into fewer pixels. Barycentric weights measured on the screen therefore do not match the weights the surface itself sees. An attribute interpolated with screen weights drifts from what the geometry says, and a texture slides and warps as the camera moves.

## The correction

Each corner's value is weighted by its `inv_w`, and the sum is divided by the interpolated `inv_w`:

```
attribute = sum(w_i * a_i * inv_w_i) / sum(w_i * inv_w_i)
```

The error this removes grows with how much perspective one triangle spans. It is invisible on a subdivided sphere and obvious on a floor drawn as two triangles.

## Depth is not corrected

Depth in normalized device space is already divided by `w`. The projection makes it linear in screen space on purpose, so a depth buffer can interpolate it linearly. Correcting it again would be wrong.

## Orthographic cameras

An orthographic projection leaves `w` at one. Every `inv_w` is one, and the correction divides by one. Nothing branches on the camera type.

## See it

`make animation` renders `out/uv.png`: two frames of one floor plane with its texture coordinates written out as color. The first is correct. The second forces every `inv_w` to one. Every covered pixel differs, by up to 142 levels of 255.

Both frames come from one `Renderer.prepare` call. That is why `prepare` is public. The affine frame is the same prepared triangles with the perspective thrown away. Nothing but the correction can account for the difference.
