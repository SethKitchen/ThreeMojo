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

Run it with `mojo run -I . bench/hair_cost_bench.mojo`.

Hardware: AMD Ryzen 9 5900X (12 cores, 24 threads), 62 GiB, WSL 2 on
Windows 11, Mojo 1.1.0 (`8189361e`). The stages run on one thread.

## Results

| Guides x followers | Strands | Points | Vertex bytes | Grow and upload | Shade | Step and write | Shade after step |
|---|---:|---:|---:|---:|---:|---:|---:|
| 250 x 2 | 708 | 4,713 | 192,240 | 84 ms | 1.36 ms | 2.17 ms | 1.37 ms |
| 1000 x 4 | 4,875 | 32,865 | 1,343,520 | 229 ms | 9.59 ms | 16.3 ms | 9.60 ms |
| 1500 x 6 (default) | 10,185 | 68,495 | 2,798,880 | 330 ms | 20.2 ms | 33.3 ms | 20.3 ms |
| 1500 x 0 (guides only) | 1,455 | 9,785 | 399,840 | 297 ms | 2.86 ms | 4.62 ms | 2.85 ms |

Both per-frame stages scale linearly with the point count. The step costs
about 0.49 microseconds a point, and shading about 0.30 microseconds a point.
Shading after a step costs the same as shading a still groom. Growth is a
one-time cost, and most of it is the guides: the guides-only groom takes 297
of the default groom's 330 milliseconds.

The default groom's per-frame hair work is about 53 milliseconds on one
thread. A 60 frames-per-second frame has 16.7 milliseconds for everything,
so the current CPU path cannot meet that target with the default groom.

## Decisions

- **Simulate the guides only.** Followers can follow their guide in the
  guide's frame. The guides-only step costs 4.6 milliseconds, about one
  seventh of the full step. The follower interpolation is a fixed offset per
  point, so it adds a pass that is cheaper than the step. This is the next
  simulation change.
- **Move shading off one CPU thread.** Shading is 20 milliseconds for the
  default groom even with guide-only simulation. It is a per-point loop with
  no dependency between strands, so it can run in parallel on the CPU or on
  the GPU. The GPU path stays a separate decision with the rasterizer work
  in #298 and the general compositor in
  [#251](https://github.com/SethKitchen/ThreeMojo/issues/251).
- **Keep growth as a load-time cost.** It runs once per groom.

These numbers describe this machine. They are not a hardware-independent
claim, and they do not replace the named-hardware 1080p benchmark that #298
also asks for.
