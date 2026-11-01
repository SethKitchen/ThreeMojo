# Materials and coatings

Engineering requirements need material data with a source, and coatings need their mechanics. `extensions/chemistry/materials.mojo` gives expansion curves, melting points and eutectics. `coating.mojo` gives the stress in a coating, and the conditions where it peels, buckles or cracks.

This page is a reference. For the rest of the library, see [Process chemistry](Process-chemistry).

## Materials data

An `ExpansionCurve` is a linear expansion coefficient at a list of temperatures, linear between them. `strain(start, end)` integrates it exactly, and `mean(start, end)` divides the strain by the temperature change. A mean coefficient is wrong where the coefficient changes much over a range, as diamond's does.

`melting_point(element)` gives an element's melting point at one atmosphere. The table holds W, Ta, Mo, Ti, Fe, Co, Ni, Pt, Cu, Au, Ag, Al, Mg, Zn, Bi and Si. The values are from the CRC Handbook. They agree with the phase transitions in the NASA data to 5 K or less.

`eutectic_temperature(a, b)` gives the lowest melting point of a binary system, in either order:

| System | Eutectic | Source |
|---|---|---|
| Fe-Ti | 1085 degC | Murray (1981) |
| Fe-C | 1147 degC, with cementite | The standard Fe-C diagram |
| Al-Si | 577 degC | The standard Al-Si diagram |

A stated bound in a step, such as the retort below the Fe-Ti eutectic, can then read its value from this table.

## Coating stress

A coating deposited hot and then cooled holds a residual stress. The thick substrate sets the strain, so the coating is in equal biaxial stress. A positive stress is compression in the coating:

```text
sigma = E_c / (1 - nu_c) * (alpha_s - alpha_c) * (T_dep - T_service)
```

`mismatch_stress` uses an `ElasticLayer` for each material: a modulus, a Poisson ratio and a mean expansion coefficient. `curve_mismatch_stress` uses an expansion curve for each material instead of the means.

## Peeling, buckling and cracking

| Function | Gives | Source |
|---|---|---|
| `delamination_thickness` | The thickest coating that does not peel from an edge: `h = 2 E Gamma / ((1 - nu^2) sigma^2)` | Hutchinson and Suo (1992) |
| `straight_buckle_stress` | The stress at which a delaminated strip buckles: `(pi^2 / 12) E / (1 - nu^2) (h / b)^2` | Hutchinson and Suo (1992) |
| `circular_buckle_stress` | The same for a disc, with 1.2235 for `pi^2 / 12` | Hutchinson and Suo (1992) |
| `thermal_shock_difference` | The sudden temperature change that cracks a brittle surface: `sigma_f (1 - nu) / (E alpha)` | Kingery's first parameter |

Here `b` is the half-width or the radius of the delamination. The interface fracture energy `Gamma` depends on the surface preparation. Measure it on the real surface, for example with an indentation or a scratch test.

## Measure the stress

`stoney_stress` gives the stress that a measured substrate curvature shows (Stoney, 1909):

```text
sigma = E_s h_s^2 kappa / (6 (1 - nu_s) h_f)
```

`stack_curvature` is the inverse for a stack of thin layers: each layer adds its stress times its thickness. The tests check that the two invert each other.

## The diamond tool

`processes.diamond` holds typical properties in `CVD_DIAMOND` and `CEMENTED_CARBIDE`. Diamond deposited at 850 degC on carbide with 6 % cobalt cools to about 2.5 GPa of compression. At a fracture energy of 30 J/m², the limit is about 11 micrometers.

## Limits

The coating is thin and the substrate is thick, so the substrate does not bend. The layers are elastic and isotropic. The table values are typical. Measure the values of the real material for a design.
