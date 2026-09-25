// Copyright (c) 2026 Seth Kitchen, PE
// SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
//
// Writes three_geometries.json: what three.js 0.180's geometries build for
// the calls that `tests/test_geometry_signatures.mojo` makes. Run it with
// three 0.180 installed beside it: `node three_geometries.mjs > three_geometries.json`.
//
// Each entry holds `position`, `normal` and `uv` as flat arrays, `index`,
// and `groups` as [start, count, materialIndex] triples.

import * as THREE from 'three';

function dump( geometry ) {
	const out = {
		position: Array.from( geometry.getAttribute( 'position' ).array ),
		normal: Array.from( geometry.getAttribute( 'normal' ).array ),
		uv: Array.from( geometry.getAttribute( 'uv' ).array ),
		index: geometry.index ? Array.from( geometry.index.array ) : [],
		groups: geometry.groups.map( ( g ) => [ g.start, g.count, g.materialIndex ] ),
	};
	return out;
}

const out = {};

// --- boxes -------------------------------------------------------------------

out.box_plain = dump( new THREE.BoxGeometry( 1, 2, 3 ) );
out.box_segments = dump( new THREE.BoxGeometry( 1, 2, 3, 2, 3, 4 ) );

// --- spheres -----------------------------------------------------------------

out.sphere_whole = dump( new THREE.SphereGeometry( 1.5, 8, 6 ) );
out.sphere_band = dump( new THREE.SphereGeometry( 1.5, 8, 6, 0.5, 4, 0.3, 2 ) );
out.sphere_cap = dump( new THREE.SphereGeometry( 1.5, 8, 6, 0, Math.PI * 2, 0, 1 ) );
out.sphere_bottom = dump( new THREE.SphereGeometry( 1.5, 8, 6, 1, 2, 2, Math.PI ) );

// --- shapes ------------------------------------------------------------------

function square( x, y, side ) {
	const shape = new THREE.Shape();
	shape.moveTo( x, y );
	shape.lineTo( x + side, y );
	shape.lineTo( x + side, y + side );
	shape.lineTo( x, y + side );
	shape.lineTo( x, y );
	return shape;
}

function triangle( x, y ) {
	const shape = new THREE.Shape();
	shape.moveTo( x, y );
	shape.lineTo( x + 2, y );
	shape.lineTo( x + 1, y + 1.5 );
	shape.lineTo( x, y );
	return shape;
}

const shapes = [ square( 0, 0, 1 ), triangle( 3, 0 ) ];
out.shapes_flat = dump( new THREE.ShapeGeometry( shapes, 4 ) );
out.shapes_extruded = dump( new THREE.ExtrudeGeometry( shapes, { depth: 0.5, bevelEnabled: false, steps: 2 } ) );

// A UV generator of its own: the top faces take x and y halved, the side
// walls take the first corner's x and z for all four.
const halving = {
	generateTopUV( geometry, vertices, a, b, c ) {
		return [
			new THREE.Vector2( vertices[ a * 3 ] / 2, vertices[ a * 3 + 1 ] / 2 ),
			new THREE.Vector2( vertices[ b * 3 ] / 2, vertices[ b * 3 + 1 ] / 2 ),
			new THREE.Vector2( vertices[ c * 3 ] / 2, vertices[ c * 3 + 1 ] / 2 ),
		];
	},
	generateSideWallUV( geometry, vertices, a, b, c, d ) {
		return [
			new THREE.Vector2( vertices[ a * 3 ], vertices[ a * 3 + 2 ] ),
			new THREE.Vector2( vertices[ b * 3 ], vertices[ b * 3 + 2 ] ),
			new THREE.Vector2( vertices[ c * 3 ], vertices[ c * 3 + 2 ] ),
			new THREE.Vector2( vertices[ d * 3 ], vertices[ d * 3 + 2 ] ),
		];
	},
};
out.extruded_uv_generator = dump( new THREE.ExtrudeGeometry( square( 0, 0, 1 ), {
	depth: 0.5, bevelEnabled: false, UVGenerator: halving,
} ) );

console.log( JSON.stringify( out ) );
