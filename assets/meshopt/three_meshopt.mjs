// Copyright (c) 2026 Seth Kitchen, PE
// SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
//
// Writes meshopt.json: streams that meshoptimizer 0.22's encoder makes, some
// of them damaged on purpose, and what three.js 0.180's MeshoptDecoder
// decodes from each, or the error it throws. It also writes two glTF files
// that store their buffer views with EXT_meshopt_compression, and what
// three.js's GLTFLoader reads from them. `tests/test_meshopt.mojo` reads
// them. Run it with three 0.180 and meshoptimizer 0.22.0 installed beside
// it: `node three_meshopt.mjs`.

import { writeFileSync } from 'node:fs';
import { MeshoptDecoder } from 'three/examples/jsm/libs/meshopt_decoder.module.js';
import { GLTFLoader } from 'three/examples/jsm/loaders/GLTFLoader.js';
import { MeshoptEncoder } from 'meshoptimizer';

// Node has no ProgressEvent, which FileLoader makes for a data: URI.
globalThis.ProgressEvent ??= class ProgressEvent {

	constructor( type, init ) {

		Object.assign( this, { type }, init );

	}

};

await MeshoptDecoder.ready;
await MeshoptEncoder.ready;

// A small deterministic generator, so that the file does not change.
let seed = 12345;
function random() {

	seed = ( Math.imul( seed, 1103515245 ) + 12345 ) >>> 0;
	return ( seed >>> 8 ) / 16777216;

}

function randint( n ) {

	return Math.floor( random() * n );

}

const hex = ( a ) => Buffer.from( a.buffer, a.byteOffset, a.byteLength ).toString( 'hex' );
const u8 = ( a ) => new Uint8Array( a.buffer, a.byteOffset, a.byteLength );

const streams = [];

function record( name, count, stride, source, mode, filter ) {

	const entry = { name, count, stride, mode, filter, source: hex( source ), result: null, error: null };
	try {

		const target = new Uint8Array( count * stride );
		MeshoptDecoder.decodeGltfBuffer( target, count, stride, source, mode, filter );
		entry.result = hex( target );

	} catch ( e ) {

		entry.error = e.message;

	}

	streams.push( entry );
	return entry;

}

function attributes( name, data, count, stride, filter = 'NONE' ) {

	const source = MeshoptEncoder.encodeVertexBuffer( u8( data ), count, stride );
	record( name, count, stride, source, 'ATTRIBUTES', filter );
	return source;

}

// --- ATTRIBUTES ---------------------------------------------------------

const encoded = {};

attributes( 'no elements', new Uint8Array( 0 ), 0, 4 );
attributes( 'one element', new Uint8Array( [ 1, 2, 3, 250 ] ), 1, 4 );

{

	// Positions on a wavy surface, in floats: 700 elements are three
	// blocks of 256, 256 and 188.
	const f = new Float32Array( 700 * 3 );
	for ( let i = 0; i < 700; i ++ ) {

		const u = ( i % 30 ) / 29, v = Math.floor( i / 30 ) / 23;
		f[ i * 3 ] = u * 4 - 2;
		f[ i * 3 + 1 ] = Math.sin( u * 6 ) * Math.cos( v * 5 ) * 0.5;
		f[ i * 3 + 2 ] = v * 3 - 1.5;

	}

	encoded.positions = attributes( 'float positions', f, 700, 12 );

}

{

	const r = new Uint8Array( 33 * 16 );
	for ( let i = 0; i < r.length; i ++ ) r[ i ] = randint( 256 );
	encoded.random = attributes( 'random bytes', r, 33, 16 );

}

{

	// Bytes that change a little from one element to the next, and now
	// and then a lot, so that each width of delta and its escape occurs.
	const s = new Uint8Array( 200 * 64 );
	for ( let i = 0; i < 200; i ++ ) {

		for ( let k = 0; k < 64; k ++ ) {

			const step = k % 4 === 0 ? 0 : k % 4 === 1 ? randint( 3 ) - 1 : k % 4 === 2 ? randint( 13 ) - 6 : randint( 3 ) === 0 ? randint( 256 ) : 1;
			s[ i * 64 + k ] = ( ( i > 0 ? s[ ( i - 1 ) * 64 + k ] : k * 3 ) + step ) & 255;

		}

	}

	encoded.slow = attributes( 'slowly changing bytes', s, 200, 64 );

}

{

	const w = new Uint8Array( 70 * 256 );
	for ( let i = 0; i < w.length; i ++ ) w[ i ] = ( i * 7 + ( i >> 8 ) * 3 ) & 255;
	attributes( 'wide elements', w, 70, 256 );

}

{

	const c = new Uint8Array( 50 * 8 );
	for ( let i = 0; i < c.length; i ++ ) c[ i ] = [ 9, 0, 0, 128, 255, 1, 2, 3 ][ i % 8 ];
	attributes( 'constant elements', c, 50, 8 );

}

// --- TRIANGLES ----------------------------------------------------------

function grid( n ) {

	const indices = [];
	for ( let y = 0; y < n; y ++ ) {

		for ( let x = 0; x < n; x ++ ) {

			const a = y * ( n + 1 ) + x, b = a + 1, c = a + n + 1, d = c + 1;
			indices.push( a, c, b, b, c, d );

		}

	}

	return new Uint32Array( indices );

}

function triangles( name, indices, size ) {

	const data = size === 2 ? new Uint16Array( indices ) : new Uint32Array( indices );
	const source = MeshoptEncoder.encodeIndexBuffer( u8( data ), indices.length, size );
	record( name, indices.length, size, source, 'TRIANGLES', undefined );
	return source;

}

{

	const g = grid( 20 );
	MeshoptEncoder.reorderMesh( g, true, false );
	encoded.grid16 = triangles( 'a grid, 16-bit', g, 2 );
	triangles( 'a grid, 32-bit', g, 4 );

	// The same grid in its first order, which the codes cache less of.
	encoded.plain = triangles( 'a grid, unordered', grid( 12 ), 4 );

	// Triangles with nothing in common: free indices, far apart.
	const scattered = new Uint32Array( 90 );
	for ( let i = 0; i < 90; i ++ ) scattered[ i ] = randint( 3000000 );
	encoded.scattered = triangles( 'scattered triangles', scattered, 4 );

	// Walking along a strip one vertex at a time, back and forth, so
	// that the codes one before and one after the last free index occur.
	const walk = [];
	for ( let i = 0; i < 40; i ++ ) {

		const base = 1000 + ( i % 2 === 0 ? i : 40 - i );
		walk.push( 7, base, base + ( i % 3 === 0 ? 1 : - 1 ) );

	}

	encoded.walk = triangles( 'a walk', new Uint32Array( walk ), 4 );
	triangles( 'no triangles', new Uint32Array( 0 ), 2 );

	// Version 0 reads codes 13 and 14 from the cache instead.
	const v0 = encoded.grid16.slice();
	v0[ 0 ] = 0xe0;
	record( 'a grid, version 0', g.length, 2, v0, 'TRIANGLES', undefined );
	const w0 = encoded.walk.slice();
	w0[ 0 ] = 0xe0;
	record( 'a walk, version 0', walk.length, 4, w0, 'TRIANGLES', undefined );

}

// --- INDICES ------------------------------------------------------------

function sequence( name, indices, size ) {

	const data = size === 2 ? new Uint16Array( indices ) : new Uint32Array( indices );
	const source = MeshoptEncoder.encodeIndexSequence( u8( data ), indices.length, size );
	record( name, indices.length, size, source, 'INDICES', undefined );
	return source;

}

{

	const strip = [];
	for ( let i = 0; i < 60; i ++ ) strip.push( i % 2 === 0 ? i / 2 : 100 + ( i - 1 ) / 2 );
	encoded.strip = sequence( 'two interleaved runs', strip, 2 );
	const jumps = [];
	for ( let i = 0; i < 40; i ++ ) jumps.push( randint( 4000000000 ) );
	encoded.jumps = sequence( 'large jumps', jumps, 4 );
	sequence( 'no indices', [], 4 );

}

// --- filters ------------------------------------------------------------

function unitVectors( n, w ) {

	const out = new Float32Array( n * 4 );
	for ( let i = 0; i < n; i ++ ) {

		let x = random() * 2 - 1, y = random() * 2 - 1, z = random() * 2 - 1;
		if ( i === 0 ) [ x, y, z ] = [ 0, 0, - 1 ];
		if ( i === 1 ) [ x, y, z ] = [ 1, 0, 0 ];
		if ( i === 2 ) [ x, y, z ] = [ 0, - 1, 0 ];
		const l = Math.hypot( x, y, z );
		out.set( [ x / l, y / l, z / l, w ? random() * 2 - 1 : 1 ], i * 4 );

	}

	return out;

}

for ( const [ stride, bits ] of [ [ 4, 8 ], [ 4, 5 ], [ 8, 16 ], [ 8, 12 ] ] ) {

	const f = MeshoptEncoder.encodeFilterOct( unitVectors( 37, true ), 37, stride, bits );
	attributes( `octahedral, ${stride} bytes, ${bits} bits`, f, 37, stride, 'OCTAHEDRAL' );

}

for ( const bits of [ 16, 12, 4 ] ) {

	const q = new Float32Array( 41 * 4 );
	for ( let i = 0; i < 41; i ++ ) {

		const v = [ random() * 2 - 1, random() * 2 - 1, random() * 2 - 1, random() * 2 - 1 ];
		if ( i < 4 ) v.fill( 0 ), v[ i ] = i % 2 ? - 1 : 1;
		const l = Math.hypot( ...v );
		q.set( v.map( ( c ) => c / l ), i * 4 );

	}

	const f = MeshoptEncoder.encodeFilterQuat( q, 41, 8, bits );
	attributes( `quaternion, ${bits} bits`, f, 41, 8, 'QUATERNION' );

}

for ( const [ mode, bits ] of [ [ 'Separate', 23 ], [ 'SharedVector', 10 ], [ 'SharedComponent', 15 ], [ 'Clamped', 1 ] ] ) {

	const v = new Float32Array( 29 * 3 );
	for ( let i = 0; i < v.length; i ++ ) v[ i ] = ( random() * 2 - 1 ) * Math.pow( 10, randint( 13 ) - 6 );
	v[ 0 ] = 0;
	v[ 1 ] = - 0;
	v[ 2 ] = 1e30;
	const f = MeshoptEncoder.encodeFilterExp( v, 29, 12, bits, mode );
	attributes( `exponential, ${mode}, ${bits} bits`, f, 29, 12, 'EXPONENTIAL' );

}

{

	// Raw words with any exponent the specification allows, and raw
	// octahedral and quaternion components, including a zero vector.
	const words = new Int32Array( 64 );
	for ( let i = 0; i < 64; i ++ ) words[ i ] = ( ( randint( 201 ) - 100 ) << 24 ) | randint( 1 << 24 );
	attributes( 'exponential, raw words', words, 16, 16, 'EXPONENTIAL' );
	const oct = new Int8Array( 24 * 4 );
	for ( let i = 0; i < 24; i ++ ) oct.set( [ randint( 255 ) - 127, randint( 255 ) - 127, 127, randint( 256 ) - 128 ], i * 4 );
	oct.set( [ 0, 0, 0, 5 ], 0 );
	oct.set( [ 0, 0, 127, 5 ], 4 );
	attributes( 'octahedral, raw bytes', oct, 24, 4, 'OCTAHEDRAL' );
	const oct16 = new Int16Array( 24 * 4 );
	for ( let i = 0; i < 24; i ++ ) oct16.set( [ randint( 2047 ) - 1023, randint( 2047 ) - 1023, i % 2 ? 1023 : - 31745, randint( 65536 ) - 32768 ], i * 4 );
	attributes( 'octahedral, raw shorts', oct16, 24, 8, 'OCTAHEDRAL' );
	const quat = new Int16Array( 24 * 4 );
	for ( let i = 0; i < 24; i ++ ) quat.set( [ randint( 2047 ) - 1023, randint( 2047 ) - 1023, randint( 2047 ) - 1023, ( 1023 & ~3 ) | ( i & 3 ) | ( i % 5 === 0 ? - 32768 : 0 ) ], i * 4 );
	attributes( 'quaternion, raw shorts', quat, 24, 8, 'QUATERNION' );

}

// --- damaged streams ----------------------------------------------------

function damage( name, source, count, stride, mode ) {

	record( name + ', cut short', count, stride, source.slice( 0, source.length - 1 ), mode );
	const longer = new Uint8Array( source.length + 1 );
	longer.set( source );
	record( name + ', one byte too many', count, stride, longer, mode );
	const header = source.slice();
	header[ 0 ] ^= 0x10;
	record( name + ', wrong header', count, stride, header, mode );
	const version = source.slice();
	version[ 0 ] = ( version[ 0 ] & 0xf0 ) | 2;
	record( name + ', unknown version', count, stride, version, mode );
	record( name + ', only a header', count, stride, source.slice( 0, 1 ), mode );
	for ( let k = 0; k < 6; k ++ ) {

		const flipped = source.slice();
		for ( let j = 0; j < 3; j ++ ) flipped[ 1 + randint( source.length - 1 ) ] ^= 1 << randint( 8 );
		record( name + ', flipped ' + k, count, stride, flipped, mode );

	}

}

damage( 'float positions', encoded.positions, 700, 12, 'ATTRIBUTES' );
damage( 'slowly changing bytes', encoded.slow, 200, 64, 'ATTRIBUTES' );
damage( 'a grid', encoded.grid16, 1200, 2, 'TRIANGLES' );
damage( 'scattered triangles', encoded.scattered, 90, 4, 'TRIANGLES' );
damage( 'a walk', encoded.walk, 120, 4, 'TRIANGLES' );
damage( 'two interleaved runs', encoded.strip, 60, 2, 'INDICES' );
damage( 'large jumps', encoded.jumps, 40, 4, 'INDICES' );

{

	// A three-vertex code that restarts the new vertices, and one whose
	// table entry is a free index, which only the byte form reads.
	const restart = new Uint8Array( [ 0xe1, 0xf0, 0xfe, 0xf1, 0x00, ...new Uint8Array( 14 ).fill( 0 ).map( ( _, i ) => i === 1 ? 0xff : 0 ), 0, 0 ] );
	record( 'a restart', 9, 2, restart, 'TRIANGLES' );
	const free = new Uint8Array( [ 0xe1, 0xff, 0xff, 0x04, 0x02, 0x00, ...new Uint8Array( 16 ) ] );
	record( 'three free indices', 3, 4, free, 'TRIANGLES' );

}

// --- glTF ---------------------------------------------------------------

function align( chunks ) {

	let length = 0;
	for ( const c of chunks ) length += ( c.length + 3 ) & ~3;
	const out = new Uint8Array( length );
	const offsets = [];
	let at = 0;
	for ( const c of chunks ) {

		offsets.push( at );
		out.set( c, at );
		at += ( c.length + 3 ) & ~3;

	}

	return [ out, offsets ];

}

function model( required ) {

	// A 6 by 6 grid of quads, bent into a hill: 16-bit positions, 8-bit
	// octahedral normals, 16-bit texture coordinates and 16-bit triangles,
	// and an animation of rotations and of times.
	const n = 6, verts = ( n + 1 ) * ( n + 1 );
	const pos = new Uint16Array( verts * 4 ), uv = new Uint16Array( verts * 2 ), nrm = new Float32Array( verts * 4 );
	for ( let y = 0; y <= n; y ++ ) {

		for ( let x = 0; x <= n; x ++ ) {

			const i = y * ( n + 1 ) + x;
			const h = Math.sin( x / n * Math.PI ) * Math.sin( y / n * Math.PI );
			pos.set( [ x * 1000, Math.round( h * 3000 ), y * 1000, 0 ], i * 4 );
			uv.set( [ Math.round( x / n * 65535 ), Math.round( y / n * 65535 ) ], i * 2 );
			const nx = - Math.cos( x / n * Math.PI ) * Math.sin( y / n * Math.PI ) * 0.5, nz = - Math.sin( x / n * Math.PI ) * Math.cos( y / n * Math.PI ) * 0.5;
			const l = Math.hypot( nx, 1, nz );
			nrm.set( [ nx / l, 1 / l, nz / l, 1 ], i * 4 );

		}

	}

	const index = new Uint16Array( grid( n ) );
	const oct = MeshoptEncoder.encodeFilterOct( nrm, verts, 4, 8 );
	const keys = 5;
	const times = new Float32Array( [ 0, 0.5, 1, 1.5, 2 ] );
	const quats = new Float32Array( keys * 4 );
	for ( let k = 0; k < keys; k ++ ) {

		const a = k * 0.4;
		quats.set( [ 0, Math.sin( a / 2 ), 0, Math.cos( a / 2 ) ], k * 4 );

	}

	const quat = MeshoptEncoder.encodeFilterQuat( quats, keys, 8, 12 );
	const time = MeshoptEncoder.encodeFilterExp( times, keys, 4, 23, 'Separate' );

	const views = [
		[ u8( pos ), verts, 8, 'ATTRIBUTES', 'NONE', 34962 ],
		[ oct, verts, 4, 'ATTRIBUTES', 'OCTAHEDRAL', 34962 ],
		[ u8( uv ), verts, 4, 'ATTRIBUTES', 'NONE', 34962 ],
		[ u8( index ), index.length, 2, 'TRIANGLES', 'NONE', 34963 ],
		[ time, keys, 4, 'ATTRIBUTES', 'EXPONENTIAL', undefined ],
		[ quat, keys, 8, 'ATTRIBUTES', 'QUATERNION', undefined ],
	];
	const compressed = views.map( ( [ data, count, stride, mode ] ) => MeshoptEncoder.encodeGltfBuffer( data, count, stride, mode ) );
	const [ packed, packedOffsets ] = align( compressed );
	// The fallback holds the data unfiltered, where a reader without the
	// extension reads it; with the extension, it is not read.
	const [ plain, plainOffsets ] = align( views.map( ( v ) => v[ 0 ] ) );

	const bufferViews = views.map( ( [ , count, stride, mode, filter, target ], i ) => {

		const ext = { buffer: 0, byteOffset: packedOffsets[ i ], byteLength: compressed[ i ].length, byteStride: stride, count, mode };
		if ( filter !== 'NONE' ) ext.filter = filter;
		const view = { buffer: 1, byteOffset: plainOffsets[ i ], byteLength: count * stride, extensions: { EXT_meshopt_compression: ext } };
		if ( mode === 'ATTRIBUTES' && target === 34962 ) view.byteStride = stride;
		if ( target ) view.target = target;
		return view;

	} );

	const base64 = ( a ) => 'data:application/octet-stream;base64,' + Buffer.from( a ).toString( 'base64' );
	const fallback = required ? { byteLength: plain.length, extensions: { EXT_meshopt_compression: { fallback: true } } } : { byteLength: plain.length, uri: base64( plain ) };
	return {
		asset: { version: '2.0' },
		extensionsUsed: [ 'EXT_meshopt_compression', 'KHR_mesh_quantization' ],
		extensionsRequired: required ? [ 'EXT_meshopt_compression', 'KHR_mesh_quantization' ] : [ 'KHR_mesh_quantization' ],
		buffers: [ { byteLength: packed.length, uri: base64( packed ) }, fallback ],
		bufferViews,
		accessors: [
			{ bufferView: 0, componentType: 5123, count: verts, type: 'VEC3', min: [ 0, 0, 0 ], max: [ n * 1000, 3000, n * 1000 ] },
			{ bufferView: 1, componentType: 5120, normalized: true, count: verts, type: 'VEC3' },
			{ bufferView: 2, componentType: 5123, normalized: true, count: verts, type: 'VEC2' },
			{ bufferView: 3, componentType: 5123, count: index.length, type: 'SCALAR' },
			{ bufferView: 4, componentType: 5126, count: keys, type: 'SCALAR', min: [ 0 ], max: [ 2 ] },
			{ bufferView: 5, componentType: 5122, normalized: true, count: keys, type: 'VEC4' },
		],
		meshes: [ { primitives: [ { attributes: { POSITION: 0, NORMAL: 1, TEXCOORD_0: 2 }, indices: 3 } ] } ],
		nodes: [ { mesh: 0, name: 'hill', scale: [ 0.001, 0.001, 0.001 ] } ],
		scenes: [ { nodes: [ 0 ] } ],
		scene: 0,
		animations: [ { channels: [ { sampler: 0, target: { node: 0, path: 'rotation' } } ], samplers: [ { input: 4, output: 5 } ] } ],
	};

}

const loader = new GLTFLoader().setMeshoptDecoder( MeshoptDecoder );
const models = {};
for ( const [ name, required ] of [ [ 'required', true ], [ 'optional', false ] ] ) {

	const json = JSON.stringify( model( required ) );
	writeFileSync( `hill_${name}.gltf`, json );
	const gltf = await loader.parseAsync( json, '' );
	const mesh = gltf.scene.getObjectByName( 'hill' );
	const g = mesh.geometry;
	const track = gltf.animations[ 0 ].tracks[ 0 ];
	// An interleaved attribute's array holds its neighbors too, and a
	// normalized one holds integers: getComponent reads each value as
	// the renderer does.
	const values = ( a ) => {

		const out = [];
		for ( let i = 0; i < a.count; i ++ ) for ( let c = 0; c < a.itemSize; c ++ ) out.push( a.getComponent( i, c ) );
		return out;

	};

	models[ name ] = {
		position: values( g.attributes.position ),
		normal: values( g.attributes.normal ),
		uv: values( g.attributes.uv ),
		index: Array.from( g.index.array ),
		times: Array.from( track.times ),
		values: Array.from( track.values ),
	};

}

writeFileSync( 'meshopt.json', JSON.stringify( { streams, models } ) );
console.log( streams.length, 'streams' );
