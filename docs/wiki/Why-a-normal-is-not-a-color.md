# Why a normal is not a color

A normal material and a depth material write bytes, not light. Every other stage of this renderer works in linear light. So those two fragments take a different path out. They skip the tone mapping curve. They are stored so that the sRGB encode gives back the bytes they named. The alternative is an image that lies about its own numbers.

## The problem

`RenderTarget` holds linear light and `resolve` encodes it once. See [Why color is linear](Why-color-is-linear). That is right for a lit surface. It is wrong for a normal.

A surface square on to the camera has a normal of (0, 0, 1). three.js writes that as (128, 128, 255), and a tool that reads the image expects those bytes back. The number 128 is not half the light of 255. It is the *encoding* of about 21.6% of the light.

So a normal written as linear 0.5 encodes to 188, not 128. And a tone mapping curve, whose job is to compress light that a display cannot show, moves it again. Neither step is a rounding error. Both change what the image says.

## The fix

`data_color` in `render/rasterizer.mojo` does two things. It quantizes the three channels to the bytes the material names, without the sRGB curve. Then it decodes those bytes back through the curve into the linear buffer.

`resolve` encodes that value and gets the same bytes. The two conversions cancel.

The target also records, per pixel, that the pixel holds data. `resolve` reads the flag and encodes such a pixel without tone mapping it. The last fragment written into a pixel decides.

A data material cannot blend, and both rasterizers refuse the pair. So a blend never mixes bytes with light, and a pixel that a blend touches holds light. A blend at alpha zero touches nothing and leaves the flag alone.

## Why a flag per pixel

One frame can hold both kinds. A scene with a lit floor and a sphere showing its normals needs the curve on the floor and off the sphere. A flag on the whole image cannot say that.

The flag is not a second buffer of colors. It is one `Bool` per pixel beside the depth, and both rasterizers set it the same way. The GPU kernel keeps the winning fragment's kind in a register and decides at the end, which is the same answer.

## What else takes this path

The `SHADE_UV` debug view. It writes texture coordinates as red and green, and a coordinate is not a brightness either. It used the same trick before either data material existed, spelled out by hand at the one call site. `data_color` is that trick named.

## What is given up

A translucent normal material composites its bytes as though they were light. The result means nothing, but both backends agree on it, which is what the parity tests ask for. three.js has the same property for the same reason.

The depth material's useful range depends on the camera. One minus the window-space depth is not linear in distance. A camera from one to a thousand meters puts almost every surface within a few levels of black. Set `near` and `far` close together. three.js's `MeshDepthMaterial` behaves the same way.
