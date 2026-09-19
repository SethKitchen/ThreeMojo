# Why mipmaps

A texture that recedes into the distance shimmers without a mip chain. Bilinear filtering does not help, because the problem is the opposite of the one filtering solves.

## Minification is not magnification

Filtering fixes a pixel that covers less than a texel. When a surface recedes, a pixel covers dozens of texels. Reading one of them is a point sample of a signal far finer than the pixel grid can carry. Which texel it lands on swings wildly for a coordinate that barely moved. The result is noise, and the noise crawls as the camera moves.

## The chain

The answer is to average every texel under the pixel. A mip chain is those averages taken in advance. Each level is the one above it halved, so the level whose texels are pixel-sized is a lookup instead of a sum.

The chain is opt-in. It costs a third more memory and buys nothing for an image that is never minified.

## Built in linear light

Each level is built in premultiplied linear light. Averaging sRGB bytes makes every level darker than the one before, so a receding surface dims. Averaging straight alpha drags the color of transparent texels into view. Each level is re-encoded to bytes, which is what a GPU stores.

## Choosing the level

`mip_level` measures how far the texture coordinates move over one pixel, in both directions, and takes the longer. The shorter would leave the compressed direction aliasing, which is exactly the case of a surface seen edge-on. The log of that length is the level, because the chain halves.

Sampling is trilinear: bilinear within the two levels either side, then linear between them. The change from one level to the next is therefore not a visible band.

## The footprint

Hardware estimates the footprint by shading pixels in 2 by 2 quads and subtracting a neighbor's value. This renderer evaluates the neighbors from the triangle's own coordinate function, perspective divide included. It needs no inter-thread operation. The estimate is the same finite difference that hardware makes, and both backends compute it the same way.

## See it

![A receding floor is mipmapped on the right and aliases on the left](out/floor.png)

`examples/floor.mojo` renders one checkerboard floor to the horizon, mipmapped on the right and not on the left. The moiré in the top left is the point of the picture, not a defect. That half has no chain, so every pixel near the horizon is one texel picked out of dozens. The right half averages them and fades to gray.
