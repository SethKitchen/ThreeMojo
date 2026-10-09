# Strand hair CPU costs (#298)

This report measures the CPU cost of each strand-hair stage, as issue
[#298](https://github.com/SethKitchen/ThreeMojo/issues/298) asks. It then
decides the next simulation and shading work from the numbers.

## Method

`bench/hair_cost_bench.mojo` grows a six-foot male groom with
`add_groom`. It times the growth and the first geometry upload once. Then it
times five frames of each per-frame stage and reports the median:

- `shade`: `HairStrands.shade` with one distant light, a camera and ambient
  light.
- `step+write`: one `HairSimulation.step` against a scalp collider, and
  `HairSimulation.write` back into the groom.
- `shade after step`: the shading pass that follows a moved groom.
- `guides-only step`: `HairSimulation(groom, guides_only=True).step`, which
  steps the guides and lays each follower along its moved guide.

Run it with `mojo run -I . bench/hair_cost_bench.mojo`.

Hardware: AMD Ryzen 9 5900X (12 cores, 24 threads), 62 GiB, WSL 2 on
Windows 11, Mojo 1.1.0 (`8189361e`). The stages run on one thread.

## Results

| Guides x followers | Strands | Points | Vertex bytes | Grow and upload | Shade | Step and write | Shade after step | Guides-only step |
|---|---:|---:|---:|---:|---:|---:|---:|---:|
| 250 x 2 | 708 | 4,713 | 192,240 | 85 ms | 1.39 ms | 2.26 ms | 1.39 ms | 0.80 ms |
| 1000 x 4 | 4,875 | 32,865 | 1,343,520 | 230 ms | 9.76 ms | 16.1 ms | 9.76 ms | 4.05 ms |
| 1500 x 6 (default) | 10,185 | 68,495 | 2,798,880 | 334 ms | 20.5 ms | 33.9 ms | 20.5 ms | 7.08 ms |
| 1500 x 0 (no followers) | 1,455 | 9,785 | 399,840 | 303 ms | 2.89 ms | 4.80 ms | 2.89 ms | 4.04 ms |

Both per-frame stages scale linearly with the point count. The step costs
about 0.49 microseconds a point, and shading about 0.30 microseconds a point.
Shading after a step costs the same as shading a still groom. Growth is a
one-time cost, and most of it is the guides: the groom without followers takes 303
of the default groom's 334 milliseconds.

The default groom's per-frame hair work is about 53 milliseconds on one
thread. A 60 frames-per-second frame has 16.7 milliseconds for everything,
so the full CPU path cannot meet that target with the default groom. With
guides-only simulation the per-frame hair work is about 28 milliseconds,
and shading is most of it.

## Decisions

- **Simulate the guides only.** This is now `guides_only=True`. The groom
  records each follower's guide and its offsets across the hair and up off
  it. The simulation steps the guides and lays each follower at those
  offsets in its moved guide's frame, as TressFX lays follow strands. For the
  default groom the step falls from 33.9 to 7.1 milliseconds. The guides
  move exactly as in the full step.
- **Move shading off one CPU thread.** Shading is 20 milliseconds for the
  default groom even with guides-only simulation. It is a per-point loop with
  no dependency between strands, so it can run in parallel on the CPU or on
  the GPU. The GPU path stays a separate decision with the rasterizer work
  in #298 and the general compositor in
  [#251](https://github.com/SethKitchen/ThreeMojo/issues/251).
- **Keep growth as a load-time cost.** It runs once per groom.

These numbers describe this machine. They are not a hardware-independent
claim, and they do not replace the named-hardware 1080p benchmark that #298
also asks for.
