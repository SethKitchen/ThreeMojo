// Copyright (c) 2026 Seth Kitchen, PE
// SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
//
// Writes holes.json: the triangles three.js 0.180's earcut gives polygons
// with holes, for `tests/test_earcut.mojo`. Run it with three 0.180
// installed beside it: `node three_holes.mjs > holes.json`.
//
// - `cases`: earcut's `data` and `holeIndices`, and its triangles.
// - `shapes`: `ShapeUtils.triangulateShape`'s outline and holes, each
//   closed by a repeat of its first point, and its triangles.

import * as THREE from 'three';
import { Earcut } from 'three/src/extras/Earcut.js';

const ring = ( cx, cy, r, n, turn = 0 ) => {

	const out = [];
	for ( let i = 0; i < n; i ++ ) {

		const a = turn + i / n * Math.PI * 2;
		out.push( + ( cx + r * Math.cos( a ) ).toFixed( 6 ), + ( cy + r * Math.sin( a ) ).toFixed( 6 ) );

	}

	return out;

};

const cases = [];
const add = ( name, rings ) => {

	const data = [];
	const holeIndices = [];
	rings.forEach( ( r, i ) => {

		if ( i > 0 ) holeIndices.push( data.length / 2 );
		data.push( ...r );

	} );
	cases.push( { name, data, holeIndices, triangles: Earcut.triangulate( data, holeIndices ) } );

};

const square = [ 0, 0, 10, 0, 10, 10, 0, 10 ];
add( 'one hole', [ square, [ 3, 3, 3, 7, 7, 7, 7, 3 ] ] );
add( 'two holes', [ square, [ 6, 2, 6, 4, 8, 4, 8, 2 ], [ 1, 5, 1, 8, 4, 8 ] ] );
add( 'same leftmost x', [ square, [ 2, 2, 4, 3, 2, 4 ], [ 2, 6, 5, 8, 2, 8 ] ] );
add( 'a point', [ square, [ 5, 5 ] ] );
add( 'touching', [ square, [ 0, 5, 3, 4, 3, 6 ] ] );
add( 'on the ray', [ [ 0, 0, 10, 0, 10, 10, 5, 5, 0, 10 ], [ 7, 4, 8, 4, 8, 6 ] ] );
add( 'many', [ ring( 0, 0, 20, 90 ), ring( - 8, 0, 4, 12 ), ring( 8, 1, 5, 20, 0.3 ), ring( 0, 10, 3, 7 ) ] );
add( 'counter-clockwise hole', [ square, [ 3, 3, 7, 3, 7, 7, 3, 7 ] ] );
add( 'same leftmost point', [ square, [ 2, 5, 4, 4, 4, 6 ], [ 2, 5, 4, 7, 3, 8 ] ] );
add( 'on an outline corner', [ [ 0, 0, 10, 0, 10, 10, 0, 10, 0, 5 ], [ 0, 5, 3, 4, 3, 6 ] ] );
add( 'on the first corner', [ [ 0, 5, 0, 0, 10, 0, 10, 10, 0, 10 ], [ 0, 5, 3, 4, 3, 6 ] ] );
add( 'on the last corner', [ [ 0, 0, 10, 0, 10, 10, 0, 10, 0, 5 ].reverse(), [ 0, 5, 3, 4, 3, 6 ] ] );
add( 'on an edge, the other way', [ [ 0, 10, 10, 10, 10, 0, 0, 0 ], [ 0, 5, 3, 4, 3, 6 ] ] );
add( 'outside', [ square, [ - 5, 5, - 4, 4, - 4, 6 ] ] );
add( 'level with an edge', [ [ 0, 0, 10, 0, 10, 10, 0, 10, 0, 6, 1, 6, 1, 4, 0, 4 ], [ 3, 6, 5, 5, 5, 7 ] ] );
add( 'in a U', [ [ 0, 0, 10, 0, 10, 10, 7, 10, 7, 3, 3, 3, 3, 10, 0, 10 ], [ 8, 5, 9, 5, 9, 6 ], [ 1, 5, 2, 5, 2, 6 ] ] );
add( 'touching the bottom', [ [ 0, 0, 12, 0, 12, 12, 0, 12 ], [ 3, 0, 4, 1, 3, 1 ], [ 5, 6, 6, 5, 6, 6 ] ] );
add( 'in a U, the other way', [ [ 0, 10, 3, 10, 3, 3, 7, 3, 7, 10, 10, 10, 10, 0, 0, 0 ], [ 1, 5, 2, 5, 2, 6 ], [ 8, 5, 9, 5, 9, 6 ] ] );

const shapes = [];
const vectors = ( flat ) => {

	const out = [];
	for ( let i = 0; i < flat.length; i += 2 ) out.push( new THREE.Vector2( flat[ i ], flat[ i + 1 ] ) );
	return out;

};

const closed = ( flat ) => [ ...flat, flat[ 0 ], flat[ 1 ] ];
const shape = ( name, contour, holes ) => {

	const faces = THREE.ShapeUtils.triangulateShape( vectors( contour ), holes.map( vectors ) );
	shapes.push( { name, contour, holes, triangles: faces.flat() } );

};

shape( 'closed with a closed hole', closed( square ), [ closed( [ 3, 3, 3, 7, 7, 7, 7, 3 ] ) ] );
shape( 'open with two holes', square, [ [ 6, 2, 6, 4, 8, 4, 8, 2 ], closed( [ 1, 5, 1, 8, 4, 8 ] ) ] );

console.log( JSON.stringify( { cases, shapes } ) );
