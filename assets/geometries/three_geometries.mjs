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

// A square with two holes: one drawn counter-clockwise, and one drawn
// clockwise with a curve in it. ShapeGeometry turns the outline clockwise
// and both holes counter-clockwise.
function holed() {
	const shape = square( 0, 0, 4 );
	const a = new THREE.Path();
	a.moveTo( 0.5, 0.5 );
	a.lineTo( 1.5, 0.5 );
	a.lineTo( 1.5, 1.5 );
	a.lineTo( 0.5, 1.5 );
	a.lineTo( 0.5, 0.5 );
	const b = new THREE.Path();
	b.moveTo( 2.5, 2.5 );
	b.lineTo( 2.5, 3.5 );
	b.quadraticCurveTo( 3.6, 3.4, 3.4, 2.5 );
	b.lineTo( 2.5, 2.5 );
	shape.holes.push( a, b );
	return shape;
}

// An outline drawn clockwise, with a hole drawn clockwise too. The
// extrusion keeps both as they are, since its outline needs no turning.
function clockwise() {
	const shape = new THREE.Shape();
	shape.moveTo( 0, 0 );
	shape.lineTo( 0, 3 );
	shape.lineTo( 1, 4 );
	shape.lineTo( 3, 3 );
	shape.lineTo( 3, 0 );
	shape.lineTo( 0, 0 );
	const hole = new THREE.Path();
	hole.moveTo( 1, 1 );
	hole.lineTo( 1, 2 );
	hole.lineTo( 2, 2 );
	hole.lineTo( 2, 1 );
	hole.lineTo( 1, 1 );
	shape.holes.push( hole );
	return shape;
}

out.shape_holes = dump( new THREE.ShapeGeometry( holed(), 3 ) );
out.shape_clockwise = dump( new THREE.ShapeGeometry( clockwise(), 3 ) );
out.extruded_holes = dump( new THREE.ExtrudeGeometry( holed(), {
	depth: 1, steps: 2, curveSegments: 3, bevelEnabled: true,
	bevelThickness: 0.3, bevelSize: 0.2, bevelOffset: 0.05, bevelSegments: 2,
} ) );
// Points midway along each edge, and a spike out and straight back: the
// bevel moves each as three.js's collinear branch does.
function midpoints() {
	const shape = new THREE.Shape();
	shape.moveTo( 0, 0 );
	shape.lineTo( 2, 0 );
	shape.lineTo( 4, 0 );
	shape.lineTo( 4, 2 );
	shape.lineTo( 6, 2 );
	shape.lineTo( 4, 2 );
	shape.lineTo( 4, 4 );
	shape.lineTo( 2, 4 );
	shape.lineTo( 0, 4 );
	shape.lineTo( 0, 2 );
	shape.lineTo( 0, 0 );
	return shape;
}

out.extruded_midpoints = dump( new THREE.ExtrudeGeometry( midpoints(), {
	depth: 1, bevelEnabled: true, bevelThickness: 0.2, bevelSize: 0.1, bevelSegments: 1,
} ) );
out.extruded_clockwise = dump( new THREE.ExtrudeGeometry( clockwise(), { depth: 0.5, bevelEnabled: false } ) );

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
