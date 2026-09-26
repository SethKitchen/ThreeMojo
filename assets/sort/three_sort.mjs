// Copyright (c) 2026 Seth Kitchen, PE
// SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
//
// Writes three.json: the order three.js 0.180's `radixSort` puts items in,
// for `tests/test_sort_utils.mojo`. Run it with three 0.180 installed beside
// it: `node three_sort.mjs > three.json`.
//
// Six hundred items take 32-bit keys from `MathUtils.seededRandom` from 11,
// a third of them repeated so that the order of equal keys shows. `forward`
// and `reversed` are the items' order after each sort.

import * as THREE from 'three';
import { radixSort } from 'three/examples/jsm/utils/SortUtils.js';

THREE.MathUtils.seededRandom( 11 );
const keys = [];
for ( let i = 0; i < 600; i ++ ) {

	keys.push( i % 3 === 2 ? keys[ i - 1 ] : Math.floor( THREE.MathUtils.seededRandom() * 4294967296 ) >>> 0 );

}

const sorted = ( reversed ) => {

	const items = keys.map( ( key, id ) => ( { key, id } ) );
	radixSort( items, { get: ( el ) => el.key, reversed } );
	return items.map( ( el ) => el.id );

};

console.log( JSON.stringify( { keys, forward: sorted( false ), reversed: sorted( true ) } ) );
