# Texture gather refusal fixtures

These files contain unedited three.js r186 serialization output.
They test refusal by the node, material, and object JSON readers.
They do not establish GPU gather ordering or rendered parity.

## Source and runtime

- Package: `three@0.186.0`, from `https://registry.npmjs.org`.
- Package tarball SHA-256: `61eeff9d7616005c9a481c796f52287d81fbbbc0d55eaca5565322924252c1aa`.
- Upstream r186 commit: `9b4a2ac29c63ccb43fd51c5661f2f873ac2c39b8`.
- The package's `TextureNode.js` and `Node.js` match that commit's files.
  This comparison ignores trailing newline differences from text retrieval.
- Node: `24.19.0`; V8: `13.6.233.17-node.51`; Linux x64.
- `provenance.json` records SHA-256 hashes of the package source files.

`generate.mjs` creates a 2 by 2 data texture. The red samples are distinct
and nonzero. Green and blue are zero; alpha is one. It calls
`texture(map).gather(int(0))`, then serializes that node, a material that
uses it, and a scene that uses the material. The material explicitly sets
`shadowSide` to `FrontSide`. This numeric setting keeps the test focused
on gather. The reader now accepts the default null shadow side. The explicit-side
fixtures remain unchanged. A seeded random generator makes UUIDs
repeatable. No serialized fields or nodes are removed.

An ordinary RGBA sample cannot be used in place of these red-channel
gathers. This fixture needs no claim about the order of gathered texels.

## Generate again

Use Node `24.19.0`. From the repository root, download and unpack the
exact official package in a temporary directory:

```sh
npm pack three@0.186.0 --registry=https://registry.npmjs.org --ignore-scripts
# Check the tarball against the SHA-256 above before unpacking it.
tar xzf three-0.186.0.tgz
node assets/node_gather/generate.mjs "$PWD/package"
```

The command replaces the three JSON fixtures and their provenance file.
Run it only when updating or checking these fixtures. Keep the runtime
and package outside the committed source tree.

## Raw default-null fixtures

`default_null/` preserves the original generator, all three raw outputs,
the provenance file, and their initial hash record. The material and the
scene material have `shadowSide: null`. The composition test reads these
files without edits. Public material and object readers must pass the
null flag and refuse the reached `gatherNode` input by name. The direct
node and node-material readers must also refuse that input.

Run `node assets/node_gather/default_null/generate.mjs "$PWD/package"`
with the pinned runtime and package to generate the original form again.
Check the JSON and provenance files against `initial-hashes.json`.
The raw fixture test does not establish shadow rendering or gather parity.
