# Construction kits

`extensions/building/kits.mojo` gives the materials, the layered constructions and the construction set of one way of building, ready for `assemble`. A kit is the part of a building that other buildings reuse. A scanned apartment, a procedural tower and an imported plan that use the masonry kit have the same brick walls and concrete floors. Their structural, bearing and thermal views then read the same materials.

![A building model fitted to a scan of a two-storey room, turning](out/scanned-buildings.png)

## Use a kit

```mojo
var kit = construction_kit(MASONRY_KIT)
var building = assemble(
    "row house", site, Length64(0, METER), plans,
    kit.materials.copy(), kit.constructions.copy(), kit.defaults,
    Length64(1e-6, METER),
)
```

`kit_kind("stone")` gives a kit from its name, as a manifest writes it. `kit.check()` refuses a kit that `assemble` would refuse. Each kit holds five constructions, in the order of a `ConstructionSet`: the outside wall, the partition, the ground slab, the floor and the roof. `kit.defaults` names them in that order.

## The kits

| Kit | Outside wall | Partition | Ground slab | Floor | Roof |
|---|---|---|---|---|---|
| `MASONRY_KIT` | 365 mm brick, 15 mm plaster | 115 mm brick | 200 mm concrete | 180 mm concrete | 200 mm wool, 100 mm timber |
| `STONE_KIT` | 1.2 m stone masonry | 600 mm stone masonry | 300 mm flagstones | 400 mm stone vault | 150 mm timber |
| `CONCRETE_KIT` | 120 mm wool, 200 mm concrete, 12.5 mm board | Stud: board, 75 mm wool, board | 250 mm concrete | 220 mm concrete | 200 mm wool, 220 mm concrete |
| `TIMBER_KIT` | 22 mm timber, 140 mm wool, 12.5 mm board | Stud: board, 75 mm wool, board | 150 mm concrete | 220 mm timber | 50 mm timber, 200 mm wool |

The layers run from the outside face to the inside face. The plaster is gypsum board, and the wool is mineral wool, from `extensions.building.material`.

- **Masonry** is a European apartment block or row house.
- **Stone** is a church, a castle or a Roman temple.
- **Concrete** is a recent block.
- **Timber** is a North American house.

## Stone masonry

`stone_masonry()` is the one material that the material library does not have. It is historic rubble and ashlar masonry in lime mortar.

| Property | Value |
|---|---|
| Density | 2200 kg/m³ |
| Elastic modulus | 3 GPa |
| Poisson's ratio | 0.2 |
| Compressive strength | 3 MPa |
| Conductivity | 1.7 W/(m K) |
| Specific heat | 1000 J/(kg K) |

The strength is that of the masonry, which is far below that of the stone itself.

## Limits

The values are typical values, not design values, as in [Building model](Building-model). A layered construction has no studs or joists, so a timber frame's strength is that of its sheathing. A project must use the values of its own products and codes.
