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
- `guides-only step+write`: `HairSimulation(groom, guides_only=True).step`
  and its `write`, the same work as `step+write` with the guides only.
- `guides-only frame`: that step, its write and the shading pass, timed
  together as one frame.

Each of the three simulations starts from the same grown pose. The bench
restores the points, normals and depths that a write changes before it
builds the next simulation.

Run it with `mojo run -I . bench/hair_cost_bench.mojo`.

Hardware: AMD Ryzen 9 5900X (12 cores, 24 threads), 62 GiB, WSL 2 on
Windows 11, Mojo 1.1.0 (`8189361e`). Shading and its self-shadow depths
run on every logical core. Growth and the simulation step run on one
thread.

## Results

| Guides x followers | Strands | Points | Vertex bytes | Grow and upload | Shade | Step and write | Shade after step | Guides-only step and write | Guides-only frame |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| 250 x 2 | 708 | 4,713 | 192,240 | 86 ms | 1.03 ms | 2.41 ms | 1.08 ms | 1.17 ms | 2.31 ms |
| 1000 x 4 | 4,875 | 32,865 | 1,343,520 | 227 ms | 2.57 ms | 16.9 ms | 2.70 ms | 6.73 ms | 9.96 ms |
| 1500 x 6 (default) | 10,185 | 68,495 | 2,798,880 | 319 ms | 4.98 ms | 34.9 ms | 4.69 ms | 13.3 ms | 19.1 ms |
| 1500 x 0 (no followers) | 1,455 | 9,785 | 399,840 | 299 ms | 1.36 ms | 5.07 ms | 1.42 ms | 4.90 ms | 6.43 ms |

Before shading ran in parallel, one thread shaded the default groom in 20.5
milliseconds.

Both per-frame stages scale linearly with the point count. The full step
costs about 0.5 microseconds a point on one thread.
Shading after a step costs the same as shading a still groom. Growth is a
one-time cost, and most of it is the guides: the groom without followers takes 299
of the default groom's 319 milliseconds.

On one thread the default groom's per-frame hair work was about 55
milliseconds. A 60 frames-per-second frame has 16.7 milliseconds for
everything. With guides-only simulation and parallel shading, a measured
frame of the default groom takes 19.1 milliseconds on this machine. That is
still over the budget. The write, which turns every normal and depth, is
now a large part of the guides-only step.

## Decisions

- **Simulate the guides only.** This is now `guides_only=True`. The groom
  records each follower's guide and its offsets across the hair and up off
  it. The simulation steps the guides and lays each follower at those
  offsets in its moved guide's frame, as TressFX lays follow strands. For the
  default groom the step and its write fall from 34.9 to 13.3
  milliseconds. The guides move exactly as in the full step.
- **Shade in parallel.** Shading and its self-shadow depths now run on
  every logical core. Each task owns a disjoint run of strands or points,
  and the colors and depths equal the serial arithmetic bit for bit. For
  the default groom shading falls from 20.5 to about 5 milliseconds. A GPU path
  stays a separate decision with the rasterizer work in #298 and the
  general compositor in
  [#251](https://github.com/SethKitchen/ThreeMojo/issues/251).
- **Keep growth as a load-time cost.** It runs once per groom.

These numbers describe this machine. They are not a hardware-independent
claim, and they do not replace the named-hardware 1080p benchmark that #298
also asks for.
