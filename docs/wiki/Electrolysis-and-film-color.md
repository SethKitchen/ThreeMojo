# Electrolysis and film color

`extensions/chemistry/electrochemistry.mojo` gives the voltage, the charge and the energy of an electrolysis cell. `optics.mojo` gives the color of a thin oxide film on a metal, such as anodized titanium or tempered steel.

This page is a reference. For the rest of the library, see [Process chemistry](Process-chemistry).

## Cell voltages

A reaction that moves n electrons per mole has the reversible voltage `E = -dG / (n F)`. The Faraday constant `FARADAY` is 96485.33212331001 C/mol.

| Function | Gives |
|---|---|
| `reversible_voltage(reaction, n, T, P)` | `-dG / (n F)`. Positive for a reaction that runs by itself: a battery |
| `decomposition_voltage(reaction, n, T, P)` | `dG / (n F)`, the least voltage that drives an electrolysis |
| `thermoneutral_voltage(reaction, n, T, P)` | `dH / (n F)`, where the cell neither heats nor cools |

The reaction's mole fractions and activities enter `dG`, so these functions are the Nernst equation. `Voltage64` and `Current64` are separate types, because `units.quantity.Quantity` has no electric dimension.

`CellVoltage` adds the anode and cathode overpotentials and the ohmic drop to the reversible voltage. Its `total()` is the voltage a cell runs at.

## Charge and energy

Faraday's law gives the mass that a current deposits or frees: `m = I t M eta / (n F)`, with `eta` the current efficiency. `faraday_mass` gives the mass, and `faraday_time` gives the time to make a mass.

`specific_energy(voltage, molar_mass, n, efficiency)` turns a cell voltage into energy per kilogram of product. `KILOWATT_HOUR_PER_KILOGRAM` is its unit.

## Checks

| Quantity | Computed | Reference |
|---|---|---|
| Water at 25 degC | 1.229 V, thermoneutral 1.481 V | 1.229 V and 1.481 V |
| Alumina with a carbon anode at 960 degC | 1.19 V | 1.18 to 1.20 V |
| MgCl2 at 700 degC | 2.52 V | About 2.5 V |
| Aluminum at 4.2 V and 95 % efficiency | 13.2 kWh/kg | 13 to 15 kWh/kg in smelters |

## Film color

![Twenty-five swatches of anodized titanium from 0 to 120 V: bronze, purple, blue, gold, magenta and green](out/anodizing.png)

Light reflects from both faces of a thin oxide and interferes. `film_reflectance` sums the two reflections of one transparent film on an absorbing substrate at normal incidence (Born and Wolf, 1.6):

```text
r   = (r01 + r12 e^(2 i b)) / (1 + r01 r12 e^(2 i b))
r01 = (1 - n1) / (1 + n1),  r12 = (n1 - N2) / (n1 + N2)
b   = 2 pi n1 t / wavelength
```

Here `n1` is the film's index, `t` its thickness and `N2 = n + i k` the substrate's `ComplexIndex`.

`film_color` weights the reflectance by the CIE 1931 color matching functions from 380 to 780 nm, under an equal-energy light. It uses the analytic fit of Wyman, Sloan and Shirley (2013). The result is X, Y and Z, with Y = 1 for a perfect mirror. `linear_srgb` turns them into linear sRGB with a D65 white.

`anodic_thickness(volts, growth)` is the thickness of a film that grows a fixed amount per volt. The growth depends on the metal and the electrolyte, so measure it on your bath.

`examples/anodizing.mojo` draws the swatches. Its constants are assumed values, not measurements. Titanium is 2.6 + 3.5i, the film is 2.3 at every wavelength, and it grows 2 nm per volt. The colors follow the known sequence of anodized titanium.

## Limits

The cell functions give the thermodynamic part of a cell. The overpotentials and the resistance come from the cell's measurements. The film model takes one film of one index with flat faces. A real anodic film has an index that changes with wavelength, and some light scatters.
