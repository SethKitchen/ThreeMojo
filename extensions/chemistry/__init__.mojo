# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Process chemistry: the requirements that turn a material into a product.

The package is in layers. Each layer uses only the ones before it:

- `quantities`, `kinds` and `elements`: units, kinds, elements and
  formulas.
- `thermo`, `chemkin` and `catalog`: NASA polynomials, species and
  substances, a reader for CHEMKIN thermo files, and built-in data.
- `reaction`: reactions, their driving force, and the temperature and
  pressure where it crosses zero.
- `requirement`, `window` and `step`: the `Constraint` trait, the built-in
  requirements, operating windows and process steps.
- `coating` and `balance`: coating mechanics and energy balances.
- `processes`: worked processes built from the layers above.

See the wiki page Process chemistry.
"""
