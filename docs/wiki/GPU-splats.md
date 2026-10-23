# GPU splats

`render/gpu_splat_tiles.mojo` and `render/gpu_splat_lod.mojo` draw Gaussian splats on a GPU, a tile of the screen at a time. A scan of a building draws at 1920 by 1080 in 21 milliseconds on the GPU, where 24 CPU threads take 43. The scan stays on the device, and a frame sends only the places of the splats that the host's walk of the [level-of-detail tree](Splat-level-of-detail) selected.

![A scanned brick church with a lead roof, drawn on a GPU](out/seem-church-gpu.png)

The picture is the Seem Kirke scan of [Cleaning and orienting scans](Cleaning-and-orienting-scans), drawn by `examples/scan_view_gpu.mojo`. `examples/scan_walk_gpu.mojo` draws a walk through a scan in the same way. The module needs MAX: `uv pip install "mojo==1.1.0" "max==26.6.0"`.

## Why a tile

`render.gpu.GpuSplats` gives each pixel a thread, and every thread walks every splat. A scan of a building has hundreds of thousands of splats on the screen, and a pixel is reached by a few hundred of them. A tile of 16 by 16 pixels takes one thread block. The block reads the tile's splats in batches of 256 into shared memory, one splat to each thread. Then every thread blends the batch into its pixel in draw order.

`render.splat_tiles.bin_splats` finds each tile's splats on the host. It is a counting sort in runs. The fill of `rasterize_splats` sorts by bands of rows in the same way. So the lists are the same for any count of workers. A tile's list is in draw order, so a pixel takes the blends in the order that the host takes them.

The opacity is `splat_alpha`, and the blend is source over with straight alpha, each sum of products one fused multiply-add. The picture is the host's to within a level of the 255 that a channel holds.

## The pipeline

`GpuSplatScene` keeps the scan's splats on the device: the tree's own and its merged ones, with their covariances, colors and spherical harmonics. `GpuSplatScene.draw` does one frame in eight launches.

| Stage | What it does |
|---|---|
| Select | On the host: `select_splats` walks the tree and gives the places of the splats to draw. They go to the device, 4 bytes each. |
| Project | A thread to each splat shades it with its harmonics, projects it as `project_splat` does, and finds its depth bin and its box of tiles. |
| Sort by depth | A counting sort of the 4,096 depth bins in 1,024 runs. Each run counts its splats in each bin, a block scan makes the starts, and each run places its splats. The draw order is the host's. |
| Sort into tiles | The same counting sort of the sorted splats into the tiles that they reach. The host reads one number, the length of the lists, so that the list buffer is big enough. |
| Fill | `splat_tile_kernel`, one block to each tile. |
| Back | The picture comes back as four bytes a pixel. |

```mojo
var lod = build_splat_lod(splats, node)       # once, on the host
var device = GpuSplatScene(lod)               # once: the scan goes to the device
var picture = List[UInt8]()
device.draw_bytes(scene, lod, camera, 1920, 1080, Color(7, 8, 15), picture, workers)
```

`draw` returns a `Framebuffer`, and `draw_bytes` fills a list that the caller keeps from frame to frame. The work buffers stay between frames and grow when a frame needs more.

## The speed

The numbers come from a Linux machine with 24 threads and an NVIDIA TITAN RTX. Each is the mean of 24 frames or more, with the camera turning round the scan.

| Scan | Size | Splats drawn | CPU, 24 threads | GPU |
|---|---|---|---|---|
| Seem Kirke | 1920 by 1080 | 850,000 | 43 ms, 23 frames a second | 17 ms, 58 frames a second |
| Seem Kirke | 1280 by 720 | 745,000 | 34 ms, 29 frames a second | 14 ms, 72 frames a second |
| Studio 11, inside | 1280 by 720 | 500,000 | | 14 ms, 72 frames a second, with the physics |

The stages of a frame inside Studio 11, at 1280 by 720, are these, in milliseconds. The host walks the tree in 1.8 and prepares the places in 1.1.

| Upload and clear | Project | Sort by depth | Tile counts | Tile placement | Fill | Back |
|---|---|---|---|---|---|---|
| 0.7 | 0.3 | 1.0 | 2.3 | 2.0 | 3.1 | 0.9 |

The fill alone takes 3.7 ms at 1080p for 850,000 splats, where the CPU takes 29. The rest is the sort. Splats that are near the camera cover many pixels, so an interior takes more fill than an exterior of the same count.

A game picks its quality with `pixels`, the limit of `select_splats`: how many pixels a node's sphere can cover to draw as its merged splat. At 2.5, the default, Seem Kirke draws 850,000 splats at 1080p. At 8 it draws 428,000, within a level or two of the picture at 2.5, and the CPU takes 31 ms where it took 43.

## Tests

`tests/test_splat_tiles_gpu.mojo` draws random splats on the device and on the host. The target is not a whole number of tiles, and one tile holds more splats than a batch. `tests/test_splat_lod_gpu.mojo` draws a scan with harmonics of each degree from near and from far. A channel differs by at most three levels, and under one percent of the channels differ at all. `tests/test_splat_tiles.mojo` holds the tile lists to a brute-force walk and to every count of workers, on the host.

## Limits

- The fill has no depth buffer. It draws into a cleared, opaque target. A scene with meshes in front of the splats draws on the host with `draw_splat_lod`, where the target's depth hides the splats behind it.
- The host walks the tree. It takes 3 to 5 ms a frame, on every thread, and the device waits for it. Moving it to the device would remove the host from the loop.
- The device sorts by 4,096 bins of depth, as the host does, so two splats in one bin keep their order in the tree. Two splats that are close together and cross each other can blend in the wrong order, as they do on the host.
- The tile sort's table holds 16 million counts, a count for each run and each tile. A picture of 1080p has 2,048 runs, and a picture with more tiles has fewer runs and a slower sort.
- A splat near the camera can reach many tiles. A close-up of a wall costs an entry in the tile lists for each tile of each splat.
- `examples/scan_view_gpu.mojo` and `examples/scan_walk_gpu.mojo` need MAX and a GPU. A name that ends in `_gpu` puts an example in the Makefile's GPU entry points.
