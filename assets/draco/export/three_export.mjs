// Copyright (c) 2026 Seth Kitchen, PE
// SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
//
// Writes three.json and three.bin: geometries, and what three.js 0.180's
// DRACOExporter writes for each with draco3d 1.5.6's encoder, for the option
// sets below. `tests/test_draco_export.mojo` reads them. Run it with three
// 0.180 and draco3d 1.5.6 installed beside it: `node three_export.mjs`.
//
// three.bin holds 32-bit little-endian words. An input float or index is one
// word. An export is its bytes, padded to whole words. The JSON gives an
// input array as [first word, count] and an export as [first word, bytes].

import * as THREE from 'three';
import { DRACOExporter } from 'three/addons/exporters/DRACOExporter.js';
import { writeFileSync } from 'node:fs';
import { createRequire } from 'node:module';

const require = createRequire( import.meta.url );
const draco3d = require( 'draco3d' );

const words = [];

function pushFloats( array ) {

	const start = words.length;
	const bits = new Uint32Array( new Float32Array( array ).buffer );
	for ( const w of bits ) words.push( w );
	return [ start, bits.length ];

}

function pushInts( array ) {

	const start = words.length;
	for ( const w of array ) words.push( w >>> 0 );
	return [ start, array.length ];

}

function pushBytes( bytes ) {

	const start = words.length;
	const padded = new Uint8Array( Math.ceil( bytes.length / 4 ) * 4 );
	padded.set( new Uint8Array( bytes.buffer, bytes.byteOffset, bytes.length ) );
	for ( const w of new Uint32Array( padded.buffer ) ) words.push( w );
	return [ start, bytes.length ];

}

// A small generator, so that the colors and the points are the same each run.
let seed = 12345;
function random() {

	seed = ( Math.imul( seed, 1103515245 ) + 12345 ) >>> 0;
	return ( seed >>> 8 ) / 16777216;

}

function colored( geometry ) {

	const position = geometry.getAttribute( 'position' );
	const colors = [];
	for ( let i = 0; i < position.count; i ++ ) {

		colors.push( 0.5 + 0.5 * Math.sin( position.getX( i ) * 3 ), random(), ( i % 7 ) / 6 );

	}

	geometry.setAttribute( 'color', new THREE.Float32BufferAttribute( colors, 3 ) );
	return geometry;

}

function cloud( count, duplicates ) {

	const positions = [];
	const colors = [];
	for ( let i = 0; i < count; i ++ ) {

		positions.push( random() * 4 - 2, random() * 2, random() - 0.5 );
		colors.push( random(), random(), random(), random() );

	}

	for ( let i = 0; i < duplicates; i ++ ) {

		const k = Math.floor( random() * count );
		positions.push( positions[ 3 * k ], positions[ 3 * k + 1 ], positions[ 3 * k + 2 ] );
		colors.push( colors[ 4 * k ], colors[ 4 * k + 1 ], colors[ 4 * k + 2 ], colors[ 4 * k + 3 ] );

	}

	const geometry = new THREE.BufferGeometry();
	geometry.setAttribute( 'position', new THREE.Float32BufferAttribute( positions, 3 ) );
	geometry.setAttribute( 'color', new THREE.Float32BufferAttribute( colors, 4 ) );
	return geometry;

}

function triangle() {

	const geometry = new THREE.BufferGeometry();
	geometry.setAttribute( 'position', new THREE.Float32BufferAttribute( [ 0, 0, 0, 1, 0, 0, 0, 1, 0 ], 3 ) );
	geometry.setIndex( [ 0, 1, 2 ] );
	return geometry;

}

// A mesh with the cases Draco's corner table handles on its own: an edge
// that three triangles share, a vertex with two fans, a fan that meets a
// vertex twice, a triangle that repeats a vertex, a triangle and its
// mirror, a vertex no triangle uses, a vertex equal to another, a texture
// seam, two vertices with one uv, and a zero normal.
function odd() {

	const positions = [
		0, 0, 0, 1, 0, 0, 0, 1, 0, 1, 1, 0, 0.5, 0.5, 1, 0.5, 0.5, - 1,
		2, 2, 0, 3, 2, 0, 2, 3, 0, 5, 5, 5, 1, 1, 0, 0, 0, 0,
		4, 0, 0, 5, 0, 0, 4, 1, 0, 3, 1, 0.5, 3.5, - 1, 0.2,
		6, 0, 0, 7, 0, 0.5, 6.5, 1, 0, 7, 1, 0,
	];
	const normals = [];
	const uvs = [];
	const colors = [];
	for ( let i = 0; i < 21; i ++ ) {

		normals.push( i === 4 ? 0 : 0.1 * i, i === 4 ? 0 : 1, i === 4 ? 0 : - 0.2 * i );
		uvs.push( positions[ 3 * i ] / 5, positions[ 3 * i + 1 ] / 5 );
		colors.push( i / 12, 1 - i / 12, 0.5, i % 2 );

	}

	// Vertex 10 repeats vertex 3; vertex 11 is vertex 0 with another uv.
	uvs[ 22 ] = 0.9;
	// Vertices 18 and 19 share a uv.
	uvs[ 36 ] = uvs[ 38 ] = 0.3;
	uvs[ 37 ] = uvs[ 39 ] = 0.3;
	const geometry = new THREE.BufferGeometry();
	geometry.setAttribute( 'position', new THREE.Float32BufferAttribute( positions, 3 ) );
	geometry.setAttribute( 'normal', new THREE.Float32BufferAttribute( normals, 3 ) );
	geometry.setAttribute( 'uv', new THREE.Float32BufferAttribute( uvs, 2 ) );
	geometry.setAttribute( 'color', new THREE.Float32BufferAttribute( colors, 4 ) );
	geometry.setIndex( [
		0, 1, 2, 1, 3, 2, 0, 1, 4, 0, 1, 5, 3, 6, 7, 2, 2, 4,
		10, 8, 6, 11, 2, 4, 0, 2, 1, 6, 8, 7,
		12, 13, 14, 12, 14, 15, 12, 15, 16, 12, 16, 14,
		17, 18, 19, 18, 20, 19, 13, 17, 19,
	] );
	return geometry;

}

// Triangles tangled so that the fans of their vertices meet a neighbor
// twice, which Draco cuts apart.
function tangle( index ) {

	const geometry = new THREE.BufferGeometry();
	geometry.setAttribute( 'position', new THREE.Float32BufferAttribute( [ 0, 0, 0, 1, 0, 0, 0, 1, 0, 0, 0, 1, 1, 1, 1 ], 3 ) );
	geometry.setIndex( index );
	return geometry;

}

// Triangles that all repeat a vertex.
function flat() {

	const geometry = new THREE.BufferGeometry();
	geometry.setAttribute( 'position', new THREE.Float32BufferAttribute( [ 0, 0, 0, 1, 0, 0, 0, 1, 0 ], 3 ) );
	geometry.setIndex( [ 0, 0, 1, 1, 2, 2 ] );
	return geometry;

}

// Points with a coordinate that is not a number.
function nan() {

	const geometry = new THREE.BufferGeometry();
	geometry.setAttribute( 'position', new THREE.Float32BufferAttribute( [ 0, 0, 0, 1, NaN, 0, 0, 1, 0 ], 3 ) );
	return geometry;

}

const geometries = {
	odd: [ 'mesh', odd() ],
	flat: [ 'mesh', flat() ],
	tangle: [ 'mesh', tangle( [ 4, 3, 0, 4, 0, 1, 4, 2, 3, 3, 0, 2, 2, 1, 0, 0, 2, 4, 0, 2, 1, 1, 3, 2 ] ) ],
	knotted: [ 'mesh', tangle( [ 3, 1, 2, 1, 3, 4, 1, 0, 2, 0, 1, 2, 0, 4, 2, 3, 4, 1, 1, 4, 2 ] ) ],
	grid: [ 'mesh', colored( new THREE.PlaneGeometry( 2, 1, 30, 20 ) ) ],
	nan: [ 'points', nan() ],
	box: [ 'mesh', new THREE.BoxGeometry( 1, 2, 3, 2, 2, 2 ) ],
	sphere: [ 'mesh', new THREE.SphereGeometry( 1, 16, 12 ) ],
	knot: [ 'mesh', colored( new THREE.TorusKnotGeometry( 1, 0.3, 64, 8 ) ) ],
	plane: [ 'mesh', colored( new THREE.PlaneGeometry( 2, 1, 5, 3 ) ) ],
	torus: [ 'mesh', colored( new THREE.TorusGeometry( 1, 0.4, 6, 10 ) ) ],
	triangle: [ 'mesh', triangle() ],
	points: [ 'points', cloud( 200, 20 ) ],
	few: [ 'points', cloud( 5, 1 ) ],
};

const meshOptions = [
	{},
	{ encodeSpeed: 0, decodeSpeed: 0 },
	{ encodeSpeed: 1, decodeSpeed: 0 },
	{ encodeSpeed: 2, decodeSpeed: 2 },
	{ encodeSpeed: 3, decodeSpeed: 1 },
	{ encodeSpeed: 4, decodeSpeed: 4 },
	{ encodeSpeed: 6, decodeSpeed: 5 },
	{ encodeSpeed: 7, decodeSpeed: 7 },
	{ encodeSpeed: 8, decodeSpeed: 3 },
	{ encodeSpeed: 10, decodeSpeed: 10 },
	{ encodeSpeed: 0, decodeSpeed: 0, exportColor: true },
	{ encodeSpeed: 5, decodeSpeed: 5, exportColor: true },
	{ encodeSpeed: 7, decodeSpeed: 6, exportColor: true },
	{ exportUvs: false },
	{ exportNormals: false, exportColor: true },
	{ quantization: [ 11, 10, 8, 12, 8 ] },
	{ quantization: [ 20, 6, 10, 14, 8 ], encodeSpeed: 2, decodeSpeed: 2, exportColor: true },
	{ quantization: [ 24, 20, 16, 22, 8 ], encodeSpeed: 1, decodeSpeed: 1, exportColor: true },
	{ quantization: [ 0, 0, 0, 0, 0 ], exportColor: true },
	{ quantization: [ 3, 8, 8, 4, 8 ], encodeSpeed: 3, decodeSpeed: 3 },
	{ quantization: [ 0, 8, 8, 12, 8 ], encodeSpeed: 1, decodeSpeed: 0 },
	{ quantization: [ 14 ], encodeSpeed: 0, decodeSpeed: 0 },
	{ quantization: [ 1, 2, 1, 1, 1 ], exportColor: true },
	{ encoderMethod: DRACOExporter.MESH_SEQUENTIAL_ENCODING },
	{ encoderMethod: DRACOExporter.MESH_SEQUENTIAL_ENCODING, encodeSpeed: 0, decodeSpeed: 0, exportColor: true },
	{ encoderMethod: DRACOExporter.MESH_SEQUENTIAL_ENCODING, encodeSpeed: 10, decodeSpeed: 10 },
	{ encoderMethod: DRACOExporter.MESH_SEQUENTIAL_ENCODING, quantization: [ 0, 0, 0, 0, 0 ], exportColor: true },
];

// The two meshes of more than 1000 triangles take the valence traversal
// below speed 5. They are exported with fewer options, to keep the files
// small.
const bigOptions = [
	{},
	{ encodeSpeed: 0, decodeSpeed: 0 },
	{ encodeSpeed: 3, decodeSpeed: 1, exportColor: true },
	{ encodeSpeed: 4, decodeSpeed: 4 },
	{ encodeSpeed: 7, decodeSpeed: 6, exportColor: true },
	{ quantization: [ 3, 8, 8, 4, 8 ], encodeSpeed: 3, decodeSpeed: 3 },
	{ encoderMethod: DRACOExporter.MESH_SEQUENTIAL_ENCODING, encodeSpeed: 0, decodeSpeed: 0 },
];

const pointOptions = [
	{},
	{ encodeSpeed: 0, decodeSpeed: 0 },
	{ encodeSpeed: 1, decodeSpeed: 1 },
	{ encodeSpeed: 2, decodeSpeed: 2 },
	{ encodeSpeed: 3, decodeSpeed: 3 },
	{ encodeSpeed: 4, decodeSpeed: 4 },
	{ encodeSpeed: 6, decodeSpeed: 6 },
	{ encodeSpeed: 7, decodeSpeed: 7 },
	{ encodeSpeed: 8, decodeSpeed: 8 },
	{ encodeSpeed: 9, decodeSpeed: 9 },
	{ encodeSpeed: 10, decodeSpeed: 10 },
	{ exportColor: true },
	{ exportColor: true, encodeSpeed: 0, decodeSpeed: 0 },
	{ exportColor: true, encodeSpeed: 3, decodeSpeed: 2 },
	{ exportColor: true, encodeSpeed: 10, decodeSpeed: 10 },
	{ exportColor: true, quantization: [ 12, 8, 5, 8, 8 ] },
	{ exportColor: true, quantization: [ 2, 8, 2, 8, 8 ], encodeSpeed: 3, decodeSpeed: 3 },
	{ exportColor: true, quantization: [ 0, 8, 8, 8, 8 ] },
	{ exportColor: true, quantization: [ 16, 8, 0, 8, 8 ] },
	{ encoderMethod: DRACOExporter.MESH_SEQUENTIAL_ENCODING },
	{ encoderMethod: DRACOExporter.MESH_SEQUENTIAL_ENCODING, exportColor: true, encodeSpeed: 0, decodeSpeed: 0 },
	{ encoderMethod: DRACOExporter.MESH_SEQUENTIAL_ENCODING, exportColor: true, quantization: [ 0, 8, 0, 8, 8 ] },
];

const json = { geometries: {}, cases: [] };

for ( const [ name, [ kind, geometry ] ] of Object.entries( geometries ) ) {

	const entry = { kind, attributes: {} };
	for ( const key of [ 'position', 'normal', 'uv', 'color' ] ) {

		const attribute = geometry.getAttribute( key );
		if ( attribute === undefined ) continue;
		entry.attributes[ key ] = { itemSize: attribute.itemSize, words: pushFloats( attribute.array ) };

	}

	if ( geometry.index !== null ) entry.index = pushInts( geometry.index.array );
	json.geometries[ name ] = entry;

}

const exporter = new DRACOExporter();

for ( const [ name, [ kind, geometry ] ] of Object.entries( geometries ) ) {

	const object = kind === 'mesh' ? new THREE.Mesh( geometry ) : new THREE.Points( geometry );
	let options = kind === 'mesh' ? meshOptions : pointOptions;
	if ( name === 'knot' || name === 'grid' ) options = bigOptions;
	for ( const option of options ) {

		// three.js makes a new encoder module for each export.
		const module = await draco3d.createEncoderModule( {} );
		globalThis.DracoEncoderModule = () => module;
		const entry = { geometry: name, options: option };
		try {

			entry.bytes = pushBytes( exporter.parse( object, option ) );

		} catch ( error ) {

			entry.error = String( error.message ?? error );

		}

		json.cases.push( entry );

	}

}

writeFileSync( 'three.json', JSON.stringify( json ) + '\n' );
writeFileSync( 'three.bin', Buffer.from( new Uint32Array( words ).buffer ) );
