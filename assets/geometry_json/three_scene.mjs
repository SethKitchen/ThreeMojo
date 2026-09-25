// Copyright (c) 2026 Seth Kitchen, PE
// SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
//
// Writes scene.json: a three.js 0.180 scene with one mesh for each of the
// nineteen geometry types that `fromJSON` reads, for
// `tests/test_geometry_json.mojo`. Run it with three 0.180 installed
// beside it: `node three_scene.mjs > scene.json`.
//
// - `scene`: `scene.toJSON()`, geometries written as their parameters.
// - `arrays`: each geometry's position, normal and uv, its index and its
//   groups, in the order of `scene.geometries`.
// - `box` and `material`: a lone geometry's and a lone material's
//   `toJSON()`, and `data`: a geometry with no parameters.

import * as THREE from 'three';

function square( x, y, side ) {

	const path = new THREE.Shape();
	path.moveTo( x, y );
	path.lineTo( x + side, y );
	path.lineTo( x + side, y + side );
	path.lineTo( x, y + side );
	path.lineTo( x, y );
	return path;

}

const plate = square( 0, 0, 2 );
const hole = new THREE.Path();
hole.moveTo( 0.5, 0.5 );
hole.lineTo( 0.5, 1.5 );
hole.lineTo( 1.5, 1.5 );
hole.lineTo( 1.5, 0.5 );
hole.lineTo( 0.5, 0.5 );
plate.holes.push( hole );

const badge = new THREE.Shape();
badge.moveTo( 3, 0 );
badge.lineTo( 4, 0 );
badge.quadraticCurveTo( 4.5, 1, 3.5, 1.5 );
badge.lineTo( 3, 0 );

const spine = new THREE.CatmullRomCurve3( [
	new THREE.Vector3( 0, 0, 0 ), new THREE.Vector3( 1, 2, 0 ), new THREE.Vector3( 3, 2, 1 ), new THREE.Vector3( 4, 0, 2 ),
] );
const wire = new THREE.CatmullRomCurve3( [
	new THREE.Vector3( 0, 0, 0 ), new THREE.Vector3( 1, 1, 0 ), new THREE.Vector3( 2, 0, 1 ),
], false, 'chordal' );

const geometries = [
	new THREE.BoxGeometry( 1, 2, 3, 2, 1, 3 ),
	new THREE.CapsuleGeometry( 0.5, 1.5, 3, 6, 2 ),
	new THREE.CircleGeometry( 1, 12, 0.5, 4 ),
	new THREE.ConeGeometry( 1, 2, 10, 2, true, 0.3, 5 ),
	new THREE.CylinderGeometry( 0.5, 1, 2, 10, 3, false, 0, 6 ),
	new THREE.DodecahedronGeometry( 1.5, 1 ),
	new THREE.ExtrudeGeometry( [ plate, badge ], {
		curveSegments: 4, steps: 2, depth: 0.5, bevelEnabled: true,
		bevelThickness: 0.1, bevelSize: 0.05, bevelOffset: 0, bevelSegments: 2,
	} ),
	new THREE.ExtrudeGeometry( badge, { curveSegments: 4, steps: 6, extrudePath: spine } ),
	new THREE.IcosahedronGeometry( 1, 2 ),
	new THREE.LatheGeometry( [ new THREE.Vector2( 0, - 1 ), new THREE.Vector2( 0.8, - 0.5 ), new THREE.Vector2( 0.6, 0.5 ), new THREE.Vector2( 0, 1 ) ], 8, 0.2, 5 ),
	new THREE.OctahedronGeometry( 1, 0 ),
	new THREE.PlaneGeometry( 2, 1, 3, 2 ),
	new THREE.PolyhedronGeometry( [ 1, 1, 1, - 1, - 1, 1, - 1, 1, - 1, 1, - 1, - 1 ], [ 2, 1, 0, 0, 3, 2, 1, 3, 0, 2, 3, 1 ], 1.2, 1 ),
	new THREE.RingGeometry( 0.4, 1, 10, 2, 0.1, 5 ),
	new THREE.ShapeGeometry( [ plate, badge ], 6 ),
	new THREE.SphereGeometry( 1, 12, 8, 0.2, 5, 0.3, 2 ),
	new THREE.TetrahedronGeometry( 1, 1 ),
	new THREE.TorusGeometry( 1, 0.3, 8, 20, 5 ),
	new THREE.TorusKnotGeometry( 1, 0.3, 40, 6, 3, 5 ),
	new THREE.TubeGeometry( wire, 20, 0.2, 6, false ),
];

const scene = new THREE.Scene();
const paint = new THREE.MeshBasicMaterial();
for ( const g of geometries ) scene.add( new THREE.Mesh( g, paint ) );

const json = scene.toJSON();
const byUuid = new Map( geometries.map( ( g ) => [ g.uuid, g ] ) );
const dump = ( g ) => ( {
	position: Array.from( g.getAttribute( 'position' ).array ),
	normal: Array.from( g.getAttribute( 'normal' ).array ),
	uv: Array.from( g.getAttribute( 'uv' ).array ),
	index: g.index ? Array.from( g.index.array ) : [],
	groups: g.groups.map( ( r ) => [ r.start, r.count, r.materialIndex ] ),
} );
const arrays = json.geometries.map( ( entry ) => dump( byUuid.get( entry.uuid ) ) );

const box = new THREE.BoxGeometry( 1, 2, 3 );
box.name = 'crate';
const data = new THREE.BufferGeometry();
data.setAttribute( 'position', new THREE.Float32BufferAttribute( [ 0, 0, 0, 1, 0, 0, 0, 1, 0 ], 3 ) );
data.setIndex( [ 0, 1, 2 ] );
const material = new THREE.MeshStandardMaterial( { color: 0x336699, roughness: 0.25, metalness: 0.5, name: 'steel' } );

console.log( JSON.stringify( { scene: json, arrays, box: box.toJSON(), data: data.toJSON(), material: material.toJSON() } ) );
