# Why scans become building models

A splat scan is a cloud of colored blobs on the surfaces of a place. It has no walls, no floors, no mass and no materials. ThreeMojo fits a canonical building model to it, so that every view that reads a building reads the scan too. This page says why, and why each step is as it is.

![A building model fitted to a scan of a two-storey room, turning](out/scanned-buildings.png)

## One model for every view

[Why buildings have one canonical model](Why-buildings-have-one-canonical-model) says why a procedural tower is a `Building`, not a mesh. A scan follows the same rule. A fitted model has storeys, walls and slabs of a construction kit. The bearing view weighs it, the thermal view heats it, the render view draws it, and the IFC writer exports it. None of them needs to know that it came from a scan.

The kits are the reusable part. A stone church and a stone castle share the stone kit. A scanned flat and a generated block share the masonry kit. A change to a kit reaches every building that uses it.

## A grid, not the splats

The splats are the wrong shape for physics and engineering. There are millions of them, they overlap, and some float in the air. An occupancy grid keeps what a splat says about space: something opaque is here. Faint splats add nothing, and a voxel needs enough opacity to be solid, so most floaters vanish. A grid also gives one answer to "is this point inside a surface" at any scale, which the levels and the collider both need.

## Floors from clear height

A scanner sees a slab from both sides: the ceiling below and the floor above. It never sees the inside of the slab. So the grid has an empty gap inside each slab, and the top of a ceiling looks like a floor. A floor face therefore needs clear height above it, at least `min_clear`. That rule also drops the top of the highest ceiling, which looks up at nothing. A table top's few faces cover too little of the plan.

## Rectangles, and notes

Each storey's plan is a rectangle, and each storey has one space. Furniture hides the floor, and a scanner rarely sees every wall. A rectangle is a plan that the scan supports, and the fill says how much of it the scan saw. Finding interior walls and non-rectangular plans is future work.

A fitted model carries notes, because its numbers carry the scan's uncertainty. A declared scale can be wrong by a factor, and a mass grows with the cube of it. The kit is assumed, not measured. The notes keep those facts next to the numbers, so that a reader does not take a scan's load for a survey's.

## Downloads, not commits

The scans are 15 MB to over 1 GB each. Git is the wrong store for them. The manifest pins each file's SHA-256 instead, as the CARLA assets do. Each person downloads the same bytes, and a changed file is refused. The manifest also holds each scan's credit and license, and the tool refuses a license that forbids changes or commercial use.
