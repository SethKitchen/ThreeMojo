// Copyright (c) 2026 Seth Kitchen, PE
// SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
//
// Writes pdb.json: what three.js 0.180's `PDBLoader.parse` makes of
// fixture.pdb, for `tests/test_pdb.mojo`. Run it with three 0.180 installed
// beside it: `node three_pdb.mjs > pdb.json`.

import { readFileSync } from 'fs';
import { PDBLoader } from 'three/examples/jsm/loaders/PDBLoader.js';

const text = readFileSync( new URL( './fixture.pdb', import.meta.url ), 'utf8' );
const pdb = new PDBLoader().parse( text );
console.log( JSON.stringify( {
	atoms: Array.from( pdb.geometryAtoms.getAttribute( 'position' ).array ),
	colors: Array.from( pdb.geometryAtoms.getAttribute( 'color' ).array ),
	bonds: Array.from( pdb.geometryBonds.getAttribute( 'position' ).array ),
	json: pdb.json.atoms,
} ) );
