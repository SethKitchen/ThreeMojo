// Copyright (c) 2026 Seth Kitchen, PE
// SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
//
// Writes three.json: the files three.js r187's EXRExporter writes for data
// textures, for `tests/test_exr_export.mojo`. Run it with three 0.187.0
// installed: `node three_exr_export.mjs /path/to/three three.json`.
//
// The texels come from a xorshift generator that the test repeats. The
// first 49 entries are those three.js 0.180 wrote for this fixture before:
// four sizes, float and half input, no compression, ZIPS and ZIP, and half
// and float samples, then the default options. The rest are RLE and PIZ.
// A file larger than 4,096 bytes is held by its size and SHA-256.

import { createHash } from 'node:crypto';
import { readFileSync, writeFileSync } from 'node:fs';
import { join } from 'node:path';
import { pathToFileURL } from 'node:url';

const [ threeDir, output ] = process.argv.slice( 2 );
const THREE = await import( pathToFileURL( join( threeDir, 'build/three.module.js' ) ) );
const { EXRExporter } = await import( pathToFileURL( join( threeDir, 'examples/jsm/exporters/EXRExporter.js' ) ) );
const version = JSON.parse( readFileSync( join( threeDir, 'package.json' ), 'utf8' ) ).version;
if ( version !== '0.187.0' ) throw Error( `Expected three 0.187.0; got ${version}` );

class Random {

	constructor( seed ) {

		this.x = seed >>> 0;

	}

	next() {

		let x = this.x;
		x ^= x << 13; x >>>= 0;
		x ^= x >>> 17;
		x ^= x << 5; x >>>= 0;
		this.x = x;
		return x;

	}

}

const SPECIAL = [ 0, - 0, 1, - 1, 0.5, 65504, 70000, - 1e9, 1e-6, 6e-8, 1e-10, NaN, Infinity, - Infinity, 3.14159, 0.1 ];

function floats( n, seed ) {

	const random = new Random( seed );
	const out = new Float32Array( n );
	for ( let i = 0; i < n; i ++ ) {

		const r = random.next();
		out[ i ] = ( r % 4 === 0 ) ? SPECIAL[ random.next() % SPECIAL.length ] : ( random.next() % 200001 - 100000 ) / 1000;

	}

	return out;

}

function halves( n, seed ) {

	const random = new Random( seed );
	const out = new Uint16Array( n );
	for ( let i = 0; i < n; i ++ ) out[ i ] = random.next() & 0xffff;
	return out;

}

// A smooth image that RLE and PIZ make smaller: a ramp and a triangle
// wave held to a grid of 1/64, with a run of one value along each row's
// start. It uses only arithmetic that rounds alike in Mojo.
function smooth( width, height, seed ) {

	const out = new Float32Array( width * height * 4 );
	for ( let y = 0; y < height; y ++ ) {

		for ( let x = 0; x < width; x ++ ) {

			const i = ( y * width + x ) * 4;
			const run = x < ( seed % 7 ) + 3;
			const wave = Math.abs( ( ( y + seed ) % 6 ) / 3 - 1 );
			out[ i ] = run ? 0.25 : Math.floor( 64 * ( x / width + 0.5 * wave ) + 0.5 ) / 64;
			out[ i + 1 ] = run ? 0.25 : Math.floor( 256 * y / height + 0.5 ) / 64;
			out[ i + 2 ] = ( ( x + y + seed ) % 9 ) / 8;
			out[ i + 3 ] = 1;

		}

	}

	return out;

}

// A smooth image with a little hashed noise in the low bits of each
// float: its blocks hold more than 16,384 different sixteen-bit words, so
// PIZ takes the wide wavelet, and PIZ still makes them smaller.
function fine( width, height, seed ) {

	const out = new Float32Array( width * height * 4 );
	for ( let y = 0; y < height; y ++ ) {

		for ( let x = 0; x < width; x ++ ) {

			const i = ( y * width + x ) * 4;
			const h0 = ( x * 7919 + y * 104729 + seed ) % 65521;
			const h1 = ( x * 104729 + y * 7919 + seed ) % 65521;
			const h2 = ( x * 31337 + y * 271 + seed ) % 65521;
			out[ i ] = x * 0.0123 + y * 0.0071 + h0 * 1e-8;
			out[ i + 1 ] = ( x - 192 ) * ( x - 192 ) * 0.0001 - y * 0.02 + h1 * 1e-8;
			out[ i + 2 ] = x * y * 0.0002 + 0.5 + h2 * 1e-8;
			out[ i + 3 ] = 1;

		}

	}

	return out;

}

function texture( width, height, input, seed ) {

	const n = width * height * 4;
	if ( input === 'half' ) {

		return new THREE.DataTexture( halves( n, seed ), width, height, THREE.RGBAFormat, THREE.HalfFloatType );

	}

	const data = {
		zero: () => new Float32Array( n ),
		smooth: () => smooth( width, height, seed ),
		fine: () => fine( width, height, seed ),
		float: () => floats( n, seed ),
	}[ input ]();
	return new THREE.DataTexture( data, width, height, THREE.RGBAFormat, THREE.FloatType );

}

// toHalfFloat warns about each value out of the half range.
console.warn = () => {};
const LARGE_FILE = 4096;
const exporter = new EXRExporter();
const entries = [];

async function add( width, height, input, compression, type, seed ) {

	const tex = texture( width, height, input, seed );
	const options = compression === - 1 ? undefined : { compression, type: type === 'float' ? THREE.FloatType : THREE.HalfFloatType };
	const bytes = await exporter.parse( tex, options );
	const entry = { width, height, input, compression, type, seed };
	// A large file is held by its SHA-256 and size, to keep the fixture small.
	if ( bytes.length > LARGE_FILE ) {

		entry.size = bytes.length;
		entry.sha256 = createHash( 'sha256' ).update( bytes ).digest( 'hex' );

	} else {

		entry.bytes = Buffer.from( bytes ).toString( 'base64' );

	}

	entries.push( entry );

}

const SIZES = [ [ 1, 1 ], [ 5, 3 ], [ 7, 20 ], [ 4, 33 ] ];
const TYPES = [ 'half', 'float' ];

let seed = 2;
for ( const [ width, height ] of SIZES ) {

	for ( const input of [ 'float', 'half' ] ) {

		for ( const compression of [ 0, 2, 3 ] ) {

			for ( const type of TYPES ) await add( width, height, input, compression, type, seed ++ );

		}

	}

}

await add( 3, 2, 'float', - 1, 'default', 99 );

{

	// RLE and PIZ, from seed 100: the sizes above, then larger smooth
	// images whose blocks the two compressions make smaller, then a fine
	// one with enough different words for PIZ's sixteen-bit wavelet.
	seed = 100;
	const LARGE = [ [ 33, 35 ], [ 64, 70 ] ];
	for ( const compression of [ 1, 4 ] ) {

		for ( const [ width, height ] of SIZES ) {

			for ( const input of [ 'float', 'half', 'smooth' ] ) {

				for ( const type of TYPES ) await add( width, height, input, compression, type, seed ++ );

			}

		}

		for ( const [ width, height ] of LARGE ) {

			for ( const type of TYPES ) await add( width, height, 'smooth', compression, type, seed ++ );

		}

	}

	await add( 256, 40, 'fine', 4, 'float', seed ++ );

	// Runs and literals longer than one count byte holds, and a run of
	// one Huffman symbol longer than one run code holds.
	await add( 300, 2, 'zero', 1, 'half', seed ++ );
	await add( 160, 2, 'half', 1, 'half', seed ++ );
	for ( const type of TYPES ) await add( 7, 20, 'zero', 4, type, seed ++ );

}

writeFileSync( output, JSON.stringify( entries ) );
console.log( `three ${version}: ${entries.length} entries` );
