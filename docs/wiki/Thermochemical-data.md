# Thermochemical data

Every computed bound in the library comes from thermochemical data. `extensions/chemistry/` reads that data in the three polynomial forms that publishers use. It fits polynomials to a table, writes CHEMKIN files, and carries each enthalpy's uncertainty into the results.

This page is a reference. For the rest of the library, see [Process chemistry](Process-chemistry).

## One fit, three forms

A `ThermoFit` holds the nine-coefficient NASA form of McBride, Zehe and Gordon (NASA TP-2002-211556), one set per temperature segment:

```text
cp/R = a1 T^-2 + a2 T^-1 + a3 + a4 T + a5 T^2 + a6 T^3 + a7 T^4
H/RT = -a1 T^-2 + a2 ln(T)/T + a3 + a4 T/2 + a5 T^2/3 + a6 T^3/4
       + a7 T^4/5 + b1/T
S/R  = -a1 T^-2/2 - a2/T + a3 ln T + a4 T + a5 T^2/2 + a6 T^3/3
       + a7 T^4/4 + b2
```

| Constructor | Form | Source |
|---|---|---|
| `nasa9(bounds, coefficients)` | Nine coefficients per segment | NASA TP-2002-211556, NASA CEA |
| `nasa7(bounds, coefficients)` | Seven, with a1 = a2 = 0 | NASA TM-4513, CHEMKIN files |
| `shomate(bounds, coefficients)` | A to G, with t = T / 1000 | The NIST Chemistry WebBook |

The Shomate enthalpy coefficient F is in kJ/mol and holds the formation enthalpy. The coefficient H is not needed and is not read. `shifted(dh, ds)` moves a fit by a constant enthalpy and entropy. The catalog makes diamond from graphite this way.

H is the enthalpy of formation at 298.15 K plus the heat taken up since. So `G = H - T S` of each species is on one scale, and the sum over a reaction is its change. S is at one bar.

## Read, write and fit

| Function | Does |
|---|---|
| `read_chemkin_thermo(text)` | Reads CHEMKIN records, with the fifth element pair of extended files in columns 74 to 78 |
| `write_chemkin_thermo(species)` | Writes CHEMKIN records, each coefficient as Fortran's E15.8 writes it |
| `read_cea_thermo(text)` | Reads NASA CEA `thermo.inp` records |
| `fit_nasa7(points, low, common, high)` | Fits two NASA-7 segments to a table |

The CEA reader leaves out ions, records with no temperature interval, and formulas with a count that is not whole. A record that is short or that cannot be read raises an error with its line number. The writer takes fits of one or two segments in the seven-coefficient form.

`fit_nasa7` takes a list of `ThermoPoint`: a temperature, the heat capacity, the enthalpy and the entropy, as JANAF tables give them. It fits the two heat capacity quartics together by least squares, equal at the common temperature. The enthalpy and entropy constants make H and S continuous there. Each segment needs five points at least.

## Uncertainty

`Species.set_uncertainty(u)` sets the standard uncertainty of a species' enthalpy, as CODATA gives it with the enthalpy of formation. `Substance.uncertainty_at(T)` reads it for the phase at a temperature.

`Reaction.delta_g_uncertainty(T)` adds the terms' uncertainties in quadrature, each times its coefficient. `Reaction.equilibrium_temperature_uncertainty(T, P)` divides that by the change's slope in temperature. The tests check it against moving the data by the uncertainty and solving again.

## The catalog

The catalog's 30 substances use NASA TM-4513 data, except Fe(a), which Cantera stores in the NASA-9 form of TP-2002-211556. All coefficients come unchanged from the conversion that Cantera 3.2 ships, and both sources are public domain. See [THIRD-PARTY-NOTICES.md](https://github.com/SethKitchen/ThreeMojo/blob/main/THIRD-PARTY-NOTICES.md).

## Checks

| Check | Result |
|---|---|
| NASA-9 O2 from a CEA record and NASA-7 O2 from TM-4513 | Agree to the 0.1 % the two fits differ by |
| NIST Shomate CO2 and NASA CO2 | Agree in H, S and G |
| A table sampled from the CO2 fit, refitted | Gives back the fit |
| A CHEMKIN file written from species, read back | Gives back the species |
| Methane read from a CHEMKIN record | Equal to the catalog's G to 1e-6 J/mol |

## Limits

A fit is valid only over its range, and a computation outside a range raises an error. The NASA data of a condensed phase is for a pure, stoichiometric compound, as the FeO of [Process maps](Process-maps#limits) shows.
