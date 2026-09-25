// Copyright (c) 2026 Seth Kitchen, PE
// SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
//
// Writes curves.json: three.js 0.180's `toJSON` of plane curves, curves in
// space, a path of them and a shape, and the points each gives, for
// `tests/test_curve_json.mojo`. Run it with three 0.180 installed beside
// it: `node three_curves.mjs > curves.json`.
//
// Each entry holds `json`, the curve's `toJSON()`, and `points`, its
// `getPoints( 8 )` (a shape's `extractPoints( 6 )` outline and holes).

import * as THREE from 'three';

const flat = ( points ) => points.flatMap( ( p ) => p.toArray() );

const plane = [
	new THREE.LineCurve( new THREE.Vector2( 0, 0 ), new THREE.Vector2( 2, 1 ) ),
	new THREE.QuadraticBezierCurve( new THREE.Vector2( 0, 0 ), new THREE.Vector2( 1, 2 ), new THREE.Vector2( 2, 0 ) ),
	new THREE.CubicBezierCurve( new THREE.Vector2( 0, 0 ), new THREE.Vector2( 0, 2 ), new THREE.Vector2( 2, 2 ), new THREE.Vector2( 2, 0 ) ),
	new THREE.SplineCurve( [ new THREE.Vector2( 0, 0 ), new THREE.Vector2( 1, 1 ), new THREE.Vector2( 2, 0 ), new THREE.Vector2( 3, 1 ) ] ),
	new THREE.EllipseCurve( 1, 2, 3, 1.5, 0.25, 2.5, true, 0.4 ),
	new THREE.ArcCurve( 0, 0, 2, 0, Math.PI, false ),
];

const space = [
	new THREE.LineCurve3( new THREE.Vector3( 0, 0, 0 ), new THREE.Vector3( 1, 2, 3 ) ),
	new THREE.QuadraticBezierCurve3( new THREE.Vector3( 0, 0, 0 ), new THREE.Vector3( 1, 2, 0 ), new THREE.Vector3( 2, 0, 1 ) ),
	new THREE.CubicBezierCurve3( new THREE.Vector3( 0, 0, 0 ), new THREE.Vector3( 0, 2, 1 ), new THREE.Vector3( 2, 2, 0 ), new THREE.Vector3( 2, 0, 1 ) ),
	new THREE.CatmullRomCurve3( [ new THREE.Vector3( 0, 0, 0 ), new THREE.Vector3( 1, 1, 0 ), new THREE.Vector3( 2, 0, 1 ), new THREE.Vector3( 3, 1, 1 ) ] ),
	new THREE.CatmullRomCurve3( [ new THREE.Vector3( 0, 0, 0 ), new THREE.Vector3( 1, 1, 0 ), new THREE.Vector3( 2, 0, 1 ) ], true, 'chordal' ),
	new THREE.CatmullRomCurve3( [ new THREE.Vector3( 0, 0, 0 ), new THREE.Vector3( 1, 1, 0 ), new THREE.Vector3( 2, 0, 1 ) ], false, 'catmullrom', 0.3 ),
];

const path3 = new THREE.CurvePath();
path3.add( space[ 0 ] );
path3.add( space[ 1 ] );

const shape = new THREE.Shape();
shape.moveTo( 0, 0 );
shape.lineTo( 4, 0 );
shape.quadraticCurveTo( 5, 2, 4, 4 );
shape.bezierCurveTo( 3, 5, 1, 5, 0, 4 );
shape.splineThru( [ new THREE.Vector2( - 0.5, 3 ), new THREE.Vector2( 0, 2 ) ] );
shape.lineTo( 0, 0 );
const hole = new THREE.Path();
hole.absarc( 2, 2, 0.5, 0, Math.PI * 2, false );
shape.holes.push( hole );
const extracted = shape.extractPoints( 6 );

const out = {
	plane: plane.map( ( c ) => ( { json: c.toJSON(), points: flat( c.getPoints( 8 ) ) } ) ),
	space: space.map( ( c ) => ( { json: c.toJSON(), points: flat( c.getPoints( 8 ) ) } ) ),
	path3: { json: path3.toJSON(), points: flat( path3.getPoints( 8 ) ) },
	shape: { json: shape.toJSON(), outline: flat( extracted.shape ), holes: extracted.holes.map( flat ) },
};

console.log( JSON.stringify( out ) );
