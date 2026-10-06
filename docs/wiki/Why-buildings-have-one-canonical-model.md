# Why buildings have one canonical model

A procedural building must serve two users. An engineer analyzes its structure and its energy. A game draws it and lets a player walk through it. Both use one canonical model, and each derives its own form from that model. A derived form never feeds back into the model.

## The problem with one form per use

A game mesh is the wrong source for analysis. It has no materials with physical properties, no layers in its walls and no record of which room is on which side of a wall. A structural model is the wrong source for rendering: it is a set of lines and plates. An energy model is zones and surfaces with no visible thickness.

If each tool keeps its own form, the forms drift apart. A window moved in the game mesh stays where it was in the energy model. The code that makes rooms, walls and windows is also written three times.

## The canonical model

The [building model](Building-model) holds what every view needs, once:

- The [cell complex](Building-topology): each room is a cell, and two rooms that share a wall share one face.
- Elements on the faces of the complex: walls, slabs and roofs, each with a layered construction.
- Frame members on axes, with sections and materials.
- Openings in walls, with glazing for windows.
- Materials with physical properties beside a look.

The cell complex carries the adjacency. A thermal view reads which zone is on each side of a wall. A structural view reads which slab a beam carries. A render view reads which face of a wall is outside. None of them stores that adjacency again.

## Views

Each view reads the model and builds its own form:

| View | Form | What it drops |
|---|---|---|
| Render | Meshes per storey and look, with an element id per vertex | Physical properties, inner layers, structural and thermal data |
| Structural | Nodes, frame members, shells, supports and loads | Walls, openings, looks |
| Thermal | Zones, surfaces, windows and gains | Frame members, looks |
| IFC | An exchange file | Nothing that it can read back. The fingerprint survives the round trip. |

Each view records what it drops. The render view stores the model's fingerprint on its node, so a game can tell whether a baked mesh is current. The same approach keeps the [humanoid](Humanoid-fidelity) apart: a rendered body is not a validated engineering model.

## Generators write the model

A generator writes the canonical model and never a mesh. A procedural tower or a floor plan generator writes storeys, spaces and openings. The render view then draws them, and the structural and thermal views analyze the same building. A change to a generator reaches every view at once.

## What this does not claim

A checked analysis needs more than a shared model. Loads, material properties and boundary conditions need engineering judgment. The library materials hold typical values, not design values. The views state their methods and their limits on their own pages.
