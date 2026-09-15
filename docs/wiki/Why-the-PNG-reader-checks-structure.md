# Why the PNG reader checks structure

The PNG decoder checks chunk order, chunk length, three separate integrity values and an output bound. A decoder that walks chunks in any order and trusts what they contain lets a malformed file reach arithmetic written for a well-formed one.

## Why a decoder at all

Writing a PNG needs no compression. DEFLATE has a stored block type, so the encoder builds a legal file from a header, raw bytes and a checksum. Reading a file someone else wrote gets no such shortcut. Every real encoder uses the compressed block types. `render/inflate.mojo` is therefore the whole of RFC 1951.

## Two things that are easy to get backwards

Bits run low to high within a byte, but Huffman codes are packed most significant bit first. The extra bits after a length or a distance are ordinary little-endian integers.

A back-reference can overlap the output's own end. A run of identical bytes is stored as one byte and a distance of one, so the copy must proceed a byte at a time.

## A file is a structure

A PNG is an ordered sequence. The header comes first and once. A palette comes before the data that indexes it. The image data is one run, and an end marker closes the file. A `tRNS` chunk one byte long once left an empty color key that the pixel loop then indexed. Every chunk CRC in that file was valid.

So order, duplication, applicability and length are checked per chunk. An unknown chunk with an uppercase first letter is critical, and the decoder refuses the file rather than pretend to have read it.

Dimensions are bounded before anything is allocated. A thirteen-byte header can ask for ten billion pixels.

## Three integrity layers

| Check | Proves |
|---|---|
| Chunk CRC | The compressed bytes survived the journey. |
| Adler-32 | They decompress to what the encoder meant. |
| Output bound | They decompress to the size the header promised. |

Only the first was checked at first. The bound is enforced as bytes are produced, because the exact size is known before inflation starts: `height * (1 + width * channels)`.

## What the samples mean

PNG does not imply sRGB. A file can declare a gamma of one. Decoding that through the sRGB curve turns a mid gray from half the light into a fifth of it, with nothing downstream able to tell. `decode` returns the samples with their declared interpretation, and `texture_from` refuses to guess. See [Image files](Image-files).

## Tested against real files

The tests decode files written by a conforming encoder, embedded as bytes. A decoder tested only against this project's encoder would never see a Huffman code or a row filter. Some fifty malformed files, each damaged in one way with correct CRCs, reach the check each is aimed at.
