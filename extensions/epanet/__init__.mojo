# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""A port of the EPANET 2.3 engine for pipe networks.

`EpanetProject` reads an EPANET input file. It runs the hydraulics of the
network over the time of the simulation, and then the water quality. The
modules follow the C modules of OWA EPANET 2.3.6, which has the MIT
license. See THIRD-PARTY-NOTICES.md and the wiki page Pipe networks.
"""
