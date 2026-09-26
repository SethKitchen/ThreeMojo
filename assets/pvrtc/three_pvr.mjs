// Wraps the PVRTC payloads in this folder in PVR files, versions 3 and 2,
// and reads each with three.js 0.180's PVRLoader, into pvr.json. Run it
// where `three` is installed.
import { readFileSync, writeFileSync } from 'node:fs';
import { PVRLoader } from 'three/examples/jsm/loaders/PVRLoader.js';

const payload = ( name ) => readFileSync( name + '.bin' );

function v3( pixelFormat, width, height, faces, levels, data ) {
	const h = new Uint32Array( 13 );
	h[ 0 ] = 0x03525650; h[ 2 ] = pixelFormat;
	h[ 6 ] = height; h[ 7 ] = width; h[ 8 ] = 1; h[ 9 ] = 1; h[ 10 ] = faces; h[ 11 ] = levels;
	h[ 12 ] = 4; // four bytes of metadata, stepped over
	return Buffer.concat( [ Buffer.from( h.buffer ), Buffer.from( [ 9, 9, 9, 9 ] ), ...data ] );
}

function v2( width, height, levels, flags, alpha, surfaces, data ) {
	const h = new Uint32Array( 13 );
	h[ 0 ] = 52; h[ 1 ] = height; h[ 2 ] = width; h[ 3 ] = levels - 1; h[ 4 ] = flags;
	h[ 10 ] = alpha; h[ 11 ] = 0x21525650; h[ 12 ] = surfaces;
	return Buffer.concat( [ Buffer.from( h.buffer ), ...data ] );
}

const files = {
	'mips.pvr': v3( 3, 8, 8, 1, 2, [ payload( '4bpp_8x8' ), payload( '4bpp_4x4' ) ] ),
	'cube.pvr': v3( 2, 8, 8, 6, 1, Array.from( { length: 6 }, () => payload( '4bpp_8x8' ) ) ),
	'v2.pvr': v2( 16, 8, 1, 24, 0xff, 1, [ payload( '2bpp_16x8' ) ] ),
};

const reference = {};
for ( const [ name, file ] of Object.entries( files ) ) {
	writeFileSync( name, file );
	const buffer = file.buffer.slice( file.byteOffset, file.byteOffset + file.length );
	const pvr = new PVRLoader().parse( buffer, true );
	reference[ name ] = {
		width: pvr.width, height: pvr.height, format: pvr.format, mipmapCount: pvr.mipmapCount, isCubemap: pvr.isCubemap,
		mipmaps: pvr.mipmaps.map( ( m ) => ( { width: m.width, height: m.height, data: Array.from( m.data ) } ) ),
	};
}
writeFileSync( 'pvr.json', JSON.stringify( reference ) );
