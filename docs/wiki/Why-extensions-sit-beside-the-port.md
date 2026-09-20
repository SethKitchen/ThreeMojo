# Why extensions sit beside the port

The core library ports three.js. An extension adds content that three.js does not have: a femur, a tibia, later a tree, a building, water.

Keeping them apart protects both jobs. A port can follow three.js names and tests without growing a humanoid. An extension can use osteometry without pretending three.js shipped a femur.

`extensions/` is that split. The first path is `humanoid/skeleton/leg/`. A later bone lands next to the femur, tibia, fibula and patella. The knee tissues sit in `leg/knee/`. The named muscles sit in `leg/muscles/`. Grass, terrain and water each get their own folder under `extensions/`.

The house rules do not change. Units, kinds, coverage and documentation apply to an extension the same way they apply to a camera. The README list for extensions is separate from the three.js checklist, so a ticked femur is not a claim that three.js has one.
