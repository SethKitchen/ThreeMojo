// Writes the Gaussian splat test files here, and reads each one back with
// three.js r186's own loaders into expected.json: the geometry every loader
// makes, and what a GaussianSplat computes from one of them (its bounds, a
// raycast and its CPU sort). Run it where `three` 0.186 is installed, with
// the output directory as its one argument:
//
//     node make_splats.mjs assets/gaussian_splat
//
// No compressor is needed: the gzip files come from node's zlib, and the one
// zstd file is built of raw blocks, which every zstd decoder reads.
import { writeFileSync } from 'node:fs';
import { join } from 'node:path';
import { gzipSync } from 'node:zlib';
import { DataUtils, PerspectiveCamera, Raycaster, Vector3 } from 'three';
import { SPLATLoader } from 'three/addons/loaders/SPLATLoader.js';
import { KSPLATLoader } from 'three/addons/loaders/KSPLATLoader.js';
import { SPZLoader } from 'three/addons/loaders/SPZLoader.js';
import { GaussianSplatPLYLoader } from 'three/addons/loaders/GaussianSplatPLYLoader.js';
import { GLTFLoader } from 'three/addons/loaders/GLTFLoader.js';
import { GLTFGaussianSplatLoaderExtension } from 'three/addons/loaders/GLTFGaussianSplatLoaderExtension.js';
import { GaussianSplat } from 'three/addons/objects/GaussianSplat.js';

const out = process.argv[ 2 ] || '.';

// Node has no ProgressEvent, which three.js's FileLoader makes while it
// reads the glTF file's data: URI.
globalThis.ProgressEvent ??= class extends Event {

	constructor( type, init ) {

		super( type ); Object.assign( this, init );

	}

};

class Writer {

	constructor() {

		this.bytes = [];

	}

	u8( v ) {

		this.bytes.push( v & 255 );

	}

	u16( v ) {

		this.u8( v ); this.u8( v >> 8 );

	}

	u32( v ) {

		this.u16( v & 0xffff ); this.u16( v >>> 16 );

	}

	f32( v ) {

		const b = new Uint8Array( new Float32Array( [ v ] ).buffer );
		for ( const x of b ) this.u8( x );

	}

	half( v ) {

		this.u16( DataUtils.toHalfFloat( v ) );

	}

	pad( n ) {

		while ( this.bytes.length < n ) this.u8( 0 );

	}

	buffer() {

		return new Uint8Array( this.bytes ).buffer;

	}

}

function geometryJSON( geometry ) {

	const json = {
		count: geometry.getAttribute( 'position' ).count,
		centers: Array.from( geometry.getAttribute( 'position' ).array ),
		covariances: Array.from( geometry.getAttribute( 'covariance' ).array ),
		colors: Array.from( geometry.getAttribute( 'color' ).array )
	};

	for ( let i = 1; i <= 3; i ++ ) {

		const attribute = geometry.getAttribute( `sphericalHarmonics${ i }` );
		if ( attribute !== undefined ) json[ `sh${ i }` ] = Array.from( new Uint8Array( attribute.array.buffer ) );

	}

	return json;

}

const expected = {};

function save( name, buffer ) {

	writeFileSync( join( out, name ), new Uint8Array( buffer ) );

}

// --- .splat ----------------------------------------------------------------

{

	const w = new Writer();
	const rows = [
		[ [ 0.5, - 0.25, 1 ], [ 0.1, 0.2, 0.3 ], [ 255, 128, 0, 200 ], [ 200, 140, 100, 128 ] ],
		[ [ - 1, 2, - 3 ], [ 1, 0.5, 0.25 ], [ 10, 20, 30, 40 ], [ 128, 255, 128, 128 ] ],
		[ [ 0, 0, 0 ], [ 0.05, 0.05, 0.05 ], [ 1, 2, 3, 4 ], [ 128, 128, 128, 128 ] ]
	];
	for ( const [ c, s, color, q ] of rows ) {

		c.forEach( ( v ) => w.f32( v ) );
		s.forEach( ( v ) => w.f32( v ) );
		color.forEach( ( v ) => w.u8( v ) );
		q.forEach( ( v ) => w.u8( v ) );

	}

	save( 'three.splat', w.buffer() );
	expected[ 'three.splat' ] = geometryJSON( new SPLATLoader().parse( w.buffer() ) );

}

// --- .ksplat ---------------------------------------------------------------

const KSPLAT_LEVELS = {
	0: { center: 12, scale: 12, rotation: 16, color: 4, sh: 4 },
	1: { center: 6, scale: 6, rotation: 8, color: 4, sh: 2 },
	2: { center: 6, scale: 6, rotation: 8, color: 4, sh: 1 }
};
const SH_COMPONENTS = [ 0, 9, 24, 45 ];

// Each section: { splats: [ { center, scale, rotation (w, x, y, z), color, sh } ],
// maxSplatCount, bucketSize, bucketBlockSize, buckets (centers), partial (lengths),
// fullBucketCount, scaleRange (0 for the default), degree }.
function ksplat( level, sections, { minSH = 0, maxSH = 0, maxSectionCount = sections.length } = {} ) {

	const L = KSPLAT_LEVELS[ level ];
	const w = new Writer();
	const total = sections.reduce( ( n, s ) => n + s.splats.length, 0 );
	w.u8( 0 ); w.u8( 1 ); w.u16( 0 );
	w.u32( maxSectionCount );
	w.u32( sections.length );
	w.u32( total );
	w.u32( total );
	w.u16( level );
	w.pad( 36 );
	w.f32( minSH ); w.f32( maxSH );
	w.pad( 4096 );
	for ( let i = 0; i < maxSectionCount; i ++ ) {

		const s = sections[ i ];
		const start = 4096 + i * 1024;
		w.pad( start );
		if ( s !== undefined ) {

			w.u32( s.splats.length );
			w.u32( s.maxSplatCount );
			w.u32( s.bucketSize || 0 );
			w.u32( ( s.buckets || [] ).length );
			w.f32( s.bucketBlockSize || 0 );
			w.u16( 12 );
			w.u16( 0 );
			w.u32( s.scaleRange || 0 );
			w.u32( 0 );
			w.u32( s.fullBucketCount || 0 );
			w.u32( ( s.partial || [] ).length );
			w.u16( s.degree );

		}

		w.pad( start + 1024 );

	}

	for ( const s of sections ) {

		const range = s.scaleRange || 32767;
		const factor = ( s.bucketBlockSize || 0 ) / 2 / range;
		for ( const length of s.partial || [] ) w.u32( length );
		for ( const b of s.buckets || [] ) b.forEach( ( v ) => w.f32( v ) );
		const perSplat = L.center + L.scale + L.rotation + L.color + SH_COMPONENTS[ s.degree ] * L.sh;
		const rowsStart = w.bytes.length;
		s.splats.forEach( ( p, index ) => {

			if ( L.center === 12 ) {

				p.center.forEach( ( v ) => w.f32( v ) );

			} else {

				// The stored value, relative to the splat's bucket.
				p.quantized.forEach( ( v ) => w.u16( v ) );

			}

			if ( L.scale === 12 ) p.scale.forEach( ( v ) => w.f32( v ) ); else p.scale.forEach( ( v ) => w.half( v ) );
			if ( L.rotation === 16 ) p.rotation.forEach( ( v ) => w.f32( v ) ); else p.rotation.forEach( ( v ) => w.half( v ) );
			p.color.forEach( ( v ) => w.u8( v ) );
			for ( let k = 0; k < SH_COMPONENTS[ s.degree ]; k ++ ) {

				const v = p.sh[ k ];
				if ( L.sh === 4 ) w.f32( v ); else if ( L.sh === 2 ) w.half( v ); else w.u8( v );

			}

			void index; void factor;

		} );
		w.pad( rowsStart + perSplat * s.maxSplatCount );

	}

	return w.buffer();

}

function shRamp( n, scale, offset = 0 ) {

	return Array.from( { length: n }, ( _, k ) => Math.sin( k * 1.7 + offset ) * scale );

}

{

	const buffer = ksplat( 0, [
		{
			maxSplatCount: 3,
			degree: 0,
			splats: [
				{ center: [ 1, 2, 3 ], scale: [ 0.5, 0.25, 0.125 ], rotation: [ 1, 0, 0, 0 ], color: [ 255, 0, 128, 255 ], sh: [] },
				{ center: [ - 1, 0.5, 2 ], scale: [ 0.1, 0.3, 0.2 ], rotation: [ 0.7, 0.1, - 0.2, 0.3 ], color: [ 5, 6, 7, 8 ], sh: [] }
			]
		},
		{
			maxSplatCount: 1,
			degree: 1,
			splats: [
				{ center: [ 0, - 2, 1 ], scale: [ 0.2, 0.2, 0.4 ], rotation: [ 0, 0, 1, 0 ], color: [ 90, 91, 92, 93 ], sh: shRamp( 9, 0.9 ).concat( [ 1.5 ] ).slice( 0, 9 ) }
			]
		}
	], { maxSectionCount: 3 } );
	save( 'level0.ksplat', buffer );
	expected[ 'level0.ksplat' ] = geometryJSON( new KSPLATLoader().parse( buffer ) );

}

{

	const splats = [];
	for ( let i = 0; i < 5; i ++ ) {

		splats.push( {
			quantized: [ 32767 + i * 1000, 32767 - i * 700, 30000 + i * 3 ],
			scale: [ 0.1 + i * 0.05, 0.2, 0.3 - i * 0.02 ],
			rotation: [ 0.9, 0.1 * i, - 0.05, 0.2 ],
			color: [ i * 40, 255 - i * 30, 17, 250 - i ],
			sh: shRamp( 24, 0.6, i )
		} );

	}

	const buffer = ksplat( 1, [ {
		maxSplatCount: 6,
		degree: 2,
		bucketSize: 2,
		bucketBlockSize: 4,
		buckets: [ [ 1, 2, 3 ], [ - 4, 5, - 6 ], [ 0.5, 0.25, 0.125 ] ],
		fullBucketCount: 1,
		partial: [ 2, 1 ],
		splats
	} ] );
	save( 'level1.ksplat', buffer );
	expected[ 'level1.ksplat' ] = geometryJSON( new KSPLATLoader().parse( buffer ) );

}

{

	const splats = [];
	for ( let i = 0; i < 2; i ++ ) {

		splats.push( {
			quantized: [ 100 + i, 65000 - i, 32767 ],
			scale: [ 0.3, 0.1 + i * 0.1, 0.05 ],
			rotation: [ 0.5, 0.5, 0.5, 0.5 - i ],
			color: [ 1, 2, 3, 4 + i ],
			sh: Array.from( { length: 45 }, ( _, k ) => ( k * 37 + i * 11 ) % 256 )
		} );

	}

	const buffer = ksplat( 2, [ {
		maxSplatCount: 2,
		degree: 3,
		bucketSize: 2,
		bucketBlockSize: 10,
		scaleRange: 1000,
		buckets: [ [ - 1, 0, 1 ] ],
		fullBucketCount: 1,
		splats
	} ], { minSH: - 2, maxSH: 2.5 } );
	save( 'level2.ksplat', buffer );
	expected[ 'level2.ksplat' ] = geometryJSON( new KSPLATLoader().parse( buffer ) );

	// The same file with no range in its header reads the default one.
	const bytes = new Uint8Array( buffer.slice( 0 ) );
	bytes.fill( 0, 36, 44 );
	save( 'level2_default_range.ksplat', bytes.buffer );
	expected[ 'level2_default_range.ksplat' ] = geometryJSON( new KSPLATLoader().parse( bytes.buffer ) );

}

// --- .spz ------------------------------------------------------------------

function int24( w, v, fractionalBits ) {

	const fixed = Math.round( v * ( 1 << fractionalBits ) );
	w.u8( fixed ); w.u8( fixed >> 8 ); w.u8( fixed >> 16 );

}

// splats: { center, alpha, color (3 bytes), scale (3 bytes), rotation (bytes, or a u32 for v3), sh (bytes) }
function spzRaw( version, shDegree, flags, fractionalBits, splats ) {

	const w = new Writer();
	w.u32( 0x5053474e ); w.u32( version ); w.u32( splats.length );
	w.u8( shDegree ); w.u8( fractionalBits ); w.u8( flags ); w.u8( 0 );
	for ( const s of splats ) {

		if ( version === 1 ) s.center.forEach( ( v ) => w.half( v ) ); else s.center.forEach( ( v ) => int24( w, v, fractionalBits ) );

	}

	for ( const s of splats ) w.u8( s.alpha );
	for ( const s of splats ) s.color.forEach( ( v ) => w.u8( v ) );
	for ( const s of splats ) s.scale.forEach( ( v ) => w.u8( v ) );
	for ( const s of splats ) {

		if ( version === 3 ) w.u32( s.rotation ); else s.rotation.forEach( ( v ) => w.u8( v ) );

	}

	for ( const s of splats ) s.sh.forEach( ( v ) => w.u8( v ) );
	if ( ( flags & 0x80 ) !== 0 ) for ( let i = 0; i < splats.length * 6; i ++ ) w.u8( i );
	return new Uint8Array( w.bytes );

}

const SPZ_VECTORS = [ 0, 3, 8, 15, 24 ];

function spzSH( degree, seed ) {

	return Array.from( { length: SPZ_VECTORS[ degree ] * 3 }, ( _, k ) => ( k * 29 + seed * 7 ) % 256 );

}

function quat3( largest, a, b, c ) {

	// a fills the low ten bits, c the high ten, each sign-magnitude.
	const code = ( v ) => ( v < 0 ? 512 : 0 ) | Math.round( Math.abs( v ) / Math.SQRT1_2 * 511 );
	return ( ( largest << 30 ) | ( code( c ) << 20 ) | ( code( b ) << 10 ) | code( a ) ) >>> 0;

}

async function spzCase( name, raw ) {

	const file = gzipSync( raw );
	save( name, file );
	expected[ name ] = geometryJSON( new SPZLoader().parse( file.buffer.slice( file.byteOffset, file.byteOffset + file.byteLength ) ) );

}

await spzCase( 'v1.spz', spzRaw( 1, 0, 0x80, 0, [
	{ center: [ 0.5, - 1.25, 3 ], alpha: 77, color: [ 0, 128, 255 ], scale: [ 100, 150, 200 ], rotation: [ 128, 64, 200 ], sh: [] }
] ) );

await spzCase( 'v2.spz', spzRaw( 2, 1, 0, 12, [
	{ center: [ 1.5, - 0.75, 2.25 ], alpha: 255, color: [ 10, 100, 250 ], scale: [ 140, 145, 150 ], rotation: [ 0, 255, 127 ], sh: spzSH( 1, 1 ) },
	{ center: [ - 3, 0.001, - 100 ], alpha: 3, color: [ 127, 128, 129 ], scale: [ 0, 255, 16 ], rotation: [ 255, 255, 255 ], sh: spzSH( 1, 2 ) }
] ) );

await spzCase( 'v3.spz', spzRaw( 3, 4, 0, 8, [
	{ center: [ 0.25, 0.5, 0.75 ], alpha: 10, color: [ 1, 2, 3 ], scale: [ 160, 150, 140 ], rotation: quat3( 0, 0.1, - 0.2, 0.3 ), sh: spzSH( 4, 1 ) },
	{ center: [ - 0.25, - 0.5, - 0.75 ], alpha: 20, color: [ 4, 5, 6 ], scale: [ 160, 150, 140 ], rotation: quat3( 1, - 0.4, 0.05, 0.6 ), sh: spzSH( 4, 2 ) },
	{ center: [ 8, 9, 10 ], alpha: 30, color: [ 7, 8, 9 ], scale: [ 160, 150, 140 ], rotation: quat3( 2, 0.7, 0.7, 0.7 ), sh: spzSH( 4, 3 ) },
	{ center: [ - 8, 0, 1 ], alpha: 40, color: [ 250, 251, 252 ], scale: [ 160, 150, 140 ], rotation: quat3( 3, 0, - 0.01, 0.2 ), sh: spzSH( 4, 4 ) }
] ) );

// v4: a raw header, a table of contents and one zstd frame per stream.
function zstdRaw( bytes ) {

	const w = new Writer();
	w.u32( 0xfd2fb528 );
	// Single segment, a four-byte content size.
	w.u8( 0x80 | 0x20 );
	w.u32( bytes.length );
	for ( let at = 0; at < bytes.length || at === 0; at += 1000 ) {

		const size = Math.min( 1000, bytes.length - at );
		const last = at + size >= bytes.length ? 1 : 0;
		const header = last | ( 0 << 1 ) | ( size << 3 );
		w.u8( header ); w.u8( header >> 8 ); w.u8( header >> 16 );
		for ( let k = 0; k < size; k ++ ) w.u8( bytes[ at + k ] );
		if ( size === 0 ) break;

	}

	return w.bytes;

}

{

	const splats = [
		{ center: [ 1, 2, 3 ], alpha: 200, color: [ 30, 60, 90 ], scale: [ 150, 160, 170 ], rotation: quat3( 3, 0.1, 0.1, 0.1 ), sh: spzSH( 1, 5 ) },
		{ center: [ - 1, - 2, - 3 ], alpha: 100, color: [ 200, 150, 100 ], scale: [ 120, 130, 140 ], rotation: quat3( 0, - 0.3, 0.2, 0.1 ), sh: spzSH( 1, 6 ) }
	];
	const fractionalBits = 10;
	const count = splats.length;
	const position = new Writer();
	for ( const s of splats ) s.center.forEach( ( v ) => int24( position, v, fractionalBits ) );
	const streams = [
		position.bytes,
		splats.map( ( s ) => s.alpha ),
		splats.flatMap( ( s ) => s.color ),
		splats.flatMap( ( s ) => s.scale ),
		( () => {

			const r = new Writer(); splats.forEach( ( s ) => r.u32( s.rotation ) ); return r.bytes;

		} )(),
		splats.flatMap( ( s ) => s.sh )
	].map( zstdRaw );
	const w = new Writer();
	const tocOffset = 32;
	w.u32( 0x5053474e ); w.u32( 4 ); w.u32( count );
	w.u8( 1 ); w.u8( fractionalBits ); w.u8( 0x02 ); w.u8( streams.length );
	w.u32( tocOffset );
	w.pad( tocOffset );
	for ( const s of streams ) {

		w.u32( s.length ); w.u32( 0 );
		w.u32( 0 ); w.u32( 0 );

	}

	for ( const s of streams ) s.forEach( ( v ) => w.u8( v ) );
	save( 'v4.spz', w.buffer() );
	expected[ 'v4.spz' ] = geometryJSON( await new SPZLoader().parse( w.buffer() ) );

}

// --- Gaussian splat PLY ----------------------------------------------------

{

	const names = [ 'x', 'y', 'z', 'nx', 'ny', 'nz', 'f_dc_0', 'f_dc_1', 'f_dc_2' ];
	for ( let i = 0; i < 9; i ++ ) names.push( `f_rest_${ i }` );
	names.push( 'opacity', 'scale_0', 'scale_1', 'scale_2', 'rot_0', 'rot_1', 'rot_2', 'rot_3' );
	const rows = [
		[ 0.5, 1.5, - 2, 0, 0, 0, 1.2, - 0.4, 0.05, ...shRamp( 9, 0.8 ), 2.5, - 2, - 1.5, - 3, 0.9, 0.1, - 0.3, 0.2 ],
		[ - 1, 0, 4, 0, 0, 0, - 3, 0, 5, ...shRamp( 9, 1.5, 2 ), - 1, - 0.5, - 0.5, - 0.5, 0, 0, 0, 1 ]
	];
	let header = 'ply\nformat binary_little_endian 1.0\ncomment made for ThreeMojo\n';
	header += `element vertex ${ rows.length }\n`;
	for ( const n of names ) header += `property float ${ n }\n`;
	header += 'end_header\n';
	const w = new Writer();
	for ( const c of header ) w.u8( c.charCodeAt( 0 ) );
	for ( const r of rows ) r.forEach( ( v ) => w.f32( v ) );
	save( 'splat.ply', w.buffer() );
	expected[ 'splat.ply' ] = geometryJSON( new GaussianSplatPLYLoader().parse( w.buffer() ) );

	const ascii = [
		'ply', 'format ascii 1.0', 'element vertex 1',
		'property float x', 'property float y', 'property float z',
		'property float scale_0', 'property float scale_1', 'property float scale_2',
		'property float rot_0', 'property float rot_1', 'property float rot_2', 'property float rot_3',
		'property float f_dc_0', 'property float f_dc_1', 'property float f_dc_2',
		'property float opacity',
		'element face 0', 'property list uchar int vertex_indices',
		'end_header',
		'0.25 -0.5 1 -1 -2 -3 0.5 0.5 0.5 0.5 0.1 0.2 0.3 0'
	].join( '\n' ) + '\n';
	save( 'ascii.ply', new TextEncoder().encode( ascii ).buffer );
	expected[ 'ascii.ply' ] = geometryJSON( new GaussianSplatPLYLoader().parse( ascii ) );

}

// --- glTF KHR_gaussian_splatting -------------------------------------------

{

	const w = new Writer();
	const views = [];
	const accessors = [];
	function view( floats, { component = 5126, type = 'VEC3', normalized = false, stride, count } ) {

		while ( w.bytes.length % 4 ) w.u8( 0 );
		const offset = w.bytes.length;
		for ( const v of floats ) {

			if ( component === 5126 ) w.f32( v );
			else if ( component === 5121 || component === 5120 ) w.u8( v );
			else w.u16( v );

		}

		views.push( { buffer: 0, byteOffset: offset, byteLength: w.bytes.length - offset, ...( stride ? { byteStride: stride } : {} ) } );
		accessors.push( { bufferView: views.length - 1, componentType: component, count, type, ...( normalized ? { normalized: true } : {} ) } );
		return accessors.length - 1;

	}

	function primitive( n, seed, { opacity = 'float', rotation = 'float', degree = 1 } = {} ) {

		const attributes = {};
		attributes.POSITION = view( Array.from( { length: n * 3 }, ( _, k ) => Math.cos( k + seed ) * 2 ), { count: n } );
		attributes[ 'KHR_gaussian_splatting:SCALE' ] = view( Array.from( { length: n * 3 }, ( _, k ) => 0.1 + ( ( k + seed ) % 5 ) * 0.05 ), { count: n } );
		if ( rotation === 'float' ) {

			attributes[ 'KHR_gaussian_splatting:ROTATION' ] = view( Array.from( { length: n * 4 }, ( _, k ) => [ 0.1, 0.2, 0.3, 0.9 ][ k % 4 ] * ( 1 + seed * 0.1 ) ), { type: 'VEC4', count: n } );

		} else {

			// A normalized signed short, with a byte stride wider than the element.
			const shorts = [];
			for ( let i = 0; i < n; i ++ ) shorts.push( ( 32767 * 0.5 ) | 0, 65536 - 16000, 1000, 30000, 0xabcd, 0xabcd );
			attributes[ 'KHR_gaussian_splatting:ROTATION' ] = view( shorts, { component: 5122, type: 'VEC4', normalized: true, stride: 12, count: n } );

		}

		if ( opacity === 'float' ) {

			attributes[ 'KHR_gaussian_splatting:OPACITY' ] = view( Array.from( { length: n }, ( _, k ) => 0.25 + k * 0.2 ), { type: 'SCALAR', count: n } );

		} else {

			attributes[ 'KHR_gaussian_splatting:OPACITY' ] = view( Array.from( { length: n }, ( _, k ) => 60 + k * 70 ), { component: 5121, type: 'SCALAR', normalized: true, count: n } );

		}

		attributes[ 'KHR_gaussian_splatting:SH_DEGREE_0_COEF_0' ] = view( Array.from( { length: n * 3 }, ( _, k ) => Math.sin( k * 0.9 + seed ) * 1.8 ), { count: n } );
		for ( let d = 1; d <= degree; d ++ ) {

			for ( let c = 0; c < 2 * d + 1; c ++ ) {

				attributes[ `KHR_gaussian_splatting:SH_DEGREE_${ d }_COEF_${ c }` ] = view( Array.from( { length: n * 3 }, ( _, k ) => Math.sin( k + c * 3 + d ) * 0.9 ), { count: n } );

			}

		}

		return {
			attributes,
			mode: 0,
			extensions: { KHR_gaussian_splatting: { kernel: 'ellipse', colorSpace: 'srgb_rec709_display', sortingMethod: 'cameraDistance', projection: 'perspective' } }
		};

	}

	const meshes = [
		{ name: 'splats', extras: { tag: 'a', count: 3 }, primitives: [ primitive( 3, 0, { degree: 1 } ) ] },
		{ primitives: [ { attributes: { POSITION: view( [ 0, 0, 0, 1, 0, 0, 0, 1, 0 ], { count: 3 } ) } } ] },
		{ name: 'twin pair', primitives: [ primitive( 2, 1, { opacity: 'byte', rotation: 'short', degree: 2 } ), primitive( 1, 2, { degree: 0 } ) ] },
		{ name: 'splats', primitives: [ primitive( 1, 3, { degree: 3 } ) ] }
	];
	const buffer = new Uint8Array( w.bytes );
	const json = {
		asset: { version: '2.0' },
		extensionsUsed: [ 'KHR_gaussian_splatting' ],
		buffers: [ { byteLength: buffer.length, uri: 'data:application/octet-stream;base64,' + Buffer.from( buffer ).toString( 'base64' ) } ],
		bufferViews: views,
		accessors,
		meshes,
		nodes: meshes.map( ( _, i ) => ( { mesh: i } ) ),
		scenes: [ { nodes: meshes.map( ( _, i ) => i ) } ],
		scene: 0
	};
	const text = JSON.stringify( json, null, 1 );
	writeFileSync( join( out, 'splats.gltf' ), text );

	// The same document with its buffer beside it, and in a .glb.
	writeFileSync( join( out, 'external.bin' ), buffer );
	writeFileSync( join( out, 'external.gltf' ), JSON.stringify( { ...json, buffers: [ { byteLength: buffer.length, uri: 'external.bin' } ] } ) );
	{

		const pad = ( bytes, fill ) => {

			const padded = new Uint8Array( Math.ceil( bytes.length / 4 ) * 4 ).fill( fill );
			padded.set( bytes );
			return padded;

		};

		const jsonChunk = pad( new TextEncoder().encode( JSON.stringify( { ...json, buffers: [ { byteLength: buffer.length } ] } ) ), 0x20 );
		const binChunk = pad( buffer, 0 );
		const total = 12 + 8 + jsonChunk.length + 8 + binChunk.length;
		const glb = new Writer();
		glb.u32( 0x46546c67 ); glb.u32( 2 ); glb.u32( total );
		glb.u32( jsonChunk.length ); glb.u32( 0x4e4f534a );
		jsonChunk.forEach( ( v ) => glb.u8( v ) );
		glb.u32( binChunk.length ); glb.u32( 0x004e4942 );
		binChunk.forEach( ( v ) => glb.u8( v ) );
		save( 'splats.glb', glb.buffer() );

	}
	const loader = new GLTFLoader();
	loader.register( ( parser ) => new GLTFGaussianSplatLoaderExtension( parser ) );
	const gltf = await loader.parseAsync( text, '' );
	const found = [];
	gltf.scene.traverse( ( object ) => {

		if ( object.isGaussianSplat ) {

			found.push( { name: object.name, parent: object.parent.isGroup ? object.parent.name : null, userData: object.userData.tag === undefined ? null : object.userData.tag, geometry: geometryJSON( object.splatGeometry ) } );

		}

	} );
	expected[ 'splats.gltf' ] = found;

}

// --- GaussianSplat: bounds, a raycast and the CPU sort ---------------------

{

	const geometry = new SPLATLoader().parse( ( () => {

		const w = new Writer();
		const rows = [
			[ [ 0, 0, 0 ], [ 0.2, 0.2, 0.2 ], 255 ],
			[ [ 1, 0.5, - 2 ], [ 0.5, 0.1, 0.3 ], 255 ],
			[ [ - 1.5, - 0.5, 1 ], [ 0.1, 0.4, 0.1 ], 30 ],
			[ [ 0.2, 0.1, 3 ], [ 0.3, 0.3, 0.05 ], 200 ]
		];
		for ( const [ c, s, a ] of rows ) {

			c.forEach( ( v ) => w.f32( v ) );
			s.forEach( ( v ) => w.f32( v ) );
			w.u8( 200 ); w.u8( 100 ); w.u8( 50 ); w.u8( a );
			[ 220, 150, 120, 100 ].forEach( ( v ) => w.u8( v ) );

		}

		save( 'four.splat', w.buffer() );
		return w.buffer();

	} )() );
	const mesh = new GaussianSplat( geometry );
	mesh.position.set( 0.5, - 0.25, 0.1 );
	mesh.rotation.set( 0.2, 0.4, - 0.1 );
	mesh.scale.set( 1.5, 1.5, 1.5 );
	mesh.updateMatrixWorld( true );
	mesh.computeBoundingSphere();
	const camera = new PerspectiveCamera( 50, 1.25, 0.5, 40 );
	camera.position.set( 1, 2, 9 );
	camera.lookAt( 0, 0, 0 );
	camera.updateMatrixWorld( true );
	const raycaster = new Raycaster( new Vector3( - 3, 0.2, 0 ), new Vector3( 1, 0, 0.05 ).normalize(), 0.1, 100 );
	const hits = [];
	mesh.raycast( raycaster, hits );
	mesh._needsSort( camera );
	mesh._updateSortUniforms( camera );
	mesh._sortCPU();
	expected.object = {
		file: 'four.splat',
		position: [ 0.5, - 0.25, 0.1 ],
		rotation: [ 0.2, 0.4, - 0.1 ],
		scale: 1.5,
		boundingBox: [ ...mesh.boundingBox.min.toArray(), ...mesh.boundingBox.max.toArray() ],
		boundingSphere: [ ...mesh.boundingSphere.center.toArray(), mesh.boundingSphere.radius ],
		camera: { fov: 50, aspect: 1.25, near: 0.5, far: 40, position: [ 1, 2, 9 ] },
		ray: { origin: [ - 3, 0.2, 0 ], direction: [ 1, 0, 0.05 ], near: 0.1, far: 100 },
		hits: hits.map( ( h ) => ( { distance: h.distance, point: h.point.toArray(), index: h.index } ) ),
		sortDepthRange: mesh._sortDepthRange.value.toArray(),
		order: Array.from( mesh._sort.orderAttribute.array )
	};

}

writeFileSync( join( out, 'expected.json' ), JSON.stringify( expected, null, 1 ) + '\n' );
