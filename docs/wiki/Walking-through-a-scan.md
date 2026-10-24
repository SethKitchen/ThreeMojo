# Walking through a scan

`extensions/scan/walk.mojo` puts a person in a scanned building, as a game does. The person is a capsule in a physics world that holds the scan as a static collider. A tick of the world is a tick of the game loop. A camera at the walker's eye gives the first-person view.

![A first-person walk through a scanned furnished apartment, drawn on every core](out/scan-walk.png)

The picture comes from `examples/scan_walk.mojo`. The scan is "Studio 11" by milanoski, under CC BY 4.0. The walker crosses the living room, with a rug, an armchair and a television, and turns round at a wall.

## The loop

```mojo
var scan = open_scan("studio-11")
var filled = fill_grid(scan)
var walker = Walker(
    filled.grid,
    filled.floor,
    Vec3d(filled.region.low.x, filled.region.low.y, 0),
    Vec3d(filled.region.high.x, filled.region.high.y, 0),
    default_walk_options(),
    PhysicsMaterial.default(),
)
for _ in range(frames):
    walker.step(Duration(Float32(1.0 / 60), SECOND))
    var eye = walker.eye()          # meters east, north and up
    var ahead = walker.forward()    # a unit vector in the plan
    # Draw the scene from the eye.
```

`open_scan` and `fill_grid` are in `tools/_scan_demo.mojo`, which the examples share. They read a scan, clean it, and fill its [occupancy grid](Scanned-buildings#the-occupancy-grid) with the voxel grown until it fits. A caller with its own grid passes it to `Walker`.

A tick does three things.

1. The walker turns toward its goal, at most `turn` radians a second. It stops and turns where its way is more than 0.6 radians from the goal.
2. It sets its horizontal velocity to `speed` along the way it faces.
3. The world steps. Gravity, the floor, the walls and the furniture of the scan decide the rest.

The capsule cannot turn over: its inverse inertia is locked, as `locked_inverse_inertia` gives it. The walker turns round when it comes within 0.3 m of an end.

## The ends of the walk

The goal is one of two points of the floor. `walk_ends` finds them from the occupancy grid.

1. A plan point is clear when the floor is under it. No solid voxel is within the walker's radius, from `step` to `clearance` over the floor.
2. The clear points are tried on a lattice, `spacing` apart.
3. The first end is the clear point nearest the middle of the clear points.
4. The second is the clear point farthest from the first with a clear line between them. `is_walkable` checks the line every 0.1 m.
5. The first end then moves to the point farthest from the second in the same way.

A scan with fewer than two clear points has no walk, and `walk_ends` refuses it.

`is_clear` tests one point, and `is_walkable` tests one line. Each checks its options first. They refuse options that `WalkOptions.check` refuses.

## Options

`WalkOptions` holds sizes and paces as typed quantities. `default_walk_options()` gives an adult.

| Option | Default | Meaning |
|---|---|---|
| `radius` | 0.3 m | The capsule's radius |
| `height` | 1.8 m | Feet to crown |
| `eye` | 0.75 m | The eye over the capsule's center, inside the capsule |
| `speed` | 1.4 m/s | The walking pace |
| `turn` | 2.5 rad/s | The most the walker turns in a second |
| `step` | 0.25 m | The lowest solid voxel that stops the walker. A lower one is a step |
| `clearance` | 1.7 m | The height over the floor that must be clear |
| `spacing` | 0.5 m | The distance between the points tried for the ends |
| `mass` | 80 kg | The walker's mass |

## The speed

The numbers come from a Linux machine with 24 threads and an NVIDIA TITAN RTX. The scan holds 4,759,156 splats after the cleaning. Its tree for levels of detail holds 6,301,303.

| Draw | Size | Physics | Draw | The loop |
|---|---|---|---|---|
| `scan_walk.mojo`, on every core | 480 by 270 | 0.7 ms | 24.3 ms | 40 frames a second |
| `scan_walk_gpu.mojo`, on the GPU | 1280 by 720 | 0.7 ms | 13.2 ms | 72 frames a second |

The physics of the whole scan, as one static mesh of merged faces, costs about a millisecond a tick. The draw is the rest. See [GPU splats](GPU-splats) for where its time goes.

## Limits

- The walker follows two points and no more. It is a test of the scan's collider and of the frame rate, not a path finder.
- A scan holds surfaces, and a collider made of its voxels is a shell one voxel thick. A walker that walks at 1.4 m/s does not pass through it. A fast body can: see [Scanned buildings](Scanned-buildings#collide-with-a-scan).
- A stair is a sequence of steps. A step higher than `step` stops the walker.
- A scan has holes where the camera did not see. A hole in a wall is a door to the walker.
