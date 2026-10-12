# Strand hair CPU costs (#298)

This report measures the CPU cost of each strand-hair stage, as issue
[#298](https://github.com/SethKitchen/ThreeMojo/issues/298) asks. It
covers shading, allocation, geometry upload and the cost of each follower
strand. Then it decides the guide-only interpolation and GPU work from the
numbers.

The decision: use guide-only interpolation for interactive frames. Do not move the hair simulation or shading to the GPU now.
Strand rasterization costs about 50 to 110 times more than all the hair
stages together, so the GPU work goes to strand drawing first.

## Method

`bench/hair_cost_bench.mojo` grows a six-foot male groom with
`groom_hair`. It times the growth once. It then times `add_strands`
once. That call builds the line geometry, does the first shading pass and
fills the vertex buffer. Then it times nine frames of each per-frame stage
and reports the median:

- `shade`: `HairStrands.shade` with one distant light, a camera and ambient
  light.
- The four stages of `shade`, in the same order. These are the density
  rebuild, the optical depths, the strand colors and the vertex upload.
  The vertex upload writes the positions and colors into the retained CPU
  buffer. The bench stops with an error when the four stages
  do not give the same vertex bytes as `shade`.
- `full step` and `full write`: one `HairSimulation.step` with every
  strand against a scalp collider, and `HairSimulation.write` back into
  the groom.
- `guides-only step` and `guides-only write`: the same work with
  `guides_only=True`. The step lays each follower from its moved guide.
- `guides-only frame`: that step, its write and the shading pass, timed
  together as one frame.

Each of the three simulations starts from the same grown pose. The bench
restores the points, normals and depths that a write changes before it
builds the next simulation.

The cost of one simulated follower is the full step less the guides-only
step, divided by the follower count. For the cost of one laid follower,
subtract the guides-only step of the 1500 x 0 groom from the guides-only
step of the default groom. Then divide by the follower count.

The allocation pass is separate from the timings. It loads the pinned Mojo
runtime hook `bench/navigation_allocations.c` and counts the requested
bytes and calls of one frame of each stage. The hook records the calling
thread only. The stages run their strand loops on pool threads, and the
hook does not count those threads. A reading of the source finds no
allocation in those loops. That is an inspection, not a measurement.

Run it as follows:

```sh
mkdir -p .cache/hair-cost
.venv/bin/mojo build -I . --Werror -o .cache/hair-cost/bench \
  bench/hair_cost_bench.mojo
.cache/hair-cost/bench
cc -std=c11 -Wall -Wextra -Werror -O2 -shared -fPIC \
  bench/navigation_allocations.c -ldl -o .cache/hair-cost/allocations.so
LD_PRELOAD="$PWD/.cache/hair-cost/allocations.so" \
  .cache/hair-cost/bench "$PWD/.cache/hair-cost/allocations.so"
```

Do not compare a timing from the hooked run with a native timing.

## Results on a shared cloud machine

Hardware: Intel Xeon 2.8 GHz 4-vCPU cloud VM, shared. Software: Linux,
Mojo 1.1.0 (`8189361e`). Other jobs shared the four logical cores. The load
average was 6 to 8 during the runs, so each parallel stage had less than
four cores. These results are local evidence for this machine only.

The bench ran five times. Each cell is the median of the five run medians,
in milliseconds. The range in brackets is the smallest and largest run
median. A cell without a range had every run median within 0.03 ms of it.

| Guides x followers | Strands | Points | Vertex bytes | Growth | Attach and first upload |
|---|---:|---:|---:|---:|---:|
| 250 x 2 | 708 | 4,713 | 192,240 | 231 [115, 278] | 2.1 [1.7, 8.5] |
| 1000 x 4 | 4,875 | 32,865 | 1,343,520 | 458 [324, 618] | 12.6 [11.8, 18.2] |
| 1500 x 6 (default) | 10,185 | 68,495 | 2,798,880 | 585 [500, 616] | 20.0 [15.2, 26.2] |
| 1500 x 0 (no followers) | 1,455 | 9,785 | 399,840 | 592 [478, 649] | 3.3 [2.8, 8.1] |

The shading pass and its four stages:

| Guides x followers | Shade | Density | Optical depth | Color | Vertex upload |
|---|---:|---:|---:|---:|---:|
| 250 x 2 | 2.1 [1.8, 2.8] | 0.17 | 1.1 [0.9, 1.5] | 1.1 [0.9, 1.5] | 0.09 |
| 1000 x 4 | 20.4 [15.4, 26.3] | 1.1 | 7.5 [6.7, 9.7] | 8.5 [7.2, 10.0] | 0.73 |
| 1500 x 6 (default) | 35.1 [29.9, 40.5] | 2.5 [2.3, 2.8] | 16.9 [9.9, 18.6] | 15.3 [13.6, 19.8] | 1.5 [1.4, 1.6] |
| 1500 x 0 (no followers) | 4.8 [4.1, 6.3] | 0.34 | 2.2 [1.7, 3.5] | 2.0 [1.7, 4.7] | 0.19 [0.17, 0.24] |

The simulation:

| Guides x followers | Full step | Full write | Guides-only step | Guides-only write | Guides-only frame |
|---|---:|---:|---:|---:|---:|
| 250 x 2 | 2.6 [1.4, 5.4] | 0.66 [0.47, 0.85] | 1.2 [1.0, 1.3] | 0.43 [0.30, 0.64] | 4.8 [4.1, 6.3] |
| 1000 x 4 | 20.4 [16.7, 21.3] | 4.5 [4.0, 6.4] | 6.2 [4.8, 8.0] | 4.3 [3.9, 4.8] | 32.2 [22.8, 34.2] |
| 1500 x 6 (default) | 48.4 [38.0, 60.0] | 11.7 [8.6, 18.5] | 11.4 [7.0, 13.4] | 12.1 [7.9, 12.9] | 64.0 [54.0, 95.2] |
| 1500 x 0 (no followers) | 5.2 [4.1, 5.8] | 1.2 [0.8, 1.6] | 5.7 [3.6, 10.6] | 1.3 [1.0, 1.8] | 12.7 [10.7, 17.5] |

The cost of one strand in the default groom:

| Strand | Cost in one step |
|---|---:|
| Simulated guide, in the guides-only step | 7.8 µs [4.8, 9.2] |
| Simulated follower, full step less guides-only step | 4.4 µs [3.1, 5.6] |
| Laid follower, guides-only step less the 1500 x 0 step | 0.65 µs |

The allocations of one frame on the calling thread were the same for
every groom size:

| Stage | Calls | Requested bytes |
|---|---:|---:|
| Density rebuild | 0 | 0 |
| Optical depth | 5 | 512 |
| Color | 5 | 1,600 |
| Vertex upload | 0 | 0 |
| Full step | 5 | 960 |
| Full write | 5 | 1,184 |
| Guides-only step | 10 | 1,376 |

Each parallel pass makes the same small number of allocations, whatever
the groom size. The vertex upload and the density rebuild allocate
nothing: they write into retained storage. Construction of a guides-only
`HairSimulation` for the default groom requests 9,222,384 bytes in eleven
calls. That is retained simulation state. It is not a per-frame cost.

## Results on a 12-core desktop

These are the earlier results of the first version of the bench. It
reported growth with the first upload, and it did not split the shading
pass or the simulation step from its write.

Hardware: AMD Ryzen 9 5900X (12 cores, 24 threads), 62 GiB, WSL 2 on
Windows 11, Mojo 1.1.0 (`8189361e`).

| Guides x followers | Strands | Points | Grow and upload | Shade | Step and write | Guides-only step and write | Guides-only frame |
|---|---:|---:|---:|---:|---:|---:|---:|
| 250 x 2 | 708 | 4,713 | 68 ms | 1.04 ms | 0.88 ms | 0.27 ms | 1.57 ms |
| 1000 x 4 | 4,875 | 32,865 | 216 ms | 2.53 ms | 2.05 ms | 1.45 ms | 4.38 ms |
| 1500 x 6 (default) | 10,185 | 68,495 | 306 ms | 4.48 ms | 3.53 ms | 2.31 ms | 7.29 ms |
| 1500 x 0 (no followers) | 1,455 | 9,785 | 291 ms | 1.43 ms | 1.05 ms | 1.02 ms | 2.74 ms |

Before shading ran in parallel, one thread shaded the default groom in 20.5
milliseconds. The step, the follower layout and the write also ran on one
thread at first. Then the default groom's step and write took 34.9
milliseconds. Its guides-only step and write took 13.3, and its
guides-only frame 19.1.

## What the measurements show

- **Followers are most of the simulation cost.** In the default groom,
  8,730 of the 10,185 strands are followers. A simulated follower costs
  about 4.4 µs a step on the shared machine. A laid follower costs about
  0.65 µs, about one seventh. The guides-only step of the default groom
  costs about a quarter of the full step on the shared machine.
- **The write is now as large as the guides-only step.** The write turns
  the frame of every point, guides and followers alike. So it costs the
  same in both modes, 12 ms on the shared machine.
- **Shading is mostly the optical depths and the colors.** The density
  rebuild and the vertex upload are serial stages, and together they cost
  about 4 ms for the default groom on the shared machine. They do not
  allocate.
- **No per-frame allocation grows with the groom.** The retained buffers
  hold the vertices, colors, optical depths and particles. Each parallel
  pass makes five allocations of at most 1,600 bytes in total on the
  calling thread.
- **The CPU vertex upload is small.** It costs about 1.5 ms for 2.8 MB of
  vertices. The upload to the device is a different cost. The
  [1080p frame report](hair-frame-729.md) measured more than 14 seconds
  in `GpuRenderer.draw` for one frame at 240 x 135. That draw flattens the
  strand triangles that the renderer builds from these vertices.
- **Strand drawing costs much more than all the hair stages.** On the
  shared machine, `bench/hair_strand_raster_bench.mojo 3` rendered the
  default groom at 1920 x 1080 in 3.1 to 5.2 seconds a frame. It used
  one, two and four workers. The same scene with the hair hidden rendered
  in 87 milliseconds. Thus the hair stages, about 64 ms, are less than 2.1
  percent of a CPU frame on this machine. On the 12-core desktop the
  ratio was 7 ms to 784 ms.

## Decisions

- **Keep guide-only interpolation.** `guides_only=True` lays each follower
  at its groomed offsets in its moved guide's frame, as TressFX lays follow
  strands. It removes about six sevenths of each follower's step cost. The
  guides move exactly as in the full step. Use the full step only when each
  follower must collide on its own.
- **Do not move the hair simulation or shading to the GPU now.** Strand
  rasterization costs about 50 times as much as all the hair stages on the
  shared machine. On the desktop it costs about 110 times as much.
  A GPU simulation could remove at most those tens of milliseconds. Strand rasterization and the device upload
  are the GPU work. That work continues under #298.
- **The next CPU step is the write.** A guides-only write could turn each
  follower's frame with its guide's rotation, as the layout does. This is
  a candidate, not a change in this report. Measure it before it changes.
- **Keep growth as a load-time cost.** It runs once per groom, and most of
  it is the guides.

These numbers describe two machines. They are not a hardware-independent
claim. They do not replace the named-hardware 1080p benchmark that #298
also asks for.
