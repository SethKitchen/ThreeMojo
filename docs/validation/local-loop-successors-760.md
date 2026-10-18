# PR760 local loop successors

These source reviews retain three local nonempty-loop theorems. They do not
admit the broader HairDensity, retained-groom, or CARLA proof graphs.

## Exact endpoints

The renderer and its count producer form one reviewed pair:

- `renderers/renderer.mojo`: `2491b99a982cd4bc49b3573d3c6db8313bfdd47372e693e932c03c27d0ff127d`
- `objects/line_segments2.mojo`: `fdff9f90123e0d3d8d3ca9b0aaf22e3b2c110c255d01a14927ce1fca8fa7d021`

The two package files and `tests/test_small_loop_witnesses.mojo` retain their
historical bindings. The complete `_emit_strand_cap` and `cap_steps` functions
are byte-identical to commit `0ad03120447c3b01fbdfa545f37debfbcd1d23bc`.
The renderer still imports `cap_steps` from `objects.line_segments2`. The
producer still imports `ceil`, `min`, and `max` from `std.math`, and keeps
`MIN_CAP_STEPS = 2` and `MAX_CAP_STEPS = 64`. No new import rebinds those names.
The unchanged count graph bounds a reached `range(1, steps + 1)` to 2 through
64 iterations. The current loop is at line 4047.

The literal upload successor is:

- `extensions/humanoid/skeleton/head/hair/strands.mojo`:
  `058c0e6fbfce95ee97c79247622185de968c8de5e0ad23240d667da13776404f`

Its complete `_upload` method is byte-identical to that same commit. The
current literal loops are `range(2)` at line 229 and `range(3)` at line 235.
The reviewed complete source does not rebind `range`. These local counts do
not establish that the outer groom loop is nonempty.

The original endpoint tables and descriptors remain unchanged. The cap
successor requires the exact pair. It does not accept a mixed historical and
current pair. Each accepted loop still requires a runtime True hit. Only its
named False outcome can be removed from the denominator.

## Receipt boundary

A compiler-free modeled-generation test exposed a missing consumed-read
check in `strand_cap_loops`. A producer with `MIN_CAP_STEPS = 0` could remain
physical throughout a generation, while a projected hash stream supplied the
reviewed bytes only to the cap checker. The receipt then included the cap
proof. Final input checks alone did not detect this projected read.

The cap checker now passes the existing receipt owner to `relative_source`
and `file_sha256`. The existing stream observer compares consumed bytes with
the same generation image. A caught mismatch remains fatal at the receipt
boundary. No new owner, admission protocol, or proof evaluator is added.

## Controls and limits

The focused Python suites cover the exact three masks, retained unrelated
branches, historical descriptors, mixed-pair selection, source mutations,
package and std shadows, symlinks, physical-text projection, projected producer
streams, mutation followed by restoration, foreign roots, closed owners,
changed include roots, and caught sticky failures. Normal and optimized Python
runs each pass 35 tests. The pinned Mojo compiler builds the maintained
`test_small_loop_witnesses` suite with warnings as errors; all three tests pass
under the unchanged 5-second suite gate. Descriptor-selection tests mock hash results only to
exercise all old/new combinations; they do not claim historical compilation.
The receipt tests use explicitly modeled producer records. They are security
controls, not native runtime or full coverage evidence.

Full coverage and CARLA source admission remain separate requirements. These
three local successors do not refresh any other source pin or waive any other
branch outcome.

## Camera-order successor

The Camera-order repair adds one exact renderer endpoint:
`df552b5bc14d6cc5a0ef4cf919afaf66da620f431b0d4f5bb9c3a61538cb2b84`.
It uses the same producer pair and line 4047. The original PR760 pair remains
accepted separately. The complete cap and producer bodies still match main.
The repair delays `camera.visible_layers()` until after the caster filter;
it does not change the cap count theorem or any receipt observation check.

The format-only successor is
`5cc066092d9b0302c60a6676459efc855e220dc319d1f88b5eb84df768f489f9`.
The wrapped generic signature adds two lines before the unchanged cap body.
The same exact producer pairs with its loop at line 4049. Both earlier PR760
pairs remain separate descriptors; no source or receipt control is removed.
